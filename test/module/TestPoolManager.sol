// SPDX-License-Identifier: GPL-3.0

import "forge-std/Test.sol";
import {Base} from "src/wallet/Base.sol";
import {BaseProxy} from "src/wallet/BaseProxy.sol";
import {Wallet} from "src/wallet/Wallet.sol";
import {NounsPool, NounsGovernanceV2} from "src/module/governance-pool/nouns/Nouns.sol";
import {GovernancePool} from "src/module/governance-pool/GovernancePool.sol";
import {ModuleConfig} from "src/module/governance-pool/ModuleConfig.sol";
import {NounsFactory} from "src/module/governance-pool/nouns/NounsFactory.sol";
import {ManagerFactory} from "src/module/manager/ManagerFactory.sol";
import {AtomicBidAndCast} from "test/misc/AtomicBidAndCast.sol";
import {FailMockValidator, PassMockValidator} from "test/misc/MockFactValidator.sol";
import {MockProver} from "test/misc/MockProver.sol";
import {PausableUpgradeable} from "openzeppelin-upgradeable/security/PausableUpgradeable.sol";
import {TestEnv, NOUNS_GOVERNOR, NOUNS_TOKEN, DELEGATE_CASH, RELIQUARY, SLOT_INDEX_TOKEN_BALANCE, SLOT_INDEX_DELEGATEE} from "test/environment/TestEnv.sol";
import {NounsDAOStorageV1Adjusted, NounsDAOStorageV2} from "nouns-contracts/governance/NounsDAOInterfaces.sol";
import {NounsDAOLogicV2} from "nouns-contracts/governance/NounsDAOLogicV2.sol";
import {NounsToken} from "nouns-contracts/NounsToken.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IReliquary} from "relic-sdk/packages/contracts/interfaces/IReliquary.sol";
import {IProver} from "relic-sdk/packages/contracts/interfaces/IProver.sol";
import {IBatchProver} from "relic-sdk/packages/contracts/interfaces/IBatchProver.sol";
import {Fact} from "relic-sdk/packages/contracts/lib/Facts.sol";
import {FactSigs} from "relic-sdk/packages/contracts/lib/FactSigs.sol";
import {Storage} from "relic-sdk/packages/contracts/lib/Storage.sol";
import {IDelegationRegistry} from "delegate-cash/IDelegationRegistry.sol";
import {Manager} from "src/module/manager/Manager.sol";

pragma solidity ^0.8.19;

interface Pausable {
    function pause() external;

    function unpause() external;
}

