// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

contract LidoLocatorMock {
    address public l;
    address public b;
    address public wq;
    address public el;
    address public t;
    address public sr;
    address public twg;

    constructor(
        address _lido,
        address _burner,
        address _wq,
        address _el,
        address _t,
        address _sr,
        address _twg
    ) {
        l = _lido;
        b = _burner;
        wq = _wq;
        el = _el;
        t = _t;
        sr = _sr;
        twg = _twg;
    }

    function lido() external view returns (address) {
        return l;
    }

    function burner() external view returns (address) {
        return b;
    }

    function withdrawalQueue() external view returns (address) {
        return wq;
    }

    function elRewardsVault() external view returns (address) {
        return el;
    }

    function treasury() external view returns (address) {
        return t;
    }

    function stakingRouter() external view returns (address payable) {
        return payable(sr);
    }

    function triggerableWithdrawalsGateway() external view returns (address) {
        return twg;
    }
}
