// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import { ERC20LockBoostProvider } from "src/ERC20LockBoostProvider.sol";
import { ERC20LockVault } from "src/ERC20LockVault.sol";
import { LidoGovernanceLockVault } from "src/LidoGovernanceLockVault.sol";
import { IAragonVotingLockVault } from "src/interfaces/IAragonVotingLockVault.sol";
import { IERC20LockBoostProvider } from "src/interfaces/IERC20LockBoostProvider.sol";
import { IERC20LockVault } from "src/interfaces/IERC20LockVault.sol";
import { IMetaRegistry } from "src/interfaces/IMetaRegistry.sol";
import { IBaseWeightBoostProvider } from "src/interfaces/IBaseWeightBoostProvider.sol";
import { IStepwiseWeightBoost, Step } from "src/interfaces/IStepwiseWeightBoost.sol";
import { ISnapshotDelegationLockVault } from "src/interfaces/ISnapshotDelegationLockVault.sol";
import { MetaRegistry } from "src/MetaRegistry.sol";
import { NodeOperator, NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";

import { CuratedMock } from "../helpers/mocks/CuratedMock.sol";
import { StakingRouterMock } from "../helpers/mocks/StakingRouterMock.sol";
import { StepwiseWeightBoostBehaviour } from "../helpers/StepwiseWeightBoostBehaviour.sol";
import { ERC20Testable } from "../helpers/ERCTestable.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { Fixtures } from "../helpers/Fixtures.sol";

contract LidoAragonVotingMock {
    mapping(address voter => address delegate) public delegateOf;
    address public lastVoter;
    uint256 public lastVoteId;
    bool public lastSupport;
    bool public lastExecutesIfDecided;

    function assignDelegate(address delegate) external {
        delegateOf[msg.sender] = delegate;
    }

    function unassignDelegate() external {
        delegateOf[msg.sender] = address(0);
    }

    function vote(uint256 voteId, bool support, bool executesIfDecided) external {
        lastVoter = msg.sender;
        lastVoteId = voteId;
        lastSupport = support;
        lastExecutesIfDecided = executesIfDecided;
    }
}

contract SnapshotDelegationMock {
    mapping(address delegator => mapping(bytes32 id => address delegate)) public delegateOf;
    address public lastDelegator;
    bytes32 public lastId;
    address public lastDelegate;

    function setDelegate(bytes32 id, address delegate) external {
        delegateOf[msg.sender][id] = delegate;
        lastDelegator = msg.sender;
        lastId = id;
        lastDelegate = delegate;
    }

    function clearDelegate(bytes32 id) external {
        delete delegateOf[msg.sender][id];
        lastDelegator = msg.sender;
        lastId = id;
        lastDelegate = address(0);
    }
}

contract ERC20LockBoostProviderForTest is ERC20LockBoostProvider {
    constructor(
        address module,
        address token,
        address vaultBeacon,
        uint256 minLockPeriod
    ) ERC20LockBoostProvider(module, token, vaultBeacon, minLockPeriod) {}

    function mock_withdraw(uint256 nodeOperatorId, uint256 amount, address receiver) external {
        _withdraw(nodeOperatorId, amount, receiver);
    }
}

contract ERC20LockBoostProviderBaseTest is Test, Utilities, Fixtures {
    CuratedMock public module;
    StakingRouterMock public stakingRouter;
    MetaRegistry public registry;
    ERC20Testable public token;
    LidoAragonVotingMock public voting;
    SnapshotDelegationMock public snapshotDelegation;
    LidoGovernanceLockVault public vaultImpl;
    UpgradeableBeacon public vaultBeacon;
    ERC20LockBoostProvider public provider;

    address public admin;
    address public groupManager;
    address public bondCurveWeightManager;
    address public nodeOperatorOwner;
    address public receiver;
    address public votingDelegate;
    address public snapshotDelegate;
    address public stranger;

    uint256 internal constant NODE_OPERATOR_ID = 0;
    uint256 internal constant GROUP_ID = 1;
    uint256 internal constant BASE_WEIGHT = 10000;
    uint16 internal constant MAX_BP = 10000;
    uint256 internal constant MIN_LOCK_PERIOD = 1 days;
    uint256 internal constant MAX_LOCK_PERIOD = 365 days;
    uint256 internal constant LOCK_PERIOD = 30 days;
    uint128 internal constant STEP_1_AMOUNT = 100 ether;
    uint128 internal constant STEP_2_AMOUNT = 200 ether;
    uint128 internal constant STEP_1_WEIGHT_BOOST_BP = 1_000;
    uint128 internal constant STEP_2_WEIGHT_BOOST_BP = 1_500;
    uint256 internal constant STEP_1_MULTIPLIER_BP = MAX_BP + STEP_1_WEIGHT_BOOST_BP;
    uint256 internal constant STEP_2_MULTIPLIER_BP = MAX_BP + STEP_2_WEIGHT_BOOST_BP;
    bytes32 internal constant SNAPSHOT_ALL_SPACES = bytes32(0);

    function setUp() public virtual {
        admin = nextAddress("ADMIN");
        groupManager = nextAddress("GROUP_MANAGER");
        bondCurveWeightManager = nextAddress("BOND_CURVE_WEIGHT_MANAGER");
        nodeOperatorOwner = nextAddress("NODE_OPERATOR_OWNER");
        receiver = nextAddress("RECEIVER");
        votingDelegate = nextAddress("VOTING_DELEGATE");
        snapshotDelegate = nextAddress("SNAPSHOT_DELEGATE");
        stranger = nextAddress("STRANGER");

        module = new CuratedMock();
        module.mock_setNodeOperatorsCount(1);
        module.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties({
                managerAddress: nodeOperatorOwner,
                rewardAddress: nodeOperatorOwner,
                extendedManagerPermissions: true
            })
        );
        stakingRouter = StakingRouterMock(module.LIDO_LOCATOR().stakingRouter());
        address[] memory modules = new address[](1);
        modules[0] = address(module);
        stakingRouter.setModules(modules);

        registry = new MetaRegistry(address(module));
        module.mock_setMetaRegistry(address(registry));
        _enableInitializers(address(registry));
        registry.initialize(admin);

        vm.startPrank(admin);
        registry.grantRole(registry.MANAGE_OPERATOR_GROUPS_ROLE(), groupManager);
        registry.grantRole(registry.SET_BOND_CURVE_WEIGHT_ROLE(), bondCurveWeightManager);
        vm.stopPrank();

        token = new ERC20Testable();
        voting = new LidoAragonVotingMock();
        snapshotDelegation = new SnapshotDelegationMock();
        address expectedProvider = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);
        vaultImpl = new LidoGovernanceLockVault(
            address(token),
            expectedProvider,
            address(module),
            address(voting),
            address(snapshotDelegation)
        );
        vaultBeacon = new UpgradeableBeacon(address(vaultImpl), admin);
        provider = new ERC20LockBoostProvider(address(module), address(token), address(vaultBeacon), MIN_LOCK_PERIOD);
        assertEq(address(provider), expectedProvider);
        _enableInitializers(address(provider));
        provider.initialize(admin, LOCK_PERIOD, _defaultSteps());

        vm.prank(admin);
        registry.addWeightBoostProvider(provider, IMetaRegistry.WeightBoostProviderMode.MaxPerGroup);

        vm.prank(bondCurveWeightManager);
        registry.setBondCurveWeight(0, BASE_WEIGHT);

        vm.prank(groupManager);
        registry.createOrUpdateOperatorGroup(
            0,
            IMetaRegistry.OperatorGroup({
                name: "Alpha",
                subNodeOperators: _subOperatorsArr1(uint64(NODE_OPERATOR_ID), 10000),
                externalOperators: _extOperatorsArr0()
            })
        );
    }

    function _setDefaultSteps() internal {
        vm.prank(admin);
        provider.setSteps(_defaultSteps());
    }

    function _defaultSteps() internal pure returns (Step[] memory) {
        return _steps(STEP_1_AMOUNT, STEP_1_WEIGHT_BOOST_BP, STEP_2_AMOUNT, STEP_2_WEIGHT_BOOST_BP);
    }

    function _mintAndApprove(uint256 amount) internal {
        token.mint(nodeOperatorOwner, amount);
        vm.prank(nodeOperatorOwner);
        token.approve(address(provider), amount);
    }

    function _lock(uint256 amount) internal {
        _mintAndApprove(amount);
        vm.prank(nodeOperatorOwner);
        provider.lock(NODE_OPERATOR_ID, amount);
    }

    function _weight(uint256 multiplierBP) internal pure returns (uint256) {
        return (BASE_WEIGHT * multiplierBP) / MAX_BP;
    }

    function _subOperatorsArr1(
        uint64 nodeOperatorId,
        uint16 share
    ) internal pure returns (IMetaRegistry.SubNodeOperator[] memory ops) {
        ops = new IMetaRegistry.SubNodeOperator[](1);
        ops[0] = IMetaRegistry.SubNodeOperator({ nodeOperatorId: nodeOperatorId, share: share });
    }

    function _subOperatorsArr2(
        IMetaRegistry.SubNodeOperator memory op0,
        IMetaRegistry.SubNodeOperator memory op1
    ) internal pure returns (IMetaRegistry.SubNodeOperator[] memory ops) {
        ops = new IMetaRegistry.SubNodeOperator[](2);
        ops[0] = op0;
        ops[1] = op1;
    }

    function _extOperatorsArr0() internal pure returns (IMetaRegistry.ExternalOperator[] memory ops) {}

    function _subOperatorsArr0() internal pure returns (IMetaRegistry.SubNodeOperator[] memory ops) {}

    function _steps(
        uint128 amount0,
        uint128 weightBoost0,
        uint128 amount1,
        uint128 weightBoost1
    ) internal pure returns (Step[] memory steps) {
        steps = new Step[](2);
        steps[0] = Step({ threshold: amount0, value: weightBoost0 });
        steps[1] = Step({ threshold: amount1, value: weightBoost1 });
    }

    function _steps1(uint128 amount, uint128 weightBoost) internal pure returns (Step[] memory steps) {
        steps = new Step[](1);
        steps[0] = Step({ threshold: amount, value: weightBoost });
    }

    function _steps0() internal pure returns (Step[] memory steps) {}
}

