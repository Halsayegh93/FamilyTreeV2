import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
spec = importlib.util.spec_from_file_location('backup', Path(__file__).resolve().parents[2] / 'scripts/backup-storage.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class StorageBackupTests(unittest.TestCase):
    def test_same_size_corruption_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / 'blob'
            file.write_bytes(b'photo')
            metadata = {'eTag': '"' + hashlib.md5(b'photo').hexdigest() + '"'}
            self.assertTrue(m.matches_etag(file, metadata))
            file.write_bytes(b'wrong')
            self.assertFalse(m.matches_etag(file, metadata))
    def test_multipart_etag_is_not_an_md5(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / 'blob'
            file.write_bytes(b'photo')
            self.assertTrue(m.matches_etag(file, {'eTag':'abcd-2'}))
            self.assertTrue(m.matches_etag(file, None))

if __name__ == '__main__':
    unittest.main()
