// Usage: bun scripts/benchmark-typed-do.ts BASELINE.ts PATCHED.ts BASE.bend
// Reverse only bend-typed-do-shadow.patch to construct BASELINE.ts.
// Parsing only: no type checking, code generation, native runtime, or I/O timed.
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createHash } from "node:crypto";

const paths = process.argv.slice(2).map(resolvePath => resolve(resolvePath));
if (paths.length !== 3) throw new Error("expected baseline, patched, and Base paths");
const baseline = await import(paths[0]);
const patched = await import(paths[1]);
const base = readFileSync(paths[2], "utf8");
const fixture = readFileSync("tests/typed-do-shadow.bend", "utf8").replace(/^import .*$/gm, "");
const programs = {
  base,
  "standalone-regression": base + "\n" + fixture,
  "ordinary-actions": Array.from({ length: 400 }, (_, i) =>
    `def bench${i}() -> IO(Unit):\n  do IO<Unit>:\n    IO.print("a")\n    IO.print("b")\n    IO.print("c")\n    return Unit{}\n`).join("\n"),
  "typed-bindings": Array.from({ length: 400 }, (_, i) =>
    `def bench${i}() -> IO(U32):\n  do IO<U32>:\n    x : U32 <- IO.pure(U32, 1)\n    y : U32 = x\n    return y\n`).join("\n"),
};
const result: Record<string, unknown> = {};
const hash = (text: string) => createHash("sha256").update(text).digest("hex");
for (const [name, source] of Object.entries(programs)) {
  const run = (compiler: typeof baseline) => compiler.parse_book(compiler.book_nil(), "", source);
  for (let i = 0; i < 15; ++i) { run(baseline); run(patched); }
  const samples = { baseline: [] as number[], patched: [] as number[] };
  const rounds = 30, repetitions = 10;
  for (let round = 0; round < rounds; ++round) {
    // Alternate ordering; force GC outside timing for both implementations.
    for (const variant of round % 2 ? ["patched", "baseline"] : ["baseline", "patched"]) {
      Bun.gc(true);
      const started = performance.now();
      for (let i = 0; i < repetitions; ++i) run(variant === "baseline" ? baseline : patched);
      samples[variant as keyof typeof samples].push((performance.now() - started) / repetitions);
    }
  }
  const median = (xs: number[]) => {
    const ys = [...xs].sort((a, b) => a - b);
    return (ys[14] + ys[15]) / 2;
  };
  result[name] = { sourceSha256: hash(source), rounds, repetitions, samplesMs: samples,
    baselineMedianMs: median(samples.baseline), patchedMedianMs: median(samples.patched),
    ratio: median(samples.patched) / median(samples.baseline) };
}
console.log(JSON.stringify({ bun: Bun.version, compilerSha256: paths.slice(0, 2).map(p => hash(readFileSync(p, "utf8"))), workloads: result }, null, 2));
