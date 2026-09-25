// Test-only oracle for runtime/src/highlight.bend: writes highlight cases
// (hand-written snippets, one generic snippet per highlight.js language, and
// windows of public source files found on this machine) and highlight.js
// 10.7.3's HTML for each, using the package pi installs.
//
//   bun tests/highlight_reference.mjs OUT_DIR [--no-corpus]
import { UPSTREAM } from "./upstream_pin.mjs";
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { snippets } from "./highlight_snippets.mjs";

const out = process.argv[2] ?? "build/highlight";
const corpus = !process.argv.includes("--no-corpus");
const packageDir = process.env.HIGHLIGHT_JS ?? "/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/highlight.js";
const require = createRequire(import.meta.url);
const hljs = require(join(packageDir, "lib/index.js"));

// Deterministic 32-bit PRNG for window choices.
let seed = 0x9e3779b9;
const random = () => {
  seed ^= seed << 13; seed >>>= 0; seed ^= seed >>> 17; seed ^= seed << 5; seed >>>= 0;
  return seed / 0x100000000;
};

const generic = `# comment
// comment
/* block */ -- dash comment
; semicolon
function main(a, b) { return a + b * 2; }
if x == 1 then print("string 'quoted'") end
let value = 0x1F + 3.14e-2; var list = [1, 2, 3]
<tag attr="v">text</tag> $var @attr %macro
class Foo extends Bar:
    def method(self): pass
`;

const cases = [...snippets];
for (const name of hljs.listLanguages()) cases.push({ language: name, code: generic });

// Public sources: system headers and scripts, pi-mono, and package caches.
const roots = ["/usr/include", "/usr/lib/python3", "/usr/share", UPSTREAM + "/packages", "/home/agent/.bun/install/cache"];
const extensions = {
  python: ["py"], java: ["java"], go: ["go"], javascript: ["js", "mjs"], cpp: ["cpp", "cc", "hpp"], typescript: ["ts", "tsx"],
  php: ["php"], ruby: ["rb"], c: ["c", "h"], csharp: ["cs"], bash: ["sh", "bash"], rust: ["rs"], swift: ["swift"], perl: ["pl", "pm"],
  lua: ["lua"], json: ["json"], yaml: ["yaml", "yml"], xml: ["xml", "html", "svg"], css: ["css"], scss: ["scss"], sql: ["sql"],
  diff: ["diff", "patch"], markdown: ["md"], ini: ["toml", "ini"], vim: ["vim"], latex: ["tex"], makefile: ["mk"], cmake: ["cmake"],
};
if (corpus) {
  for (const [language, exts] of Object.entries(extensions)) {
    const files = [];
    for (const root of roots) {
      if (!existsSync(root)) continue;
      const args = [root, "-xdev", "-type", "f", "-size", "-60k", "("];
      exts.forEach((ext, i) => args.push(...(i ? ["-o"] : []), "-name", `*.${ext}`));
      args.push(")");
      let found = "";
      try { found = execFileSync("find", args, { encoding: "utf8", maxBuffer: 1 << 26, stdio: ["ignore", "pipe", "ignore"] }); } catch (e) { found = e.stdout ?? ""; }
      files.push(...found.split("\n").filter((f) => f && !f.includes("/.git/")).sort().slice(0, 400));
    }
    const chosen = [];
    for (let i = 0; i < 12 && files.length; i++) chosen.push(files[Math.floor(random() * files.length)]);
    for (const file of chosen) {
      let text;
      try { text = readFileSync(file, "utf8"); } catch { continue; }
      if (text.includes("\u0000")) continue;
      const lines = text.split("\n");
      const start = Math.floor(random() * Math.max(1, lines.length - 50));
      cases.push({ language, code: lines.slice(start, start + 50).join("\n"), source: file });
    }
  }
}

mkdirSync(out, { recursive: true });
const expected = cases.map(({ language, code }) => {
  if (!hljs.getLanguage(language)) return "null";
  return JSON.stringify(hljs.highlight(code, { language, ignoreIllegals: true }).value);
});
writeFileSync(join(out, "cases.jsonl"), cases.map((c) => JSON.stringify(c)).join("\n") + "\n");
writeFileSync(join(out, "expected.jsonl"), expected.join("\n") + "\n");
console.log(`${cases.length} highlight cases`);
