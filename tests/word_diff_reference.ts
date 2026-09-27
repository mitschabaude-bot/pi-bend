import { UPSTREAM } from "./upstream_pin.mjs";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { strict as assert } from "node:assert";
for (const [file, hash] of [
  ["base.js", "faa81734df6ea7f8034efc5572ad1bbf19c50b300fdd183baf0d7813c5eec3b2"],
  ["word.js", "c1d6a6c52ef517e4ea9df6d71465fa520ce677d1b4e127425e3c2d8cf14f7a22"],
  ["line.js", "e3ef2d8c8c3a56f6b9fb04609f545b2aae2f84a02c31c5de3201aef1b0545f90"],
]) assert.equal(createHash("sha256").update(readFileSync(UPSTREAM + "/node_modules/diff/libesm/diff/" + file)).digest("hex"), hash);
const { diffWords } = await import(UPSTREAM + "/node_modules/diff/libesm/diff/word.js");
const { diffLines } = await import(UPSTREAM + "/node_modules/diff/libesm/diff/line.js");
const decode = (value: string) => value ? String.fromCodePoint(...value.split(",").map(Number)) : "";
const encode = (value: string) => Array.from(value, char => char.codePointAt(0)).join(",");
for (const argument of process.argv.slice(2)) {
  const line = argument.startsWith("line/");
  const [old, newer] = (line ? argument.slice(5) : argument).split("/").map(decode);
  const groups: { kind: string; words: string[] }[] = [];
  // Disable whitespace display postprocessing: this fixture checks token
  // matching, independently of the pending original-text rendering policy.
  for (const part of (line ? diffLines : diffWords)(old, newer, { oneChangePerToken: true })) {
    const kind = part.added ? "+" : part.removed ? "-" : "=";
    const key = encode(line ? part.value : part.value.trim());
    if (groups.at(-1)?.kind === kind) groups.at(-1)!.words.push(key);
    else groups.push({ kind, words: [key] });
  }
  console.log(groups.map(group => group.kind + ":" + group.words.join(";")).join("|"));
}