contract ERC20LockBoostProviderConstructorTest is ERC20LockBoostProviderBaseTest {
    function test_constructor_SetsImmutables() public view {
        assertEq(address(provider.MODULE()), address(module));
        assertEq(address(provider.META_REGISTRY()), address(registry));
        assertEq(provider.TOKEN(), address(token));
        assertEq(address(provider.VAULT_BEACON()), address(vaultBeacon));
        assertEq(provider.MIN_LOCK_PERIOD(), MIN_LOCK_PERIOD);
        assertEq(provider.MAX_LOCK_PERIOD(), MAX_LOCK_PERIOD);
    }

    function test_constructor_RevertWhen_ZeroAddresses() public {
        vm.expectRevert(IBaseWeightBoostProvider.ZeroModuleAddress.selector);
        new ERC20LockBoostProvider(address(0), address(token), address(vaultBeacon), MIN_LOCK_PERIOD);

        vm.expectRevert(IERC20LockBoostProvider.ZeroTokenAddress.selector);
        new ERC20LockBoostProvider(address(module), address(0), address(vaultBeacon), MIN_LOCK_PERIOD);

        vm.expectRevert(IERC20LockBoostProvider.ZeroVaultBeaconAddress.selector);
        new ERC20LockBoostProvider(address(module), address(token), address(0), MIN_LOCK_PERIOD);
    }

    function test_constructor_RevertWhen_InvalidMinLockPeriod() public {
        vm.expectRevert(IERC20LockBoostProvider.InvalidLockPeriod.selector);
        new ERC20LockBoostProvider(address(module), address(token), address(vaultBeacon), 0);

        vm.expectRevert(IERC20LockBoostProvider.InvalidLockPeriod.selector);
        new ERC20LockBoostProvider(address(module), address(token), address(vaultBeacon), MAX_LOCK_PERIOD + 1);
    }
}

