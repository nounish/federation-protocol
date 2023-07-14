// SPDX-License-Identifier: GPL-3.0

import { OwnableUpgradeable } from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import { IDelegationRegistry } from "delegate-cash/IDelegationRegistry.sol";
import { IBatchProver } from "relic-sdk/packages/contracts/interfaces/IBatchProver.sol";
import { IReliquary } from "relic-sdk/packages/contracts/interfaces/IReliquary.sol";
import { GovernancePool } from "src/module/governance-pool/GovernancePool.sol";
import { Wallet } from "src/wallet/Wallet.sol";

pragma solidity ^0.8.19;

// The storage slot index of the mapping containing Nouns token balance
bytes32 constant SLOT_INDEX_TOKEN_BALANCE = bytes32(uint256(4));

// The storage slot index of the mapping containing Nouns delegate addresses
bytes32 constant SLOT_INDEX_DELEGATE = bytes32(uint256(11));

abstract contract ModuleConfig is OwnableUpgradeable {
  /// Emitted when storage slots are updated
  event SlotsUpdated(bytes32 balanceSlot, bytes32 delegateSlot);

  /// Emitted when the config is updated
  event ConfigChanged();

  /// Returns if a lock is active for this module
  error ConfigModuleHasActiveLock();

  /// Config is the structure of cfg for a Governance Pool module
  struct Config {
    /// The base wallet address for this module
    address base;
    /// The address of the DAO we are casting votes against
    address externalDAO;
    /// The address of the token used for voting in the external DAO
    address externalToken;
    /// feeRecipient is the address that receives any configured protocol fee
    address feeRecipient;
    /// The minimum bid accepted to cast a vote
    uint256 reservePrice;
    /// Amount of blocks an auction should extend if a bid is placed
    uint256 timeBuffer;
    /// The minimum percent difference between the last bid placed for a
    /// proposal vote and the current one
    uint256 minBidIncrementPercentage;
    /// The window in blocks when a vote can be cast
    uint256 castWindow;
    /// The default amount of blocks an auction ends before a proposals endblock
    /// provides a buffer for the last bid placed to extend the auction by timeBuffer up until the cast window
    /// this sets the default value for all bids. It must be at least castWindow blocks.
    /// (ex) to end auctions 2 hours before a proposal ends, set this to 600. they can then be extended up to castWindow
    uint256 auctionCloseBlocks;
    /// The default tip configured for casting a vote
    uint256 tip;
    /// feeBPS as parts per 10_000, i.e. 10% = 1000
    uint256 feeBPS;
    /// The maximum amount of base fee that can be refunded when casting a vote
    uint256 maxBaseFeeRefund;
    /// Max relic batch prover version; if 0 any prover version is accepted
    uint256 maxProverVersion;
    /// Relic reliquary address
    address reliquary;
    /// Delegate cash registry address
    address dcash;
    /// Fact validator address
    address factValidator;
    /// In preparation for Nouns governance v2->v3 we need to know
    /// handle switching vote snapshots to a proposal's start block
    uint256 useStartBlockFromPropId;
    /// Configurable vote reason
    string reason;
    /// Minimum propId that bids can be placed on. This is used to prevent competing
    /// with a previous version of this pool that has existing bids placed
    /// Set to accept bids on any prop
    uint256 migrationPropId;
  }

  /// The storage slot index containing nouns token balance mappings
  bytes32 public balanceSlotIdx = SLOT_INDEX_TOKEN_BALANCE;

  /// The storage slot index containing nouns delegate mappings
  bytes32 public delegateSlotIdx = SLOT_INDEX_DELEGATE;

  /// The config of this module
  Config internal _cfg;

  modifier isNotLocked() {
    _isNotLocked();
    _;
  }

  /// Reverts if the module has an open lock
  function _isNotLocked() internal view virtual {
    if (Wallet(_cfg.base).hasActiveLock()) {
      revert ConfigModuleHasActiveLock();
    }
  }

  /// Management function to get this contracts config
  function getConfig() external view returns (Config memory) {
    return _cfg;
  }

  /// Management function to update the config post initialization
  function setConfig(Config memory _config) external onlyOwner isNotLocked {
    _cfg = _validateConfig(_config);
    emit ConfigChanged();
  }

  function setTipAndRefund(uint256 _tip, uint256 _maxBaseFeeRefund) external onlyOwner {
    _cfg.tip = _tip;
    _cfg.maxBaseFeeRefund = _maxBaseFeeRefund;
    emit ConfigChanged();
  }

  /// Management function to set token storage slots for proof verification
  function setSlots(uint256 balanceSlot, uint256 delegateSlot) external onlyOwner {
    balanceSlotIdx = bytes32(balanceSlot);
    delegateSlotIdx = bytes32(delegateSlot);
    emit SlotsUpdated(balanceSlotIdx, delegateSlotIdx);
  }

  /// Management function to update dependency addresses
  function setAddresses(address _reliquary, address _delegateCash, address _factValidator)
    external
    onlyOwner
  {
    require(_reliquary != address(0), "invalid reliquary addr");
    require(_delegateCash != address(0), "invalid delegate cash registry addr");
    require(_factValidator != address(0), "invalid fact validator addr");

    _cfg.reliquary = _reliquary;
    _cfg.dcash = _delegateCash;
    _cfg.factValidator = _factValidator;
    emit ConfigChanged();
  }

  /// Management function to set a max required prover version
  /// Protects the pool in the event that relic is compromised
  function setMaxProverVersion(uint256 _version) external onlyOwner {
    _cfg.maxProverVersion = _version;
    emit ConfigChanged();
  }

  /// Management function to set the prop id for when we should start using
  /// proposal start blocks for voting snapshots
  function setUseStartBlockFromPropId(uint256 _pId) external onlyOwner {
    _cfg.useStartBlockFromPropId = _pId;
    emit ConfigChanged();
  }

  /// Management function to set vote reason
  function setReason(string calldata _reason) external onlyOwner {
    _cfg.reason = _reason;
    emit ConfigChanged();
  }

  /// Management function to reduce fees
  function setFee(uint256 _feeBPS, address _feeRecipient) external onlyOwner {
    if (_feeBPS > 0) {
      require(_feeRecipient != address(0), "recipient cannot be 0 if fee is set");
    }

    require(_feeBPS < _cfg.feeBPS, "fee cannot be increased");

    _cfg.feeBPS = _feeBPS;
    _cfg.feeRecipient = _feeRecipient;
    emit ConfigChanged();
  }

  /// Management function to update auction reserve price
  function setReservePrice(uint256 _reservePrice) external onlyOwner {
    require(_reservePrice > 0, "reserve cannot be 0");
    _cfg.reservePrice = _reservePrice;
    emit ConfigChanged();
  }

  /// Management function to update castWindow
  function setCastWindow(uint256 _castWindow) external onlyOwner {
    require(_castWindow > 0, "cast window 0");
    _cfg.castWindow = _castWindow;
    emit ConfigChanged();
  }

  /// Management function to update auction extension settings
  function setAuctionSettings(uint256 _timeBuffer, uint256 _auctionCloseBlocks) external onlyOwner {
    require(_auctionCloseBlocks >= _cfg.castWindow, "auction close blocks < cast window");
    _cfg.timeBuffer = _timeBuffer;
    _cfg.auctionCloseBlocks = _auctionCloseBlocks;
    emit ConfigChanged();
  }

  /// Management function to set migrationPropId
  function setMigrationPropId(uint256 _migrationPropId) external onlyOwner {
    _cfg.migrationPropId = _migrationPropId;
    emit ConfigChanged();
  }

  /// Validates that the config is set properly and sets default values if necessary
  function _validateConfig(Config memory _config) internal pure returns (Config memory) {
    if (_config.castWindow == 0) {
      revert GovernancePool.InitCastWindowNotSet();
    }

    if (_config.auctionCloseBlocks == 0 || _config.auctionCloseBlocks < _config.castWindow) {
      revert GovernancePool.InitAuctionCloseBlocksNotSet();
    }

    if (_config.externalDAO == address(0)) {
      revert GovernancePool.InitExternalDAONotSet();
    }

    if (_config.externalToken == address(0)) {
      revert GovernancePool.InitExternalTokenNotSet();
    }

    if (_config.feeBPS > 0 && _config.feeRecipient == address(0)) {
      revert GovernancePool.InitFeeRecipientNotSet();
    }

    if (_config.base == address(0)) {
      revert GovernancePool.InitBaseWalletNotSet();
    }

    // default reserve price
    if (_config.reservePrice == 0) {
      _config.reservePrice = 1 wei;
    }

    return _config;
  }
}
