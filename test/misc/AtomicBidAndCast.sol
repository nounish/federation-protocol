// SPDX-License-Identifier: BSD-3-Clause

import { GovernancePool } from "src/module/governance-pool/GovernancePool.sol";

pragma solidity ^0.8.19;

/// @title Test implementation of a contract that can be used to bid and cast on governance pools
contract AtomicBidAndCast {
  function bidAndCast(address pool, uint256 propId, uint8 support) external payable {
    GovernancePool(pool).bid{ value: msg.value }(propId, support);
    GovernancePool(pool).castVote(propId);
  }
}
