#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))


class ReuseTests(unittest.TestCase):
    def test_only_wrapper_and_probe_changes_can_reuse_native_artifacts(self):
        spec = importlib.util.spec_from_file_location('reuse', Path(__file__).with_name('verify-reuse.py'))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'Paging').mkdir()
            (root / 'Ghostty.ref').write_text('a' * 40 + '\n')
            (root / 'Paging/recipe.json').write_text(json.dumps({'renderer': 'a' * 40, 'rendererPatches': ['native']}))
            patch = root / 'Paging/native.patch'
            patch.write_text('native patch')
            (root / 'Sources').mkdir()
            wrapper = root / 'Sources/Wrapper.swift'
            wrapper.write_text('// wrapper')
            def git(*args):
                return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()
            git('init', '-q')
            git('config', 'user.name', 'Fixture')
            git('config', 'user.email', 'fixture@example.test')
            git('add', '.')
            git('commit', '-qm', 'native inputs')
            source = git('rev-parse', 'HEAD')
            module.verify(root, source)
            wrapper.write_text('// updated wrapper')
            module.verify(root, source)
            patch.write_text('different native patch')
            with self.assertRaises(ValueError):
                module.verify(root, source)


if __name__ == '__main__':
    unittest.main()
