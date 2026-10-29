#!/usr/bin/env python3
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest


class PackagingTests(unittest.TestCase):
    def test_archive_ignores_filesystem_timestamps_and_modes(self):
        spec = importlib.util.spec_from_file_location('pack', Path(__file__).with_name('pack-xcframework.py'))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'GhosttyKit.xcframework'
            source.mkdir()
            binary = source / 'libghostty.a'
            binary.write_bytes(b'native archive')
            module.pack(source, root / 'first.zip')
            os.utime(binary, (1700000000, 1700000000))
            binary.chmod(0o755)
            module.pack(source, root / 'second.zip')
            self.assertEqual((root / 'first.zip').read_bytes(), (root / 'second.zip').read_bytes())


if __name__ == '__main__':
    unittest.main()
