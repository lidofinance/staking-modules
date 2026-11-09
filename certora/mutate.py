#!/usr/bin/env python3
"""Offline seeded mutation checks of executable witnesses; never formal proofs.

Production files in the checkout are read only. Every baseline and mutant runs
in a disposable copy. A build error, timeout, missing test, or unexpected revert
is inconclusive, never a killed mutant.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
from typing import Callable
import uuid

FUZZ_SEED = "0x" + "42" * 32


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


@dataclass
class Invocation:
    returncode: int | None
    stdout: str = ""
    stderr: str = ""
    timed_out: bool = False


def invoke(command: list[str], cwd: Path, timeout: int) -> Invocation:
    env = dict(os.environ, FOUNDRY_PROFILE="formal")
    env["FOUNDRY_VERBOSITY"] = "0"
    env.setdefault("FOUNDRY_FUZZ_RUNS", "64")
    # Stable fuzz inputs make mutant and baseline comparisons reproducible.
    env["FOUNDRY_FUZZ_SEED"] = FUZZ_SEED
    try:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, start_new_session=True)
        try:
            stdout, stderr = process.communicate(timeout=timeout)
            return Invocation(process.returncode, stdout, stderr)
        except subprocess.TimeoutExpired:
            # Forge may have spawned solc: kill the entire disposable job, not
            # only its parent, before TemporaryDirectory removes its files.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            stdout, stderr = process.communicate()
            return Invocation(None, stdout, stderr, True)
        except BaseException:
            # Interrupts must not leave Forge/solc writing into a deleted copy.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate()
            raise
    except OSError as error:
        return Invocation(None, stderr=str(error))


def read_tests(stdout: str) -> list[dict]:
    """Accept Forge's aggregate JSON, optionally preceded by compiler progress.

    Trailing non-whitespace is rejected so partial/truncated JSON cannot pass.
    Only actual test_results entries count, never compiler diagnostic objects.
    """
    decoder = json.JSONDecoder()
    for match in re.finditer(r"(?m)^\s*\{", stdout):
        try:
            payload, end = decoder.raw_decode(stdout, match.end() - 1)
        except json.JSONDecodeError:
            continue
        if stdout[end:].strip() or not isinstance(payload, dict):
            continue
        tests = []
        for suite, result in payload.items():
            if not isinstance(result, dict) or not isinstance(result.get("test_results"), dict):
                continue
            for name, test in result["test_results"].items():
                if isinstance(test, dict):
                    tests.append(dict(test, name=name, suite=suite))
        if tests:
            return tests
    return []


def classify(result: Invocation, test_name: str, expected_failure: str, *, baseline: bool = False) -> tuple[str, str]:
    if result.timed_out:
        return "inconclusive", "test command timed out"
    if result.returncode is None:
        return "inconclusive", "test command could not start"
    tests = read_tests(result.stdout)
    selected = [test for test in tests if test["name"].split("(", 1)[0] == test_name]
    if len(selected) != 1 or len(tests) != 1:
        return "inconclusive", "expected exactly one named test in complete Forge JSON"
    test = selected[0]
    status = test.get("status")
    if status == "Success" and result.returncode == 0:
        return ("passed" if baseline else "survived"), "selected test passed"
    if baseline:
        return "inconclusive", "baseline did not pass"
    reason = test.get("reason")
    if status == "Failure" and result.returncode == 1 and isinstance(reason, str):
        if re.search(expected_failure, reason):
            return "killed", reason
    return "inconclusive", f"unexpected test result: {status}: {reason}"


def load_manifest(path: Path) -> list[dict]:
    manifest = json.loads(path.read_text())
    if manifest.get("schema_version") != 1 or not isinstance(manifest.get("mutations"), list):
        raise ValueError("unsupported mutation manifest")
    mutations = manifest["mutations"]
    names = set()
    for mutation in mutations:
        for key in ("name", "suite", "source", "find", "replace", "test_path", "test", "expected_failure"):
            if not isinstance(mutation.get(key), str) or not mutation[key]:
                raise ValueError(f"mutation requires nonempty {key}")
        if not re.fullmatch(r"[a-z0-9_-]+", mutation["name"]) or mutation["name"] in names:
            raise ValueError("mutation names must be unique safe slugs")
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", mutation["test"]):
            raise ValueError("test must be one Foundry test function name")
        source = Path(mutation["source"])
        if source.is_absolute() or ".." in source.parts or source.parts[0] != "src":
            raise ValueError("mutations may target only relative src/ paths")
        test_path = Path(mutation["test_path"])
        if test_path.is_absolute() or ".." in test_path.parts or test_path.parts[:3] != ("test", "unit", "formal"):
            raise ValueError("test_path must be inside test/unit/formal")
        if mutation["find"] == mutation["replace"]:
            raise ValueError("mutation must change the source")
        re.compile(mutation["expected_failure"])
        names.add(mutation["name"])
    return mutations


def snapshot(root: Path, destination: Path, output_dir: Path) -> None:
    excluded = {".git", "node_modules", "out", "cache", "broadcast", ".certora_internal", "__pycache__"}

    def ignore(directory: str, names: list[str]) -> list[str]:
        skipped = []
        for name in names:
            path = Path(directory) / name
            if name in excluded or path.resolve() in {output_dir.resolve(), (root / "certora/results").resolve()}:
                skipped.append(name)
        return skipped

    shutil.copytree(root, destination, symlinks=True, ignore=ignore)
    dependencies = root / "node_modules"
    if dependencies.exists():
        (destination / "node_modules").symlink_to(dependencies.resolve(), target_is_directory=True)


def write_logs(directory: Path, stage: str, result: Invocation) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{stage}.stdout.log").write_text(result.stdout)
    (directory / f"{stage}.stderr.log").write_text(result.stderr)


def write_report(directory: Path, report: dict) -> None:
    temporary = directory / f".report-{uuid.uuid4().hex}.tmp"
    try:
        temporary.write_text(json.dumps(report, indent=2) + "\n")
        temporary.replace(directory / "report.json")
    finally:
        temporary.unlink(missing_ok=True)


def evaluate(
    root: Path,
    mutation: dict,
    output_dir: Path,
    forge: str,
    solc: str,
    timeout: int,
    runner: Callable[[list[str], Path, int], Invocation] = invoke,
) -> dict:
    report = dict(name=mutation["name"], suite=mutation["suite"], status="inconclusive", reason="not run")
    report["mutation_sha256"] = hashlib.sha256(json.dumps(mutation, sort_keys=True).encode()).hexdigest()
    report["fuzz_seed"] = FUZZ_SEED
    report["fuzz_runs"] = os.environ.get("FOUNDRY_FUZZ_RUNS", "64")
    report["config_sha256"] = {name: sha256(root / name) for name in
                                ("foundry.toml", "remappings.txt", "package.json", "yarn.lock", ".foundryref")
                                if (root / name).is_file()}
    log_dir = output_dir / mutation["name"]
    relative = Path(mutation["source"])
    if any((root / Path(*relative.parts[:index])).is_symlink() for index in range(1, len(relative.parts) + 1)):
        return dict(report, reason="mutation source and its parent directories must not be symlinks")
    source = (root / mutation["source"]).resolve()
    if not source.is_relative_to(root.resolve()):
        return dict(report, reason="source escapes repository")
    original = source.read_bytes()
    report["source_sha256"] = hashlib.sha256(original).hexdigest()
    text = original.decode()
    if text.count(mutation["find"]) != 1:
        return dict(report, reason="replacement target must occur exactly once")
    if not (root / mutation["test_path"]).is_file():
        return dict(report, reason="selected test file is missing")
    commands = {
        "build": [forge, "build", mutation["test_path"], "--use", solc],
        "test": [forge, "test", "--use", solc, "--json", "--match-path", mutation["test_path"],
                 "--match-test", "^" + re.escape(mutation["test"]) + r"\("],
    }
    report["commands"] = commands
    report["test"] = mutation["test"]
    with tempfile.TemporaryDirectory(prefix="staking-fv-mutation-") as temporary:
        directory = Path(temporary)
        for mode in ("baseline", "mutant"):
            checkout = directory / mode
            snapshot(root, checkout, output_dir)
            target = checkout / mutation["source"]
            if not target.resolve().is_relative_to(checkout.resolve()):
                return dict(report, reason="disposable mutation source escapes its checkout")
            if target.read_bytes() != original:
                return dict(report, reason="source changed while creating disposable checkout")
            test_hash = sha256(checkout / mutation["test_path"])
            report[mode + "_test_sha256"] = test_hash
            if mode == "mutant" and test_hash != report["baseline_test_sha256"]:
                return dict(report, reason="baseline and mutant witness files changed during execution")
            if mode == "mutant":
                # A source symlink must never write back into the original tree.
                if target.is_symlink():
                    return dict(report, reason="mutation source must not be a symlink")
                target.write_text(text.replace(mutation["find"], mutation["replace"], 1))
            build = runner(commands["build"], checkout, timeout)
            write_logs(log_dir, mode + "-build", build)
            if build.timed_out or build.returncode != 0:
                report["reason"] = mode + " compilation did not succeed"
                break
            test_result = runner(commands["test"], checkout, timeout)
            write_logs(log_dir, mode + "-test", test_result)
            status, reason = classify(test_result, mutation["test"], mutation["expected_failure"], baseline=mode == "baseline")
            report[mode] = dict(status=status, reason=reason, returncode=test_result.returncode)
            if mode == "baseline" and status != "passed":
                report["reason"] = "baseline did not pass: " + reason
                break
            if mode == "mutant":
                report.update(status=status, reason=reason)
    if source.read_bytes() != original:
        raise RuntimeError("original checkout changed during mutation run")
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="list selected mutations without executing")
    parser.add_argument("--suite", action="append", default=[])
    parser.add_argument("--mutation", action="append", default=[])
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--output-dir", type=Path, default=Path("certora/results/mutations"))
    parser.add_argument("--forge", default=os.environ.get("FORGE", "forge"))
    parser.add_argument("--solc", default=os.environ.get("SOLC", "solc"))
    parser.add_argument("--timeout", type=int, default=180, help="timeout in seconds for each build/test command")
    args = parser.parse_args(argv)
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    root = args.repo_root.resolve()
    manifest_path = args.manifest or root / "certora/mutations.json"
    summary = None
    output_dir = None
    previous_sigterm = signal.getsignal(signal.SIGTERM)

    def interrupted(signum, frame):
        raise KeyboardInterrupt("terminated")

    signal.signal(signal.SIGTERM, interrupted)
    try:
        mutations = load_manifest(manifest_path)
        for value in args.suite:
            if value not in {mutation["suite"] for mutation in mutations}:
                parser.error(f"unknown suite: {value}")
        for value in args.mutation:
            if value not in {mutation["name"] for mutation in mutations}:
                parser.error(f"unknown mutation: {value}")
        selected = [mutation for mutation in mutations
                    if (not args.suite or mutation["suite"] in args.suite)
                    and (not args.mutation or mutation["name"] in args.mutation)]
        if not selected:
            parser.error("no mutations selected")
        if args.list:
            for mutation in selected:
                print(f"{mutation['name']}\t{mutation['suite']}\t{mutation['test']}")
            return 0
        output_dir = args.output_dir.resolve()
        output_dir.mkdir(parents=True, exist_ok=True)
        reports = []
        summary = {"kind": "offline-executable-mutation-tests", "formal_proof": False,
                   "run_id": uuid.uuid4().hex, "started_at": datetime.now(timezone.utc).isoformat(),
                   "manifest_sha256": sha256(manifest_path), "tool_versions": {},
                   "selected_count": len(selected), "selected": [item["name"] for item in selected],
                   "completed_count": 0, "complete": False, "all_killed": False, "mutations": reports}
        # Clear any prior successful result before commands can fail or block.
        write_report(output_dir, summary)
        versions = {}
        for name, executable in (("forge", args.forge), ("solc", args.solc)):
            version = invoke([executable, "--version"], root, 10)
            versions[name] = {"returncode": version.returncode, "version": version.stdout.strip(),
                              "stderr": version.stderr.strip(), "timed_out": version.timed_out}
        summary["tool_versions"] = versions
        for mutation in selected:
            summary["active_mutation"] = mutation["name"]
            write_report(output_dir, summary)
            report = evaluate(root, mutation, output_dir, args.forge, args.solc, args.timeout)
            reports.append(report)
            print(f"{report['name']}: {report['status']}: {report['reason']}", flush=True)
            complete = len(reports) == len(selected)
            summary.update(completed_count=len(reports), complete=complete,
                           all_killed=complete and all(item["status"] == "killed" for item in reports))
            summary.pop("active_mutation", None)
            if complete:
                summary["finished_at"] = datetime.now(timezone.utc).isoformat()
            write_report(output_dir, summary)
        return 0 if all(report["status"] == "killed" for report in reports) else 1
    except (OSError, ValueError, RuntimeError, KeyboardInterrupt) as error:
        if summary is not None and output_dir is not None:
            summary.update(complete=False, all_killed=False, error=str(error) or "interrupted",
                           finished_at=datetime.now(timezone.utc).isoformat())
            try:
                write_report(output_dir, summary)
            except OSError as report_error:
                print(f"could not persist failed mutation report: {report_error}", file=sys.stderr)
        print(f"mutation checks failed: {error}", file=sys.stderr)
        return 130 if isinstance(error, KeyboardInterrupt) else 2
    finally:
        signal.signal(signal.SIGTERM, previous_sigterm)


if __name__ == "__main__":
    raise SystemExit(main())
