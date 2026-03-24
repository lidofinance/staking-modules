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
import { CuratedDepositAllocator } from "./lib/allocator/CuratedDepositAllocator.sol";
import { NodeOperatorOps } from "./lib/NodeOperatorOps.sol";
import { StakeTracker } from "./lib/StakeTracker.sol";

contract CuratedModule is ICuratedModule, BaseModule {
    bytes32 public constant OPERATOR_ADDRESSES_ADMIN_ROLE = keccak256("OPERATOR_ADDRESSES_ADMIN_ROLE");

    IMetaRegistry public immutable META_REGISTRY;

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
            _baseStorage(),
            operatorIds,
            keyIndices,
            topUpLimits
        );

        allocations = _allocateTopUps(maxDepositAmount, operatorIds, keyIndices, cappedTopUpLimits);

        _incrementModuleNonce();
    }

    /// @inheritdoc ICuratedModule
    function changeNodeOperatorAddresses(
        uint256 nodeOperatorId,
        address newManagerAddress,
        address newRewardAddress
    ) external {
        _checkRole(OPERATOR_ADDRESSES_ADMIN_ROLE);
        NOAddresses.changeNodeOperatorAddresses({
            nodeOperators: _baseStorage().nodeOperators,
            nodeOperatorId: nodeOperatorId,
            newManagerAddress: newManagerAddress,
            newRewardAddress: newRewardAddress,
            stETH: address(STETH)
        });
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
    function getNodeOperatorWeightAndExternalStake(
        uint256 nodeOperatorId
    ) external view returns (uint256 weight, uint256 externalStake) {
        _requireDepositInfoUpToDate();
        return _metaRegistry().getNodeOperatorWeightAndExternalStake(nodeOperatorId);
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
        return CuratedDepositAllocator.getTopUpAllocationTargets(_baseStorage());
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
            $: $,
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
        allocations = CuratedDepositAllocator.allocateAndDistributeTopUps({
            $: $,
            allocationAmount: maxDepositAmount,
            operatorIds: operatorIds,
            topUpLimits: topUpLimits
        });

        StakeTracker.increaseKeyBalances($, operatorIds, keyIndices, allocations);
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
}
