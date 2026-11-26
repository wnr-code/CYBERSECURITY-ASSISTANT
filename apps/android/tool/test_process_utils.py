import subprocess
import sys
import unittest

from process_utils import run_bounded


class BoundedProcessTests(unittest.TestCase):
    def test_returns_output_and_exit_status(self):
        result = run_bounded(
            [sys.executable, "-c", "print('finished')"],
            timeout=5,
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "finished")

    def test_timeout_terminates_the_child_process_group(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            run_bounded(
                [sys.executable, "-c", "import time; print('started', flush=True); time.sleep(10)"],
                timeout=0.1,
                text=True,
                capture_output=True,
            )

    def test_check_raises_with_captured_diagnostics(self):
        with self.assertRaises(subprocess.CalledProcessError) as context:
            run_bounded(
                [sys.executable, "-c", "import sys; print('bad', file=sys.stderr); sys.exit(3)"],
                timeout=5,
                text=True,
                capture_output=True,
                check=True,
            )
        self.assertEqual(context.exception.returncode, 3)
        self.assertIn("bad", context.exception.stderr)


if __name__ == "__main__":
    unittest.main()
