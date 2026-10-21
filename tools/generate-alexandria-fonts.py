#!/usr/bin/env python3
"""Regenerate bundled Alexandria static instances. Requires fonttools 4.60.2.
Source: Google Fonts ofl/alexandria/Alexandria[wght].ttf (OFL).
Pass the downloaded source as the only argument; its checksum is verified.
"""
import hashlib
import sys
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
source = Path(sys.argv[1])
if hashlib.sha256(source.read_bytes()).hexdigest() != 'db8ae03b62d55a65aa4e04307878df8c00d6e5388e4800635cbe0e22b6411b64':
    raise SystemExit('Unexpected Alexandria source checksum')
output = Path(__file__).resolve().parents[1] / 'FamilyTreeV2/FamilyTreeV2/Resources/Fonts'
weights = ['Thin','ExtraLight','Light','Regular','Medium','SemiBold','Bold','ExtraBold','Black']
for value, name in enumerate(weights, 1):
    font = instantiateVariableFont(TTFont(source), {'wght': value * 100}, inplace=True)
    for record in list(font['name'].names):
        names = {1:'Alexandria '+name, 2:'Regular', 4:'Alexandria '+name,
                 6:'Alexandria-'+name, 16:'Alexandria', 17:name}
        if record.nameID in names:
            font['name'].setName(names[record.nameID], record.nameID,
                                 record.platformID, record.platEncID, record.langID)
    font.save(output / f'Alexandria-{name}.ttf')
