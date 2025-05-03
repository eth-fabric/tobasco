// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {ITobascoAccount} from "../src/ITobascoAccount.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface IMock7702Account {
    function getNonce() external view returns (uint256);
    function conditionalExecuteCall(ITobascoAccount.Call calldata call, bytes calldata signature) external;
}

/**
 * @title Mock7702Account
 * @dev Mock implementation of a 7702-compliant account for testing
 * Simulates the conditional execution of calls with signature verification
 * This is a simplified version of the 7702 account that only supports conditional execution
 * and does not include the full account functionality.
 * The idea is that if the account owner has pre-signed a Call with their ECDSA key,
 * then anyone can submit it on their behalf using the conditionalExecuteCall function.
 */
contract Mock7702Account {
    uint256 public nonce;

    /**
     * @dev Executes a call if the provided signature is valid
     * @param call The call to execute
     * @param signature The signature authorizing the call
     */
    function conditionalExecuteCall(ITobascoAccount.Call calldata call, bytes calldata signature) external {
        // Verify the call was signed by this account using the current nonce
        bytes32 digest = keccak256(abi.encodePacked(nonce, call.to, call.value, call.data));
        address recovered = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(digest), signature);
        require(recovered == address(this), "Invalid signature");

        _executeCall(call);
    }

    function getNonce() external view returns (uint256) {
        return nonce;
    }

    /**
     * @dev Internal function to execute a call and increment the nonce
     * @param callItem The call to execute
     */
    function _executeCall(ITobascoAccount.Call calldata callItem) internal {
        nonce++;
        (bool success,) = callItem.to.call{value: callItem.value}(callItem.data);
        require(success, "Call reverted");
        emit ITobascoAccount.CallExecuted(msg.sender, callItem.to, callItem.value, callItem.data);
    }
}
