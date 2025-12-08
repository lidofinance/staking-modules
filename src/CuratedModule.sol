// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IStakingModule, IStakingModuleV2 } from "./interfaces/IStakingModule.sol";

import { BaseModule } from "./abstract/BaseModule.sol";

import { NOAddresses } from "./lib/NOAddresses.sol";

contract CuratedModule is ICuratedModule, BaseModule {
    bytes32 public constant OPERATOR_ADDRESSES_ADMIN_ROLE =
        keccak256("OPERATOR_ADDRESSES_ADMIN_ROLE");

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

    /// @inheritdoc IStakingModule
    function obtainDepositData(
        uint256 /* depositsCount */,
        bytes calldata /* depositCalldata */
    )
        external
        virtual
        returns (bytes memory publicKeys, bytes memory signatures)
    {
        revert NotImplemented();
    }

    /// @inheritdoc IStakingModuleV2
    function obtainDepositData(
        uint256,
        /* depositAmount */
        bytes calldata,
        /* packedPubkeys */
        uint256[] calldata,
        /* keyIndices */
        uint256[] calldata,
        /* operatorIds */
        uint256[] calldata /* topUpLimitsGwei */
    )
        external
        returns (bytes[] memory publicKeys, uint256[] memory allocations)
    {
        revert NotImplemented();
    }

    /// @inheritdoc IStakingModuleV2
    function updateOperatorBalances(
        bytes calldata,
        /* operatorIds */
        bytes calldata,
        /* balances */
        uint256 /* refSlot */
    ) external {
        revert NotImplemented();
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

    // TODO: Implement. It does not revert currently for tests.
    function _onOperatorDepositableChange(
        uint256 /* nodeOperatorId */
    ) internal override {
        //
    }
}
