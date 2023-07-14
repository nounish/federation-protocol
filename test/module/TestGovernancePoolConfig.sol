// SPDX-License-Identifier: GPL-3.0

import "forge-std/Test.sol";
import { Base } from "src/wallet/Base.sol";
import { BaseProxy } from "src/wallet/BaseProxy.sol";
import { Wallet } from "src/wallet/Wallet.sol";
import { NounsPool, NounsGovernanceV2 } from "src/module/governance-pool/Nouns.sol";
import { GovernancePool } from "src/module/governance-pool/GovernancePool.sol";
import { ModuleConfig } from "src/module/governance-pool/ModuleConfig.sol";
import { NounsFactory } from "src/module/governance-pool/NounsFactory.sol";
import { AtomicBidAndCast } from "test/misc/AtomicBidAndCast.sol";
import { FailMockValidator, PassMockValidator } from "test/misc/MockFactValidator.sol";
import { MockProver } from "test/misc/MockProver.sol";
import {
  TestEnv,
  NOUNS_GOVERNOR,
  NOUNS_TOKEN,
  DELEGATE_CASH,
  RELIQUARY,
  SLOT_INDEX_TOKEN_BALANCE,
  SLOT_INDEX_DELEGATEE
} from "test/environment/TestEnv.sol";
import {
  NounsDAOStorageV1Adjusted,
  NounsDAOStorageV2
} from "nouns-contracts/governance/NounsDAOInterfaces.sol";
import { NounsDAOLogicV2 } from "nouns-contracts/governance/NounsDAOLogicV2.sol";
import { NounsToken } from "nouns-contracts/NounsToken.sol";
import { AccessControl } from "openzeppelin/access/AccessControl.sol";
import { Strings } from "openzeppelin/utils/Strings.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import { IReliquary } from "relic-sdk/packages/contracts/interfaces/IReliquary.sol";
import { IProver } from "relic-sdk/packages/contracts/interfaces/IProver.sol";
import { IBatchProver } from "relic-sdk/packages/contracts/interfaces/IBatchProver.sol";
import { Fact } from "relic-sdk/packages/contracts/lib/Facts.sol";
import { FactSigs } from "relic-sdk/packages/contracts/lib/FactSigs.sol";
import { Storage } from "relic-sdk/packages/contracts/lib/Storage.sol";
import { IDelegationRegistry } from "delegate-cash/IDelegationRegistry.sol";

pragma solidity ^0.8.19;

interface Pausable {
  function pause() external;
  function unpause() external;
}

