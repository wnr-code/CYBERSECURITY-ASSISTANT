import unittest

from run_flutter_analyze import parse_diagnostics


class FlutterAnalyzeParserTests(unittest.TestCase):
    def test_parses_source_diagnostics_with_path_and_location(self):
        output = (
            "Analyzing cybersecurity_assistant...\n"
            "  error • The method isn't defined • lib/main.dart:42:7 • undefined_method\n"
            "  warning • Unused import • test/core_test.dart:3:8 • unused_import\n"
            "2 issues found.\n"
        )

        diagnostics = parse_diagnostics(output)

        self.assertEqual(len(diagnostics), 2)
        self.assertEqual(diagnostics[0].severity, "error")
        self.assertEqual(diagnostics[0].path, "lib/main.dart")
        self.assertEqual(diagnostics[0].line, 42)
        self.assertEqual(diagnostics[0].column, 7)
        self.assertEqual(diagnostics[0].code, "undefined_method")

    def test_ignores_summary_and_non_diagnostic_lines(self):
        self.assertEqual(parse_diagnostics("No issues found!\nAnalyzing...\n"), [])


if __name__ == "__main__":
    unittest.main()
