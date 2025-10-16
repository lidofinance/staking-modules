// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;
import { NodeOperatorManagementProperties, NodeOperator } from "../../../src/interfaces/ICSModule.sol";
import { ICSAccounting } from "../../../src/interfaces/ICSAccounting.sol";
import { ICSParametersRegistry } from "../../../src/interfaces/ICSParametersRegistry.sol";
import { ILidoLocator } from "../../../src/interfaces/ILidoLocator.sol";
import { CSParametersRegistryMock } from "./CSParametersRegistryMock.sol";
import { CSAccountingMock } from "./CSAccountingMock.sol";
import { WstETHMock } from "./WstETHMock.sol";
import { LidoMock } from "./LidoMock.sol";
import { Utilities } from "../Utilities.sol";
import { LidoLocatorMock } from "./LidoLocatorMock.sol";
import { Fixtures } from "../Fixtures.sol";

contract CSMMock is Utilities, Fixtures {
    NodeOperator internal mockNodeOperator;
    uint256 internal nodeOperatorsCount;
    uint256 internal nodeOperatorTotalDepositedKeys;
    bool internal isValidatorWithdrawnMock;
    ICSAccounting public immutable ACCOUNTING;
    ICSParametersRegistry public immutable PARAMETERS_REGISTRY;
    LidoLocatorMock public immutable LIDO_LOCATOR;
    NodeOperatorManagementProperties internal managementProperties;

    constructor() {
        PARAMETERS_REGISTRY = ICSParametersRegistry(
            address(new CSParametersRegistryMock())
        );
        WstETHMock wstETH;
        LidoMock lido;
        (LIDO_LOCATOR, wstETH, lido, , ) = initLido();
        ACCOUNTING = ICSAccounting(
            address(
                new CSAccountingMock(
                    2 ether,
                    address(wstETH),
                    address(lido),
                    address(1337)
                )
            )
        );
    }

    function accounting() external view returns (ICSAccounting) {
        return ACCOUNTING;
    }

    function mock_setNodeOperator(NodeOperator memory no) external {
        mockNodeOperator = no;
    }

    function getNodeOperator(
        uint256 /* nodeOperatorId */
    ) external view returns (NodeOperator memory) {
        return mockNodeOperator;
    }

    function mock_setNodeOperatorManagementProperties(
        NodeOperatorManagementProperties memory _managementProperties
    ) external {
        managementProperties = _managementProperties;
    }

    function getNodeOperatorManagementProperties(
        uint256 /* nodeOperatorId */
    ) external view returns (NodeOperatorManagementProperties memory) {
        return managementProperties;
    }

    function getNodeOperatorOwner(
        uint256 /* nodeOperatorId */
    ) external view returns (address) {
        return
            managementProperties.extendedManagerPermissions
                ? managementProperties.managerAddress
                : managementProperties.rewardAddress;
    }

    function mock_setIsValidatorWithdrawn(bool value) external {
        isValidatorWithdrawnMock = value;
    }

    function isValidatorWithdrawn(
        uint256,
        uint256
    ) external view returns (bool) {
        return isValidatorWithdrawnMock;
    }

    function mock_setNodeOperatorsCount(uint256 count) external {
        nodeOperatorsCount = count;
    }

    function getNodeOperatorsCount() external view returns (uint256) {
        return nodeOperatorsCount;
    }

    function mock_setNodeOperatorTotalDepositedKeys(uint256 count) external {
        nodeOperatorTotalDepositedKeys = count;
    }

    function getNodeOperatorTotalDepositedKeys(
        uint256
    ) external view returns (uint256) {
        return nodeOperatorTotalDepositedKeys;
    }

    function createNodeOperator(
        address /* from */,
        NodeOperatorManagementProperties memory /* managementProperties */,
        address /* referrer */
    ) external pure returns (uint256) {
        return 0;
    }

    function addValidatorKeysETH(
        address from,
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes memory publicKeys,
        bytes memory signatures
    ) external payable {}

    function addValidatorKeysStETH(
        address from,
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes memory publicKeys,
        bytes memory signatures,
        ICSAccounting.PermitInput memory permit
    ) external {}

    function addValidatorKeysWstETH(
        address from,
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes memory publicKeys,
        bytes memory signatures,
        ICSAccounting.PermitInput memory permit
    ) external {}

    function getSigningKeys(
        uint256 /* nodeOperatorId */,
        uint256 startIndex,
        uint256 keysCount
    ) external pure returns (bytes memory pubkeys) {
        (pubkeys, ) = keysSignatures(keysCount, startIndex);
    }

    function exitDeadlineThreshold(
        uint256 /* nodeOperatorId */
    ) external view returns (uint256) {
        return PARAMETERS_REGISTRY.getAllowedExitDelay(0);
    }
}
