// SPDX-License-Identifier: GPL-3.0

import { Module } from "src/module/Module.sol";
import { Wallet } from "src/wallet/Wallet.sol";

pragma solidity ^0.8.19;

struct ModuleConfig {
  address base;
}

contract GenericModule is Module {
  ModuleConfig public cfg;
  bool initialized = false;

  /// Can only be called once
  function init(bytes calldata data) external payable override {
    if (initialized) {
      return;
    }

    cfg = abi.decode(data, (ModuleConfig));
    initialized = true;
  }

  /// Calls execute on base wallet which callbacks to this.ex()
  /// Used in tests to ensure that arb txns are executed and return values are
  /// handled properly
  function exec() external returns (bytes memory) {
    Wallet w = Wallet(cfg.base);
    return w.execute(address(this), 0, abi.encodeWithSelector(this.ex.selector));
  }

  /// Example return fn used in tests
  function ex() external pure returns (uint256) {
    return 1;
  }
}
