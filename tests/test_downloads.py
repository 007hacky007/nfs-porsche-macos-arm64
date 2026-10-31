import functools
import hashlib
import io
import tempfile
import unittest
from pathlib import Path

from unittest.mock import patch

from tools import downloads, patches


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

    def test_cache_with_any_accepted_checksum_is_kept(self):
        other = b'original release bytes'
        def offline(*args, **kwargs):
            self.fail('network must not be called for an accepted cache')
        for data in (self.payload, other):
            with self.subTest(data=data):
                cache = self.root / 'patch.zip'
                cache.write_bytes(data)
                self.assertEqual(downloads.fetch('https://example.invalid/patch.zip', self.sha, cache,
                                                 accepted=(hashlib.sha256(other).hexdigest(),), opener=offline), cache)
                self.assertEqual(cache.read_bytes(), data)

    def test_wrong_cache_is_replaced_even_with_accepted_checksums(self):
        cache = self.root / 'patch.zip'
        cache.write_bytes(b'wrong')
        downloads.fetch('https://example.invalid/patch.zip', self.sha, cache, accepted=('0' * 64,),
                        opener=lambda *a, **k: io.BytesIO(self.payload))
        self.assertEqual(cache.read_bytes(), self.payload)

    def test_download_must_match_pinned_checksum_not_alternatives(self):
        cache = self.root / 'patch.zip'
        with self.assertRaisesRegex(ValueError, 'checksum'):
            downloads.fetch('https://example.invalid/patch.zip', self.sha, cache,
                            accepted=(hashlib.sha256(b'other').hexdigest(),), opener=lambda *a, **k: io.BytesIO(b'other'))
        self.assertFalse(cache.exists())

    def test_fetch_patches_keeps_original_combined_patch_cache(self):
        self.assertEqual(downloads.COMBINED_SHA, patches.COMBINED_MIRROR_SHA)
        self.assertEqual(downloads.COMBINED_ORIGINAL_SHA, patches.COMBINED_SHA)
        combined, silent = self.root / 'NFS5-Combined-Patch-v1.1.zip', self.root / 'SilentPatchNFS90s.zip'
        combined.write_bytes(b'original combined')
        silent.write_bytes(b'silent')
        def offline(*args, **kwargs):
            self.fail('the original Combined Patch archive must not be downloaded again')
        with patch.object(downloads, 'COMBINED_ORIGINAL_SHA', hashlib.sha256(b'original combined').hexdigest()), \
                patch.object(downloads, 'SILENT_SHA', hashlib.sha256(b'silent').hexdigest()), \
                patch.object(downloads, 'fetch', functools.partial(downloads.fetch, opener=offline)):
            self.assertEqual(downloads.fetch_patches(self.root), (combined, silent))
        self.assertEqual(combined.read_bytes(), b'original combined')
