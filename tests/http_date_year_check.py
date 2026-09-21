"""HTTP-date year resolution: exhaustive century search as an independent oracle."""
import calendar
import hashlib
import json
import random
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREFIX = ROOT / 'build/http-date-year'
MONTHS = 'Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec'.split()
rng = random.Random(9110)
cases = []


def add(reference, year, tail, form='rfc850'):
    month, day, hour, minute, second = tail
    clock = f'{hour:02}:{minute:02}:{second:02}'
    if form == 'rfc850':
        text = f'Sunday, {day:02}-{MONTHS[month - 1]}-{year:02} {clock} GMT'
        upper = (reference[0] + 50, *reference[1:])
        # Enumerate every candidate century, including the neighbors outside
        # our calendar range. Choosing in-range candidates first would hide
        # a correctly resolved but unrepresentable date at either endpoint.
        eligible = [y for y in range(-100, 10200) if y % 100 == year and (y, *tail) <= upper]
        selected = max(eligible)
        expected = str(selected) if 0 <= selected <= 9999 else 'range'
    elif form == 'imf':
        text = f'Sun, {day:02} {MONTHS[month - 1]} {year:04} {clock} GMT'
        expected = str(year)
    else:
        text = f'Sun {MONTHS[month - 1]} {day:2} {clock} {year:04}'
        expected = str(year)
    cases.append({'input': ';'.join(map(str, reference)) + ';' + text, 'expected': expected})


for current in [0, 1, 49, 50, 99, 100, 1900, 1999, 2000, 2024, 2049, 2050, 2099, 2100, 9949, 9950, 9999]:
    reference = (current, 6, 15, 12, 30, 30)
    for year in range(100):
        for tail in [(6, 15, 12, 30, 29), (6, 15, 12, 30, 30), (6, 15, 12, 30, 31)]:
            add(reference, year, tail)
for current in [0, 4, 400, 2000, 2024, 2400]:
    for tail in [(2, 28, 23, 59, 59), (2, 29, 0, 0, 0), (3, 1, 0, 0, 0)]:
        add((current, 2, 29, 0, 0, 0), (current + 50) % 100, tail)
for _ in range(2048):
    year = rng.randrange(10000)
    month = rng.randrange(1, 13)
    reference = (year, month, rng.randrange(1, calendar.monthrange(year, month)[1] + 1), rng.randrange(24), rng.randrange(60), rng.randrange(60))
    tail = (rng.randrange(1, 13), rng.randrange(1, 29), rng.randrange(24), rng.randrange(60), rng.randrange(60))
    add(reference, rng.randrange(100), tail)
for reference in [(0, 1, 1, 0, 0, 0), (2026, 9, 21, 0, 0, 0), (9999, 12, 31, 23, 59, 59)]:
    for year in [0, 1, 49, 50, 99, 100, 1994, 2026, 9999]:
        for form in ['imf', 'asctime']:
            add(reference, year, (11, 6, 8, 49, 37), form)
for reference in [(10000, 1, 1, 0, 0, 0), (2025, 2, 29, 0, 0, 0), (2026, 13, 1, 0, 0, 0), (2026, 1, 1, 24, 0, 0)]:
    cases.append({'input': ';'.join(map(str, reference)) + ';Sunday, 06-Nov-94 08:49:37 GMT', 'expected': 'reference'})

runs = []
for backend, command in [('native-1', [str(PREFIX), '--threads', '1']), ('native-4', [str(PREFIX), '--threads', '4']), ('bun', [str(Path.home() / '.bun/bin/bun'), str(PREFIX) + '.js'])]:
    for index in range(0, len(cases), 64):
        batch = cases[index:index + 64]
        result = subprocess.run(command + [c['input'] for c in batch], capture_output=True, text=True, check=True, timeout=15)
        assert result.stdout.splitlines() == [c['expected'] for c in batch], (backend, index, result.stdout, batch)
        assert not result.stderr, result.stderr
    runs.append({'backend': backend, 'cases': len(cases)})
    print(backend, len(cases), 'year-resolution cases PASS', flush=True)

pending = [ROOT / 'packages/runtime/test/http-date-year.bend']
seen = {Path(__file__).resolve()}
while pending:
    path = pending.pop().resolve()
    if path in seen:
        continue
    seen.add(path)
    pending.extend(path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.M))
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
record = {'scope': __doc__, 'seed': 9110, 'runs': runs, 'cases': cases, 'sources': {str(p): digest(p) for p in sorted(seen)}, 'program_sha256': {str(p): digest(p) for p in [PREFIX, Path(str(PREFIX) + '.c'), Path(str(PREFIX) + '.js')]}}
Path(str(PREFIX) + '-results.json').write_text(json.dumps(record, indent=2) + '\n')
