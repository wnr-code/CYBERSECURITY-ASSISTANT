import hashlib
import io
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import prepare_llama_cpp_source as source


class _Response:
    status = 200

    def __init__(self, url, payload):
        self.url = url
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return None

    def geturl(self):
        return self.url

    def read(self, _limit):
        return self.payload


class _Opener:
    def __init__(self, response):
        self.response = response
        self.request = None

    def open(self, request, timeout):
        self.request = request
        self.timeout = timeout
        return self.response


def _source_archive(commit):
    root = f"llama.cpp-{commit}"
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz") as archive:
        for name, content in (
            (f"{root}/CMakeLists.txt", b"project(llama.cpp)"),
            (f"{root}/include/llama.h", b"#pragma once"),
        ):
            info = tarfile.TarInfo(name)
            info.size = len(content)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(content))
    return output.getvalue()


class PrepareLlamaCppSourceTests(unittest.TestCase):
    def test_fetches_only_pinned_official_source_and_extracts_after_hash_validation(self):
        payload = _source_archive(source.SOURCE_COMMIT)
        opener = _Opener(_Response(source.SOURCE_URL, payload))
        with tempfile.TemporaryDirectory() as temporary, patch.object(source, "SOURCE_SHA256", hashlib.sha256(payload).hexdigest()):
            project = Path(temporary)
            prepared = source.prepare_source(project, opener=opener)
            self.assertEqual(opener.request.full_url, source.SOURCE_URL)
            self.assertEqual(prepared, project / ".dart_tool/llama.cpp")
            self.assertEqual((prepared / ".csa-source-lock").read_text().strip(), source.SOURCE_COMMIT)
            self.assertTrue((prepared / "include/llama.h").is_file())
            (prepared / "CMakeLists.txt").write_text("tampered", encoding="utf-8")
            self.assertEqual(source.prepare_source(project, opener=opener), prepared)
            self.assertEqual((prepared / "CMakeLists.txt").read_bytes(), b"project(llama.cpp)")

    def test_hash_mismatch_does_not_extract_source(self):
        payload = _source_archive(source.SOURCE_COMMIT)
        opener = _Opener(_Response(source.SOURCE_URL, payload))
        with tempfile.TemporaryDirectory() as temporary, patch.object(source, "SOURCE_SHA256", "0" * 64):
            with self.assertRaisesRegex(source.SourceError, "SHA-256 mismatch"):
                source.prepare_source(Path(temporary), opener=opener)
            self.assertFalse((Path(temporary) / ".dart_tool/llama.cpp").exists())

    def test_off_origin_source_response_is_rejected(self):
        payload = _source_archive(source.SOURCE_COMMIT)
        opener = _Opener(_Response("https://example.invalid/redirect", payload))
        with tempfile.TemporaryDirectory() as temporary, patch.object(source, "SOURCE_SHA256", hashlib.sha256(payload).hexdigest()):
            with self.assertRaisesRegex(source.SourceError, "exact pinned HTTPS URL"):
                source.prepare_source(Path(temporary), opener=opener)


if __name__ == "__main__":
    unittest.main()
