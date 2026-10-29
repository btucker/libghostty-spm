#!/usr/bin/env python3
"""Require the complete production matrix and paging exports in every archive."""
from pathlib import Path
import plistlib
import subprocess
import sys

root = Path(sys.argv[1])
with (root / 'Info.plist').open('rb') as stream:
    libraries = plistlib.load(stream)['AvailableLibraries']
expected = {('macos', None): {'arm64', 'x86_64'}, ('ios', None): {'arm64'},
            ('ios', 'simulator'): {'arm64', 'x86_64'}}
actual = {(entry['SupportedPlatform'], entry.get('SupportedPlatformVariant')):
          set(entry['SupportedArchitectures']) for entry in libraries}
if actual != expected or len(libraries) != len(expected):
    raise SystemExit(f'Incomplete production architecture matrix: {actual}')
required = {'_ghostty_surface_' + name for name in (
    'snapshot_ready', 'snapshot_page', 'snapshot_near_top', 'set_source_grid',
    'clear_source_grid', 'read_scrollbar', 'font_size', 'read_history')}
for entry in libraries:
    archive = root / entry['LibraryIdentifier'] / entry['LibraryPath']
    for architecture in entry['SupportedArchitectures']:
        symbols = subprocess.check_output(['nm', '-g', '-arch', architecture, str(archive)],
                                          text=True, stderr=subprocess.DEVNULL)
        defined = {words[-1] for line in symbols.splitlines()
                   if len(words := line.split()) >= 3 and words[-2] != 'U'}
        if missing := required - defined:
            raise SystemExit(f'{archive} {architecture}: missing paging exports {sorted(missing)}')
print('Production slices and paging exports PASS')
