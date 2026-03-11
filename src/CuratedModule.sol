// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IMetaRegistry } from "./interfaces/IMetaRegistry.sol";
import { IStakingModule, IStakingModuleV2 } from "./interfaces/IStakingModule.sol";
import { NodeOperator } from "./interfaces/IBaseModule.sol";

import { BaseModule } from "./abstract/BaseModule.sol";

import { NOAddresses } from "./lib/NOAddresses.sol";
import { SigningKeys } from "./lib/SigningKeys.sol";
import { TransientUintUintMap, TransientUintUintMapLib } from "./lib/TransientUintUintMapLib.sol";
import { CuratedDepositAllocator } from "./lib/allocator/CuratedDepositAllocator.sol";
import { CuratedOperatorBalancesOps } from "./lib/CuratedOperatorBalancesOps.sol";
import { NodeOperatorOps } from "./lib/NodeOperatorOps.sol";

contract CuratedModule is ICuratedModule, BaseModule {
    /// @custom:storage-location erc7201:CuratedModule
    struct CuratedModuleStorage {
        // Tracks per-operator balances (in wei) reported by the Accounting oracle.
        mapping(uint256 nodeOperatorId => uint256 balance) operatorBalances;
    }

    bytes32 public constant OPERATOR_ADDRESSES_ADMIN_ROLE = keccak256("OPERATOR_ADDRESSES_ADMIN_ROLE");

    IMetaRegistry public immutable META_REGISTRY;

    // keccak256(abi.encode(uint256(keccak256("CuratedModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CURATED_MODULE_STORAGE_LOCATION =
        0x748416948424a2a643c796b7b8213bcf41155fd3a072f0851ad0a3d6ca632500;

    constructor(
        bytes32 moduleType,
        address lidoLocator,
        address parametersRegistry,
        address accounting,
        address exitPenalties,
        address metaRegistry
    ) BaseModule(moduleType, lidoLocator, parametersRegistry, accounting, exitPenalties) {
        if (metaRegistry == address(0)) revert ZeroMetaRegistryAddress();

        META_REGISTRY = IMetaRegistry(metaRegistry);
    }

    /// @dev Initialize contract from scratch. In case of a method call frontrun, the contract instance should be discarded.
    ///      It is recommended to call this method in the same transaction as the deployment transaction
    ///      and perform extensive deployment verification before using the contract instance.
    function initialize(address admin) external override initializer {
        __BaseModule_init(admin);
    }

    /// @inheritdoc IStakingModule
    function obtainDepositData(
        uint256 depositsCount,
        bytes calldata /* depositCalldata */
    ) external returns (bytes memory publicKeys, bytes memory signatures) {
        _checkStakingRouterRole();
        _requireDepositInfoUpToDate();

        BaseModuleStorage storage $ = _baseStorage();
        (uint256 allocated, uint256[] memory operatorIds, uint256[] memory allocations) = CuratedDepositAllocator
            .allocateInitialDeposits($.nodeOperators, $.nodeOperatorsCount, depositsCount);
        if (allocated == 0) return (publicKeys, signatures);
        (publicKeys, signatures) = SigningKeys.initKeysSigsBuf(allocated);

        uint256 loadedKeysCount;
        for (uint256 i; i < allocations.length; ++i) {
            uint256 allocation = allocations[i];
            uint256 operatorId = operatorIds[i];
            NodeOperator storage no = $.nodeOperators[operatorId];

            SigningKeys.loadKeysSigs({
                nodeOperatorId: operatorId,
                startIndex: no.totalDepositedKeys,
                keysCount: allocation,
                pubkeys: publicKeys,
                signatures: signatures,
                bufOffset: loadedKeysCount
            });

            loadedKeysCount += allocation;

            // `allocation` is capped by depositableValidatorsCount which is uint32.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint32 totalDepositedKeys = no.totalDepositedKeys + uint32(allocation);
            no.totalDepositedKeys = totalDepositedKeys;
            emit DepositedSigningKeysCountChanged(operatorId, totalDepositedKeys);

            // `allocation` is capped by depositableValidatorsCount which is uint32.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint32 depositableValidatorsCount = no.depositableValidatorsCount - uint32(allocation);
            no.depositableValidatorsCount = depositableValidatorsCount;
            emit DepositableSigningKeysCountChanged(operatorId, depositableValidatorsCount);

            CuratedOperatorBalancesOps.increaseBalance(
                _curatedStorage().operatorBalances,
                operatorId,
                allocation * CuratedDepositAllocator.MIN_ACTIVATION_BALANCE
            );
        }
        unchecked {
            // `allocated` is capped by _depositableValidatorsCount which is uint64.
            // forge-lint: disable-next-line(unsafe-typecast)
            $.depositableValidatorsCount -= uint64(allocated);
            // `allocated` is capped by _depositableValidatorsCount which is uint64.
            // forge-lint: disable-next-line(unsafe-typecast)
            $.totalDepositedValidators += uint64(allocated);
        }

        _incrementModuleNonce();
    }

    /// @inheritdoc IStakingModuleV2
    function allocateDeposits(
        uint256 maxDepositAmount,
        bytes[] calldata pubkeys,
        uint256[] calldata keyIndices,
        uint256[] calldata operatorIds,
        uint256[] calldata topUpLimits
    ) external returns (uint256[] memory allocations) {
        _checkStakingRouterRole();
        _requireDepositInfoUpToDate();

        if (maxDepositAmount == 0) return new uint256[](0);
        if (
            pubkeys.length != keyIndices.length ||
            pubkeys.length != topUpLimits.length ||
            pubkeys.length != operatorIds.length
        ) {
            revert InvalidInput();
        }

        // NOTE: StakingRouter is expected to avoid duplicate (operatorId, keyIndex)
        // entries in a single request.

        _validateTopUpPublicKeys(pubkeys, keyIndices, operatorIds);

        // Cap top-ups so we don't over-allocate to keys that lost balance due to CL penalties.
        uint256[] memory cappedTopUpLimits = NodeOperatorOps.capTopUpLimitsByKeyBalance(
            _baseStorage().keyAddedBalances,
            operatorIds,
            keyIndices,
            topUpLimits
        );

        allocations = _allocateTopUps(maxDepositAmount, operatorIds, keyIndices, cappedTopUpLimits);

        _incrementModuleNonce();
    }

    /// @inheritdoc IStakingModuleV2
    function updateOperatorBalances(bytes calldata operatorIds, bytes calldata totalBalancesGwei) external {
        _checkStakingRouterRole();
        CuratedOperatorBalancesOps.applyReportedBalances(
            _curatedStorage().operatorBalances,
            _baseStorage().nodeOperatorsCount,
            operatorIds,
            totalBalancesGwei
        );
        _incrementModuleNonce();
    }

    /// @inheritdoc ICuratedModule
    function changeNodeOperatorAddresses(
        uint256 nodeOperatorId,
        address newManagerAddress,
        address newRewardAddress
    ) external {
        _checkRole(OPERATOR_ADDRESSES_ADMIN_ROLE);
        NOAddresses.changeNodeOperatorAddresses(
            _baseStorage().nodeOperators,
            nodeOperatorId,
            newManagerAddress,
            newRewardAddress
        );
    }

    /// @inheritdoc ICuratedModule
    function notifyNodeOperatorWeightChange(uint256 nodeOperatorId, uint256 oldWeight, uint256 newWeight) external {
        if (msg.sender != address(_metaRegistry())) revert SenderIsNotMetaRegistry();
        if (newWeight == 0) {
            _applyDepositableValidatorsCount({
                no: _baseStorage().nodeOperators[nodeOperatorId],
                nodeOperatorId: nodeOperatorId,
                newCount: 0,
                incrementNonceIfUpdated: false
            });
        } else if (oldWeight == 0) {
            _updateDepositableValidatorsCount({ nodeOperatorId: nodeOperatorId, incrementNonceIfUpdated: false });
        }

        // NOTE: We always increment the nonce since weight change might affect the expected deposit allocation.
        _incrementModuleNonce();
    }

    /// @inheritdoc ICuratedModule
    function getOperatorWeights(
        uint256[] calldata operatorIds
    ) external view returns (uint256[] memory operatorWeights) {
        _requireDepositInfoUpToDate();
        return _metaRegistry().getOperatorWeights(operatorIds);
    }

    /// @inheritdoc ICuratedModule
    function getNodeOperatorBalance(uint256 operatorId) external view returns (uint256) {
        return _curatedStorage().operatorBalances[operatorId];
    }

    /// @inheritdoc ICuratedModule
    function getDepositAllocationTargets()
        external
        view
        returns (uint256[] memory currentValidators, uint256[] memory targetValidators)
    {
        _requireDepositInfoUpToDate();
        BaseModuleStorage storage $ = _baseStorage();
        return CuratedDepositAllocator.getDepositAllocationTargets($.nodeOperators, $.nodeOperatorsCount);
    }

    /// @inheritdoc ICuratedModule
    function getTopUpAllocationTargets()
        external
        view
        returns (uint256[] memory currentAllocations, uint256[] memory targetAllocations)
    {
        _requireDepositInfoUpToDate();
        return
            CuratedDepositAllocator.getTopUpAllocationTargets(
                _curatedStorage().operatorBalances,
                _baseStorage().nodeOperatorsCount
            );
    }

    /// @inheritdoc ICuratedModule
    function getDepositsAllocation(
        uint256 maxDepositAmount
    ) external view returns (uint256 allocated, uint256[] memory operatorIds, uint256[] memory allocations) {
        _requireDepositInfoUpToDate();
        BaseModuleStorage storage $ = _baseStorage();
        uint256 operatorsCount = $.nodeOperatorsCount;
        if (maxDepositAmount == 0 || operatorsCount == 0) return (0, new uint256[](0), new uint256[](0));

        uint256[] memory allOperatorIds = new uint256[](operatorsCount);
        for (uint256 i; i < operatorsCount; ++i) {
            allOperatorIds[i] = i;
        }

        (allocated, operatorIds, allocations) = CuratedDepositAllocator.allocateTopUps({
            nodeOperators: $.nodeOperators,
            nodeOperatorBalances: _curatedStorage().operatorBalances,
            operatorsCount: operatorsCount,
            allocationAmount: maxDepositAmount,
            operatorIds: allOperatorIds
        });
    }

    function _updateDepositInfo(uint256 nodeOperatorId) internal override {
        _metaRegistry().refreshOperatorWeight(nodeOperatorId);
        _updateDepositableValidatorsCount({ nodeOperatorId: nodeOperatorId, incrementNonceIfUpdated: true });
    }

    function _applyDepositableValidatorsCount(
        NodeOperator storage no,
        uint256 nodeOperatorId,
        uint256 newCount,
        bool incrementNonceIfUpdated
    ) internal override returns (bool depositableChanged) {
        if (newCount > 0) {
            uint256 weight = _metaRegistry().getNodeOperatorWeight(nodeOperatorId);
            if (weight == 0) newCount = 0;
        }

        depositableChanged = super._applyDepositableValidatorsCount({
            no: no,
            nodeOperatorId: nodeOperatorId,
            newCount: newCount,
            incrementNonceIfUpdated: incrementNonceIfUpdated
        });
    }

    function _allocateTopUps(
        uint256 maxDepositAmount,
        uint256[] calldata operatorIds,
        uint256[] calldata keyIndices,
        uint256[] memory topUpLimits
    ) internal returns (uint256[] memory allocations) {
        BaseModuleStorage storage $ = _baseStorage();
        uint256[] memory uniqueOperatorIds = _uniqueOperatorIds(operatorIds);
        (, uint256[] memory allocatedOperatorIds, uint256[] memory operatorAllocations) = CuratedDepositAllocator
            .allocateTopUps({
                nodeOperators: $.nodeOperators,
                nodeOperatorBalances: _curatedStorage().operatorBalances,
                operatorsCount: $.nodeOperatorsCount,
                allocationAmount: maxDepositAmount,
                operatorIds: uniqueOperatorIds
            });

        uint256[] memory perOperatorIncrements;
        (allocations, perOperatorIncrements) = NodeOperatorOps.distributeTopUpAllocations({
            operatorIds: operatorIds,
            topUpLimits: topUpLimits,
            allocatedOperatorIds: allocatedOperatorIds,
            operatorAllocations: operatorAllocations,
            operatorsCount: $.nodeOperatorsCount
        });

        NodeOperatorOps.increaseKeyAddedBalancesByAllocations($.keyAddedBalances, operatorIds, keyIndices, allocations);
        CuratedOperatorBalancesOps.increaseByAllocations(
            _curatedStorage().operatorBalances,
            uniqueOperatorIds,
            perOperatorIncrements
        );
    }

    /// @dev Deduplicate operator ids for allocation to avoid overweighting by repeated keys.
    function _uniqueOperatorIds(uint256[] calldata operatorIds) internal returns (uint256[] memory uniqueOperatorIds) {
        uniqueOperatorIds = new uint256[](operatorIds.length);
        TransientUintUintMap seen = TransientUintUintMapLib.create();
        uint256 count;
        for (uint256 i; i < operatorIds.length; ++i) {
            uint256 operatorId = operatorIds[i];
            if (seen.get(operatorId) != 0) continue;
            seen.set(operatorId, 1);
            uniqueOperatorIds[count] = operatorId;
            ++count;
        }

        if (count != operatorIds.length) {
            // Trim the uniqueOperatorIds array to the actual count of unique ids.
            assembly {
                mstore(uniqueOperatorIds, count)
            }
        }
    }

    function _validateTopUpPublicKeys(
        bytes[] calldata pubkeys,
        uint256[] calldata keyIndices,
        uint256[] calldata operatorIds
    ) internal view {
        for (uint256 i; i < pubkeys.length; ++i) {
            uint256 operatorId = operatorIds[i];
            uint256 keyIndex = keyIndices[i];
            if (keyIndex >= _baseStorage().nodeOperators[operatorId].totalDepositedKeys)
                revert SigningKeysInvalidOffset();
            SigningKeys.verifySigningKey(operatorId, keyIndex, pubkeys[i]);
        }
    }

    function _metaRegistry() internal view returns (IMetaRegistry) {
        return META_REGISTRY;
    }

    function _canRequestDepositInfoUpdate() internal view override {
        if (msg.sender != address(_accounting()) && msg.sender != address(_metaRegistry())) {
            revert SenderIsNotEligible();
        }
    }

    function _curatedStorage() internal pure returns (CuratedModuleStorage storage $) {
        assembly ("memory-safe") {
            $.slot := CURATED_MODULE_STORAGE_LOCATION
        }
    }
}
