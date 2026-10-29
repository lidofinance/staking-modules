# The scanner clones staking-modules, then builds this file with that checkout as the context.
# Network access ends after the image is built. Keep dependencies, build artifacts and compiler caches.
FROM node:20-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git python3 build-essential pkg-config unzip jq \
    && rm -rf /var/lib/apt/lists/*

ENV HUSKY=0 \
    FOUNDRY_THREADS=4 \
    PATH=/root/.foundry/bin:$PATH

COPY . /src
WORKDIR /src

# The bundled Yarn release and lockfile pin the dependency install to Yarn 4.1.1.
# Node 20 follows .nvmrc and CI; Verifier tests use Node FFI with these dependencies.
RUN corepack enable \
    && node .yarn/releases/yarn-4.1.1.cjs install --immutable

# Forge is the primary build/test runner, so installation and compilation must succeed.
RUN curl -fsSL -o /tmp/foundry-installer.sh https://foundry.paradigm.xyz \
    && bash /tmp/foundry-installer.sh \
    && rm -f /tmp/foundry-installer.sh \
    && /root/.foundry/bin/foundryup -i "$(cat .foundryref)" \
    && forge --version

# Foundry v1.5.1's embedded compiler-release metadata can lag on some architectures.
# Prefetch the official compiler explicitly and keep it in the SVM cache for offline tests.
# SHA-256 values are from the official Solidity v0.8.33 release assets.
RUN case "$(uname -m)" in \
         x86_64) solc_asset=solc-static-linux; solc_sha=1274e5c4621ae478090c5a1f48466fd3c5f658ed9e14b15a0b213dc806215468 ;; \
         aarch64) solc_asset=solc-static-linux-arm; solc_sha=9e34cfb916a75bdd641b1e706d538afe9fb4471ae6105a9077e7908a058df959 ;; \
         *) echo "Unsupported compiler architecture: $(uname -m)"; exit 1 ;; \
       esac \
    && mkdir -p /root/.svm/0.8.33 \
    && curl -fsSL -o /root/.svm/0.8.33/solc-0.8.33 \
         "https://github.com/argotorg/solidity/releases/download/v0.8.33/$solc_asset" \
    && echo "$solc_sha  /root/.svm/0.8.33/solc-0.8.33" | sha256sum --check - \
    && chmod +x /root/.svm/0.8.33/solc-0.8.33 \
    && /root/.svm/0.8.33/solc-0.8.33 --version \
    && forge build --offline

# Reference material for offline review, outside scan scope. Each fetch is optional.
# core v4.1.0 is the production dependency; LIPs and registry pins match core's scanner image.
# Update contract pins for relevant production upgrades and docs/LIPs for registry or specification changes.
RUN mkdir -p /opt/lido \
    && for reference in \
         core:1440c830eb1d0916a436468a71cd73bc8b8deffb \
         lido-improvement-proposals:b3f58400a576d01a5a160de69fa823283b38bc3f; do \
         repo="${reference%%:*}"; ref="${reference#*:}"; \
         (git init --quiet "/opt/lido/$repo" \
           && git -C "/opt/lido/$repo" fetch --quiet --depth 1 "https://github.com/lidofinance/$repo" "$ref" \
           && git -C "/opt/lido/$repo" checkout --quiet --detach "$ref") \
           || { rm -rf "/opt/lido/$repo"; echo "WARNING: could not fetch $repo at $ref"; }; \
       done \
    && (curl -fsSL -o /opt/lido/deployed-contracts.md \
          https://raw.githubusercontent.com/lidofinance/docs/c261dab80c82609d947c6eaccfe0129aa03fe3e6/docs/deployed-contracts/index.md \
        || { rm -f /opt/lido/deployed-contracts.md; echo "WARNING: could not fetch deployed-contracts.md"; })

# A bounded smoke suite exercises Node FFI and offline compilation with cached dependencies.
# Report test failures without hiding a failure to install Forge or compile the project.
RUN timeout 900 forge test --offline --skip script \
      --match-path test/unit/Verifier.t.sol --match-contract '^VerifierWithdrawalTest$' \
    || echo "WARNING: offline Verifier smoke test reported failures"

# Use the committed Yarn executable directly so the offline shell never asks Corepack to download it.
RUN ln -sf /src/.yarn/releases/yarn-4.1.1.cjs /usr/local/bin/yarn \
    && ln -sf /src/.yarn/releases/yarn-4.1.1.cjs /usr/local/bin/yarnpkg \
    && yarn --version

# Offline unit suite: forge test --offline --skip script --no-match-path 'test/fork/**'
# Fork/deployment suites need an Ethereum RPC endpoint and are not part of the offline smoke test.
