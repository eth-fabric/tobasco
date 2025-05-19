// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

import {IBurn} from "./IBurn.sol";
import {ITobasco} from "./ITobasco.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Burn is IBurn {
    mapping(bytes32 challengeID => Challenge challenge) private challenges;
    mapping(bytes32 challengeID => GatewayFault fault) private faults;
    address private _urc;
    address private _tobasco;
    uint256 private _slashAmountWei;
    uint64 private _commitmentType;
    uint256 private _challengeWindowSeconds;

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
    ) external returns (uint256 slashAmountWei) {
        // Only the URC can call this function
        if (msg.sender != _urc) revert OnlyURC();

        bytes32 _challengeID = _computeChallengeID(_delegation, _commitment);

        // Can only slash if the challenge is still unresolved
        if (challenges[_challengeID].status != Status.Unresolved) {
            revert WrongChallengeStatus();
        }

        // Verify the challenge period expired
        if (block.timestamp - challenges[_challengeID].timestamp < _challengeWindowSeconds)
            revert ChallengePeriodNotExpired();
        
        // Update the challenge status to ProposerFault to prevent replays
        challenges[_challengeID].status = Status.ProposerFault;

        // Return the slash amount to the URC slasher
        slashAmountWei = _slashAmountWei;
    }

    // @dev This function is called to challenge a Proposer failed to submit a transaction at the specified timestamp at ToB.
    // @dev This function does not check _delegation or _commitment signatures as this is handled in the `attributeGatewayFault` function or `slash()` function if the challenge is valid.
    // @dev If someone tries to grief by calling this function with an invalid _delegation or _commitment, the challenges can be ignored as they are unenforceable by `slash()` or `attributeGatewayFault()`
    function openChallenge(
        Delegation calldata _delegation,
        Commitment calldata _commitment
    ) external returns (bytes32 _challengeID) {
        // Decode the commitment payload
        ToBCommitment memory toBCommitment = abi.decode(
            _commitment.payload,
            (ToBCommitment)
        );

        // Slashing is only possible if the transaction was not submitted at the specified timestamp
        if (_wasSubmitted(toBCommitment.timestamp))
            revert CommitmentWasNotBroken();

        // Verify the ToB destination address was the expected Tobasco contract
        if (toBCommitment.tobasco != _tobasco) revert InvalidDestination();

        // Verify the commitment.slasher is this contract
        if (_commitment.slasher != address(this)) revert WrongSlasher();

        // Verify the commitment type matches this contract's
        if (_commitment.commitmentType != _commitmentType)
            revert InvalidCommitmentType();

        // Compute the challenge ID
        _challengeID = _computeChallengeID(_delegation, _commitment);

        // Check if the challenge already exists
        if (challenges[_challengeID].status != Status.Nonexistent) {
            revert ChallengeAlreadyExists();
        }

        // The challenge is valid -> log the challenge to start the challenge window
        challenges[_challengeID] = Challenge({
            timestamp: uint48(block.timestamp),
            status: Status.Unresolved
        });

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
        if (challenges[_challengeID].status != Status.Unresolved)
            revert WrongChallengeStatus();

        // The challenge must have been created within the challenge window
        if (block.timestamp - challenges[_challengeID].timestamp > _challengeWindowSeconds)
            revert ChallengePeriodExpired();

        // Verify the Gateway signed the blockhash and the commitment
        // This provides evidence that the Gateway attested to the block's correctness
        // and therefore is the party at fault
        if (!_verifyGatewaySignatures(
                _gateway,
                _commitment,
                _blockhashSignature
            )
        ) revert InvalidSignature();

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
        if (faults[_faultID].status != Status.Unresolved)
            revert WrongChallengeStatus();

        // The challenge window must have expired to mark them slashable
        if (block.timestamp - faults[_faultID].timestamp < _challengeWindowSeconds)
            revert ChallengePeriodNotExpired();

        faults[_faultID].status = Status.GatewayFault;
    }

    function vindicateGateway() external {
        // todo
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

    // todo getters for the private variables
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
        ToBCommitment memory _toBCommitment = abi.decode(
            _commitment.commitment.payload,
            (ToBCommitment)
        );

        bytes32 _blockhash = ITobasco(_tobasco).submittedBlockhash(
            _toBCommitment.timestamp
        );

        // Verify the Gateway signed the blockhash
        return ECDSA.recover(_blockhash, _signature) == _gateway;
    }

    function _wasSubmitted(uint48 _timestamp) internal view returns (bool) {
        return ITobasco(_tobasco).submitted(_timestamp);
    }

    function _computeChallengeID(
        Delegation calldata delegation,
        Commitment calldata commitment
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(commitment, delegation));
    }

    function _computeFaultID(
        SignedCommitment calldata commitment
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(commitment));
    }
}
