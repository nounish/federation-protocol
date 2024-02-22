// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { Wallet } from "src/wallet/Wallet.sol";
import { Relayer } from "src/module/l2-governance/Relayer.sol";

contract UpdateRelayerConfig is Script {

  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    Wallet w = Wallet(0x0ceD883DEc9861B4805E59A15CFa17697c6c3c3c);

    Relayer.Config memory config = Relayer.Config({
        base: 0x0ceD883DEc9861B4805E59A15CFa17697c6c3c3c,
        externalDAO: 0x6f3E6272A167e8AcCb32072d08E0957F9c79223d,
        nativeToken: 0x4b10701Bfd7BFEdc47d50562b76b436fbB5BdB3B,
        zkSync: 0x32400084C286CF3E17e7B677ea9583e60a000324,
        governor: 0x12A8924D3B8F96c6B13eEbd022c1414d0b537Ad9,
        quorumVotesBPS: 0
    });

    w.execute(0x675188C46D47198e9b868633B67adaA16f8F4fcB, 0, abi.encodeWithSignature("setConfig((address,address,address,address,address,uint256))", abi.encode(config)));

    vm.stopBroadcast();
  }
}
