// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { IAccounting } from "src/interfaces/IAccounting.sol";
import { IBaseModule, NodeOperator, NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";
import { ILidoLocator } from "src/interfaces/ILidoLocator.sol";
import { IStakingModule } from "src/interfaces/IStakingModule.sol";
import { IWithdrawalQueue } from "src/interfaces/IWithdrawalQueue.sol";
import { SigningKeys } from "src/lib/SigningKeys.sol";

import { LidoMock } from "../../helpers/mocks/LidoMock.sol";
import { Utilities } from "../../helpers/Utilities.sol";
import { WstETHMock } from "../../helpers/mocks/WstETHMock.sol";
import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleAddValidatorKeys is ModuleFixtures {
    function test_AddValidatorKeysWstETH() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator();
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        uint256 nonce = module.getNonce();
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysWstETH_keysLimit_withdrawnKeys() public assertInvariants brutalizeMemory {
        parametersRegistry.setKeysLimit(0, 1);

        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        withdrawKey(noId, 0);

        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysWstETH_withTargetLimitSet() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator();

        module.updateTargetValidatorsLimits({ nodeOperatorId: noId, targetLimitMode: 1, targetLimit: 0 });

        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        uint256 nonce = module.getNonce();

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
        assertEq(module.getNonce(), nonce + 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);
    }

    function test_AddValidatorKeysWstETH_withPermit() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator();
        uint256 toWrap = BOND_SIZE + 1 wei;
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(toWrap);
        uint256 nonce = module.getNonce();
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({
                value: wstETHAmount,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysStETH() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));
        uint256 nonce = module.getNonce();

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({ value: BOND_SIZE, deadline: 0, v: 0, r: 0, s: 0 })
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysStETH_keysLimit_withdrawnKeys() public assertInvariants brutalizeMemory {
        parametersRegistry.setKeysLimit(0, 1);

        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        withdrawKey(noId, 0);

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({ value: BOND_SIZE, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysStETH_withTargetLimitSet() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator();

        module.updateTargetValidatorsLimits({ nodeOperatorId: noId, targetLimitMode: 1, targetLimit: 0 });

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));
        uint256 nonce = module.getNonce();

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({ value: BOND_SIZE, deadline: 0, v: 0, r: 0, s: 0 })
        );
        assertEq(module.getNonce(), nonce + 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);
    }

    function test_AddValidatorKeysStETH_withPermit() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);
        vm.prank(nodeOperator);
        stETH.submit{ value: required }(address(0));
        uint256 nonce = module.getNonce();

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        vm.prank(nodeOperator);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({
                value: required,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysETH() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);
        uint256 nonce = module.getNonce();

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(nodeOperator, noId, 1, keys, signatures);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysETH_keysLimit_withdrawnKeys() public assertInvariants brutalizeMemory {
        parametersRegistry.setKeysLimit(0, 1);

        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        withdrawKey(noId, 0);

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(nodeOperator, noId, 1, keys, signatures);
    }

    function test_AddValidatorKeysETH_withTargetLimitSet() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator();

        module.updateTargetValidatorsLimits({ nodeOperatorId: noId, targetLimitMode: 1, targetLimit: 0 });

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);
        uint256 nonce = module.getNonce();

        vm.prank(nodeOperator);
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysETH{ value: required }(nodeOperator, noId, 1, keys, signatures);
        assertEq(module.getNonce(), nonce + 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);
    }

    function test_AddValidatorKeysETH_withMoreEthThanRequired() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        uint256 deposit = required + 1 ether;
        vm.deal(nodeOperator, deposit);
        uint256 nonce = module.getNonce();

        vm.prank(nodeOperator);
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysETH{ value: deposit }(nodeOperator, noId, 1, keys, signatures);
        assertEq(module.getNonce(), nonce + 1);
    }
}

