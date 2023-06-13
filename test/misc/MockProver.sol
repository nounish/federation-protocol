// SPDX-License-Identifier: BSD-3-Clause

import { IBatchProver } from "relic-sdk/packages/contracts/interfaces/IBatchProver.sol";
import { Fact } from "relic-sdk/packages/contracts/lib/Facts.sol";

pragma solidity ^0.8.19;

/// @title Test implementation of a contract that can be used to bid and cast on governance pools
contract MockProver is IBatchProver {
  bytes[] public proofData;

  function setProofData(bytes[] calldata _data) external {
    proofData = _data;
  }

  // Generates facts with the expected data in data fields
  function proveBatch(bytes calldata, bool) external payable returns (Fact[] memory facts) {
    Fact[] memory _facts = new Fact[](proofData.length);
    for (uint256 i = 0; i < _facts.length; ++i) {
      _facts[i].data = proofData[i];
    }
    return _facts;
  }
}
