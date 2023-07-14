// SPDX-License-Identifier: GPL-3.0

import { Module } from "src/module/Module.sol";
import { Manager } from "src/module/governance-pool/Manager.sol";
import { Clones } from "openzeppelin/proxy/Clones.sol";

pragma solidity ^0.8.19;

contract ManagerFactory {
  /// The name of this contract
  string public constant name = "Federation Manager Factory v0.1";

  /// Emitted when a new clone is created
  event Created(address addr);

  /// The address of the implementation contract
  address public impl;

  constructor(address _impl) {
    impl = _impl;
  }

  /// Deploy a new Manager module
  /// @param _base The base address
  /// @param _module Address of module to manage
  /// @param _owner Address of the module owner
  function clone(address _base, address _module, address _owner) external payable returns (address) {
    address inst = Clones.clone(impl);

    Manager.Config memory cfg = Manager.Config(_base, _module, _owner);
    Module(inst).init{ value: msg.value }(abi.encode(cfg));
    emit Created(inst);

    return inst;
  }
}
