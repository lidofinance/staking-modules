# Repository Guidelines

## Project Structure & Module Organization

- `src/`: Solidity contracts (Solc 0.8.33).
- `test/`: Forge tests (`*.t.sol`), plus `test/fork/*` for fork/integration and deployment tests.
- `script/`: Forge scripts (deploy/verify, per-chain variants).
- `artifacts/`, `broadcast/`, `out/`, `cache/`: build, deploy, and fork outputs.
- `gists/`: small code examples related to the module.
- `node_modules/`: dependencies; see `remappings.txt`.
- `docs/`: documentation and design notes.

## Build, Test, and Development Commands

- `just deps`: install production deps; `just deps-dev`: dev deps + husky.
- `just`: clean, deps, build, and run all tests.
- `just build`: build the project skipping tests and scripts (preferable for faster iterations); use `forge build` for compile all files of the project.
- `just test-unit`: unit tests only; `just test-all`: unit + fork suites.
- `just test-local`: spins up anvil fork, deploys, runs deployment+integration tests.
- `just coverage` | `just coverage-lcov`: coverage (LCOV saved; see `lcov.html`).
- Linting: `yarn lint:check` (prettier + solhint), `yarn lint:fix`, `yarn lint:solhint`.
- Diff: `git diff --no-ext-diff`

- For fast local checks after small edits, prefer targeted compile of changed Solidity files: `forge build <changed-file-1> <changed-file-2> ...`.
- Keep `forge build` as the full-project compile when touching shared interfaces/libraries or before final handoff.

## Coding Style & Naming Conventions

- Formatting: Prettier + `prettier-plugin-solidity` (Solidity `printWidth=80`, `tabWidth=4`, spaces only).
- Linting: Solhint (`.solhint.json`) with `solhint:recommended` and `solhint-plugin-lido-csm`.
- Versions: enforce `pragma solidity 0.8.33` (`compiler-version` rule).
- Naming: contracts/libraries `CamelCase` (e.g., `CSModule`, `AssetRecovererLib`), interfaces `IName` (rule: `interface-starts-with-i`).
- Inline assembly should be well documented, preferably every non-trivial line with its own comment.
- Conventions: prefer custom errors, calldata parameters, and struct packing (gas rules). Immutable vars styled as constants.
- Keep things in one function unless composable or reusable.
- Prefer short variable names where possible. Prefer same length variable names for related things.
- Prefer early returns to else statements.
- While refactoring keep comments added from existing implementations where applicable.
- Make sure external functions in contracts and interfaces have proper natspec.
- Avoid using magic numbers, prefer re-using or defining constants.
- Inline values used only once where the variable name does not add legibility.
- When last I looked, the year was 2026.

## Testing Guidelines

- Framework: Foundry/Forge with fuzzing (`fuzz.runs=256`).
- Structure: unit tests in `test/*.t.sol`; fork suites under `test/fork/*` (deployment/integration).
- Run: `just test-unit` for fast cycles; `CHAIN`/`RPC_URL` required for fork tests. Example: `export CHAIN=hoodi && export RPC_URL=<https-url>`.
- Coverage: `just coverage-lcov` produces LCOV output (commit if relevant).
- After making changes to the source code make sure you've either ran build command or unit tests.
- `vm.prank(addr)` applies to the next external call only. Avoid patterns where the next call is accidentally consumed by a getter inside arguments or call-chaining.
  Bad: `vm.prank(admin); target.grantRole(target.ROLE(), user)` or `vm.prank(admin); module.PARAMETERS_REGISTRY().setX(...)`.
  Good: precompute external values before prank (`bytes32 role = target.ROLE();`) or use `vm.startPrank`/`vm.stopPrank` for multi-call sequences.
- Do not assert unchanged state after a reverting call.
- Order tests: happy path first, revert cases afterwards.
- Deployment test name suffixes are part of the test selection contract used by `just` recipes and encode two axes: phase and flow.
- Phase semantics:
- `*_scratch*`: checks for post-deploy, pre-vote state only.
- `*_afterVote*`: checks for post-governance state only; these should validate changes introduced by vote execution (`script/fork-helpers/SimulateVote.s.sol`), e.g. upgrades, finalize steps, role migrations, pause/resume transitions.
- Flow semantics:
- `*_onlyFull*`: checks that run only in full deployment flows and are excluded from `test-deployment-csm-v3-only-scratch`.
- Combined semantics:
- `*_scratch_onlyFull*`: scratch-phase checks that also require full-flow context.
- No suffix (`test_*`): use only for invariants expected to hold in every phase/flow where the suite is executed.
- Naming rule: choose suffixes based on the state transition under test; if a check depends on vote-executed effects, it must include `_afterVote`.

## Deployment & Upgrade Flow

- Protocol rollout is two-phase: deployment first, vote execution second.
- Deployment phase: deploy scripts should deploy new implementations/helpers and execute all privileged setup that is possible while deployer temporarily has admin rights.
- Deployment phase must end in post-handoff state: required admin roles are returned to the protocol agent and deployer admin rights are revoked.
- Vote phase: simulate-vote scripts should apply governance actions to already deployed protocol contracts only (proxy upgrades, role/state transitions), not deployment-only setup.
- Vote phase steps should be explicit and deterministic: encode concrete, ordered calls with known addresses; avoid generic loop-based governance steps unless explicitly required.

## Commit & Pull Request Guidelines

- Commits: Conventional Commits. Examples: `feat: add validator key rotation`, `fix: resolve bond calculation overflow`.
- PRs: clear description, linked issues, rationale, test coverage notes, storage layout impacts (if any), and gas impact (attach `GAS.md` when updated). Ensure CI green and `yarn lint:check` passes.

## Communication

- If a feature request is underspecified, ask targeted questions before implementing. Do not invent requirements or omit important details—surface uncertainties explicitly.

## Security & Configuration Tips

- Never commit keys; use `.env` from `.env.sample`. For forks: `ANVIL_IP_ADDR`, `ANVIL_PORT`, `RPC_URL`, `CHAIN`.
- Pin Foundry to version in `.foundryref`. Use `just make-fork`/`just kill-fork` to manage local forks.
