// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {ISlasher} from "urc/src/ISlasher.sol";

interface IBurn is ISlasher {
    struct ToBCommitment {
        // The timestamp the transaction should have been submitted
        uint48 timestamp;
        // The address of the ToB contract
        address tobasco;
    }

    enum Status {
        Nonexistent,
        Unresolved,
        ProposerFault,
        GatewayFault
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
    // Events
    event ChallengeOpened(bytes32 challengeID);
    event GatewayFaultProven(bytes32 faultID, bytes32 challengeID, address gateway);
}
