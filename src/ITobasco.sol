// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface ITobasco {
    // External functions
    function setIntrinsicGasCost(uint256 _intrinsicGasCost) external;

    // External view functions
    function submitted(uint48 _blockNumber) external view returns (bool);
    function getIntrinsicGasCost() external view returns (uint256);

    // Events
    event IntrinsicGasCostUpdated(uint256 oldIntrinsicGasCost, uint256 newIntrinsicGasCost);
    event TopOfBlockSubmitted(address indexed submitter);

    // Errors
    error NotTopOfBlock();
    error BlockTimestampMismatch();
    error IntrinsicGasCostTooLow();
}
