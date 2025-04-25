// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

import {ITabasco} from "./ITabasco.sol";

contract Tobasco is ITabasco {
    mapping(uint48 blockNumber => bool submitted) private submitted;
    mapping(address submitter => bool canSubmit) private submitters;
    address public urc;
    uint256 public slashAmountWei;

    constructor(address[] memory _owners, address _urc, uint256 _slashAmountWei) {
        for (uint256 i = 0; i < _owners.length; i++) {
            _updateSubmitters(_owners[i], true);
        }
        urc = _urc;
        slashAmountWei = _slashAmountWei;
    }

    // Slasher function
    function slash(
        Delegation calldata delegation,
        Commitment calldata commitment,
        address committer,
        bytes calldata evidence,
        address challenger
    ) external returns (uint256 slashAmountWei) {
        // todo
    }

    // Modifiers
    modifier onlyTopOfBlock(uint256 expectedBlockNumber) {
        // Prevent replay attacks
        require(block.number == expectedBlockNumber, "TopOfBlock: block number mismatch");

        // Check gas consumption to determine if it's a ToB transaction
        // todo

        // Mark the block as submitted
        _recordSubmission(uint48(block.number));
        _;
    }

    modifier onlySubmitter() {
        require(_canSubmit(msg.sender), "Tobasco: caller is not a submitter");
        _;
    }

    // external view functions
    function wasSubmitted(uint48 blockNumber) external view returns (bool) {
        return submitted[blockNumber];
    }

    function canSubmit(address submitter) external view returns (bool) {
        return _canSubmit(submitter);
    }

    // internal mutator functions
    function _updateSubmitters(address _submitter, bool _isSubmitter) internal {
        submitters[_submitter] = _isSubmitter;
    }

    function _recordSubmission(uint48 blockNumber) internal {
        submitted[blockNumber] = true;
    }

    // internal view functions
    function _canSubmit(address submitter) internal view returns (bool) {
        return submitters[submitter];
    }
}
