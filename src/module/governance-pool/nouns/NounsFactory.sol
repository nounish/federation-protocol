// SPDX-License-Identifier: GPL-3.0

import { GovernancePool } from "src/module/governance-pool/GovernancePool.sol";
import { Module } from "src/module/Module.sol";
import { ModuleConfig } from "src/module/governance-pool/ModuleConfig.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

pragma solidity ^0.8.19;

contract NounsFactory is Ownable {
  /// The name of this contract
  string public constant name = "Federation Governance Pool Factory v0.1";

  /// Emitted when a new clone is created
  event Created(address addr);

  /// Emitted when dependency addresses are updated
  event AddressesUpdated(
    address impl, address reliquary, address delegateCash, address factValidator
  );

  /// Emitted when the max base fee refund is updated for pools
  event MaxBaseFeeRefundUpdated();

  /// Emitted when fee config is updated
  event FeeConfigUpdated();

  /// Emitted when useStartBlockFromPropId is updated
  event StartBlockSnapshotFromPropId(uint256 pId);

  /// PoolConfig is the structure of cfg for a Nouns Governance Pool
  struct PoolConfig {
    /// The base wallet address for this module
    address base;
    /// The address of the DAO we are casting votes against
    address dao;
    /// The address of the token used for voting in the external DAO
    address token;
    /// The minimum bid accepted to cast a vote
    uint256 reservePrice;
    /// The minimum percent difference between the last bid placed for a
    /// proposal vote and the current one
    uint256 minBidIncrementPercentage;
    /// The window in blocks when a vote can be cast
    uint256 castWindow;
    /// Blocks to extend auctions
    uint256 timeBuffer;
    /// The default amount of blocks an auction ends before a proposals endblock
    uint256 auctionCloseBlocks;
    /// Cast vote tip
    uint256 tip;
    /// Minimum prop id bids can be accepted on
    uint256 migrationPropId;
  }

  /// The address of the implementation contract
  address public impl;

  /// The address of the relic reliquary
  address public reliquary;

  /// The address of the delegate cash registry
  address public dcash;

  /// The address of the module fact validator
  address public factValidator;

  /// The address that receives any configured protocol fee
  address public feeRecipient;

  /// bps as parts per 10_000, i.e. 10% = 1000
  uint256 public feeBPS;

  /// max base fee to refund callers who cast votes
  uint256 public maxBaseFeeRefund;

  /// whether to use startBlock or creationBlock for voting power snapshots
  uint256 useStartBlockFromPropId;

  constructor(
    address _impl,
    address _reliquary,
    address _dcash,
    address _factValidator,
    address _feeRecipient,
    uint256 _feeBPS,
    uint256 _maxBaseFeeRefund,
    uint256 _useStartBlockFromPropId
  ) {
    impl = _impl;
    reliquary = _reliquary;
    dcash = _dcash;
    factValidator = _factValidator;
    feeRecipient = _feeRecipient;
    feeBPS = _feeBPS;
    maxBaseFeeRefund = _maxBaseFeeRefund;
    useStartBlockFromPropId = _useStartBlockFromPropId;
  }

  /// Deploy a new Nouns Governance Pool
  /// @param _cfg Factory pool config
  /// @param _reason The reason used when voting on proposals
  function clone(PoolConfig memory _cfg, string calldata _reason)
    external
    payable
    returns (address)
  {
    address inst = Clones.clone(impl);

    // default to ~30 min
    if (_cfg.castWindow == 0) {
      _cfg.castWindow = 150;
    }

    if (_cfg.tip == 0) {
      _cfg.tip = 0.0025 ether;
    }

    // default to ~5 min
    if (_cfg.timeBuffer == 0) {
      _cfg.timeBuffer = 25;
    }

    // default to ~2 hours: results in max 1.5 hours extension
    if (_cfg.auctionCloseBlocks == 0) {
      _cfg.auctionCloseBlocks = 600;
    }

    ModuleConfig.Config memory cfg = ModuleConfig.Config(
      _cfg.base,
      _cfg.dao,
      _cfg.token,
      feeRecipient,
      _cfg.reservePrice,
      _cfg.timeBuffer,
      _cfg.minBidIncrementPercentage,
      _cfg.castWindow,
      _cfg.auctionCloseBlocks,
      _cfg.tip,
      feeBPS,
      maxBaseFeeRefund,
      0, // maxProver version
      reliquary,
      dcash,
      factValidator,
      useStartBlockFromPropId,
      _reason,
      _cfg.migrationPropId
    );

    Module(inst).init{ value: msg.value }(abi.encode(cfg));
    emit Created(inst);

    return inst;
  }

  /// Management function to update dependency addresses
  function setAddresses(
    address _impl,
    address _reliquary,
    address _delegateCash,
    address _factValidator
  ) external onlyOwner {
    require(_impl != address(0), "invalid implementation addr");
    require(_reliquary != address(0), "invalid reliquary addr");
    require(_delegateCash != address(0), "invalid delegate cash registry addr");
    require(_factValidator != address(0), "invalid fact validator addr");

    impl = _impl;
    reliquary = _reliquary;
    dcash = _delegateCash;
    factValidator = _factValidator;
    emit AddressesUpdated(_impl, _reliquary, _delegateCash, _factValidator);
  }

  function setMaxBaseFeeRefund(uint256 _maxBaseFeeRefund) external onlyOwner {
    maxBaseFeeRefund = _maxBaseFeeRefund;
    emit MaxBaseFeeRefundUpdated();
  }

  function setFeeConfig(address _feeRecipient, uint256 _feeBPS) external onlyOwner {
    feeRecipient = _feeRecipient;
    feeBPS = _feeBPS;
    emit FeeConfigUpdated();
  }

  function setUseStartBlockFromPropId(uint256 _useStartBlockFromPropId) external onlyOwner {
    useStartBlockFromPropId = _useStartBlockFromPropId;
    emit StartBlockSnapshotFromPropId(_useStartBlockFromPropId);
  }
}
