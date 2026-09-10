#!/usr/bin/env python3
"""Check tracked source metadata without printing any potential secret values."""
import argparse
import json
import pathlib
import re
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--require-license', action='store_true')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parent.parent
names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
problems = []
patterns = [r'\bsk-[A-Za-z0-9_-]{20,}', r'\bgh[pousr]_[A-Za-z0-9]{20,}',
            r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
            r'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}']
for name in filter(None, names):
    path = root / name
    if name.startswith(('.build/', 'dist/')) or path.name == 'auth.json' or path.name.endswith('.auth.json') or path.name.startswith('.env'):
        problems.append(f'Excluded data is tracked: {name}')
    if not path.exists() or path.suffix in {'.png', '.jpg'}:
        continue
    text = path.read_text(encoding='utf-8')
    if any(re.search(pattern, text) for pattern in patterns):
        problems.append(f'Potential secret in {name} (value suppressed)')
catalogs = [json.loads((root / f'Sources/SwitchCore/Resources/{lang}.json').read_text()) for lang in ['en', 'ko']]
if catalogs[0].keys() != catalogs[1].keys():
    problems.append('Localization keys differ')
for key in catalogs[0].keys() & catalogs[1].keys():
    if catalogs[0][key].count('%@') != catalogs[1][key].count('%@'):
        problems.append('Localization argument count differs')
if args.require_license and not (root / 'LICENSE').is_file():
    problems.append('Choose a license before publication: LICENSE is missing')
if problems:
    print('\n'.join(problems))
    sys.exit(1)
print('Tracked-source heuristic checks and localization parity passed.')
