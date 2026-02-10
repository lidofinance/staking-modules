// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IMetaRegistry } from "./interfaces/IMetaRegistry.sol";
import { IStakingModule, IStakingModuleV2 } from "./interfaces/IStakingModule.sol";
import { IBaseModule, NodeOperator, NodeOperatorManagementProperties } from "./interfaces/IBaseModule.sol";

import { BaseModule } from "./abstract/BaseModule.sol";

import { NOAddresses } from "./lib/NOAddresses.sol";
import { SigningKeys } from "./lib/SigningKeys.sol";
import { TransientUintUintMap, TransientUintUintMapLib } from "./lib/TransientUintUintMapLib.sol";
import { CuratedDepositAllocator } from "./lib/allocator/CuratedDepositAllocator.sol";
import { NodeOperatorOps } from "./lib/NodeOperatorOps.sol";

contract CuratedModule is ICuratedModule, BaseModule {
    /// @custom:storage-location erc7201:CuratedModule
    struct CuratedModuleStorage {
        // Tracks per-operator balances (in wei) reported by the Accounting oracle.
        mapping(uint256 nodeOperatorId => uint256 balance) operatorBalances;
        // Tracks how many operators left to update due to changes in weights.
        uint256 upToDateOperatorWeightsCount;
    }

    bytes32 public constant OPERATOR_ADDRESSES_ADMIN_ROLE =
        keccak256("OPERATOR_ADDRESSES_ADMIN_ROLE");

    IMetaRegistry public immutable META_REGISTRY;

    uint64 internal constant INITIALIZED_VERSION = 1;
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
    )
        BaseModule(
            moduleType,
            lidoLocator,
            parametersRegistry,
            accounting,
            exitPenalties
        )
    {
        if (metaRegistry == address(0)) {
            revert ZeroMetaRegistryAddress();
        }

        META_REGISTRY = IMetaRegistry(metaRegistry);
    }

    /// @dev Initialize contract from scratch. In case of a method call frontrun, the contract instance should be discarded.
    ///      It is recommended to call this method in the same transaction as the deployment transaction
    ///      and perform extensive deployment verification before using the contract instance.
    function initialize(
        address admin
    ) external override reinitializer(INITIALIZED_VERSION) {
        __BaseModule_init(admin);
    }

    /// @inheritdoc IStakingModule
    function obtainDepositData(
        uint256 depositsCount,
        bytes calldata /* depositCalldata */
    ) external returns (bytes memory publicKeys, bytes memory signatures) {
        _checkStakingRouterRole();
        _requireNodeOperatorWeightsUpToDate();

        (
            uint256 allocated,
            uint256[] memory operatorIds,
            uint256[] memory allocations
        ) = CuratedDepositAllocator.allocateInitialDeposits(
                _nodeOperators,
                _nodeOperatorsCount,
                depositsCount
            );
        if (allocated == 0) {
            return (publicKeys, signatures);
        }
        (publicKeys, signatures) = SigningKeys.initKeysSigsBuf(allocated);

        uint256 loadedKeysCount;
        CuratedModuleStorage storage $ = _storage();
        for (uint256 i; i < allocations.length; ++i) {
            uint256 allocation = allocations[i];
            uint256 operatorId = operatorIds[i];
            NodeOperator storage no = _nodeOperators[operatorId];

            SigningKeys.loadKeysSigs({
                nodeOperatorId: operatorId,
                startIndex: no.totalDepositedKeys,
                keysCount: allocation,
                pubkeys: publicKeys,
                signatures: signatures,
                bufOffset: loadedKeysCount
            });

            loadedKeysCount += allocation;

            uint32 totalDepositedKeys = no.totalDepositedKeys +
                uint32(allocation);
            no.totalDepositedKeys = totalDepositedKeys;
            emit DepositedSigningKeysCountChanged(
                operatorId,
                totalDepositedKeys
            );

            uint32 depositableValidatorsCount = no.depositableValidatorsCount -
                uint32(allocation);
            no.depositableValidatorsCount = depositableValidatorsCount;
            emit DepositableSigningKeysCountChanged(
                operatorId,
                depositableValidatorsCount
            );

            _increaseOperatorBalance(
                $,
                operatorId,
                allocation * CuratedDepositAllocator.MIN_ACTIVATION_BALANCE
            );
        }
        unchecked {
            _depositableValidatorsCount -= uint64(allocated);
            _totalDepositedValidators += uint64(allocated);
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
        _requireNodeOperatorWeightsUpToDate();

        if (maxDepositAmount == 0) {
            return new uint256[](0);
        }

        if (
            pubkeys.length != keyIndices.length ||
            pubkeys.length != topUpLimits.length ||
            pubkeys.length != operatorIds.length
        ) {
            revert InvalidInput();
        }

        // NOTE: StakingRouter is expected to provide per-key top-up limits capped
        // by MAX_EFFECTIVE_BALANCE and avoid duplicate (operatorId, keyIndex)
        // entries in a single request.

        _validateTopUpPublicKeys(pubkeys, keyIndices, operatorIds);
        allocations = _allocateTopUps(
            maxDepositAmount,
            operatorIds,
            keyIndices,
            topUpLimits
        );

        // TODO: Do we need to check for zero allocations here?
        _incrementModuleNonce();
    }

    /// @inheritdoc IStakingModuleV2
    function updateOperatorBalances(
        uint256[] calldata operatorIds,
        uint256[] calldata validatorsBalancesGwei,
        uint256[] calldata pendingBalancesGwei,
        uint256 /* refSlot */
    ) external {
        _checkStakingRouterRole();
        // TODO: Move operator balances ops into internal lib
        uint256 operatorsCount = operatorIds.length;
        if (
            operatorsCount != validatorsBalancesGwei.length ||
            operatorsCount != pendingBalancesGwei.length
        ) {
            revert InvalidInput();
        }

        CuratedModuleStorage storage $ = _storage();
        uint256 nodeOperatorsCount = _nodeOperatorsCount;

        for (uint256 i; i < operatorsCount; ++i) {
            uint256 operatorId = operatorIds[i];
            if (operatorId >= nodeOperatorsCount) {
                revert NodeOperatorDoesNotExist();
            }

            _setOperatorBalance(
                $,
                operatorId,
                (validatorsBalancesGwei[i] + pendingBalancesGwei[i]) * 1 gwei
            );
        }
        _incrementModuleNonce();
    }

    /// @inheritdoc ICuratedModule
    function getOperatorWeights(
        uint256[] calldata operatorIds
    ) external view returns (uint256[] memory operatorWeights) {
        _requireNodeOperatorWeightsUpToDate();
        return _metaRegistry().getOperatorWeights(operatorIds);
    }

    /// @inheritdoc IBaseModule
    function createNodeOperator(
        address from,
        NodeOperatorManagementProperties calldata managementProperties,
        address referrer
    ) public override(IBaseModule, BaseModule) whenResumed returns (uint256) {
        CuratedModuleStorage storage $ = _storage();
        if ($.upToDateOperatorWeightsCount == _nodeOperatorsCount) {
            // NOTE: Unconditionally increase the counter because the new operator will have zero weight, hence do not
            // affect the allocation. The operator should be added to a group eventually and it will trigger the full
            // weights refresh routine.
            unchecked {
                ++$.upToDateOperatorWeightsCount;
            }
        }

        return super.createNodeOperator(from, managementProperties, referrer);
    }

    /// @inheritdoc ICuratedModule
    function changeNodeOperatorAddresses(
        uint256 nodeOperatorId,
        address newManagerAddress,
        address newRewardAddress
    ) external {
        _checkRole(OPERATOR_ADDRESSES_ADMIN_ROLE);
        NOAddresses.changeNodeOperatorAddresses(
            _nodeOperators,
            nodeOperatorId,
            newManagerAddress,
            newRewardAddress
        );
    }

    // TODO: Rename to updateNodeOperatorWeightAndDepositableValidatorsCount
    /// @inheritdoc IBaseModule
    /// @dev This one is called in `Accounting.setBondCurve`.
    function onNodeOperatorBondCurveUpdated(
        uint256 nodeOperatorId
    ) external override(IBaseModule) {
        _metaRegistry().refreshOperatorWeight(nodeOperatorId);
        _updateDepositableValidatorsCount({
            nodeOperatorId: nodeOperatorId,
            incrementNonceIfUpdated: true
        });
    }

    /// @inheritdoc ICuratedModule
    function onNodeOperatorWeightChange(
        uint256 nodeOperatorId,
        uint256 newWeight
    ) external {
        if (msg.sender != address(_metaRegistry())) {
            revert SenderIsNotMetaRegistry();
        }

        if (newWeight == 0) {
            _applyDepositableValidatorsCount({
                no: _nodeOperators[nodeOperatorId],
                nodeOperatorId: nodeOperatorId,
                newCount: 0,
                incrementNonceIfUpdated: false
            });
        }

        // NOTE: We always increment the nonce since weight change might affect the expected deposit allocation.
        _incrementModuleNonce();
    }

    /// @inheritdoc ICuratedModule
    function requestFullOperatorWeightsUpdate() external {
        if (msg.sender != address(_metaRegistry())) {
            revert SenderIsNotMetaRegistry();
        }

        _storage().upToDateOperatorWeightsCount = 0;
        _incrementModuleNonce();
    }

    /// @inheritdoc ICuratedModule
    function batchUpdateNodeOperatorWeights(
        uint256 maxCount
    ) external override returns (uint256 operatorsLeft) {
        if (maxCount == 0) {
            revert InvalidMaxCount();
        }

        CuratedModuleStorage storage $ = _storage();
        uint256 operatorsCount = _nodeOperatorsCount;
        uint256 noId = $.upToDateOperatorWeightsCount;
        if (noId == operatorsCount) {
            return 0;
        }

        uint256 limit = Math.min(noId + maxCount, operatorsCount);

        for (; noId < limit; ++noId) {
            _metaRegistry().refreshOperatorWeight(noId);
        }

        $.upToDateOperatorWeightsCount = limit;
        operatorsLeft = operatorsCount - limit;

        if (operatorsLeft == 0) emit NodeOperatorWeightsUpToDate();
    }

    /// @inheritdoc ICuratedModule
    function getNodeOperatorWeightsToUpdateCount()
        external
        view
        returns (uint256)
    {
        return _nodeOperatorsCount - _storage().upToDateOperatorWeightsCount;
    }

    /// @inheritdoc ICuratedModule
    function getNodeOperatorBalance(
        uint256 operatorId
    ) external view returns (uint256) {
        return _storage().operatorBalances[operatorId];
    }

    /// @inheritdoc ICuratedModule
    function getDepositsAllocation(
        uint256 maxDepositAmount
    )
        external
        view
        returns (
            uint256 allocated,
            uint256[] memory operatorIds,
            uint256[] memory allocations
        )
    {
        _requireNodeOperatorWeightsUpToDate();

        uint256 operatorsCount = _nodeOperatorsCount;
        if (maxDepositAmount == 0 || operatorsCount == 0) {
            return (0, new uint256[](0), new uint256[](0));
        }

        uint256[] memory allOperatorIds = new uint256[](operatorsCount);
        for (uint256 i; i < operatorsCount; ++i) {
            allOperatorIds[i] = i;
        }

        (allocated, operatorIds, allocations) = CuratedDepositAllocator
            .allocateTopUps({
                nodeOperators: _nodeOperators,
                nodeOperatorBalances: _storage().operatorBalances,
                operatorsCount: operatorsCount,
                allocationAmount: maxDepositAmount,
                operatorIds: allOperatorIds
            });
    }

    function _applyDepositableValidatorsCount(
        NodeOperator storage no,
        uint256 nodeOperatorId,
        uint256 newCount,
        bool incrementNonceIfUpdated
    ) internal override returns (bool depositableChanged) {
        if (newCount > 0) {
            uint256 weight = _metaRegistry().getNodeOperatorWeight(
                nodeOperatorId
            );
            if (weight == 0) {
                newCount = 0;
            }
        }

        depositableChanged = super._applyDepositableValidatorsCount({
            no: no,
            nodeOperatorId: nodeOperatorId,
            newCount: newCount,
            incrementNonceIfUpdated: incrementNonceIfUpdated
        });
    }

    function _requireNodeOperatorWeightsUpToDate() internal view {
        if (_storage().upToDateOperatorWeightsCount != _nodeOperatorsCount) {
            revert NodeOperatorWeightsUpdateInProgress();
        }
    }

    function _validateTopUpPublicKeys(
        bytes[] calldata pubkeys,
        uint256[] calldata keyIndices,
        uint256[] calldata operatorIds
    ) internal view {
        for (uint256 i; i < pubkeys.length; ++i) {
            // TODO: Move to NodeOperatorOps and unify with CSM
            uint256 operatorId = operatorIds[i];
            uint256 keyIndex = keyIndices[i];
            if (keyIndex >= _nodeOperators[operatorId].totalDepositedKeys) {
                revert SigningKeysInvalidOffset();
            }
            if (
                keccak256(pubkeys[i]) !=
                keccak256(SigningKeys.loadKeys(operatorId, keyIndex, 1))
            ) {
                revert PubkeyMismatch();
            }
        }
    }

    function _allocateTopUps(
        uint256 maxDepositAmount,
        uint256[] calldata operatorIds,
        uint256[] calldata keyIndices,
        uint256[] calldata topUpLimits
    ) internal returns (uint256[] memory allocations) {
        uint256[] memory uniqueOperatorIds = _uniqueOperatorIds(operatorIds);
        (
            ,
            uint256[] memory allocatedOperatorIds,
            uint256[] memory operatorAllocations
        ) = CuratedDepositAllocator.allocateTopUps({
                nodeOperators: _nodeOperators,
                nodeOperatorBalances: _storage().operatorBalances,
                operatorsCount: _nodeOperatorsCount,
                allocationAmount: maxDepositAmount,
                operatorIds: uniqueOperatorIds
            });

        // TODO: Add capped top-up limits like in CSM

        uint256[] memory perOperatorIncrements;
        (allocations, perOperatorIncrements) = NodeOperatorOps
            .distributeTopUpAllocations({
                operatorIds: operatorIds,
                topUpLimits: topUpLimits,
                allocatedOperatorIds: allocatedOperatorIds,
                operatorAllocations: operatorAllocations,
                operatorsCount: _nodeOperatorsCount
            });

        NodeOperatorOps.increaseKeyAddedBalancesByAllocations(
            _keyAddedBalances,
            operatorIds,
            keyIndices,
            allocations
        );
        _increaseOperatorBalancesByAllocations({
            uniqueOperatorIds: uniqueOperatorIds,
            perOperatorIncrements: perOperatorIncrements
        });
    }

    /// @dev Deduplicate operator ids for allocation to avoid overweighting by repeated keys.
    function _uniqueOperatorIds(
        uint256[] calldata operatorIds
    ) internal returns (uint256[] memory uniqueOperatorIds) {
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

    function _increaseOperatorBalancesByAllocations(
        uint256[] memory uniqueOperatorIds,
        uint256[] memory perOperatorIncrements
    ) internal {
        CuratedModuleStorage storage $ = _storage();
        for (uint256 i; i < uniqueOperatorIds.length; ++i) {
            uint256 operatorId = uniqueOperatorIds[i];
            uint256 increment = perOperatorIncrements[operatorId];
            if (increment == 0) continue;
            _increaseOperatorBalance($, operatorId, increment);
        }
    }

    function _increaseOperatorBalance(
        CuratedModuleStorage storage $,
        uint256 operatorId,
        uint256 incrementWei
    ) internal {
        _setOperatorBalance(
            $,
            operatorId,
            $.operatorBalances[operatorId] + incrementWei
        );
    }

    function _setOperatorBalance(
        CuratedModuleStorage storage $,
        uint256 operatorId,
        uint256 balanceWei
    ) internal {
        $.operatorBalances[operatorId] = balanceWei;
        emit NodeOperatorBalanceUpdated(operatorId, balanceWei);
    }

    function _metaRegistry() internal view returns (IMetaRegistry) {
        return META_REGISTRY;
    }

    function _storage() internal pure returns (CuratedModuleStorage storage $) {
        assembly ("memory-safe") {
            $.slot := CURATED_MODULE_STORAGE_LOCATION
        }
    }
}

// Last review ended here
