#!/usr/bin/env python3
"""Converte Resources/AppIcon.icns in windows/ClipImporter/Assets/AppIcon.ico (solo macOS: usa sips).

Ogni dimensione è salvata come PNG dentro l'ICO (formato supportato da Windows Vista in poi).
Uso (dalla radice del repository):  python3 windows/tools/make_ico.py
"""
import os, struct, subprocess, sys, tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SRC = os.path.join(ROOT, 'Resources', 'AppIcon.icns')
DST = os.path.join(ROOT, 'windows', 'ClipImporter', 'Assets', 'AppIcon.ico')
SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]

def main():
    os.makedirs(os.path.dirname(DST), exist_ok=True)
    pngs = []
    with tempfile.TemporaryDirectory() as tmp:
        for s in SIZES:
            out = os.path.join(tmp, f'{s}.png')
            subprocess.run(['sips', '-s', 'format', 'png', '-z', str(s), str(s), SRC, '--out', out],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            pngs.append((s, open(out, 'rb').read()))
    header = struct.pack('<HHH', 0, 1, len(pngs))
    offset = 6 + 16 * len(pngs)
    entries, data = b'', b''
    for s, png in pngs:
        dim = 0 if s >= 256 else s
        entries += struct.pack('<BBBBHHII', dim, dim, 0, 0, 1, 32, len(png), offset)
        data += png
        offset += len(png)
    with open(DST, 'wb') as f:
        f.write(header + entries + data)
    print('ok', DST, os.path.getsize(DST), 'bytes')

if __name__ == '__main__':
    sys.exit(main())
