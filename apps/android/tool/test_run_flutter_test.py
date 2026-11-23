import unittest

from run_flutter_test import _escape_command_value, _failure_message


class FlutterTestOutputTests(unittest.TestCase):
    def test_failure_annotation_escapes_workflow_command_characters(self):
        message = _failure_message(1, "line one\nline 100% failed\r\n")

        escaped = _escape_command_value(message)

        self.assertIn("line one%0Aline 100%25 failed%0D%0A", escaped)
        self.assertTrue(escaped.startswith("flutter test failed (exit 1)."))

    def test_failure_annotation_is_bounded(self):
        message = _failure_message(1, "x" * 60_000)

        self.assertLessEqual(len(message), 50_000)
        self.assertIn("output truncated", message)


if __name__ == "__main__":
    unittest.main()
