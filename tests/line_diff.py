"""Compare native line diffs and both Pi renderers with pinned diff 8.0.4."""
from upstream_pin import UPSTREAM
import argparse
import itertools
import json
import os
from pathlib import Path
import random
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def corpus():
    short = [""]
    for length in range(1, 4):
        for tokens in itertools.product(["a\n", "b\n"], repeat=length):
            text = "".join(tokens)
            short.extend([text, text[:-1]])
    cases = [[a, b, (i + j) % 5, "file name.txt"]
             for i, a in enumerate(short) for j, b in enumerate(short)]
    rng = random.Random(20260922)
    alphabet = ["a\n", "b\n", "\n", "é\r\n", "😀\n", "tail", "\r", "\t \n"]
    for _ in range(400):
        make = lambda: "".join(rng.choice(alphabet) for _ in range(rng.randrange(25)))
        cases.append([make(), make(), rng.randrange(8), "src/example.bend"])
    # Hunk merging at exactly twice the context; width changes and EOF markers.
    for context in range(6):
        for gap in range(15):
            middle = "".join(f"line {i}\n" for i in range(gap))
            cases.append(["old\n" + middle + "last", "new\n" + middle + "final", context, "f"])
    for length in [10, 100, 1000]:
        original = "".join(f"line {i}\n" for i in range(length))
        cases.extend([[original, original + "added\n" * length, 4, "f"],
                      [original, "", 0, "f"], ["", original, 4, "f"],
                      [original, original, 4, "f"]])
    return cases


def oracle(reference, package, cases, directory):
    metadata = json.loads((package / "package.json").read_text())
    assert metadata["version"] == "8.0.4", metadata["version"]
    source = (reference / "packages/coding-agent/src/core/tools/edit-diff.ts").read_text()
    functions = []
    for name in ["generateUnifiedPatch", "generateDiffString"]:
        start = source.index(f"export function {name}")
        end = source.index("\nexport ", start + 10)
        functions.append(source[start:end])
    driver = directory / "oracle.ts"
    driver.write_text(f"import * as Diff from {json.dumps(str(package / 'libesm/index.js'))};\n"
                      + "\n".join(functions) + '''
const cases = await Bun.file(process.argv[2]).json();
console.log(JSON.stringify(cases.map(([a,b,c,p]) => {
  const r = generateDiffString(a,b,c);
  return [[r.diff,r.firstChangedLine??null],generateUnifiedPatch(p,a,b,c),
    [...Diff.diffLines(a,b).map(x=>[x.added?"+":x.removed?"-":" ",x.value]),null]];
})));
''')
    inputs = directory / "cases.json"
    inputs.write_text(json.dumps(cases))
    return json.loads(subprocess.check_output(["bun", str(driver), str(inputs)], text=True))


def distance(left, right):
    row = list(range(len(right) + 1))
    for i, a in enumerate(left):
        next_row = [i + 1]
        for j, b in enumerate(right):
            next_row.append(row[j] if a == b else 1 + min(row[j + 1], next_row[j]))
        row = next_row
    return row[-1]


def lines(text):
    # Unlike splitlines(), jsdiff only treats LF as a terminator.
    parts = text.split("\n")
    return [line + "\n" for line in parts[:-1]] + ([parts[-1]] if parts[-1] else [])


def invariants(case, value):
    old, new = case[:2]
    changes = value[2][:-1]
    assert "".join(text for kind, text in changes if kind != "+") == old
    assert "".join(text for kind, text in changes if kind != "-") == new
    assert all(a[0] != b[0] for a, b in zip(changes, changes[1:]))
    assert all(text for _, text in changes)
    if len(lines(old)) + len(lines(new)) <= 60:
        edits = sum(len(lines(text)) for kind, text in changes if kind != " ")
        assert edits == distance(lines(old), lines(new))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bend", type=Path)
    parser.add_argument("--reference", type=Path, default=UPSTREAM)
    parser.add_argument("--diff-package", type=Path, default=ROOT / "build/package")
    parser.add_argument("--backends", nargs="+", choices=["bun", "native-1", "native-4"], default=["bun", "native-1", "native-4"])
    parser.add_argument("--no-build", action="store_true")
    args = parser.parse_args()
    directory = ROOT / "build/line-diff-reference"
    directory.mkdir(parents=True, exist_ok=True)
    if not (args.diff_package / "package.json").exists():
        parser.error("Install test oracle: npm pack diff@8.0.4 --pack-destination build; tar -xzf build/diff-8.0.4.tgz -C build")
    compiler = args.bend or Path(os.environ.get("BEND", str(ROOT / "build/bend-native-toolchain/bend2/main.ts")))
    prefix = ROOT / "build/line-diff"
    long_prefix = ROOT / "build/line-diff-long"
    if not args.no_build:
        if "bun" in args.backends:
            for source, output in [("tests/line-diff.bend", prefix), ("tests/line-diff-long.bend", long_prefix)]:
                subprocess.run([str(compiler), source, "-o", str(output) + ".js"], cwd=ROOT, check=True)
        if any(name.startswith("native") for name in args.backends):
            for source, output in [("tests/line-diff.bend", prefix), ("tests/line-diff-long.bend", long_prefix)]:
                subprocess.run(["sh", "scripts/build-pure.sh", source, str(output)], cwd=ROOT,
                               env=dict(os.environ, BEND=str(compiler)), check=True)
    cases = corpus()
    expected = oracle(args.reference.resolve(), args.diff_package.resolve(), cases, directory)
    for backend in args.backends:
        command = ["bun", str(prefix) + ".js"] if backend == "bun" else [str(prefix), "--threads", backend[-1]]
        for start in range(0, len(cases), 40):
            batch = cases[start:start + 40]
            arguments = [value for old, new, context, path in batch for value in [old, new, "x" * context, path]]
            output = subprocess.check_output(command + arguments, text=True, timeout=90)
            actual = [json.loads(line) for line in output.splitlines()]
            assert len(actual) == len(batch), (backend, start, len(actual))
            for offset, (case, got, wanted) in enumerate(zip(batch, actual, expected[start:])):
                assert got == wanted, (backend, start + offset, case, got, wanted)
                invariants(case, got)
        print(f"{backend}: {len(cases)} exact reference comparisons; reconstruction, maximal runs and minimal edits pass", flush=True)
        long_command = ["bun", str(long_prefix) + ".js"] if backend == "bun" else [str(long_prefix), "--threads", backend[-1]]
        measurements = []
        for sample in range(3):
            timing = directory / f"long-{backend}-{sample}.time"
            output = subprocess.check_output(["/usr/bin/time", "-f", "%e %M", "-o", str(timing), *long_command], text=True, timeout=90)
            assert output.strip() == "long lines: identity, replacement, EOF and context pass", output
            measurements.append(tuple(map(float, timing.read_text().split())))
        print(f"{backend}: 200KB long-line cases pass; process wall median {statistics.median(x[0] for x in measurements):.3f}s, "
              f"peak RSS {max(x[1] for x in measurements):.0f} KiB (3 runs, including fixture construction)", flush=True)



if __name__ == "__main__":
    main()
