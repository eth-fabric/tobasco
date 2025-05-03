// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

import {Test, console} from "forge-std/Test.sol";

import {TobascoAccount} from "../src/TobascoAccount.sol";
import {ITobascoAccount} from "../src/ITobascoAccount.sol";
import {MockURC} from "./MockURC.sol";
import {Mock7702Account, IMock7702Account} from "./Mock7702Account.sol";
import {IRegistry} from "urc/src/IRegistry.sol";
import {ISlasher} from "urc/src/ISlasher.sol";

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title TobascoAccountTest
 * @dev Test contract for TobascoAccount functionality
 * Tests various scenarios including basic transfers, batch transfers, and conditional execution
 */
contract TobascoAccountTest is Test {
    // Test configuration constants
    uint64 public commitmentType = 1;
    uint256 public slashAmountWei = 1 ether;
    uint256 public intrinsicGasCost = 21000;

    // Test state variables
    address signer;
    uint256 signerPrivateKey;
    address urc;

    function setUp() public {
        urc = address(new MockURC());
        (signer, signerPrivateKey) = makeAddrAndKey("Signer");
        TobascoAccount _tobAccount = new TobascoAccount(urc, slashAmountWei, intrinsicGasCost, commitmentType);

        vm.signAndAttachDelegation(address(_tobAccount), signerPrivateKey);
        vm.deal(signer, 100 ether);
    }

    /**
     * @dev Helper function to create a commitment for testing
     * @param _blockNumber The block number for the inclusion commitment
     * @return commitment The signed commitment structure
     */
    function commitment(uint256 _blockNumber) public returns (ISlasher.SignedCommitment memory commitment) {
        commitment = ISlasher.SignedCommitment({
            commitment: ISlasher.Commitment({
                commitmentType: commitmentType,
                payload: abi.encode(_blockNumber, signer),
                slasher: address(signer)
            }),
            signature: bytes("")
        });
    }

    /**
     * @dev Helper function to encode multiple calls into a single bytes array
     * @param calls Array of calls to encode
     * @return Encoded bytes representation of the calls
     */
    function encodeCalls(ITobascoAccount.Call[] memory calls) internal returns (bytes memory) {
        bytes memory encodedCalls = "";
        for (uint256 i = 0; i < calls.length; i++) {
            encodedCalls = abi.encodePacked(encodedCalls, calls[i].to, calls[i].value, calls[i].data);
        }
        return encodedCalls;
    }

    /**
     * @dev Helper function to sign a batch of calls
     * @param privateKey The private key of the signer
     * @param calls The calls to sign
     * @param nonce The nonce of the signer
     * @return signature The signed batch of calls
     */
    function signBatch(uint256 privateKey, ITobascoAccount.Call[] memory calls, uint256 nonce)
        internal
        returns (bytes memory signature)
    {
        bytes memory encodedCalls = encodeCalls(calls);
        bytes32 digest = keccak256(abi.encodePacked(nonce, encodedCalls));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, MessageHashUtils.toEthSignedMessageHash(digest));
        signature = abi.encodePacked(r, s, v);
    }

    /**
     * @dev Test basic contract deployment with 7702
     */
    function test_deploy() public {
        require(address(signer).code.length != 0);
        require(ITobascoAccount(address(signer)).wasSubmitted(uint48(block.number)) == false, "interface works");
    }

    /**
     * @dev Test basic ETH transfer functionality works despite 7702
     */
    function test_basicTransfer() public {
        address payable to = payable(makeAddr("to"));
        vm.prank(signer);
        to.call{value: 1 ether}("");
        assertEq(to.balance, 1 ether);
    }

    /**
     * @dev Test batch ETH transfer functionality using executeBatch
     */
    function test_basicBatchEthTransfer() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        // Create two transfer calls
        ITobascoAccount.Call[] memory calls = new ITobascoAccount.Call[](2);
        calls[0] = ITobascoAccount.Call({to: alice, value: 1 ether, data: ""});
        calls[1] = ITobascoAccount.Call({to: bob, value: 1 ether, data: ""});

        // Encode and sign the batch
        bytes memory signature = signBatch(signerPrivateKey, calls, ITobascoAccount(address(signer)).getNonce());

        // Execute the batch
        vm.prank(bob);
        ITobascoAccount(address(signer)).executeBatch(calls, signature);

        // Verify balances
        assertEq(alice.balance, 1 ether);
        assertEq(bob.balance, 1 ether);
    }

    /**
     * @dev Test conditional execution of a single call through a 7702-compliant account
     */
    function test_conditionalExecuteCall() public {
        // Setup Alice's smart account
        (address alice, uint256 alicePrivateKey) = makeAddrAndKey("alice");
        vm.deal(alice, 100 ether);
        Mock7702Account mock7702Account = new Mock7702Account();
        vm.signAndAttachDelegation(address(mock7702Account), alicePrivateKey);

        // Alice pre-signs an ETH transfer to Bob
        address bob = makeAddr("bob");
        ITobascoAccount.Call[] memory calls = new ITobascoAccount.Call[](1);
        calls[0] = ITobascoAccount.Call({to: bob, value: 1 ether, data: ""});
        bytes memory signature = signBatch(alicePrivateKey, calls, IMock7702Account(address(alice)).getNonce());

        // Bob submits the call on behalf of Alice
        vm.prank(bob);
        IMock7702Account(address(alice)).conditionalExecuteCall(calls[0], signature);

        // Verify the transfer was executed
        assertEq(bob.balance, 1 ether);
    }

    /**
     * @dev Test conditional execution of calls through a 7702-compliant account
     * This test verifies that a user's pre-signed transaction can be included in a batch
     * and executed conditionally based on signature verification
     */
    function test_BatchedConditionalExecuteCall() public {
        // Bob is the end recipient
        address bob = makeAddr("bob");

        // Setup Alice's smart account
        (address alice, uint256 alicePrivateKey) = makeAddrAndKey("alice");
        vm.deal(alice, 100 ether);
        Mock7702Account mock7702Account = new Mock7702Account();
        vm.signAndAttachDelegation(address(mock7702Account), alicePrivateKey);

        // Alice pre-signs an ETH transfer to Bob
        ITobascoAccount.Call[] memory subCalls = new ITobascoAccount.Call[](1);
        subCalls[0] = ITobascoAccount.Call({to: bob, value: 1 ether, data: ""});
        bytes memory subSignature = signBatch(alicePrivateKey, subCalls, IMock7702Account(address(alice)).getNonce());

        // Create a batch call that includes Alice's pre-signed transaction
        ITobascoAccount.Call[] memory calls = new ITobascoAccount.Call[](1);
        calls[0] = ITobascoAccount.Call({
            to: alice,
            value: 0,
            data: abi.encodeCall(Mock7702Account.conditionalExecuteCall, (subCalls[0], subSignature))
        });

        // Sign and execute the batch
        bytes memory signature = signBatch(signerPrivateKey, calls, ITobascoAccount(address(signer)).getNonce());

        vm.prank(bob);
        ITobascoAccount(address(signer)).executeBatch(calls, signature);

        // Verify the transfer was executed
        assertEq(alice.balance, 99 ether);
        assertEq(bob.balance, 1 ether);
    }
}
