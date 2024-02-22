// SPDX-License-Identifier: Unliscensed
pragma solidity ^0.8.19;

import { IL1Messenger } from "zksync-l2/system-contracts/interfaces/IL1Messenger.sol";
import { AddressAliasHelper } from "zksync-l1/contracts/vendor/AddressAliasHelper.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IZkSync, L2Message } from "zksync-l1/contracts/zksync/interfaces/IZkSync.sol";

struct Message {
    uint256 proposal;
    uint256 forVotes;
    uint256 againstVotes;
    uint256 abstainVotes;
}

contract TestCrossChainMessagingL2 is Ownable {
    event Sucess(string);

    modifier onlyMainnetOwner() {
        address owner = owner();

        if (msg.sender != owner) {
            if (AddressAliasHelper.undoL1ToL2Alias(msg.sender) != owner) {
                revert("Unautorized");
            }
        }

        _;
    }

    constructor(address _l1) {
        _transferOwnership(_l1);
    }

    function ping(address _messenger) external returns(bytes32) {
        IL1Messenger messenger = IL1Messenger(_messenger);

        Message memory message = Message({
            proposal: 69,
            forVotes: 5,
            againstVotes: 3,
            abstainVotes: 2
        });

        return messenger.sendToL1(abi.encode(message));
    }

    function testOwnership(string memory data) external onlyMainnetOwner {
        emit Sucess(data);
    }
}

contract TestCrossChainMessagingL1 {
    event Pong(uint256 proposal);

    function pong( 
        uint256 _l2BlockNumber,
        uint256 _index,
        uint16 _l2TxNumberInBlock,
        bytes calldata _message,
        bytes32[] calldata _messageProof,
        address _zkSync,
        address _l2,
        uint256 _gasLimit,
        uint256 _gasPerPubdataByteLimit
    ) external payable {
        IZkSync zksync = IZkSync(_zkSync);

        L2Message memory encodedMessage = L2Message({
            sender: _l2,
            data: _message,
            txNumberInBlock: _l2TxNumberInBlock
        });

        bool success = zksync.proveL2MessageInclusion(
            _l2BlockNumber,
            _index,
            encodedMessage,
            _messageProof
        );

        if (!success) revert("Bad proof");

        Message memory message = abi.decode(_message, (Message));

        emit Pong(message.proposal);

        zksync.requestL2Transaction{value: msg.value}(_l2, 0, abi.encodeWithSelector(
            TestCrossChainMessagingL2.testOwnership.selector,
            "some data lol"
        ), _gasLimit, _gasPerPubdataByteLimit, new bytes[](0), msg.sender);
    }
}