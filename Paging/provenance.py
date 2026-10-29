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
    paths += [root / name for name in ('Script/build-ghostty.sh', 'Script/apply-patches.sh',
                                     'Script/support/libcxx-verbose-abort-compat.c',
                                     'Script/build.sh', 'Script/build-platform.sh', 'Script/merge-xcframework.sh',
                                     'Script/verify-xcframework.sh', 'Paging/pack-xcframework.py',
                                     'Paging/provenance.py', 'Paging/verify-api.py') if (root / name).exists()]
    return {str(path.relative_to(root)): sha(path) for path in paths}


def wrapper_inputs(root):
    return {str(path.relative_to(root)): sha(path)
            for path in sorted((root / 'Sources').rglob('*.swift'))}


def artifacts(binary):
    return {str(path.relative_to(binary)): sha(path)
            for path in sorted(binary.rglob('*')) if path.is_file()}


def write(root, binary, source, arm64_only, toolchain=None):
    recipe = json.loads((root / 'Paging/recipe.json').read_text())
    receipt = dict(schemaVersion=1, snapshotABI=recipe['snapshotABI'],
                   renderer=recipe['renderer'], wrapper=recipe['wrapper'], zig=recipe['zig'],
                   sourceCommit=source, wrapperSourceCommit=source, arm64Only=arm64_only,
                   inputs=inputs(root), wrapperInputs=wrapper_inputs(root), artifacts=artifacts(binary),
                   toolchain=toolchain or {})
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


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['write', 'verify', 'refresh-wrapper'])
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--binary', type=Path)
    parser.add_argument('--source', default='local')
    parser.add_argument('--arm64-only', action='store_true')
    args = parser.parse_args()
    binary = args.binary or args.root / 'BinaryTarget/GhosttyKit.xcframework'
    if args.operation == 'write':
        import shutil
        import subprocess
        def output(*command):
            return subprocess.check_output(command, text=True).strip()
        compiler = Path(shutil.which('zig')).resolve()
        toolchain = dict(zig=output(str(compiler), 'version'), zigSHA256=sha(compiler),
                         xcode=output('xcodebuild', '-version'),
                         sdkBuilds={sdk: output('xcrun', '--sdk', sdk, '--show-sdk-build-version')
                                    for sdk in ('macosx', 'iphoneos', 'iphonesimulator')})
        if toolchain['zig'] != json.loads((args.root / 'Paging/recipe.json').read_text())['zig']:
            raise ValueError('receipt compiler does not match the pinned Zig version')
        write(args.root, binary, args.source, args.arm64_only, toolchain)
    elif args.operation == 'refresh-wrapper':
        refresh_wrapper(args.root, binary, args.source)
    else:
        verify(args.root, binary)
    print('Paging provenance ' + args.operation + ' PASS')
