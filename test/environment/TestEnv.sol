// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { NounsToken } from "nouns-contracts/NounsToken.sol";
import { ERC721 } from "nouns-contracts/base/ERC721.sol";
import { INounsDAOLogicV2 } from "src/external/nouns/NounsInterfaces.sol";

// Nouns mainnet addresses
address constant NOUNS_EXECUTOR = 0x0BC3807Ec262cB779b38D65b38158acC3bfedE10;
address constant NOUNS_GOVERNOR = payable(address(0x6f3E6272A167e8AcCb32072d08E0957F9c79223d));
address constant NOUNS_TOKEN = 0x9C8fF314C9Bc7F6e59A9d9225Fb22946427eDC03;
address constant NOUNS_AUCTION = 0x830BD73E4184ceF73443C15111a1DF14e495C706;
address constant DELEGATE_CASH = 0x00000000000076A84feF008CDAbe6409d2FE638B;
address constant RELIQUARY = 0x5E4DE6Bb8c6824f29c44Bd3473d44da120387d08;

// The storage slot index of the mapping containing Nouns token balance
bytes32 constant SLOT_INDEX_TOKEN_BALANCE = bytes32(uint256(4));
// The storage slot index of the mapping containing Nouns delegate addresses
bytes32 constant SLOT_INDEX_DELEGATEE = bytes32(uint256(11));

contract TestEnv {
  using stdStorage for StdStorage;

  address[5] public accounts;
  StdStorage internal stdstore;

  constructor(Vm vm) {
    accounts = [vm.addr(0x1), vm.addr(0x2), vm.addr(0x3), vm.addr(0x4), vm.addr(0x5)];
  }

  /// Set vetoer address
  function SetVetoer(address _vetoer) external {
    stdstore.target(NOUNS_GOVERNOR).sig("vetoer()").checked_write(_vetoer);
  }

  /// Setup 5 accounts and mint a random number of nouns for each
  function SetupNouners(Vm vm) external returns (address[5] memory) {
    // overwrite minter storage slot and set account[0] as the minter
    stdstore.target(NOUNS_TOKEN).sig("minter()").checked_write(accounts[0]);
    NounsToken nToken = NounsToken(NOUNS_TOKEN);

    // mint a random number of nouns for each account
    for (uint256 i = 0; i < accounts.length; ++i) {
      uint256 mintAmount = _random(2, 10, accounts[i]);

      for (uint256 j = 0; j < mintAmount; ++j) {
        vm.prank(accounts[0]);
        uint256 nounId = nToken.mint();

        if (i > 0) {
          vm.prank(accounts[0]);
          ERC721(address(nToken)).transferFrom(accounts[0], accounts[i], nounId);
        }
      }
    }

    // we do a little mining
    vm.roll(block.number + 10);

    return accounts;
  }

  address[] targets;
  uint256[] values;
  string[] signatures;
  bytes[] calldatas;

  /// Submits a proposal to send a target ether
  function SubmitProposal(Vm vm, uint256 _amount, address _target, address _proposer)
    external
    returns (uint256 pId)
  {
    targets.push(_target);
    values.push(_amount);
    signatures.push("");
    calldatas.push("0x");

    INounsDAOLogicV2 nounsDAO = INounsDAOLogicV2(NOUNS_GOVERNOR);

    vm.prank(_proposer);
    pId = nounsDAO.propose(targets, values, signatures, calldatas, "# Hello World");
  }

  /// Returns a random number between min and max
  function _random(uint256 min, uint256 max, address addr) internal view returns (uint256) {
    uint256 amount =
      uint256(keccak256(abi.encodePacked(block.timestamp, addr, block.number))) % (max - min);

    amount = amount + min;

    return amount;
  }
}
