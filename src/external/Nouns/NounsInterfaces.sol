// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.0;

import { NounsDAOStorageV2 } from "nouns-contracts/governance/NounsDAOInterfaces.sol";

interface INounsDAOLogicV2 {
  function propose(
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description
  ) external returns (uint256);

  function castRefundableVote(uint256 proposalId, uint8 support) external;

  function castVote(uint256 proposalId, uint8 support) external;

  function queue(uint256 proposalId) external;

  function execute(uint256 proposalId) external;

  function state(uint256 proposalId) external view returns (NounsDAOStorageV2.ProposalState);

  function quorumVotes() external view returns (uint256);

  function proposalThreshold() external view returns (uint256);
}
