// SPDX-License-Identifier: GPL-3.0

import { Fact, FactSignature } from "relic-sdk/packages/contracts/lib/Facts.sol";
import { FactSigs } from "relic-sdk/packages/contracts/lib/FactSigs.sol";

pragma solidity ^0.8.19;

interface Validator {
  function validate(Fact memory fact, bytes32 expectedSlot, uint256 expectedBlock, address account)
    external
    pure
    returns (bool);
}

/// FailMockValidator fails all proof validation
contract FailMockValidator is Validator {
  function validate(Fact memory, bytes32, uint256, address) external pure returns (bool) {
    return false;
  }
}

/// PassMockValidator passes all proof validation
contract PassMockValidator is Validator {
  function validate(Fact memory, bytes32, uint256, address) external pure returns (bool) {
    return true;
  }
}