contract ERC20LockBoostProviderInitializeTest is ERC20LockBoostProviderBaseTest {
    function test_initialize_SetsAdminLockPeriodAndSteps() public view {
        assertEq(provider.getInitializedVersion(), 1);
        assertEq(provider.getLockPeriod(), LOCK_PERIOD);
        assertTrue(provider.hasRole(provider.DEFAULT_ADMIN_ROLE(), admin));
        Step[] memory steps = provider.getSteps();
        assertEq(steps.length, 2);
        assertEq(steps[0].threshold, STEP_1_AMOUNT);
        assertEq(steps[0].value, STEP_1_WEIGHT_BOOST_BP);
        assertEq(steps[1].threshold, STEP_2_AMOUNT);
        assertEq(steps[1].value, STEP_2_WEIGHT_BOOST_BP);
    }

    function test_initialize_DoesNotNotifyProviderConfigChanged() public {
        ERC20LockBoostProvider p = new ERC20LockBoostProvider(
            address(module),
            address(token),
            address(vaultBeacon),
            MIN_LOCK_PERIOD
        );
        _enableInitializers(address(p));

        expectNoCall(
            address(registry),
            abi.encodeWithSelector(IMetaRegistry.notifyWeightBoostProviderConfigChanged.selector)
        );
        p.initialize(admin, LOCK_PERIOD, _defaultSteps());
    }

    function test_initialize_RevertWhen_ZeroAdmin() public {
        ERC20LockBoostProvider p = new ERC20LockBoostProvider(
            address(module),
            address(token),
            address(vaultBeacon),
            MIN_LOCK_PERIOD
        );
        _enableInitializers(address(p));

        vm.expectRevert(IBaseWeightBoostProvider.ZeroAdminAddress.selector);
        p.initialize(address(0), LOCK_PERIOD, _defaultSteps());
    }

    function test_initialize_RevertWhen_InvalidLockPeriod() public {
        ERC20LockBoostProvider p = new ERC20LockBoostProvider(
            address(module),
            address(token),
            address(vaultBeacon),
            MIN_LOCK_PERIOD
        );
        _enableInitializers(address(p));

        vm.expectRevert(IERC20LockBoostProvider.InvalidLockPeriod.selector);
        p.initialize(admin, MIN_LOCK_PERIOD - 1, _defaultSteps());
    }

    function test_initialize_RevertWhen_DoubleCall() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        provider.initialize(admin, LOCK_PERIOD, _defaultSteps());
    }
}

contract ERC20LockBoostProviderAdminTest is ERC20LockBoostProviderBaseTest, StepwiseWeightBoostBehaviour {
    function _stepwise() internal view override returns (IStepwiseWeightBoost) {
        return IStepwiseWeightBoost(address(provider));
    }

    function _stepwiseAdmin() internal view override returns (address) {
        return admin;
    }

    function _stepwiseSteps(uint256 count) internal view override returns (Step[] memory steps) {
        steps = new Step[](count);
        for (uint256 i; i < count; ++i) {
            // Locked amounts must be nonzero.
            steps[i] = Step({ threshold: uint128((i + 1) * 1 ether), value: uint128((i + 1) * 100) });
        }
    }

    function test_setLockPeriod() public {
        uint256 newLockPeriod = LOCK_PERIOD + 1 days;

        vm.expectEmit(address(provider));
        emit IERC20LockBoostProvider.LockPeriodSet(newLockPeriod);
        vm.prank(admin);
        provider.setLockPeriod(newLockPeriod);

        assertEq(provider.getLockPeriod(), newLockPeriod);
    }

    function test_setLockPeriod_RevertWhen_NotAdmin() public {
        expectRoleRevert(stranger, provider.DEFAULT_ADMIN_ROLE());
        vm.prank(stranger);
        provider.setLockPeriod(LOCK_PERIOD + 1 days);
    }

    function test_setLockPeriod_RevertWhen_SamePeriod() public {
        vm.prank(admin);
        vm.expectRevert(IERC20LockBoostProvider.SameLockPeriod.selector);
        provider.setLockPeriod(LOCK_PERIOD);
    }

    function test_setLockPeriod_RevertWhen_InvalidPeriod() public {
        vm.prank(admin);
        vm.expectRevert(IERC20LockBoostProvider.InvalidLockPeriod.selector);
        provider.setLockPeriod(MIN_LOCK_PERIOD - 1);
    }

    function test_setSteps() public {
        Step[] memory steps = _steps(STEP_1_AMOUNT, STEP_1_WEIGHT_BOOST_BP, STEP_2_AMOUNT, STEP_2_WEIGHT_BOOST_BP);

        vm.expectEmit(address(provider));
        emit IStepwiseWeightBoost.StepsSet(steps);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(IMetaRegistry.notifyWeightBoostProviderConfigChanged.selector)
        );
        vm.prank(admin);
        provider.setSteps(steps);

        Step[] memory stored = provider.getSteps();
        assertEq(stored.length, 2);
        assertEq(stored[0].threshold, STEP_1_AMOUNT);
        assertEq(stored[0].value, STEP_1_WEIGHT_BOOST_BP);
        assertEq(stored[1].threshold, STEP_2_AMOUNT);
        assertEq(stored[1].value, STEP_2_WEIGHT_BOOST_BP);
    }

    function test_setSteps_DoesNotRefreshExistingWeights() public {
        _setDefaultSteps();
        _lock(STEP_2_AMOUNT);
        assertEq(provider.getWeightBoostMultiplierBP(NODE_OPERATOR_ID), STEP_2_MULTIPLIER_BP);
        assertEq(registry.getNodeOperatorWeight(NODE_OPERATOR_ID), _weight(STEP_2_MULTIPLIER_BP));

        vm.prank(admin);
        provider.setSteps(_steps1(STEP_2_AMOUNT + 1, 2_000));

        assertEq(provider.getWeightBoostMultiplierBP(NODE_OPERATOR_ID), MAX_BP);
        assertEq(registry.getNodeOperatorWeight(NODE_OPERATOR_ID), _weight(STEP_2_MULTIPLIER_BP));

        registry.refreshOperatorWeight(NODE_OPERATOR_ID);
        assertEq(registry.getNodeOperatorWeight(NODE_OPERATOR_ID), BASE_WEIGHT);
    }

    function test_setSteps_AllowsZeroWeightBoost() public {
        vm.prank(admin);
        provider.setSteps(_steps1(STEP_1_AMOUNT, 0));

        _lock(STEP_1_AMOUNT);

        assertEq(provider.getWeightBoostMultiplierBP(NODE_OPERATOR_ID), MAX_BP);
        assertEq(registry.getNodeOperatorWeight(NODE_OPERATOR_ID), BASE_WEIGHT);
    }

    /// @dev A lock threshold of zero would boost operators that locked nothing.
    function test_setSteps_RevertWhen_ZeroThreshold() public {
        vm.expectRevert(abi.encodeWithSelector(IStepwiseWeightBoost.InvalidStep.selector, 0));
        vm.prank(admin);
        provider.setSteps(_steps1(0, STEP_1_WEIGHT_BOOST_BP));
    }
}

