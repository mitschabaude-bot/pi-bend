#!/usr/bin/env bun
// Serializes highlight.js 10.7.3's compiled grammars for the Bend highlighter
// (packages/runtime/src/highlight.bend).
//
//   bun scripts/generate-highlight-languages.mjs [highlight.js package dir]
//
// highlight.js grammars are JavaScript functions that highlight.js compiles
// lazily (compileLanguage) on the first highlight call. This script lets
// highlight.js compile every language and writes the resulting mode graph:
// one JSON file per language plus index.json (registration order and
// language metadata). Modes are numbered in breadth-first order from the
// language root (mode 0); `contains` and `starts` refer to those numbers, so
// shared and self-referential modes keep their identity.
//
// Only five function-valued mode properties exist across the 191 languages;
// they are written as named callbacks and implemented natively in Bend. The
// script fails on any other function, so a grammar update cannot silently
// lose behavior.
import { createRequire } from "node:module";
import { mkdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const packageDir = process.argv[2] ?? "/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/highlight.js";
const outDir = join(root, "packages/runtime/data/highlight");
const require = createRequire(import.meta.url);
const hljs = require(join(packageDir, "lib/index.js"));
const version = JSON.parse(readFileSync(join(packageDir, "package.json"), "utf8")).version;
if (version !== "10.7.3") throw new Error(`expected highlight.js 10.7.3, found ${version}`);


// Registration order of highlight.js/lib/index.js.
const indexSource = readFileSync(join(packageDir, "lib/index.js"), "utf8");
const order = [...indexSource.matchAll(/registerLanguage\('([^']+)'/g)].map((m) => m[1]);

// Mathematica's builtin-symbol callback closes over this module constant.
const mathematicaSource = readFileSync(join(packageDir, "lib/languages/mathematica.js"), "utf8");
const systemSymbols = JSON.parse(mathematicaSource.match(/const SYSTEM_SYMBOLS = (\[[\s\S]*?\]);/)[1].replace(/,\s*\]$/, "]"));

const source = (re) => (re === undefined || re === null ? undefined : typeof re === "string" ? re : re.source);

function callbackName(fn, kind) {
  const text = fn.toString();
  if (kind === "__beforeBegin" && fn.name === "skipIfhasPrecedingDot") return { name: "skipIfHasPrecedingDot" };
  if (kind === "on:begin" && text.includes("m.index !== 0")) return { name: "shebang" };
  if (kind === "on:begin" && text.includes("resp.data._beginMatch = m[1]")) return { name: "endSameAsBegin" };
  if (kind === "on:end" && text.includes("resp.data._beginMatch !== m[1]")) return { name: "endSameAsBegin" };
  if (kind === "on:begin" && fn.name === "isTrulyOpeningTag" && text.includes("hasClosingTag")) return { name: "jsxOpeningTag" };
  if (kind === "on:begin" && text.includes("SYSTEM_SYMBOLS_SET.has(match[0])")) return { name: "systemSymbol", symbols: systemSymbols };
  throw new Error(`unknown ${kind} callback: ${text}`);
}

// Properties _highlight never reads after compilation.
const compileOnly = new Set(["isCompiled", "matcher", "beginRe", "endRe", "illegalRe", "keywordPatternRe", "variants", "cachedVariants", "lexemes", "beginKeywords", "match", "rawDefinition", "classNameAliases", "compilerExtensions", "name", "aliases", "disableAutodetect", "supersetOf", "case_insensitive", "data", "end", "exports", "binary", "label"]);
const read = new Set(["className", "begin", "terminatorEnd", "illegal", "keywords", "contains", "starts", "relevance", "subLanguage", "excludeBegin", "excludeEnd", "returnBegin", "returnEnd", "endsWithParent", "endsParent", "skip", "endSameAsBegin", "__beforeBegin", "on:begin", "on:end"]);
const unknownKeys = new Set();

function serializeLanguage(name) {
  const language = hljs.getLanguage(name);
  hljs.highlight("", { language: name, ignoreIllegals: true }); // compileLanguage
  const ids = new Map();
  const modes = [];
  const queue = [language];
  ids.set(language, 0);
  const keywordTables = [];
  const keywordIds = new Map();
  while (queue.length) {
    const mode = queue.shift();
    const id = ids.get(mode);
    const visit = (m) => {
      if (!ids.has(m)) { ids.set(m, ids.size); queue.push(m); }
      return ids.get(m);
    };
    const out = {};
    for (const key of Object.keys(mode)) {
      if (!read.has(key) && !compileOnly.has(key)) unknownKeys.add(`${name}:${key}`);
      if (typeof mode[key] === "function" && !["__beforeBegin", "on:begin", "on:end", "rawDefinition"].includes(key)) throw new Error(`${name}: function-valued ${key}`);
    }
    if (mode.className !== undefined && mode.className !== null) {
      if (typeof mode.className !== "string") throw new Error(`${name}: className ${mode.className}`);
      out.className = mode.className;
    }
    if (id !== 0) {
      out.begin = source(mode.begin);
      if (mode.endRe) out.end = mode.endRe.source;
      out.terminatorEnd = mode.terminatorEnd;
    }
    if (mode.illegal) out.illegal = source(mode.illegal);
    if (mode.keywords) {
      const text = JSON.stringify(mode.keywords);
      if (!keywordIds.has(text)) { keywordIds.set(text, keywordTables.length); keywordTables.push(mode.keywords); }
      out.keywords = keywordIds.get(text);
    }
    out.keywordPattern = mode.keywordPatternRe.source;
    if (mode.relevance !== undefined) out.relevance = mode.relevance;
    for (const flag of ["excludeBegin", "excludeEnd", "returnBegin", "returnEnd", "endsWithParent", "endsParent", "skip"]) {
      if (mode[flag]) out[flag] = true;
    }
    // No 10.7.3 grammar sets the endSameAsBegin mode flag (END_SAME_AS_BEGIN
    // is the callback pair below); the Bend port does not implement it.
    if (mode.endSameAsBegin) throw new Error(`${name}: endSameAsBegin mode flag`);
    if (mode.subLanguage !== undefined && mode.subLanguage !== null) out.subLanguage = mode.subLanguage;
    if (mode.__beforeBegin) out.beforeBegin = callbackName(mode.__beforeBegin, "__beforeBegin");
    if (mode["on:begin"]) out.onBegin = callbackName(mode["on:begin"], "on:begin");
    if (mode["on:end"]) out.onEnd = callbackName(mode["on:end"], "on:end");
    out.contains = mode.contains.map(visit);
    if (mode.starts) out.starts = visit(mode.starts);
    modes[id] = out;
  }
  // A malformed keyword score (hy's "|" entry) is NaN, which JSON cannot hold.
  const keywords = keywordTables.map((table) => Object.entries(table).map(([word, [kind, relevance]]) => [word, kind, Number.isNaN(relevance) ? "NaN" : relevance]));
  return {
    name,
    caseInsensitive: !!language.case_insensitive,
    classNameAliases: { ...language.classNameAliases },
    keywords,
    modes,
  };
}

rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });
const index = { version, languages: [] };
let total = 0;
for (const name of order) {
  const language = hljs.getLanguage(name);
  const aliases = language.aliases === undefined ? [] : typeof language.aliases === "string" ? [language.aliases] : language.aliases;
  const entry = { name, aliases };
  if (language.disableAutodetect) entry.disableAutodetect = true;
  if (language.supersetOf) entry.supersetOf = language.supersetOf;
  index.languages.push(entry);
  const text = JSON.stringify(serializeLanguage(name));
  total += text.length;
  writeFileSync(join(outDir, `${name}.json`), text + "\n");
}
writeFileSync(join(outDir, "index.json"), JSON.stringify(index, null, 1) + "\n");
writeFileSync(join(outDir, "LICENSE"), readFileSync(join(packageDir, "LICENSE"), "utf8"));
if (unknownKeys.size) console.error(`unread mode properties: ${[...unknownKeys].join(", ")}`);
console.log(`${order.length} languages, ${total} bytes of grammar data in ${outDir}`);
