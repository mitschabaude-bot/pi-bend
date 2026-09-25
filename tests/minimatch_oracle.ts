// Test-only oracle: pi-mono's pinned minimatch@10.2.6 (with brace-expansion@5.0.9)
// on posix with default options. Prints {match, brace}: `match` holds
// [path, pattern, expected] with expected "true", "false" or "throw" (the
// upstream constructor throws), `brace` holds [pattern, expansions joined by U+001E].
import { UPSTREAM } from "./upstream_pin.mjs";
const { minimatch, braceExpand } = await import(UPSTREAM + "/node_modules/minimatch/dist/esm/index.js");

let seed = 0x5eed1234;
function random(): number {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const pick = <T>(values: T[]): T => values[Math.floor(random() * values.length)];
const count = (n: number) => Math.floor(random() * n);

const cases: [string, string, string][] = [];
const seen = new Set<string>();
function add(path: string, pattern: string) {
  // The Bend fixture receives cases as UTF-8 process arguments separated by U+001F.
  if (/[\u0000\u001e\u001f]/.test(path + pattern)) return;
  if (/[\ud800-\udfff]/u.test(path + pattern)) return;
  const key = path + "\u001f" + pattern;
  if (seen.has(key)) return;
  seen.add(key);
  let expected: string;
  try { expected = String(minimatch(path, pattern)); } catch { expected = "throw"; }
  cases.push([path, pattern, expected]);
}

// Hand-picked cases after minimatch's own test/patterns.ts and bash's glob tests.
const files = ["a", "b", "c", "d", "abc", "abd", "abe", "bb", "bcd", "ca", "cb", "dd", "de", "bdir/", "bdir/cfile",
  "a-b", "aXb", ".x", ".y", "a/b", "a/.b", ".a/b", "a/b/c", "a/b/c/d", "a/b/", "a//b", "/a", "/a/b", "a/", "/", "//", "",
  ".", "..", "./a", "../a", "a/..", "a/../b", "a/./b", "x/y/z/.w", "a.js", "b.JS", ".js", "x/a.js", "x/.a.js", "a.b.c",
  "man/man1/bash.1", "s/..*//", "/^root:/{s/^[^:]*:[^:]*:\\([^:]*\\).*$/\\1/", "a*", "*", "**", "\\*", "a\\*", "[", "[]",
  "a[b]c", "abc/", "a/b/c/", "x/y", "a.b", "#a", "!a", "{a,b}", "a,b", "{}", "ab", "aab", "abab", "abcd", "acd",
  "é", "éa", "😀", "a😀b", "\t", " ", "a b", "A", "Z", "_", "-", "]", "^", "\\", "()", "@()", "+()", "!()",
  "a.a", "a.b/c", ".a", "..a", "a..", "...", "xyz", "xyzzy", "zzz", "q/r/s/t", "a/b/c/d/e/f", "a/x/y/z/b", "a/.x/b",
  "a/x/b/", "a/b/x", "foo.txt", "foo/bar.txt", "src/index.ts", "node_modules/x/index.js", ".git/config", "a/.git/b"];
const patterns = ["a*", "X*", "\\*", "\\**", "\\*\\*", "b*/", "c*", "**", "\\.\\./*/", "s/\\..*//", "/^root:/{s/^[^:]*:[^:]*:\\([^:]*\\).*$/\\1/",
  "[a-c]b*", "[a-y]*[^c]", "a*[^c]", "a[X-]b", "[^a-c]*", "a\\*b/*", "a\\*?/*", "*\\\\!*", "*\\!*", "*.\\*", "a[b]c",
  "a[\\b]c", "a?c", "a\\*c", "", "*/man*/bash.*", "man/man1/bash.1", "a***c", "a*****?c", "?*****??", "*****??",
  "?*****?c", "?***?****c", "?***?****?", "?***?****", "*******c", "*******?", "a*cd**?**??k", "a**?**cd**?**??k",
  "a**?**cd**?**??k***", "a**?**cd**?**??***k", "a**?**cd**?**??***k**", "a****c**?**??*****", "[-abc]", "[abc-]",
  "\\", "[\\\\]", "[[]", "[", "[*", "a[", "a[a-c]", "a[]]", "[]]", "[!]]", "[^]]", "[\\]]", "[]-a]", "[a-]", "[!a-]",
  "*.js", "**/*.js", "*.{js,ts}", "{a,b}", "{a,b}/**", "a/{b,c}/d", "{1..3}", "{01..10}", "{a..e..2}", "a{,b}c",
  "{}", "{},a}b", "a{},b}c", "{a},b}", "x{{a,b}}y", "{-01..5}", "{9..-2..3}", "${a,b}", "\\{a,b}", "{a\\,b,c}",
  "{a..c}{1..2}", "{Z..a}", "{a..Z}", "{1..10..0}", "{3..1}", "{a,b{c,d}}", "{a,{b,c}d}", "a{b}c", "a{2..}b",
  "{a,b}{c,d}{e,f}", "{,}", "{,a}", "{a,}", "{{a,b}}", "\\{", "{\\}", "a{\\,,b}", "{a.b,c}", "{1.2..3}", "{a..}",
  "#comment", "\\#a", "#", "!a", "!!a", "!!!a", "!", "!*", "!*.js", "a/**", "a/**/", "**/b", "a/**/b", "**/.x",
  "**/*", "*/**", "a/**/**/b", "**/**", "a/*/b", "a/*", "*/", "a/", "/a", "/*", "//a", "a//b", "*/*", "*/*/*",
  "a/../b", "../a", "./a", "a/./b", "a/b/..", "**/..", "**/../a", ".*", "*.*", "*.", ".", "..", "./*", "*/.",
  ".x", ".*/*", "*/.*", "a/.*", "?", "??", "???", "?/?", "?.js", "??.js", "a?", ".?", "[.]x", "[.]*", "\\.x",
  "[[:alpha:]]", "[[:digit:]]*", "[[:alnum:]_]", "[![:space:]]", "[[:upper:][:lower:]]", "[[:xdigit:]]",
  "[[:punct:]]", "[[:ascii:]]", "[[:graph:]]", "[[:print:]]", "[[:blank:]]", "[[:cntrl:]]", "[[:word:]]",
  "[[:alpha:]-]", "[a-[:alpha:]]", "[[:alpha:]]x", "[[:bogus:]]", "[[:alpha:]", "[z-a]", "[a-a]", "[b-a]x",
  "+(a|b)", "*(a|b)", "?(a|b)", "@(a|b)", "!(a|b)", "+(a|b)c", "*(a|b)c", "!(a)", "!(a)*", "*!(a)", "a!(b)c",
  "!(!(a))", "!(!(!(a)))", "!(*.js)", "!(*.js|*.ts)", "@(x|y)", "*(+(a|b)|c)", "+(*(a|b)|c)", "?(?(a))", "@(@(a))",
  "!(@(a|b))", "!(?(a|b))", "@(?(a|b))", "+(?(a|b))", "+(*(a))", "*(?(a|b))", "!(a|?(b))", "@(a|!(b))", "!(a)b",
  "!(a)!(b)", "!(a)!(b)c", "!(a!(b)c)d", "!(!(x))y", "!(!(!(x)))y", "@(a|!(!(b)))c", "@()", "+()", "*()", "?()", "!()",
  "!(a)+()", "!(+())", "@(|)", "+(|)", "*(|a)", "!(|)", "!(a|)", "x@()", "a+(b", "+(*", "*(a|b", "!(a", "@(a|",
  "+(a|b))", "(a|b)", "a|b", "+(a|b|c)", "*(a|b|c).js", "*.+(js|ts)", "!(*.d).ts", "a+(.)b", "+(.a)", "*(.)",
  "!(.a)", "@(.a|b)", "?(.)", "*(.*)", "+([a-c])", "*([[:alpha:]])", "!([[:digit:]])", "*(\\*)", "+(\\()", "@(a\\|b)",
  "+(a|[)", "+(a|[|])", "@([)|a)", "*(a|[!)])", "+(+(+(+(a))))", "*(*(*(*(a))))", "@(!(a)|b)", "!(?(a)b)",
  "a/!(b)/c", "!(a)/b", "**/!(*.js)", "+(a)/**", "@(a|b)/@(c|d)", "a/+(b)/", "[!a]", "[^a]", "[!a-c]x", "[\\-]",
  "[a\\]b]", "[\\\\-]", "[\\-\\\\]", "[a-c-e]", "[--0]", "[!--0]", "é", "?é", "[é]", "😀", "?", "[😀]", "a?b",
  "*😀", "\\😀", "[a-é]", "[é-a]", "[[:alpha:]]😀", "\t", "[\t]", "[[:space:]]", "a b", "a\\ b", "[ ]", "*,*", "[,]",
  "a#b", "[#]", "a!b", "[!!]", "a-b", "[[:alpha:]]-b", "[[:alpha:]],", "[[:alpha:]]#", "[[:alpha:]] ", "\\![[:alpha:]]",
  "[[:alpha:]]\\!", "@(a,b)", "[[:alpha:]]@(a|-)", "a{[[:alpha:]],b}", "{a,b}[[:digit:]]"];
for (const p of patterns) for (const f of files) add(f, p);

// Brace-expanded patterns are matched against their own expansions.
for (const p of patterns) {
  try { for (const e of braceExpand(p).slice(0, 8)) { add(e, p); add(e + "/", p); } } catch {}
}

// Randomized patterns over a small alphabet and paths with dot and empty segments.
const patternTokens = ["a", "a", "b", "b", "c", ".", "/", "/", "*", "*", "**", "?", "[", "]", "{", "}", ",", "!", "+", "@",
  "(", ")", "|", "\\", "-", "^", "..", "x", "[a-c]", "[!a]", "{a,b}", "{1..3}", "!(", "+(", "@(", "*(", "?(", "#", "é",
  "😀", " ", "[[:alpha:]]", "[:digit:]", ":", "$", "0", "1"];
const segmentTokens = ["a", "a", "b", "b", "c", ".", ".", "x", "-", "é", "😀", "\\", "*", "(", ")", "|", "!", "@", "1", "0", " ", ","];
function randomSegment(): string {
  const r = random();
  if (r < 0.08) return ".";
  if (r < 0.14) return "..";
  if (r < 0.2) return "";
  let s = "";
  for (let i = 1 + count(4); i > 0; i--) s += pick(segmentTokens);
  return s;
}
function randomPath(): string {
  const parts: string[] = [];
  for (let i = 1 + count(4); i > 0; i--) parts.push(randomSegment());
  let path = parts.join("/");
  if (random() < 0.1) path = "/" + path;
  if (random() < 0.15) path += "/";
  return path;
}
function randomPattern(): string {
  let s = random() < 0.08 ? "!" : "";
  for (let i = 1 + count(7); i > 0; i--) s += pick(patternTokens);
  return s;
}
// A path likely to match: expand braces, then instantiate the remaining magic.
function derivedPath(pattern: string): string {
  let expansions: string[];
  try { expansions = braceExpand(pattern.replace(/^!+/, "")); } catch { return randomPath(); }
  if (!expansions.length) return randomPath();
  const text = pick(expansions);
  let out = "";
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === "*") { if (text[i + 1] === "*") { out += pick(["", "x", "x/y", "a/b/c"]); i++; } else out += pick(["", "a", "bc", "x"]); }
    else if (c === "?") out += pick(["a", "b", "é", "."]);
    else if ("[]()|!+@\\".includes(c)) { if (random() < 0.5) out += pick(["a", "b", "c"]); }
    else out += c;
  }
  return out;
}
for (let n = 0; n < 5200; n++) {
  const pattern = randomPattern();
  add(randomPath(), pattern);
  add(derivedPath(pattern), pattern);
  add(derivedPath(pattern), pattern);
}
// Extglob-heavy random patterns.
const extTokens = ["a", "b", "c", ".", "*", "?", "|", "|", "(", ")", "!(", "+(", "@(", "*(", "?(", "!(", "[a-b]", "\\", "/"];
for (let n = 0; n < 3000; n++) {
  let pattern = "";
  for (let i = 2 + count(8); i > 0; i--) pattern += pick(extTokens);
  add(randomPath(), pattern);
  add(derivedPath(pattern), pattern);
  const flat = pattern.replace(/[!+@*?]\(|[()|]/g, () => pick(["", "a", "b", "."]));
  add(flat.replace(/[*?\[\]\\]/g, ""), pattern);
}

// POSIX classes compile to Unicode property escapes: probe every property
// range boundary that Bun reports, so the Bend Unicode tables are compared.
const classes: [string, RegExp][] = [["alnum", /[\p{L}\p{Nl}\p{Nd}]/u], ["alpha", /[\p{L}\p{Nl}]/u], ["blank", /[\p{Zs}\t]/u],
  ["cntrl", /\p{Cc}/u], ["digit", /\p{Nd}/u], ["graph", /[^\p{Z}\p{C}]/u], ["lower", /\p{Ll}/u], ["print", /\p{C}/u],
  ["punct", /\p{P}/u], ["space", /[\p{Z}\t\r\n\v\f]/u], ["upper", /\p{Lu}/u], ["word", /[\p{L}\p{Nl}\p{Nd}\p{Pc}]/u]];
for (const [name, re] of classes) {
  const probes = new Set<number>();
  let previous = re.test(String.fromCodePoint(0));
  for (let cp = 1; cp <= 0x10ffff; cp++) {
    if (cp >= 0xd800 && cp <= 0xdfff) continue;
    const now = re.test(String.fromCodePoint(cp));
    if (now !== previous) { probes.add(cp - 1); probes.add(cp); previous = now; }
  }
  for (const cp of probes) {
    if (cp === 0 || cp === 0x1f || cp === 0x2f || (cp >= 0xd800 && cp <= 0xdfff)) continue;
    add(String.fromCodePoint(cp), `[[:${name}:]]`);
  }
}

// Nested extglobs around negations exercise flattening and `!` continuations.
const nestTokens = ["!(", "!(", "@(", "?(", "+(", "*(", ")", ")", ")", "|", "a", "b", "x", ".", "*", "?"];
for (let n = 0; n < 4000; n++) {
  let pattern = "";
  for (let i = 3 + count(9); i > 0; i--) pattern += pick(nestTokens);
  let depth = 0;
  for (const c of pattern) depth += c === "(" ? 1 : c === ")" ? -1 : 0;
  if (random() < 0.8) while (depth-- > 0) pattern += ")";
  if (random() < 0.5) pattern += pick(["a", "b", "x", "ab", "*", "!(a)", "@(b|x)"]);
  add(randomPath().split("/")[0], pattern);
  add(derivedPath(pattern), pattern);
  add(pick(["a", "b", "x", "ab", "ba", "xa", "", ".a", "aab", "bx", "abx", "xx"]), pattern);
}

// Globstar body sections between several `**` against deeper paths.
const deepSegments = ["a", "b", "c", ".d", "", "..", "."];
for (let n = 0; n < 2500; n++) {
  const parts: string[] = [];
  for (let i = 2 + count(6); i > 0; i--) parts.push(pick(["**", "**", "a", "b", "*", "?", ".d", "c", "{a,b}", "!(a)"]));
  const pattern = parts.join("/") + (random() < 0.2 ? "/" : "");
  const path: string[] = [];
  for (let i = 1 + count(9); i > 0; i--) path.push(pick(deepSegments));
  add(path.join("/"), pattern);
  add(derivedPath(pattern), pattern);
}

// UTF-16 width: `?` and classes see code units unless a POSIX class adds `u`.
for (const pattern of ["?", "??", "???", "?😀", "😀?", "[😀]", "[😀]?", "[^a]", "[^a][^a]", "*", "[[:alpha:]]", "[[:alpha:]]?", "[[:so:]]", "x[😀-😁]", "[a-😀]", "[😀-a]", "[[:alpha:]😀]", "[[:alpha:]a-😀]", "?(😀)", "+(😀)", "!(😀)", "😀*", "*😀", "[!😀]", "𝒳", "?𝒳"])
  for (const path of ["😀", "😀😀", "a😀", "😁", "a", "ab", "é", "𝒳", "a𝒳", "\ud83d"]) add(path, pattern);

// Long inputs and the maxGlobstarRecursion (200) cap.
add("x".repeat(30000), "x".repeat(30000));
add("x".repeat(29999) + "y", "x".repeat(30000));
add("x".repeat(30000), "*");
add("x".repeat(30000), "*x");
add("a".repeat(300), "*a".repeat(300) + "b");
add(Array(1000).fill("a").join("/"), "**/a");
add(Array(1000).fill("a").join("/"), "a/**");
add(Array(1000).fill("a").join("/") + "/.b", "**");
add("a" + "x".repeat(30000), "{a,b}" + "x".repeat(30000));
add("x".repeat(30000), "{" + "x".repeat(30000) + ",b}");
add("a", "+(" + "b|".repeat(10000) + "a)");
add("b".repeat(50), "+(" + "b|".repeat(10000) + "a)");
add("a", "[" + "b".repeat(30000) + "a]");
add("x", "!(" + "a".repeat(30000) + ")");
add("x".repeat(3000), "*(x)");
add("x".repeat(3000) + "y", "*(x)");
add("x".repeat(2000), "+(x|xx)");
add("ab".repeat(1000), "*(a|b)*(a|b)");
add(Array(3000).fill("a").join("/"), "**/a/**/a");
for (const sections of [150, 199, 200, 201, 250]) {
  const pattern = "**/" + "a/**/".repeat(sections) + "b";
  add(Array(sections + 2).fill("a").join("/") + "/b", pattern);
  add(Array(sections).fill("a").join("/") + "/b", pattern);
}

// brace-expansion results through minimatch.braceExpand.
const braces: [string, string][] = [];
const braceSeen = new Set<string>();
function addBrace(pattern: string) {
  if (/[\u0000\u001e\u001f]/.test(pattern) || /[\ud800-\udfff]/u.test(pattern) || braceSeen.has(pattern)) return;
  braceSeen.add(pattern);
  braces.push([pattern, braceExpand(pattern).join("\u001e")]);
}
for (const p of patterns) addBrace(p);
for (const p of ["{1..3}", "{01..10}", "{-05..5..3}", "{a..e..2}", "{9..-2..3}", "{1..3..0}", "{-0..2}", "{0..-0}", "{1e3..2}",
  "a{b,c{d,e}f}g", "{a,b}{c,d}{e,f}", "{,}", "{,,a}", "x{,}y", "{Z..c}", "{c..Z}", "{A..A}", "{1..2}{a..b}", "{007..9}",
  "{-10..-7}", "{-1..-01}", "{1..2000}", "{a,b}".repeat(12), "{99999999999999999999..100000000000000000001}",
  "{9007199254740990..9007199254740995}", "{-9007199254740993..-9007199254740990}", "{1..5..-2}", "{5..1..2}", "{a..f..-2}",
  "\\{a,b}", "\\\{a,b}", "{a\\,b}", "{a\\\,b}", "{\\.}", "{a..c\\}", "{},{a,b}", "a{}b{c,d}", "{a{b,c}", "{a,b}}", "}{a,b}{",
  "{$a,b}", "${a,b}{c,d}", "$${a,b}", "{a,b\n}", "{a\nb,c}", "{\na,b}", "é{😀,x}", "{😀..😁}", "{é..a}", "{a..é}"]) addBrace(p);
const braceTokens = ["{", "}", ",", ".", "..", "a", "b", "\\", "$", "1", "2", "-", "0", "z", "A", "{a,b}", "{1..3}", "\n", "é", "😀", "{}", ",,", "{a..c}", "{0..2}"];
for (let n = 0; n < 6000; n++) {
  let s = "";
  for (let i = 1 + count(10); i > 0; i--) s += pick(braceTokens);
  addBrace(s);
}

process.stdout.write(JSON.stringify({ match: cases, brace: braces }));