contract ERC20LockBoostProviderLockTest is ERC20LockBoostProviderBaseTest {
    function test_lock_CreatesVaultAndLocksTokens() public {
        _setDefaultSteps();
        uint256 amount = STEP_1_AMOUNT;
        uint256 nowTs = 1000;
        vm.warp(nowTs);

        _mintAndApprove(amount);
        vm.expectEmit(address(provider));
        emit IERC20LockBoostProvider.TokensLocked(NODE_OPERATOR_ID, amount, nowTs + LOCK_PERIOD);
        vm.prank(nodeOperatorOwner);
        provider.lock(NODE_OPERATOR_ID, amount);

        IERC20LockBoostProvider.OperatorLock memory lockInfo = provider.getLock(NODE_OPERATOR_ID);
        assertTrue(lockInfo.vault != address(0));
        assertEq(provider.getVault(NODE_OPERATOR_ID), lockInfo.vault);
        assertEq(LidoGovernanceLockVault(lockInfo.vault).VOTING_CONTRACT(), address(voting));
        assertEq(LidoGovernanceLockVault(lockInfo.vault).snapshotDelegation(), address(snapshotDelegation));
        assertEq(lockInfo.amount, amount);
        assertEq(lockInfo.lockUntil, nowTs + LOCK_PERIOD);
        assertEq(token.balanceOf(lockInfo.vault), amount);
        assertEq(provider.getWeightBoostMultiplierBP(NODE_OPERATOR_ID), STEP_1_MULTIPLIER_BP);
        assertEq(registry.getNodeOperatorWeight(NODE_OPERATOR_ID), _weight(STEP_1_MULTIPLIER_BP));
    }

    function test_lock_ResetsLockUntil() public {
        _setDefaultSteps();
        vm.warp(1000);
        _lock(1 ether);

        vm.warp(2000);
        _lock(1 ether);

        IERC20LockBoostProvider.OperatorLock memory lockInfo = provider.getLock(NODE_OPERATOR_ID);
        assertEq(lockInfo.amount, 2 ether);
        assertEq(lockInfo.lockUntil, 2000 + LOCK_PERIOD);
    }

    function test_lock_DoesNotRefreshRegistryWhenBoostUnchanged() public {
        _setDefaultSteps();
        _lock(STEP_1_AMOUNT);

        expectNoCall(
            address(registry),
            abi.encodeWithSelector(IMetaRegistry.notifyWeightBoostChanged.selector, NODE_OPERATOR_ID)
        );
        _lock(1 ether);

        assertEq(provider.getWeightBoostMultiplierBP(NODE_OPERATOR_ID), STEP_1_MULTIPLIER_BP);
    }

    function test_lock_RefreshesRegistryWhenBoostIncreases() public {
        _setDefaultSteps();
        _lock(STEP_1_AMOUNT);

        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(IMetaRegistry.notifyWeightBoostChanged.selector, NODE_OPERATOR_ID)
        );
        _lock(STEP_2_AMOUNT - STEP_1_AMOUNT);

        assertEq(provider.getWeightBoostMultiplierBP(NODE_OPERATOR_ID), STEP_2_MULTIPLIER_BP);
        assertEq(registry.getNodeOperatorWeight(NODE_OPERATOR_ID), _weight(STEP_2_MULTIPLIER_BP));
    }

    function test_lock_MaxPerGroupBoostAppliesToWholeGroup() public {
        module.mock_setNodeOperatorsCount(2);
        _setDefaultSteps();
        _lock(STEP_1_AMOUNT);

        IMetaRegistry.SubNodeOperator memory op0 = IMetaRegistry.SubNodeOperator({
            nodeOperatorId: uint64(NODE_OPERATOR_ID),
            share: 5000
        });
        IMetaRegistry.SubNodeOperator memory op1 = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 1, share: 5000 });

        vm.prank(groupManager);
        registry.createOrUpdateOperatorGroup(
            GROUP_ID,
            IMetaRegistry.OperatorGroup({
                name: "Alpha",
                subNodeOperators: _subOperatorsArr2(op0, op1),
                externalOperators: _extOperatorsArr0()
            })
        );

        assertEq(provider.getWeightBoostMultiplierBP(NODE_OPERATOR_ID), STEP_1_MULTIPLIER_BP);
        assertEq(provider.getWeightBoostMultiplierBP(1), MAX_BP);
        assertEq(registry.getNodeOperatorWeight(NODE_OPERATOR_ID), _weight(STEP_1_MULTIPLIER_BP) / 2);
        assertEq(registry.getNodeOperatorWeight(1), _weight(STEP_1_MULTIPLIER_BP) / 2);
    }

    function test_lock_RevertWhen_InvalidAmount() public {
        vm.prank(nodeOperatorOwner);
        vm.expectRevert(IERC20LockBoostProvider.InvalidAmount.selector);
        provider.lock(NODE_OPERATOR_ID, 0);
    }

    function test_lock_RevertWhen_NotNodeOperatorOwner() public {
        vm.prank(stranger);
        vm.expectRevert(IBaseWeightBoostProvider.SenderIsNotNodeOperatorOwner.selector);
        provider.lock(NODE_OPERATOR_ID, 1 ether);
    }

    function test_lock_RevertWhen_NodeOperatorDoesNotExist() public {
        vm.prank(nodeOperatorOwner);
        vm.expectRevert(IBaseWeightBoostProvider.NodeOperatorDoesNotExist.selector);
        provider.lock(NODE_OPERATOR_ID + 1, 1 ether);
    }
}

