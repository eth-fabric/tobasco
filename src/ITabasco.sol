// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {ISlasher} from "urc/src/ISlasher.sol";

interface ITabasco is ISlasher {
    function wasSubmitted(uint48 blockNumber) external view returns (bool);
    function canSubmit(address submitter) external view returns (bool);
}