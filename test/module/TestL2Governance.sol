// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Governor} from "src/module/l2-governance/Governor.sol";
import {NounsGovernor} from "src/module/l2-governance/nouns/NounsGovernor.sol";
import {Relayer} from "src/module/l2-governance/Relayer.sol";
import {NounsRelayer} from "src/module/l2-governance/nouns/NounsRelayer.sol";
import {NounsRelayerFactory} from "src/module/l2-governance/nouns/NounsRelayerFactory.sol";
import {MotivatorV2} from "src/incentives/MotivatorV2.sol";
import {TestEnv, NOUNS_GOVERNOR, NOUNS_TOKEN, RELIQUARY, SLOT_INDEX_TOKEN_BALANCE, SLOT_INDEX_DELEGATEE} from "test/environment/TestEnv.sol";
import {INounsDAOLogicV2, NounsDAOStorageV2} from "src/external/nouns/NounsInterfaces.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Wallet} from "src/wallet/Wallet.sol";
import {BaseProxy} from "src/wallet/BaseProxy.sol";
import {Base} from "src/wallet/Base.sol";
import {AddressAliasHelper} from "zksync-l1/contracts/vendor/AddressAliasHelper.sol";
import {FailMockValidator, PassMockValidator} from "test/misc/MockFactValidator.sol";
import {MockProver} from "test/misc/MockProver.sol";
import {MockLogProver} from "test/misc/MockLogProver.sol";
import {MockTransactionProver} from "test/misc/MockTransactionProver.sol";
import {IReliquary} from "relic-sdk/packages/contracts/interfaces/IReliquary.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {NounsToken} from "nouns-contracts/NounsToken.sol";

