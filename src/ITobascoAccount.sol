// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {ISlasher} from "urc/src/ISlasher.sol";

interface ITobascoAccount is ISlasher {
    /// @notice Represents a single call within a batch.
    struct Call {
        address to;
        uint256 value;
        bytes data;
    }

    // External functions
    function executeBatchWithSig(Call[] calldata calls, bytes calldata signature) external;
    function executeBatch(Call[] calldata calls) external;
    function executeBatchWithSigToB(Call[] calldata calls, bytes calldata signature) external;
    function executeBatchToB(Call[] calldata calls) external;
    function wasSubmitted(uint48 blockNumber) external view returns (bool);
    function getNonce() external view returns (uint256);
    function getCommitmentType() external view returns (uint64);
    function getIntrinsicGasCost() external view returns (uint256);
    function getSlashAmountWei() external view returns (uint256);
    function getUrc() external view returns (address);

    /// @notice Emitted for every individual call executed.
    event CallExecuted(address indexed sender, address indexed to, uint256 value, bytes data);
    /// @notice Emitted when a full batch is executed.
    event BatchExecuted(uint256 indexed nonce, Call[] calls);

    // Errors
    error CommitmentWasNotBroken();
    error OnlyURC();
    error InvalidCommitmentType();
    error InvalidDestination();
    error NotOwner();
    error NotTopOfBlock();
    error BlockNumberMismatch();
}
