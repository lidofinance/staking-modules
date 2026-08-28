// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";
import { IAccounting } from "src/interfaces/IAccounting.sol";

import { PermitHelper } from "../../../helpers/Permit.sol";
import { ModuleTypeBase, CSMIntegrationBase, CSM0x02IntegrationBase } from "./ModuleTypeBase.sol";

abstract contract PermissionlessCreateNodeOperatorTestBase is PermitHelper, ModuleTypeBase {
    uint256 internal immutable KEYS_COUNT;
    address internal nodeOperator;

    constructor(uint256 keysCount) {
        KEYS_COUNT = keysCount;
    }

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        uint256 noCount = module.getNodeOperatorsCount();
        assertModuleKeys(module);
        _assertModuleEnqueuedCount();
        assertAccountingTotalBondShares(noCount, lido, accounting);
        assertAccountingBurnerApproval(lido, address(accounting), locator.burner());
        assertAccountingUnusedStorageSlots(accounting);
        assertFeeDistributorClaimableShares(lido, feeDistributor);
        assertFeeDistributorTree(feeDistributor);
        assertFeeOracleUnusedStorageSlots(oracle);
        vm.resumeGasMetering();
    }

    function setUp() public virtual {
        _setUpModule();
        handleStakingLimit();
        handleBunkerMode();
        nodeOperator = nextAddress("NodeOperator");
    }

    function test_createNodeOperatorETH() public assertInvariants {
        (bytes memory keys, bytes memory signatures) = keysSignatures(KEYS_COUNT);
        uint256 amount = accounting.getBondAmountByKeysCount(KEYS_COUNT, permissionlessGate.CURVE_ID());
        vm.deal(nodeOperator, amount);

        uint256 preTotalShares = accounting.totalBondShares();
        uint256 shares = lido.getSharesByPooledEth(amount);

        vm.startPrank(nodeOperator);
        vm.startSnapshotGas("PermissionlessGate.addNodeOperatorETH");
        uint256 noId = permissionlessGate.addNodeOperatorETH{ value: amount }({
            keysCount: KEYS_COUNT,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });
        vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(accounting.getBondCurveId(noId), permissionlessGate.CURVE_ID());
        assertEq(accounting.getBondShares(noId), shares);
        assertEq(accounting.totalBondShares(), shares + preTotalShares);
    }

    function test_createNodeOperatorStETH() public assertInvariants {
        uint256 amount = accounting.getBondAmountByKeysCount(KEYS_COUNT, permissionlessGate.CURVE_ID());
        vm.startPrank(nodeOperator);
        vm.deal(nodeOperator, amount);
        lido.submit{ value: amount }(address(0));

        uint256 preTotalShares = accounting.totalBondShares();
        lido.approve(address(accounting), type(uint256).max);

        (bytes memory keys, bytes memory signatures) = keysSignatures(KEYS_COUNT);
        uint256 shares = lido.getSharesByPooledEth(
            accounting.getBondAmountByKeysCount(KEYS_COUNT, permissionlessGate.CURVE_ID())
        );

        vm.startSnapshotGas("PermissionlessGate.addNodeOperatorStETH");
        uint256 noId = permissionlessGate.addNodeOperatorStETH({
            keysCount: KEYS_COUNT,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            permit: IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 }),
            referrer: address(0)
        });
        vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(accounting.getBondCurveId(noId), permissionlessGate.CURVE_ID());
        assertEq(accounting.getBondShares(noId), shares);
        assertEq(accounting.totalBondShares(), shares + preTotalShares);
    }

    function test_createNodeOperatorWstETH() public assertInvariants {
        uint256 amount = accounting.getBondAmountByKeysCount(KEYS_COUNT, permissionlessGate.CURVE_ID());
        vm.startPrank(nodeOperator);
        vm.deal(nodeOperator, amount);
        lido.submit{ value: amount }(address(0));
        lido.approve(address(wstETH), type(uint256).max);
        uint256 preTotalShares = accounting.totalBondShares();

        wstETH.approve(address(accounting), type(uint256).max);

        (bytes memory keys, bytes memory signatures) = keysSignatures(KEYS_COUNT);
        uint256 wstETHAmount = wstETH.wrap(amount);
        uint256 shares = lido.getSharesByPooledEth(wstETH.getStETHByWstETH(wstETHAmount));

        vm.startSnapshotGas("PermissionlessGate.addNodeOperatorWstETH");
        uint256 noId = permissionlessGate.addNodeOperatorWstETH({
            keysCount: KEYS_COUNT,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            permit: IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 }),
            referrer: address(0)
        });
        vm.stopSnapshotGas();
        vm.stopPrank();

        assertEq(accounting.getBondCurveId(noId), permissionlessGate.CURVE_ID());
        assertEq(accounting.getBondShares(noId), shares);
        assertEq(accounting.totalBondShares(), shares + preTotalShares);
    }
}

contract PermissionlessCreateNodeOperatorTestCSM is PermissionlessCreateNodeOperatorTestBase, CSMIntegrationBase {
    constructor() PermissionlessCreateNodeOperatorTestBase(1) {}
}

contract PermissionlessCreateNodeOperator10KeysTestCSM is PermissionlessCreateNodeOperatorTestBase, CSMIntegrationBase {
    constructor() PermissionlessCreateNodeOperatorTestBase(10) {}
}

contract PermissionlessCreateNodeOperatorTestCSM0x02 is
    PermissionlessCreateNodeOperatorTestBase,
    CSM0x02IntegrationBase
{
    constructor() PermissionlessCreateNodeOperatorTestBase(1) {}
}

contract PermissionlessCreateNodeOperator10KeysTestCSM0x02 is
    PermissionlessCreateNodeOperatorTestBase,
    CSM0x02IntegrationBase
{
    constructor() PermissionlessCreateNodeOperatorTestBase(10) {}
}
