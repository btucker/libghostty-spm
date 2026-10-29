#!/usr/bin/env python3
"""Pack a stable ZIP, independent of source filesystem ordering and timestamps."""
from pathlib import Path
import sys
import zipfile


def pack(source, output):
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(source.rglob('*')):
            if path.is_symlink():
                raise ValueError(f'Unexpected symlink in static XCFramework: {path}')
            if not path.is_file():
                continue
            entry = zipfile.ZipInfo(str(Path(source.name) / path.relative_to(source)), (1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, path.read_bytes(), compresslevel=6)


if __name__ == '__main__':
    pack(Path(sys.argv[1]), Path(sys.argv[2]))