contract GateWithTestCapabilities is Test, Utilities {
    IBaseModule private module;
    IAccounting private accounting;

    WstETHMock private wstETH;
    LidoMock private stETH;

    constructor(IBaseModule _module) {
        module = _module;
        accounting = module.ACCOUNTING();
        ILidoLocator locator = module.LIDO_LOCATOR();
        stETH = LidoMock(locator.lido());
        wstETH = WstETHMock(IWithdrawalQueue(locator.withdrawalQueue()).WSTETH());
        stETH.approve(address(wstETH), UINT256_MAX);
    }

    function createNodeOperatorWithKeysWithETHBond(
        address owner,
        uint256 keyCount,
        bytes memory keys,
        bytes memory sigs
    ) external returns (uint256 noId) {
        noId = module.createNodeOperator({
            from: owner,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: owner,
                rewardAddress: owner,
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        uint256 required = accounting.getRequiredBondForNextKeys(noId, keyCount);
        vm.deal(address(this), required);

        uint256 nonce = module.getNonce();

        module.addValidatorKeysETH{ value: required }(owner, noId, keyCount, keys, sigs);

        assertEq(module.getNonce(), ++nonce);
    }

    function batchCreateNodeOperatorWithKeysWithETHBond(
        address owner,
        uint256 operatorCount,
        uint256 operatorKeyCount,
        bytes memory keys,
        bytes memory sigs
    ) external returns (uint256[] memory ids) {
        ids = new uint256[](operatorCount);
        for (uint256 i; i < ids.length; i++) {
            ids[i] = module.createNodeOperator(
                owner,
                NodeOperatorManagementProperties({
                    managerAddress: owner,
                    rewardAddress: owner,
                    extendedManagerPermissions: false
                }),
                address(0)
            );
        }
        uint256 firstId = ids[0];
        shuffle(ids);

        uint256 nonce = module.getNonce();

        for (uint256 i; i < ids.length; i++) {
            bytes memory _keys = slice(keys, ids[i] - firstId * 48, operatorKeyCount * 48);
            bytes memory _sigs = slice(sigs, ids[i] - firstId * 96, operatorKeyCount * 96);

            uint256 required = accounting.getRequiredBondForNextKeys(ids[i], operatorKeyCount);
            vm.deal(address(this), required);

            module.addValidatorKeysETH{ value: required }(owner, ids[i], operatorKeyCount, _keys, _sigs);

            assertEq(module.getNonce(), ++nonce);
        }
    }

    function createNodeOperatorWithKeysWithStETHBond(
        address owner,
        uint256 keyCount,
        bytes memory keys,
        bytes memory sigs
    ) external returns (uint256 noId) {
        noId = module.createNodeOperator({
            from: owner,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: owner,
                rewardAddress: owner,
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        uint256 required = accounting.getRequiredBondForNextKeys(noId, keyCount);
        uint256 toWrap = required + 1 wei;
        vm.deal(address(this), toWrap);
        stETH.submit{ value: toWrap }(address(0));

        uint256 nonce = module.getNonce();

        module.addValidatorKeysStETH(
            owner,
            noId,
            keyCount,
            keys,
            sigs,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );

        assertEq(module.getNonce(), ++nonce);
    }

    function batchCreateNodeOperatorWithKeysWithStETHBond(
        address owner,
        uint256 operatorCount,
        uint256 operatorKeyCount,
        bytes memory keys,
        bytes memory sigs
    ) external returns (uint256[] memory ids) {
        ids = new uint256[](operatorCount);
        for (uint256 i; i < ids.length; i++) {
            ids[i] = module.createNodeOperator(
                owner,
                NodeOperatorManagementProperties({
                    managerAddress: owner,
                    rewardAddress: owner,
                    extendedManagerPermissions: false
                }),
                address(0)
            );
        }
        uint256 firstId = ids[0];
        shuffle(ids);

        uint256 nonce = module.getNonce();

        for (uint256 i; i < ids.length; i++) {
            bytes memory _keys = slice(keys, ids[i] - firstId * 48, operatorKeyCount * 48);
            bytes memory _sigs = slice(sigs, ids[i] - firstId * 96, operatorKeyCount * 96);

            uint256 required = accounting.getRequiredBondForNextKeys(ids[i], operatorKeyCount);
            uint256 ethAmountToSend = required + 1 wei;
            vm.deal(address(this), ethAmountToSend);
            stETH.submit{ value: ethAmountToSend }(address(0));

            module.addValidatorKeysStETH(
                owner,
                ids[i],
                operatorKeyCount,
                _keys,
                _sigs,
                IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
            );

            assertEq(module.getNonce(), ++nonce);
        }
    }

    function createNodeOperatorWithKeysWithWstETHBond(
        address owner,
        uint256 keyCount,
        bytes memory keys,
        bytes memory sigs
    ) external returns (uint256 noId) {
        noId = module.createNodeOperator({
            from: owner,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: owner,
                rewardAddress: owner,
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        uint256 required = accounting.getRequiredBondForNextKeys(noId, keyCount);
        uint256 toWrap = required + 1 wei;
        vm.deal(address(this), toWrap);

        stETH.submit{ value: toWrap }(address(0));
        wstETH.wrap(toWrap);

        module.addValidatorKeysWstETH(
            owner,
            noId,
            keyCount,
            keys,
            sigs,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function batchCreateNodeOperatorWithKeysWithWstETHBond(
        address owner,
        uint256 operatorCount,
        uint256 operatorKeyCount,
        bytes memory keys,
        bytes memory sigs
    ) external returns (uint256[] memory ids) {
        ids = new uint256[](operatorCount);
        for (uint256 i; i < ids.length; i++) {
            ids[i] = module.createNodeOperator(
                owner,
                NodeOperatorManagementProperties({
                    managerAddress: owner,
                    rewardAddress: owner,
                    extendedManagerPermissions: false
                }),
                address(0)
            );
        }
        uint256 firstId = ids[0];
        shuffle(ids);

        uint256 nonce = module.getNonce();

        for (uint256 i; i < ids.length; i++) {
            bytes memory _keys = slice(keys, ids[i] - firstId * 48, operatorKeyCount * 48);
            bytes memory _sigs = slice(sigs, ids[i] - firstId * 96, operatorKeyCount * 96);

            uint256 required = accounting.getRequiredBondForNextKeys(ids[i], operatorKeyCount);

            uint256 toWrap = required + 1 wei;
            vm.deal(address(this), toWrap);
            stETH.submit{ value: toWrap }(address(0));
            wstETH.wrap(toWrap);

            module.addValidatorKeysWstETH(
                owner,
                ids[i],
                operatorKeyCount,
                _keys,
                _sigs,
                IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
            );

            assertEq(module.getNonce(), ++nonce);
        }
    }
}

abstract contract ModuleAddValidatorKeysViaGate is ModuleFixtures {
    GateWithTestCapabilities internal gate;

    // Using a modifier to avoid overriding setUp.
    modifier withGate() {
        gate = new GateWithTestCapabilities(module);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), address(gate));
        _;
    }

    function test_GateAddValidatorKeysETH() public assertInvariants brutalizeMemory withGate {
        uint256 keyCount = 3;
        (bytes memory keys, bytes memory sigs) = keysSignatures(keyCount);
        gate.createNodeOperatorWithKeysWithETHBond(nodeOperator, keyCount, keys, sigs);
    }

    function test_GateAddValidatorKeysETH_MultipleOperators() public assertInvariants brutalizeMemory withGate {
        uint256 operatorCount = 3;
        uint256 operatorKeyCount = 1;
        uint256 keyCount = operatorCount * operatorKeyCount;

        (bytes memory keys, bytes memory sigs) = keysSignatures(keyCount);
        gate.batchCreateNodeOperatorWithKeysWithETHBond(nodeOperator, operatorCount, operatorKeyCount, keys, sigs);
    }

    function test_GateAddValidatorKeysStETH() public assertInvariants brutalizeMemory withGate {
        uint256 keyCount = 3;
        (bytes memory keys, bytes memory sigs) = keysSignatures(keyCount);
        gate.createNodeOperatorWithKeysWithStETHBond(nodeOperator, keyCount, keys, sigs);
    }

    function test_GateAddValidatorKeysStETH_MultipleOperators() public assertInvariants brutalizeMemory withGate {
        uint256 operatorCount = 3;
        uint256 operatorKeyCount = 1;
        uint256 keyCount = operatorCount * operatorKeyCount;

        (bytes memory keys, bytes memory sigs) = keysSignatures(keyCount);
        gate.batchCreateNodeOperatorWithKeysWithStETHBond(nodeOperator, operatorCount, operatorKeyCount, keys, sigs);
    }

    function test_GateAddValidatorKeysWstETH() public assertInvariants brutalizeMemory withGate {
        uint256 keyCount = 3;
        (bytes memory keys, bytes memory sigs) = keysSignatures(keyCount);
        gate.createNodeOperatorWithKeysWithWstETHBond(nodeOperator, keyCount, keys, sigs);
    }

    function test_GateAddValidatorKeysWstETH_MultipleOperators() public assertInvariants brutalizeMemory withGate {
        uint256 operatorCount = 3;
        uint256 operatorKeyCount = 1;
        uint256 keyCount = operatorCount * operatorKeyCount;

        (bytes memory keys, bytes memory sigs) = keysSignatures(keyCount);
        gate.batchCreateNodeOperatorWithKeysWithWstETHBond(nodeOperator, operatorCount, operatorKeyCount, keys, sigs);
    }

    function test_GateAddValidatorKeysETH_RevertWhenCalledFromAnotherGate() public assertInvariants {
        address gateOne = nextAddress("GATE_ONE");
        address gateTwo = nextAddress("GATE_TWO");

        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), gateOne);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), gateTwo);

        vm.prank(gateOne);
        uint256 noId = module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: nodeOperator,
                rewardAddress: nodeOperator,
                extendedManagerPermissions: false
            }),
            address(0)
        );

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        uint256 required = accounting.getRequiredBondForNextKeys(noId, 1);
        vm.deal(gateTwo, required);

        {
            vm.expectRevert(IBaseModule.CannotAddKeys.selector);

            vm.prank(gateTwo);
            module.addValidatorKeysETH{ value: required }(nodeOperator, noId, 1, keys, signatures);
        }
    }

    function test_GateAddValidatorKeysStETH_RevertWhenCalledFromAnotherGate() public assertInvariants {
        address gateOne = nextAddress("GATE_ONE");
        address gateTwo = nextAddress("GATE_TWO");

        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), gateOne);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), gateTwo);

        vm.prank(gateOne);
        uint256 noId = module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: nodeOperator,
                rewardAddress: nodeOperator,
                extendedManagerPermissions: false
            }),
            address(0)
        );

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        {
            vm.expectRevert(IBaseModule.CannotAddKeys.selector);

            vm.prank(gateTwo);
            module.addValidatorKeysStETH(
                nodeOperator,
                noId,
                1,
                keys,
                signatures,
                IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
            );
        }
    }

    function test_GateAddValidatorKeysWstETH_RevertWhenCalledFromAnotherGate() public assertInvariants {
        address gateOne = nextAddress("GATE_ONE");
        address gateTwo = nextAddress("GATE_TWO");

        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), gateOne);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), gateTwo);

        vm.prank(gateOne);
        uint256 noId = module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: nodeOperator,
                rewardAddress: nodeOperator,
                extendedManagerPermissions: false
            }),
            address(0)
        );

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        {
            vm.expectRevert(IBaseModule.CannotAddKeys.selector);

            vm.prank(gateTwo);
            module.addValidatorKeysWstETH(
                nodeOperator,
                noId,
                1,
                keys,
                signatures,
                IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
            );
        }
    }

    function test_GateAddValidatorKeysETH_RevertWhenCalledTwice() public assertInvariants withGate {
        (bytes memory keys, bytes memory sigs) = keysSignatures(1);
        uint256 noId = gate.createNodeOperatorWithKeysWithETHBond(nodeOperator, 1, keys, sigs);

        (keys, sigs) = keysSignatures(1, 1);

        {
            vm.expectRevert(IBaseModule.CannotAddKeys.selector);

            vm.prank(address(gate));
            module.addValidatorKeysETH(nodeOperator, noId, 1, keys, sigs);
        }
    }

    function test_GateAddValidatorKeysStETH_RevertWhenCalledTwice() public assertInvariants withGate {
        (bytes memory keys, bytes memory sigs) = keysSignatures(1);
        uint256 noId = gate.createNodeOperatorWithKeysWithStETHBond(nodeOperator, 1, keys, sigs);

        (keys, sigs) = keysSignatures(1, 1);
        {
            vm.expectRevert(IBaseModule.CannotAddKeys.selector);

            vm.prank(address(gate));
            module.addValidatorKeysStETH(
                nodeOperator,
                noId,
                1,
                keys,
                sigs,
                IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
            );
        }
    }

    function test_GateAddValidatorKeysWstETH_RevertWhenCalledTwice() public assertInvariants withGate {
        (bytes memory keys, bytes memory sigs) = keysSignatures(1);
        uint256 noId = gate.createNodeOperatorWithKeysWithWstETHBond(nodeOperator, 1, keys, sigs);

        (keys, sigs) = keysSignatures(1, 1);

        {
            vm.expectRevert(IBaseModule.CannotAddKeys.selector);

            vm.prank(address(gate));
            module.addValidatorKeysWstETH(
                nodeOperator,
                noId,
                1,
                keys,
                sigs,
                IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
            );
        }
    }
}

