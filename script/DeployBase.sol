// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { Base } from "src/wallet/Base.sol";
import { BaseProxy } from "src/wallet/BaseProxy.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

contract Deploy is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    Base impl = new Base();
    ProxyAdmin admin = new ProxyAdmin();

    bytes memory data = abi.encodeWithSelector(Base.initialize.selector, tx.origin);
    BaseProxy proxy = new BaseProxy(address(impl), address(admin), data);

    console2.log("proxy admin:", address(admin));
    console2.log("base impl:", address(impl));
    console2.log("base:", address(proxy));

    vm.stopBroadcast();
  }
}
