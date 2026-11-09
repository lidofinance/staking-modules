#!/usr/bin/env python3
"""Run pinned verification suites without confusing compilation with proof."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "certora/suites.json"
CONFIG_KEYS = {
    "files", "verify", "solc", "solc_evm_version", "solc_optimize", "packages",
    "link", "loop_iter", "rule_sanity", "msg", "optimistic_loop",
}


def checked_config(path: Path) -> dict:
    """Reject settings that can turn omissions into successful CI results."""
    conf = json.loads(path.read_text())
    if not isinstance(conf, dict):
        raise ValueError(f"{path.name}: configuration must be an object")
    unknown = set(conf) - CONFIG_KEYS
    if unknown:
        raise ValueError(f"{path.name}: unreviewed configuration keys are forbidden: {', '.join(sorted(unknown))}")
    if "optimistic_loop" in conf and conf["optimistic_loop"] is not False:
        raise ValueError(f"{path.name}: optimistic_loop must be false")
    if conf.get("rule_sanity") != "basic":
        raise ValueError(f"{path.name}: rule_sanity must be basic")
    try:
        optimizer = int(conf.get("solc_optimize", -1))
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{path.name}: solc_optimize must be 150") from exc
    if conf.get("solc") != "solc" or conf.get("solc_evm_version") != "osaka" or optimizer != 150:
        raise ValueError(f"{path.name}: build must match Osaka and optimizer runs 150")
    if not isinstance(conf.get("files"), list) or not conf["files"] or not isinstance(conf.get("verify"), str):
        raise ValueError(f"{path.name}: explicit nonempty files and verify are required")
    return conf


def command(mode: str, config: str, executable: str) -> list[str]:
    args = [executable, config]
    if mode == "check":
        args.append("--compilation_steps_only")
    else:
        args += ["--wait_for_results", "all"]
    return args


def source_fingerprint(conf: dict) -> str:
    """Identify the exact production/harness/model/spec/config input state."""
    digest = hashlib.sha256()
    paths = set(ROOT.glob("src/**/*.sol")) | set(ROOT.glob("certora/**/*.sol"))
    # A lockfile alone does not identify locally edited imported dependency code.
    paths |= set(ROOT.glob("node_modules/@openzeppelin/**/*.sol"))
    paths |= set(ROOT.glob("certora/**/*.spec")) | set(ROOT.glob("certora/confs/*.conf"))
    paths |= {
        ROOT / "yarn.lock", ROOT / "remappings.txt", ROOT / "foundry.toml",
        ROOT / "package.json", ROOT / "certora/requirements.txt", MANIFEST,
    }
    for path in sorted(paths):
        digest.update(str(path.relative_to(ROOT)).encode() + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def run_process(command: list[str], *, timeout: int, stdout=None, stderr=None, env=None) -> subprocess.CompletedProcess:
    """Kill the complete local process group when a compiler/Java invocation is interrupted.

    A timed-out cloud client does not cancel the job already submitted to Certora.
    Linux and macOS use separate sessions; the non-POSIX fallback can kill only the direct child.
    """
    with subprocess.Popen(command, cwd=ROOT, stdout=stdout, stderr=stderr, env=env,
                          text=True, start_new_session=os.name == "posix") as process:
        try:
            output, errors = process.communicate(timeout=timeout)
        except BaseException:
            try:
                if os.name == "posix":
                    os.killpg(process.pid, signal.SIGKILL)
                else:
                    process.kill()
            except ProcessLookupError:
                pass
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                # A detached descendant may have escaped the session while retaining a pipe.
                # Closing it in Popen.__exit__ keeps cleanup itself bounded.
                pass
            raise
        return subprocess.CompletedProcess(command, process.returncode, output, errors)


def write_report(path: Path, results: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(results, indent=2) + "\n")
    temporary.replace(path)


def version(executable: str) -> dict:
    """Record tool identity without forwarding the Prover credential to the probe."""
    environment = dict(os.environ)
    environment.pop("CERTORAKEY", None)
    result = run_process([executable, "--version"], timeout=15, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, env=environment)
    if result.returncode != 0 or not result.stdout.strip():
        raise ValueError(f"Could not identify {executable}")
    return {"path": shutil.which(executable), "version": result.stdout.strip()}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("list", "check", "prove"))
    parser.add_argument("--suite", action="append", choices=list(json.loads(MANIFEST.read_text())))
    parser.add_argument("--certora", default=os.environ.get("CERTORA_RUN", "certoraRun"))
    parser.add_argument("--output-dir", type=Path, default=ROOT / "certora/results")
    parser.add_argument("--timeout", type=int, default=3600, help="Per-suite process timeout in seconds")
    args = parser.parse_args(argv)
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    manifest = json.loads(MANIFEST.read_text())
    selected = list(dict.fromkeys(args.suite or list(manifest)))
    if args.mode == "list":
        for suite in selected:
            print(f"{suite}: {manifest[suite]['boundary']}")
        return 0
    args.output_dir.mkdir(parents=True, exist_ok=True)
    results = {
        "run_id": str(uuid.uuid4()),
        "mode": args.mode,
        "started_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "meaning": "Compilation and CVL typechecking only; no properties proved."
        if args.mode == "check" else "Cloud Prover execution; inspect individual rule results and assumptions.",
        "selected_suites": selected,
        "selected_count": len(selected),
        "completed_count": 0,
        "complete": False,
        "suites": [],
    }
    report_path = args.output_dir / f"{args.mode}.json"
    write_report(report_path, results)
    if args.mode == "prove" and not os.environ.get("CERTORAKEY"):
        results["error"] = "CERTORAKEY is not configured; no verification jobs submitted."
        write_report(report_path, results)
        print(results["error"], file=sys.stderr)
        return 2
    if not shutil.which(args.certora):
        results["error"] = f"Missing {args.certora}; install certora/requirements.txt"
        write_report(report_path, results)
        print(results["error"], file=sys.stderr)
        return 2
    try:
        # Certora's implicit expected.json can accept a known failing rule as expected success.
        # A verification run here must require SUCCESS for every returned rule instead.
        if args.mode == "prove" and (ROOT / "expected.json").exists():
            raise ValueError("Refusing expected.json comparison baseline; cloud rules must all succeed")
        configs = {suite: checked_config(ROOT / manifest[suite]["config"]) for suite in selected}
        results["tools"] = {"certora": version(args.certora), "solc": version("solc")}
        results["source_sha256"] = source_fingerprint({})
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        results["error"] = str(exc)
        write_report(report_path, results)
        print(results["error"], file=sys.stderr)
        return 2
    write_report(report_path, results)
    failed = False
    for suite in selected:
        entry = manifest[suite]
        record = {"suite": suite, "boundary": entry["boundary"], "status": "running"}
        results["suites"].append(record)
        write_report(report_path, results)
        started = time.monotonic()
        try:
            conf = configs[suite]
            record["source_sha256"] = source_fingerprint(conf)
            record["config"] = entry["config"]
            cmd = command(args.mode, entry["config"], args.certora)
            record["command"] = cmd
            print(f"{args.mode}: {suite}", flush=True)
            log_path = args.output_dir / f"{suite}.{args.mode}.log"
            record["log"] = str(log_path)
            with log_path.open("w") as log:
                result = run_process(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout)
            record["exit_code"] = result.returncode
            record["status"] = (
                "compiled_not_proved" if args.mode == "check" else "prover_completed_review_rules"
            ) if result.returncode == 0 else "failed"
            if source_fingerprint(conf) != record["source_sha256"]:
                record["status"] = "inputs_changed"
        except subprocess.TimeoutExpired:
            record["status"] = "timeout"
            if args.mode == "prove":
                record["warning"] = "Client timed out; any submitted cloud job may still be running"
        except KeyboardInterrupt:
            record["status"] = "interrupted"
            record["seconds"] = round(time.monotonic() - started, 2)
            write_report(report_path, results)
            return 130
        except (OSError, ValueError) as exc:
            record["status"] = "error"
            record["error"] = str(exc)
        record["seconds"] = round(time.monotonic() - started, 2)
        results["completed_count"] += 1
        results["complete"] = results["completed_count"] == results["selected_count"]
        if results["complete"]:
            results["finished_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
        failed |= record["status"] not in ("compiled_not_proved", "prover_completed_review_rules")
        print(f"{suite}: {record['status']}", flush=True)
        write_report(report_path, results)
    return 1 if failed else 0


if __name__ == "__main__":
    # CI cancellation must reach the cleanup path of a compiler/Java subprocess group.
    def interrupted(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    raise SystemExit(main())
