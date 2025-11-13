// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import "forge-std/Test.sol";

import { BondCurveOneTimeDeployer } from "src/utils/BondCurveOneTimeDeployer.sol";
import { IBondCurveOneTimeDeployer } from "src/interfaces/IBondCurveOneTimeDeployer.sol";
import { ICSBondCurve } from "src/interfaces/ICSBondCurve.sol";
import { ICSParametersRegistry } from "src/interfaces/ICSParametersRegistry.sol";
import { CSAccountingMock } from "../helpers/mocks/CSAccountingMock.sol";
import { CSParametersRegistryMock } from "../helpers/mocks/CSParametersRegistryMock.sol";
import { Utilities } from "../helpers/Utilities.sol";

contract BondCurveOneTimeDeployerTest is Test, Utilities {
    CSAccountingMock internal accounting;
    CSParametersRegistryMock internal registry;

    function setUp() public {
        accounting = new CSAccountingMock(
            1 ether,
            address(0),
            address(0),
            address(0)
        );
        registry = new CSParametersRegistryMock();
    }

    function test_constructor_revertWhen_ZeroAccountingAddress() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _paramsWithAllOverrides();

        vm.expectRevert(
            IBondCurveOneTimeDeployer.ZeroAccountingAddress.selector
        );
        new BondCurveOneTimeDeployer(address(0), address(registry), params);
    }

    function test_constructor_revertWhen_ZeroRegistryAddress() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _paramsWithAllOverrides();

        vm.expectRevert(IBondCurveOneTimeDeployer.ZeroRegistryAddress.selector);
        new BondCurveOneTimeDeployer(address(accounting), address(0), params);
    }

    function test_constructor_revertWhen_EmptyBondCurve() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _paramsWithAllOverrides();
        delete params.bondCurve;

        vm.expectRevert(IBondCurveOneTimeDeployer.EmptyBondCurve.selector);
        new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            params
        );
    }

    function test_execute() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _paramsWithAllOverrides();
        BondCurveOneTimeDeployer deployer = new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);

        uint256 expectedCurveId = 1;
        _expectAllOverrideCalls(expectedCurveId, params);

        vm.expectEmit(address(deployer));
        emit IBondCurveOneTimeDeployer.BondCurveDeployed(expectedCurveId);

        uint256 curveId = deployer.execute();
        assertEq(curveId, expectedCurveId);
        assertEq(deployer.deployedCurveId(), expectedCurveId);
        assertTrue(deployer.executed());
    }

    function test_execute_partialOverrides() external {
        IBondCurveOneTimeDeployer.ConstructorParams
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

        BondCurveOneTimeDeployer deployer = new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setKeyRemovalCharge.selector
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock
                    .setGeneralDelayedPenaltyAdditionalFine
                    .selector,
                1,
                params.generalDelayedPenaltyFine.value
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setKeysLimit.selector,
                1,
                params.keysLimit.value
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setQueueConfig.selector,
                1,
                params.queueConfig.priority,
                params.queueConfig.maxDeposits
            )
        );
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setRewardShareData.selector
            )
        );
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setPerformanceLeewayData.selector
            )
        );
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setStrikesParams.selector
            )
        );
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setBadPerformancePenalty.selector
            )
        );
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setPerformanceCoefficients.selector
            )
        );
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setAllowedExitDelay.selector
            )
        );
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setExitDelayFee.selector
            )
        );
        expectNoCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setMaxWithdrawalRequestFee.selector
            )
        );

        deployer.execute();
    }

    function test_execute_setsKeyRemovalCharge() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _baseParams();
        params.keyRemovalCharge = _scalarOverride(11);

        BondCurveOneTimeDeployer deployer = new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setKeyRemovalCharge.selector,
                1,
                params.keyRemovalCharge.value
            )
        );

        deployer.execute();
    }

    function test_execute_setsGeneralDelayedPenaltyFine() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _baseParams();
        params.generalDelayedPenaltyFine = _scalarOverride(12);

        BondCurveOneTimeDeployer deployer = new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock
                    .setGeneralDelayedPenaltyAdditionalFine
                    .selector,
                1,
                params.generalDelayedPenaltyFine.value
            )
        );

        deployer.execute();
    }

    function test_execute_setsKeysLimit() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _baseParams();
        params.keysLimit = _scalarOverride(99);

        BondCurveOneTimeDeployer deployer = new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setKeysLimit.selector,
                1,
                params.keysLimit.value
            )
        );

        deployer.execute();
    }

    function test_execute_setsQueueConfig() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _baseParams();
        params.queueConfig = _queueOverride(7, 13);

        BondCurveOneTimeDeployer deployer = new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setQueueConfig.selector,
                1,
                params.queueConfig.priority,
                params.queueConfig.maxDeposits
            )
        );

        deployer.execute();
    }

    function test_execute_setsRewardShareData() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _baseParams();
        params.rewardShareData = _intervalOverride(7777);

        BondCurveOneTimeDeployer deployer = new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setRewardShareData.selector,
                1,
                params.rewardShareData.data
            )
        );

        deployer.execute();
    }

    function test_execute_setsPerformanceLeewayData() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _baseParams();
        params.performanceLeewayData = _intervalOverride(5555);

        BondCurveOneTimeDeployer deployer = new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setPerformanceLeewayData.selector,
                1,
                params.performanceLeewayData.data
            )
        );

        deployer.execute();
    }

    function test_execute_setsStrikesParams() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _baseParams();
        params.strikesParams = _strikesOverride(9, 3);

        BondCurveOneTimeDeployer deployer = new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setStrikesParams.selector,
                1,
                params.strikesParams.lifetime,
                params.strikesParams.threshold
            )
        );

        deployer.execute();
    }

    function test_execute_setsBadPerformancePenalty() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _baseParams();
        params.badPerformancePenalty = _scalarOverride(21);

        BondCurveOneTimeDeployer deployer = new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setBadPerformancePenalty.selector,
                1,
                params.badPerformancePenalty.value
            )
        );

        deployer.execute();
    }

    function test_execute_setsPerformanceCoefficients() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _baseParams();
        params.performanceCoefficients = _performanceCoefficientsOverride(
            1,
            2,
            3
        );

        BondCurveOneTimeDeployer deployer = new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setPerformanceCoefficients.selector,
                1,
                params.performanceCoefficients.attestationsWeight,
                params.performanceCoefficients.blocksWeight,
                params.performanceCoefficients.syncWeight
            )
        );

        deployer.execute();
    }

    function test_execute_setsAllowedExitDelay() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _baseParams();
        params.allowedExitDelay = _scalarOverride(100);

        BondCurveOneTimeDeployer deployer = new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setAllowedExitDelay.selector,
                1,
                params.allowedExitDelay.value
            )
        );

        deployer.execute();
    }

    function test_execute_setsExitDelayFee() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _baseParams();
        params.exitDelayFee = _scalarOverride(101);

        BondCurveOneTimeDeployer deployer = new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setExitDelayFee.selector,
                1,
                params.exitDelayFee.value
            )
        );

        deployer.execute();
    }

    function test_execute_setsMaxWithdrawalRequestFee() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _baseParams();
        params.maxWithdrawalRequestFee = _scalarOverride(202);

        BondCurveOneTimeDeployer deployer = new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            params
        );

        _expectBondCurveAddition(params.bondCurve);
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setMaxWithdrawalRequestFee.selector,
                1,
                params.maxWithdrawalRequestFee.value
            )
        );

        deployer.execute();
    }

    function test_execute_revertWhen_AlreadyExecuted() external {
        BondCurveOneTimeDeployer deployer = new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            _paramsWithAllOverrides()
        );

        deployer.execute();

        vm.expectRevert(IBondCurveOneTimeDeployer.AlreadyExecuted.selector);
        deployer.execute();
    }

    function test_constructor() external {
        IBondCurveOneTimeDeployer.ConstructorParams
            memory params = _paramsWithAllOverrides();

        BondCurveOneTimeDeployer deployer = new BondCurveOneTimeDeployer(
            address(accounting),
            address(registry),
            params
        );

        assertEq(address(deployer.ACCOUNTING()), address(accounting));
        assertEq(address(deployer.REGISTRY()), address(registry));
    }

    function _expectAllOverrideCalls(
        uint256 expectedCurveId,
        IBondCurveOneTimeDeployer.ConstructorParams memory params
    ) internal {
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setKeyRemovalCharge.selector,
                expectedCurveId,
                params.keyRemovalCharge.value
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock
                    .setGeneralDelayedPenaltyAdditionalFine
                    .selector,
                expectedCurveId,
                params.generalDelayedPenaltyFine.value
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setKeysLimit.selector,
                expectedCurveId,
                params.keysLimit.value
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setQueueConfig.selector,
                expectedCurveId,
                params.queueConfig.priority,
                params.queueConfig.maxDeposits
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setRewardShareData.selector,
                expectedCurveId,
                params.rewardShareData.data
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setPerformanceLeewayData.selector,
                expectedCurveId,
                params.performanceLeewayData.data
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setStrikesParams.selector,
                expectedCurveId,
                params.strikesParams.lifetime,
                params.strikesParams.threshold
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setBadPerformancePenalty.selector,
                expectedCurveId,
                params.badPerformancePenalty.value
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setPerformanceCoefficients.selector,
                expectedCurveId,
                params.performanceCoefficients.attestationsWeight,
                params.performanceCoefficients.blocksWeight,
                params.performanceCoefficients.syncWeight
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setAllowedExitDelay.selector,
                expectedCurveId,
                params.allowedExitDelay.value
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setExitDelayFee.selector,
                expectedCurveId,
                params.exitDelayFee.value
            )
        );
        vm.expectCall(
            address(registry),
            abi.encodeWithSelector(
                CSParametersRegistryMock.setMaxWithdrawalRequestFee.selector,
                expectedCurveId,
                params.maxWithdrawalRequestFee.value
            )
        );
    }

    function _paramsWithAllOverrides()
        internal
        pure
        returns (IBondCurveOneTimeDeployer.ConstructorParams memory params)
    {
        params.bondCurve = _bondCurve();
        params.keyRemovalCharge = IBondCurveOneTimeDeployer.ScalarOverride({
            isSet: true,
            value: 1
        });
        params.generalDelayedPenaltyFine = IBondCurveOneTimeDeployer
            .ScalarOverride({ isSet: true, value: 2 });
        params.keysLimit = IBondCurveOneTimeDeployer.ScalarOverride({
            isSet: true,
            value: 42
        });
        params.queueConfig = IBondCurveOneTimeDeployer.QueueConfigOverride({
            isSet: true,
            priority: 3,
            maxDeposits: 5
        });

        params.rewardShareData = _intervalOverride(10000);
        params.performanceLeewayData = _intervalOverride(8000);
        params.strikesParams = IBondCurveOneTimeDeployer.StrikesOverride({
            isSet: true,
            lifetime: 4,
            threshold: 2
        });
        params.badPerformancePenalty = IBondCurveOneTimeDeployer
            .ScalarOverride({ isSet: true, value: 5 });
        params.performanceCoefficients = IBondCurveOneTimeDeployer
            .PerformanceCoefficientsOverride({
                isSet: true,
                attestationsWeight: 1,
                blocksWeight: 2,
                syncWeight: 3
            });
        params.allowedExitDelay = IBondCurveOneTimeDeployer.ScalarOverride({
            isSet: true,
            value: 6
        });
        params.exitDelayFee = IBondCurveOneTimeDeployer.ScalarOverride({
            isSet: true,
            value: 7
        });
        params.maxWithdrawalRequestFee = IBondCurveOneTimeDeployer
            .ScalarOverride({ isSet: true, value: 8 });
    }

    function _baseParams()
        internal
        pure
        returns (IBondCurveOneTimeDeployer.ConstructorParams memory params)
    {
        params.bondCurve = _bondCurve();
    }

    function _bondCurve()
        internal
        pure
        returns (ICSBondCurve.BondCurveIntervalInput[] memory curve)
    {
        curve = new ICSBondCurve.BondCurveIntervalInput[](2);
        curve[0] = ICSBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 1 ether
        });
        curve[1] = ICSBondCurve.BondCurveIntervalInput({
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
            IBondCurveOneTimeDeployer.KeyNumberValueIntervalsOverride
                memory overrideData
        )
    {
        overrideData.isSet = true;
        overrideData.data = new ICSParametersRegistry.KeyNumberValueInterval[](
            1
        );
        overrideData.data[0] = ICSParametersRegistry.KeyNumberValueInterval({
            minKeyNumber: 1,
            value: value
        });
    }

    function _scalarOverride(
        uint256 value
    )
        internal
        pure
        returns (IBondCurveOneTimeDeployer.ScalarOverride memory overrideData)
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
        returns (
            IBondCurveOneTimeDeployer.QueueConfigOverride memory overrideData
        )
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
        returns (IBondCurveOneTimeDeployer.StrikesOverride memory overrideData)
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
            IBondCurveOneTimeDeployer.PerformanceCoefficientsOverride
                memory overrideData
        )
    {
        overrideData.isSet = true;
        overrideData.attestationsWeight = attestations;
        overrideData.blocksWeight = blocks;
        overrideData.syncWeight = sync;
    }

    function _expectBondCurveAddition(
        ICSBondCurve.BondCurveIntervalInput[] memory curve
    ) internal {
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.addBondCurve.selector, curve)
        );
    }
}
