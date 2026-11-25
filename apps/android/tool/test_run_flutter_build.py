import unittest
from unittest.mock import patch

from local_ai_artifact_gate import GateError
from run_flutter_build import failure_annotations, flutter_build_command, main


class FlutterBuildOutputTests(unittest.TestCase):
    def test_native_build_targets_only_the_supported_arm64_abi(self):
        self.assertEqual(
            flutter_build_command(native_enabled=True),
            ["flutter", "build", "apk", "--debug", "--target-platform=android-arm64"],
        )

    def test_regular_build_keeps_flutter_default_platforms(self):
        self.assertEqual(flutter_build_command(native_enabled=False), ["flutter", "build", "apk", "--debug"])

    def test_failure_output_is_split_into_bounded_annotations(self):
        messages = failure_annotations(1, "x" * 5000)
        self.assertGreater(len(messages), 1)
        self.assertTrue(all(len(message) <= 1800 for message in messages))

    def test_long_failure_output_keeps_the_useful_tail_and_compiler_error(self):
        output = "CMake Error at CMakeLists.txt:11 (message): unsupported ABI\n" + "x" * 9000 + "\nAAPT ERROR: invalid resource"
        messages = failure_annotations(1, output)
        combined = "".join(messages)
        self.assertLessEqual(sum(map(len, messages)), 7200)
        self.assertIn("AAPT ERROR", combined)
        self.assertIn("unsupported ABI", combined)
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
