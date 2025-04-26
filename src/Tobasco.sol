// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

import {ITobasco} from "./ITobasco.sol";

contract Tobasco is ITobasco {
    mapping(uint48 blockNumber => bool submitted) private submitted;
    mapping(address submitter => bool canSubmit) private submitters;
    address public urc;
    uint256 public SLASH_AMOUNT_WEI;
    uint256 public intrinsic_gas_cost;
    uint64 public commitmentType;

    constructor(
        address[] memory _owners,
        address _urc,
        uint256 _slashAmountWei,
        uint256 _intrinsic_gas_cost,
        uint64 _commitmentType
    ) {
        for (uint256 i = 0; i < _owners.length; i++) {
            _updateSubmitters(_owners[i], true);
        }
        urc = _urc;
        SLASH_AMOUNT_WEI = _slashAmountWei;
        intrinsic_gas_cost = _intrinsic_gas_cost;
        commitmentType = _commitmentType;
    }

    // Slasher function

    // @dev This function is assumed to be called by the URC
    // @dev The URC should have already checked:
    // @dev - that the committer signed the commitment
    // @dev - that the commitment.slasher is this contract
    function slash(
        Delegation calldata delegation,
        Commitment calldata commitment,
        address committer,
        bytes calldata evidence,
        address challenger
    ) external view returns (uint256 slashAmountWei) {
        if (msg.sender != urc) revert OnlyURC();
        if (commitment.commitmentType != commitmentType) revert InvalidCommitmentType();

        // @dev The Preconfer committed to submitting a transaction to this contract at this block number
        (uint256 blockNumber, address destination) = abi.decode(commitment.payload, (uint256, address));

        // Slash is invalid if the destination is not this contract
        if (destination != commitment.slasher) revert InvalidDestination();

        // Slash is invalid if a transaction was submitted at this block number
        if (_wasSubmitted(uint48(blockNumber))) revert CommitmentWasNotBroken();

        // Return the slash amount to the URC slasher
        slashAmountWei = SLASH_AMOUNT_WEI;
    }

    // Modifiers

    // @dev When creating the transaction you must set transaction.gasLimit = block.gaslimit
    // @dev Idea originally from https://x.com/Brechtpd/status/1854192593804177410
    modifier onlyTopOfBlock(uint256 expectedBlockNumber) {
        // Prevent replay attacks
        if (block.number != expectedBlockNumber) revert BlockNumberMismatch();

        // Check gas consumption to determine if it's a ToB transaction
        if (block.gaslimit - _gasleft() - intrinsic_gas_cost > 21000) revert NotTopOfBlock();

        // Mark the block as submitted
        _recordSubmission(uint48(block.number));
        _;
    }

    // @dev Only whitelisted can submit transactions
    // @dev It is up to the contract inheriting from this to implement the whitelist
    // @dev and use this modifier to filter ToB submissions
    modifier onlySubmitter() {
        if (!_canSubmit(msg.sender)) revert NotSubmitter();
        _;
    }

    // external view functions
    function wasSubmitted(uint48 blockNumber) external view returns (bool) {
        return _wasSubmitted(blockNumber);
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

    function _updateIntrinsicGasCost(uint256 _intrinsic_gas_cost) internal {
        intrinsic_gas_cost = _intrinsic_gas_cost;
    }

    // internal view functions
    function _wasSubmitted(uint48 blockNumber) internal view returns (bool) {
        return submitted[blockNumber];
    }

    function _canSubmit(address submitter) internal view returns (bool) {
        return submitters[submitter];
    }

    function _gasleft() internal virtual returns (uint256) {
        return gasleft(); // virtual to be overridden in tests
    }
}
