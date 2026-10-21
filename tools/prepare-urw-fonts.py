#!/usr/bin/env python3
"""Provision licensed app fonts from the existing Occasion Kit distribution.
Run before building this font trial. Binaries remain ignored by Git.
"""
from pathlib import Path
from urllib.request import urlopen

root = Path(__file__).resolve().parents[1]
output = root / 'FamilyTreeV2/FamilyTreeV2/Resources/Fonts'
output.mkdir(parents=True, exist_ok=True)
for weight in ('regular', 'semibold', 'extrabold'):
    name = f'urw-geometric-arabic-{weight}.ttf'
    target = output / name
    if not target.exists():
        with urlopen(f'https://app.almohali.com/occasion-kit/fonts/{name}', timeout=60) as response:
            data = response.read()
        if data[:4] not in (b'\x00\x01\x00\x00', b'OTTO'):
            raise RuntimeError(f'Invalid font response: {name}')
        target.write_bytes(data)
    print(f'Ready: {name}')
