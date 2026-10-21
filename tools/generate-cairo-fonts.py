#!/usr/bin/env python3
"""Regenerate bundled Cairo static instances. Requires fonttools 4.60.2.
Source: Google Fonts ofl/cairo/Cairo[slnt,wght].ttf (OFL).
Pass the downloaded source as the only argument; its checksum is verified.
"""
import hashlib
import sys
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
source = Path(sys.argv[1])
if hashlib.sha256(source.read_bytes()).hexdigest() != '667c987182391c91f4e57a2f455b1794fb5e3ee6ca4ef3383e86bb690fa9c964':
    raise SystemExit('Unexpected Cairo source checksum')
output = Path(__file__).resolve().parents[1] / 'FamilyTreeV2/FamilyTreeV2/Resources/Fonts'
weights = ['ExtraLight','Light','Regular','Medium','SemiBold','Bold','ExtraBold','Black','ExtraBlack']
for value, name in enumerate(weights, 2):
    font = instantiateVariableFont(TTFont(source), {'wght': value * 100, 'slnt': 0}, inplace=True)
    for record in list(font['name'].names):
        names = {1:'Cairo '+name, 2:'Regular', 4:'Cairo '+name,
                 6:'Cairo-'+name, 16:'Cairo', 17:name}
        if record.nameID in names:
            font['name'].setName(names[record.nameID], record.nameID,
                                 record.platformID, record.platEncID, record.langID)
    font.save(output / f'Cairo-{name}.ttf')
