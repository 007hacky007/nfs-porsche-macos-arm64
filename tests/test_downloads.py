import hashlib
import tempfile
import unittest
from pathlib import Path

from tools import downloads


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.payload = b'verified patch bytes'
        self.sha = hashlib.sha256(self.payload).hexdigest()

    def test_valid_cache_is_used_without_contacting_network(self):
        cache = self.root / 'patch.zip'
        cache.write_bytes(self.payload)
        def offline(*args, **kwargs):
            self.fail('network must not be called for a verified cache hit')
        self.assertEqual(downloads.fetch('https://example.invalid/patch.zip', self.sha, cache, opener=offline), cache)

    def test_rejects_wrong_download_and_never_commits_partial_file(self):
        import io
        cache = self.root / 'patch.zip'
        with self.assertRaisesRegex(ValueError, 'checksum'):
            downloads.fetch('https://example.invalid/patch.zip', self.sha, cache,
                            opener=lambda *a, **k: io.BytesIO(b'wrong data'))
        self.assertFalse(cache.exists())
        self.assertEqual(list(self.root.iterdir()), [])

    def test_interrupted_download_preserves_existing_cache(self):
        cache = self.root / 'patch.zip'
        cache.write_bytes(b'old invalid cache')
        def offline(*args, **kwargs):
            raise OSError('offline')
        with self.assertRaisesRegex(OSError, 'offline'):
            downloads.fetch('https://example.invalid/patch.zip', self.sha, cache, opener=offline)
        self.assertEqual(cache.read_bytes(), b'old invalid cache')

    def test_replaces_corrupt_cache_only_after_verified_download(self):
        import io
        cache = self.root / 'patch.zip'
        cache.write_bytes(b'corrupt')
        downloads.fetch('https://example.invalid/patch.zip', self.sha, cache,
                        opener=lambda *a, **k: io.BytesIO(self.payload))
        self.assertEqual(cache.read_bytes(), self.payload)

    def test_rejects_non_https_sources(self):
        with self.assertRaisesRegex(ValueError, 'HTTPS'):
            downloads.fetch('http://example.invalid/patch.zip', self.sha, self.root / 'patch.zip')