contract TestPoolManager is Test {
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
    Manager manager;

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

        poolFactory = new NounsFactory(
            address(_pool),
            RELIQUARY,
            DELEGATE_CASH,
            address(0),
            owner,
            150,
            80 gwei,
            0
        );

        bytes memory data = abi.encodeWithSelector(
            Base.initialize.selector,
            address(this)
        );
        BaseProxy proxy = new BaseProxy(
            address(baseImpl),
            address(admin),
            data
        );
        baseWallet = Wallet(address(proxy));
        admin.transferOwnership(owner);

        NounsFactory.PoolConfig memory fCfg = NounsFactory.PoolConfig(
            address(baseWallet),
            NOUNS_GOVERNOR,
            NOUNS_TOKEN,
            0.1 ether,
            5,
            150,
            0,
            0,
            0.01 ether,
            0
        );
        pool = NounsPool(poolFactory.clone(fCfg, "hello world"));
        baseWallet.setModule(address(pool), true);

        Manager m = new Manager();
        ManagerFactory mf = new ManagerFactory(address(m));
        address newManager = mf.clone(
            address(baseWallet),
            address(pool),
            owner
        );
        manager = Manager(newManager);

        baseWallet.setModule(address(newManager), true);
        assertEq(manager.owner(), owner);

        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);
        vm.rollFork(17131180);
        _env = new TestEnv(vm);
    }

    function testPauseUnpause() public {
        _registerMockProver();

        NounsToken nt = NounsToken(NOUNS_TOKEN);
        address[5] memory nouners = _env.SetupNouners(vm);
        address proposer = nouners[0];
        address delegator1 = nouners[1];

        // should not be able to change feeBPS or Receipient
        ModuleConfig.Config memory cfg = pool.getConfig();
        PassMockValidator pmv = new PassMockValidator();
        ModuleConfig.Config memory pcfg = ModuleConfig.Config(
            address(baseWallet),
            NOUNS_GOVERNOR,
            NOUNS_TOKEN,
            address(0),
            0.1 ether,
            25, // timeBuffer
            5,
            150,
            200, // auctionCloseBlocks
            0.01 ether,
            0,
            80 gwei,
            0,
            RELIQUARY,
            DELEGATE_CASH,
            address(pmv),
            0,
            "",
            0
        );

        vm.prank(delegator1);
        nt.delegate(cfg.base);

        vm.prank(cfg.base);
        pool.setConfig(pcfg);

        cfg = pool.getConfig();

        uint256 pId = _env.SubmitProposal(vm, 1 ether, bidder1, proposer);
        NounsDAOLogicV2 nounsDAO = NounsDAOLogicV2(payable(NOUNS_GOVERNOR));
        NounsDAOStorageV2.ProposalCondensed memory pc = nounsDAO.proposals(pId);

        bytes4 s = Pausable.pause.selector;
        bytes memory callData = abi.encodeWithSelector(s);
        vm.prank(owner);
        manager.execute(callData);

        bool paused = PausableUpgradeable(address(pool)).paused();
        assertEq(paused, true);

        // change a setting when paused
        s = ModuleConfig.setUseStartBlockFromPropId.selector;
        callData = abi.encodeWithSelector(s, 1);
        vm.prank(owner);
        manager.execute(callData);

        // cannot bid
        vm.roll((pc.endBlock - cfg.auctionCloseBlocks));
        vm.prank(bidder1);
        vm.expectRevert();
        pool.bid{value: 20 ether}(pId, 1, "");

        s = Pausable.unpause.selector;
        callData = abi.encodeWithSelector(s);
        vm.prank(owner);
        manager.execute(callData);

        paused = PausableUpgradeable(address(pool)).paused();
        assertEq(paused, false);

        // can bid + auction extends
        pool.bid{value: 20 ether}(pId, 1, "");
    }

    function testSetUseStartBlock() public {
        bytes4 s = ModuleConfig.setUseStartBlockFromPropId.selector;
        bytes memory callData = abi.encodeWithSelector(s, 1);
        vm.prank(owner);
        manager.execute(callData);

        ModuleConfig.Config memory _pcfg = ModuleConfig(address(pool))
            .getConfig();
        assertEq(_pcfg.useStartBlockFromPropId, 1);
    }

    function testSetAddresses() public {
        bytes4 s = ModuleConfig.setAddresses.selector;
        bytes memory callData = abi.encodeWithSelector(
            s,
            address(0),
            address(0),
            address(0)
        );

        // should fail if no addresses set
        vm.expectRevert();
        vm.prank(owner);
        manager.execute(callData);

        callData = abi.encodeWithSelector(
            s,
            address(1),
            address(1),
            address(1)
        );
        vm.prank(owner);
        manager.execute(callData);

        ModuleConfig.Config memory _pcfg = ModuleConfig(address(pool))
            .getConfig();
        assertEq(_pcfg.reliquary, address(1));
        assertEq(_pcfg.dcash, address(1));
        assertEq(_pcfg.factValidator, address(1));
    }

    function testSetMaxProverVersion() public {
        bytes4 s = ModuleConfig.setMaxProverVersion.selector;
        bytes memory callData = abi.encodeWithSelector(s, 1);
        vm.prank(owner);
        manager.execute(callData);

        ModuleConfig.Config memory _pcfg = ModuleConfig(address(pool))
            .getConfig();
        assertEq(_pcfg.maxProverVersion, 1);
    }

    // sets permissions on reliquary and registers the mock prover for testing
    function _registerMockProver() internal {
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
        try reliquary.addProver(address(mp), 69) {
            vm.warp(block.timestamp + 3 days);
            vm.stopPrank();
            vm.startPrank(relicDeployer);
            reliquary.activateProver(address(mp));
            reliquary.setProverFee(
                address(mp),
                IReliquary.FeeInfo(1, 0, 0, 0, 0),
                address(0)
            );
        } catch Error(string memory) {
            // only register once
        }
        vm.stopPrank();
    }
}