contract ERC20LockBoostProviderWithdrawTest is ERC20LockBoostProviderBaseTest {
    function test_withdraw_AfterLockPeriod() public {
        _setDefaultSteps();
        _lock(STEP_2_AMOUNT);
        IERC20LockBoostProvider.OperatorLock memory lockInfo = provider.getLock(NODE_OPERATOR_ID);

        vm.warp(lockInfo.lockUntil);
        vm.expectEmit(address(provider));
        emit IERC20LockBoostProvider.TokensWithdrawn(NODE_OPERATOR_ID, receiver, 60 ether, 140 ether);
        vm.prank(nodeOperatorOwner);
        provider.withdraw(NODE_OPERATOR_ID, 60 ether, receiver);

        lockInfo = provider.getLock(NODE_OPERATOR_ID);
        assertEq(lockInfo.amount, 140 ether);
        assertEq(token.balanceOf(receiver), 60 ether);
        assertEq(provider.getWeightBoostMultiplierBP(NODE_OPERATOR_ID), STEP_1_MULTIPLIER_BP);
        assertEq(registry.getNodeOperatorWeight(NODE_OPERATOR_ID), _weight(STEP_1_MULTIPLIER_BP));
    }

    function test_withdraw_ClearsLockUntilWhenFullyWithdrawn() public {
        _lock(10 ether);
        IERC20LockBoostProvider.OperatorLock memory lockInfo = provider.getLock(NODE_OPERATOR_ID);

        vm.warp(lockInfo.lockUntil);
        vm.prank(nodeOperatorOwner);
        provider.withdraw(NODE_OPERATOR_ID, 10 ether, receiver);

        lockInfo = provider.getLock(NODE_OPERATOR_ID);
        assertEq(lockInfo.amount, 0);
        assertEq(lockInfo.lockUntil, 0);
    }

    function test_withdraw_AfterVaultImplementationUpgrade() public {
        _lock(10 ether);
        IERC20LockBoostProvider.OperatorLock memory lockInfo = provider.getLock(NODE_OPERATOR_ID);
        IERC20LockVault vault = IERC20LockVault(lockInfo.vault);
        SnapshotDelegationMock newSnapshotDelegation = new SnapshotDelegationMock();
        LidoGovernanceLockVault newVaultImpl = new LidoGovernanceLockVault(
            address(token),
            address(provider),
            address(module),
            address(voting),
            address(newSnapshotDelegation)
        );

        vm.prank(admin);
        vaultBeacon.upgradeTo(address(newVaultImpl));

        assertEq(vault.nodeOperatorId(), NODE_OPERATOR_ID);
        assertEq(vault.TOKEN(), address(token));
        assertEq(vault.PROVIDER(), address(provider));
        assertEq(address(vault.MODULE()), address(module));
        assertEq(token.balanceOf(lockInfo.vault), 10 ether);

        vm.warp(lockInfo.lockUntil);
        vm.prank(nodeOperatorOwner);
        provider.withdraw(NODE_OPERATOR_ID, 10 ether, receiver);

        assertEq(token.balanceOf(receiver), 10 ether);
        assertEq(token.balanceOf(lockInfo.vault), 0);
    }

    function test_withdraw_DoesNotRefreshRegistryWhenBoostUnchanged() public {
        _setDefaultSteps();
        _lock(STEP_1_AMOUNT + 10 ether);
        IERC20LockBoostProvider.OperatorLock memory lockInfo = provider.getLock(NODE_OPERATOR_ID);

        vm.warp(lockInfo.lockUntil);
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(IMetaRegistry.notifyWeightBoostChanged.selector, NODE_OPERATOR_ID)
        );
        vm.prank(nodeOperatorOwner);
        provider.withdraw(NODE_OPERATOR_ID, 1 ether, receiver);

        assertEq(provider.getWeightBoostMultiplierBP(NODE_OPERATOR_ID), STEP_1_MULTIPLIER_BP);
    }

    function test_withdraw_RevertWhen_LockPeriodNotEnded() public {
        _lock(10 ether);

        vm.prank(nodeOperatorOwner);
        vm.expectRevert(IERC20LockBoostProvider.LockPeriodNotEnded.selector);
        provider.withdraw(NODE_OPERATOR_ID, 1 ether, receiver);
    }

    function test_withdraw_AllowsEarlyWithdrawalWhenOperatorRemovedAndInactive() public {
        _lock(10 ether);

        vm.prank(groupManager);
        registry.createOrUpdateOperatorGroup(
            GROUP_ID,
            IMetaRegistry.OperatorGroup({
                name: "",
                subNodeOperators: _subOperatorsArr0(),
                externalOperators: _extOperatorsArr0()
            })
        );

        vm.prank(nodeOperatorOwner);
        provider.withdraw(NODE_OPERATOR_ID, 10 ether, receiver);

        assertEq(token.balanceOf(receiver), 10 ether);
    }

    function test_withdraw_RevertWhen_EarlyWithdrawalOutsideGroupButDepositable() public {
        NodeOperator memory no;
        no.depositableValidatorsCount = 1;
        module.mock_setNodeOperator(no);

        _lock(10 ether);
        vm.prank(groupManager);
        registry.createOrUpdateOperatorGroup(
            GROUP_ID,
            IMetaRegistry.OperatorGroup({
                name: "",
                subNodeOperators: _subOperatorsArr0(),
                externalOperators: _extOperatorsArr0()
            })
        );

        vm.prank(nodeOperatorOwner);
        vm.expectRevert(IERC20LockBoostProvider.LockPeriodNotEnded.selector);
        provider.withdraw(NODE_OPERATOR_ID, 10 ether, receiver);
    }

    function test_withdraw_RevertWhen_InvalidInputs() public {
        _lock(10 ether);
        IERC20LockBoostProvider.OperatorLock memory lockInfo = provider.getLock(NODE_OPERATOR_ID);
        vm.warp(lockInfo.lockUntil);

        vm.startPrank(nodeOperatorOwner);

        vm.expectRevert(IERC20LockVault.ZeroReceiverAddress.selector);
        provider.withdraw(NODE_OPERATOR_ID, 1 ether, address(0));

        vm.expectRevert(IERC20LockBoostProvider.InvalidAmount.selector);
        provider.withdraw(NODE_OPERATOR_ID, 0, receiver);

        vm.expectRevert(IERC20LockBoostProvider.InvalidAmount.selector);
        provider.withdraw(NODE_OPERATOR_ID, 11 ether, receiver);

        vm.stopPrank();
    }

    function test_withdraw_RevertWhen_NoTokensLocked() public {
        vm.prank(nodeOperatorOwner);
        vm.expectRevert(IERC20LockBoostProvider.NoTokensLocked.selector);
        provider.withdraw(NODE_OPERATOR_ID, 1 ether, receiver);
    }

    function test_withdraw_InternalGuardRevertWhen_NoTokensLocked() public {
        ERC20LockBoostProviderForTest p = new ERC20LockBoostProviderForTest(
            address(module),
            address(token),
            address(vaultBeacon),
            MIN_LOCK_PERIOD
        );

        vm.expectRevert(IERC20LockBoostProvider.NoTokensLocked.selector);
        p.mock_withdraw(NODE_OPERATOR_ID, 1 ether, receiver);
    }
}

