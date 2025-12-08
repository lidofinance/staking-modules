// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { OneShotCurveSetup } from "src/utils/OneShotCurveSetup.sol";
import { IOneShotCurveSetup } from "src/interfaces/IOneShotCurveSetup.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";
import { IParametersRegistry } from "src/interfaces/IParametersRegistry.sol";
import { AccountingMock } from "../helpers/mocks/AccountingMock.sol";
import { ParametersRegistryMock } from "../helpers/mocks/ParametersRegistryMock.sol";
import { Utilities } from "../helpers/Utilities.sol";

contract OneShotCurveSetupTest is Test, Utilities {
    AccountingMock internal accounting;
    ParametersRegistryMock internal registry;

    function setUp() public {
        accounting = new AccountingMock(
            1 ether,
            address(0),
            address(0),
            address(0)
        );
        registry = new ParametersRegistryMock();
    }

    function test_constructor_revertWhen_ZeroAccountingAddress() external {
        IOneShotCurveSetup.ConstructorParams
            memory params = _paramsWithAllOverrides();

        vm.expectRevert(IOneShotCurveSetup.ZeroAccountingAddress.selector);
        new OneShotCurveSetup(address(0), address(registry), params);
    }

    function test_constructor_revertWhen_ZeroRegistryAddress() external {
        IOneShotCurveSetup.ConstructorParams
            memory params = _paramsWithAllOverrides();

        vm.expectRevert(IOneShotCurveSetup.ZeroRegistryAddress.selector);
        new OneShotCurveSetup(address(accounting), address(0), params);
    }

    function test_constructor_revertWhen_EmptyBondCurve() external {
        IOneShotCurveSetup.ConstructorParams
            memory params = _paramsWithAllOverrides();
        delete params.bondCurve;

        vm.expectRevert(IOneShotCurveSetup.EmptyBondCurve.selector);
        new OneShotCurveSetup(address(accounting), address(registry), params);
    }

    function test_execute() external {
        IOneShotCurveSetup.ConstructorParams
            memory params = _paramsWithAllOverrides();
        OneShotCurveSetup deployer = new OneShotCurveSetup(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);

        uint256 expectedCurveId = 1;
        _expectAllOverrideCalls(expectedCurveId, params);

        vm.expectEmit(address(deployer));
        emit IOneShotCurveSetup.BondCurveDeployed(expectedCurveId);

        uint256 curveId = deployer.execute();
        assertEq(curveId, expectedCurveId);
        assertEq(deployer.deployedCurveId(), expectedCurveId);
        assertTrue(deployer.executed());
    }

    function test_execute_partialOverrides() external {
        IOneShotCurveSetup.ConstructorParams
            memory params = _paramsWithAllOverrides();
        params.keyRemovalCharge.isSet = false;
        params.rewardShareData.isSet = false;
        params.performanceLeewayData.isSet = false;
        params.strikesParams.isSet = false;
        params.badPerformancePenalty.isSet = false;
        params.performanceCoefficients.isSet = false;
        params.allowedExitDelay.isSet = false;
        params.exitDelayFee.isSet = false;
        params.maxWithdrawalRequestFee.isSet = false;

        OneShotCurveSetup deployer = new OneShotCurveSetup(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setKeyRemovalCharge.selector
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock
                    .setGeneralDelayedPenaltyAdditionalFine
                    .selector,
                1,
                params.generalDelayedPenaltyFine.value
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setKeysLimit.selector,
                1,
                params.keysLimit.value
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setQueueConfig.selector,
                1,
                params.queueConfig.priority,
                params.queueConfig.maxDeposits
            )
        );
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setRewardShareData.selector
            )
        );
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setPerformanceLeewayData.selector
            )
        );
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setStrikesParams.selector
            )
        );
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setBadPerformancePenalty.selector
            )
        );
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setPerformanceCoefficients.selector
            )
        );
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setAllowedExitDelay.selector
            )
        );
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setExitDelayFee.selector
            )
        );
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setMaxWithdrawalRequestFee.selector
            )
        );

        deployer.execute();
    }

    function test_execute_setsKeyRemovalCharge() external {
        IOneShotCurveSetup.ConstructorParams memory params = _baseParams();
        params.keyRemovalCharge = _scalarOverride(11);

        OneShotCurveSetup deployer = new OneShotCurveSetup(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setKeyRemovalCharge.selector,
                1,
                params.keyRemovalCharge.value
            )
        );

        deployer.execute();
    }

    function test_execute_setsGeneralDelayedPenaltyFine() external {
        IOneShotCurveSetup.ConstructorParams memory params = _baseParams();
        params.generalDelayedPenaltyFine = _scalarOverride(12);

        OneShotCurveSetup deployer = new OneShotCurveSetup(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock
                    .setGeneralDelayedPenaltyAdditionalFine
                    .selector,
                1,
                params.generalDelayedPenaltyFine.value
            )
        );

        deployer.execute();
    }

    function test_execute_setsKeysLimit() external {
        IOneShotCurveSetup.ConstructorParams memory params = _baseParams();
        params.keysLimit = _scalarOverride(99);

        OneShotCurveSetup deployer = new OneShotCurveSetup(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setKeysLimit.selector,
                1,
                params.keysLimit.value
            )
        );

        deployer.execute();
    }

    function test_execute_setsQueueConfig() external {
        IOneShotCurveSetup.ConstructorParams memory params = _baseParams();
        params.queueConfig = _queueOverride(7, 13);

        OneShotCurveSetup deployer = new OneShotCurveSetup(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setQueueConfig.selector,
                1,
                params.queueConfig.priority,
                params.queueConfig.maxDeposits
            )
        );

        deployer.execute();
    }

    function test_execute_setsRewardShareData() external {
        IOneShotCurveSetup.ConstructorParams memory params = _baseParams();
        params.rewardShareData = _intervalOverride(7777);

        OneShotCurveSetup deployer = new OneShotCurveSetup(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setRewardShareData.selector,
                1,
                params.rewardShareData.data
            )
        );

        deployer.execute();
    }

    function test_execute_setsPerformanceLeewayData() external {
        IOneShotCurveSetup.ConstructorParams memory params = _baseParams();
        params.performanceLeewayData = _intervalOverride(5555);

        OneShotCurveSetup deployer = new OneShotCurveSetup(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setPerformanceLeewayData.selector,
                1,
                params.performanceLeewayData.data
            )
        );

        deployer.execute();
    }

    function test_execute_setsStrikesParams() external {
        IOneShotCurveSetup.ConstructorParams memory params = _baseParams();
        params.strikesParams = _strikesOverride(9, 3);

        OneShotCurveSetup deployer = new OneShotCurveSetup(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setStrikesParams.selector,
                1,
                params.strikesParams.lifetime,
                params.strikesParams.threshold
            )
        );

        deployer.execute();
    }

    function test_execute_setsBadPerformancePenalty() external {
        IOneShotCurveSetup.ConstructorParams memory params = _baseParams();
        params.badPerformancePenalty = _scalarOverride(21);

        OneShotCurveSetup deployer = new OneShotCurveSetup(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setBadPerformancePenalty.selector,
                1,
                params.badPerformancePenalty.value
            )
        );

        deployer.execute();
    }

    function test_execute_setsPerformanceCoefficients() external {
        IOneShotCurveSetup.ConstructorParams memory params = _baseParams();
        params.performanceCoefficients = _performanceCoefficientsOverride(
            1,
            2,
            3
        );

        OneShotCurveSetup deployer = new OneShotCurveSetup(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setPerformanceCoefficients.selector,
                1,
                params.performanceCoefficients.attestationsWeight,
                params.performanceCoefficients.blocksWeight,
                params.performanceCoefficients.syncWeight
            )
        );

        deployer.execute();
    }

    function test_execute_setsAllowedExitDelay() external {
        IOneShotCurveSetup.ConstructorParams memory params = _baseParams();
        params.allowedExitDelay = _scalarOverride(100);

        OneShotCurveSetup deployer = new OneShotCurveSetup(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setAllowedExitDelay.selector,
                1,
                params.allowedExitDelay.value
            )
        );

        deployer.execute();
    }

    function test_execute_setsExitDelayFee() external {
        IOneShotCurveSetup.ConstructorParams memory params = _baseParams();
        params.exitDelayFee = _scalarOverride(101);

        OneShotCurveSetup deployer = new OneShotCurveSetup(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setExitDelayFee.selector,
                1,
                params.exitDelayFee.value
            )
        );

        deployer.execute();
    }

    function test_execute_setsMaxWithdrawalRequestFee() external {
        IOneShotCurveSetup.ConstructorParams memory params = _baseParams();
        params.maxWithdrawalRequestFee = _scalarOverride(202);

        OneShotCurveSetup deployer = new OneShotCurveSetup(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setMaxWithdrawalRequestFee.selector,
                1,
                params.maxWithdrawalRequestFee.value
            )
        );

        deployer.execute();
    }

    function test_execute_revertWhen_AlreadyExecuted() external {
        OneShotCurveSetup deployer = new OneShotCurveSetup(
            address(accounting),
            address(registry),
            _paramsWithAllOverrides()
        );

        deployer.execute();

        vm.expectRevert(IOneShotCurveSetup.AlreadyExecuted.selector);
        deployer.execute();
    }

    function test_constructor() external {
        IOneShotCurveSetup.ConstructorParams
            memory params = _paramsWithAllOverrides();

        OneShotCurveSetup deployer = new OneShotCurveSetup(
            address(accounting),
            address(registry),
            params
        );

        assertEq(address(deployer.ACCOUNTING()), address(accounting));
        assertEq(address(deployer.REGISTRY()), address(registry));
    }

    function _expectAllOverrideCalls(
        uint256 expectedCurveId,
        IOneShotCurveSetup.ConstructorParams memory params
    ) internal {
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setKeyRemovalCharge.selector,
                expectedCurveId,
                params.keyRemovalCharge.value
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock
                    .setGeneralDelayedPenaltyAdditionalFine
                    .selector,
                expectedCurveId,
                params.generalDelayedPenaltyFine.value
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setKeysLimit.selector,
                expectedCurveId,
                params.keysLimit.value
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setQueueConfig.selector,
                expectedCurveId,
                params.queueConfig.priority,
                params.queueConfig.maxDeposits
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setRewardShareData.selector,
                expectedCurveId,
                params.rewardShareData.data
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setPerformanceLeewayData.selector,
                expectedCurveId,
                params.performanceLeewayData.data
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setStrikesParams.selector,
                expectedCurveId,
                params.strikesParams.lifetime,
                params.strikesParams.threshold
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setBadPerformancePenalty.selector,
                expectedCurveId,
                params.badPerformancePenalty.value
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setPerformanceCoefficients.selector,
                expectedCurveId,
                params.performanceCoefficients.attestationsWeight,
                params.performanceCoefficients.blocksWeight,
                params.performanceCoefficients.syncWeight
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setAllowedExitDelay.selector,
                expectedCurveId,
                params.allowedExitDelay.value
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setExitDelayFee.selector,
                expectedCurveId,
                params.exitDelayFee.value
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                ParametersRegistryMock.setMaxWithdrawalRequestFee.selector,
                expectedCurveId,
                params.maxWithdrawalRequestFee.value
            )
        );
    }

    function _paramsWithAllOverrides()
        internal
        pure
        returns (IOneShotCurveSetup.ConstructorParams memory params)
    {
        params.bondCurve = _bondCurve();
        params.keyRemovalCharge = IOneShotCurveSetup.ScalarOverride({
            isSet: true,
            value: 1
        });
        params.generalDelayedPenaltyFine = IOneShotCurveSetup.ScalarOverride({
            isSet: true,
            value: 2
        });
        params.keysLimit = IOneShotCurveSetup.ScalarOverride({
            isSet: true,
            value: 42
        });
        params.queueConfig = IOneShotCurveSetup.QueueConfigOverride({
            isSet: true,
            priority: 3,
            maxDeposits: 5
        });

        params.rewardShareData = _intervalOverride(10000);
        params.performanceLeewayData = _intervalOverride(8000);
        params.strikesParams = IOneShotCurveSetup.StrikesOverride({
            isSet: true,
            lifetime: 4,
            threshold: 2
        });
        params.badPerformancePenalty = IOneShotCurveSetup.ScalarOverride({
            isSet: true,
            value: 5
        });
        params.performanceCoefficients = IOneShotCurveSetup
            .PerformanceCoefficientsOverride({
                isSet: true,
                attestationsWeight: 1,
                blocksWeight: 2,
                syncWeight: 3
            });
        params.allowedExitDelay = IOneShotCurveSetup.ScalarOverride({
            isSet: true,
            value: 6
        });
        params.exitDelayFee = IOneShotCurveSetup.ScalarOverride({
            isSet: true,
            value: 7
        });
        params.maxWithdrawalRequestFee = IOneShotCurveSetup.ScalarOverride({
            isSet: true,
            value: 8
        });
    }

    function _baseParams()
        internal
        pure
        returns (IOneShotCurveSetup.ConstructorParams memory params)
    {
        params.bondCurve = _bondCurve();
    }

    function _bondCurve()
        internal
        pure
        returns (IBondCurve.BondCurveIntervalInput[] memory curve)
    {
        curve = new IBondCurve.BondCurveIntervalInput[](2);
        curve[0] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 1 ether
        });
        curve[1] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 11,
            trend: 1.5 ether
        });
    }

    function _intervalOverride(
        uint256 value
    )
        internal
        pure
        returns (
            IOneShotCurveSetup.KeyNumberValueIntervalsOverride
                memory overrideData
        )
    {
        overrideData.isSet = true;
        overrideData.data = new IParametersRegistry.KeyNumberValueInterval[](1);
        overrideData.data[0] = IParametersRegistry.KeyNumberValueInterval({
            minKeyNumber: 1,
            value: value
        });
    }

    function _scalarOverride(
        uint256 value
    )
        internal
        pure
        returns (IOneShotCurveSetup.ScalarOverride memory overrideData)
    {
        overrideData.isSet = true;
        overrideData.value = value;
    }

    function _queueOverride(
        uint256 priority,
        uint256 maxDeposits
    )
        internal
        pure
        returns (IOneShotCurveSetup.QueueConfigOverride memory overrideData)
    {
        overrideData.isSet = true;
        overrideData.priority = priority;
        overrideData.maxDeposits = maxDeposits;
    }

    function _strikesOverride(
        uint256 lifetime,
        uint256 threshold
    )
        internal
        pure
        returns (IOneShotCurveSetup.StrikesOverride memory overrideData)
    {
        overrideData.isSet = true;
        overrideData.lifetime = lifetime;
        overrideData.threshold = threshold;
    }

    function _performanceCoefficientsOverride(
        uint256 attestations,
        uint256 blocks,
        uint256 sync
    )
        internal
        pure
        returns (
            IOneShotCurveSetup.PerformanceCoefficientsOverride
                memory overrideData
        )
    {
        overrideData.isSet = true;
        overrideData.attestationsWeight = attestations;
        overrideData.blocksWeight = blocks;
        overrideData.syncWeight = sync;
    }

    function _expectBondCurveAddition(
        IBondCurve.BondCurveIntervalInput[] memory curve
    ) internal {
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.addBondCurve.selector, curve)
        );
    }
}
