// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Tobasco} from "../src/Tobasco.sol";
import {ITobasco} from "../src/ITobasco.sol";
import {TobascoTester} from "./Helpers.sol";

contract TobascoTest is Test {
    address alice = makeAddr("Alice");
    address bob = makeAddr("Bob");
    TobascoTester tobasco;

    function setUp() public {
        tobasco = new TobascoTester();
    }

    function sendN(uint256 n, address _to) internal {
        bool success;
        for (uint256 i = 0; i < n; i++) {
            assembly ("memory-safe") {
                success := call(gas(), _to, 1, 0, 0, 0, 0)
            }
        }
    }

    function test_TopOfBlockSubmitted() public {
        // hack to fix the gasleft() issue in foundry tests
        // When tobasco.gasLeft() is called, this will return the amount of gas left
        // in the block after initiating the call.
        tobasco.setGasLeftAmount(block.gaslimit - tobasco.getIntrinsicGasCost());

        tobasco.update{gas: block.gaslimit}(100, block.number);
        assert(tobasco.foo() == 100);
    }

    function test_BlockNumberMismatch() public {
        vm.expectRevert(ITobasco.BlockNumberMismatch.selector);
        tobasco.update(100, block.number + 1);
    }

    function test_NotTopOfBlock() public {
        vm.deal(alice, 1 ether);
        uint256 blockNumber = block.number;

        // fill the top of the block
        sendN(10, alice);

        // make sure its still the same block
        assert(block.number == blockNumber);

        vm.prank(alice);
        vm.expectRevert(ITobasco.NotTopOfBlock.selector);
        tobasco.update{gas: block.gaslimit}(100, block.number);

        require(tobasco.foo() == 0);
    }

    function test_IntrinsicGasCostTooLow() public {
        vm.expectRevert(ITobasco.IntrinsicGasCostTooLow.selector);
        tobasco.setIntrinsicGasCost(20000);
    }

    function test_IntrinsicGasCostUpdated() public {
        vm.expectEmit(true, true, true, true);
        emit ITobasco.IntrinsicGasCostUpdated(21000, 22000);
        tobasco.setIntrinsicGasCost(22000);
        assert(tobasco.getIntrinsicGasCost() == 22000);
    }
}
