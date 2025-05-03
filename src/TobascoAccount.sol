// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ITobascoAccount} from "./ITobascoAccount.sol";

contract TobascoAccount is ITobascoAccount {
    using ECDSA for bytes32;

    // State
    mapping(uint48 blockNumber => bool submitted) private submitted;
    address private urc;
    uint256 private slashAmountWei;
    uint256 private intrinsicGasCost;
    uint64 private commitmentType;
    uint256 private nonce;

    constructor(address _urc, uint256 _slashAmountWei, uint256 _intrinsicGasCost, uint64 _commitmentType) {
        urc = _urc;
        slashAmountWei = _slashAmountWei;
        intrinsicGasCost = _intrinsicGasCost;
        commitmentType = _commitmentType;
    }

    /**
     * @notice Executes a batch of calls using an off–chain signature.
     * @param calls An array of Call structs containing destination, ETH value, and calldata.
     * @param signature The ECDSA signature over the current nonce and the call data.
     *
     * The signature must be produced off–chain by signing:
     * The signing key should be the account’s key (which becomes the smart account’s own identity after upgrade).
     */
    function executeBatch(Call[] calldata calls, bytes calldata signature) external payable {
        // Compute the digest that the account was expected to sign.
        bytes memory encodedCalls;
        for (uint256 i = 0; i < calls.length; i++) {
            encodedCalls = abi.encodePacked(encodedCalls, calls[i].to, calls[i].value, calls[i].data);
        }
        bytes32 digest = keccak256(abi.encodePacked(nonce, encodedCalls));

        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(digest);

        // Recover the signer from the provided signature.
        address recovered = ECDSA.recover(ethSignedMessageHash, signature);
        require(recovered == address(this), "Invalid signature");

        _executeBatch(calls);
    }

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
    ) public view returns (uint256 slashAmountWei) {
        if (msg.sender != urc) revert OnlyURC();
        if (commitment.commitmentType != commitmentType) revert InvalidCommitmentType();

        // @dev The Preconfer committed to submitting a transaction to this contract at this block number
        (uint256 blockNumber, address destination) = abi.decode(commitment.payload, (uint256, address));

        // Slash is invalid if the destination is not this contract
        if (destination != commitment.slasher) revert InvalidDestination();

        // Slash is invalid if a transaction was submitted at this block number
        if (_wasSubmitted(uint48(blockNumber))) revert CommitmentWasNotBroken();

        // Return the slash amount to the URC slasher
        return slashAmountWei;
    }

    // @dev When creating the transaction you must set transaction.gasLimit = block.gaslimit
    // @dev Idea originally from https://x.com/Brechtpd/status/1854192593804177410
    modifier onlyTopOfBlock(uint256 expectedBlockNumber) {
        // Prevent replay attacks
        if (block.number != expectedBlockNumber) revert BlockNumberMismatch();

        // Check gas consumption to determine if it's a ToB transaction
        if (block.gaslimit - _gasleft() - intrinsicGasCost > 21000) revert NotTopOfBlock();

        // Mark the block as submitted
        _recordSubmission(uint48(block.number));
        _;
    }

    // external view functions
    function wasSubmitted(uint48 blockNumber) external view returns (bool) {
        return _wasSubmitted(blockNumber);
    }

    function getNonce() external view returns (uint256) {
        return nonce;
    }

    function getCommitmentType() external view returns (uint64) {
        return commitmentType;
    }

    function getIntrinsicGasCost() external view returns (uint256) {
        return intrinsicGasCost;
    }

    function getSlashAmountWei() external view returns (uint256) {
        return slashAmountWei;
    }

    function getUrc() external view returns (address) {
        return urc;
    }
    // internal functions

    function _executeBatch(Call[] calldata calls) internal {
        uint256 currentNonce = nonce;
        nonce++; // Increment nonce to protect against replay attacks

        for (uint256 i = 0; i < calls.length; i++) {
            _executeCall(calls[i]);
        }

        emit BatchExecuted(currentNonce, calls);
    }

    /**
     * @dev Internal function to execute a single call.
     * @param callItem The Call struct containing destination, value, and calldata.
     */
    function _executeCall(Call calldata callItem) internal {
        (bool success,) = callItem.to.call{value: callItem.value}(callItem.data);
        require(success, "Call reverted");
        emit CallExecuted(msg.sender, callItem.to, callItem.value, callItem.data);
    }

    function _recordSubmission(uint48 blockNumber) internal {
        submitted[blockNumber] = true;
    }

    function _wasSubmitted(uint48 blockNumber) internal view returns (bool) {
        return submitted[blockNumber];
    }

    function _updateIntrinsicGasCost(uint256 _intrinsicGasCost) internal {
        intrinsicGasCost = _intrinsicGasCost;
    }

    function _gasleft() internal virtual returns (uint256) {
        return gasleft(); // virtual to be overridden in tests
    }

    // Allow the contract to receive ETH
    fallback() external payable {}
    receive() external payable {}
}
//
