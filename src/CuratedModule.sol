// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IStakingModule, IStakingModuleV2 } from "./interfaces/IStakingModule.sol";
import { NodeOperator } from "./interfaces/IBaseModule.sol";

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
    }

    bytes32 public constant OPERATOR_ADDRESSES_ADMIN_ROLE =
        keccak256("OPERATOR_ADDRESSES_ADMIN_ROLE");

    uint64 internal constant INITIALIZED_VERSION = 1;
    // keccak256(abi.encode(uint256(keccak256("CuratedModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CURATED_MODULE_STORAGE_LOCATION =
        0x748416948424a2a643c796b7b8213bcf41155fd3a072f0851ad0a3d6ca632500;

    constructor(
        bytes32 moduleType,
        address lidoLocator,
        address parametersRegistry,
        address accounting,
        address exitPenalties
    )
        BaseModule(
            moduleType,
            lidoLocator,
            parametersRegistry,
            accounting,
            exitPenalties
        )
    {}

    /// @notice Initialize the module from scratch
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
        (
            uint256 allocated,
            uint256[] memory operatorIds,
            uint256[] memory allocations
        ) = CuratedDepositAllocator.allocateDeposits(
                _nodeOperators,
                _nodeOperatorsCount,
                depositsCount
            );
        (publicKeys, signatures) = SigningKeys.initKeysSigsBuf(allocated);
        if (allocated == 0) {
            return (publicKeys, signatures);
        }

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

    // Start next review from here

    /// @inheritdoc IStakingModuleV2
    function allocateDeposits(
        uint256 maxDepositAmount,
        bytes[] calldata pubkeys,
        uint256[] calldata keyIndices,
        uint256[] calldata operatorIds,
        uint256[] calldata topUpLimits
    ) external returns (uint256[] memory allocations) {
        _checkStakingRouterRole();
        if (maxDepositAmount == 0) {
            return new uint256[](0);
        }

        if (
            operatorIds.length != keyIndices.length ||
            operatorIds.length != topUpLimits.length ||
            pubkeys.length != operatorIds.length
        ) {
            revert InvalidInput();
        }
        // @dev StakingRouter is expected to provide per-key top-up limits capped
        // by MAX_EFFECTIVE_BALANCE and to avoid duplicate (operatorId, keyIndex)
        // entries in a single request.

        _validateTopUpPublicKeys({
            pubkeys: pubkeys,
            keyIndices: keyIndices,
            operatorIds: operatorIds
        });
        allocations = _allocateTopUps(
            maxDepositAmount,
            operatorIds,
            keyIndices,
            topUpLimits
        );

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
            validatorsBalancesGwei.length != operatorsCount ||
            pendingBalancesGwei.length != operatorsCount
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

            uint256 balanceWei = (validatorsBalancesGwei[i] +
                pendingBalancesGwei[i]) * 1 gwei;
            _setOperatorBalance($, operatorId, balanceWei);
        }
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
            _nodeOperators,
            nodeOperatorId,
            newManagerAddress,
            newRewardAddress
        );
    }

    /// @inheritdoc ICuratedModule
    function getNodeOperatorBalance(
        uint256 operatorId
    ) external view returns (uint256) {
        return _storage().operatorBalances[operatorId];
    }

    /// @inheritdoc ICuratedModule
    function getDepositsAllocation(
        uint256 depositAmount
    )
        external
        view
        returns (
            uint256 allocated,
            uint256[] memory operatorIds,
            uint256[] memory allocations
        )
    {
        uint256 operatorsCount = _nodeOperatorsCount;
        if (depositAmount == 0 || operatorsCount == 0) {
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
                depositAmount: depositAmount,
                operatorIds: allOperatorIds
            });
    }

    function _applyDepositableValidatorsCount(
        NodeOperator storage no,
        uint256 nodeOperatorId,
        uint256 newCount,
        bool incrementNonceIfUpdated
    ) internal override {
        if (newCount > 0) {
            if (
                PARAMETERS_REGISTRY.getDepositAllocationWeight(
                    _getBondCurveId(nodeOperatorId)
                ) == 0
            ) {
                newCount = 0;
            }
        }
        super._applyDepositableValidatorsCount(
            no,
            nodeOperatorId,
            newCount,
            incrementNonceIfUpdated
        );
    }

    function _validateTopUpPublicKeys(
        bytes[] calldata pubkeys,
        uint256[] calldata keyIndices,
        uint256[] calldata operatorIds
    ) internal view {
        for (uint256 i; i < operatorIds.length; ++i) {
            if (pubkeys[i].length != SigningKeys.PUBKEY_LENGTH) {
                revert InvalidInput();
            }
            uint256 operatorId = operatorIds[i];
            uint256 keyIndex = keyIndices[i];
            NodeOperator storage no = _nodeOperators[operatorId];
            if (keyIndex >= no.totalDepositedKeys) {
                revert SigningKeysInvalidOffset();
            }

            uint256 pointer = _keyPointer(operatorId, keyIndex);
            if (_isValidatorWithdrawn[pointer]) {
                revert PublicKeyIsWithdrawn();
            }
            if (_isValidatorSlashed[pointer]) {
                revert PublicKeyIsSlashed();
            }

            bytes memory pubkey = pubkeys[i];
            if (
                keccak256(pubkey) !=
                keccak256(SigningKeys.loadKeys(operatorId, keyIndex, 1))
            ) {
                revert PubkeyMismatch();
            }
        }
    }

    function _allocateTopUps(
        uint256 depositAmount,
        uint256[] calldata operatorIds,
        uint256[] calldata keyIndices,
        uint256[] calldata topUpLimits
    ) internal returns (uint256[] memory allocations) {
        uint256[] memory uniqueOperatorIds = _uniqueOperatorIds(
            operatorIds,
            _nodeOperatorsCount
        );
        (
            ,
            uint256[] memory allocatedOperatorIds,
            uint256[] memory operatorAllocations
        ) = CuratedDepositAllocator.allocateTopUps({
                nodeOperators: _nodeOperators,
                nodeOperatorBalances: _storage().operatorBalances,
                operatorsCount: _nodeOperatorsCount,
                depositAmount: depositAmount,
                operatorIds: uniqueOperatorIds
            });

        allocations = _distributeTopUpAllocations({
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
            operatorIds: operatorIds,
            allocations: allocations,
            uniqueOperatorIds: uniqueOperatorIds,
            operatorsCount: _nodeOperatorsCount
        });
    }

    /// @dev Deduplicate operator ids for allocation to avoid overweighting by repeated keys.
    function _uniqueOperatorIds(
        uint256[] calldata operatorIds,
        uint256 operatorsCount
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
            assembly {
                mstore(uniqueOperatorIds, count)
            }
        }
    }

    /// @dev Distribute per-operator allocations to per-key allocations with per-key limits.
    function _distributeTopUpAllocations(
        uint256[] calldata operatorIds,
        uint256[] calldata topUpLimits,
        uint256[] memory allocatedOperatorIds,
        uint256[] memory operatorAllocations,
        uint256 operatorsCount
    ) internal returns (uint256[] memory allocations) {
        // topUpLimits are per-key and aligned with operatorIds/keyIndices order.
        allocations = new uint256[](operatorIds.length);
        // NOTE: Use a full operatorsCount-sized array for O(1) lookups; operator counts are small enough
        // that a compact map would add overhead and can be worse overall.
        uint256[] memory perOperatorAllocations = new uint256[](operatorsCount);
        for (uint256 i; i < allocatedOperatorIds.length; ++i) {
            perOperatorAllocations[
                allocatedOperatorIds[i]
            ] = operatorAllocations[i];
        }

        unchecked {
            for (uint256 i; i < operatorIds.length; ++i) {
                uint256 operatorId = operatorIds[i];
                uint256 remaining = perOperatorAllocations[operatorId];
                if (remaining == 0) continue;

                uint256 limit = topUpLimits[i];
                if (limit == 0) continue;

                uint256 amount = remaining < limit ? remaining : limit;
                allocations[i] = amount;
                perOperatorAllocations[operatorId] = remaining - amount;
            }
        }
    }

    function _increaseOperatorBalancesByAllocations(
        uint256[] calldata operatorIds,
        uint256[] memory allocations,
        uint256[] memory uniqueOperatorIds,
        uint256 operatorsCount
    ) internal {
        CuratedModuleStorage storage $ = _storage();
        uint256[] memory perOperatorIncrements = new uint256[](operatorsCount);
        for (uint256 i; i < operatorIds.length; ++i) {
            uint256 allocationWei = allocations[i];
            if (allocationWei == 0) continue;
            perOperatorIncrements[operatorIds[i]] += allocationWei;
        }
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

    function _storage() internal pure returns (CuratedModuleStorage storage $) {
        assembly ("memory-safe") {
            $.slot := CURATED_MODULE_STORAGE_LOCATION
        }
    }
}
