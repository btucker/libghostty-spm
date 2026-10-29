#!/usr/bin/env python3
"""Publish a successful workflow's tested handoff with local GitHub authentication.

Use when publishing a branch that modifies workflows: GitHub's GITHUB_TOKEN
cannot publish those commits. No local credential is stored in the repository.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

REPOSITORY = 'btucker/libghostty-spm'
ASSET = 'GhosttyKit.xcframework.zip'


def gh(*arguments):
    return subprocess.check_output(['gh', *arguments], text=True).strip()


def api(path):
    return json.loads(gh('api', f'repos/{REPOSITORY}/{path}'))


def validate_handoff(run, metadata):
    kind = metadata.get('kind')
    workflow = {'native': 'build.yml', 'package': 'release.yml'}.get(kind)
    if (run.get('repository', {}).get('full_name') != REPOSITORY
            or run.get('status') != 'completed' or run.get('conclusion') != 'success'
            or run.get('path') != f'.github/workflows/{workflow}'
            or metadata.get('workflowCommit') != run.get('head_sha')
            or not re.fullmatch('[0-9a-f]{40}', metadata.get('commit', ''))):
        raise ValueError('Handoff must belong to a successful matching publication workflow')
    pattern = r'upstream\.[0-9a-f]{12}-[0-9]+' if kind == 'native' else r'[0-9]+\.[0-9]+\.[0-9]+'
    if not re.fullmatch(pattern, metadata.get('tag', '')):
        raise ValueError('Invalid release tag')
    if kind == 'native' and metadata['commit'] != run['head_sha']:
        raise ValueError('Native publication must target its tested workflow commit')


def verify_checksums(root):
    expected = {ASSET, 'PAGING-BUILD.json'}
    lines = (root/'SHA256SUMS').read_text().splitlines()
    names = set()
    for line in lines:
        match = re.fullmatch(r'([0-9a-f]{64})  (.+)', line)
        if not match or match[2] not in expected or match[2] in names:
            raise ValueError('Invalid native checksum inventory')
        names.add(match[2])
        if hashlib.sha256((root/match[2]).read_bytes()).hexdigest() != match[1]:
            raise ValueError(f'Checksum mismatch: {match[2]}')
    if names != expected:
        raise ValueError('Incomplete native checksum inventory')


def manifest_binding(manifest):
    url = re.search(r'url:\s*"https://github.com/btucker/libghostty-spm/releases/download/(upstream\.[0-9a-f]{12}-[0-9]+)/GhosttyKit\.xcframework\.zip"', manifest)
    checksum = re.search(r'checksum:\s*"([0-9a-f]{64})"', manifest)
    if not url or not checksum:
        raise ValueError('Manifest must pin a checksummed fork storage asset')
    return url[1], checksum[1]


def tracked_file(commit, name):
    response = api(f'contents/{name}?ref={commit}')
    return base64.b64decode(response['content'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run_id', type=int)
    args = parser.parse_args()
    run = api(f'actions/runs/{args.run_id}')
    with tempfile.TemporaryDirectory(prefix='libghostty-publication-') as directory:
        root = Path(directory)
        gh('run', 'download', str(args.run_id), '-R', REPOSITORY,
           '--name', 'publication', '--dir', str(root))
        metadata = json.loads((root/'release.json').read_text())
        validate_handoff(run, metadata)
        tag, commit = metadata['tag'], metadata['commit']
        # Never update a published release or replace an asset.
        existing = api('releases?per_page=100')
        if any(release['tag_name'] == tag for release in existing):
            raise ValueError(f'Release already exists: {tag}')
        assets = []
        if metadata['kind'] == 'native':
            verify_checksums(root)
            receipt = json.loads((root/'PAGING-BUILD.json').read_text())
            if receipt['wrapperSourceCommit'] != run['head_sha']:
                raise ValueError('Receipt wrapper commit does not match the tested workflow')
            assets = [str(root/name) for name in (ASSET, 'PAGING-BUILD.json', 'SHA256SUMS')]
            notes = f'Pinned Graftty paging renderer.\n\nValidated workflow: {run["html_url"]}\n\nUniversal macOS, arm64 iOS, universal iOS Simulator. Checksums and per-slice provenance are attached.'
        else:
            generated = api(f'commits/{commit}')
            if commit != run['head_sha'] and [p['sha'] for p in generated['parents']] != [run['head_sha']]:
                raise ValueError('Package commit must be the tested workflow commit or its generated child')
            for name in ('Package.swift', 'PAGING-BUILD.json'):
                if tracked_file(commit, name) != (root/name).read_bytes():
                    raise ValueError(f'Generated package file differs from tested handoff: {name}')
            storage, checksum = manifest_binding((root/'Package.swift').read_text())
            release = api(f'releases/tags/{storage}')
            native = next(asset for asset in release['assets'] if asset['name'] == ASSET)
            if native['digest'] != f'sha256:{checksum}':
                raise ValueError('Published native asset does not match the package checksum')
            notes = f'GhosttyKit {tag}\n\nValidated workflow: {run["html_url"]}\n\nNative artifacts: https://github.com/{REPOSITORY}/releases/tag/{storage}\n\nExact package commit: {commit}'
        notes_path = root/'notes.md'
        notes_path.write_text(notes + '\n')
        gh('release', 'create', tag, '-R', REPOSITORY, '--target', commit,
           '--title', tag, '--notes-file', str(notes_path), *assets)
        release = api(f'releases/tags/{tag}')
        reference = api(f'git/ref/tags/{tag}')
        if reference['object']['sha'] != commit:
            raise ValueError('Published tag does not match the tested commit')
        for asset in release['assets']:
            if assets and asset['name'] in (ASSET, 'PAGING-BUILD.json', 'SHA256SUMS'):
                checksum = hashlib.sha256((root/asset['name']).read_bytes()).hexdigest()
                if asset['digest'] != f'sha256:{checksum}':
                    raise ValueError('Published asset digest mismatch')
        print(release['html_url'])


if __name__ == '__main__':
    main()
