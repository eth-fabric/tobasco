// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

import {ITobasco} from "./ITobasco.sol";

contract Tobasco is ITobasco {
    // @dev A mapping that saves the block number whenever the transaction was submitted at ToB
    mapping(uint48 blockNumber => bool submitted) private _submitted;

    // @dev The default intrinsic gas cost of an L1 transaction
    // @dev We omit setting this in a constructor as EIP-7702 accounts don't run init code
    // @dev Note that for EIP-7702, the intrinsic gas cost is > 21000
    uint256 private _intrinsicGasCost = 21000;

    function setIntrinsicGasCost(uint256 intrinsicGasCost_) external {
        if (intrinsicGasCost_ < 21000) revert IntrinsicGasCostTooLow();
        emit IntrinsicGasCostUpdated(_intrinsicGasCost, intrinsicGasCost_);
        _intrinsicGasCost = intrinsicGasCost_;
    }

    // @dev When creating the transaction you must set transaction.gasLimit = block.gaslimit
    // @dev Idea originally from https://x.com/Brechtpd/status/1854192593804177410
    modifier onlyTopOfBlock(uint256 _expectedTimestamp) {
        // Prevent replay attacks
        if (block.timestamp != _expectedTimestamp) revert BlockTimestampMismatch();

        // Check gas consumption to determine if it's a ToB transaction
        if (block.gaslimit - _gasleft() - _intrinsicGasCost > 21000) revert NotTopOfBlock();

        // Mark the block as submitted
        _recordSubmission(uint48(block.number));
        _;
    }

    // external view functions
    function submitted(uint48 _blockNumber) external view returns (bool) {
        return _submitted[_blockNumber];
    }

    function getIntrinsicGasCost() external view returns (uint256) {
        return _intrinsicGasCost;
    }

    // internal mutator functions
    function _recordSubmission(uint48 _blockNumber) internal {
        _submitted[_blockNumber] = true;
        emit TopOfBlockSubmitted(msg.sender);
    }

    // @dev This function is virtual to be overridden in tests
    function _gasleft() internal virtual returns (uint256) {
        return gasleft();
    }
}
