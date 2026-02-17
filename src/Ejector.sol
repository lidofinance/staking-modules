// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import { AssetRecoverer } from "./abstract/AssetRecoverer.sol";
import { ExitTypes } from "./abstract/ExitTypes.sol";
import { PausableWithRoles } from "./abstract/PausableWithRoles.sol";

import { TransientUintUintMap, TransientUintUintMapLib } from "./lib/TransientUintUintMapLib.sol";

import { IEjector } from "./interfaces/IEjector.sol";
import { IBaseModule } from "./interfaces/IBaseModule.sol";
import { ITriggerableWithdrawalsGateway, ValidatorData } from "./interfaces/ITriggerableWithdrawalsGateway.sol";

contract Ejector is IEjector, ExitTypes, AccessControlEnumerable, PausableWithRoles, AssetRecoverer {
    uint256 public immutable STAKING_MODULE_ID;
    IBaseModule public immutable MODULE;
    address public immutable STRIKES;

    modifier onlyStrikes() {
        _onlyStrikes();
        _;
    }

    constructor(address module, address strikes, uint256 stakingModuleId, address admin) {
        if (module == address(0)) revert ZeroModuleAddress();
        if (strikes == address(0)) revert ZeroStrikesAddress();
        if (admin == address(0)) revert ZeroAdminAddress();

        STRIKES = strikes;
        MODULE = IBaseModule(module);
        STAKING_MODULE_ID = stakingModuleId;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IEjector
    function voluntaryEject(
        uint256 nodeOperatorId,
        uint256[] calldata keyIndices,
        address refundRecipient
    ) external payable whenResumed {
        _onlyNodeOperatorOwner(nodeOperatorId);

        if (keyIndices.length == 0) revert NothingToEject();

        // Default to sender if no refund recipient is specified
        refundRecipient = _msgSenderIfEmpty(refundRecipient);

        uint256 totalDepositedKeys = MODULE.getNodeOperator(nodeOperatorId).totalDepositedKeys;
        ValidatorData[] memory exitsData = new ValidatorData[](keyIndices.length);
        TransientUintUintMap seen = TransientUintUintMapLib.create();
        for (uint256 i = 0; i < keyIndices.length; i++) {
            uint256 keyIndex = keyIndices[i];
            // Revert in case of duplicate keys in the input array
            if (seen.get(keyIndex) != 0) revert DuplicateKeyIndex();
            seen.set(keyIndex, 1);

            // A key must be deposited to prevent ejecting unvetted keys that can intersect with
            // other modules.
            if (keyIndex >= totalDepositedKeys) revert SigningKeysInvalidOffset();
            // A key must be non-withdrawn to restrict unlimited exit requests consuming sanity
            // checker limits, although a deposited key can be requested to exit multiple times.
            // But, it will eventually be withdrawn, so potentially malicious behaviour stops when
            // there are no active keys available
            if (MODULE.isValidatorWithdrawn(nodeOperatorId, keyIndex)) revert AlreadyWithdrawn();
            bytes memory pubkey = MODULE.getSigningKeys(nodeOperatorId, keyIndex, 1);
            exitsData[i] = ValidatorData({
                stakingModuleId: STAKING_MODULE_ID,
                nodeOperatorId: nodeOperatorId,
                pubkey: pubkey
            });
            emit VoluntaryEjectionRequested({
                nodeOperatorId: nodeOperatorId,
                pubkey: pubkey,
                refundRecipient: refundRecipient
            });
        }

        // @dev This call might revert if the limits are exceeded on the protocol side.
        triggerableWithdrawalsGateway().triggerFullWithdrawals{ value: msg.value }(
            exitsData,
            refundRecipient,
            VOLUNTARY_EXIT_TYPE_ID
        );
    }

    /// @inheritdoc IEjector
    function ejectBadPerformer(
        uint256 nodeOperatorId,
        uint256 keyIndex,
        address refundRecipient
    ) external payable whenResumed onlyStrikes {
        if (refundRecipient == address(0)) revert ZeroRefundRecipient();
        // A key must be deposited to prevent ejecting unvetted keys that can intersect with
        // other modules.
        if (keyIndex >= MODULE.getNodeOperator(nodeOperatorId).totalDepositedKeys) revert SigningKeysInvalidOffset();
        // A key must be non-withdrawn to restrict unlimited exit requests consuming sanity checker
        // limits, although a deposited key can be requested to exit multiple times. But, it will
        // eventually be withdrawn, so potentially malicious behaviour stops when there are no
        // active keys available
        if (MODULE.isValidatorWithdrawn(nodeOperatorId, keyIndex)) revert AlreadyWithdrawn();

        ValidatorData[] memory exitsData = new ValidatorData[](1);
        bytes memory pubkey = MODULE.getSigningKeys(nodeOperatorId, keyIndex, 1);
        exitsData[0] = ValidatorData({
            stakingModuleId: STAKING_MODULE_ID,
            nodeOperatorId: nodeOperatorId,
            pubkey: pubkey
        });
        emit BadPerformerEjectionRequested({
            nodeOperatorId: nodeOperatorId,
            pubkey: pubkey,
            refundRecipient: refundRecipient
        });

        // @dev This call might revert if the limits are exceeded on the protocol side.
        triggerableWithdrawalsGateway().triggerFullWithdrawals{ value: msg.value }(
            exitsData,
            refundRecipient,
            STRIKES_EXIT_TYPE_ID
        );
    }

    /// @inheritdoc IEjector
    function triggerableWithdrawalsGateway() public view returns (ITriggerableWithdrawalsGateway) {
        return ITriggerableWithdrawalsGateway(MODULE.LIDO_LOCATOR().triggerableWithdrawalsGateway());
    }

    function _msgSenderIfEmpty(address input) internal view returns (address) {
        return input == address(0) ? msg.sender : input;
    }

    function _onlyStrikes() internal view {
        if (msg.sender != STRIKES) revert SenderIsNotStrikes();
    }

    /// @dev Verifies that the sender is the owner of the node operator
    function _onlyNodeOperatorOwner(uint256 nodeOperatorId) internal view {
        address owner = MODULE.getNodeOperatorOwner(nodeOperatorId);
        if (owner == address(0)) revert NodeOperatorDoesNotExist();
        if (owner != msg.sender) revert SenderIsNotEligible();
    }

    function _onlyRecoverer() internal view override {
        _checkRole(RECOVERER_ROLE);
    }

    function __checkRole(bytes32 role) internal view override {
        _checkRole(role);
    }
}
