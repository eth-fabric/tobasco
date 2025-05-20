// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {MockURC, UnitTestHelper, TobascoTester} from "./Helpers.sol";
import {Tobasco} from "../src/Tobasco.sol";
import {ITobasco} from "../src/ITobasco.sol";
import {IBurn} from "../src/IBurn.sol";
import {Burn} from "../src/Burn.sol";
import {ISlasher} from "urc/src/ISlasher.sol";

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

    function test_CommitmentWasNotBroken() public {
        (ISlasher.SignedCommitment memory _signedCommitment, ISlasher.SignedDelegation memory _signedDelegation) =
        slashingInputs(
            SlashingInputs({
                timestamp: block.timestamp,
                commitmentCommitter: gateway,
                delegationCommitter: gateway,
                tobasco: address(tobasco),
                privateKey: gatewayKey,
                funcSelector: bytes4(keccak256("update(uint256,uint256)")),
                slasher: address(burn),
                commitmentType: commitmentType
            })
        );

        uint48 _commitmentTimestamp = uint48(block.timestamp);

        // Submit ToB transaction
        vm.prank(gateway);
        vm.expectEmit(true, true, true, true);
        emit ITobasco.TopOfBlockSubmitted(gateway, _commitmentTimestamp);
        tobasco.update{gas: block.gaslimit}(100, _commitmentTimestamp);
        assert(tobasco.foo() == 100);

        // Verify it was submitted
        vm.assertEq(tobasco.submitted(_commitmentTimestamp), true);
        vm.assertEq(tobasco.submittedBlockhash(_commitmentTimestamp), blockhash(block.number - 1));

        // Open a challenge
        vm.expectRevert(IBurn.CommitmentWasNotBroken.selector);
        burn.openChallenge(_signedDelegation.delegation, _signedCommitment.commitment);
    }
}
