// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { StorageSlot } from "@openzeppelin/contracts/utils/StorageSlot.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/// @notice An ossifiable proxy contract. Extends the ERC1967Proxy contract by
///     adding admin functionality
contract OssifiableProxy is ERC1967Proxy {
    event ProxyOssified();

    error NotAdmin();
    error ProxyIsOssified();

    /// @dev Validates that proxy is not ossified and that method is called by the admin
    ///     of the proxy
    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    /// @dev Initializes the upgradeable proxy with the initial implementation and admin
    /// @param implementation_ Address of the implementation
    /// @param admin_ Address of the admin of the proxy
    /// @param data_ Data used in a delegate call to implementation. The delegate call will be
    ///     skipped if the data is empty bytes
    constructor(
        address implementation_,
        address admin_,
        bytes memory data_
    ) ERC1967Proxy(implementation_, data_) {
        ERC1967Utils.changeAdmin(admin_);
    }

    /// @notice Fallback function that delegates calls to the address returned by `_implementation()`.
    // Will run if call data is empty.
    // The only use of this function is to suppress the solidity warning "This contract has a payable fallback function, but no receive ether function"
    // See https://forum.openzeppelin.com/t/proxy-sol-fallback/36951/7 for details
    // Previously it was implemented in the Proxy contract, but it was removed in the OZ 5.0
    receive() external payable virtual {
        _fallback();
    }

    /// @notice Allows to transfer admin rights to zero address and prevent future
    ///     upgrades of the proxy
    // solhint-disable-next-line func-name-mixedcase
    function proxy__ossify() external onlyAdmin {
        address prevAdmin = ERC1967Utils.getAdmin();
        StorageSlot.getAddressSlot(ERC1967Utils.ADMIN_SLOT).value = address(0);
        emit ERC1967Utils.AdminChanged(prevAdmin, address(0));
        emit ProxyOssified();
    }

    /// @notice Changes the admin of the proxy
    /// @param newAdmin_ Address of the new admin
    // solhint-disable-next-line func-name-mixedcase
    function proxy__changeAdmin(address newAdmin_) external onlyAdmin {
        ERC1967Utils.changeAdmin(newAdmin_);
    }

    /// @notice Upgrades the implementation of the proxy
    /// @param newImplementation_ Address of the new implementation
    // solhint-disable-next-line func-name-mixedcase
    function proxy__upgradeTo(address newImplementation_) external onlyAdmin {
        ERC1967Utils.upgradeToAndCall(newImplementation_, bytes(""));
    }

    /// @notice Upgrades the proxy to a new implementation, optionally performing an additional
    ///     setup call.
    /// @param newImplementation_ Address of the new implementation
    /// @param setupCalldata_ Data for the setup call. The call is skipped if setupCalldata_ is empty
    // solhint-disable-next-line func-name-mixedcase
    function proxy__upgradeToAndCall(
        address newImplementation_,
        bytes calldata setupCalldata_
    ) external onlyAdmin {
        ERC1967Utils.upgradeToAndCall(newImplementation_, setupCalldata_);
    }

    /// @notice Returns the current admin of the proxy
    // solhint-disable-next-line func-name-mixedcase
    function proxy__getAdmin() external view returns (address) {
        return ERC1967Utils.getAdmin();
    }

    /// @notice Returns the current implementation address
    // solhint-disable-next-line func-name-mixedcase
    function proxy__getImplementation() external view returns (address) {
        return _implementation();
    }

    /// @notice Returns whether the implementation is locked forever
    // solhint-disable-next-line func-name-mixedcase
    function proxy__getIsOssified() external view returns (bool) {
        return ERC1967Utils.getAdmin() == address(0);
    }

    function _onlyAdmin() internal view {
        address admin = ERC1967Utils.getAdmin();
        if (admin == address(0)) {
            revert ProxyIsOssified();
        }
        if (admin != msg.sender) {
            revert NotAdmin();
        }
    }
}
