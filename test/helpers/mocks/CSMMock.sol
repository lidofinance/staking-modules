// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;
import { NodeOperatorManagementProperties, NodeOperator } from "../../../src/interfaces/IBaseModule.sol";
import { IAccounting } from "../../../src/interfaces/IAccounting.sol";
import { IParametersRegistry } from "../../../src/interfaces/IParametersRegistry.sol";
import { ParametersRegistryMock } from "./ParametersRegistryMock.sol";
import { AccountingMock } from "./AccountingMock.sol";
import { WstETHMock } from "./WstETHMock.sol";
import { LidoMock } from "./LidoMock.sol";
import { Utilities } from "../Utilities.sol";
import { LidoLocatorMock } from "./LidoLocatorMock.sol";
import { Fixtures } from "../Fixtures.sol";
import { INodeOperatorOwner } from "../../../src/interfaces/INodeOperatorOwner.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract CSMMock is Utilities, Fixtures {
    NodeOperator internal mockNodeOperator;
    uint256 internal nodeOperatorsCount;
    uint256 internal nodeOperatorTotalDepositedKeys;
    mapping(uint256 => mapping(uint256 => bool))
        internal isValidatorWithdrawnByKey;
    IAccounting public immutable ACCOUNTING;
    IParametersRegistry public immutable PARAMETERS_REGISTRY;
    LidoLocatorMock public immutable LIDO_LOCATOR;
    NodeOperatorManagementProperties internal managementProperties;

    constructor() {
        PARAMETERS_REGISTRY = IParametersRegistry(
            address(new ParametersRegistryMock())
        );
        WstETHMock wstETH;
        LidoMock lido;
        (LIDO_LOCATOR, wstETH, lido, , ) = initLido();
        ACCOUNTING = IAccounting(
            address(
                new AccountingMock(
                    2 ether,
                    address(wstETH),
                    address(lido),
                    address(1337)
                )
            )
        );
    }

    function accounting() external view returns (IAccounting) {
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
        uint256 nodeOperatorId
    ) external view returns (address) {
        if (nodeOperatorId != 0) {
            return address(0);
        }
        return
            managementProperties.extendedManagerPermissions
                ? managementProperties.managerAddress
                : managementProperties.rewardAddress;
    }

    function mock_setIsValidatorWithdrawn(
        uint256 nodeOperatorId,
        uint256 keyIndex,
        bool value
    ) external {
        isValidatorWithdrawnByKey[nodeOperatorId][keyIndex] = value;
    }

    function isValidatorWithdrawn(
        uint256 nodeOperatorId,
        uint256 keyIndex
    ) external view returns (bool) {
        return isValidatorWithdrawnByKey[nodeOperatorId][keyIndex];
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
        IAccounting.PermitInput memory permit
    ) external {}

    function addValidatorKeysWstETH(
        address from,
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes memory publicKeys,
        bytes memory signatures,
        IAccounting.PermitInput memory permit
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

    function supportsInterface(
        bytes4 interfaceId
    ) external pure returns (bool) {
        return
            interfaceId == type(INodeOperatorOwner).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}

contract NodeOperatorOwnerNo165Mock {
    address internal _owner;

    constructor(address owner) {
        _owner = owner;
    }

    function setOwner(address owner) external {
        _owner = owner;
    }

    function getNodeOperatorOwner(
        uint256 nodeOperatorId
    ) external view returns (address) {
        if (nodeOperatorId != 0) {
            return address(0);
        }
        return _owner;
    }
}
