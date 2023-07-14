// SPDX-License-Identifier: GPL-3.0

import { Module } from "src/module/Module.sol";
import { OwnableUpgradeable } from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import { Wallet } from "src/wallet/Wallet.sol";

pragma solidity ^0.8.19;

/// Module to manage governance pools
contract Manager is Module, OwnableUpgradeable {
  /// The name of this contract
  string public constant name = "Federation Manager v0.1";

  struct Config {
    /// The base wallet address for this module
    address base;
    /// The module to manage
    address module;
    /// Owner of this module
    address owner;
  }

  /// Module config
  Config internal _cfg;

  /// Do not leave implementation uninitialized
  constructor() {
    _disableInitializers();
  }

  /// Module initialization; Can only be called once
  function init(bytes calldata _data) external payable initializer {
    __Ownable_init();

    _cfg = abi.decode(_data, (Config));

    _transferOwnership(_cfg.owner);
  }

  /// Execute a generic tx against the governance pool
  function execute(bytes calldata _data) external onlyOwner {
    Wallet(_cfg.base).execute(_cfg.module, 0, _data);
  }
}
