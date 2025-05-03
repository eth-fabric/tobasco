// SPDX-License-Identifier: MIT OR Apache-2.0
// pragma solidity >=0.8.0 <0.9.0;
pragma solidity ^0.8.13;

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
    address alice;
    uint256 alicePrivateKey;
    uint256 aliceInitialBalance;
    address bob;
    uint256 bobPrivateKey;
    uint256 bobInitialBalance;
    address urc;

    function setUp() public {
        urc = address(new MockURC());
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");
        aliceInitialBalance = 100 ether;
        bobInitialBalance = 100 ether;
        vm.deal(alice, aliceInitialBalance);
        vm.deal(bob, bobInitialBalance);

        // Create the TobascoAccount instance
        TobascoAccount _tobAccount = new TobascoAccount(urc, slashAmountWei, intrinsicGasCost, commitmentType);

        // Alice and Bob both use the TobascoAccount as their 7702 account
        vm.signAndAttachDelegation(address(_tobAccount), alicePrivateKey);
        vm.signAndAttachDelegation(address(_tobAccount), bobPrivateKey);
    }

    /**
     * @dev Helper function to create a commitment for testing
     * @param _blockNumber The block number for the inclusion commitment
     * @return _commitment The signed commitment structure
     */
    function commitment(uint256 _blockNumber, address _signer)
        public
        returns (ISlasher.SignedCommitment memory _commitment)
    {
        _commitment = ISlasher.SignedCommitment({
            commitment: ISlasher.Commitment({
                commitmentType: commitmentType,
                payload: abi.encode(_blockNumber, _signer),
                slasher: address(_signer)
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
        require(address(alice).code.length != 0);
        require(ITobascoAccount(address(alice)).wasSubmitted(uint48(block.number)) == false, "interface works");
    }

    /**
     * @dev Test basic ETH transfer functionality works despite 7702
     */
    function test_basicTransfer() public {
        vm.prank(alice);
        (bool success,) = bob.call{value: 1 ether}("");
        require(success, "transfer failed");
        assertEq(bob.balance, bobInitialBalance + 1 ether);
        assertEq(alice.balance, aliceInitialBalance - 1 ether);
    }

    /**
     * @dev Test batch ETH transfer functionality using executeBatchWithSig, submitted by a non-owner
     */
    function test_executeBatchWithSig() public {
        address dest1 = makeAddr("dest1");
        address dest2 = makeAddr("dest2");

        // Create two transfer calls
        ITobascoAccount.Call[] memory calls = new ITobascoAccount.Call[](2);
        calls[0] = ITobascoAccount.Call({to: dest1, value: 1 ether, data: ""});
        calls[1] = ITobascoAccount.Call({to: dest2, value: 1 ether, data: ""});

        // Encode and sign the batch
        bytes memory signature = signBatch(alicePrivateKey, calls, ITobascoAccount(address(alice)).getNonce());

        // Execute the batch
        vm.prank(bob); // not alice
        ITobascoAccount(address(alice)).executeBatchWithSig(calls, signature);

        // Verify balances
        assertEq(dest1.balance, 1 ether);
        assertEq(dest2.balance, 1 ether);
    }

    /**
     * @dev Test batch ETH transfers initiated by the owner
     */
    function test_executeBatch() public {
        // Alice pre-signs an ETH transfer to Bob
        address dest1 = makeAddr("dest1");
        address dest2 = makeAddr("dest2");
        ITobascoAccount.Call[] memory calls = new ITobascoAccount.Call[](2);
        calls[0] = ITobascoAccount.Call({to: dest1, value: 1 ether, data: ""});
        calls[1] = ITobascoAccount.Call({to: dest2, value: 1 ether, data: ""});

        // Alice submits the call
        vm.prank(alice);
        ITobascoAccount(address(alice)).executeBatch(calls);

        // Verify the transfer was executed
        assertEq(dest1.balance, 1 ether);
        assertEq(dest2.balance, 1 ether);
    }

    /**
     * @dev Assumes all accounts are TobascoAccounts allowing arbitrary delegation of calls
     * 1.
     */
    function test_nestedBatchExecuteWithSig() public {
        // Charlie is the end recipient of the eth transfers
        address charlie = makeAddr("charlie");

        // Bob pre-signs an ETH transfer to Charlie
        ITobascoAccount.Call[] memory subCalls = new ITobascoAccount.Call[](1);
        subCalls[0] = ITobascoAccount.Call({to: charlie, value: 1 ether, data: ""});
        bytes memory subSignature = signBatch(bobPrivateKey, subCalls, ITobascoAccount(address(bob)).getNonce());

        // Encode Bob's eth transfer as an executeBatch() call that will be executed in Alice's batch
        ITobascoAccount.Call[] memory calls = new ITobascoAccount.Call[](2);
        calls[0] = ITobascoAccount.Call({
            to: bob,
            value: 0,
            data: abi.encodeCall(ITobascoAccount.executeBatchWithSig, (subCalls, subSignature))
        });

        calls[1] = ITobascoAccount.Call({to: charlie, value: 1 ether, data: ""});

        // Execute the batch (no signature required since Alice is the submitter)
        vm.prank(alice);
        ITobascoAccount(address(alice)).executeBatch(calls);

        // Verify the transfer was executed
        assertEq(alice.balance, 99 ether);
        assertEq(bob.balance, 99 ether);
        assertEq(charlie.balance, 2 ether);
    }
}
