#!/usr/bin/env python3
"""Exercise the release receipt with small binary fixtures."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('provenance', ROOT / 'Paging/provenance.py')
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'Paging').mkdir()
        (self.root / 'Paging/recipe.json').write_text((ROOT / 'Paging/recipe.json').read_text())
        for patch in (ROOT / 'Paging').glob('*.patch'):
            (self.root / 'Paging' / patch.name).write_bytes(patch.read_bytes())
        (self.root / 'Ghostty.ref').write_text(json.loads((ROOT / 'Paging/recipe.json').read_text())['renderer']+'\n')
        self.binary = self.root / 'BinaryTarget/GhosttyKit.xcframework'
        self.binary.mkdir(parents=True)
        (self.binary / 'libghostty.a').write_bytes(b'archive')
        (self.binary / 'ghostty.h').write_bytes(b'header')
        (self.root / "Sources").mkdir()
        (self.root / "Sources/Wrapper.swift").write_text("// wrapper\n")
        self.module.write(self.root, self.binary, 'fixture-source', False)

    def test_receipt_validates_its_own_recipe_and_binary(self):
        self.module.verify(self.root, self.binary)

    def test_mutated_binary_is_rejected(self):
        (self.binary / 'libghostty.a').write_bytes(b'stale archive')
        with self.assertRaises(ValueError):
            self.module.verify(self.root, self.binary)

    def test_mutated_patch_is_rejected(self):
        (self.root / 'Paging/source-grid.patch').write_bytes(b'changed')
        with self.assertRaises(ValueError):
            self.module.verify(self.root, self.binary)

    def test_unrecorded_binary_is_rejected(self):
        (self.binary / 'extra.a').write_bytes(b'unrecorded')
        with self.assertRaises(ValueError):
            self.module.verify(self.root, self.binary)

    def test_wrapper_refresh_preserves_native_provenance(self):
        previous = json.loads((self.root / 'PAGING-BUILD.json').read_text())
        (self.root / 'Sources/Wrapper.swift').write_text('// updated wrapper\n')
        with self.assertRaises(ValueError):
            self.module.verify(self.root, self.binary)
        self.module.refresh_wrapper(self.root, self.binary, 'updated-wrapper')
        self.module.verify(self.root, self.binary)
        current = json.loads((self.root / 'PAGING-BUILD.json').read_text())
        self.assertEqual(current['sourceCommit'], previous['sourceCommit'])
        self.assertEqual(current['wrapperSourceCommit'], 'updated-wrapper')
        self.assertEqual(current['artifacts'], previous['artifacts'])

    def test_native_toolchains_are_bound_to_every_slice(self):
        recipe = json.loads((self.root / 'Paging/recipe.json').read_text())
        targets = ['aarch64-macos', 'x86_64-macos', 'aarch64-ios',
                   'aarch64-ios-simulator', 'x86_64-ios-simulator']
        directory = self.root / 'targets'
        for target in targets:
            root = directory / target
            (root / 'lib').mkdir(parents=True)
            (root / 'include/libghostty').mkdir(parents=True)
            archive = root / 'lib/libghostty.a'
            header = root / 'include/libghostty/ghostty.h'
            archive.write_bytes(target.encode())
            header.write_bytes(b'header')
            record = dict(target=target, zig=recipe['zig'],
                          archiveSHA256=self.module.sha(archive), headerSHA256=self.module.sha(header))
            (root / 'toolchain.json').write_text(json.dumps(record))
        self.assertEqual(set(self.module.native_toolchains(directory, recipe)), set(targets))
        archive.write_bytes(b'changed after compilation')
        with self.assertRaises(ValueError):
            self.module.native_toolchains(directory, recipe)
        (root / 'toolchain.json').unlink()
        with self.assertRaises(ValueError):
            self.module.native_toolchains(directory, recipe)

    def test_wrong_abi_is_rejected(self):
        path = self.root / 'PAGING-BUILD.json'
        receipt = json.loads(path.read_text())
        receipt['snapshotABI'] = 'other'
        path.write_text(json.dumps(receipt))
        with self.assertRaises(ValueError):
            self.module.verify(self.root, self.binary)


if __name__ == '__main__':
    unittest.main()