contract ERC20LockBoostProviderVotingTest is ERC20LockBoostProviderBaseTest {
    function test_assignAndUnassignVotingDelegate() public {
        _lock(10 ether);
        IERC20LockBoostProvider.OperatorLock memory lockInfo = provider.getLock(NODE_OPERATOR_ID);
        IAragonVotingLockVault vault = IAragonVotingLockVault(lockInfo.vault);

        vm.prank(nodeOperatorOwner);
        vault.assignVotingDelegate(votingDelegate);

        assertEq(voting.delegateOf(lockInfo.vault), votingDelegate);

        vm.prank(nodeOperatorOwner);
        vault.unassignVotingDelegate();

        assertEq(voting.delegateOf(lockInfo.vault), address(0));
    }

    function test_assignAndUnassignSnapshotDelegate() public {
        _lock(10 ether);
        IERC20LockBoostProvider.OperatorLock memory lockInfo = provider.getLock(NODE_OPERATOR_ID);
        ISnapshotDelegationLockVault vault = ISnapshotDelegationLockVault(lockInfo.vault);

        vm.prank(nodeOperatorOwner);
        vault.assignSnapshotDelegate(snapshotDelegate);

        assertEq(snapshotDelegation.delegateOf(lockInfo.vault, SNAPSHOT_ALL_SPACES), snapshotDelegate);
        assertEq(snapshotDelegation.lastDelegator(), lockInfo.vault);
        assertEq(snapshotDelegation.lastId(), SNAPSHOT_ALL_SPACES);

        vm.prank(nodeOperatorOwner);
        vault.unassignSnapshotDelegate();

        assertEq(snapshotDelegation.delegateOf(lockInfo.vault, SNAPSHOT_ALL_SPACES), address(0));
        assertEq(snapshotDelegation.lastDelegator(), lockInfo.vault);
        assertEq(snapshotDelegation.lastId(), SNAPSHOT_ALL_SPACES);
    }

    function test_assignVotingDelegate_ReassignsAndCanAssignAfterUnassign() public {
        address newVotingDelegate = nextAddress("NEW_VOTING_DELEGATE");

        _lock(10 ether);
        IERC20LockBoostProvider.OperatorLock memory lockInfo = provider.getLock(NODE_OPERATOR_ID);
        IAragonVotingLockVault vault = IAragonVotingLockVault(lockInfo.vault);

        vm.startPrank(nodeOperatorOwner);
        vault.assignVotingDelegate(votingDelegate);
        vault.assignVotingDelegate(newVotingDelegate);

        assertEq(voting.delegateOf(lockInfo.vault), newVotingDelegate);

        vault.unassignVotingDelegate();
        vault.assignVotingDelegate(votingDelegate);
        vm.stopPrank();

        assertEq(voting.delegateOf(lockInfo.vault), votingDelegate);
    }

    function test_vote() public {
        _lock(10 ether);
        IERC20LockBoostProvider.OperatorLock memory lockInfo = provider.getLock(NODE_OPERATOR_ID);
        IAragonVotingLockVault vault = IAragonVotingLockVault(lockInfo.vault);

        vm.prank(nodeOperatorOwner);
        vault.vote(42, true);

        assertEq(voting.lastVoter(), lockInfo.vault);
        assertEq(voting.lastVoteId(), 42);
        assertTrue(voting.lastSupport());
        assertFalse(voting.lastExecutesIfDecided());
    }

    function test_assignVotingDelegate_AllowsZeroDelegate() public {
        _lock(10 ether);
        IERC20LockBoostProvider.OperatorLock memory lockInfo = provider.getLock(NODE_OPERATOR_ID);
        IAragonVotingLockVault vault = IAragonVotingLockVault(lockInfo.vault);

        vm.prank(nodeOperatorOwner);
        vault.assignVotingDelegate(address(0));

        assertEq(voting.delegateOf(lockInfo.vault), address(0));
    }

    function test_assignVotingDelegate_AllowsSameDelegate() public {
        _lock(10 ether);
        IERC20LockBoostProvider.OperatorLock memory lockInfo = provider.getLock(NODE_OPERATOR_ID);
        IAragonVotingLockVault vault = IAragonVotingLockVault(lockInfo.vault);

        vm.startPrank(nodeOperatorOwner);
        vault.assignVotingDelegate(votingDelegate);
        vault.assignVotingDelegate(votingDelegate);
        vm.stopPrank();

        assertEq(voting.delegateOf(lockInfo.vault), votingDelegate);
    }

    function test_assignDelegates_AllowsEmptyVault() public {
        _lock(10 ether);
        IERC20LockBoostProvider.OperatorLock memory lockInfo = provider.getLock(NODE_OPERATOR_ID);
        vm.warp(lockInfo.lockUntil);

        vm.prank(nodeOperatorOwner);
        provider.withdraw(NODE_OPERATOR_ID, 10 ether, receiver);

        vm.startPrank(nodeOperatorOwner);
        IAragonVotingLockVault(lockInfo.vault).assignVotingDelegate(votingDelegate);
        ISnapshotDelegationLockVault(lockInfo.vault).assignSnapshotDelegate(snapshotDelegate);
        vm.stopPrank();

        assertEq(voting.delegateOf(lockInfo.vault), votingDelegate);
        assertEq(snapshotDelegation.delegateOf(lockInfo.vault, SNAPSHOT_ALL_SPACES), snapshotDelegate);
    }

    function test_getVault_ReturnsZeroWhenNoVaultCreated() public view {
        assertEq(provider.getVault(NODE_OPERATOR_ID), address(0));
    }
}

