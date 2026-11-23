import unittest

from run_flutter_build import failure_annotations


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


if __name__ == "__main__":
    unittest.main()
