// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {IRegistry} from "urc/src/IRegistry.sol";
import {ISlasher} from "urc/src/ISlasher.sol";
import {IBurn} from "../src/IBurn.sol";
import {Burn} from "../src/Burn.sol";
import {Tobasco} from "../src/Tobasco.sol";

contract TobascoTester is Tobasco {
    uint256 public foo;
    uint256 public gasLeftAmount;

    function update(uint256 _foo, uint256 _blockNumber) external onlyTopOfBlock(_blockNumber) {
        foo = _foo;
    }

    function _gasleft() internal override returns (uint256) {
        if (gasLeftAmount > 0) {
            // By default Foundry is consuming gas so the default gasleft()
            // is too low during unit tests. This is a hack to fix that.
            return gasLeftAmount;
        }
        return gasleft();
    }

    function setGasLeftAmount(uint256 _gasLeftAmount) public {
        gasLeftAmount = _gasLeftAmount;
    }
}

contract MockURC {
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

contract UnitTestHelper is Test {
    MockURC urc;
    Burn burn;
    TobascoTester tobasco;

    address proposer;
    uint256 proposerKey;
    address challenger;
    uint256 challengerKey;
    address user;
    uint256 userKey;
    address gateway;
    uint256 gatewayKey;

    struct SlashingInputs {
        uint256 blockNumber;
        address commitmentCommitter;
        address delegationCommitter;
        address tobasco;
        uint256 privateKey;
        bytes4 funcSelector;
        address slasher;
        uint256 commitmentType;
    }

    function signedCommitment(
        IBurn.ToBCommitment memory _toBCommitment,
        uint256 _commitmentType,
        address _slasher,
        uint256 _privateKey
    ) public returns (ISlasher.SignedCommitment memory) {
        ISlasher.Commitment memory commitment = ISlasher.Commitment({
            commitmentType: uint64(_commitmentType),
            payload: abi.encode(_toBCommitment),
            slasher: _slasher
        });

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, keccak256(abi.encode(commitment)));
        bytes memory signature = abi.encodePacked(r, s, v);
        return ISlasher.SignedCommitment({commitment: commitment, signature: signature});
    }

    // basic delegation, we only care about checking the committer address in our tests
    function signedDelegation(address _committer) public returns (ISlasher.SignedDelegation memory delegation) {
        delegation.delegation.committer = _committer;
    }

    function slashingInputs(SlashingInputs memory _slashingInputs)
        public
        returns (ISlasher.SignedCommitment memory, ISlasher.SignedDelegation memory)
    {
        // Create a SignedCommitment
        ISlasher.SignedCommitment memory _signedCommitment = signedCommitment(
            IBurn.ToBCommitment({
                blockNumber: uint48(_slashingInputs.blockNumber),
                tobasco: _slashingInputs.tobasco,
                funcSelector: _slashingInputs.funcSelector
            }),
            _slashingInputs.commitmentType,
            _slashingInputs.slasher,
            _slashingInputs.privateKey
        );

        // Create a SignedDelegation
        ISlasher.SignedDelegation memory _signedDelegation = signedDelegation(_slashingInputs.delegationCommitter);

        return (_signedCommitment, _signedDelegation);
    }
}
