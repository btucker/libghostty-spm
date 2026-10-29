#!/usr/bin/env python3
"""Allow reuse of compiled slices only when every native input is unchanged."""
import hashlib
from pathlib import Path
import subprocess
import sys

from provenance import inputs


def verify(root, source):
    for relative, expected in inputs(root).items():
        previous = subprocess.check_output(['git', '-C', str(root), 'show', f'{source}:{relative}'])
        if hashlib.sha256(previous).hexdigest() != expected:
            raise ValueError(f'native artifact reuse rejected: {relative} changed')


if __name__ == '__main__':
    verify(Path(__file__).resolve().parents[1], sys.argv[1])
    print('Native artifact source inputs match PASS')
