// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { NodeOperator } from "src/interfaces/IBaseModule.sol";
import { IAccounting } from "src/interfaces/IAccounting.sol";

import { PermitHelper } from "../../../helpers/Permit.sol";
import { ModuleTypeBase, CSMIntegrationBase, CSM0x02IntegrationBase, CuratedIntegrationBase } from "./ModuleTypeBase.sol";

abstract contract AccountingIntegrationTestBase is ModuleTypeBase, PermitHelper {
    address internal user;
    address internal nodeOperator;
    uint256 internal userPrivateKey;

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        uint256 noCount = module.getNodeOperatorsCount();
        assertModuleKeys(module);
        _assertModuleEnqueuedCount();
        assertModuleUnusedStorageSlots(module);
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

        vm.startPrank(module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0));
        module.grantRole(module.DEFAULT_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        handleStakingLimit();
        handleBunkerMode();

        userPrivateKey = 0xa11ce;
        user = vm.addr(userPrivateKey);
        nodeOperator = nextAddress("NodeOperator");
    }
}

abstract contract DepositTestBase is AccountingIntegrationTestBase {
    uint256 internal defaultNoId;

    function setUp() public virtual override {
        super.setUp();
        defaultNoId = integrationHelpers.addNodeOperator(nodeOperator, 2);
    }

    function test_depositStETH() public assertInvariants {
        vm.startPrank(user);
        vm.deal(user, 32 ether);
        uint256 shares = lido.submit{ value: 32 ether }(address(0));

        uint256 preShares = accounting.getBondShares(defaultNoId);
        uint256 preTotalShares = accounting.totalBondShares();

        lido.approve(address(accounting), type(uint256).max);
        vm.startSnapshotGas("Accounting.depositStETH");
        accounting.depositStETH(
            defaultNoId,
            32 ether,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
        vm.stopSnapshotGas();

        assertEq(lido.balanceOf(user), 0);
        assertEq(accounting.getBondShares(defaultNoId), shares + preShares);
        assertEq(accounting.totalBondShares(), shares + preTotalShares);
    }

    function test_depositETH() public assertInvariants {
        vm.startPrank(user);
        vm.deal(user, 32 ether);

        uint256 preShares = accounting.getBondShares(defaultNoId);
        uint256 preTotalShares = accounting.totalBondShares();

        uint256 shares = lido.getSharesByPooledEth(32 ether);
        vm.startSnapshotGas("Accounting.depositETH");
        accounting.depositETH{ value: 32 ether }(defaultNoId);
        vm.stopSnapshotGas();

        assertEq(user.balance, 0);
        assertEq(accounting.getBondShares(defaultNoId), shares + preShares);
        assertEq(accounting.totalBondShares(), shares + preTotalShares);
    }

    function test_depositWstETH() public assertInvariants {
        vm.startPrank(user);
        vm.deal(user, 32 ether);
        lido.submit{ value: 32 ether }(address(0));
        lido.approve(address(wstETH), type(uint256).max);
        uint256 wstETHAmount = wstETH.wrap(32 ether);

        uint256 shares = lido.getSharesByPooledEth(wstETH.getStETHByWstETH(wstETHAmount));

        uint256 preShares = accounting.getBondShares(defaultNoId);
        uint256 preTotalShares = accounting.totalBondShares();

        wstETH.approve(address(accounting), type(uint256).max);
        vm.startSnapshotGas("Accounting.depositWstETH");
        accounting.depositWstETH(
            defaultNoId,
            wstETHAmount,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
        vm.stopSnapshotGas();

        assertEq(wstETH.balanceOf(user), 0);
        assertEq(accounting.getBondShares(defaultNoId), shares + preShares);
        assertEq(accounting.totalBondShares(), shares + preTotalShares);
    }

    function test_depositStETHWithPermit() public assertInvariants {
        bytes32 digest = stETHPermitDigest(
            user,
            address(accounting),
            32 ether,
            vm.getNonce(user),
            type(uint256).max,
            address(lido)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        vm.deal(user, 32 ether);
        vm.startPrank(user);
        uint256 shares = lido.submit{ value: 32 ether }(address(0));

        uint256 preShares = accounting.getBondShares(defaultNoId);
        uint256 preTotalShares = accounting.totalBondShares();

        vm.startSnapshotGas("Accounting.depositStETH_permit");
        accounting.depositStETH(
            defaultNoId,
            32 ether,
            IAccounting.PermitInput({ value: 32 ether, deadline: type(uint256).max, v: v, r: r, s: s })
        );
        vm.stopSnapshotGas();

        assertEq(lido.balanceOf(user), 0);
        assertEq(accounting.getBondShares(defaultNoId), shares + preShares);
        assertEq(accounting.totalBondShares(), shares + preTotalShares);
    }

    function test_depositWstETHWithPermit() public assertInvariants {
        vm.deal(user, 33 ether);
        vm.startPrank(user);
        lido.submit{ value: 33 ether }(address(0));
        lido.approve(address(wstETH), type(uint256).max);
        uint256 wstETHAmount = wstETH.wrap(32 ether);

        bytes32 digest = wstETHPermitDigest(
            user,
            address(accounting),
            wstETHAmount + 10 wei,
            vm.getNonce(user),
            type(uint256).max,
            address(wstETH)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        uint256 shares = lido.getSharesByPooledEth(wstETH.getStETHByWstETH(wstETHAmount));

        uint256 preShares = accounting.getBondShares(defaultNoId);
        uint256 preTotalShares = accounting.totalBondShares();

        vm.startSnapshotGas("Accounting.depositWstETH_permit");
        accounting.depositWstETH(
            defaultNoId,
            wstETHAmount,
            IAccounting.PermitInput({ value: wstETHAmount + 10 wei, deadline: type(uint256).max, v: v, r: r, s: s })
        );
        vm.stopSnapshotGas();

        assertEq(wstETH.balanceOf(user), 0);
        assertEq(accounting.getBondShares(defaultNoId), shares + preShares);
        assertEq(accounting.totalBondShares(), shares + preTotalShares);
    }
}

contract DepositTestCSM is DepositTestBase, CSMIntegrationBase {}

contract DepositTestCSM0x02 is DepositTestBase, CSM0x02IntegrationBase {}

contract DepositTestCurated is DepositTestBase, CuratedIntegrationBase {}

abstract contract AddValidatorKeysTestBase is AccountingIntegrationTestBase {
    uint256 internal defaultNoId;
    uint256 internal initialKeysCount = 2;
    uint256 internal bondCurveId;

    function _keysCount() internal pure virtual returns (uint256);

    function setUp() public virtual override {
        super.setUp();
        defaultNoId = integrationHelpers.addNodeOperatorWithManagement(
            nodeOperator,
            nodeOperator,
            nodeOperator,
            false,
            initialKeysCount
        );
        bondCurveId = accounting.getBondCurveId(defaultNoId);
    }

    function test_addValidatorKeysETH() public assertInvariants {
        uint256 keysCount = _keysCount();
        (bytes memory keys, bytes memory signatures) = keysSignatures(keysCount);
        uint256 amount = accounting.getRequiredBondForNextKeys(defaultNoId, keysCount);
        vm.deal(nodeOperator, amount);

        vm.startPrank(nodeOperator);
        vm.startSnapshotGas("Module.addValidatorKeysETH");
        module.addValidatorKeysETH{ value: amount }(nodeOperator, defaultNoId, keysCount, keys, signatures);
        vm.stopSnapshotGas();
        vm.stopPrank();

        NodeOperator memory no = module.getNodeOperator(defaultNoId);
        assertEq(no.totalAddedKeys, initialKeysCount + keysCount);
    }

    function test_addValidatorKeysStETH() public assertInvariants {
        uint256 keysCount = _keysCount();
        uint256 amount = accounting.getRequiredBondForNextKeys(defaultNoId, keysCount);
        vm.startPrank(nodeOperator);
        vm.deal(nodeOperator, amount);
        lido.submit{ value: amount }(address(0));

        lido.approve(address(accounting), type(uint256).max);

        (bytes memory keys, bytes memory signatures) = keysSignatures(keysCount);

        vm.startSnapshotGas("Module.addValidatorKeysStETH");
        module.addValidatorKeysStETH(
            nodeOperator,
            defaultNoId,
            keysCount,
            keys,
            signatures,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
        vm.stopSnapshotGas();
        vm.stopPrank();

        NodeOperator memory no = module.getNodeOperator(defaultNoId);
        assertEq(no.totalAddedKeys, initialKeysCount + keysCount);
    }

    function test_addValidatorKeysWstETH() public assertInvariants {
        uint256 keysCount = _keysCount();
        uint256 amount = accounting.getRequiredBondForNextKeys(defaultNoId, keysCount);
        vm.startPrank(nodeOperator);
        vm.deal(nodeOperator, amount);
        lido.submit{ value: amount }(address(0));
        lido.approve(address(wstETH), type(uint256).max);

        wstETH.approve(address(accounting), type(uint256).max);

        (bytes memory keys, bytes memory signatures) = keysSignatures(keysCount);
        wstETH.wrap(amount);

        vm.startSnapshotGas("Module.addValidatorKeysWstETH");
        module.addValidatorKeysWstETH(
            nodeOperator,
            defaultNoId,
            keysCount,
            keys,
            signatures,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
        vm.stopSnapshotGas();
        vm.stopPrank();

        NodeOperator memory no = module.getNodeOperator(defaultNoId);
        assertEq(no.totalAddedKeys, initialKeysCount + keysCount);
    }
}

contract AddValidatorKeysTestCSM is AddValidatorKeysTestBase, CSMIntegrationBase {
    function _keysCount() internal pure override returns (uint256) {
        return 1;
    }
}

contract AddValidatorKeysTestCSM0x02 is AddValidatorKeysTestBase, CSM0x02IntegrationBase {
    function _keysCount() internal pure override returns (uint256) {
        return 1;
    }
}

contract AddValidatorKeysTestCurated is AddValidatorKeysTestBase, CuratedIntegrationBase {
    function _keysCount() internal pure override returns (uint256) {
        return 1;
    }
}

contract AddValidatorKeys10KeysTestCSM is AddValidatorKeysTestBase, CSMIntegrationBase {
    function _keysCount() internal pure override returns (uint256) {
        return 10;
    }
}

contract AddValidatorKeys10KeysTestCSM0x02 is AddValidatorKeysTestBase, CSM0x02IntegrationBase {
    function _keysCount() internal pure override returns (uint256) {
        return 10;
    }
}

contract AddValidatorKeys10KeysTestCurated is AddValidatorKeysTestBase, CuratedIntegrationBase {
    function _keysCount() internal pure override returns (uint256) {
        return 10;
    }
}

abstract contract RemoveKeysTestBase is AccountingIntegrationTestBase {
    uint256 internal defaultNoId;
    uint256 internal initialKeysCount = 3;
    uint256 internal bondCurveId;

    function setUp() public virtual override {
        super.setUp();
        defaultNoId = integrationHelpers.addNodeOperator(nodeOperator, initialKeysCount);
        bondCurveId = accounting.getBondCurveId(defaultNoId);
    }

    function test_removeKeys_withoutCharge() public assertInvariants {
        uint256 keysCount = 1;

        (uint256 bondBefore, ) = accounting.getBondSummary(defaultNoId);

        vm.startPrank(parametersRegistry.getRoleMember(parametersRegistry.DEFAULT_ADMIN_ROLE(), 0));
        parametersRegistry.setKeyRemovalCharge(bondCurveId, 0);
        vm.stopPrank();

        vm.startPrank(nodeOperator);
        vm.startSnapshotGas("Module.removeKeys");
        module.removeKeys(defaultNoId, initialKeysCount - keysCount, keysCount);
        vm.stopSnapshotGas();
        vm.stopPrank();

        NodeOperator memory no = module.getNodeOperator(defaultNoId);
        assertEq(no.totalAddedKeys, initialKeysCount - keysCount);

        (uint256 bondAfter, ) = accounting.getBondSummary(defaultNoId);

        assertEq(bondBefore, bondAfter);
    }

    function test_removeKeys_vettingReset() public assertInvariants {
        uint256 keysCount = 2;
        uint256 noId = integrationHelpers.addNodeOperatorWithManagement(
            nodeOperator,
            nodeOperator,
            nodeOperator,
            false,
            keysCount
        );

        vm.prank(address(stakingRouter));
        module.decreaseVettedSigningKeysCount(
            // Node/operator identifiers fit 64 bits and key counts are tiny (<100) in this suite.
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes.concat(bytes8(uint64(noId))),
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes.concat(bytes16(uint128(keysCount - 1)))
        );

        uint256 additionalKeysCount = 2;
        (bytes memory keys, bytes memory signatures) = keysSignatures(additionalKeysCount);
        uint256 amount = accounting.getRequiredBondForNextKeys(noId, additionalKeysCount);
        vm.deal(nodeOperator, amount);

        vm.startPrank(nodeOperator);
        vm.startSnapshotGas("Module.addValidatorKeysETH");
        module.addValidatorKeysETH{ value: amount }(nodeOperator, noId, additionalKeysCount, keys, signatures);
        vm.stopSnapshotGas();
        vm.stopPrank();

        uint256 keysCountToRemove = 1;

        vm.startPrank(nodeOperator);
        vm.startSnapshotGas("Module.removeKeys");
        module.removeKeys(noId, keysCount - keysCountToRemove - 1, keysCountToRemove);
        vm.stopSnapshotGas();
        vm.stopPrank();

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, keysCount + additionalKeysCount - keysCountToRemove);
        assertEq(no.totalVettedKeys, no.totalAddedKeys);
    }
}

contract RemoveKeysTestCSM is RemoveKeysTestBase, CSMIntegrationBase {
    function test_removeKeys_withCharge() public assertInvariants {
        uint256 keysCount = 1;

        (uint256 bondBefore, ) = accounting.getBondSummary(defaultNoId);

        uint256 keyRemovalCharge = parametersRegistry.getKeyRemovalCharge(bondCurveId);

        vm.startPrank(nodeOperator);
        vm.startSnapshotGas("CSM.removeKeys");
        module.removeKeys(defaultNoId, initialKeysCount - keysCount, keysCount);
        vm.stopSnapshotGas();
        vm.stopPrank();

        NodeOperator memory no = module.getNodeOperator(defaultNoId);
        assertEq(no.totalAddedKeys, initialKeysCount - keysCount);

        (uint256 bondAfter, ) = accounting.getBondSummary(defaultNoId);

        assertApproxEqAbs(bondBefore, bondAfter + keyRemovalCharge, 2 wei);
    }
}

contract RemoveKeysTestCSM0x02 is RemoveKeysTestBase, CSM0x02IntegrationBase {
    function test_removeKeys_withCharge() public assertInvariants {
        uint256 keysCount = 1;

        (uint256 bondBefore, ) = accounting.getBondSummary(defaultNoId);

        uint256 keyRemovalCharge = parametersRegistry.getKeyRemovalCharge(bondCurveId);

        vm.startPrank(nodeOperator);
        vm.startSnapshotGas("CSM0x02.removeKeys");
        module.removeKeys(defaultNoId, initialKeysCount - keysCount, keysCount);
        vm.stopSnapshotGas();
        vm.stopPrank();

        NodeOperator memory no = module.getNodeOperator(defaultNoId);
        assertEq(no.totalAddedKeys, initialKeysCount - keysCount);

        (uint256 bondAfter, ) = accounting.getBondSummary(defaultNoId);

        assertApproxEqAbs(bondBefore, bondAfter + keyRemovalCharge, 2 wei);
    }
}

contract RemoveKeysTestCurated is RemoveKeysTestBase, CuratedIntegrationBase {
    function test_removeKeys_withChargeIgnored() public assertInvariants {
        uint256 keysCount = 1;

        (uint256 bondBefore, ) = accounting.getBondSummary(defaultNoId);

        vm.startPrank(parametersRegistry.getRoleMember(parametersRegistry.DEFAULT_ADMIN_ROLE(), 0));
        parametersRegistry.setKeyRemovalCharge(bondCurveId, 1);
        vm.stopPrank();

        vm.startPrank(nodeOperator);
        vm.startSnapshotGas("Curated.removeKeys");
        module.removeKeys(defaultNoId, initialKeysCount - keysCount, keysCount);
        vm.stopSnapshotGas();
        vm.stopPrank();

        NodeOperator memory no = module.getNodeOperator(defaultNoId);
        assertEq(no.totalAddedKeys, initialKeysCount - keysCount);

        (uint256 bondAfter, ) = accounting.getBondSummary(defaultNoId);

        assertEq(bondBefore, bondAfter);
    }
}
