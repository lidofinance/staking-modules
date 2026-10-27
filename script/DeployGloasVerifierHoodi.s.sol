// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployGloasVerifierBase } from "./DeployGloasVerifier.s.sol";
import { WCType } from "./utils/WithdrawalCredentials.sol";

abstract contract DeployGloasVerifierHoodi is DeployGloasVerifierBase {
    constructor() DeployGloasVerifierBase("hoodi", 560048) {
        verifierGloasSlot = 4235264; // GLOAS_FORK_EPOCH = 4235264 / 32 = 132352, @see https://github.com/eth-clients/hoodi/blob/main/metadata/config.yaml#L49

        // Lido addresses
        config.lidoLocatorAddress = 0xe2EF9536DAAAEBFf5b1c130957AB3E80056b06D8;
        config.aragonAgent = 0x0534aA41907c9631fae990960bCC72d75fA7cfeD;

        config.slotsPerEpoch = 32;

        // Verifier
        config.verifierFirstSupportedSlot = 2048 * config.slotsPerEpoch; // @see https://github.com/eth-clients/hoodi/blob/main/metadata/config.yaml#L41
        config.capellaSlot = 0; // @see https://github.com/eth-clients/hoodi/blob/main/metadata/config.yaml#L33

        // CircuitBreaker
        config.circuitBreaker = 0x44a5789dFeDa59cD176Ab5709ec2F4829dE4d555;

        // DG
        config.resealManager = 0x05172CbCDb7307228F781436b327679e4DAE166B;

        config.secondAdminAddress = 0x4AF43Ee34a6fcD1fEcA1e1F832124C763561dA53; // Dev team EOA
    }
}

contract DeployGloasVerifierHoodiCSM is DeployGloasVerifierHoodi {
    constructor() {
        module = 0x79CEf36D84743222f37765204Bec41E92a93E59d;

        config.verifierWcType = WCType.Eth1;
        config.minWithdrawalRatio = 9900;
    }
}

contract DeployGloasVerifierHoodiCSM0x02 is DeployGloasVerifierHoodi {
    constructor() {
        module = 0xbb7dd81FAC80f3Effa10eA8b973c15AE65a4CAf9;

        config.verifierWcType = WCType.Compounding;
        config.minWithdrawalRatio = 9900;
    }
}

contract DeployGloasVerifierHoodiCurated is DeployGloasVerifierHoodi {
    constructor() {
        module = 0x87EB69Ae51317405FD285efD2326a4a11f6173b9;

        config.verifierWcType = WCType.Compounding;
        config.minWithdrawalRatio = 9950;
    }

    /// @inheritdoc DeployGloasVerifierBase
    function run(string memory gitRef, string memory paramsKey) public override {
        super.run(gitRef, paramsKey);
        _deployCuratedModule();
    }
}
