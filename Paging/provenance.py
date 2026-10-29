#!/usr/bin/env python3
"""Create and verify the package-owned paging build receipt."""
import argparse
import hashlib
import json
from pathlib import Path

ABI = 'ghostty-8af6897c-paging-1'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs(root):
    recipe = json.loads((root / 'Paging/recipe.json').read_text())
    if recipe['renderer'] != (root / 'Ghostty.ref').read_text().strip():
        raise ValueError('Ghostty.ref and paging recipe disagree')
    paths = [root / 'Ghostty.ref', root / 'Paging/recipe.json']
    paths += [root / 'Paging' / (name + '.patch') for name in recipe['rendererPatches']]
    paths += sorted((root / 'Patches/zig').glob(recipe['zig'] + '-*.patch'))
    paths += [root / name for name in ('Script/build-ghostty.sh', 'Script/apply-patches.sh',
                                     'Script/prepare-zig-lib.sh',
                                     'Script/support/libcxx-verbose-abort-compat.c',
                                     'Script/build.sh', 'Script/build-platform.sh', 'Script/merge-xcframework.sh',
                                     'Script/verify-xcframework.sh', 'Paging/pack-xcframework.py',
                                     'Paging/provenance.py', 'Paging/verify-api.py', 'Paging/toolchain.py') if (root / name).exists()]
    return {str(path.relative_to(root)): sha(path) for path in paths}


def wrapper_inputs(root):
    return {str(path.relative_to(root)): sha(path)
            for path in sorted((root / 'Sources').rglob('*.swift'))}


def artifacts(binary):
    return {str(path.relative_to(binary)): sha(path)
            for path in sorted(binary.rglob('*')) if path.is_file()}


def write(root, binary, source, arm64_only, toolchain=None, native_toolchains=None):
    recipe = json.loads((root / 'Paging/recipe.json').read_text())
    receipt = dict(schemaVersion=1, snapshotABI=recipe['snapshotABI'],
                   renderer=recipe['renderer'], wrapper=recipe['wrapper'], zig=recipe['zig'],
                   sourceCommit=source, wrapperSourceCommit=source, arm64Only=arm64_only,
                   inputs=inputs(root), wrapperInputs=wrapper_inputs(root), artifacts=artifacts(binary),
                   packagingToolchain=toolchain or {}, nativeToolchains=native_toolchains or {})
    (root / 'PAGING-BUILD.json').write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
    return receipt


def verify(root, binary, *, wrapper=True):
    receipt = json.loads((root / 'PAGING-BUILD.json').read_text())
    recipe = json.loads((root / 'Paging/recipe.json').read_text())
    if receipt['schemaVersion'] != 1 or receipt['snapshotABI'] != ABI or recipe['snapshotABI'] != ABI:
        raise ValueError('incompatible paging ABI')
    if any(receipt[key] != recipe[key] for key in ('renderer', 'wrapper', 'zig')):
        raise ValueError('paging source pins do not match receipt')
    if receipt['inputs'] != inputs(root):
        raise ValueError('native build inputs changed since this binary was built')
    if wrapper and receipt['wrapperInputs'] != wrapper_inputs(root):
        raise ValueError('wrapper sources changed since this package receipt was written')
    actual = artifacts(binary)
    if not actual or receipt['artifacts'] != actual:
        raise ValueError('binary files do not match the paging receipt')
    return receipt


def refresh_wrapper(root, binary, source):
    receipt = verify(root, binary, wrapper=False)
    receipt['wrapperInputs'] = wrapper_inputs(root)
    receipt['wrapperSourceCommit'] = source
    (root / 'PAGING-BUILD.json').write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')


def native_toolchains(directory, recipe):
    records = {}
    for path in sorted(directory.rglob('toolchain.json')):
        record = json.loads(path.read_text())
        target = record['target']
        if target in records or record['zig'] != recipe['zig']:
            raise ValueError('duplicate target or incorrect native compiler')
        if record['archiveSHA256'] != sha(path.parent / 'lib/libghostty.a'):
            raise ValueError('native archive changed after recording its toolchain')
        if record['headerSHA256'] != sha(path.parent / 'include/libghostty/ghostty.h'):
            raise ValueError('native header changed after recording its toolchain')
        records[target] = record
    expected = {'aarch64-macos', 'x86_64-macos', 'aarch64-ios',
                'aarch64-ios-simulator', 'x86_64-ios-simulator'}
    if set(records) != expected:
        raise ValueError('missing native toolchain records')
    return records


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['write', 'verify', 'refresh-wrapper'])
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--binary', type=Path)
    parser.add_argument('--source', default='local')
    parser.add_argument('--toolchains-dir', type=Path)
    parser.add_argument('--arm64-only', action='store_true')
    args = parser.parse_args()
    binary = args.binary or args.root / 'BinaryTarget/GhosttyKit.xcframework'
    if args.operation == 'write':
        from toolchain import capture
        toolchain = capture()
        recipe = json.loads((args.root / 'Paging/recipe.json').read_text())
        records = native_toolchains(args.toolchains_dir, recipe) if args.toolchains_dir else {}
        if toolchain['zig'] != recipe['zig']:
            raise ValueError('receipt compiler does not match the pinned Zig version')
        write(args.root, binary, args.source, args.arm64_only, toolchain, records)
    elif args.operation == 'refresh-wrapper':
        refresh_wrapper(args.root, binary, args.source)
    else:
        verify(args.root, binary)
    print('Paging provenance ' + args.operation + ' PASS')
