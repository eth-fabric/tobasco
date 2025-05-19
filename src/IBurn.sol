// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {ISlasher} from "urc/src/ISlasher.sol";

interface IBurn is ISlasher {
    struct ToBCommitment {
        // The timestamp the transaction should have been submitted
        uint48 timestamp;
        // The address of the ToB contract
        address tobasco;
        // The target function selector committed to being called
        bytes4 funcSelector;
    }

    enum Status {
        Nonexistent,
        Unresolved,
        ProposerFault,
        GatewayFault,
        Vindicated
    }

    struct Challenge {
        // The timestamp the challenge was created
        uint48 timestamp;
        // The status of the challenge
        Status status;
    }

    struct GatewayFault {
        // The address of the guilty party
        address gateway;
        // The timestamp the fault was proven
        uint48 timestamp;
        // The challenge ID
        bytes32 challengeID;
        // The status of the fault
        Status status;
    }

    struct InclusionProof {
        // block number where the transactions are included
        uint256 inclusionBlockNumber;
        // RLP-encoded block header of the previous block of the inclusion block
        // (for clarity: `previousBlockHeader.number == inclusionBlockNumber - 1`)
        bytes previousBlockHeaderRLP;
        // RLP-encoded block header where the committed transaction is included
        bytes inclusionBlockHeaderRLP;
        // merkle inclusion proof of the transaction in the transaction trie of the inclusion block
        // (checked against the inclusionBlockHeader.txRoot)
        bytes txMerkleProof;
    }

    struct BlockHeaderData {
        bytes32 parentHash;
        bytes32 stateRoot;
        bytes32 txRoot;
        uint256 blockNumber;
        uint256 timestamp;
        uint256 baseFee;
    }

    // Errors
    error CommitmentWasNotBroken();
    error OnlyURC();
    error InvalidCommitmentType();
    error InvalidDestination();
    error WrongSlasher();
    error ChallengeAlreadyExists();
    error WrongChallengeStatus();
    error ChallengePeriodExpired();
    error ChallengePeriodNotExpired();
    error InvalidSignature();
    error InvalidBlockNumber();
    error InvalidBlockHash();
    error InvalidParentBlockHash();
    error TransactionNotIncluded();
    error IncorrectTimestamp();
    error IncorrectFunctionSelector();
    error InclusionProofInvalid();

    // Events
    event ChallengeOpened(bytes32 challengeID);
    event GatewayFaultProven(bytes32 faultID, bytes32 challengeID, address gateway);

    // Functions

    /// @notice Opens a challenge against a Proposer who failed to execute a transaction at ToB
    /// @param _delegation The delegation containing the Gateway's `committer` address
    /// @param _commitment The commitment containing the ToBCommitment payload
    /// @return The ID of the created challenge
    function openChallenge(Delegation calldata _delegation, Commitment calldata _commitment)
        external
        returns (bytes32);

    /// @notice Attributes a fault to a Gateway and vindicates the Proposer
    /// @param _delegation The delegation containing the Gateway's `committer` address
    /// @param _commitment The Gateway-signed commitment containing the ToBCommitment payload
    /// @param _blockhashSignature The Gateway-signed blockhash for the block the challenge is for
    function attributeGatewayFault(
        Delegation calldata _delegation,
        SignedCommitment calldata _commitment,
        bytes calldata _blockhashSignature
    ) external;

    /// @notice Marks a Gateway as slashable after the challenge period has expired
    /// @param _faultID The ID of the fault to mark as slashable
    function markGatewaySlashable(bytes32 _faultID) external;

    /// @notice Allows a Gateway to vindicate themselves by proving transaction execution
    /// @param _commitment The signed commitment containing the payload and slasher
    /// @param _inclusionProof The proof of transaction inclusion in the block
    function vindicateGateway(SignedCommitment calldata _commitment, InclusionProof calldata _inclusionProof)
        external;

    /// @notice Checks if a Gateway is slashable for a given fault
    /// @param _faultID The ID of the fault to check
    /// @return True if the Gateway is slashable, false otherwise
    function gatewaySlashable(bytes32 _faultID) external view returns (bool);

    /// @notice Gets the fault details for a given fault ID
    /// @param _faultID The ID of the fault to get
    /// @return The GatewayFault struct containing fault details
    function getFault(bytes32 _faultID) external view returns (GatewayFault memory);

    /// @notice Gets the challenge details for a given challenge ID
    /// @param _challengeID The ID of the challenge to get
    /// @return The Challenge struct containing challenge details
    function getChallenge(bytes32 _challengeID) external view returns (Challenge memory);

    /// @notice Gets the URC address
    /// @return The address of the URC contract
    function urc() external view returns (address);

    /// @notice Gets the Tobasco contract address
    /// @return The address of the Tobasco contract
    function tobasco() external view returns (address);

    /// @notice Gets the slash amount in wei
    /// @return The amount to slash in wei
    function slashAmountWei() external view returns (uint256);

    /// @notice Gets the commitment type
    /// @return The commitment type identifier
    function commitmentType() external view returns (uint64);

    /// @notice Gets the challenge window duration in seconds
    /// @return The duration of the challenge window in seconds
    function challengeWindowSeconds() external view returns (uint256);
}