contract ERC20LockVaultTest is Test, Utilities {
    ERC20Testable public token;
    ERC20LockVault public vaultImpl;
    UpgradeableBeacon public vaultBeacon;
    ERC20LockVault public vault;

    address public admin;
    address public provider;
    address public module;
    address public receiver;
    address public stranger;

    uint256 internal constant NODE_OPERATOR_ID = 13;

    function setUp() public {
        admin = nextAddress("ADMIN");
        provider = nextAddress("PROVIDER");
        module = nextAddress("MODULE");
        receiver = nextAddress("RECEIVER");
        stranger = nextAddress("STRANGER");

        token = new ERC20Testable();
        vaultImpl = new ERC20LockVault(address(token), provider, module);
        vaultBeacon = new UpgradeableBeacon(address(vaultImpl), admin);
        vault = ERC20LockVault(
            address(
                new BeaconProxy({
                    beacon: address(vaultBeacon),
                    data: abi.encodeCall(IERC20LockVault.initialize, (NODE_OPERATOR_ID))
                })
            )
        );
    }

    function test_initialize_SetsState() public view {
        assertEq(vault.nodeOperatorId(), NODE_OPERATOR_ID);
        assertEq(vault.TOKEN(), address(token));
        assertEq(vault.PROVIDER(), provider);
        assertEq(address(vault.MODULE()), module);
    }

    function test_constructor_RevertWhen_ZeroAddresses() public {
        vm.expectRevert(IERC20LockVault.ZeroTokenAddress.selector);
        new ERC20LockVault(address(0), provider, module);

        vm.expectRevert(IERC20LockVault.ZeroProviderAddress.selector);
        new ERC20LockVault(address(token), address(0), module);

        vm.expectRevert(IERC20LockVault.ZeroModuleAddress.selector);
        new ERC20LockVault(address(token), provider, address(0));
    }

    function test_initialize_RevertWhen_DoubleCall() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(NODE_OPERATOR_ID);
    }

    function test_transferTokens() public {
        token.mint(address(vault), 1 ether);

        vm.prank(provider);
        vault.transferTokens(receiver, 1 ether);

        assertEq(token.balanceOf(receiver), 1 ether);
    }

    function test_transferTokens_RevertWhen_InvalidCallerOrReceiver() public {
        token.mint(address(vault), 1 ether);

        vm.prank(stranger);
        vm.expectRevert(IERC20LockVault.SenderIsNotProvider.selector);
        vault.transferTokens(receiver, 1 ether);

        vm.prank(provider);
        vm.expectRevert(IERC20LockVault.ZeroReceiverAddress.selector);
        vault.transferTokens(address(0), 1 ether);
    }
}

