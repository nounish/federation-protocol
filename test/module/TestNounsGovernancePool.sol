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

// Wraps veto functionality
interface Vetoer {
  function vetoer() external view returns (address);
  function veto(uint256) external;
}

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

    NounsFactory.PoolConfig memory fCfg =
      NounsFactory.PoolConfig(address(baseWallet), NOUNS_GOVERNOR, NOUNS_TOKEN, 0.1 ether, 5);
    pool = NounsPool(poolFactory.clone(fCfg, 150, 0.01 ether, "hello world"));
    baseWallet.setModule(address(pool), true);

    uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
    vm.selectFork(mainnetFork);
    vm.rollFork(17131180);
    _env = new TestEnv(vm);
  }

  function testInitializer() public {
    // test reinit reverts; modules should only be initiated once
    poolCfg = ModuleConfig.Config(
      address(0),
      NOUNS_GOVERNOR,
      NOUNS_TOKEN,
      owner,
      0.1 ether,
      5,
      5,
      150,
      0.01 ether,
      250,
      80 gwei,
      0,
      address(0),
      address(0),
      address(0),
      0,
      ""
    );

    vm.expectRevert();
    pool.init(abi.encode(poolCfg));

    // validation checks
    NounsFactory.PoolConfig memory fCfg =
      NounsFactory.PoolConfig(address(baseWallet), address(0), NOUNS_TOKEN, 0.1 ether, 5);

    vm.expectRevert(GovernancePool.InitExternalDAONotSet.selector);
    NounsPool poolTestInit = NounsPool(poolFactory.clone(fCfg, 150, 0.01 ether, ""));

    fCfg = NounsFactory.PoolConfig(address(baseWallet), NOUNS_GOVERNOR, address(0), 0.1 ether, 5);
    vm.expectRevert(GovernancePool.InitExternalTokenNotSet.selector);
    poolTestInit = NounsPool(poolFactory.clone(fCfg, 150, 0.01 ether, ""));

    fCfg = NounsFactory.PoolConfig(address(0), NOUNS_GOVERNOR, NOUNS_TOKEN, 0.1 ether, 5);
    vm.expectRevert(GovernancePool.InitBaseWalletNotSet.selector);
    poolTestInit = NounsPool(poolFactory.clone(fCfg, 150, 0.01 ether, ""));

    // castWindow should default to 150 if not set and should not revert
    fCfg = NounsFactory.PoolConfig(address(baseWallet), NOUNS_GOVERNOR, NOUNS_TOKEN, 0.1 ether, 5);
    poolTestInit = NounsPool(poolFactory.clone(fCfg, 0, 0.01 ether, "hello world hello world"));
  }

  function testBidPropConditions() public {
    NounsDAOStorageV1Adjusted nounsDAO = NounsDAOStorageV1Adjusted(NOUNS_GOVERNOR);
    uint256 latestPropId = nounsDAO.proposalCount();

    // should revert if prop does not exist
    vm.expectRevert(bytes("NounsDAO::state: invalid proposal id"));
    pool.bid{ value: 1 ether }(999 ether, 1);

    ModuleConfig.Config memory cfg = pool.getConfig();
    assertEq(cfg.reservePrice, 0.1 ether);
    // should revert if prop voting period is not active
    vm.expectRevert(GovernancePool.BidProposalNotActive.selector);
    pool.bid{ value: 1 ether }(1, 1);

    // should revert on invalid support
    vm.expectRevert(GovernancePool.BidInvalidSupport.selector);
    pool.bid{ value: 1 ether }(latestPropId, 3);

    // should revert if reserve price not met
    vm.expectRevert(GovernancePool.BidReserveNotMet.selector);
    pool.bid{ value: cfg.reservePrice - 0.01 ether }(latestPropId, 0);
  }

  function testCreateBid() public {
    // ensure bid is created
    vm.prank(bidder1);
    pool.bid{ value: 1 ether }(270, 1);

    NounsGovernanceV2 nounsDAO = NounsGovernanceV2(NOUNS_GOVERNOR);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(270);
    GovernancePool.Bid memory bid = pool.getBid(270);
    assertEq(bid.amount, 1 ether);
    assertEq(bid.creationBlock, pc.creationBlock);
    assertEq(bid.bidder, bidder1);
    assertEq(bid.support, 1);
    assertEq(bid.endBlock, pc.endBlock);

    // bidders should post a bid amount larger than the last one
    uint256 bidAmount = pool.minBidAmount(270);
    assert(bidAmount > 1 ether);

    vm.prank(bidder2);
    vm.expectRevert(GovernancePool.BidTooLow.selector);
    pool.bid{ value: bidAmount - 1 }(270, 0);

    vm.prank(bidder2);
    uint256 prevBalance = bidder1.balance;
    pool.bid{ value: bidAmount }(270, 0);
    uint256 postBalance = bidder1.balance;

    // last bidder should be refunded their eth
    assertEq(postBalance - prevBalance, 1 ether);
  }

  function testVoteCast() public {
    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator = nouners[1];

    ModuleConfig.Config memory cfg = pool.getConfig();

    vm.prank(delegator);
    nt.delegate(cfg.base);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsGovernanceV2 nounsDAO = NounsGovernanceV2(NOUNS_GOVERNOR);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    vm.roll(pc.startBlock + 10);
    pool.bid{ value: 1 ether }(pId, 1);

    // move into the execution window
    vm.roll((pc.endBlock - cfg.castWindow));
    pool.castVote(pId);

    // cannot be cast if already executed
    vm.roll(block.number + 10);
    vm.expectRevert();
    pool.castVote(pId);

    // ensure no one can bid on this prop anymore since the vote has been cast
    vm.expectRevert();
    pool.bid{ value: 2 ether }(pId, 0);
    vm.roll(pc.endBlock + 10); // let prop expire

    // cannot be cast if voting is closed
    pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    pc = nounsDAO.proposals(pId);

    // reverts if no bid placed but in window
    vm.roll((pc.endBlock - cfg.castWindow));
    vm.expectRevert(GovernancePool.CastVoteBidDoesNotExist.selector);
    pool.castVote(pId);

    // move outside the execution window
    pool.bid{ value: 1 ether }(pId, 1);
    vm.roll(pc.endBlock + 10);

    vm.expectRevert();
    pool.castVote(pId);

    pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    pc = nounsDAO.proposals(pId);

    vm.roll(pc.startBlock + 10);
    pool.bid{ value: 1 ether }(pId, 1);
    vm.roll(pc.endBlock - cfg.castWindow);

    // test refunds gas and tips
    uint256 preBalance = address(tx.origin).balance;
    vm.recordLogs();
    pool.castVote(pId);
    Vm.Log[] memory entries = vm.getRecordedLogs();

    uint256 postBalance = address(tx.origin).balance;
    assertEq(postBalance - preBalance, cfg.tip);

    uint256 feeAmount;
    uint256 refundAndTipAmount;
    for (uint256 i = 0; i < entries.length; i++) {
      bytes32 e = entries[i].topics[0];
      if (e == keccak256("ProtocolFeeApplied(address,uint256)")) {
        feeAmount = abi.decode(entries[i].data, (uint256));
      } else if (e == keccak256("GasRefundWithTip(address,uint256,uint256)")) {
        (uint256 amount,) = abi.decode(entries[i].data, (uint256, uint256));
        refundAndTipAmount = amount;
      }
    }

    assert(feeAmount > 0);
    assert(refundAndTipAmount > 0);

    // ensures pool amount has the gas refund and tip deducted
    GovernancePool.Bid memory bid = pool.getBid(pId);
    assertEq(bid.remainingAmount, 1 ether - (refundAndTipAmount + feeAmount));
  }

  function testVoteCastLateBid() public {
    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator = nouners[1];

    ModuleConfig.Config memory cfg = pool.getConfig();

    vm.prank(delegator);
    nt.delegate(cfg.base);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsGovernanceV2 nounsDAO = NounsGovernanceV2(NOUNS_GOVERNOR);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    vm.roll(pc.startBlock + 10);

    // move into the execution window
    uint256 blockInCastWindow = pc.endBlock - cfg.castWindow;
    vm.roll(blockInCastWindow + 10);

    // bid, wait cast blocks to pass, then cast vote
    pool.bid{ value: pool.minBidAmount(pId) }(pId, 1);

    // auction has ended, we should not allow further bids since vote will be cast
    vm.expectRevert();
    pool.bid{ value: 1 ether }(pId, 1);

    vm.roll(block.number + 2);
    pool.castVote(pId);

    // cannot be cast if already executed
    vm.roll(block.number + 10);
    vm.expectRevert();
    pool.castVote(pId);

    // ensure no one can bid on this prop anymore since the vote has been cast
    vm.expectRevert();
    pool.bid{ value: 2 ether }(pId, 0);
    vm.roll(pc.endBlock + 10); // let prop expire

    // cannot be cast if voting is closed
    pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    pc = nounsDAO.proposals(pId);

    // reverts if no bid placed but in window
    vm.roll((pc.endBlock - cfg.castWindow));
    vm.expectRevert(GovernancePool.CastVoteBidDoesNotExist.selector);
    pool.castVote(pId);

    // move outside the execution window
    pool.bid{ value: 1 ether }(pId, 1);
    vm.roll(pc.endBlock + 10);

    vm.expectRevert();
    pool.castVote(pId);

    pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    pc = nounsDAO.proposals(pId);

    vm.roll(pc.startBlock + 10);
    pool.bid{ value: 1 ether }(pId, 1);
    vm.roll(pc.endBlock - cfg.castWindow);

    // test refunds gas and tips
    uint256 preBalance = address(tx.origin).balance;
    vm.recordLogs();
    pool.castVote(pId);
    Vm.Log[] memory entries = vm.getRecordedLogs();

    uint256 postBalance = address(tx.origin).balance;
    assertEq(postBalance - preBalance, cfg.tip);

    uint256 feeAmount;
    uint256 refundAndTipAmount;
    for (uint256 i = 0; i < entries.length; i++) {
      bytes32 e = entries[i].topics[0];
      if (e == keccak256("ProtocolFeeApplied(address,uint256)")) {
        feeAmount = abi.decode(entries[i].data, (uint256));
      } else if (e == keccak256("GasRefundWithTip(address,uint256,uint256)")) {
        (uint256 amount,) = abi.decode(entries[i].data, (uint256, uint256));
        refundAndTipAmount = amount;
      }
    }

    assert(feeAmount > 0);
    assert(refundAndTipAmount > 0);

    // ensures pool amount has the gas refund and tip deducted
    GovernancePool.Bid memory bid = pool.getBid(pId);
    assertEq(bid.remainingAmount, 1 ether - (refundAndTipAmount + feeAmount));
  }

  function testNoAtomicBidAndCasts() public {
    AtomicBidAndCast atomic = new AtomicBidAndCast();
    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator = nouners[1];

    ModuleConfig.Config memory cfg = pool.getConfig();

    vm.prank(delegator);
    nt.delegate(cfg.base);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsGovernanceV2 nounsDAO = NounsGovernanceV2(NOUNS_GOVERNOR);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    // move into the execution window
    vm.roll((pc.endBlock - cfg.castWindow));
    vm.expectRevert(GovernancePool.CastVoteMustWait.selector);
    atomic.bidAndCast{ value: 1 ether }(address(pool), pId, 1);

    pool.bid{ value: 99 ether }(pId, 1);
  }

  function testRefundOnVeto() public {
    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator = nouners[1];

    ModuleConfig.Config memory cfg = pool.getConfig();

    vm.prank(delegator);
    nt.delegate(cfg.base);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsGovernanceV2 nounsDAO = NounsGovernanceV2(NOUNS_GOVERNOR);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    // move into the execution window
    vm.roll((pc.endBlock - cfg.castWindow));
    vm.prank(bidder1);
    pool.bid{ value: 69.42 ether }(pId, 1);
    vm.roll(block.number + cfg.castWindow / 2);

    pool.castVote(pId);

    address cVetoer = Vetoer(NOUNS_GOVERNOR).vetoer();
    vm.prank(cVetoer);
    Vetoer(address(nounsDAO)).veto(pId);

    vm.expectRevert(GovernancePool.ClaimOnlyBidder.selector);
    pool.claimRefund(pId);

    uint256 beforeBal = bidder1.balance;
    vm.prank(bidder1);
    pool.claimRefund(pId);
    uint256 afterBal = bidder1.balance;

    // bid will be partially refunded. gas refund and tip will be deducted as well
    // as any protocol fee
    assertEq(afterBal - beforeBal, pool.getBid(pId).remainingAmount);

    // test already refunded
    vm.prank(bidder1);
    vm.expectRevert(GovernancePool.ClaimAlreadyRefunded.selector);
    pool.claimRefund(pId);
  }

  function testClaimRefundAfterVoteCast() public {
    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator = nouners[1];

    ModuleConfig.Config memory cfg = pool.getConfig();

    vm.prank(delegator);
    nt.delegate(cfg.base);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsGovernanceV2 nounsDAO = NounsGovernanceV2(NOUNS_GOVERNOR);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    // move into the execution window
    vm.roll((pc.endBlock - cfg.castWindow));
    vm.prank(bidder1);
    pool.bid{ value: 69.42 ether }(pId, 1);
    vm.roll(block.number + 100);

    pool.castVote(pId);

    // should reject a refund since the prop is still active
    vm.prank(bidder1);
    vm.expectRevert(GovernancePool.ClaimNotRefundable.selector);
    pool.claimRefund(pId);

    vm.roll(pc.endBlock + 100);

    // should reject a refund if the vote is already cast
    vm.prank(bidder1);
    vm.expectRevert(GovernancePool.ClaimNotRefundable.selector);
    pool.claimRefund(pId);
  }

  function testWithdraw() public {
    _registerMockProver();

    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator1 = nouners[1];
    address delegator2 = nouners[2];
    address delegator3 = nouners[3];

    uint256 n1Balance = nt.balanceOf(delegator1);
    uint256 n2Balance = nt.balanceOf(delegator2);
    uint256 n3Balance = nt.balanceOf(delegator3);

    ModuleConfig.Config memory cfg = pool.getConfig();

    // update pool config to always succeed on proof validation in withdraw
    PassMockValidator pmv = new PassMockValidator();
    ModuleConfig.Config memory pcfg = ModuleConfig.Config(
      address(baseWallet),
      NOUNS_GOVERNOR,
      NOUNS_TOKEN,
      owner,
      0.1 ether,
      5,
      5,
      150,
      0.01 ether,
      250,
      80 gwei,
      0,
      RELIQUARY,
      DELEGATE_CASH,
      address(pmv),
      0,
      ""
    );

    vm.prank(cfg.base);
    pool.setConfig(pcfg);

    // it's a pool party! ~~
    vm.prank(delegator1);
    nt.delegate(cfg.base);

    vm.prank(delegator2);
    nt.delegate(cfg.base);

    vm.prank(delegator3);
    nt.delegate(cfg.base);

    uint256 totalVotes = nt.getCurrentVotes(cfg.base);
    assertEq(totalVotes, n1Balance + n2Balance + n3Balance);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsGovernanceV2 nounsDAO = NounsGovernanceV2(NOUNS_GOVERNOR);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    // move into the execution window
    vm.roll((pc.endBlock - cfg.castWindow));
    vm.prank(bidder1);
    pool.bid{ value: 20 ether }(pId, 1);
    vm.roll(block.number + 100);

    vm.prank(bidder1);
    pool.castVote(pId);
    uint256 amountToWithdraw = pool.getBid(pId).remainingAmount;

    // ===================
    // prep done; now do the things

    // set proof data on mock prover
    bytes[] memory proofData = new bytes[](2);

    // first proof is token balance
    bytes memory b = new bytes(32);
    assembly ("memory-safe") {
      mstore(add(b, 32), n1Balance)
    }
    proofData[0] = b;

    // second proof is the address nouns were delegated to
    proofData[1] = abi.encodePacked(cfg.base);
    mp.setProofData(proofData);

    // build fn arguments for withdraw
    uint256[] memory pIds = new uint256[](1);
    pIds[0] = pId;

    uint256[] memory fees = new uint256[](1);
    fees[0] = 0;

    bytes[] memory proofBatches = new bytes[](1);
    proofBatches[0] = abi.encode(proofData);

    uint256 balancePoolBefore = address(pool).balance;
    uint256 balanceBefore = delegator1.balance;

    // bid cannot be withdrawn if the prop is still active (gives time for cancel or veto)
    vm.prank(delegator1);
    vm.expectRevert(GovernancePool.WithdrawPropIsActive.selector);
    uint256 totalWithdrawn = pool.withdraw(delegator1, address(mp), pIds, fees, proofBatches);

    // should revert if the prover is not registered with the reliquary
    vm.expectRevert();
    vm.prank(delegator1);
    pool.withdraw(delegator1, vm.addr(0x420), pIds, fees, proofBatches);

    vm.roll(pc.endBlock + 10);
    vm.prank(delegator1);
    totalWithdrawn = pool.withdraw(delegator1, address(mp), pIds, fees, proofBatches);

    uint256 balanceAfter = delegator1.balance;
    uint256 balancePoolAfter = address(pool).balance;
    assertEq(balanceAfter - balanceBefore, balancePoolBefore - balancePoolAfter);

    // ===== we do a little copy pasta =====
    // now everyone else withdraw

    // set proof data on mock prover
    proofData = new bytes[](2);
    b = new bytes(32);
    assembly ("memory-safe") {
      mstore(add(b, 32), n2Balance)
    }
    proofData[0] = b;

    // second proof is the address nouns were delegated to
    proofData[1] = abi.encodePacked(cfg.base);
    mp.setProofData(proofData);

    // build fn arguments for withdraw
    pIds = new uint256[](1);
    pIds[0] = pId;

    fees = new uint256[](1);
    fees[0] = 0;

    proofBatches = new bytes[](1);
    proofBatches[0] = abi.encode(proofData);

    vm.prank(delegator2);
    totalWithdrawn += pool.withdraw(delegator2, address(mp), pIds, fees, proofBatches);

    proofData = new bytes[](2);
    b = new bytes(32);
    assembly ("memory-safe") {
      mstore(add(b, 32), n3Balance)
    }
    proofData[0] = b;

    // second proof is the address nouns were delegated to
    proofData[1] = abi.encodePacked(cfg.base);
    mp.setProofData(proofData);

    // build fn arguments for withdraw
    pIds = new uint256[](1);
    pIds[0] = pId;

    fees = new uint256[](1);
    fees[0] = 0;

    proofBatches = new bytes[](1);
    proofBatches[0] = abi.encode(proofData);

    vm.prank(delegator3);
    totalWithdrawn += pool.withdraw(delegator3, address(mp), pIds, fees, proofBatches);

    assertEq(amountToWithdraw, totalWithdrawn, "all proceeds should be withdrawn");
    assertEq(address(pool).balance, 0);
  }

  function testWithdrawDelegate() public {
    _registerMockProver();

    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator1 = nouners[1];
    address delegator2 = nouners[2];

    // register a dcash delegate that can withdraw on the noun owners behalf
    IDelegationRegistry dr = IDelegationRegistry(DELEGATE_CASH);
    vm.prank(delegator1);
    dr.delegateForAll(proposer, true);

    // update pool config to always succeed on proof validation in withdraw
    ModuleConfig.Config memory cfg = pool.getConfig();
    PassMockValidator pmv = new PassMockValidator();
    ModuleConfig.Config memory pcfg = ModuleConfig.Config(
      address(baseWallet),
      NOUNS_GOVERNOR,
      NOUNS_TOKEN,
      owner,
      0.1 ether,
      5,
      5,
      150,
      0.01 ether,
      250,
      80 gwei,
      0,
      RELIQUARY,
      DELEGATE_CASH,
      address(pmv),
      0,
      ""
    );

    vm.prank(cfg.base);
    pool.setConfig(pcfg);

    // it's a pool party! ~~
    vm.prank(delegator1);
    nt.delegate(cfg.base);

    vm.prank(delegator2);
    nt.delegate(cfg.base);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsGovernanceV2 nounsDAO = NounsGovernanceV2(NOUNS_GOVERNOR);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    // move into the execution window and cast a vote
    vm.roll((pc.endBlock - cfg.castWindow));
    vm.prank(bidder1);
    pool.bid{ value: 15 ether }(pId, 1);

    vm.roll(block.number + 100);
    pool.castVote(pId);
    vm.roll(pc.endBlock + 10);

    // set proof data on mock prover
    bytes[] memory proofData = new bytes[](2);

    // first proof is token balance
    uint256 d1 = nt.balanceOf(delegator1);
    bytes memory b = new bytes(32);
    assembly ("memory-safe") {
      mstore(add(b, 32), d1)
    }
    proofData[0] = b;

    // second proof is the address nouns were delegated to
    proofData[1] = abi.encodePacked(cfg.base);
    mp.setProofData(proofData);

    // build fn arguments for withdraw
    uint256[] memory pIds = new uint256[](1);
    pIds[0] = pId;

    uint256[] memory fees = new uint256[](1);
    fees[0] = 0;

    bytes[] memory proofBatches = new bytes[](1);
    proofBatches[0] = abi.encode(proofData);

    // should fail since caller is not the delegate for the token owner
    vm.prank(bidder2);
    vm.expectRevert(GovernancePool.WithdrawDelegateOrOwnerOnly.selector);
    pool.withdraw(delegator1, address(mp), pIds, fees, proofBatches);

    // delegate cash verification; ensure that someone can withdraw if they
    // have been registered as the delegate in the dcash registry
    // delegator1 assigned proposer address as eligible to kick off withdrawal for them
    vm.prank(proposer);
    pool.withdraw(delegator1, address(mp), pIds, fees, proofBatches);

    // try to withdraw with owner account
    vm.expectRevert(GovernancePool.WithdrawAlreadyClaimed.selector);
    vm.prank(delegator1);
    pool.withdraw(delegator1, address(mp), pIds, fees, proofBatches);
  }

  function testWithdrawDelegateWithVault() public {
    _registerMockProver();

    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator1 = nouners[1];
    address delegator2 = nouners[2];

    // register a dcash delegate that can withdraw on the noun owners behalf
    IDelegationRegistry dr = IDelegationRegistry(DELEGATE_CASH);
    vm.prank(delegator1);
    dr.delegateForAll(proposer, true);

    // update pool config to always succeed on proof validation in withdraw
    ModuleConfig.Config memory cfg = pool.getConfig();
    PassMockValidator pmv = new PassMockValidator();
    ModuleConfig.Config memory pcfg = ModuleConfig.Config(
      address(baseWallet),
      NOUNS_GOVERNOR,
      NOUNS_TOKEN,
      owner,
      0.1 ether,
      5,
      5,
      150,
      0.01 ether,
      250,
      80 gwei,
      0,
      RELIQUARY,
      DELEGATE_CASH,
      address(pmv),
      0,
      ""
    );

    vm.prank(cfg.base);
    pool.setConfig(pcfg);

    // it's a pool party! ~~
    vm.prank(delegator1);
    nt.delegate(cfg.base);

    vm.prank(delegator2);
    nt.delegate(cfg.base);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsGovernanceV2 nounsDAO = NounsGovernanceV2(NOUNS_GOVERNOR);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    // move into the execution window and cast a vote
    vm.roll((pc.endBlock - cfg.castWindow));
    vm.prank(bidder1);
    pool.bid{ value: 15 ether }(pId, 1);

    vm.roll(block.number + 100);
    pool.castVote(pId);
    vm.roll(pc.endBlock + 10);

    // set proof data on mock prover
    bytes[] memory proofData = new bytes[](2);

    // first proof is token balance
    uint256 d1 = nt.balanceOf(delegator1);
    bytes memory b = new bytes(32);
    assembly ("memory-safe") {
      mstore(add(b, 32), d1)
    }
    proofData[0] = b;

    // second proof is the address nouns were delegated to
    proofData[1] = abi.encodePacked(cfg.base);
    mp.setProofData(proofData);

    // build fn arguments for withdraw
    uint256[] memory pIds = new uint256[](1);
    pIds[0] = pId;

    uint256[] memory fees = new uint256[](1);
    fees[0] = 0;

    bytes[] memory proofBatches = new bytes[](1);
    proofBatches[0] = abi.encode(proofData);

    // delegate cash verification; ensure that someone can withdraw if they
    // have been registered as the delegate in the dcash registry
    // delegator1 assigned proposer address as eligible to kick off withdrawal for them
    vm.prank(delegator1);
    pool.withdraw(delegator1, address(mp), pIds, fees, proofBatches);
  }

  function testWithdrawNoBid() public {
    _registerMockProver();

    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator1 = nouners[1];
    address delegator2 = nouners[2];

    // update pool config to always succeed on proof validation in withdraw
    ModuleConfig.Config memory cfg = pool.getConfig();
    PassMockValidator pmv = new PassMockValidator();
    ModuleConfig.Config memory pcfg = ModuleConfig.Config(
      address(baseWallet),
      NOUNS_GOVERNOR,
      NOUNS_TOKEN,
      owner,
      0.1 ether,
      5,
      5,
      150,
      0.01 ether,
      250,
      80 gwei,
      0,
      RELIQUARY,
      DELEGATE_CASH,
      address(pmv),
      0,
      ""
    );

    vm.prank(cfg.base);
    pool.setConfig(pcfg);

    // it's a pool party! ~~
    vm.prank(delegator1);
    nt.delegate(cfg.base);

    vm.prank(delegator2);
    nt.delegate(cfg.base);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);

    // set proof data on mock prover
    bytes[] memory proofData = new bytes[](2);

    // first proof is token balance
    uint256 d1 = nt.balanceOf(delegator1);
    bytes memory b = new bytes(32);
    assembly ("memory-safe") {
      mstore(add(b, 32), d1)
    }
    proofData[0] = b;

    // second proof is the address nouns were delegated to
    proofData[1] = abi.encodePacked(cfg.base);
    mp.setProofData(proofData);

    // build fn arguments for withdraw
    uint256[] memory pIds = new uint256[](1);
    pIds[0] = pId;

    uint256[] memory fees = new uint256[](1);
    fees[0] = 0;

    bytes[] memory proofBatches = new bytes[](1);
    proofBatches[0] = abi.encode(proofData);

    vm.prank(delegator1);
    vm.expectRevert(GovernancePool.WithdrawBidNotOffered.selector);
    pool.withdraw(delegator1, address(mp), pIds, fees, proofBatches);
  }

  function testWithdrawNotCast() public {
    _registerMockProver();

    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator1 = nouners[1];
    address delegator2 = nouners[2];

    // register a dcash delegate that can withdraw on the noun owners behalf
    IDelegationRegistry dr = IDelegationRegistry(DELEGATE_CASH);
    vm.prank(delegator1);
    dr.delegateForAll(proposer, true);

    // update pool config to always succeed on proof validation in withdraw
    ModuleConfig.Config memory cfg = pool.getConfig();
    PassMockValidator pmv = new PassMockValidator();
    ModuleConfig.Config memory pcfg = ModuleConfig.Config(
      address(baseWallet),
      NOUNS_GOVERNOR,
      NOUNS_TOKEN,
      owner,
      0.1 ether,
      5,
      5,
      150,
      0.01 ether,
      250,
      80 gwei,
      0,
      RELIQUARY,
      DELEGATE_CASH,
      address(pmv),
      0,
      ""
    );

    vm.prank(cfg.base);
    pool.setConfig(pcfg);

    // it's a pool party! ~~
    vm.prank(delegator1);
    nt.delegate(cfg.base);

    vm.prank(delegator2);
    nt.delegate(cfg.base);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsGovernanceV2 nounsDAO = NounsGovernanceV2(NOUNS_GOVERNOR);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    // move into the execution window and cast a vote
    vm.roll((pc.endBlock - cfg.castWindow));
    vm.prank(bidder1);
    pool.bid{ value: 15 ether }(pId, 1);

    // set proof data on mock prover
    bytes[] memory proofData = new bytes[](2);

    // first proof is token balance
    uint256 d1 = nt.balanceOf(delegator1);
    bytes memory b = new bytes(32);
    assembly ("memory-safe") {
      mstore(add(b, 32), d1)
    }
    proofData[0] = b;

    // second proof is the address nouns were delegated to
    proofData[1] = abi.encodePacked(cfg.base);
    mp.setProofData(proofData);

    // build fn arguments for withdraw
    uint256[] memory pIds = new uint256[](1);
    pIds[0] = pId;

    uint256[] memory fees = new uint256[](1);
    fees[0] = 0;

    bytes[] memory proofBatches = new bytes[](1);
    proofBatches[0] = abi.encode(proofData);

    vm.prank(delegator1);
    vm.expectRevert(GovernancePool.WithdrawVoteNotCast.selector);
    pool.withdraw(delegator1, address(mp), pIds, fees, proofBatches);
  }

  function testWithdrawAlreadyRefunded() public {
    _registerMockProver();

    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator1 = nouners[1];
    address delegator2 = nouners[2];

    // register a dcash delegate that can withdraw on the noun owners behalf
    IDelegationRegistry dr = IDelegationRegistry(DELEGATE_CASH);
    vm.prank(delegator1);
    dr.delegateForAll(proposer, true);

    // update pool config to always succeed on proof validation in withdraw
    ModuleConfig.Config memory cfg = pool.getConfig();
    PassMockValidator pmv = new PassMockValidator();
    ModuleConfig.Config memory pcfg = ModuleConfig.Config(
      address(baseWallet),
      NOUNS_GOVERNOR,
      NOUNS_TOKEN,
      owner,
      0.1 ether,
      5,
      5,
      150,
      0.01 ether,
      250,
      80 gwei,
      0,
      RELIQUARY,
      DELEGATE_CASH,
      address(pmv),
      0,
      ""
    );

    vm.prank(cfg.base);
    pool.setConfig(pcfg);

    // it's a pool party! ~~
    vm.prank(delegator1);
    nt.delegate(cfg.base);

    vm.prank(delegator2);
    nt.delegate(cfg.base);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsGovernanceV2 nounsDAO = NounsGovernanceV2(NOUNS_GOVERNOR);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    // move into the execution window and cast a vote
    vm.roll((pc.endBlock - cfg.castWindow));
    vm.prank(bidder1);
    pool.bid{ value: 15 ether }(pId, 1);
    vm.roll(pc.endBlock + 100);

    vm.prank(bidder1);
    pool.claimRefund(pId);

    // set proof data on mock prover
    bytes[] memory proofData = new bytes[](2);

    // first proof is token balance
    uint256 d1 = nt.balanceOf(delegator1);
    bytes memory b = new bytes(32);
    assembly ("memory-safe") {
      mstore(add(b, 32), d1)
    }
    proofData[0] = b;

    // second proof is the address nouns were delegated to
    proofData[1] = abi.encodePacked(cfg.base);
    mp.setProofData(proofData);

    // build fn arguments for withdraw
    uint256[] memory pIds = new uint256[](1);
    pIds[0] = pId;

    uint256[] memory fees = new uint256[](1);
    fees[0] = 0;

    bytes[] memory proofBatches = new bytes[](1);
    proofBatches[0] = abi.encode(proofData);

    vm.prank(delegator1);
    vm.expectRevert(GovernancePool.WithdrawBidRefunded.selector);
    pool.withdraw(delegator1, address(mp), pIds, fees, proofBatches);
  }

  function testWithdrawRevertIfCanceled() public {
    _registerMockProver();

    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator1 = nouners[1];
    address delegator2 = nouners[2];

    // register a dcash delegate that can withdraw on the noun owners behalf
    IDelegationRegistry dr = IDelegationRegistry(DELEGATE_CASH);
    vm.prank(delegator1);
    dr.delegateForAll(proposer, true);

    // update pool config to always succeed on proof validation in withdraw
    ModuleConfig.Config memory cfg = pool.getConfig();
    PassMockValidator pmv = new PassMockValidator();
    ModuleConfig.Config memory pcfg = ModuleConfig.Config(
      address(baseWallet),
      NOUNS_GOVERNOR,
      NOUNS_TOKEN,
      owner,
      0.1 ether,
      5,
      5,
      150,
      0.01 ether,
      250,
      80 gwei,
      0,
      RELIQUARY,
      DELEGATE_CASH,
      address(pmv),
      0,
      ""
    );

    vm.prank(cfg.base);
    pool.setConfig(pcfg);

    // it's a pool party! ~~
    vm.prank(delegator1);
    nt.delegate(cfg.base);

    vm.prank(delegator2);
    nt.delegate(cfg.base);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsDAOLogicV2 nounsDAO = NounsDAOLogicV2(payable(address(NOUNS_GOVERNOR)));
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    vm.roll((pc.endBlock - cfg.castWindow));
    vm.prank(bidder1);
    pool.bid{ value: 15 ether }(pId, 1);
    vm.roll(pc.endBlock - 10);

    vm.prank(proposer);
    nounsDAO.cancel(pId);
    vm.roll(pc.endBlock + 10);

    // set proof data on mock prover
    bytes[] memory proofData = new bytes[](2);

    // first proof is token balance
    uint256 d1 = nt.balanceOf(delegator1);
    bytes memory b = new bytes(32);
    assembly ("memory-safe") {
      mstore(add(b, 32), d1)
    }
    proofData[0] = b;

    // second proof is the address nouns were delegated to
    proofData[1] = abi.encodePacked(cfg.base);
    mp.setProofData(proofData);

    // build fn arguments for withdraw
    uint256[] memory pIds = new uint256[](1);
    pIds[0] = pId;

    uint256[] memory fees = new uint256[](1);
    fees[0] = 0;

    bytes[] memory proofBatches = new bytes[](1);
    proofBatches[0] = abi.encode(proofData);

    vm.prank(delegator1);
    vm.expectRevert(GovernancePool.WithdrawBidRefunded.selector);
    pool.withdraw(delegator1, address(mp), pIds, fees, proofBatches);
  }

  function testWithdrawRevertIfVeto() public {
    _registerMockProver();

    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator1 = nouners[1];
    address delegator2 = nouners[2];

    // register a dcash delegate that can withdraw on the noun owners behalf
    IDelegationRegistry dr = IDelegationRegistry(DELEGATE_CASH);
    vm.prank(delegator1);
    dr.delegateForAll(proposer, true);

    // update pool config to always succeed on proof validation in withdraw
    ModuleConfig.Config memory cfg = pool.getConfig();
    PassMockValidator pmv = new PassMockValidator();
    ModuleConfig.Config memory pcfg = ModuleConfig.Config(
      address(baseWallet),
      NOUNS_GOVERNOR,
      NOUNS_TOKEN,
      owner,
      0.1 ether,
      5,
      5,
      150,
      0.01 ether,
      250,
      80 gwei,
      0,
      RELIQUARY,
      DELEGATE_CASH,
      address(pmv),
      0,
      ""
    );

    vm.prank(cfg.base);
    pool.setConfig(pcfg);

    // it's a pool party! ~~
    vm.prank(delegator1);
    nt.delegate(cfg.base);

    vm.prank(delegator2);
    nt.delegate(cfg.base);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsDAOLogicV2 nounsDAO = NounsDAOLogicV2(payable(address(NOUNS_GOVERNOR)));
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    vm.roll((pc.endBlock - cfg.castWindow));
    vm.prank(bidder1);
    pool.bid{ value: 15 ether }(pId, 1);
    vm.roll(pc.endBlock - 10);

    address cVetoer = Vetoer(NOUNS_GOVERNOR).vetoer();
    vm.prank(cVetoer);
    Vetoer(address(nounsDAO)).veto(pId);
    vm.roll(pc.endBlock + 10);

    // set proof data on mock prover
    bytes[] memory proofData = new bytes[](2);

    // first proof is token balance
    uint256 d1 = nt.balanceOf(delegator1);
    bytes memory b = new bytes(32);
    assembly ("memory-safe") {
      mstore(add(b, 32), d1)
    }
    proofData[0] = b;

    // second proof is the address nouns were delegated to
    proofData[1] = abi.encodePacked(cfg.base);
    mp.setProofData(proofData);

    // build fn arguments for withdraw
    uint256[] memory pIds = new uint256[](1);
    pIds[0] = pId;

    uint256[] memory fees = new uint256[](1);
    fees[0] = 0;

    bytes[] memory proofBatches = new bytes[](1);
    proofBatches[0] = abi.encode(proofData);

    vm.prank(delegator1);
    vm.expectRevert(GovernancePool.WithdrawBidRefunded.selector);
    pool.withdraw(delegator1, address(mp), pIds, fees, proofBatches);
  }

  function testWithdrawNotDelegated() public {
    _registerMockProver();

    // ensure cannot withdraw any funds if nouns were not delegated at proposal
    // creation block
    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator = nouners[1];
    address fakeDelegator = nouners[3];
    uint256 n1Balance = nt.balanceOf(delegator);

    ModuleConfig.Config memory cfg = pool.getConfig();

    // update pool config to always succeed on proof validation in withdraw
    FailMockValidator fmv = new FailMockValidator();
    ModuleConfig.Config memory pcfg = ModuleConfig.Config(
      address(baseWallet),
      NOUNS_GOVERNOR,
      NOUNS_TOKEN,
      owner,
      0.1 ether,
      5,
      5,
      150,
      0.01 ether,
      250,
      80 gwei,
      0,
      RELIQUARY,
      DELEGATE_CASH,
      address(fmv),
      0,
      ""
    );

    vm.prank(cfg.base);
    pool.setConfig(pcfg);

    vm.prank(delegator);
    nt.delegate(cfg.base);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsGovernanceV2 nounsDAO = NounsGovernanceV2(NOUNS_GOVERNOR);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    // move into the execution window
    vm.roll((pc.endBlock - cfg.castWindow));
    vm.prank(bidder1);
    pool.bid{ value: 20 ether }(pId, 1);
    vm.roll(block.number + 100);
    pool.castVote(pId);
    vm.roll(pc.endBlock + 10);

    // set proof data on mock prover
    bytes[] memory proofData = new bytes[](2);

    // first proof is token balance
    bytes memory b = new bytes(32);
    assembly ("memory-safe") {
      mstore(add(b, 32), n1Balance)
    }
    proofData[0] = b;

    // second proof is the address nouns were delegated to
    proofData[1] = abi.encodePacked(cfg.base);
    mp.setProofData(proofData);

    // build fn arguments for withdraw
    uint256[] memory pIds = new uint256[](1);
    pIds[0] = pId;

    uint256[] memory fees = new uint256[](1);
    fees[0] = 0;

    bytes[] memory proofBatches = new bytes[](1);
    proofBatches[0] = abi.encode(proofData);

    vm.startPrank(fakeDelegator);
    vm.expectRevert(GovernancePool.WithdrawDelegateOrOwnerOnly.selector);
    pool.withdraw(delegator, address(mp), pIds, fees, proofBatches);

    // previously set fail proof validator because slots wouldn't be valid in the case where
    // the caller and token owner are the same but different from the proofs.
    // proofs are calculated against slots we validate so we know if they can be tied to the calling account
    vm.expectRevert(
      abi.encodeWithSelector(GovernancePool.WithdrawInvalidProof.selector, "balanceOf")
    );
    pool.withdraw(fakeDelegator, address(mp), pIds, fees, proofBatches);
  }

  function testWithdrawMultipleProps() public {
    _registerMockProver();

    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator1 = nouners[1];
    address delegator2 = nouners[2];
    address delegator3 = nouners[3];

    uint256 n1Balance = nt.balanceOf(delegator1);

    ModuleConfig.Config memory cfg = pool.getConfig();

    // update pool config to always succeed on proof validation in withdraw
    PassMockValidator pmv = new PassMockValidator();
    ModuleConfig.Config memory pcfg = ModuleConfig.Config(
      address(baseWallet),
      NOUNS_GOVERNOR,
      NOUNS_TOKEN,
      owner,
      1 wei,
      5,
      5,
      150,
      0.01 ether,
      250,
      80 gwei,
      0,
      RELIQUARY,
      DELEGATE_CASH,
      address(pmv),
      0,
      ""
    );

    vm.prank(cfg.base);
    pool.setConfig(pcfg);

    // it's a pool party! ~~
    vm.prank(delegator1);
    nt.delegate(cfg.base);

    vm.prank(delegator2);
    nt.delegate(cfg.base);

    vm.prank(delegator3);
    nt.delegate(cfg.base);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsDAOLogicV2 nounsDAO = NounsDAOLogicV2(payable(NOUNS_GOVERNOR));
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    // move into the execution window
    vm.roll((pc.endBlock - cfg.castWindow));
    vm.prank(bidder1);
    pool.bid{ value: 1 gwei }(pId, 1);
    vm.roll(block.number + 100);
    pool.castVote(pId);
    vm.roll(pc.endBlock + 100);
    vm.roll(block.number + 500);

    uint256 firstpId = pId;
    pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    pc = nounsDAO.proposals(pId);
    vm.roll((pc.endBlock - cfg.castWindow));
    vm.prank(bidder1);
    pool.bid{ value: 6 ether }(pId, 1);
    vm.roll(block.number + 100);
    pool.castVote(pId);

    pc = nounsDAO.proposals(pId);
    vm.roll(pc.endBlock + 10);

    // ===================
    // prep done; now do the things

    // set proof data on mock prover
    bytes[] memory proofData = new bytes[](2);

    // first proof is token balance
    bytes memory b = new bytes(32);
    assembly ("memory-safe") {
      mstore(add(b, 32), n1Balance)
    }
    proofData[0] = b;

    // second proof is the address nouns were delegated to
    proofData[1] = abi.encodePacked(cfg.base);
    mp.setProofData(proofData);

    // build fn arguments for withdraw
    uint256[] memory pIds = new uint256[](2);
    pIds[0] = firstpId;
    pIds[1] = pId;

    uint256[] memory fees = new uint256[](2);
    fees[0] = 0;
    fees[1] = 0;

    bytes[] memory proofBatches = new bytes[](2);
    proofBatches[0] = abi.encode(proofData);
    proofBatches[1] = abi.encode(proofData);

    vm.prank(delegator1);
    pool.withdraw(delegator1, address(mp), pIds, fees, proofBatches);
  }

  function testInvalidWithdrawProof() public {
    _registerMockProver();

    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator = nouners[1];
    uint256 n1Balance = nt.balanceOf(delegator);

    ModuleConfig.Config memory cfg = pool.getConfig();

    // update pool config to always succeed on proof validation in withdraw
    FailMockValidator fmv = new FailMockValidator();
    ModuleConfig.Config memory pcfg = ModuleConfig.Config(
      address(baseWallet),
      NOUNS_GOVERNOR,
      NOUNS_TOKEN,
      owner,
      0.1 ether,
      5,
      5,
      150,
      0.01 ether,
      250,
      80 gwei,
      0,
      RELIQUARY,
      DELEGATE_CASH,
      address(fmv),
      0,
      ""
    );

    vm.prank(cfg.base);
    pool.setConfig(pcfg);

    vm.prank(delegator);
    nt.delegate(cfg.base);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsGovernanceV2 nounsDAO = NounsGovernanceV2(NOUNS_GOVERNOR);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    // move into the execution window
    vm.roll((pc.endBlock - cfg.castWindow));
    vm.prank(bidder1);
    pool.bid{ value: 20 ether }(pId, 1);
    vm.roll(block.number + 100);
    pool.castVote(pId);

    // set proof data on mock prover
    bytes[] memory proofData = new bytes[](2);

    // first proof is token balance
    bytes memory b = new bytes(32);
    assembly ("memory-safe") {
      mstore(add(b, 32), n1Balance)
    }
    proofData[0] = b;

    // second proof is the address nouns were delegated to
    proofData[1] = abi.encodePacked(cfg.base);
    mp.setProofData(proofData);

    // build fn arguments for withdraw
    uint256[] memory pIds = new uint256[](1);
    pIds[0] = pId;

    uint256[] memory fees = new uint256[](1);
    fees[0] = 0;

    bytes[] memory proofBatches = new bytes[](1);
    proofBatches[0] = abi.encode(proofData);

    vm.startPrank(delegator);
    vm.expectRevert(
      abi.encodeWithSelector(GovernancePool.WithdrawInvalidProof.selector, "balanceOf")
    );
    vm.roll(pc.endBlock + 10);
    pool.withdraw(delegator, address(mp), pIds, fees, proofBatches);
  }

  function testCannotBidInCastWindow() public {
    ModuleConfig.Config memory cfg = pool.getConfig();

    NounsToken nt = NounsToken(NOUNS_TOKEN);
    address[5] memory nouners = _env.SetupNouners(vm);
    address proposer = nouners[0];
    address delegator = nouners[1];
    vm.prank(delegator);
    nt.delegate(cfg.base);

    uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
    NounsGovernanceV2 nounsDAO = NounsGovernanceV2(NOUNS_GOVERNOR);
    NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

    // ensure bid is created
    vm.prank(bidder1);
    vm.roll(pc.startBlock + 10);
    pool.bid{ value: 1 ether }(pId, 1);

    vm.roll((pc.endBlock - cfg.castWindow + 10));

    vm.expectRevert(GovernancePool.BidAuctionEnded.selector);
    pool.bid{ value: 2 ether }(pId, 1);

    pool.castVote(pId);
  }

  /// an end 2 end integration test that hits the live relic api to generate
  /// proofs on historical storage data
  function testProofValidationLive() public {
    address nounder = 0x83fCFe8Ba2FEce9578F0BbaFeD4Ebf5E915045B9;
    uint256 blockNumber = 16759187;

    // get a proof from relic-protocol (ffi a nodejs script)
    string[] memory inputsAccountProof = new string[](4);
    inputsAccountProof[0] = "ts-node";
    inputsAccountProof[1] = "./etc/ffi/relic/accountProof.ts";
    inputsAccountProof[2] = Strings.toHexString(NOUNS_TOKEN);
    inputsAccountProof[3] = Strings.toString(blockNumber);

    bytes memory resAccountProof = vm.ffi(inputsAccountProof);

    // prove account storage root
    IProver accountStorageProver = IProver(0xa0334AD349c1D805BF6c9e42125845B7D4F63aDe);
    Fact memory fact = accountStorageProver.prove(resAccountProof, true);
    assertEq(fact.account, NOUNS_TOKEN);

    // calc the slot for the token balance and delegate for the nounder
    bytes32 balanceSlot =
      Storage.mapElemSlot(SLOT_INDEX_TOKEN_BALANCE, bytes32(uint256(uint160(nounder))));

    bytes32 delegateeSlot =
      Storage.mapElemSlot(SLOT_INDEX_DELEGATEE, bytes32(uint256(uint160(nounder))));

    // ffi to call relic api and get proof for each slot/blocknumber
    string[] memory inputSlotProof = new string[](5);
    inputSlotProof[0] = "ts-node";
    inputSlotProof[1] = "./etc/ffi/relic/storageSlotProof.ts";
    inputSlotProof[2] = Strings.toString(blockNumber);
    inputSlotProof[3] = Strings.toHexString(uint256(balanceSlot));
    inputSlotProof[4] = Strings.toHexString(uint256(delegateeSlot));

    bytes memory slotProof = vm.ffi(inputSlotProof);

    // validate that proof from ffi is correctly formatted
    (address account, uint256 blockNum,,, uint256[] memory slots,) =
      abi.decode(slotProof, (address, uint256, uint256, bytes, uint256[], bytes));

    assertEq(uint256(balanceSlot), slots[0]);
    assertEq(uint256(delegateeSlot), slots[1]);
    assertEq(blockNum, blockNumber);
    assertEq(account, NOUNS_TOKEN);

    IBatchProver cachedMultiStorageProver = IBatchProver(0x57E15f4DeD314a302f9A74f32C71C30c1b89E25e);
    Fact[] memory facts = cachedMultiStorageProver.proveBatch(slotProof, false);

    // verify slots and compare sigs to ensure it's for the data we want
    assertEq(
      abi.encodePacked(facts[0].sig),
      abi.encodePacked(FactSigs.storageSlotFactSig(balanceSlot, blockNumber))
    );

    assertEq(
      abi.encodePacked(facts[1].sig),
      abi.encodePacked(FactSigs.storageSlotFactSig(delegateeSlot, blockNumber))
    );

    // parse the value from the slots
    bytes memory slotBalanceData = facts[0].data;
    uint256 slotBalanceValue = uint256(Storage.parseUint64(slotBalanceData));

    // second fact is the delegate of the nouns owner
    bytes memory slotDelegateeData = facts[1].data;
    address slotDelegateeValue = Storage.parseAddress(slotDelegateeData);

    address expectedDelegate = 0xcC2688350d29623E2A0844Cc8885F9050F0f6Ed5;
    uint256 expectedTokenBalance = 2;
    assertEq(slotBalanceValue, expectedTokenBalance);
    assertEq(slotDelegateeValue, expectedDelegate);
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
