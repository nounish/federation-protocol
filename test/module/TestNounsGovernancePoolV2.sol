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
  NOUNS_EXECUTOR,
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
import { NounsDAOExecutor } from "nouns-contracts/governance/NounsDAOExecutor.sol";
import { NounsToken } from "nouns-contracts/NounsToken.sol";
import { Strings } from "openzeppelin/utils/Strings.sol";
import { AccessControl } from "openzeppelin/access/AccessControl.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import { IReliquary } from "relic-sdk/packages/contracts/interfaces/IReliquary.sol";
import { IProver } from "relic-sdk/packages/contracts/interfaces/IProver.sol";
import { IBatchProver } from "relic-sdk/packages/contracts/interfaces/IBatchProver.sol";
import { Fact } from "relic-sdk/packages/contracts/lib/Facts.sol";
import { FactSigs } from "relic-sdk/packages/contracts/lib/FactSigs.sol";
import { Storage } from "relic-sdk/packages/contracts/lib/Storage.sol";
import { IDelegationRegistry } from "delegate-cash/IDelegationRegistry.sol";

pragma solidity ^0.8.19;

contract TestNounsGovernancePool is Test {
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
    vm.rollFork(17689200);
    _env = new TestEnv(vm);
  }

  function testAuctionExtending() public {
    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator = nouners[1];

    ModuleConfig.Config memory poolCfg = pool.getConfig();
    vm.prank(delegator);
    nt.delegate(poolCfg.base);

    NounsGovernanceV2 nounsDAO = NounsGovernanceV2(NOUNS_GOVERNOR);
    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    vm.roll(pc.startBlock + 10);

    // ensure bid is created
    vm.prank(bidder1);
    pool.bid{ value: 1 ether }(pId, 1, "");

    GovernancePool.Bid memory bid = pool.getBid(pId);
    assertEq(bid.endBlock, pc.endBlock);
    assertEq(bid.auctionEndBlock, pc.endBlock - poolCfg.auctionCloseBlocks);

    // bidders should post a bid amount larger than the last one
    uint256 bidAmount = pool.minBidAmount(pId);
    vm.roll(bid.auctionEndBlock - poolCfg.timeBuffer);
    uint256 bidBlock = block.number;
    pool.bid{ value: bidAmount }(pId, 0, "");

    // should extend by time buffer up until the cast window
    uint256 finalBlock = bid.endBlock - poolCfg.castWindow;
    uint256 i;
    while (bid.auctionEndBlock < finalBlock) {
      i = i + 1;
      bid = pool.getBid(pId);

      uint256 expected = bidBlock + poolCfg.timeBuffer;
      if (expected > bid.endBlock - poolCfg.castWindow) {
        expected = bid.endBlock - poolCfg.castWindow;
      }

      assertEq(bid.auctionEndBlock, expected);

      vm.roll(bidBlock + poolCfg.timeBuffer - 1);
      bidAmount = pool.minBidAmount(pId);

      if (bid.auctionEndBlock == finalBlock) {
        // auction has ended
        vm.expectRevert();
      }

      bidBlock = block.number;
      pool.bid{ value: bidAmount }(pId, 0, "");
    }

    assertEq(bid.auctionEndBlock, finalBlock);
  }

  function testIsRefundableIfExpired() public {
    NounsToken nt = NounsToken(NOUNS_TOKEN);
    NounsDAOExecutor timelock = NounsDAOExecutor(payable(NOUNS_EXECUTOR));
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator = nouners[1];

    ModuleConfig.Config memory poolCfg = pool.getConfig();

    vm.prank(delegator);
    nt.delegate(poolCfg.base);

    NounsDAOLogicV2 nounsDAO = NounsDAOLogicV2(payable(NOUNS_GOVERNOR));
    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    // bidders should post a bid amount larger than the last one
    uint256 bidAmount = pool.minBidAmount(pId);
    vm.roll(pc.endBlock - poolCfg.auctionCloseBlocks - poolCfg.timeBuffer);
    pool.bid{ value: bidAmount }(pId, 0, "");

    vm.roll(block.number + poolCfg.timeBuffer + 1);
    pool.castVote(pId);

    pc = nounsDAO.proposals(pId);
    vm.roll(pc.endBlock - 1);
    _env.PassProp(pId, vm);
    pc = nounsDAO.proposals(pId);

    vm.roll(pc.endBlock + 1000);

    vm.expectRevert();
    pool.claimRefund(pId);

    NounsDAOStorageV1Adjusted.ProposalState state = nounsDAO.state(pId);
    assertEq(uint256(state), 4);
    nounsDAO.queue(pId);

    pc = nounsDAO.proposals(pId);
    vm.warp(pc.eta + timelock.GRACE_PERIOD() + 1);

    state = nounsDAO.state(pId);
    assertEq(uint256(state), 6); // is expired state
    pool.claimRefund(pId);
  }

  function testMigrationPropIdBids() public {
    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator = nouners[1];

    ModuleConfig.Config memory poolCfg = pool.getConfig();

    vm.prank(delegator);
    nt.delegate(poolCfg.base);

    NounsDAOLogicV2 nounsDAO = NounsDAOLogicV2(payable(NOUNS_GOVERNOR));
    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    // migration prop id is not inclusive
    vm.prank(poolCfg.base);
    pool.setMigrationPropId(pId + 1);

    // bidders should post a bid amount larger than the last one
    uint256 bidAmount = pool.minBidAmount(pId);
    vm.roll(pc.endBlock - poolCfg.auctionCloseBlocks - poolCfg.timeBuffer);

    vm.expectRevert(GovernancePool.BidNoAuction.selector);
    pool.bid{ value: bidAmount }(pId, 0, "");

    // migration prop id is not inclusive
    vm.prank(poolCfg.base);
    pool.setMigrationPropId(pId);
    pool.bid{ value: bidAmount }(pId, 0, "");
  }

  function testConfig() public {
    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator = nouners[1];
    ModuleConfig.Config memory poolCfg = pool.getConfig();

    vm.prank(delegator);
    nt.delegate(poolCfg.base);

    // only owner
    vm.expectRevert();
    pool.setFee(10, owner);

    // fee cannot increase
    vm.expectRevert();
    vm.prank(poolCfg.base);
    pool.setFee(1000, owner);

    vm.prank(poolCfg.base);
    pool.setFee(100, owner);

    // cannot have empty recipient if feeBPS not 0
    vm.prank(poolCfg.base);
    vm.expectRevert();
    pool.setFee(50, address(0));

    vm.prank(poolCfg.base);
    pool.setFee(0, address(0));

    // can still cast votes w/ 0 fee
    NounsDAOLogicV2 nounsDAO = NounsDAOLogicV2(payable(NOUNS_GOVERNOR));
    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    // bidders should post a bid amount larger than the last one
    uint256 bidAmount = pool.minBidAmount(pId);
    vm.roll(pc.endBlock - poolCfg.auctionCloseBlocks - poolCfg.timeBuffer);
    pool.bid{ value: bidAmount }(pId, 0, "");

    vm.roll(block.number + poolCfg.timeBuffer * 2);
    pool.castVote(pId);

    // auction settings
    vm.expectRevert(); // only owner
    pool.setAuctionSettings(25, 400);

    vm.prank(poolCfg.base);
    pool.setAuctionSettings(25, 400);

    vm.expectRevert();
    vm.prank(poolCfg.base); // cannot have close blocks less than cast window
    pool.setAuctionSettings(0, poolCfg.castWindow - 5);

    // migration propid
    vm.expectRevert();
    pool.setMigrationPropId(100);

    vm.prank(poolCfg.base);
    pool.setMigrationPropId(100);
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
