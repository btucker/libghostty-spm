#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / 'Script/finalize-release.py'
spec = importlib.util.spec_from_file_location('publication', MODULE)
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)

class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.run = {'status': 'completed', 'conclusion': 'success', 'head_sha': 'a' * 40,
                    'repository': {'full_name': 'btucker/libghostty-spm'},
                    'path': '.github/workflows/build.yml'}
        self.metadata = {'kind': 'native', 'tag': 'upstream.8af6897c0afc-2',
                         'commit': 'a' * 40, 'workflowCommit': 'a' * 40}

    def test_successful_native_handoff(self):
        publication.validate_handoff(self.run, self.metadata)

    def test_rejects_wrong_repository_failed_or_running_workflow(self):
        for key, value in [('status', 'in_progress'), ('conclusion', 'failure'),
                           ('path', '.github/workflows/pr.yml'),
                           ('repository', {'full_name': 'other/libghostty-spm'})]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                publication.validate_handoff({**self.run, key: value}, self.metadata)

    def test_rejects_mismatched_native_commit(self):
        with self.assertRaises(ValueError):
            publication.validate_handoff(self.run, {**self.metadata, 'commit': 'b' * 40})

    def test_package_requires_semver_and_matching_workflow(self):
        run = {**self.run, 'path': '.github/workflows/release.yml'}
        metadata = {**self.metadata, 'kind': 'package', 'tag': '3.0.2026102901', 'commit': 'b' * 40}
        publication.validate_handoff(run, metadata)
        with self.assertRaises(ValueError):
            publication.validate_handoff(run, {**metadata, 'tag': 'main'})
        with self.assertRaises(ValueError):
            publication.validate_handoff(run, {**metadata, 'workflowCommit': 'c' * 40})

    def test_native_build_one_uses_bare_storage_tag(self):
        publication.validate_handoff(self.run, {**self.metadata, 'tag': 'upstream.8af6897c0afc'})
        manifest = 'url: "https://github.com/btucker/libghostty-spm/releases/download/upstream.8af6897c0afc/GhosttyKit.xcframework.zip", checksum: "' + 'c' * 64 + '"'
        self.assertEqual(publication.manifest_binding(manifest)[0], 'upstream.8af6897c0afc')

    def test_existing_tag_mismatch_is_rejected_before_publication(self):
        references = [{'ref': 'refs/tags/' + self.metadata['tag'],
                       'object': {'type': 'commit', 'sha': 'b' * 40}}]
        with patch.object(publication, 'api', return_value=references), patch.object(publication, 'gh') as gh:
            with self.assertRaises(ValueError):
                publication.ensure_tag(self.metadata['tag'], 'a' * 40)
            gh.assert_not_called()

    def test_absent_tag_is_created_atomically_at_tested_commit(self):
        with patch.object(publication, 'api', return_value=[]), patch.object(publication, 'gh') as gh:
            publication.ensure_tag(self.metadata['tag'], 'a' * 40)
            arguments = gh.call_args.args
            self.assertIn('POST', arguments)
            self.assertIn('ref=refs/tags/' + self.metadata['tag'], arguments)
            self.assertIn('sha=' + 'a' * 40, arguments)

    def test_manifest_binds_fork_storage_asset_and_checksum(self):
        manifest = 'url: "https://github.com/btucker/libghostty-spm/releases/download/upstream.8af6897c0afc-2/GhosttyKit.xcframework.zip", checksum: "' + 'c' * 64 + '"'
        self.assertEqual(publication.manifest_binding(manifest), ('upstream.8af6897c0afc-2', 'c' * 64))
        with self.assertRaises(ValueError):
            publication.manifest_binding(manifest.replace('btucker/', 'other/'))

    def test_native_checksum_inventory_is_complete(self):
        import hashlib
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('GhosttyKit.xcframework.zip', 'PAGING-BUILD.json'):
                (root/name).write_bytes(name.encode())
            lines = [hashlib.sha256((root/name).read_bytes()).hexdigest() + '  ' + name
                     for name in ('GhosttyKit.xcframework.zip', 'PAGING-BUILD.json')]
            (root/'SHA256SUMS').write_text('\n'.join(lines) + '\n')
            publication.verify_checksums(root)
            (root/'SHA256SUMS').write_text(lines[0] + '\n')
            with self.assertRaises(ValueError):
                publication.verify_checksums(root)
            (root/'SHA256SUMS').write_text('\n'.join(lines) + '\n')
            (root/'PAGING-BUILD.json').write_text('tampered')
            with self.assertRaises(ValueError):
                publication.verify_checksums(root)

if __name__ == '__main__':
    unittest.main()
