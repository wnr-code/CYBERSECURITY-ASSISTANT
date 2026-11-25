import unittest
from unittest.mock import patch

from local_ai_artifact_gate import GateError
from run_flutter_build import failure_annotations, main


class FlutterBuildOutputTests(unittest.TestCase):
    def test_failure_output_is_split_into_bounded_annotations(self):
        messages = failure_annotations(1, "x" * 5000)
        self.assertGreater(len(messages), 1)
        self.assertTrue(all(len(message) <= 1800 for message in messages))

    def test_long_failure_output_keeps_the_useful_tail(self):
        output = "early output\n" + "x" * 9000 + "\nAAPT ERROR: invalid resource"
        messages = failure_annotations(1, output)
        self.assertLessEqual(sum(map(len, messages)), 7200)
        self.assertIn("AAPT ERROR", messages[-1])
        self.assertTrue(messages[0].startswith("flutter build apk --debug failed"))

    @patch("run_flutter_build.subprocess.run")
    @patch("run_flutter_build.preflight_runtime_build", side_effect=GateError("runtime artifact unverified"))
    def test_runtime_artifact_gate_blocks_flutter_build(self, preflight, flutter_run):
        self.assertEqual(main(), 2)
        preflight.assert_called_once()
        flutter_run.assert_not_called()

    @patch("run_flutter_build.audit_apk_cpu_only", side_effect=GateError("Vulkan backend found"))
    @patch("run_flutter_build.subprocess.run", return_value=type("Result", (), {"returncode": 0, "stdout": "built", "stderr": ""})())
    @patch("run_flutter_build.preflight_runtime_build", return_value=True)
    def test_post_build_cpu_apk_audit_must_pass(self, preflight, flutter_run, apk_audit):
        self.assertEqual(main(), 2)
        flutter_run.assert_called_once()
        apk_audit.assert_called_once()


if __name__ == "__main__":
    unittest.main()
