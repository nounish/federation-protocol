// SPDX-License-Identifier: GPL-3.0

import "forge-std/Test.sol";
import {NounsPool, NounsGovernanceV2} from "src/module/governance-pool/nouns/Nouns.sol";
import {GovernancePool} from "src/module/governance-pool/GovernancePool.sol";
import {ModuleConfig} from "src/module/governance-pool/ModuleConfig.sol";

pragma solidity ^0.8.19;

contract TestPoolHelpers is Test, NounsPool {
    function testVoteSnapshotBlock() public {
        _cfg.useStartBlockFromPropId = 0;

        GovernancePool.Bid memory b;
        b.creationBlock = 0;
        b.startBlock = 1;

        uint256 pId = 1;
        bids[pId] = b;

        GovernancePool.Bid memory b2;
        b.creationBlock = 32;
        b.startBlock = 99;
        bids[pId + 1] = b2;

        assertEq(_voteSnapshotBlock(b, pId), b.creationBlock);

        _cfg.useStartBlockFromPropId = 1;
        assertEq(_voteSnapshotBlock(b, pId), b.startBlock);

        assertEq(_voteSnapshotBlock(bids[pId + 1], pId + 1), b2.startBlock);

        _cfg.useStartBlockFromPropId = 3;
        assertEq(_voteSnapshotBlock(bids[pId + 1], pId + 1), b2.creationBlock);
    }
}
