import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from capture_android_cold_start import _startup_markers, main


class ColdStartMarkerTests(unittest.TestCase):
    def test_failure_always_writes_a_diagnostic_file(self):
        with TemporaryDirectory() as temporary:
            output_dir = Path(temporary) / "api-30"
            result = main([
                "--apk", str(Path(temporary) / "missing.apk"),
                "--output-dir", str(output_dir),
                "--api-level", "30",
            ])
            self.assertEqual(result, 1)
            diagnostics = (output_dir / "failure-diagnostics.txt").read_text()
            self.assertIn("APK not found", diagnostics)
            self.assertIn("API 30", diagnostics)

    def test_extracts_dart_stage_times_and_native_activity_markers(self):
        lines = "\n".join(
            [
                "1766000000.100 123 123 I AppStartup: native:activity-onCreate",
                "1766000000.110 123 123 I AppStartup: native:splash-installed",
                "1766000000.300 123 123 I flutter: [APP_STARTUP] dart-main +18ms",
                "1766000000.700 123 123 I flutter: [APP_STARTUP] animated-splash-first-frame +410ms",
                "1766000001.000 123 123 I flutter: [APP_STARTUP] dashboard-first-frame +720ms",
            ]
        )

        markers = _startup_markers(lines)

        self.assertEqual(
            [marker["event"] for marker in markers],
            [
                "native:activity-onCreate",
                "native:splash-installed",
                "dart-main",
                "animated-splash-first-frame",
                "dashboard-first-frame",
            ],
        )
        self.assertEqual(markers[2]["elapsed_ms"], 18)


if __name__ == "__main__":
    unittest.main()
