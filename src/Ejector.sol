// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import { AssetRecoverer } from "./abstract/AssetRecoverer.sol";
import { ExitTypes } from "./abstract/ExitTypes.sol";

import { PausableUntil } from "./lib/utils/PausableUntil.sol";
import { SigningKeys } from "./lib/SigningKeys.sol";

import { IEjector } from "./interfaces/IEjector.sol";
import { ICSModule } from "./interfaces/ICSModule.sol";
import { ITriggerableWithdrawalsGateway, ValidatorData } from "./interfaces/ITriggerableWithdrawalsGateway.sol";

contract Ejector is
    IEjector,
    ExitTypes,
    AccessControlEnumerable,
    PausableUntil,
    AssetRecoverer
{
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE");
    bytes32 public constant RECOVERER_ROLE = keccak256("RECOVERER_ROLE");

    uint256 public immutable STAKING_MODULE_ID;
    ICSModule public immutable MODULE;
    address public immutable STRIKES;

    modifier onlyStrikes() {
        _onlyStrikes();
        _;
    }

    constructor(
        address module,
        address strikes,
        uint256 stakingModuleId,
        address admin
    ) {
        if (module == address(0)) {
            revert ZeroModuleAddress();
        }
        if (strikes == address(0)) {
            revert ZeroStrikesAddress();
        }
        if (admin == address(0)) {
            revert ZeroAdminAddress();
        }

        STRIKES = strikes;
        MODULE = ICSModule(module);
        STAKING_MODULE_ID = stakingModuleId;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IEjector
    function resume() external onlyRole(RESUME_ROLE) {
        _resume();
    }

    /// @inheritdoc IEjector
    function pauseFor(uint256 duration) external onlyRole(PAUSE_ROLE) {
        _pauseFor(duration);
    }

    /// @inheritdoc IEjector
    function voluntaryEject(
        uint256 nodeOperatorId,
        uint256 startFrom,
        uint256 keysCount,
        address refundRecipient
    ) external payable whenResumed {
        _onlyNodeOperatorOwner(nodeOperatorId);

        if (keysCount == 0) {
            revert NothingToEject();
        }

        {
            // A key must be deposited to prevent ejecting unvetted keys that can intersect with
            // other modules.
            uint256 maxKeyIndex = startFrom + keysCount;
            if (
                maxKeyIndex >
                MODULE.getNodeOperatorTotalDepositedKeys(nodeOperatorId)
            ) {
                revert SigningKeysInvalidOffset();
            }
            // A key must be non-withdrawn to restrict unlimited exit requests consuming sanity
            // checker limits, although a deposited key can be requested to exit multiple times.
            // But, it will eventually be withdrawn, so potentially malicious behaviour stops when
            // there are no active keys available
            for (uint256 i = startFrom; i < maxKeyIndex; ++i) {
                if (MODULE.isValidatorWithdrawn(nodeOperatorId, i)) {
                    revert AlreadyWithdrawn();
                }
            }
        }

        bytes memory pubkeys = MODULE.getSigningKeys(
            nodeOperatorId,
            startFrom,
            keysCount
        );
        ValidatorData[] memory exitsData = new ValidatorData[](keysCount);
        for (uint256 i; i < keysCount; ++i) {
            bytes memory pubkey = new bytes(SigningKeys.PUBKEY_LENGTH);
            assembly {
                let keyLen := mload(pubkey) // PUBKEY_LENGTH
                let offset := mul(keyLen, i) // PUBKEY_LENGTH * i
                let keyPos := add(add(pubkeys, 0x20), offset) // pubkeys[offset]
                mcopy(add(pubkey, 0x20), keyPos, keyLen) // pubkey = pubkeys[offset:offset+PUBKEY_LENGTH]
            }
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
        triggerableWithdrawalsGateway().triggerFullWithdrawals{
            value: msg.value
        }(
            exitsData,
            refundRecipient == address(0) ? msg.sender : refundRecipient,
            VOLUNTARY_EXIT_TYPE_ID
        );
    }

    /// @dev Additional method for non-sequential keys to save gas and decrease fee amount compared
    /// to separate transactions.
    /// @inheritdoc IEjector
    function voluntaryEjectByArray(
        uint256 nodeOperatorId,
        uint256[] calldata keyIndices,
        address refundRecipient
    ) external payable whenResumed {
        _onlyNodeOperatorOwner(nodeOperatorId);

        if (keyIndices.length == 0) {
            revert NothingToEject();
        }

        uint256 totalDepositedKeys = MODULE.getNodeOperatorTotalDepositedKeys(
            nodeOperatorId
        );
        ValidatorData[] memory exitsData = new ValidatorData[](
            keyIndices.length
        );
        for (uint256 i = 0; i < keyIndices.length; i++) {
            // A key must be deposited to prevent ejecting unvetted keys that can intersect with
            // other modules.
            if (keyIndices[i] >= totalDepositedKeys) {
                revert SigningKeysInvalidOffset();
            }
            // A key must be non-withdrawn to restrict unlimited exit requests consuming sanity
            // checker limits, although a deposited key can be requested to exit multiple times.
            // But, it will eventually be withdrawn, so potentially malicious behaviour stops when
            // there are no active keys available
            if (MODULE.isValidatorWithdrawn(nodeOperatorId, keyIndices[i])) {
                revert AlreadyWithdrawn();
            }
            bytes memory pubkey = MODULE.getSigningKeys(
                nodeOperatorId,
                keyIndices[i],
                1
            );
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
        triggerableWithdrawalsGateway().triggerFullWithdrawals{
            value: msg.value
        }(
            exitsData,
            refundRecipient == address(0) ? msg.sender : refundRecipient,
            VOLUNTARY_EXIT_TYPE_ID
        );
    }

    /// @inheritdoc IEjector
    function ejectBadPerformer(
        uint256 nodeOperatorId,
        uint256 keyIndex,
        address refundRecipient
    ) external payable whenResumed onlyStrikes {
        // A key must be deposited to prevent ejecting unvetted keys that can intersect with
        // other modules.
        if (
            keyIndex >= MODULE.getNodeOperatorTotalDepositedKeys(nodeOperatorId)
        ) {
            revert SigningKeysInvalidOffset();
        }
        // A key must be non-withdrawn to restrict unlimited exit requests consuming sanity checker
        // limits, although a deposited key can be requested to exit multiple times. But, it will
        // eventually be withdrawn, so potentially malicious behaviour stops when there are no
        // active keys available
        if (MODULE.isValidatorWithdrawn(nodeOperatorId, keyIndex)) {
            revert AlreadyWithdrawn();
        }

        ValidatorData[] memory exitsData = new ValidatorData[](1);
        bytes memory pubkey = MODULE.getSigningKeys(
            nodeOperatorId,
            keyIndex,
            1
        );
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
        triggerableWithdrawalsGateway().triggerFullWithdrawals{
            value: msg.value
        }(exitsData, refundRecipient, STRIKES_EXIT_TYPE_ID);
    }

    /// @inheritdoc IEjector
    function triggerableWithdrawalsGateway()
        public
        view
        returns (ITriggerableWithdrawalsGateway)
    {
        return
            ITriggerableWithdrawalsGateway(
                MODULE.LIDO_LOCATOR().triggerableWithdrawalsGateway()
            );
    }

    function _onlyStrikes() internal view {
        if (msg.sender != STRIKES) {
            revert SenderIsNotStrikes();
        }
    }

    /// @dev Verifies that the sender is the owner of the node operator
    function _onlyNodeOperatorOwner(uint256 nodeOperatorId) internal view {
        address owner = MODULE.getNodeOperatorOwner(nodeOperatorId);
        if (owner == address(0)) {
            revert NodeOperatorDoesNotExist();
        }
        if (owner != msg.sender) {
            revert SenderIsNotEligible();
        }
    }

    function _onlyRecoverer() internal view override {
        _checkRole(RECOVERER_ROLE);
    }
}
