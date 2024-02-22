// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import {Relayer} from "src/module/l2-governance/Relayer.sol";
import {Governor} from "src/module/l2-governance/Governor.sol";
import {Storage} from "relic-sdk/packages/contracts/lib/Storage.sol";
// import { IZkSync, L2Message } from "zksync-l1/contracts/zksync/interfaces/IZkSync.sol";
import {ERC721Checkpointable} from "nouns-contracts/base/ERC721Checkpointable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Base} from "src/wallet/Base.sol";

/**
 * @title Mock Nouns Relayer
 * @notice For testing the Nouns Relayer without L1 -> L2 communication
 */
contract MockNounsRelayer is Relayer {
    /// The proposals that have been relayed
    mapping(uint256 => bool) public relayed;

    /**
     * @notice Initialize the contract
     * @param _data The encoded data containing the config
     */
    function init(bytes calldata _data) external payable initializer {
        (Config memory _config, MotivatorConfig memory _motivatorConfig) = abi
            .decode(_data, (Config, MotivatorConfig));

        config = _config;
        motivatorConfig = _motivatorConfig;

        if (msg.sender != _config.base) {
            _transferOwnership(_config.base);
        }
    }

    function relayVotes(
        // uint256 _l2BlockNumber,
        // uint256 _index,
        // uint16 _l2TxNumberInBlock,
        // bytes calldata _message,
        // bytes32[] calldata _messageProof
        Governor.Message memory message
    ) external refundGas {
        // IZkSync zksync = IZkSync(config.zkSync);

        // L2Message memory encodedMessage = L2Message({
        //     sender: config.governor,
        //     data: _message,
        //     txNumberInBlock: _l2TxNumberInBlock
        // });

        // bool success = zksync.proveL2MessageInclusion(
        //     _l2BlockNumber,
        //     _index,
        //     encodedMessage,
        //     _messageProof
        // );

        // if (!success) revert InvalidMessageProof();

        // Governor.Message memory message = abi.decode(_message, (Governor.Message));

        if (relayed[message.proposal]) revert AlreadyRelayed();

        uint256 totalVotes = ERC721Checkpointable(config.nativeToken)
            .totalSupply();
        uint256 totalVotesCast = message.forVotes +
            message.againstVotes +
            message.abstainVotes;

        if (totalVotesCast < (totalVotes * config.quorumVotesBPS) / 10000) {
            revert QuorumNotMet();
        }

        // 0=against, 1=for, 2=abstain
        uint8 support = 2;

        if (
            message.againstVotes >= message.forVotes &&
            message.againstVotes >= message.abstainVotes
        ) {
            support = 0;
        }

        if (
            message.forVotes >= message.againstVotes &&
            message.forVotes >= message.abstainVotes
        ) {
            support = 1;
        }

        Base(payable(config.base)).execute(
            config.externalDAO,
            0,
            abi.encodeWithSignature(
                "castRefundableVote(uint256,uint8)",
                message.proposal,
                support
            )
        );

        relayed[message.proposal] = true;

        _tip();

        emit VotesRelayed(
            message.proposal,
            support,
            totalVotes,
            totalVotesCast
        );
    }
}
