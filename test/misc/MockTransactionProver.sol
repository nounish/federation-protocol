// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.19;

import { IProver } from "relic-sdk/packages/contracts/interfaces/IProver.sol";
import { Fact } from "relic-sdk/packages/contracts/lib/Facts.sol";

/// @title Test implementation of a contract that can be used for layer 2 governance
contract MockTransactionProver is IProver {
    uint256 blockNumber;
    uint256 txIdx;

    function setProofData(uint256 _blockNumber, uint256 _txIdx) external {
        blockNumber = _blockNumber;
        txIdx = _txIdx;
    }

    function prove(bytes calldata, bool) external payable returns (Fact memory) {
        Fact memory fact;

        fact.data = abi.encode(blockNumber, txIdx);

        return fact;
    }
}