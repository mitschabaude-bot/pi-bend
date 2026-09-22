"""Compare read's pure text result with the exact pinned read.ts implementation."""

import argparse
import json
from pathlib import Path
import random
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT.parent / "pi-mono/packages/coding-agent/src/core/tools"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("backend", choices=["bun", "native-1", "native-4"])
parser.add_argument("--prefix", default="build/read-text")
args = parser.parse_args()

# Extract the original text-selection block; no rewritten reference algorithm.
source = (UPSTREAM / "read.ts").read_text()
start = source.index('const allLines = textContent.split("\\n");')
end = source.index('content = [{ type: "text", text: outputText }];', start)
body = source[start:end]
# Accepted adaptation: generated shell instructions quote paths and terminate
# option parsing. Selection, bytes, line counts and metadata remain unmodified.
original = "p' ${path} | head"
assert body.count(original) == 1
body = body.replace(original, "p' -- ${quotePath(path)} | head")
oracle = r"""
import { truncateHead, formatSize, DEFAULT_MAX_BYTES } from "TRUNCATE";
const quotePath = path => "'" + path.replaceAll("'", "'\\''") + "'";
const scalars = text => [...text].map(c => c.codePointAt(0)).join(',');
function read(textContent, path, offset, limit) {
  let details;
  BODY
  if (!details) return 'ok|' + scalars(outputText) + '|none';
  const t = details.truncation;
  return ['ok', scalars(outputText), scalars(t.content), Number(t.truncated),
    t.truncatedBy ?? 'none', t.totalLines, t.totalBytes, t.outputLines,
    t.outputBytes, Number(t.lastLinePartial), Number(t.firstLineExceedsLimit),
    t.maxLines, t.maxBytes].join('|');
}
const cases = JSON.parse(await Bun.stdin.text());
console.log(JSON.stringify(cases.map(([path,offset,limit,repetitions,text]) => {
  try { return read(text.repeat(repetitions), path, offset ?? undefined, limit ?? undefined); }
  catch (e) { return 'error|' + e.message; }
})));
""".replace("TRUNCATE", str(UPSTREAM / "truncate.ts")).replace("BODY", body)

cases = []
for text in ["", "\n", "a", "a\n", "a\nb", "\r\n", "é漢😀\nsecond\n", "\ufeffBOM\x00\nlast"]:
    for offset in [None, 0, 1, 2, 3, 5]:
        for limit in [None, 0, 1, 2, 8]:
            cases.append(["sample.txt", offset, limit, 1, text])
rng = random.Random(47913)
for _ in range(150):
    text = "".join(rng.choice("abc\n\r\té漢😀\ufeff") for _ in range(rng.randrange(80)))
    cases.append(["sample.txt", rng.randrange(12), rng.choice([None, 0, 1, 3, 9]), 1, text])
for path in ["sample.txt", "-options", "a b'c;$(literal).txt"]:
    for repetitions, text in [
        (2001, "a\n"),
        (51201, "x"),
        (51200, "x"),
        (3000, "x" * 20 + "\n"),
        (17068, "漢"),
    ]:
        for offset, limit in [(None, None), (1, 0), (1, 1), (2, 3)]:
            cases.append([path, offset, limit, repetitions, text])
expected = json.loads(subprocess.check_output(["bun", "--eval", oracle], input=json.dumps(cases), text=True))


def encode(case):
    path, offset, limit, repetitions, text = case
    scalars = lambda value: ",".join(str(ord(char)) for char in value)
    return ":".join(
        [
            scalars(path),
            "" if offset is None else str(offset),
            "" if limit is None else str(limit),
            str(repetitions),
            scalars(text),
        ]
    )


prefix = ROOT / args.prefix
command = (
    ["bun", str(prefix) + ".js"] if args.backend == "bun" else [str(prefix), "--threads", args.backend[-1]]
)
for start in range(0, len(cases), 30):
    batch = cases[start : start + 30]
    run = subprocess.run(
        command + [encode(case) for case in batch], capture_output=True, text=True, timeout=120
    )
    assert run.returncode == 0, (args.backend, start, run.stderr[-3000:])
    actual = run.stdout.splitlines()
    assert len(actual) == len(batch), (start, len(actual), len(batch))
    for index, (got, want) in enumerate(zip(actual, expected[start : start + len(batch)])):
        assert got == want, (args.backend, start + index, batch[index], got[:1000], want[:1000])
        if got.startswith("ok|") and "|bytes|" in got:
            output = "".join(chr(int(code)) for code in got.split("|")[1].split(",") if code)
            if output.startswith("[Line "):
                command_text = output.split("Use bash: ", 1)[1][:-1]
                words = shlex.split(command_text)
                assert words[:2] == ["sed", "-n"]
                assert words[3:] == ["--", batch[index][0], "|", "head", "-c", "51200"], words
print(f"{args.backend}: {len(cases)} read text comparisons PASS", flush=True)
