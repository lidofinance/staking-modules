"""Exercise fail-closed mutation classification and disposable source handling."""

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location("staking_mutate", Path(__file__).parents[1] / "mutate.py")
mutate = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = mutate
SPEC.loader.exec_module(mutate)


def forge_result(status="Success", reason=None, name="test_witness()", returncode=0):
    output = {"test/unit/formal/Witness.t.sol:Witness": {"test_results": {
        name: {"status": status, "reason": reason}
    }}}
    return mutate.Invocation(returncode, json.dumps(output))


class ClassificationTests(unittest.TestCase):
    def test_real_command_timeout_is_reported(self):
        result = mutate.invoke([sys.executable, "-c", "import time; time.sleep(5)"], Path.cwd(), 1)
        self.assertTrue(result.timed_out)
        self.assertIsNone(result.returncode)

    @unittest.skipUnless(sys.platform.startswith("linux"), "checks Linux descendant process state")
    def test_timeout_kills_descendant_after_parent_has_exited(self):
        # The child keeps inherited stdout open after the command parent exits.
        # Killing only the Popen PID would leave this grandchild running.
        script = ("import os,subprocess,sys; "
                  "child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); "
                  "print(child.pid,flush=True); os._exit(0)")
        result = mutate.invoke([sys.executable, "-c", script], Path.cwd(), 1)
        self.assertTrue(result.timed_out)
        child_pid = int(result.stdout.strip())
        state = Path(f"/proc/{child_pid}/stat")
        for _ in range(20):
            if not state.exists() or state.read_text().split()[2] == "Z":
                break
            time.sleep(0.05)
        else:
            self.fail("command descendant survived timeout cleanup")

    def test_named_assertion_is_killed(self):
        result = forge_result("Failure", "assertion failed: 0 != 10", returncode=1)
        self.assertEqual(mutate.classify(result, "test_witness", "assertion failed")[0], "killed")

    def test_unexpected_runtime_revert_is_inconclusive(self):
        result = forge_result("Failure", "EvmError: Revert", returncode=1)
        self.assertEqual(mutate.classify(result, "test_witness", "assertion failed")[0], "inconclusive")

    def test_baseline_failure_is_never_killed(self):
        result = forge_result("Failure", "assertion failed", returncode=1)
        self.assertEqual(mutate.classify(result, "test_witness", "assertion failed", baseline=True)[0], "inconclusive")

    def test_no_tests_compiler_errors_and_partial_json_are_inconclusive(self):
        examples = ["{}", '{"errors": [{"severity": "error"}]}', '{"suite": {"test_results":', "0 tests matched"]
        for stdout in examples:
            with self.subTest(stdout=stdout):
                self.assertEqual(mutate.classify(mutate.Invocation(1, stdout), "test_witness", "assertion failed")[0], "inconclusive")

    def test_wrong_test_does_not_count(self):
        result = forge_result("Failure", "assertion failed", name="test_someOtherWitness()", returncode=1)
        self.assertEqual(mutate.classify(result, "test_witness", "assertion failed")[0], "inconclusive")

    def test_timeout_is_inconclusive_even_with_partial_failure_output(self):
        result = forge_result("Failure", "assertion failed", returncode=1)
        result.timed_out = True
        self.assertEqual(mutate.classify(result, "test_witness", "assertion failed")[0], "inconclusive")

    def test_compiler_progress_before_complete_json_is_accepted(self):
        result = forge_result()
        result.stdout = "Compiling 12 files with Solc 0.8.33\n" + result.stdout
        self.assertEqual(mutate.classify(result, "test_witness", "assertion failed", baseline=True)[0], "passed")

    def test_truncated_or_extra_output_after_json_is_rejected(self):
        result = forge_result()
        result.stdout += "\nprocess crashed"
        self.assertEqual(mutate.classify(result, "test_witness", "assertion failed")[0], "inconclusive")

    def test_missing_failure_exit_status_is_inconclusive(self):
        result = forge_result("Failure", "assertion failed", returncode=0)
        self.assertEqual(mutate.classify(result, "test_witness", "assertion failed")[0], "inconclusive")


class DisposableExecutionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name) / "repo"
        (self.root / "src").mkdir(parents=True)
        (self.root / "test/unit/formal").mkdir(parents=True)
        self.source = self.root / "src/Target.sol"
        self.source.write_text("contract Target { uint constant X = 1; }\n")
        (self.root / "test/unit/formal/Witness.t.sol").write_text("// synthetic witness\n")
        self.output = self.root / "results"
        self.output.mkdir()
        self.mutation = {
            "name": "change-x", "suite": "Target", "source": "src/Target.sol",
            "find": "X = 1", "replace": "X = 2", "test_path": "test/unit/formal/Witness.t.sol",
            "test": "test_witness", "expected_failure": "assertion failed",
        }

    def test_mutation_only_changes_disposable_copy_and_cleanup_runs(self):
        paths = []

        def runner(command, cwd, timeout):
            paths.append(cwd)
            self.assertNotEqual(cwd, self.root)
            self.assertEqual(self.source.read_text(), "contract Target { uint constant X = 1; }\n")
            if command[1] == "build":
                return mutate.Invocation(0)
            if cwd.name == "baseline":
                self.assertIn("X = 1", (cwd / "src/Target.sol").read_text())
                return forge_result()
            self.assertIn("X = 2", (cwd / "src/Target.sol").read_text())
            return forge_result("Failure", "assertion failed", returncode=1)

        report = mutate.evaluate(self.root, self.mutation, self.output, "forge", "solc", 10, runner)
        self.assertEqual(report["status"], "killed")
        self.assertTrue(all(not path.exists() for path in paths))
        self.assertIn("X = 1", self.source.read_text())

    def test_mutant_compile_failure_is_inconclusive_and_skips_mutant_test(self):
        test_modes = []

        def runner(command, cwd, timeout):
            if command[1] == "build":
                return mutate.Invocation(1, stderr="Compiler error") if cwd.name == "mutant" else mutate.Invocation(0)
            test_modes.append(cwd.name)
            return forge_result()

        report = mutate.evaluate(self.root, self.mutation, self.output, "forge", "solc", 10, runner)
        self.assertEqual(report["status"], "inconclusive")
        self.assertEqual(test_modes, ["baseline"])
        self.assertIn("X = 1", self.source.read_text())

    def test_failing_baseline_prevents_mutant_execution(self):
        modes = []

        def runner(command, cwd, timeout):
            modes.append(cwd.name)
            return mutate.Invocation(0) if command[1] == "build" else forge_result("Failure", "assertion failed", returncode=1)

        report = mutate.evaluate(self.root, self.mutation, self.output, "forge", "solc", 10, runner)
        self.assertEqual(report["status"], "inconclusive")
        self.assertNotIn("mutant", modes)

    def test_ambiguous_replacement_is_rejected_without_execution(self):
        self.source.write_text("X = 1; X = 1;\n")
        def runner(*args):
            self.fail("ambiguous mutation must not execute commands")
        report = mutate.evaluate(self.root, self.mutation, self.output, "forge", "solc", 10, runner)
        self.assertEqual(report["status"], "inconclusive")

    def test_absolute_symlink_parent_cannot_write_to_original_checkout(self):
        actual = self.root / "actual"
        actual.mkdir()
        target = actual / "Target.sol"
        target.write_text("X = 1;\n")
        (self.root / "src/link").symlink_to(actual, target_is_directory=True)
        self.mutation["source"] = "src/link/Target.sol"
        def runner(*args):
            self.fail("symlink source must not execute commands")
        report = mutate.evaluate(self.root, self.mutation, self.output, "forge", "solc", 10, runner)
        self.assertEqual(report["status"], "inconclusive")
        self.assertEqual(target.read_text(), "X = 1;\n")

    def test_new_run_clears_stale_success_before_first_tool_command(self):
        manifest = self.root / "mutations.json"
        manifest.write_text(json.dumps({"schema_version": 1, "mutations": [self.mutation]}))
        report_path = self.output / "report.json"
        report_path.write_text('{"all_killed": true, "complete": true}\n')

        def version_probe(*args):
            report = json.loads(report_path.read_text())
            self.assertFalse(report["all_killed"])
            self.assertFalse(report["complete"])
            self.assertEqual(report["completed_count"], 0)
            return mutate.Invocation(0, "version")

        with mock.patch.object(mutate, "invoke", side_effect=version_probe), \
             mock.patch.object(mutate, "evaluate", side_effect=RuntimeError("fixture failure")):
            exit_code = mutate.main(["--repo-root", str(self.root), "--manifest", str(manifest),
                                     "--output-dir", str(self.output)])
        self.assertEqual(exit_code, 2)
        report = json.loads(report_path.read_text())
        self.assertFalse(report["all_killed"])
        self.assertFalse(report["complete"])
        self.assertEqual(report["error"], "fixture failure")
        self.assertEqual(len(report["run_id"]), 32)

    def test_interrupted_run_persists_incomplete_report(self):
        manifest = self.root / "mutations.json"
        manifest.write_text(json.dumps({"schema_version": 1, "mutations": [self.mutation]}))
        with mock.patch.object(mutate, "invoke", return_value=mutate.Invocation(0, "version")), \
             mock.patch.object(mutate, "evaluate", side_effect=KeyboardInterrupt):
            exit_code = mutate.main(["--repo-root", str(self.root), "--manifest", str(manifest),
                                     "--output-dir", str(self.output)])
        self.assertEqual(exit_code, 130)
        report = json.loads((self.output / "report.json").read_text())
        self.assertFalse(report["all_killed"])
        self.assertFalse(report["complete"])
        self.assertEqual(report["error"], "interrupted")


if __name__ == "__main__":
    unittest.main()