contract LidoGovernanceLockVaultTest is Test, Utilities {
    CuratedMock public module;
    ERC20Testable public token;
    LidoAragonVotingMock public voting;
    SnapshotDelegationMock public snapshotDelegation;
    LidoGovernanceLockVault public vaultImpl;
    UpgradeableBeacon public vaultBeacon;
    LidoGovernanceLockVault public vault;

    address public admin;
    address public provider;
    address public nodeOperatorOwner;
    address public votingDelegate;
    address public snapshotDelegate;
    address public stranger;

    uint256 internal constant NODE_OPERATOR_ID = 0;
    bytes32 internal constant SNAPSHOT_ALL_SPACES = bytes32(0);

    function setUp() public {
        admin = nextAddress("ADMIN");
        provider = nextAddress("PROVIDER");
        nodeOperatorOwner = nextAddress("NODE_OPERATOR_OWNER");
        votingDelegate = nextAddress("VOTING_DELEGATE");
        snapshotDelegate = nextAddress("SNAPSHOT_DELEGATE");
        stranger = nextAddress("STRANGER");

        module = new CuratedMock();
        module.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties({
                managerAddress: nodeOperatorOwner,
                rewardAddress: nodeOperatorOwner,
                extendedManagerPermissions: true
            })
        );
        token = new ERC20Testable();
        voting = new LidoAragonVotingMock();
        snapshotDelegation = new SnapshotDelegationMock();
        vaultImpl = new LidoGovernanceLockVault(
            address(token),
            provider,
            address(module),
            address(voting),
            address(snapshotDelegation)
        );
        vaultBeacon = new UpgradeableBeacon(address(vaultImpl), admin);
        vault = LidoGovernanceLockVault(
            address(
                new BeaconProxy({
                    beacon: address(vaultBeacon),
                    data: abi.encodeCall(IERC20LockVault.initialize, (NODE_OPERATOR_ID))
                })
            )
        );
    }

    function test_initialize_SetsStateAndImmutables() public view {
        assertEq(vault.nodeOperatorId(), NODE_OPERATOR_ID);
        assertEq(vault.TOKEN(), address(token));
        assertEq(vault.PROVIDER(), provider);
        assertEq(address(vault.MODULE()), address(module));
        assertEq(vault.VOTING_CONTRACT(), address(voting));
        assertEq(vault.SNAPSHOT_DELEGATION(), address(snapshotDelegation));
        assertEq(vault.snapshotDelegation(), address(snapshotDelegation));
    }

    function test_constructor_RevertWhen_ZeroGovernanceAddresses() public {
        vm.expectRevert(IAragonVotingLockVault.ZeroVotingContractAddress.selector);
        new LidoGovernanceLockVault(address(token), provider, address(module), address(0), address(snapshotDelegation));

        vm.expectRevert(ISnapshotDelegationLockVault.ZeroSnapshotDelegationAddress.selector);
        new LidoGovernanceLockVault(address(token), provider, address(module), address(voting), address(0));
    }

    function test_assignAndUnassignVotingDelegate() public {
        vm.prank(nodeOperatorOwner);
        vault.assignVotingDelegate(votingDelegate);

        assertEq(voting.delegateOf(address(vault)), votingDelegate);

        vm.prank(nodeOperatorOwner);
        vault.unassignVotingDelegate();

        assertEq(voting.delegateOf(address(vault)), address(0));
    }

    function test_assignAndUnassignSnapshotDelegate() public {
        vm.prank(nodeOperatorOwner);
        vault.assignSnapshotDelegate(snapshotDelegate);

        assertEq(snapshotDelegation.delegateOf(address(vault), SNAPSHOT_ALL_SPACES), snapshotDelegate);
        assertEq(snapshotDelegation.lastDelegator(), address(vault));
        assertEq(snapshotDelegation.lastId(), SNAPSHOT_ALL_SPACES);

        vm.prank(nodeOperatorOwner);
        vault.unassignSnapshotDelegate();

        assertEq(snapshotDelegation.delegateOf(address(vault), SNAPSHOT_ALL_SPACES), address(0));
        assertEq(snapshotDelegation.lastDelegator(), address(vault));
        assertEq(snapshotDelegation.lastId(), SNAPSHOT_ALL_SPACES);
    }

    function test_assignSnapshotDelegate_UsesCurrentBeaconImplementation() public {
        SnapshotDelegationMock newSnapshotDelegation = new SnapshotDelegationMock();
        LidoGovernanceLockVault newVaultImpl = new LidoGovernanceLockVault(
            address(token),
            provider,
            address(module),
            address(voting),
            address(newSnapshotDelegation)
        );

        vm.prank(admin);
        vaultBeacon.upgradeTo(address(newVaultImpl));

        vm.prank(nodeOperatorOwner);
        vault.assignSnapshotDelegate(snapshotDelegate);

        assertEq(vault.snapshotDelegation(), address(newSnapshotDelegation));
        assertEq(snapshotDelegation.delegateOf(address(vault), SNAPSHOT_ALL_SPACES), address(0));
        assertEq(newSnapshotDelegation.delegateOf(address(vault), SNAPSHOT_ALL_SPACES), snapshotDelegate);
    }

    function test_vote() public {
        vm.prank(nodeOperatorOwner);
        vault.vote(42, true);

        assertEq(voting.lastVoter(), address(vault));
        assertEq(voting.lastVoteId(), 42);
        assertTrue(voting.lastSupport());
        assertFalse(voting.lastExecutesIfDecided());
    }

    function test_votingCalls_RevertWhen_InvalidCaller() public {
        vm.prank(stranger);
        vm.expectRevert(IERC20LockVault.SenderIsNotNodeOperatorOwner.selector);
        vault.vote(42, true);
    }

    function test_snapshotDelegationCalls_RevertWhen_InvalidCaller() public {
        vm.prank(stranger);
        vm.expectRevert(IERC20LockVault.SenderIsNotNodeOperatorOwner.selector);
        vault.assignSnapshotDelegate(snapshotDelegate);

        vm.prank(stranger);
        vm.expectRevert(IERC20LockVault.SenderIsNotNodeOperatorOwner.selector);
        vault.unassignSnapshotDelegate();
    }
}