contract TestL2Governance is Test {
    TestEnv internal _env;

    address[5] nouners;

    address owner;
    ProxyAdmin admin;
    Wallet baseWallet;

    address motivator1;
    address motivator2;

    NounsGovernor public nounsGovernor;

    NounsRelayer public nounsRelayer;
    NounsRelayerFactory public nounsRelayerFactory;

    uint256 mainnetFork;

    uint256 proposalId;

    MockProver mockProver;
    MockLogProver mockLogProver;
    MockTransactionProver mockTransactionProver;

    function setUp() public {
        owner = vm.addr(0x6);
        motivator1 = vm.addr(0x7);
        motivator2 = vm.addr(0x8);

        vm.deal(owner, 96 ether);

        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        _env = new TestEnv(vm);
        nouners = _env.SetupNouners(vm);

        admin = new ProxyAdmin();

        BaseProxy proxy = new BaseProxy(
            address(new Base()),
            address(admin),
            abi.encodeWithSelector(Base.initialize.selector, address(this))
        );

        baseWallet = Wallet(address(proxy));
        admin.transferOwnership(owner);

        nounsRelayerFactory = new NounsRelayerFactory(
            address(new NounsRelayer())
        );

        vm.prank(address(baseWallet));
        nounsRelayer = NounsRelayer(
            nounsRelayerFactory.clone(
                Relayer.Config(
                    address(baseWallet),
                    NOUNS_GOVERNOR,
                    NOUNS_TOKEN,
                    address(0), // zkSync address
                    address(0), // nounsGovernor (not cloned yet)
                    0 // quorum votes BPS
                ),
                MotivatorV2.MotivatorConfig(
                    0, // refundBaseGas
                    0, // maxRefundPriorityFee
                    0, // maxRefundGasUsed
                    0, // maxRefundBaseFee
                    0.05 ether // tipAmount
                )
            )
        );

        mockProver = new MockProver();
        mockLogProver = new MockLogProver();
        mockTransactionProver = new MockTransactionProver();

        nounsGovernor = new NounsGovernor(
            Governor.Config(
                RELIQUARY,
                NOUNS_TOKEN,
                NOUNS_GOVERNOR,
                address(mockProver), // storage prover
                address(mockLogProver), // log prover
                address(mockTransactionProver), // transaction prover
                address(new PassMockValidator()), // fact validator
                address(0), // L1 zkSync messenger
                4,
                11,
                0, // max prover version
                0, // cast window
                0 // finality blocks
            ),
            MotivatorV2.MotivatorConfig(
                0, // refundBaseGas
                0, // maxRefundPriorityFee
                0, // maxRefundGasUsed
                0, // maxRefundBaseFee
                0.05 ether // tipAmount
            ),
            address(nounsRelayer)
        );
    }

    function testSetGovernorConfig() public {
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 castWindow,
            uint256 finalityBlocks
        ) = nounsGovernor.config();

        assertEq(castWindow, 0);
        assertEq(finalityBlocks, 0);

        Governor.Config memory config;

        config.castWindow = 100;
        config.finalityBlocks = 100;

        // Simulates the Relayer calling setGovernorConfig
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(address(nounsRelayer)));
        nounsGovernor.setConfig(config);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 newCastWindow,
            uint256 newFinalityBlocks
        ) = nounsGovernor.config();

        assertEq(newCastWindow, 100);
        assertEq(newFinalityBlocks, 100);
    }

    function testSetGovernorMotivatorConfig() public {
        (
            uint256 refundBaseGas,
            uint256 maxRefundPriorityFee,
            uint256 maxRefundGasUsed,
            uint256 maxRefundBaseFee,

        ) = nounsGovernor.motivatorConfig();

        assertEq(refundBaseGas, 0);
        assertEq(maxRefundPriorityFee, 0);
        assertEq(maxRefundGasUsed, 0);
        assertEq(maxRefundBaseFee, 0);

        MotivatorV2.MotivatorConfig memory motivatorConfig;

        motivatorConfig.refundBaseGas = 100;
        motivatorConfig.maxRefundPriorityFee = 100;
        motivatorConfig.maxRefundGasUsed = 100;
        motivatorConfig.maxRefundBaseFee = 100;

        // Simulates the Relayer calling setGovernorMotivatorConfig
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(address(nounsRelayer)));
        nounsGovernor.setMotivatorConfig(motivatorConfig);

        (
            uint256 newRefundBaseGas,
            uint256 newMaxRefundPriorityFee,
            uint256 newMaxRefundGasUsed,
            uint256 newMaxRefundBaseFee,

        ) = nounsGovernor.motivatorConfig();

        assertEq(newRefundBaseGas, 100);
        assertEq(newMaxRefundPriorityFee, 100);
        assertEq(newMaxRefundGasUsed, 100);
        assertEq(newMaxRefundBaseFee, 100);
    }

    function testSetRelayerConfig() public {
        (, , , , address governor, uint256 quorumVotesBPS) = nounsRelayer
            .config();

        console.logAddress(nounsRelayer.owner());

        assertEq(quorumVotesBPS, 0);
        assertEq(governor, address(0));

        Relayer.Config memory config;

        config.quorumVotesBPS = 5000;
        config.governor = address(nounsGovernor);

        vm.prank(address(baseWallet));
        nounsRelayer.setConfig(config);

        (, , , , address newGovernor, uint256 newQuorumVotesBPS) = nounsRelayer
            .config();

        assertEq(newQuorumVotesBPS, 5000);
        assertEq(newGovernor, address(nounsGovernor));
    }

    function testSetRelayerMotivatorConfig() public {
        (
            uint256 refundBaseGas,
            uint256 maxRefundPriorityFee,
            uint256 maxRefundGasUsed,
            uint256 maxRefundBaseFee,

        ) = nounsRelayer.motivatorConfig();

        assertEq(refundBaseGas, 0);
        assertEq(maxRefundPriorityFee, 0);
        assertEq(maxRefundGasUsed, 0);
        assertEq(maxRefundBaseFee, 0);

        MotivatorV2.MotivatorConfig memory motivatorConfig;

        motivatorConfig.refundBaseGas = 100;
        motivatorConfig.maxRefundPriorityFee = 100;
        motivatorConfig.maxRefundGasUsed = 100;
        motivatorConfig.maxRefundBaseFee = 100;

        vm.prank(address(baseWallet));
        nounsRelayer.setMotivatorConfig(motivatorConfig);

        (
            uint256 newRefundBaseGas,
            uint256 newMaxRefundPriorityFee,
            uint256 newMaxRefundGasUsed,
            uint256 newMaxRefundBaseFee,

        ) = nounsRelayer.motivatorConfig();

        assertEq(newRefundBaseGas, 100);
        assertEq(newMaxRefundPriorityFee, 100);
        assertEq(newMaxRefundGasUsed, 100);
        assertEq(newMaxRefundBaseFee, 100);
    }

    function testVote() public {
        _registerMockProver(address(mockProver), 69);
        _registerMockProver(address(mockLogProver), 420);

        NounsToken nounsToken = NounsToken(NOUNS_TOKEN);

        vm.prank(nouners[0]);
        nounsToken.delegate(address(baseWallet));

        vm.prank(nouners[1]);
        nounsToken.delegate(address(baseWallet));

        vm.prank(nouners[2]);
        nounsToken.delegate(address(baseWallet));

        vm.prank(nouners[3]);
        nounsToken.delegate(address(baseWallet));

        proposalId = _env.SubmitProposal(vm, 1 ether, motivator1, nouners[0]);

        bytes[] memory proposalCreatedProofs = new bytes[](1);

        address[] memory proofAccounts = new address[](1);

        // Set log proof data
        NounsDAOStorageV2.ProposalCondensed
            memory proposalCondensed = INounsDAOLogicV2(NOUNS_GOVERNOR)
                .proposals(proposalId);

        bytes memory data = abi.encode(
            proposalId,
            address(0),
            new address[](0),
            new uint256[](0),
            new string[](0),
            new bytes[](0),
            proposalCondensed.startBlock,
            proposalCondensed.endBlock,
            ""
        );
        (, , address externalDAO, , , , , , , , , , ) = nounsGovernor.config();
        mockLogProver.setProofData(data, externalDAO);

        vm.roll(proposalCondensed.startBlock + 10);

        // Revert because missing proposal created proof
        _setStorageProofData(nouners[0]);

        vm.prank(nouners[0]);
        vm.expectRevert();
        nounsGovernor.vote(
            proposalId,
            1,
            "a reason",
            "{metadata: 'metadata'}",
            bytes(""),
            proofAccounts,
            bytes(""),
            bytes("")
        );

        // Sync and vote for proposal
        _setStorageProofData(nouners[1]);

        proposalCreatedProofs[0] = bytes("this is a mock proof");

        vm.prank(nouners[1]);
        nounsGovernor.vote(
            proposalId,
            1,
            "a reason",
            "{metadata: 'metadata'}",
            bytes(""),
            proofAccounts,
            proposalCreatedProofs[0],
            bytes("")
        );

        (, , , uint256 forVotes, , ) = nounsGovernor.proposals(proposalId);
        assertEq(forVotes, nounsToken.balanceOf(nouners[1]));

        // vote abstain proposal
        _setStorageProofData(nouners[2]);

        vm.prank(nouners[2]);
        nounsGovernor.vote(
            proposalId,
            2,
            "a reason",
            "{metadata: 'metadata'}",
            bytes(""),
            proofAccounts,
            bytes(""),
            bytes("")
        );

        (, , , , , uint256 abstainVotes) = nounsGovernor.proposals(proposalId);
        assertEq(abstainVotes, nounsToken.balanceOf(nouners[2]));

        // vote against proposal
        _setStorageProofData(nouners[3]);

        vm.prank(nouners[3]);
        nounsGovernor.vote(
            proposalId,
            0,
            "a reason",
            "{metadata: 'metadata'}",
            bytes(""),
            proofAccounts,
            bytes(""),
            bytes("")
        );

        (, , , , uint256 againstVotes, ) = nounsGovernor.proposals(proposalId);
        assertEq(againstVotes, nounsToken.balanceOf(nouners[3]));
    }

    function _setStorageProofData(address _voter) internal {
        NounsToken nounsToken = NounsToken(NOUNS_TOKEN);

        // set proof data on mock prover
        bytes[] memory proofData = new bytes[](2);

        // first proof is token balance
        uint256 accountBalance = nounsToken.balanceOf(_voter);
        bytes memory b = new bytes(32);
        assembly ("memory-safe") {
            mstore(add(b, 32), accountBalance)
        }
        proofData[0] = b;

        // second proof is the address nouns were delegated to
        proofData[1] = abi.encodePacked(_voter);

        mockProver.setProofData(proofData);
    }

    // sets permissions on reliquary and registers the mock prover for testing
    function _registerMockProver(address _prover, uint64 _version) internal {
        address relicDeployer = 0xf979392E396dc53faB7B3C430dD385e73dD0A4e2;
        address relicGov = 0xCCEf16C5ac53714512A5Acce5Fa1984A977351bE;

        IReliquary reliquary = IReliquary(RELIQUARY);
        vm.startPrank(relicGov);
        AccessControl(address(reliquary)).grantRole(
            keccak256("ADD_PROVER_ROLE"),
            relicDeployer
        );
        AccessControl(address(reliquary)).grantRole(
            keccak256("GOVERNANCE_ROLE"),
            relicDeployer
        );
        try reliquary.addProver(_prover, _version) {
            vm.warp(block.timestamp + 3 days);
            vm.stopPrank();
            vm.startPrank(relicDeployer);
            reliquary.activateProver(_prover);
            reliquary.setProverFee(
                _prover,
                IReliquary.FeeInfo(1, 0, 0, 0, 0),
                address(0)
            );
        } catch Error(string memory err) {
            console.logString(err);
            // only register once
        }
        vm.stopPrank();
    }
}
