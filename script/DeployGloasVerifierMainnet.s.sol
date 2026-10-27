// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployGloasVerifierBase } from "./DeployGloasVerifier.s.sol";
import { WCType } from "./utils/WithdrawalCredentials.sol";

abstract contract DeployGloasVerifierMainnet is DeployGloasVerifierBase {
    constructor() DeployGloasVerifierBase("mainnet", 1) {
        // TODO: set to GLOAS_FORK_EPOCH * 32 once the mainnet fork is scheduled
        // @see https://github.com/eth-clients/mainnet/blob/main/metadata/config.yaml
        verifierGloasSlot = type(uint64).max;

        // Lido addresses
        config.lidoLocatorAddress = 0xC1d0b3DE6792Bf6b4b37EccdcC24e45978Cfd2Eb;
        config.aragonAgent = 0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c;

        config.slotsPerEpoch = 32; // https://github.com/ethereum/consensus-specs/blob/7df1ce30384b13d01617f8ddf930f4035da0f689/specs/phase0/beacon-chain.md?plain=1#L246

        // Verifier
        config.verifierFirstSupportedSlot = 364032 * config.slotsPerEpoch; // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-7600.md#activation
        config.capellaSlot = 194048 * config.slotsPerEpoch; // @see https://github.com/eth-clients/mainnet/blob/main/metadata/config.yaml#L50

        // CircuitBreaker
        config.circuitBreaker = 0x6019CB557978296BA3C08a7B73225C0975DFB2F7; // Proposed by LIP-34

        // DG
        config.resealManager = 0x7914b5a1539b97Bd0bbd155757F25FD79A522d24;
    }
}

contract DeployGloasVerifierMainnetCSM is DeployGloasVerifierMainnet {
    constructor() {
        module = 0xdA7dE2ECdDfccC6c3AF10108Db212ACBBf9EA83F;

        config.verifierWcType = WCType.Eth1;
        config.minWithdrawalRatio = 9900;
    }
}

contract DeployGloasVerifierMainnetCSM0x02 is DeployGloasVerifierMainnet {
    constructor() {
        module = 0x792Cd25e4aE3578375031FB55e048E163A804F7B;

        config.verifierWcType = WCType.Compounding;
        config.minWithdrawalRatio = 9900;
    }
}

contract DeployGloasVerifierMainnetCurated is DeployGloasVerifierMainnet {
    constructor() {
        module = 0xDa5F930cE326EB5205085D66c72A4E79d60cB8C1;

        config.verifierWcType = WCType.Compounding;
        config.minWithdrawalRatio = 9950;
    }

    /// @inheritdoc DeployGloasVerifierBase
    function run(string memory gitRef, string memory paramsKey) public override {
        super.run(gitRef, paramsKey);
        _deployCuratedModule();
    }
}
