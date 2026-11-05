#!/usr/bin/env python3
"""Controlla le traduzioni della versione Windows.

- ogni L("...") nel codice C# deve esistere in strings.json (condiviso) o in strings.windows.json;
- le frasi solo Windows devono essere tradotte in tutte le lingue;
- i segnaposto {0}, {1} devono restare uguali.
Uso:  python3 windows/tools/check_strings.py   (codice di uscita 1 se qualcosa non va)
"""
import glob, json, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
LANGS = ['it', 'es', 'fr', 'de', 'pt', 'ru', 'ja', 'ko', 'zh']
PH = re.compile(r'\{\d+\}')

def load(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f).get('translations', {})

def keys_in_code():
    keys = set()
    lit = re.compile(r'\bL\(\s*"((?:[^"\\]|\\.)*)"')
    for path in glob.glob(os.path.join(ROOT, 'windows', 'ClipImporter', '**', '*.cs'), recursive=True):
        src = open(path, encoding='utf-8').read()
        for m in lit.finditer(src):
            keys.add(json.loads('"' + m.group(1) + '"'))
    return keys

def main():
    shared = load(os.path.join(ROOT, 'Resources', 'strings.json'))
    win = load(os.path.join(ROOT, 'windows', 'strings.windows.json'))
    shared_keys = set().union(*[set(t) for t in shared.values()]) if shared else set()
    win_keys = set().union(*[set(t) for t in win.values()]) if win else set()
    used = keys_in_code()
    errors = []

    for k in sorted(used):
        if k not in shared_keys and k not in win_keys:
            errors.append(f'missing key (not in strings.json nor strings.windows.json): {k!r}')

    base_win = {k for k in win_keys if '#' not in k}
    for lang in LANGS:
        t = win.get(lang, {})
        for k in sorted(base_win):
            if k not in t:
                errors.append(f'[{lang}] Windows key not translated: {k!r}')
    for name, tables in (('strings.json', shared), ('strings.windows.json', win)):
        for lang, t in tables.items():
            for k, v in t.items():
                base = k.split('#')[0]
                if set(PH.findall(base)) != set(PH.findall(v)):
                    errors.append(f'[{name} {lang}] placeholder mismatch: {k!r} -> {v!r}')

    unused = sorted(k for k in base_win if k not in used)
    for k in unused:
        print(f'note: Windows key not used in code: {k!r}')
    reused = len([k for k in used if k in shared_keys])
    print(f'{len(used)} keys used by the Windows app: {reused} shared with the Mac, {len(used) - reused} Windows-only')
    for e in errors:
        print('ERROR', e)
    if errors:
        return 1
    print('strings OK')
    return 0

if __name__ == '__main__':
    sys.exit(main())
