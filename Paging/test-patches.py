#!/usr/bin/env python3
"""Reject native source drift even after a recipe has been applied once."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PatchTests(unittest.TestCase):
    def test_reused_source_must_match_the_applied_patch_tree(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source'
            source.mkdir()
            (root / 'Script').mkdir()
            (root / 'Paging').mkdir()
            shutil.copy(ROOT / 'Script/apply-patches.sh', root / 'Script')
            def git(*args):
                return subprocess.check_output(['git', '-C', str(source), *args], text=True).strip()
            git('init', '-q')
            git('config', 'user.name', 'Fixture')
            git('config', 'user.email', 'fixture@example.test')
            (source / 'native.zig').write_text('original\n')
            git('add', '.')
            git('commit', '-qm', 'fixture')
            (root / 'Ghostty.ref').write_text(git('rev-parse', 'HEAD') + '\n')
            (root / 'Paging/recipe.json').write_text(json.dumps({'rendererPatches': ['native']}))
            (root / 'Paging/native.patch').write_text('--- a/native.zig\n+++ b/native.zig\n@@ -1 +1 @@\n-original\n+patched\n')
            def apply():
                return subprocess.run(['bash', str(root / 'Script/apply-patches.sh'), str(source)], capture_output=True, text=True)
            self.assertEqual(apply().returncode, 0)
            self.assertEqual(apply().returncode, 0)
            (source / 'native.zig').write_text('modified after applying patches\n')
            self.assertNotEqual(apply().returncode, 0, 'reused native checkout drift must fail')


if __name__ == '__main__':
    unittest.main()
