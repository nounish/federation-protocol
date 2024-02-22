// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import { Governor } from "../Governor.sol";
import { IL1Messenger } from "zksync-l2/system-contracts/interfaces/IL1Messenger.sol";
import { IProver } from "relic-sdk/packages/contracts/interfaces/IProver.sol";
import { Fact, FactSignature } from "relic-sdk/packages/contracts/lib/Facts.sol";
import { CoreTypes } from "relic-sdk/packages/contracts/lib/CoreTypes.sol";
import { IReliquary } from "relic-sdk/packages/contracts/interfaces/IReliquary.sol";
import { IBatchProver } from "relic-sdk/packages/contracts/interfaces/IBatchProver.sol";
import { Storage } from "relic-sdk/packages/contracts/lib/Storage.sol";
import { Validator } from "src/proofs/FactValidator.sol";

/**
 * @title Nouns Governor
 * @author Federation - https://x.com/FederationWTF
 */
contract NounsGovernor is Governor {
    /// The synced proposals from NounsDAO
    mapping(uint256 => Proposal) public proposals;

    /// The voter receipts for each proposal
    mapping(uint256 => mapping(address => Receipt)) public receipts;

    /// Proposals that have been settled
    mapping(uint256 => bool) public settled;

    /**
     * @notice Initializes the governor
     * @param _config The contract config
     * @param _motivatorConfig The motivator config
     * @param _owner The owner of the governor
     */
    constructor(
        Governor.Config memory _config,
        MotivatorConfig memory _motivatorConfig,
        address _owner
    ) {
        config = _config;
        motivatorConfig = _motivatorConfig;

        if (_owner != msg.sender) {
            _transferOwnership(_owner);
        }
    }

    /**
     * @notice Vote for and sync a proposal if it does not exist
     * @param _proposal The proposal id
     * @param _support The vote support
     * @param _reason An optional reason
     * @param _metadata Optional metadata for the vote
     * @param _voterProofBatch A batch proof of delegation and balance
     * @param _voterProofAccounts The accounts associated with each voter proof
     * @param _proposalCreatedProof A log proof of the ProposalCreated event
     * @param _blockProof A proof of the proposal start block
    */
    function vote(
        uint256 _proposal,
        uint8 _support,
        string calldata _reason,
        string calldata _metadata,
        bytes calldata _voterProofBatch,
        address[] calldata _voterProofAccounts,
        bytes calldata _proposalCreatedProof,
        bytes calldata _blockProof
    ) external payable refundGas {
        Proposal storage proposal = proposals[_proposal];

        // Check if a proposal needs to be synced
        if (proposal.id == 0) {
            if (_proposalCreatedProof.length == 0) {
                revert MissingProposalCreatedProof();
            }

            (uint256 id, uint256 startBlock, uint256 endBlock) = _proveProposal(_proposalCreatedProof);

            if (settled[id]) revert ProposalEnded();

            uint256 blockNumber = _proveBlock(_blockProof);

            if (blockNumber < startBlock) revert ProposalNotStarted();

            proposal.id = id;
            proposal.endBlock = endBlock;
            proposal.startBlock = startBlock;

            emit ProposalSynced(
                id,
                endBlock,
                startBlock
            );
        }

        (uint256 votes) = _proveVoter(_voterProofBatch, _voterProofAccounts, proposal.startBlock);

        Receipt storage receipt = receipts[proposal.id][msg.sender];

        if (settled[proposal.id]) revert ProposalEnded();
        if (receipt.hasVoted) revert AlreadyVoted();
        if (votes < 1) revert NoVotingPower();
        if (_support > 2) revert InvalidSupport();

        // 0=against, 1=for, 2=abstain

        if (_support == 0) {
            proposal.againstVotes += votes;
        }

        if (_support == 1) {
            proposal.forVotes += votes;
        }

        if (_support == 2) {
            proposal.abstainVotes += votes;
        }

        receipt.hasVoted = true;
        receipt.support = _support;
        receipt.votes = votes;
        
        emit VoteCast(
            _proposal,
            msg.sender,
            _support,
            votes,
            _reason,
            _metadata
        );
        
    }

    /**
     * @notice Settle vote outcome to the relayer
     * @param _proposal The proposal id
     * @param _blockProof The proof of the block
    */
    function settleVotes(uint256 _proposal, bytes calldata _blockProof) external payable refundGas {
        Proposal memory proposal = proposals[_proposal];

        if (proposal.id == 0) {
            revert ProposalNotFound();
        }

        uint256 blockNumber = _proveBlock(_blockProof);
            
        if (blockNumber < proposal.endBlock - config.finalityBlocks - config.castWindow) {
            revert CastNotInWindow();
        }
        
        IL1Messenger messenger = IL1Messenger(config.messenger);

        Message memory message = Message({
            proposal: proposal.id,
            forVotes: proposal.forVotes,
            againstVotes: proposal.againstVotes,
            abstainVotes: proposal.abstainVotes
        });

        messenger.sendToL1(abi.encode(message));

        if (!settled[_proposal]) _tip();

        settled[_proposal] = true;
       
        emit VotesSettled(
            proposal.id,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.abstainVotes
        );
    }
        
    /**
     * @notice Retrieve a voter's receipt
     * @param _proposal The proposal id
     * @param _voter The voters address
     * @return The voter's receipt
    */
    function getReceipt(uint256 _proposal, address _voter) external view returns (Receipt memory) {
        return receipts[_proposal][_voter];
    }

    /**
     * @notice Retrieve proposal data
     * @param _proposal The proposal id
     * @return The proposal
    */
    function getProposal(uint256 _proposal) external view returns (Proposal memory) {                
        return proposals[_proposal];
    }
    
    /**
     * @notice Convert an address to bytes32
     * @param _address The address to convert
     * @return The bytes32 representation of the address
    */
    function _addressToBytes32(address _address) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_address)));
    }

    /**
     * @notice Prove a proposal is valid
     * @param _proof The log proof
     * @return The proposal id, start block, and end block
    */
    function _proveProposal(bytes calldata _proof) internal returns (uint256, uint256, uint256) {
        IProver logProver = IProver(config.logProver);

        if (!_checkProverVersion(address(logProver))) {
            revert InvalidProverVersion("The log prover is not a valid version");
        }

        Fact memory proposalFact = logProver.prove{value: msg.value}(_proof, false);
    
        CoreTypes.LogData memory logData = abi.decode(proposalFact.data, (CoreTypes.LogData));

        if (logData.Address != config.externalDAO) {
            revert SyncProposalInvalidProof();
        }

        (uint256 id, , , , , , uint256 startBlock, uint256 endBlock, ) = abi.decode(logData.Data, (uint256, address, address[], uint256[], string[], bytes[], uint256, uint256, string));
       
        return (id, startBlock, endBlock);
    }

    /**
     * @notice Prove an account is a valid voter
     * @param _proofBatch The proof batch containing proof of balance and delegation
     * @param _proofAccounts The accounts associated with each proof
     * @param _startBlock The proposal start block
     * @return The number of votes the account has
    */
    function _proveVoter(bytes calldata _proofBatch, address[] calldata _proofAccounts ,uint256 _startBlock) internal returns (uint256) {
        IBatchProver storageProver = IBatchProver(config.storageProver);
        
        if (!_checkProverVersion(address(storageProver))) {
            revert InvalidProverVersion("The storage prover is not a valid version");
        }

        Fact[] memory facts = storageProver.proveBatch{
            value: msg.value
        }(_proofBatch, false);

        if (facts.length % 2 != 0) {
            revert InvalidProofBatchLength();
        }

        if (facts.length / 2 != _proofAccounts.length) {
            revert ProofBatchAndAccountMismatch();
        }

        Validator validator = Validator(config.factValidator);

        uint256 votes = 0;

        for (uint32 i = 0; i < facts.length; i += 2) {
            Fact memory balanceFact = facts[i];
            Fact memory delegateFact = facts[i + 1];

            address proofAccount = _proofAccounts[i / 2];

            bytes32 balanceSlot = Storage.mapElemSlot(
                bytes32(config.tokenBalanceSlot),
                _addressToBytes32(proofAccount)
            );

            bytes32 delegateSlot = Storage.mapElemSlot(
                bytes32(config.tokenDelegateSlot),
                _addressToBytes32(proofAccount)
            );

            if (
                !validator.validate(
                    balanceFact,
                    balanceSlot,
                    _startBlock,
                    config.nativeToken
                )
            ) {
                revert VoteInvalidProof("balanceOf");
            }

            if (
                !validator.validate(
                    delegateFact,
                    delegateSlot,
                    _startBlock,
                    config.nativeToken
                )
            ) {
                revert VoteInvalidProof("delegate");
            }

            if (Storage.parseAddress(delegateFact.data) != msg.sender) {
                revert VoteInvalidProof("delegated address not msg.sender");
            }

            votes += Storage.parseUint256(balanceFact.data);  
        }

        if (votes == 0) {
            revert NoVotingPower();
        }

        return votes;
    }

    /**
     * @notice Prove a block is valid
     * @param _proof The proof of the block
     * @return The block number
    */
    function _proveBlock(bytes calldata _proof) internal returns (uint256) {
        IProver transactionProver = IProver(config.transactionProver);

        if (!_checkProverVersion(address(transactionProver))) {
            revert InvalidProverVersion("The transaction prover is not a valid version");
        }

        Fact memory transactionFact = transactionProver.prove{value: msg.value}(_proof, false);
    
        (uint256 number,) = abi.decode(transactionFact.data, (uint256, uint256));

        return number;
    }

    /**
     * @notice Check the prover version
     * @param _prover The address of the prover
     * @return True if the prover version is valid
    */
    function _checkProverVersion(address _prover) internal view returns (bool) {
        IReliquary reliquary = IReliquary(config.reliquary);
        IReliquary.ProverInfo memory prover = reliquary.provers(_prover);
        
        reliquary.checkProver(prover);

        if (config.maxProverVersion != 0) {
            if (prover.version > config.maxProverVersion) {
                return false;
            }
        }

        return true;
    }
}
