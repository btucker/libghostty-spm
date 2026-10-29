#!/usr/bin/env python3
"""Capture tools on the machine that actually compiled a native slice."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys


def output(*command):
    return subprocess.check_output(command, text=True).strip()


def capture():
    compiler = Path(shutil.which('zig')).resolve()
    return dict(zig=output(str(compiler), 'version'),
                zigSHA256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
                xcode=output('xcodebuild', '-version'),
                sdkBuilds={sdk: output('xcrun', '--sdk', sdk, '--show-sdk-build-version')
                           for sdk in ('macosx', 'iphoneos', 'iphonesimulator')})


if __name__ == '__main__':
    target, directory = sys.argv[1:]
    root = Path(directory)
    record = capture()
    record['target'] = target
    record['archiveSHA256'] = hashlib.sha256((root / 'lib/libghostty.a').read_bytes()).hexdigest()
    record['headerSHA256'] = hashlib.sha256((root / 'include/libghostty/ghostty.h').read_bytes()).hexdigest()
    (root / 'toolchain.json').write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
