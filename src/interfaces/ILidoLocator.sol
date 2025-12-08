// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

interface ILidoLocator {
    error ZeroAddress();

    function accountingOracle() external view returns (address);

    function burner() external view returns (address);

    function coreComponents()
        external
        view
        returns (address, address, address, address, address, address);

    function depositSecurityModule() external view returns (address);

    function elRewardsVault() external view returns (address);

    function legacyOracle() external view returns (address);

    function lido() external view returns (address);

    function oracleDaemonConfig() external view returns (address);

    function oracleReportComponentsForLido()
        external
        view
        returns (address, address, address, address, address, address, address);

    function oracleReportSanityChecker() external view returns (address);

    function postTokenRebaseReceiver() external view returns (address);

    function stakingRouter() external view returns (address payable);

    function treasury() external view returns (address);

    function validatorsExitBusOracle() external view returns (address);

    function withdrawalQueue() external view returns (address);

    function withdrawalVault() external view returns (address);

    function triggerableWithdrawalsGateway() external view returns (address);
}