abstract contract ModuleAddValidatorKeysNegative is ModuleFixtures {
    function beforeTestSetup(bytes4 /* testSelector */) public pure returns (bytes[] memory beforeTestCalldata) {
        beforeTestCalldata = new bytes[](1);
        beforeTestCalldata[0] = abi.encodePacked(this.beforeEach.selector);
    }

    function beforeEach() external {
        createNodeOperator();
    }

    function test_AddValidatorKeysETH_RevertWhen_SenderIsNotEligible() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(stranger, required);
        vm.expectRevert(IBaseModule.SenderIsNotEligible.selector);
        vm.prank(stranger);
        module.addValidatorKeysETH{ value: required }(stranger, noId, 1, new bytes(0), new bytes(0));
    }

    function test_AddValidatorKeysETH_RevertWhen_CannotAddKeys() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(stranger, required);
        vm.startPrank(admin);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);
        vm.stopPrank();

        vm.expectRevert(IBaseModule.CannotAddKeys.selector);
        vm.prank(stranger);
        module.addValidatorKeysETH{ value: required }(nodeOperator, noId, 1, new bytes(0), new bytes(0));
    }

    function test_AddValidatorKeysETH_RevertWhen_NoKeys() public assertInvariants {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 required = accounting.getRequiredBondForNextKeys(0, 0);
        vm.deal(nodeOperator, required);
        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(nodeOperator, noId, 0, new bytes(0), new bytes(0));
    }

    function test_AddValidatorKeysETH_RevertWhen_KeysAndSigsLengthMismatch() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        (bytes memory keys, ) = keysSignatures(keysCount);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);

        vm.expectRevert(SigningKeys.InvalidLength.selector);
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(nodeOperator, noId, keysCount, keys, new bytes(0));
    }

    function test_AddValidatorKeysETH_RevertWhen_ZeroKey() public assertInvariants {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        (bytes memory keys, bytes memory signatures) = keysSignaturesWithZeroKey(keysCount, 0);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);

        vm.expectRevert(SigningKeys.EmptyKey.selector);
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(nodeOperator, noId, keysCount, keys, signatures);
    }

    function test_AddValidatorKeysETH_RevertWhen_KeysLimitExceeded() public assertInvariants {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);

        parametersRegistry.setKeysLimit(0, 1);

        vm.expectRevert(IBaseModule.KeysLimitExceeded.selector);
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(nodeOperator, noId, 1, keys, signatures);
    }

    function test_AddValidatorKeysStETH_RevertWhen_SenderIsNotEligible() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.prank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        vm.expectRevert(IBaseModule.SenderIsNotEligible.selector);
        vm.prank(stranger);
        module.addValidatorKeysStETH(
            stranger,
            noId,
            1,
            new bytes(0),
            new bytes(0),
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysStETH_RevertWhen_CannotAddKeys() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.prank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));
        vm.startPrank(admin);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);
        vm.stopPrank();

        vm.expectRevert(IBaseModule.CannotAddKeys.selector);
        vm.prank(stranger);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            new bytes(0),
            new bytes(0),
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysStETH_RevertWhen_NoKeys() public assertInvariants {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            0,
            new bytes(0),
            new bytes(0),
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysStETH_RevertWhen_KeysAndSigsLengthMismatch() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        (bytes memory keys, ) = keysSignatures(keysCount);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        vm.expectRevert(SigningKeys.InvalidLength.selector);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            new bytes(0),
            IAccounting.PermitInput({ value: BOND_SIZE, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysStETH_RevertWhen_ZeroKey() public assertInvariants {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        (bytes memory keys, bytes memory signatures) = keysSignaturesWithZeroKey(keysCount, 0);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        vm.expectRevert(SigningKeys.EmptyKey.selector);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            signatures,
            IAccounting.PermitInput({ value: BOND_SIZE, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysETH_RevertWhen_InvalidAmount() public assertInvariants {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required - 1 ether);

        vm.expectRevert(IBaseModule.InvalidAmount.selector);
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required - 1 ether }(nodeOperator, noId, 1, keys, signatures);
    }

    function test_AddValidatorKeysStETH_RevertWhen_KeysLimitExceeded() public assertInvariants {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        parametersRegistry.setKeysLimit(0, 1);

        vm.expectRevert(IBaseModule.KeysLimitExceeded.selector);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({ value: BOND_SIZE, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_SenderIsNotEligible() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        vm.stopPrank();

        vm.expectRevert(IBaseModule.SenderIsNotEligible.selector);
        vm.prank(stranger);
        module.addValidatorKeysWstETH(
            stranger,
            noId,
            1,
            new bytes(0),
            new bytes(0),
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_CannotAddKeys() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        vm.stopPrank();
        vm.startPrank(admin);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);
        vm.stopPrank();

        vm.expectRevert(IBaseModule.CannotAddKeys.selector);
        vm.prank(stranger);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            new bytes(0),
            new bytes(0),
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_NoKeys() public assertInvariants {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            0,
            new bytes(0),
            new bytes(0),
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_KeysAndSigsLengthMismatch() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (bytes memory keys, ) = keysSignatures(keysCount);

        vm.expectRevert(SigningKeys.InvalidLength.selector);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            new bytes(0),
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_ZeroKey() public assertInvariants {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (bytes memory keys, bytes memory signatures) = keysSignaturesWithZeroKey(keysCount, 0);

        vm.expectRevert(SigningKeys.EmptyKey.selector);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            signatures,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_KeysLimitExceeded() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        parametersRegistry.setKeysLimit(0, 1);

        vm.expectRevert(IBaseModule.KeysLimitExceeded.selector);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }
}