contract TestGovernancePoolConfig is Test {
  address owner = vm.addr(0x1);
  address bidder1 = vm.addr(0x666);
  address bidder2 = vm.addr(0x999);
  address relicDeployer = 0xf979392E396dc53faB7B3C430dD385e73dD0A4e2;
  address relicGov = 0xCCEf16C5ac53714512A5Acce5Fa1984A977351bE;

  Wallet baseWallet;
  Base baseImpl;
  NounsPool pool;
  NounsFactory poolFactory;
  MockProver mp;
  ProxyAdmin admin;
  TestEnv internal _env;
  ModuleConfig.Config poolCfg;

  /// configure all the things
  function setUp() public {
    // steady lads deploying more capital 🫡
    vm.deal(bidder1, 128 ether);
    vm.deal(bidder2, 420 ether);
    vm.deal(owner, 96 ether);

    baseImpl = new Base();
    admin = new ProxyAdmin();
    mp = new MockProver();

    NounsPool _pool = new NounsPool();

    poolFactory =
      new NounsFactory(address(_pool), RELIQUARY, DELEGATE_CASH, address(0), owner, 150, 80 gwei, 0);

    bytes memory data = abi.encodeWithSelector(Base.initialize.selector, address(this));
    BaseProxy proxy = new BaseProxy(address(baseImpl), address(admin), data);
    baseWallet = Wallet(address(proxy));
    admin.transferOwnership(owner);

    NounsFactory.PoolConfig memory fCfg = NounsFactory.PoolConfig(
      address(baseWallet), NOUNS_GOVERNOR, NOUNS_TOKEN, 0.1 ether, 5, 150, 0, 0, 0.01 ether, 0
    );
    pool = NounsPool(poolFactory.clone(fCfg, "hello world"));
    baseWallet.setModule(address(pool), true);

    uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
    vm.selectFork(mainnetFork);
    vm.rollFork(17131180);
    _env = new TestEnv(vm);
  }

  function testModuleConfig() public {
    _registerMockProver();

    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator1 = nouners[1];

    // should not be able to change feeBPS or Receipient
    ModuleConfig.Config memory cfg = pool.getConfig();
    PassMockValidator pmv = new PassMockValidator();
    ModuleConfig.Config memory pcfg = ModuleConfig.Config(
      address(baseWallet),
      NOUNS_GOVERNOR,
      NOUNS_TOKEN,
      bidder2,
      0.1 ether,
      25, // timeBuffer
      5,
      150,
      200, // auctionCloseBlocks
      0.01 ether,
      1000,
      80 gwei,
      0,
      RELIQUARY,
      DELEGATE_CASH,
      address(pmv),
      0,
      "",
      0
    );

    vm.prank(delegator1);
    nt.delegate(cfg.base);

    vm.prank(cfg.base);
    pool.setConfig(pcfg);

    cfg = pool.getConfig();

    uint256 pIdF = _env.SubmitProposal(vm, 1 ether, bidder1, delegator1);
    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsDAOLogicV2 nounsDAO = NounsDAOLogicV2(payable(NOUNS_GOVERNOR));
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    // move into the execution window
    vm.roll((pc.endBlock - cfg.auctionCloseBlocks - 100));
    vm.prank(bidder1);
    pool.bid{ value: 20 ether }(pId, 1, "hello world");

    // if we pause, should only be allowed to bid on
    // proposals that have a previous bid
    vm.prank(cfg.base);
    Pausable(address(pool)).pause();

    vm.prank(bidder1);
    pool.bid{ value: 23 ether }(pId, 1, "hello world");

    vm.prank(bidder1);
    vm.expectRevert(GovernancePool.BidModulePaused.selector);
    pool.bid{ value: 20 ether }(pIdF, 1, "hello world");

    vm.prank(cfg.base);
    Pausable(address(pool)).unpause();
    pool.bid{ value: 20 ether }(pIdF, 1, "hello world");
    pool.bid{ value: 30 ether }(pId, 1, "hello world");
    // =====

    // can only be called if not locked
    vm.prank(cfg.base);
    vm.expectRevert(ModuleConfig.ConfigModuleHasActiveLock.selector);
    pool.setConfig(pcfg);

    // should be unlocked after prop end block
    vm.roll(pc.endBlock + 10);
    vm.prank(cfg.base);
    pool.setConfig(pcfg);

    vm.prank(cfg.base);
    pool.setSlots(1, 2);
    assertEq(pool.balanceSlotIdx(), bytes32(uint256(1)));
    assertEq(pool.delegateSlotIdx(), bytes32(uint256(2)));

    vm.prank(cfg.base);
    pool.setAddresses(owner, owner, owner);

    cfg = pool.getConfig();
    assertEq(cfg.reliquary, owner);
    assertEq(cfg.dcash, owner);
    assertEq(cfg.factValidator, owner);

    vm.expectRevert();
    pool.setFee(100, owner);

    // only owner
    vm.prank(cfg.base);
    uint256 newfee = cfg.feeBPS - 10;
    pool.setFee(newfee, owner);
    cfg = pool.getConfig();
    assertEq(cfg.feeBPS, newfee);

    // only owner
    vm.expectRevert();
    pool.setReservePrice(1 ether);

    vm.prank(cfg.base);
    pool.setReservePrice(1 ether);
    cfg = pool.getConfig();
    assertEq(cfg.reservePrice, 1 ether);
  }

  // sets permissions on reliquary and registers the mock prover for testing
  function _registerMockProver() internal {
    IReliquary reliquary = IReliquary(RELIQUARY);
    vm.startPrank(relicGov);
    AccessControl(address(reliquary)).grantRole(keccak256("ADD_PROVER_ROLE"), relicDeployer);
    AccessControl(address(reliquary)).grantRole(keccak256("GOVERNANCE_ROLE"), relicDeployer);
    try reliquary.addProver(address(mp), 69) {
      vm.warp(block.timestamp + 3 days);
      vm.stopPrank();
      vm.startPrank(relicDeployer);
      reliquary.activateProver(address(mp));
      reliquary.setProverFee(address(mp), IReliquary.FeeInfo(1, 0, 0, 0, 0), address(0));
    } catch Error(string memory) {
      // only register once
    }
    vm.stopPrank();
  }
}
