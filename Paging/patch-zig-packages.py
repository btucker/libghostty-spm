#!/usr/bin/env python3
"""Patch Zig packages that the pinned Ghostty fetches into SOURCE/zig-pkg.

aro, the C frontend behind translate-c, decides per target whether Apple
blocks are a language feature. Its isBlocksSupported asks Os.isAtLeast
about macOS for every Darwin target; since Zig 0.16 that answers false
rather than null for another OS tag, so iOS translates CoreGraphics with
blocks off and stops at "blocks are not enabled". Ask the version question
only for macOS, and answer yes for the rest of Darwin.

Zig unpacks packages under SOURCE/zig-pkg/ (gitignored) and never re-unpacks
one that exists, so the edit survives later builds. The edit is anchored and
idempotent: a package that already carries it is left unchanged.
"""
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'Script/support'))
from anchored_edit import Source  # noqa: E402

MARKER = '        // Zig answers false, not null, for another OS tag; ask about macOS only. (paging)\n'
OLD = """        if (target.os.isAtLeast(.macos, .{ .major = 10, .minor = 6, .patch = 0 })) |sup| return sup;
        // TODO: do iOS or other OSes have a min version?
        return target.os.tag != .macos;
"""
NEW = MARKER + """        if (target.os.tag != .macos) return true;
        return target.os.isAtLeast(.macos, .{ .major = 10, .minor = 6, .patch = 0 }) orelse false;
"""


def main(source_dir):
    source = Path(source_dir)
    if not list(source.glob('zig-pkg/aro-*')):
        subprocess.run(['zig', 'build', '--fetch=all'], cwd=source, check=True,
                       stdout=subprocess.DEVNULL)
    packages = sorted(source.glob('zig-pkg/aro-*'))
    if not packages:
        sys.exit('[!] no aro package under zig-pkg/ after fetch')
    for package in packages:
        target = Source(str(package), 'src/aro/Target.zig')
        target.replace(OLD, NEW, marker=MARKER)
        target.save()
        print(f'[+] aro blocks follow Darwin targets: {package.name}', file=sys.stderr)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('Usage: patch-zig-packages.py SOURCE')
    main(sys.argv[1])
