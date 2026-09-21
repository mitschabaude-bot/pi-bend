"""Native HTTP-date interpretation and retry-date callback against UTC references."""
import calendar
import datetime as dt
import hashlib
import json
import random
import re
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREFIX = ROOT / 'build/http-date'
SHORT = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
LONG = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
MONTH = 'Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec'.split()
cases = []
rng = random.Random(911007)


def words(value):
    value &= (1 << 64) - 1
    return f'{value >> 32}:{value & 0xffffffff}'


def number(value):
    return words(struct.unpack('>Q', struct.pack('>d', value))[0])


NAN = words(0x7ff8000000000000)


def add(text, expected, numeric=NAN, reference=(2026, 1, 1, 0, 0, 0)):
    cases.append({'input': ';'.join(map(str, reference)) + ';' + text, 'expected': expected + '#' + numeric})


def valid(value):
    year, month, day = value.year, value.month, value.day
    weekday = value.weekday()
    clock = value.strftime('%H:%M:%S')
    epoch = calendar.timegm(value.timetuple()) * 1000
    texts = [f'{SHORT[weekday]}, {day:02} {MONTH[month - 1]} {year:04} {clock} GMT',
             f'{LONG[weekday]}, {day:02}-{MONTH[month - 1]}-{year % 100:02} {clock} GMT',
             f'{SHORT[weekday]} {MONTH[month - 1]} {day:2} {clock} {year:04}']
    for text in texts:
        add(text, 'ordinary:' + words(epoch), number(epoch), (year, 1, 1, 0, 0, 0))
    add(texts[0].replace(SHORT[weekday], SHORT[(weekday + 1) % 7], 1), 'weekday', reference=(year, 1, 1, 0, 0, 0))


for year in [1, 4, 99, 100, 400, 1600, 1900, 1970, 1994, 2000, 2024, 2100, 2400, 9999]:
    for month in range(1, 13):
        for day in [1, calendar.monthrange(year, month)[1]]:
            valid(dt.datetime(year, month, day, 23, 59, 59))
for _ in range(1024):
    year, month = rng.randrange(1, 10000), rng.randrange(1, 13)
    valid(dt.datetime(year, month, rng.randrange(1, calendar.monthrange(year, month)[1] + 1), rng.randrange(24), rng.randrange(60), rng.randrange(60)))
add('Sat, 01 Jan 0000 00:00:00 GMT', 'ordinary:' + words(-62167219200000), number(-62167219200000))
for text in ['Sun, 06 Nov 1994 08:49:37 UTC', 'Sun, 06 Nov 1994 08:49:37 +0000', 'sun, 06 Nov 1994 08:49:37 GMT', 'Sun, 06 nov 1994 08:49:37 GMT', 'Sun, 06 Nov 1994 08:49:37 GMT trailing', 'Sun, 06 Nov 1994 08:49 GMT', '1994-11-06T08:49:37Z', 'garbage', '']:
    add(text, 'syntax')
for text in ['Sun, 00 Nov 1994 08:49:37 GMT', 'Sun, 31 Apr 1994 08:49:37 GMT', 'Sun, 29 Feb 1900 08:49:37 GMT', 'Sun, 06 Nov 1994 24:00:00 GMT', 'Sun, 06 Nov 1994 08:60:00 GMT', 'Sun, 06 Nov 1994 08:49:61 GMT']:
    add(text, 'calendar')
for text in ['Sat, 31 Dec 2016 12:59:60 GMT', 'Sat, 31 Dec 2016 23:58:60 GMT']:
    add(text, 'leap-position')
for text in ['Sat, 31 Dec 2016 23:59:60 GMT', 'Saturday, 31-Dec-16 23:59:60 GMT', 'Sat Dec 31 23:59:60 2016']:
    add(text, 'leap:' + words(1483228799000))
add('Sun, 31 Dec 2016 23:59:60 GMT', 'weekday')
add('  Sun,   06 Nov 1994 08:49:37 GMT  ', 'ordinary:' + words(784111777000), number(784111777000))

runs = []
for backend, command in [('native-1', [str(PREFIX), '--threads', '1']), ('native-4', [str(PREFIX), '--threads', '4']), ('bun', [str(Path.home() / '.bun/bin/bun'), str(PREFIX) + '.js'])]:
    for index in range(0, len(cases), 64):
        batch = cases[index:index + 64]
        result = subprocess.run(command + [c['input'] for c in batch], capture_output=True, text=True, check=True, timeout=20)
        expected = ['callback:' + number(784111777000)] + [c['expected'] for c in batch]
        assert result.stdout.splitlines() == expected, (backend, index, result.stdout, batch)
        assert not result.stderr, result.stderr
    runs.append({'backend': backend, 'cases': len(cases), 'callback_lifetimes': (len(cases) + 63) // 64})
    print(backend, len(cases), 'HTTP-date cases PASS', flush=True)

pending = [ROOT / 'packages/runtime/test/http-date.bend']
seen = {Path(__file__).resolve()}
while pending:
    path = pending.pop().resolve()
    if path in seen:
        continue
    seen.add(path)
    pending.extend(path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.M))
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
node_script = 'const s="Sat, 31 Dec 2016 23:59:60 GMT"; console.log(JSON.stringify({input:s, milliseconds:Date.parse(s), iso:new Date(Date.parse(s)).toISOString(), node:process.version}));'
record = {'scope': __doc__, 'seed': 911007, 'runs': runs, 'cases': cases, 'legacy_leap_second_reference': json.loads(subprocess.check_output(['node', '-e', node_script], text=True)), 'sources': {str(p): digest(p) for p in sorted(seen)}, 'program_sha256': {str(p): digest(p) for p in [PREFIX, Path(str(PREFIX) + '.c'), Path(str(PREFIX) + '.js')]}}
Path(str(PREFIX) + '-results.json').write_text(json.dumps(record, indent=2) + '\n')
