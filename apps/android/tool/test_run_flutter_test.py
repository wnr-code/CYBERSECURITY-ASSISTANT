import base64
import io
import json
import os
import tempfile
import unittest
import zlib
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch

from run_flutter_test import _compressed_annotation_chunks, _parse_test_summary, _redact_output, main


class FlutterTestOutputTests(unittest.TestCase):
    def test_parses_passed_and_failed_test_counts_from_expanded_reporter(self):
        self.assertEqual(_parse_test_summary('00:04 +72: All tests passed!\n'), (72, 0))
        self.assertEqual(_parse_test_summary('00:04 +70 -2: Some tests failed.\n'), (70, 2))
        self.assertIsNone(_parse_test_summary('Test output format changed'))

    def test_compressed_annotation_chunks_round_trip_without_exceeding_message_bound(self):
        output = ('test failed: token=synthetic-secret\\n' * 5000)
        chunks = _compressed_annotation_chunks(output)
        self.assertTrue(chunks)
        self.assertTrue(all(len(chunk) <= 2800 for chunk in chunks))
        decoded = zlib.decompress(base64.urlsafe_b64decode(''.join(chunks))).decode('utf-8')
        self.assertEqual(decoded, output)

    def test_redacts_common_secrets_without_dropping_diagnostic_lines(self):
        output = (
            'Expected: safe\n'
            'Actual: token=fixture-token\n'
            'Authorization: Bearer fixture-bearer\n'
            'Cookie: session=fixture-cookie\n'
            'github_token=fixture-github-token\n'
            'Unlabelled credential: github_pat_ABCDEFGHIJKLMNOPQRSTUVWXYZ123456789\n'
            'URL: https://alice:fixture-password@example.test/path?access_token=fixture-query\n'
            'Traceback: test_fixture.dart:42\n'
        )

        redacted = _redact_output(output)

        self.assertIn('Expected: safe', redacted)
        self.assertIn('Traceback: test_fixture.dart:42', redacted)
        for secret in (
            'fixture-token',
            'fixture-bearer',
            'fixture-cookie',
            'fixture-github-token',
            'github_pat_ABCDEFGHIJKLMNOPQRSTUVWXYZ123456789',
            'fixture-password',
            'fixture-query',
        ):
            self.assertNotIn(secret, redacted)
        self.assertIn('token=[REDACTED]', redacted)
        self.assertIn('Authorization: [REDACTED]', redacted)

    def test_redacts_json_credential_variants_and_preserves_nested_json(self):
        output = (
            '{ "api_key" : "synthetic-api-underscore", "api-key":"synthetic-api-hyphen", '
            '"x-api-key" : "synthetic-x-api", "TOKEN":"synthetic-token", '
            '"password" : "synthetic-password", "ACCESS_TOKEN" : "synthetic-access", '
            '"refresh_token":"synthetic-refresh", "Client_Secret" : "synthetic-client", '
            '"authorization" : "synthetic-auth", "cookie":"synthetic-cookie", '
            '"set-cookie" : null, "proxy-authorization":false, '
            '"github_token" : "synthetic-github", "simple_token":12345, '
            '"headers":{"X-API-Key":"synthetic-nested-api","safe":"nested-keep"}, '
            '"serialized":"{\\"cookie\\":\\"synthetic-embedded-cookie\\"}", '
            '"tool_id":"dns_lookup", "run_id":"run-123", "model_name":"model-safe", '
            '"token_count":"ordinary-count", "message" : "ordinary text", "ok":true }'
        )

        redacted = _redact_output(output)
        parsed = json.loads(redacted)

        for key in (
            'api_key', 'api-key', 'x-api-key', 'TOKEN', 'password', 'ACCESS_TOKEN',
            'refresh_token', 'Client_Secret', 'authorization', 'cookie', 'set-cookie',
            'proxy-authorization', 'github_token', 'simple_token',
        ):
            self.assertEqual(parsed[key], '[REDACTED]')
        self.assertEqual(parsed['headers'], {'X-API-Key': '[REDACTED]', 'safe': 'nested-keep'})
        self.assertEqual(json.loads(parsed['serialized']), {'cookie': '[REDACTED]'})
        self.assertEqual(parsed['tool_id'], 'dns_lookup')
        self.assertEqual(parsed['run_id'], 'run-123')
        self.assertEqual(parsed['model_name'], 'model-safe')
        self.assertEqual(parsed['token_count'], 'ordinary-count')
        self.assertEqual(parsed['message'], 'ordinary text')
        self.assertIs(parsed['ok'], True)
        for secret in (
            'synthetic-api-underscore', 'synthetic-api-hyphen', 'synthetic-x-api',
            'synthetic-token', 'synthetic-password', 'synthetic-access',
            'synthetic-refresh', 'synthetic-client', 'synthetic-auth',
            'synthetic-cookie', 'synthetic-github', '12345', 'synthetic-nested-api', 'synthetic-embedded-cookie',
        ):
            self.assertNotIn(secret, redacted)

    def test_main_redacts_json_on_stdout_and_stderr_before_console_and_evidence(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            evidence = Path(temp_dir) / 'evidence'
            stdout_json = (
                '{"api_key" : "synthetic-stdout-secret", "cookie":"synthetic-cookie-secret", '
                '"message":"stdout-safe"}\n'
            )
            stderr_json = (
                '{ "proxy-authorization" : "synthetic-proxy-secret", '
                '"github_token":"synthetic-github-secret", "password": false }\n'
            )
            completed = CompletedProcess(args=['flutter'], returncode=0, stdout=stdout_json, stderr=stderr_json)
            console_out = io.StringIO()
            console_err = io.StringIO()
            with patch.dict(os.environ, {'FLUTTER_TEST_EVIDENCE_DIR': str(evidence)}), \
                    patch('run_flutter_test.subprocess.run', return_value=completed), \
                    redirect_stdout(console_out), redirect_stderr(console_err):
                exit_code = main()

            saved_stdout = (evidence / 'stdout.log').read_text()
            saved_stderr = (evidence / 'stderr.log').read_text()
            self.assertEqual(exit_code, 0)
            self.assertEqual(
                json.loads(saved_stdout),
                {'api_key': '[REDACTED]', 'cookie': '[REDACTED]', 'message': 'stdout-safe'},
            )
            self.assertEqual(
                json.loads(saved_stderr),
                {
                    'proxy-authorization': '[REDACTED]',
                    'github_token': '[REDACTED]',
                    'password': '[REDACTED]',
                },
            )
            all_console_and_evidence = console_out.getvalue() + console_err.getvalue() + saved_stdout + saved_stderr
            for secret in (
                'synthetic-stdout-secret', 'synthetic-cookie-secret',
                'synthetic-proxy-secret', 'synthetic-github-secret',
            ):
                self.assertNotIn(secret, all_console_and_evidence)
            self.assertIn('stdout-safe', console_out.getvalue())
            self.assertIn('synthetic-stdout-secret', stdout_json)
            self.assertIn('synthetic-proxy-secret', stderr_json)

    def test_main_saves_successful_expanded_output_and_returns_zero(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            evidence = Path(temp_dir) / 'evidence'
            completed = CompletedProcess(
                args=['flutter'],
                returncode=0,
                stdout='00:04 +72: All tests passed!\n',
                stderr='flutter diagnostic notice\n',
            )
            stdout = io.StringIO()
            stderr = io.StringIO()
            with patch.dict(os.environ, {'FLUTTER_TEST_EVIDENCE_DIR': str(evidence)}), \
                    patch('run_flutter_test.subprocess.run', return_value=completed) as run_flutter, \
                    redirect_stdout(stdout), redirect_stderr(stderr):
                exit_code = main()

            run_flutter.assert_called_once_with(
                ['flutter', 'test', '--reporter=expanded'],
                check=False,
                capture_output=True,
                text=True,
                encoding='utf-8',
                errors='replace',
            )
            self.assertEqual(exit_code, 0)
            self.assertEqual((evidence / 'stdout.log').read_text(), completed.stdout)
            self.assertEqual((evidence / 'stderr.log').read_text(), completed.stderr)
            metadata = (evidence / 'metadata.txt').read_text()
            self.assertIn('flutter_exit_code=0', metadata)
            self.assertIn('tests_passed=72', metadata)
            self.assertIn('tests_failed=0', metadata)
            self.assertIn(completed.stdout, stdout.getvalue())
            self.assertIn(completed.stderr, stderr.getvalue())

    def test_main_preserves_failure_exit_and_full_sanitized_diagnostics(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            evidence = Path(temp_dir) / 'evidence'
            failed_stdout = (
                '00:04 +70 -2: Some tests failed.\n'
                'test/a_test.dart: failing test [E]\n'
                'Expected: expected fixture\nActual: token=fixture-token\n'
                'Stack trace: test/a_test.dart:42\n'
            )
            failed_stderr = 'Authorization: Bearer fixture-bearer\n'
            completed = CompletedProcess(args=['flutter'], returncode=17, stdout=failed_stdout, stderr=failed_stderr)
            stdout = io.StringIO()
            stderr = io.StringIO()
            with patch.dict(os.environ, {'FLUTTER_TEST_EVIDENCE_DIR': str(evidence)}), \
                    patch('run_flutter_test.subprocess.run', return_value=completed), \
                    redirect_stdout(stdout), redirect_stderr(stderr):
                exit_code = main()

            self.assertEqual(exit_code, 17)
            saved_stdout = (evidence / 'stdout.log').read_text()
            saved_stderr = (evidence / 'stderr.log').read_text()
            for detail in ('failing test [E]', 'Expected: expected fixture', 'Stack trace: test/a_test.dart:42'):
                self.assertIn(detail, saved_stdout)
                self.assertIn(detail, stdout.getvalue())
            for secret in ('fixture-token', 'fixture-bearer'):
                self.assertNotIn(secret, saved_stdout + saved_stderr + stdout.getvalue() + stderr.getvalue())
            metadata = (evidence / 'metadata.txt').read_text()
            self.assertIn('flutter_exit_code=17', metadata)
            self.assertIn('tests_passed=70', metadata)
            self.assertIn('tests_failed=2', metadata)
            self.assertIn('flutter test exited with code 17', stdout.getvalue())
            self.assertIn('::error title=Flutter test log 1 of 1::', stdout.getvalue())
            self.assertIn('failing test [E]', stdout.getvalue())
            self.assertIn('Actual: token=[REDACTED]', stdout.getvalue())
            chunks = [
                line.split('::', 2)[-1]
                for line in stdout.getvalue().splitlines()
                if 'title=Flutter test log ' in line
            ]
            decoded_log = zlib.decompress(base64.urlsafe_b64decode(''.join(chunks))).decode('utf-8')
            self.assertIn('failing test [E]', decoded_log)
            self.assertIn('Actual: token=[REDACTED]', decoded_log)
            self.assertNotIn('fixture-token', decoded_log)


if __name__ == '__main__':
    unittest.main()
