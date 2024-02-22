// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.19;

import { IProver } from "relic-sdk/packages/contracts/interfaces/IProver.sol";
import { Fact } from "relic-sdk/packages/contracts/lib/Facts.sol";
import { CoreTypes } from "relic-sdk/packages/contracts/lib/CoreTypes.sol";

/// @title Test implementation of a contract that can be used for layer 2 governance
contract MockLogProver is IProver {
    address logAddress;
    bytes logData;

    function setProofData(bytes calldata _data, address _address) external {
        logData = _data;
        logAddress = _address;
    }

    function prove(bytes calldata, bool) external payable returns (Fact memory) {
        Fact memory fact;

        CoreTypes.LogData memory log = CoreTypes.LogData({
            Data: logData,
            Topics: new bytes32[](0),
            Address: logAddress
        });

        fact.data = abi.encode(log);

        // fact.data = abi.encode(logData, new bytes32[](0), logAddress);

        return fact;
    }
}