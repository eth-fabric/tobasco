// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {MockURC, UnitTestHelper, TobascoTester} from "./Helpers.sol";
import {Tobasco} from "../src/Tobasco.sol";
import {ITobasco} from "../src/ITobasco.sol";
import {IBurn} from "../src/IBurn.sol";
import {Burn} from "../src/Burn.sol";
import {ISlasher} from "urc/src/ISlasher.sol";
import {IRegistry} from "urc/src/IRegistry.sol";

contract BurnTest is UnitTestHelper {
    uint256 slashAmountWei = 1 ether;
    uint64 commitmentType = 0xf17e; // "fire"
    uint256 challengeWindowSeconds = 120; // 10 blocks

    function setUp() public {
        (proposer, proposerKey) = makeAddrAndKey("proposer");
        (challenger, challengerKey) = makeAddrAndKey("challenger");
        (user, userKey) = makeAddrAndKey("user");
        (gateway, gatewayKey) = makeAddrAndKey("gateway");
        urc = new MockURC();
        tobasco = new TobascoTester();
        burn = new Burn(address(urc), address(tobasco), slashAmountWei, commitmentType, challengeWindowSeconds);

        // hack to fix the gasleft() issue in foundry tests
        // When tobasco.gasLeft() is called, this will return the amount of gas left
        // in the block after initiating the call.
        tobasco.setGasLeftAmount(block.gaslimit - tobasco.getIntrinsicGasCost());
    }

    function test_openChallenge() public {
        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                blockNumber: block.number,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(tobasco),
                privateKey: gatewayKey,
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(burn),
                commitmentType: commitmentType
            })
        );

        // Open a challenge
        bytes32 _challengeID = burn.openChallenge(_signedDelegation.delegation, _signedCommitment.commitment);
    }

    function test_CommitmentWasNotBroken() public {
        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                blockNumber: block.number,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(tobasco),
                privateKey: gatewayKey,
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(burn),
                commitmentType: commitmentType
            })
        );

        uint48 _commitmentBlockNumber = uint48(block.number);

        // Submit ToB transaction
        vm.prank(gateway);
        vm.expectEmit(true, true, true, true);
        emit ITobasco.TopOfBlockSubmitted(gateway);
        tobasco.update{gas: block.gaslimit}(100, _commitmentBlockNumber);
        assert(tobasco.foo() == 100);

        // Verify it was submitted
        vm.assertEq(tobasco.submitted(_commitmentBlockNumber), true);

        vm.expectRevert(IBurn.CommitmentWasNotBroken.selector);
        burn.openChallenge(_signedDelegation.delegation, _signedCommitment.commitment);
    }

    function test_InvalidDestination() public {
        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                blockNumber: block.number,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(0), // invalid destination
                privateKey: gatewayKey,
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(burn),
                commitmentType: commitmentType
            })
        );

        // Open a challenge
        vm.expectRevert(IBurn.InvalidDestination.selector);
        burn.openChallenge(_signedDelegation.delegation, _signedCommitment.commitment);
    }

    function test_WrongSlasher() public {
        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                blockNumber: block.number,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(tobasco),
                privateKey: gatewayKey,
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(0), // invalid slasher
                commitmentType: commitmentType
            })
        );

        // Open a challenge
        vm.expectRevert(IBurn.WrongSlasher.selector);
        burn.openChallenge(_signedDelegation.delegation, _signedCommitment.commitment);
    }

    function test_InvalidCommitmentType() public {
        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                blockNumber: block.number,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(tobasco),
                privateKey: gatewayKey,
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(burn),
                commitmentType: 0x1234 // invalid commitment type
            })
        );

        // Open a challenge
        vm.expectRevert(IBurn.InvalidCommitmentType.selector);
        burn.openChallenge(_signedDelegation.delegation, _signedCommitment.commitment);
    }

    function test_ChallengeAlreadyExists() public {
        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                blockNumber: block.number,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(tobasco),
                privateKey: gatewayKey,
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(burn),
                commitmentType: commitmentType
            })
        );

        // Open first challenge
        burn.openChallenge(_signedDelegation.delegation, _signedCommitment.commitment);

        // Try to open the same challenge again
        vm.expectRevert(IBurn.ChallengeAlreadyExists.selector);
        burn.openChallenge(_signedDelegation.delegation, _signedCommitment.commitment);
    }

    function test_attributeGatewayFault() public {
        uint256 blockNumber = block.number;

        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                blockNumber: blockNumber,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(tobasco),
                privateKey: gatewayKey,
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(burn),
                commitmentType: commitmentType
            })
        );

        // Open the challenge
        burn.openChallenge(_signedDelegation.delegation, _signedCommitment.commitment);

        // Advance past the block number so the blockhash is available
        vm.roll(blockNumber + 1);

        // Generate the blockhash signature
        // @dev note that the Gateway would have known the blockhash prior to publication as they were part of its construction
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(gatewayKey, blockhash(blockNumber));
        bytes memory _blockhashSignature = abi.encodePacked(r, s, v);

        // Attribute a fault
        burn.attributeGatewayFault(_signedDelegation.delegation, _signedCommitment, _blockhashSignature);
    }

    function test_WrongChallengeStatus() public {
        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                blockNumber: block.number,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(tobasco),
                privateKey: gatewayKey,
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(burn),
                commitmentType: commitmentType
            })
        );

        // Try to attribute a fault with a non-existent challenge
        vm.expectRevert(IBurn.WrongChallengeStatus.selector);
        burn.attributeGatewayFault(_signedDelegation.delegation, _signedCommitment, bytes(""));
    }

    function test_ChallengePeriodExpired() public {
        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                blockNumber: block.number,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(tobasco),
                privateKey: gatewayKey,
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(burn),
                commitmentType: commitmentType
            })
        );

        // Open the challenge
        burn.openChallenge(_signedDelegation.delegation, _signedCommitment.commitment);

        // Wait for the challenge period to expire
        vm.warp(block.timestamp + challengeWindowSeconds + 1);

        // Try to attribute a fault with a non-existent challenge
        vm.expectRevert(IBurn.ChallengePeriodExpired.selector);
        burn.attributeGatewayFault(_signedDelegation.delegation, _signedCommitment, bytes(""));
    }

    function test_InvalidSignature() public {
        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                blockNumber: block.number,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(tobasco),
                privateKey: 0x12345, // invalid private key
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(burn),
                commitmentType: commitmentType
            })
        );

        // Open the challenge
        burn.openChallenge(_signedDelegation.delegation, _signedCommitment.commitment);

        // Try to attribute a fault with a non-existent challenge
        vm.expectRevert(IBurn.InvalidSignature.selector);
        burn.attributeGatewayFault(
            _signedDelegation.delegation,
            _signedCommitment,
            bytes("") // invalid signature
        );
    }

    function test_markGatewaySlashable() public {
        uint256 blockNumber = block.number;

        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                blockNumber: blockNumber,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(tobasco),
                privateKey: gatewayKey,
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(burn),
                commitmentType: commitmentType
            })
        );

        // Open the challenge
        burn.openChallenge(_signedDelegation.delegation, _signedCommitment.commitment);

        // Advance past the block number so the blockhash is available
        vm.roll(blockNumber + 1);

        // Generate the blockhash signature
        // @dev note that the Gateway would have known the blockhash prior to publication as they were part of its construction
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(gatewayKey, blockhash(blockNumber));
        bytes memory _blockhashSignature = abi.encodePacked(r, s, v);

        // Attribute a fault
        burn.attributeGatewayFault(_signedDelegation.delegation, _signedCommitment, _blockhashSignature);

        // Wait for the challenge period to expire
        vm.warp(block.timestamp + challengeWindowSeconds + 1);

        // Compute the fault ID
        bytes32 _faultID = keccak256(abi.encode(_signedCommitment));

        // Mark the Gateway as slashable
        burn.markGatewaySlashable(_faultID);
        vm.assertEq(burn.gatewaySlashable(_faultID), true, "Gateway should be slashable");
    }

    function test_markGatewaySlashable_WrongChallengeStatus() public {
        vm.expectRevert(IBurn.WrongChallengeStatus.selector);
        burn.markGatewaySlashable(bytes32(0));
    }

    function test_markGatewaySlashable_ChallengePeriodNotExpired() public {
        uint256 blockNumber = block.number;

        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                blockNumber: blockNumber,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(tobasco),
                privateKey: gatewayKey,
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(burn),
                commitmentType: commitmentType
            })
        );

        // Open the challenge
        burn.openChallenge(_signedDelegation.delegation, _signedCommitment.commitment);

        // Advance past the block number so the blockhash is available
        vm.roll(blockNumber + 1);

        // Generate the blockhash signature
        // @dev note that the Gateway would have known the blockhash prior to publication as they were part of its construction
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(gatewayKey, blockhash(blockNumber));
        bytes memory _blockhashSignature = abi.encodePacked(r, s, v);

        // Attribute a fault
        burn.attributeGatewayFault(_signedDelegation.delegation, _signedCommitment, _blockhashSignature);

        // Compute the fault ID
        bytes32 _faultID = keccak256(abi.encode(_signedCommitment));

        vm.expectRevert(IBurn.ChallengePeriodNotExpired.selector);
        burn.markGatewaySlashable(_faultID);
    }

    function test_slash() public {
        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                blockNumber: block.number,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(tobasco),
                privateKey: gatewayKey,
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(burn),
                commitmentType: commitmentType
            })
        );

        // Open a challenge
        bytes32 _challengeID = burn.openChallenge(_signedDelegation.delegation, _signedCommitment.commitment);

        // Wait for the challenge period to expire
        vm.warp(block.timestamp + challengeWindowSeconds + 1);

        // Call the slash function on the URC
        IRegistry.RegistrationProof memory proof;
        uint256 _slashAmount = urc.slashCommitment(proof, _signedDelegation, _signedCommitment, bytes(""));

        assertEq(_slashAmount, slashAmountWei);

        IBurn.Challenge memory _challenge = burn.getChallenge(_challengeID);
        assert(_challenge.status == IBurn.Status.ProposerFault);
    }

    function test_slash_OnlyURC() public {
        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                blockNumber: block.number,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(tobasco),
                privateKey: gatewayKey,
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(burn),
                commitmentType: commitmentType
            })
        );

        vm.prank(user);

        vm.expectRevert(IBurn.OnlyURC.selector);
        burn.slash(_signedDelegation.delegation, _signedCommitment.commitment, address(0), bytes(""), address(0));
    }

    function test_slash_WrongChallengeStatus() public {
        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                blockNumber: block.number,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(tobasco),
                privateKey: gatewayKey,
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(burn),
                commitmentType: commitmentType
            })
        );

        IRegistry.RegistrationProof memory proof;

        // Call the slash function on the URC
        vm.expectRevert(IBurn.WrongChallengeStatus.selector);
        uint256 _slashAmount = urc.slashCommitment(proof, _signedDelegation, _signedCommitment, bytes(""));
    }

    function test_slash_ChallengePeriodNotExpired() public {
        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                blockNumber: block.number,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(tobasco),
                privateKey: gatewayKey,
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(burn),
                commitmentType: commitmentType
            })
        );

        // Open a challenge
        bytes32 _challengeID = burn.openChallenge(_signedDelegation.delegation, _signedCommitment.commitment);

        IRegistry.RegistrationProof memory proof;

        // Call the slash function on the URC
        vm.expectRevert(IBurn.ChallengePeriodNotExpired.selector);
        uint256 _slashAmount = urc.slashCommitment(proof, _signedDelegation, _signedCommitment, bytes(""));
    }
}
