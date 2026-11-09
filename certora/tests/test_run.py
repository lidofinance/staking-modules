"""Tests for result labeling and fail-closed verification configuration."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("certora_runner", Path(__file__).parents[1] / "run.py")
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class RunnerTest(unittest.TestCase):
    def test_local_check_cannot_submit_a_proof(self):
        self.assertEqual(runner.command("check", "suite.conf", "certoraRun"),
                         ["certoraRun", "suite.conf", "--compilation_steps_only"])

    def test_cloud_command_waits_for_results(self):
        self.assertEqual(runner.command("prove", "suite.conf", "certoraRun"),
                         ["certoraRun", "suite.conf", "--wait_for_results", "all"])

    def test_missing_key_submits_nothing_and_fails(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {}, clear=True), \
                patch.object(runner, "run_process") as process:
            self.assertEqual(runner.main(["prove", "--output-dir", directory]), 2)
            process.assert_not_called()
            report = json.loads((Path(directory) / "prove.json").read_text())
            self.assertEqual(report["suites"], [])
            self.assertIn("no verification jobs", report["error"])
            self.assertFalse(report["complete"])
            self.assertEqual(report["completed_count"], 0)

    def test_missing_executable_replaces_stale_success_report(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(runner.shutil, "which", return_value=None):
            path = Path(directory) / "check.json"
            path.write_text(json.dumps({"complete": True, "suites": [{"status": "compiled_not_proved"}]}))
            self.assertEqual(runner.main(["check", "--output-dir", directory]), 2)
            report = json.loads(path.read_text())
            self.assertFalse(report["complete"])
            self.assertEqual(report["suites"], [])
            self.assertIn("Missing", report["error"])

    def test_expected_results_baseline_cannot_accept_failing_cloud_rules(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"CERTORAKEY": "synthetic"}), \
                patch.object(runner, "ROOT", Path(directory)), \
                patch.object(runner.shutil, "which", return_value="certoraRun"), \
                patch.object(runner, "run_process") as process:
            (Path(directory) / "expected.json").write_text('{"rules": {"important": "FAIL"}}')
            self.assertEqual(runner.main(["prove", "--output-dir", directory]), 2)
            process.assert_not_called()
            report = json.loads((Path(directory) / "prove.json").read_text())
            self.assertFalse(report["complete"])
            self.assertIn("expected.json", report["error"])

    def test_version_probe_does_not_receive_prover_credential(self):
        result = subprocess.CompletedProcess([], 0, "certora-cli 8.20.3\n", None)
        with patch.dict(os.environ, {"CERTORAKEY": "synthetic"}), \
                patch.object(runner, "run_process", return_value=result) as process:
            self.assertIn("8.20.3", runner.version("certoraRun")["version"])
            self.assertNotIn("CERTORAKEY", process.call_args.kwargs["env"])

    def test_all_configurations_are_checked_before_any_cloud_submission(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"CERTORAKEY": "synthetic"}), \
                patch.object(runner.shutil, "which", return_value="certoraRun"), \
                patch.object(runner, "checked_config", side_effect=[{}, ValueError("invalid second scene")]), \
                patch.object(runner, "run_process") as process:
            self.assertEqual(runner.main(["prove", "--output-dir", directory]), 2)
            process.assert_not_called()
            report = json.loads((Path(directory) / "prove.json").read_text())
            self.assertFalse(report["complete"])
            self.assertEqual(report["completed_count"], 0)

    def test_interrupted_suite_leaves_incomplete_current_evidence(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(runner.shutil, "which", return_value="certoraRun"), \
                patch.object(runner, "checked_config", return_value={}), \
                patch.object(runner, "version", return_value={"version": "synthetic"}), \
                patch.object(runner, "source_fingerprint", return_value="synthetic-source-hash"), \
                patch.object(runner, "run_process", side_effect=KeyboardInterrupt):
            self.assertEqual(runner.main(["check", "--suite", "BondLock", "--output-dir", directory]), 130)
            report = json.loads((Path(directory) / "check.json").read_text())
            self.assertFalse(report["complete"])
            self.assertEqual(report["completed_count"], 0)
            self.assertEqual(report["suites"][0]["status"], "interrupted")

    def test_process_failure_is_not_reported_as_success(self):
        result = subprocess.CompletedProcess([], 1)
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(runner.shutil, "which", return_value="certoraRun"), \
                patch.object(runner, "checked_config", return_value={}), \
                patch.object(runner, "version", return_value={"version": "synthetic"}), \
                patch.object(runner, "source_fingerprint", return_value="synthetic-source-hash"), \
                patch.object(runner, "run_process", return_value=result):
            self.assertEqual(runner.main(["check", "--suite", "BondLock", "--output-dir", directory]), 1)
            report = json.loads((Path(directory) / "check.json").read_text())
            self.assertTrue(report["complete"])
            self.assertEqual(report["completed_count"], 1)
            self.assertEqual(report["suites"][0]["status"], "failed")

    def test_optimistic_and_silent_exclusions_are_rejected(self):
        base = {"files": ["scene.sol"], "verify": "Scene:scene.spec", "solc": "solc",
                "rule_sanity": "basic", "solc_evm_version": "osaka", "solc_optimize": 150}
        bypasses = (
            {"optimistic_loop": True}, {"no_compare": True}, {"exclude_rule": ["critical"]},
            {"build_only": True}, {"compilation_steps_only": True}, {"local": True},
            {"override_base_config": "unchecked.conf"}, {"expected_file": "known-failures.json"},
            {"prover_args": ["-assumeUnwindCond"]}, {"solc_evm_version_map": {"Scene": "prague"}},
            {"solc_optimize_map": {"Scene": 200}}, {"disable_local_typechecking": True},
        )
        for forbidden in bypasses:
            with self.subTest(forbidden=forbidden), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "suite.conf"
                path.write_text(json.dumps(base | forbidden))
                with self.assertRaises(ValueError):
                    runner.checked_config(path)

    def test_every_committed_configuration_passes_policy(self):
        manifest = json.loads(runner.MANIFEST.read_text())
        for entry in manifest.values():
            with self.subTest(config=entry["config"]):
                runner.checked_config(runner.ROOT / entry["config"])

    def test_fingerprint_includes_imported_dependency_content(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(runner, "ROOT", Path(directory)), \
                patch.object(runner, "MANIFEST", Path(directory) / "certora/suites.json"):
            for name in ("yarn.lock", "remappings.txt", "foundry.toml", "package.json",
                         "certora/requirements.txt", "certora/suites.json"):
                path = Path(directory) / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("synthetic")
            dependency = Path(directory) / "node_modules/@openzeppelin/contracts/Dependency.sol"
            dependency.parent.mkdir(parents=True)
            dependency.write_text("contract Dependency {}")
            before = runner.source_fingerprint({})
            dependency.write_text("contract Dependency { uint256 modified; }")
            self.assertNotEqual(runner.source_fingerprint({}), before)

    @unittest.skipUnless(os.name == "posix" and Path("/proc").exists(), "Linux process-tree check")
    def test_timeout_terminates_descendant_process(self):
        with tempfile.TemporaryDirectory() as directory:
            pid_file = Path(directory) / "child.pid"
            program = (
                "import pathlib, subprocess, sys, time\n"
                "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])\n"
                f"pathlib.Path({str(pid_file)!r}).write_text(str(child.pid))\n"
                "time.sleep(60)\n"
            )
            with self.assertRaises(subprocess.TimeoutExpired):
                runner.run_process([sys.executable, "-c", program], timeout=1,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            child = int(pid_file.read_text())
            stat = Path(f"/proc/{child}/stat")
            for _ in range(50):
                # A dead orphan may await the container's init reaper; it cannot run or hold compiler resources.
                try:
                    state = stat.read_text().split()[2]
                except (FileNotFoundError, ProcessLookupError):
                    # A /proc task may disappear after open but before read completes.
                    break
                if state == "Z":
                    break
                time.sleep(0.02)
            else:
                self.fail("timed-out compiler descendant is still running")


if __name__ == "__main__":
    unittest.main()
