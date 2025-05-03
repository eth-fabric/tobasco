// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

import {IRegistry} from "urc/src/IRegistry.sol";
import {ISlasher} from "urc/src/ISlasher.sol";

/**
 * @title MockURC
 * @dev Mock implementation of the URC (Universal Registry Contract) for testing purposes
 * Simulates the slashing functionality of the real URC contract
 */
contract MockURC {
    /**
     * @dev Simulates the slashing of a commitment in the URC
     * @param proof The registration proof
     * @param delegation The signed delegation
     * @param commitment The signed commitment to be slashed
     * @param evidence The evidence for slashing
     * @return slashAmountWei The amount of ETH to be slashed
     */
    function slashCommitment(
        IRegistry.RegistrationProof calldata proof,
        ISlasher.SignedDelegation calldata delegation,
        ISlasher.SignedCommitment calldata commitment,
        bytes calldata evidence
    ) external returns (uint256 slashAmountWei) {
        return ISlasher(commitment.commitment.slasher).slash(
            delegation.delegation, commitment.commitment, address(0), evidence, msg.sender
        );
    }
}
