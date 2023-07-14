// SPDX-License-Identifier: GPL-3.0

import "forge-std/Test.sol";
import { Base } from "src/wallet/Base.sol";
import { Wallet } from "src/wallet/Wallet.sol";
import { Ownable } from "openzeppelin/access/Ownable.sol";
import { BaseProxy } from "src/wallet/BaseProxy.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import { GenericModule, ModuleConfig } from "test/module/TestGenericModule.sol";

pragma solidity ^0.8.19;

contract TestBaseWallet is Test {
  address public owner = vm.addr(0x1);
  Wallet public baseWallet;
  Base baseImpl;
  ProxyAdmin admin;

  /// instantiate a base wallet to use in tests
  function setUp() public {
    baseImpl = new Base();
    admin = new ProxyAdmin();

    bytes memory data = abi.encodeWithSelector(
      Base.initialize.selector, address(this), new address[](0), new bytes[](0)
    );

    BaseProxy proxy = new BaseProxy(address(baseImpl), address(admin), data);
    baseWallet = Wallet(address(proxy));
    admin.transferOwnership(owner);
  }

  function testExecute() public {
    GenericModule module = new GenericModule();
    ModuleConfig memory mc = ModuleConfig(address(baseWallet));
    module.init(abi.encode(mc));

    // if module is not enabled execution should revert, initially enables to
    // set its config
    baseWallet.setModule(address(module), true);
    baseWallet.setModule(address(module), false);

    vm.expectRevert(Wallet.NotEnabled.selector);
    module.exec();

    // enable module and execute transaction
    baseWallet.setModule(address(module), true);

    vm.recordLogs();
    bytes memory ret = module.exec();
    Vm.Log[] memory entries = vm.getRecordedLogs();

    // ensure transaction was executed and the ret value is valid
    assertEq(ret, abi.encode(1), "should return 1");

    bytes32 e = entries[0].topics[0];
    assertEq(e, keccak256("ExecuteTransaction(address,address,uint256)"));

    address topicAddr = address(uint160(uint256((entries[0].topics[1]))));
    assertEq(topicAddr, address(module));

    address target = address(uint160(uint256((entries[0].topics[2]))));
    assertEq(target, address(module));
  }

  function testSetModule() public {
    GenericModule module = new GenericModule();
    ModuleConfig memory mc = ModuleConfig(address(baseWallet));
    module.init(abi.encode(mc));

    // ensure that modules are initiated when added to base
    vm.recordLogs();
    baseWallet.setModule(address(module), true);
    Vm.Log[] memory entries = vm.getRecordedLogs();

    bytes32 e = entries[0].topics[0];
    assertEq(e, keccak256("SetModule(address,bool)"));

    address topicAddr = address(uint160(uint256((entries[0].topics[1]))));
    assertEq(topicAddr, address(module));

    (address cfgBase) = module.cfg();
    assertEq(cfgBase, address(baseWallet), "base address should be set");

    assertEq(baseWallet.moduleEnabled(address(module)), true, "module should be enabled");

    baseWallet.setModule(address(module), true);
    entries = vm.getRecordedLogs();
    assertEq(entries.length, 0, "noop if already enabled");
  }

  address[] testMods;
  bytes[] testModCfg;

  function testInitialize() public {
    GenericModule module = new GenericModule();
    ModuleConfig memory mc = ModuleConfig(address(baseWallet));

    /// initialize w/ modules
    testMods.push(address(module));
    testModCfg.push(abi.encode(mc));

    bytes memory data = abi.encodeWithSelector(Base.initialize.selector, owner);

    BaseProxy proxy = new BaseProxy(address(baseImpl), address(admin), data);
    Wallet w = Wallet(address(proxy));
    assertEq(w.maxLockDurationBlocks(), 50_400);

    Ownable wOwn = Ownable(address(w));
    assertEq(wOwn.owner(), owner);
  }

  function testRequestLock() public {
    vm.expectRevert(Wallet.NotEnabled.selector);
    baseWallet.requestLock(100);

    GenericModule module = new GenericModule();
    ModuleConfig memory mc = ModuleConfig(address(baseWallet));

    GenericModule module2 = new GenericModule();
    module.init(abi.encode(mc));
    module2.init(abi.encode(mc));

    baseWallet.setModule(address(module), true);
    baseWallet.setModule(address(module2), true);

    vm.recordLogs();
    vm.prank(address(module));
    uint256 lockEnds = baseWallet.requestLock(300);
    assertEq(lockEnds, block.number + 300, "should return lock end time");

    Vm.Log[] memory entries = vm.getRecordedLogs();
    bytes32 e = entries[0].topics[0];
    assertEq(e, keccak256("RequestLock(address,uint256)"));

    vm.roll(block.number + 200);

    vm.prank(address(module2));
    lockEnds = baseWallet.requestLock(300);
    assertEq(lockEnds, block.number + 300, "should return lock end time");

    vm.prank(address(module));
    uint256 remaining = baseWallet.requestLock(50);
    assertEq(
      remaining,
      100,
      "should return remaining time if not expired and the requested duration is less than the remaining blocks"
    );

    vm.prank(address(module));
    bool hasLock = baseWallet.hasActiveLock();
    assertEq(hasLock, true, "should have active lock");

    vm.prank(address(module));
    remaining = baseWallet.requestLock(7200); // 24 hours
    vm.roll(block.number + 200);

    vm.prank(address(module));
    remaining = baseWallet.requestLock(6000);
    assertEq(remaining, 7000, "should return remaining time");
    vm.getRecordedLogs();

    vm.prank(address(module));
    baseWallet.releaseLock();
    entries = vm.getRecordedLogs();
    e = entries[0].topics[0];
    assertEq(e, keccak256("ReleaseLock(address)"));
  }

  function testSetMaxLockDurationBlocks() public {
    vm.recordLogs();
    baseWallet.setMaxLockDurationBlocks(100);
    assertEq(baseWallet.maxLockDurationBlocks(), 100, "should set max lock duration");

    Vm.Log[] memory entries = vm.getRecordedLogs();
    bytes32 e = entries[0].topics[0];
    assertEq(e, keccak256("MaxLockDurationBlocksChanged(uint256)"));
  }
}
