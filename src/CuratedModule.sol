// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IStakingModule, IStakingModuleV2 } from "./interfaces/IStakingModule.sol";
import { NodeOperator } from "./interfaces/IBaseModule.sol";

import { BaseModule } from "./abstract/BaseModule.sol";

import { NOAddresses } from "./lib/NOAddresses.sol";
import { PackedPubkeys } from "./lib/PackedPubkeys.sol";
import { SigningKeys } from "./lib/SigningKeys.sol";
import { CuratedDepositAllocator } from "./lib/allocator/CuratedDepositAllocator.sol";

contract CuratedModule is ICuratedModule, BaseModule {
    using PackedPubkeys for bytes;

    /// @custom:storage-location erc7201:CuratedModule
    struct CuratedModuleStorage {
        // Tracks per-operator balances (in wei) reported by the Accounting oracle.
        mapping(uint256 => uint256) operatorBalances;
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
    {
        _disableInitializers();
    }

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
    )
        external
        override(IStakingModule)
        onlyRole(STAKING_ROUTER_ROLE)
        returns (bytes memory publicKeys, bytes memory signatures)
    {
        if (depositsCount == 0) {
            return (new bytes(0), new bytes(0));
        }

        (
            uint256 allocated,
            uint256[] memory operatorIds,
            uint256[] memory allocations
        ) = CuratedDepositAllocator.allocateDeposits(
                _nodeOperators,
                _nodeOperatorsCount,
                depositsCount
            );
        if (allocated == 0) {
            revert NotEnoughKeys();
        }

        (publicKeys, signatures) = SigningKeys.initKeysSigsBuf(allocated);

        uint256 loadedKeysCount;
        uint256 allocationsCount = allocations.length;
        for (uint256 i; i < allocationsCount; ++i) {
            uint256 allocation = allocations[i];
            uint256 operatorId = operatorIds[i];
            NodeOperator storage no = _nodeOperators[operatorId];

            // solhint-disable-next-line func-named-parameters
            SigningKeys.loadKeysSigs(
                operatorId,
                no.totalDepositedKeys,
                allocation,
                publicKeys,
                signatures,
                loadedKeysCount
            );

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
        }
        if (loadedKeysCount != allocated) {
            revert NotEnoughKeys();
        }

        unchecked {
            _depositableValidatorsCount -= uint64(allocated);
            _totalDepositedValidators += uint64(allocated);
        }

        _incrementModuleNonce();
    }

    /// @inheritdoc IStakingModuleV2
    function obtainDepositData(
        uint256 depositAmount,
        bytes calldata packedPubkeys,
        uint256[] calldata keyIndices,
        uint256[] calldata operatorIds,
        uint256[] calldata topUpLimits
    )
        external
        override(IStakingModuleV2)
        onlyRole(STAKING_ROUTER_ROLE)
        returns (bytes[] memory publicKeys, uint256[] memory allocations)
    {
        if (depositAmount == 0) {
            return (new bytes[](0), new uint256[](0));
        }

        if (
            operatorIds.length != keyIndices.length ||
            operatorIds.length != topUpLimits.length ||
            packedPubkeys.count() != operatorIds.length
        ) {
            revert InvalidInput();
        }

        publicKeys = new bytes[](operatorIds.length);

        _loadTopUpPublicKeys({
            packedPubkeys: packedPubkeys,
            keyIndices: keyIndices,
            operatorIds: operatorIds,
            publicKeys: publicKeys
        });
        allocations = _allocateTopUps(depositAmount, operatorIds, topUpLimits);

        _incrementModuleNonce();
    }

    /// @inheritdoc IStakingModuleV2
    function updateOperatorBalances(
        uint256[] calldata operatorIds,
        uint256[] calldata validatorsBalancesGwei,
        uint256[] calldata pendingBalancesGwei,
        uint256 /* refSlot */
    ) external override(IStakingModuleV2) onlyRole(STAKING_ROUTER_ROLE) {
        uint256 operatorsCount = operatorIds.length;
        if (
            validatorsBalancesGwei.length != operatorsCount ||
            pendingBalancesGwei.length != operatorsCount
        ) {
            revert InvalidInput();
        }

        CuratedModuleStorage storage $ = _storage();

        for (uint256 i; i < operatorsCount; ++i) {
            uint256 operatorId = operatorIds[i];
            if (operatorId >= _nodeOperatorsCount) {
                revert NodeOperatorDoesNotExist();
            }

            uint256 totalGwei = validatorsBalancesGwei[i] +
                pendingBalancesGwei[i];
            $.operatorBalances[operatorId] = totalGwei * 1 gwei;
        }
        _incrementModuleNonce();
    }

    /// @inheritdoc IStakingModule
    /// @dev Changing the WC means that the current deposit data in the queue is not valid anymore and can't be deposited.
    ///      If there are depositable validators in the queue, the method should revert to prevent deposits with invalid
    ///      withdrawal credentials.
    function onWithdrawalCredentialsChanged()
        external
        onlyRole(STAKING_ROUTER_ROLE)
    {
        revert NotImplemented();
    }

    /// @inheritdoc ICuratedModule
    function changeNodeOperatorAddresses(
        uint256 nodeOperatorId,
        address newManagerAddress,
        address newRewardAddress
    ) external onlyRole(OPERATOR_ADDRESSES_ADMIN_ROLE) {
        NOAddresses.changeNodeOperatorAddresses(
            _nodeOperators,
            nodeOperatorId,
            newManagerAddress,
            newRewardAddress
        );
    }

    /// @inheritdoc ICuratedModule
    function getNodeOperatorBalances(
        uint256 operatorId
    ) external view returns (uint256) {
        return _storage().operatorBalances[operatorId];
    }

    /// @inheritdoc ICuratedModule
    function getDepositsAllocation(
        uint256 /* depositAmount */
    )
        external
        view
        returns (
            uint256 allocated,
            uint256[] memory operatorIds,
            uint256[] memory allocations
        )
    {
        revert NotImplemented();
    }

    /// @inheritdoc ICuratedModule
    function getTopUpAllocations(
        uint256 depositAmount
    )
        external
        view
        returns (uint256[] memory operatorIds, uint256[] memory allocations)
    {
        uint256 operatorsCount = _nodeOperatorsCount;
        if (depositAmount == 0 || operatorsCount == 0) {
            return (new uint256[](0), new uint256[](0));
        }

        uint256[] memory allOperatorIds = new uint256[](operatorsCount);
        for (uint256 i; i < operatorsCount; ++i) {
            allOperatorIds[i] = i;
        }

        return
            CuratedDepositAllocator.allocateTopUps({
                nodeOperators: _nodeOperators,
                nodeOperatorBalances: _storage().operatorBalances,
                operatorsCount: operatorsCount,
                depositAmount: depositAmount,
                operatorIds: allOperatorIds
            });
    }

    function _onOperatorDepositableChange(
        uint256 /* nodeOperatorId */
    ) internal override {
        // Not used in curated module yet.
    }

    function _loadTopUpPublicKeys(
        bytes calldata packedPubkeys,
        uint256[] calldata keyIndices,
        uint256[] calldata operatorIds,
        bytes[] memory publicKeys
    ) internal view {
        uint256 n = operatorIds.length;
        for (uint256 i; i < n; ++i) {
            uint256 operatorId = operatorIds[i];
            uint256 keyIndex = keyIndices[i];
            NodeOperator storage no = _nodeOperators[operatorId];
            if (keyIndex >= no.totalDepositedKeys) {
                revert SigningKeysInvalidOffset();
            }

            if (_isValidatorWithdrawn[_keyPointer(operatorId, keyIndex)]) {
                revert PublicKeyIsWithdrawn();
            }

            bytes memory pubkey = packedPubkeys.at(i);
            publicKeys[i] = pubkey;
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
        uint256[] calldata topUpLimits
    ) internal view returns (uint256[] memory allocations) {
        uint256[] memory uniqueOperatorIds = _uniqueOperatorIds(
            operatorIds,
            _nodeOperatorsCount
        );
        (
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
    }

    /// @dev Deduplicate operator ids for allocation to avoid overweighting by repeated keys.
    function _uniqueOperatorIds(
        uint256[] calldata operatorIds,
        uint256 operatorsCount
    ) internal pure returns (uint256[] memory uniqueOperatorIds) {
        uint256 n = operatorIds.length;
        uniqueOperatorIds = new uint256[](n);
        uint8[] memory seen = new uint8[](operatorsCount);
        uint256 count;
        for (uint256 i; i < n; ++i) {
            uint256 operatorId = operatorIds[i];
            if (seen[operatorId] != 0) continue;
            seen[operatorId] = 1;
            uniqueOperatorIds[count] = operatorId;
            ++count;
        }

        if (count != n) {
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
    ) internal pure returns (uint256[] memory allocations) {
        // topUpLimits are per-key and aligned with operatorIds/keyIndices order.
        allocations = new uint256[](operatorIds.length);
        uint256[] memory perOperatorAllocations = new uint256[](operatorsCount);
        for (uint256 i; i < allocatedOperatorIds.length; ++i) {
            perOperatorAllocations[
                allocatedOperatorIds[i]
            ] = operatorAllocations[i];
        }

        uint256 n = operatorIds.length;
        unchecked {
            for (uint256 i; i < n; ++i) {
                uint256 operatorId = operatorIds[i];
                uint256 remaining = perOperatorAllocations[operatorId];
                if (remaining == 0) continue;

                uint256 limit = topUpLimits[i] * 1 gwei;
                if (limit == 0) continue;

                uint256 amount = remaining < limit ? remaining : limit;
                allocations[i] = amount;
                perOperatorAllocations[operatorId] = remaining - amount;
            }
        }
    }

    function _storage() internal pure returns (CuratedModuleStorage storage $) {
        assembly ("memory-safe") {
            $.slot := CURATED_MODULE_STORAGE_LOCATION
        }
    }

    /// @inheritdoc IStakingModule
    function getStakingModuleSummary()
        external
        view
        returns (
            uint256 totalExitedValidators,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        )
    {
        totalExitedValidators = _totalExitedValidators;
        totalDepositedValidators = _totalDepositedValidators;
        depositableValidatorsCount = _depositableValidatorsCount;
    }
}
