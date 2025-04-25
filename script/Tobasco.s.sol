// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Tobasco} from "../src/Tobasco.sol";

contract TobascoScript is Script {
    Tobasco public tobasco;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // todo

        vm.stopBroadcast();
    }
}
