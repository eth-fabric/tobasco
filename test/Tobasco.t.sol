// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Tobasco} from "../src/Tobasco.sol";
import {ITobasco} from "../src/ITobasco.sol";

import {IRegistry} from "urc/src/IRegistry.sol";
import {ISlasher} from "urc/src/ISlasher.sol";

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

contract OracleExample is Tobasco {
    uint256 public price;
    uint256 public gasLeftAmount;

    constructor(address[] memory _owners, address _urc, uint64 _commitmentType)
        Tobasco(_owners, _urc, 1 ether, 21000, _commitmentType)
    {}

    function post(uint256 _price, uint256 _blockNumber) external onlySubmitter onlyTopOfBlock(_blockNumber) {
        price = _price;
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

contract TobascoTest is Test {
    MockURC urc;
    OracleExample oracle;
    uint64 public commitmentType = 1;
    address alice = makeAddr("Alice");
    address bob = makeAddr("Bob");

    function setUp() public {
        urc = new MockURC();
        address[] memory owners = new address[](1);
        owners[0] = alice;
        oracle = new OracleExample(owners, address(urc), commitmentType);
    }

    function commitment(uint256 _blockNumber, address _destination, uint64 _commitmentType)
        public
        returns (ISlasher.SignedCommitment memory)
    {
        return ISlasher.SignedCommitment({
            commitment: ISlasher.Commitment({
                commitmentType: _commitmentType,
                payload: abi.encode(_blockNumber, _destination),
                slasher: address(oracle)
            }),
            signature: bytes("")
        });
    }

    function sendN(uint256 n, address _to) internal {
        bool success;
        for (uint256 i = 0; i < n; i++) {
            assembly ("memory-safe") {
                success := call(gas(), _to, 1, 0, 0, 0, 0)
            }
        }
    }

    function test_NotSubmitter() public {
        vm.prank(bob);
        vm.expectRevert(ITobasco.NotSubmitter.selector);
        oracle.post(100, block.number);
    }

    function test_BlockNumberMismatch() public {
        vm.prank(alice);
        vm.expectRevert(ITobasco.BlockNumberMismatch.selector);
        oracle.post(100, block.number + 1);
    }

    function test_NotTopOfBlock() public {
        vm.deal(alice, 1 ether);
        uint256 blockNumber = block.number;

        // fill the top of the block
        sendN(10, alice);

        // make sure its still the same block
        assert(block.number == blockNumber);

        vm.prank(alice);
        vm.expectRevert(ITobasco.NotTopOfBlock.selector);
        oracle.post{gas: block.gaslimit}(100, block.number);
    }

    function test_OnlyURC() public {
        ISlasher.Delegation memory _delegation;
        ISlasher.Commitment memory _commitment;
        vm.expectRevert(ITobasco.OnlyURC.selector);
        oracle.slash(_delegation, _commitment, address(0), bytes(""), address(0));
    }

    function test_CommitmentWasNotBroken() public {
        // hack to fix the gasleft() issue
        oracle.setGasLeftAmount(block.gaslimit - 21000);

        vm.prank(alice);
        oracle.post{gas: block.gaslimit}(100, block.number);

        assert(oracle.wasSubmitted(uint48(block.number)));

        IRegistry.RegistrationProof memory _proof;
        ISlasher.SignedDelegation memory _delegation;
        ISlasher.SignedCommitment memory _commitment = commitment(block.number, address(oracle), commitmentType);

        vm.expectRevert(ITobasco.CommitmentWasNotBroken.selector);
        urc.slashCommitment(_proof, _delegation, _commitment, bytes(""));
    }

    function test_InvalidCommitmentType() public {
        uint64 differentCommitmentType = commitmentType + 1;
        IRegistry.RegistrationProof memory _proof;
        ISlasher.SignedDelegation memory _delegation;
        ISlasher.SignedCommitment memory _commitment =
            commitment(block.number, address(oracle), differentCommitmentType);

        vm.prank(bob);
        vm.expectRevert(ITobasco.InvalidCommitmentType.selector);
        urc.slashCommitment(_proof, _delegation, _commitment, bytes(""));
    }

    function test_InvalidDestination() public {
        IRegistry.RegistrationProof memory _proof;
        ISlasher.SignedDelegation memory _delegation;
        ISlasher.SignedCommitment memory _commitment = commitment(
            block.number,
            address(bob), // Invalid destination
            commitmentType
        );

        vm.prank(bob);
        vm.expectRevert(ITobasco.InvalidDestination.selector);
        urc.slashCommitment(_proof, _delegation, _commitment, bytes(""));
    }

    function test_slash() public {
        IRegistry.RegistrationProof memory _proof;
        ISlasher.SignedDelegation memory _delegation;
        ISlasher.SignedCommitment memory _commitment = commitment(block.number, address(oracle), commitmentType);

        uint256 slashAmount = urc.slashCommitment(_proof, _delegation, _commitment, bytes(""));
        assert(slashAmount > 0);
    }
}
