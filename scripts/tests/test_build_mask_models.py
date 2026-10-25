"""Model download integrity checks; no model tools or network required."""
import hashlib
import http.client
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location(
    'build_mask_models', Path(__file__).resolve().parents[1] / 'build-mask-models.py'
)
MODELS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODELS)


class ShortReads(io.BytesIO):
    def read(self, amount=-1):
        return super().read(min(amount, 3))


class ModelDownloadTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.destination = Path(self.directory.name) / 'model.bin'
        self.payload = b'original synthetic model bytes'
        self.digest = hashlib.sha256(self.payload).hexdigest()

    def fetch(self):
        MODELS.fetch('https://example.invalid/model', self.destination, len(self.payload), self.digest)

    def test_partial_reads_are_assembled_and_verified(self):
        with mock.patch.object(MODELS.urllib.request, 'urlopen', return_value=ShortReads(self.payload)) as opening:
            self.fetch()
        self.assertEqual(self.destination.read_bytes(), self.payload)
        self.assertTrue(opening.call_args.args[0].full_url.endswith('?download=true'))
        self.assertEqual(opening.call_args.args[0].get_header('Accept-encoding'), 'identity')

    def test_invalid_response_is_retried_without_changing_the_pin(self):
        with mock.patch.object(MODELS.urllib.request, 'urlopen', side_effect=[io.BytesIO(b'not a model'), io.BytesIO(self.payload)]) as opening:
            with mock.patch.object(MODELS.time, 'sleep'):
                self.fetch()
        self.assertEqual(opening.call_count, 2)
        self.assertEqual(self.destination.read_bytes(), self.payload)

    def test_corrupt_responses_do_not_replace_an_existing_file(self):
        self.destination.write_bytes(b'previous verified file')
        with mock.patch.object(MODELS.urllib.request, 'urlopen', side_effect=lambda *args, **kwargs: io.BytesIO(b'corrupt')) as opening:
            with mock.patch.object(MODELS.time, 'sleep'):
                with self.assertRaisesRegex(ValueError, 'received 7 bytes / SHA-256'):
                    self.fetch()
        self.assertEqual(opening.call_count, 3)
        self.assertEqual(self.destination.read_bytes(), b'previous verified file')

    def test_oversized_response_is_rejected_with_a_bounded_read(self):
        def response(*args, **kwargs):
            return io.BytesIO(self.payload + b'extra bytes')

        with mock.patch.object(MODELS.urllib.request, 'urlopen', side_effect=response):
            with mock.patch.object(MODELS.time, 'sleep'):
                with self.assertRaisesRegex(ValueError, f'received {len(self.payload) + 1} bytes'):
                    self.fetch()
        self.assertFalse(self.destination.exists())

    def test_interrupted_http_transfer_is_retried(self):
        with mock.patch.object(MODELS.urllib.request, 'urlopen', side_effect=[http.client.IncompleteRead(b'partial'), io.BytesIO(self.payload)]):
            with mock.patch.object(MODELS.time, 'sleep'):
                self.fetch()
        self.assertEqual(self.destination.read_bytes(), self.payload)

    def test_same_size_corruption_is_rejected(self):
        with mock.patch.object(MODELS.urllib.request, 'urlopen', side_effect=lambda *args, **kwargs: io.BytesIO(b'x' * len(self.payload))):
            with mock.patch.object(MODELS.time, 'sleep'):
                with self.assertRaisesRegex(ValueError, 'SHA-256'):
                    self.fetch()
        self.assertFalse(self.destination.exists())


if __name__ == '__main__':
    unittest.main()
