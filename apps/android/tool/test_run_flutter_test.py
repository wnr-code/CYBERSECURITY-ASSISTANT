import unittest

from run_flutter_test import _escape_command_value, _failure_messages, _parse_test_summary


class FlutterTestOutputTests(unittest.TestCase):
    def test_parses_passed_and_failed_test_counts_from_expanded_reporter(self):
        self.assertEqual(_parse_test_summary('00:04 +72: All tests passed!\n'), (72, 0))
        self.assertEqual(_parse_test_summary('00:04 +70 -2: Some tests failed.\n'), (70, 2))
        self.assertIsNone(_parse_test_summary('Test output format changed'))

    def test_failure_annotations_escape_workflow_command_characters(self):
        message = _failure_messages(1, "line one\nline 100% failed\r\n")[0]

        escaped = _escape_command_value(message)

        self.assertIn("line one%0Aline 100%25 failed%0D%0A", escaped)
        self.assertTrue(escaped.startswith("Flutter test failure output 1/1."))

    def test_failure_annotations_are_split_into_bounded_chunks(self):
        messages = _failure_messages(1, "x" * 60_000)

        self.assertGreater(len(messages), 1)
        self.assertTrue(all(len(message) <= 2_100 for message in messages))
        self.assertIn("output truncated", "".join(messages))


if __name__ == "__main__":
    unittest.main()
