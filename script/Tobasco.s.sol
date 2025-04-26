// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Tobasco} from "../src/Tobasco.sol";
import {OracleExample} from "../test/Tobasco.t.sol";

interface IOracleExample {
    function post(uint256 _price, uint256 _blockNumber) external;
}

contract OracleExampleScript is Script {
    // forge script script/Tobasco.s.sol:OracleExampleScript --sig "deploy()" --rpc-url 127.0.0.1:8545 --broadcast
    function deploy() public {
        vm.startBroadcast(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);
        address[] memory owners = new address[](1);
        owners[0] = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // account 0 in anvil
        OracleExample oracle = new OracleExample(owners, address(0), 1);
        vm.stopBroadcast();

        // write to file
        string memory filename = "oracle.txt";
        string memory content = vm.toString(address(oracle));
        vm.writeFile(filename, content);
    }

    // forge script script/Tobasco.s.sol:OracleExampleScript --sig "post()" --rpc-url 127.0.0.1:8545 --broadcast
    function post() public {
        string memory filename = "oracle.txt";
        string memory content = vm.readFile(filename);
        address _oracle = vm.parseAddress(content);

        vm.startBroadcast(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);
        IOracleExample(_oracle).post{gas: 30000000}(100, block.number); // note this isn't working properly
        vm.stopBroadcast();
    }

    // Simple transfer to consume ToB
    // forge script script/Tobasco.s.sol:OracleExampleScript --sig "spam()" --rpc-url 127.0.0.1:8545 --broadcast
    function spam() public {
        vm.startBroadcast(0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a);
        address payable recipient = payable(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
        recipient.call{value: 1 ether}("");
        console.log("sent");
        vm.stopBroadcast();
    }
}
