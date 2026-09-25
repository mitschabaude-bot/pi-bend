"""Compare the pure Bend codec with the TextDecoder/TextEncoder used by the SDK.

The native runner accepts data at runtime so coverage does not inflate generated C.
"""
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(8501)
cases = []


def decode(chunks):
    cases.append({"chunks": chunks})
    cases.append({"bytes": [byte for chunk in chunks for byte in chunk]})


decode([[]])
for byte in range(256):
    decode([[byte]])
for lead in range(128, 256):
    for following in range(256):
        decode([[lead, following]])
sequences = [
    [239, 187, 191], [239, 187, 191, 239, 187, 191],
    [65, 239, 187, 191], [224, 128, 128], [237, 160, 128],
    [240, 128, 128, 128], [244, 144, 128, 128], [226, 65, 172],
    [240, 159, 65, 128], [226, 130], [240, 159, 146],
]
for scalar in [0, 127, 128, 2047, 2048, 55295, 57344, 65535, 65536, 1114111]:
    sequences.append(list(chr(scalar).encode("utf-8")))
for _ in range(600):
    sequences.append([rng.randrange(256) for _ in range(rng.randrange(16))])
for data in sequences:
    decode([data])
    decode([[], *[[byte] for byte in data], []])
    for cut in range(len(data) + 1):
        decode([data[:cut], [], data[cut:]])
for values in [[], [65279], [55296], [56320], [55296, 56320],
               [56319, 57343], [55296, 65, 56320], [55296, 55297, 56320]]:
    cases.append({"scalars": values})
for scalar in [0, 127, 128, 2047, 2048, 55295, 55296, 56319, 56320, 57343,
               57344, 65535, 65536, 1114111] + [rng.randrange(1114112) for _ in range(1000)]:
    cases.append({"scalars": [scalar]})

oracle = r"""
const fs = require('node:fs');
const cases = JSON.parse(fs.readFileSync(0, 'utf8'));
const show = s => Array.from(s, c => c.codePointAt(0)).join(',');
console.log(JSON.stringify(cases.map(c => {
  if (c.scalars) return Array.from(new TextEncoder().encode(String.fromCodePoint(...c.scalars))).join(',');
  if (c.bytes) return show(new TextDecoder().decode(Uint8Array.from(c.bytes)));
  const decoder = new TextDecoder();
  return [...c.chunks.map(bytes => show(decoder.decode(Uint8Array.from(bytes), {stream:true}))), show(decoder.decode())].join('|');
})));
"""
expected = json.loads(subprocess.check_output(
    ["node", "-e", oracle], input=json.dumps(cases), text=True))
streaming_expected = json.loads(subprocess.check_output(
    [str(Path.home() / ".bun/bin/bun"), "-e", oracle], input=json.dumps(cases), text=True))
for index, case in enumerate(cases):
    if "chunks" in case:
        # Node 24.18.0's streaming decoder can strip two BOMs when the first is split
        # across chunks. The SDK uses non-streaming decoding (checked above).
        expected[index] = streaming_expected[index]
    else:
        assert expected[index] == streaming_expected[index], case
subprocess.run(['flock', '/tmp/pi-bend-build.lock', "sh", "scripts/build-pure.sh", "packages/runtime/test/utf8-runner.bend", "build/test-utf8"], cwd=ROOT, check=True)
arguments = [
    "e" + ",".join(map(str, case["scalars"])) if "scalars" in case
    else "b" + ",".join(map(str, case["bytes"])) if "bytes" in case
    else "d" + "|".join(",".join(map(str, chunk)) for chunk in case["chunks"])
    for case in cases
]
for threads in ["1", "4"]:
    for start in range(0, len(cases), 256):
        actual = subprocess.check_output(
            [str(ROOT / "build/test-utf8"), "--threads", threads, *arguments[start:start + 256]],
            text=True, timeout=30).splitlines()
        wanted = expected[start:start + 256]
        assert len(actual) == len(wanted), (start, len(actual), len(wanted))
        for offset, (got, want) in enumerate(zip(actual, wanted)):
            assert got == want, (threads, cases[start + offset], got, want)
    print(f"PASS UTF-8: {len(cases)} oracle cases on {threads} native threads", flush=True)
