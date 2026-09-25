#!/usr/bin/env python3
"""The marked port's rule sources (packages/runtime/src/marked/rules.bend,
built with its `edit` port) against marked 18.0.11's own compiled rules for
the default options, read from pi-mono's installed package (a test-only
oracle); every Bend source must also compile in runtime/ecma-regex.bend.

Usage: python3 tests/marked_rules_check.py [bend-toolchain main.ts] [pi-mono]
"""
import json, pathlib, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
BEND = sys.argv[1] if len(sys.argv) > 1 else str(ROOT / 'build/bend-native-toolchain/bend2/main.ts')
if not pathlib.Path(BEND).exists():
    BEND = '/home/agent/code/pi-bend/build/bend-native-toolchain/bend2/main.ts'
PI = sys.argv[2] if len(sys.argv) > 2 else '/home/agent/code/pi-mono'
OUT = ROOT / 'build/marked-rules'
OUT.mkdir(parents=True, exist_ok=True)
oracle = f'''const {{ Lexer }} = await import({json.dumps(PI + '/node_modules/marked/lib/marked.esm.js')});
const rules = new Lexer().tokenizer.rules;
const out = {{}};
for (const group of ["block", "inline"]) for (const [name, rule] of Object.entries(rules[group])) if (rule instanceof RegExp && rule.source !== "(?:)") out[group + "." + name] = [rule.flags, rule.source];
const breaks = new Lexer({{ gfm: true, breaks: true }}).tokenizer.rules.inline;
for (const name of ["br", "text"]) out["breaks." + name] = [breaks[name].flags, breaks[name].source];
console.log(JSON.stringify(out));'''
(OUT / 'oracle.mjs').write_text(oracle)
expected = json.loads(subprocess.run(['bun', str(OUT / 'oracle.mjs')], capture_output=True, text=True, check=True).stdout)
subprocess.run(['bun', BEND, 'tests/marked-rules.bend', '-o', str(OUT / 'run.js')], check=True, cwd=ROOT)
got = subprocess.run(['bun', str(OUT / 'run.js')], capture_output=True, text=True, check=True, cwd=ROOT).stdout.rstrip('\n').split('\n')
rows = [row.split('\t', 3) for row in got]
# RegExp#source escapes '/' (EscapeRegExpPattern): compare the Bend sources
# as JavaScript would print them.
(OUT / 'sources.json').write_text(json.dumps([[flags, source] for _, flags, _, source in rows]))
printed = json.loads(subprocess.run(['bun', '-e', f'console.log(JSON.stringify(JSON.parse(require("fs").readFileSync({json.dumps(str(OUT / "sources.json"))},"utf8")).map(([f,s])=>new RegExp(s,f).source)))'], capture_output=True, text=True, check=True).stdout)
bad = 0
seen = set()
for (name, flags, compiled, _), source in zip(rows, printed):
    seen.add(name)
    want = expected.get(name)
    if want is None:
        print(f'{name}: not a marked rule'); bad += 1
    elif [flags, source] != want:
        print(f'{name}: differs\n  bend /{source}/{flags}\n  js   /{want[1]}/{want[0]}'); bad += 1
    elif compiled != 'ok':
        print(f'{name}: {compiled}'); bad += 1
# Not ported: gfm's `del` expression, which marked's own del tokenizer
# never reads (it scans with delLDelim/delRDelim).
skipped = sorted(set(expected) - seen)
print(f'{len(got) - bad}/{len(got)} rule sources identical to marked and compiled; not ported: {", ".join(skipped) or "none"}')
sys.exit(1 if bad else 0)
