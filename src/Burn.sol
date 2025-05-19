// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

import {IBurn} from "./IBurn.sol";
import {ITobasco} from "./ITobasco.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {RLPReader} from "./lib/rlp/RLPReader.sol";
import {MerkleTrie} from "./lib/trie/MerkleTrie.sol";
import {RLPWriter} from "./lib/rlp/RLPWriter.sol";
import {TransactionDecoder} from "./lib/TransactionDecoder.sol";

contract Burn is IBurn {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;

    // Challenges
    mapping(bytes32 challengeID => Challenge challenge) private challenges;
    // Gateway faults
    mapping(bytes32 challengeID => GatewayFault fault) private faults;

    // Private variables
    address private _urc;
    address private _tobasco;
    uint256 private _slashAmountWei;
    uint64 private _commitmentType;
    uint256 private _challengeWindowSeconds;
    uint256 private constant BLOCKHASH_EVM_LOOKBACK = 256;

    constructor(
        address urc_,
        address tobasco_,
        uint256 slashAmountWei_,
        uint64 commitmentType_,
        uint256 challengeWindowSeconds_
    ) {
        _urc = urc_;
        _tobasco = tobasco_;
        _slashAmountWei = slashAmountWei_;
        _commitmentType = commitmentType_;
        _challengeWindowSeconds = challengeWindowSeconds_;
    }

    // @dev This function is assumed to be called by the URC to slash the Proposer.
    // @dev It will only succeed if a challenge exists and the challenge period has expired.
    // @dev The URC should have already checked that the `committer` signed the `commitment`
    // @dev and the `_delegation.committer` signed the `_commitment.commitment`.
    function slash(
        Delegation calldata _delegation,
        Commitment calldata _commitment,
        address _committer,
        bytes calldata _evidence,
        address _challenger
    ) external returns (uint256) {
        // Only the URC can call this function
        if (msg.sender != _urc) revert OnlyURC();

        bytes32 _challengeID = _computeChallengeID(_delegation, _commitment);

        // Can only slash if the challenge is still unresolved
        if (challenges[_challengeID].status != Status.Unresolved) {
            revert WrongChallengeStatus();
        }

        // Verify the challenge period expired
        if (block.timestamp - challenges[_challengeID].timestamp < _challengeWindowSeconds) {
            revert ChallengePeriodNotExpired();
        }

        // Update the challenge status to ProposerFault to prevent replays
        challenges[_challengeID].status = Status.ProposerFault;

        // Return the slash amount to the URC slasher
        return _slashAmountWei;
    }

    // @dev This function is called to challenge a Proposer failed to submit a transaction at the specified timestamp at ToB.
    // @dev This function does not check _delegation or _commitment signatures as this is handled in the `attributeGatewayFault` function or `slash()` function if the challenge is valid.
    // @dev If someone tries to grief by calling this function with an invalid _delegation or _commitment, the challenges can be ignored as they are unenforceable by `slash()` or `attributeGatewayFault()`
    function openChallenge(Delegation calldata _delegation, Commitment calldata _commitment)
        external
        returns (bytes32 _challengeID)
    {
        // Decode the commitment payload
        ToBCommitment memory toBCommitment = abi.decode(_commitment.payload, (ToBCommitment));

        // Slashing is only possible if the transaction was not submitted at the specified timestamp
        if (_wasSubmitted(toBCommitment.timestamp)) {
            revert CommitmentWasNotBroken();
        }

        // Verify the ToB destination address was the expected Tobasco contract
        if (toBCommitment.tobasco != _tobasco) revert InvalidDestination();

        // Verify the commitment.slasher is this contract
        if (_commitment.slasher != address(this)) revert WrongSlasher();

        // Verify the commitment type matches this contract's
        if (_commitment.commitmentType != _commitmentType) {
            revert InvalidCommitmentType();
        }

        // Compute the challenge ID
        _challengeID = _computeChallengeID(_delegation, _commitment);

        // Check if the challenge already exists
        if (challenges[_challengeID].status != Status.Nonexistent) {
            revert ChallengeAlreadyExists();
        }

        // The challenge is valid -> log the challenge to start the challenge window
        challenges[_challengeID] = Challenge({timestamp: uint48(block.timestamp), status: Status.Unresolved});

        emit ChallengeOpened(_challengeID);
    }

    // @dev Called to vindicate a Proposer and attribute the fault to a Gateway.
    // @dev It is assumed that the Gateway signs the blockhash with their `committer` private key
    // @dev before an L1 Proposer proposes the L1 block. If the Proposer can supply the signed blockhash
    // @dev then the Gateway attested to an incorrect block and is responsible for the fault.
    // @dev This function tentatively attributes the fault to the Gateway since there is still the possibility
    // @dev that the transaction executed at ToB but simply reverted due to user error.
    // @dev The function saves the faultId using only the `SignedCommitment` to prevent someone replaying the fault
    // @dev with falsified `Delegation` messages.
    function attributeGatewayFault(
        Delegation calldata _delegation,
        SignedCommitment calldata _commitment,
        bytes calldata _blockhashSignature
    ) external {
        address _gateway = _delegation.committer;

        // Recompute the challenge ID
        bytes32 _challengeID = _computeChallengeID(_delegation, _commitment.commitment);

        // The challenge must exist
        if (challenges[_challengeID].status != Status.Unresolved) {
            revert WrongChallengeStatus();
        }

        // The challenge must have been created within the challenge window
        if (block.timestamp - challenges[_challengeID].timestamp > _challengeWindowSeconds) {
            revert ChallengePeriodExpired();
        }

        // Verify the Gateway signed the blockhash and the commitment
        // This provides evidence that the Gateway attested to the block's correctness
        // and therefore is the party at fault
        if (!_verifyGatewaySignatures(_gateway, _commitment, _blockhashSignature)) revert InvalidSignature();

        // Close the challenge from the Proposer's perspective
        challenges[_challengeID].status = Status.GatewayFault;

        bytes32 _faultID = _computeFaultID(_commitment);

        // Mark the Gateway as the tentatively guilty party
        faults[_faultID] = GatewayFault({
            gateway: _gateway,
            timestamp: uint48(block.timestamp),
            challengeID: _challengeID,
            status: Status.Unresolved
        });

        emit GatewayFaultProven(_faultID, _challengeID, _gateway);
    }

    // @dev Callable if `attributeGatewayFault()` has been called and the challenge period has expired.
    // @dev This implies they could not supply evidence that the transaction executed at ToB but simply reverted.
    // @dev This contract does not assume the Gateway is registered in the URC, Rather it simply sets the
    // @dev GatewayFault.status to `GatewayFault` that can be queried by an external contract where the Gateway
    // @dev is collateralized.
    function markGatewaySlashable(bytes32 _faultID) external {
        if (faults[_faultID].status != Status.Unresolved) {
            revert WrongChallengeStatus();
        }

        // The challenge window must have expired to mark them slashable
        if (block.timestamp - faults[_faultID].timestamp < _challengeWindowSeconds) revert ChallengePeriodNotExpired();

        faults[_faultID].status = Status.GatewayFault;
    }

    // @dev Called by the Gateway to vindicate themselves and set the GatewayFault.status to `Vindicated`.
    // @dev This scenario is possible if the Gateway did execute the transaction at ToB but it reverted due to user error.
    // @dev This function is callable after a successful call to `attributeGatewayFault()` if the challenge period has expired.
    // @dev This function will verify that a transaction to the expected ToB contract executed at the ToB.
    function vindicateGateway(SignedCommitment calldata _commitment, InclusionProof calldata _inclusionProof)
        external
    {
        bytes32 _faultID = _computeFaultID(_commitment);
        GatewayFault memory _fault = faults[_faultID];

        // The GatewayFault must exist and be unresolved
        if (_fault.status != Status.Unresolved) revert WrongChallengeStatus();

        // The challenge window must still be active
        if (block.timestamp - faults[_faultID].timestamp > _challengeWindowSeconds) revert ChallengePeriodExpired();

        // Decode the commitment payload
        ToBCommitment memory _toBCommitment = abi.decode(_commitment.commitment.payload, (ToBCommitment));

        // Verify the inclusion proof
        if (!_verifyInclusionProof(_inclusionProof, _toBCommitment)) {
            revert InclusionProofInvalid();
        }

        // Vindicate the Gateway
        faults[_faultID].status = Status.Vindicated;
    }

    // External view functions
    function gatewaySlashable(bytes32 _faultID) external view returns (bool) {
        return faults[_faultID].status == Status.GatewayFault;
    }

    function getFault(bytes32 _faultID) external view returns (GatewayFault memory) {
        return faults[_faultID];
    }

    function getChallenge(bytes32 _challengeID) external view returns (Challenge memory) {
        return challenges[_challengeID];
    }

    function urc() external view returns (address) {
        return _urc;
    }

    function tobasco() external view returns (address) {
        return _tobasco;
    }

    function slashAmountWei() external view returns (uint256) {
        return _slashAmountWei;
    }

    function commitmentType() external view returns (uint64) {
        return _commitmentType;
    }

    function challengeWindowSeconds() external view returns (uint256) {
        return _challengeWindowSeconds;
    }

    // Internal functions
    function _verifyGatewaySignatures(
        address _gateway,
        SignedCommitment calldata _commitment,
        bytes calldata _signature
    ) internal view returns (bool) {
        // Verify the Gateway signed the commitment
        address _recovered = ECDSA.recover(keccak256(abi.encode(_commitment.commitment)), _commitment.signature);
        if (_recovered != _gateway) {
            revert InvalidSignature();
        }
        // Decode the commitment payload
        ToBCommitment memory _toBCommitment = abi.decode(_commitment.commitment.payload, (ToBCommitment));

        bytes32 _blockhash = ITobasco(_tobasco).submittedBlockhash(_toBCommitment.timestamp);

        // Verify the Gateway signed the blockhash
        return ECDSA.recover(_blockhash, _signature) == _gateway;
    }

    function _wasSubmitted(uint48 _timestamp) internal view returns (bool) {
        return ITobasco(_tobasco).submitted(_timestamp);
    }

    function _computeChallengeID(Delegation calldata delegation, Commitment calldata commitment)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(commitment, delegation));
    }

    function _computeFaultID(SignedCommitment calldata commitment) internal pure returns (bytes32) {
        return keccak256(abi.encode(commitment));
    }

    // @dev This function verifies a Merkle inclusion proof, proving:
    // @dev 1. A transaction was submitted at the ToB position during in the expected block.
    // @dev 2. The transaction called the expected contract.
    // @dev 3. The transaction called the expected function with the expected function selector.
    function _verifyInclusionProof(InclusionProof calldata proof, ToBCommitment memory toBCommitment)
        internal
        view
        returns (bool)
    {
        // Check that the previous block is within the EVM lookback window for block hashes.
        // Clearly, if the previous block is available, the target block will be too.
        uint256 previousBlockNumber = proof.inclusionBlockNumber - 1;
        if (previousBlockNumber > block.number || previousBlockNumber < block.number - BLOCKHASH_EVM_LOOKBACK) {
            revert InvalidBlockNumber();
        }

        // Get the trusted block hash for the block number in which the transactions were included.
        bytes32 trustedPreviousBlockHash = blockhash(proof.inclusionBlockNumber - 1);

        // Check the integrity of the trusted block hash
        bytes32 previousBlockHash = keccak256(proof.previousBlockHeaderRLP);
        if (previousBlockHash != trustedPreviousBlockHash) {
            revert InvalidBlockHash();
        }

        // Decode the RLP-encoded block header of the target block.
        //
        // The target block is necessary to extract the transaction root and verify the inclusion of the
        // committed transaction. By checking against the previous block's parent hash we can ensure this
        // is the correct block trusting a single block hash.
        BlockHeaderData memory targetBlockHeader = _decodeBlockHeaderRLP(proof.inclusionBlockHeaderRLP);

        // Check that the target block is a child of the previous block
        if (targetBlockHeader.parentHash != previousBlockHash) {
            revert InvalidParentBlockHash();
        }

        // Check that the commitment timestamp matches the block timestamp
        if (toBCommitment.timestamp != targetBlockHeader.timestamp) {
            revert IncorrectTimestamp();
        }

        // We expect the transaction to be in the 0th position of the block
        bytes memory txLeaf = RLPWriter.writeUint(0);

        // Verify transaction inclusion proof
        //
        // The transactions trie is built with raw leaves, without hashing them first
        // (This denotes why we use `MerkleTrie.get()` as opposed to `SecureMerkleTrie.get()`).
        (bool txExists, bytes memory txRLP) = MerkleTrie.get(txLeaf, proof.txMerkleProof, targetBlockHeader.txRoot);

        // Transaction does not exist in the ToB position
        if (!txExists) {
            revert TransactionNotIncluded();
        }

        // RLP decode the transaction to verify it called the correct contract
        TransactionDecoder.Transaction memory txData = TransactionDecoder.decodeEnveloped(txRLP);
        if (txData.to != toBCommitment.tobasco) {
            revert InvalidDestination();
        }

        // Extract the function selector from the transaction data
        // We skip the first 32B which encode the length
        bytes4 usedFuncSelector;
        bytes memory data = txData.data;
        assembly {
            usedFuncSelector := mload(add(data, 32))
        }

        // Verify the function selector matches what was committed to
        if (usedFuncSelector != toBCommitment.funcSelector) {
            revert IncorrectFunctionSelector();
        }

        return true;
    }

    /// @notice Decode the block header fields from an RLP-encoded block header.
    /// @param headerRLP The RLP-encoded block header to decode
    function _decodeBlockHeaderRLP(bytes memory headerRLP) internal pure returns (BlockHeaderData memory blockHeader) {
        RLPReader.RLPItem[] memory headerFields = headerRLP.toRLPItem().readList();

        blockHeader.parentHash = headerFields[0].readBytes32();
        blockHeader.stateRoot = headerFields[3].readBytes32();
        blockHeader.txRoot = headerFields[4].readBytes32();
        blockHeader.blockNumber = headerFields[8].readUint256();
        blockHeader.timestamp = headerFields[11].readUint256();
        blockHeader.baseFee = headerFields[15].readUint256();
    }
}
