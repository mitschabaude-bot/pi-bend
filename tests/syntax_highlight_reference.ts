// Test-only oracle for tests/syntax-highlight.bend: pi-mono's
// utils/syntax-highlight.ts, theme.ts highlightCode/getLanguageFromPath and
// the TUI Markdown component with getMarkdownTheme(). Writes the cases and
// upstream's result for each (as JSON, one per line).
//
//   bun tests/syntax_highlight_reference.ts OUT_DIR
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { snippets } from "./highlight_snippets.mjs";

const out = process.argv[2] ?? "build/syntax-highlight";
const root = "/home/agent/code/pi-mono";
const sh = await import(`${root}/packages/coding-agent/src/utils/syntax-highlight.ts`);
const themeModule = await import(`${root}/packages/coding-agent/src/modes/interactive/theme/theme.ts`);
const { Markdown } = await import(`${root}/packages/tui/src/components/markdown.ts`);
themeModule.setThemeInstance(themeModule.loadThemeFromPath(`${root}/packages/coding-agent/src/modes/interactive/theme/dark.json`, "truecolor"));

const markerKeys = ["keyword", "built_in", "type", "literal", "number", "regexp", "string", "subst", "symbol", "class", "function", "title", "params", "comment", "doctag", "meta", "section", "tag", "name", "attr", "attribute", "variable", "bullet", "code", "emphasis", "strong", "formula", "link", "quote", "selector", "template", "addition", "deletion", "operator", "punctuation"];
const markerTheme = (withDefault: boolean) => {
  const theme: Record<string, (text: string) => string> = {};
  for (const key of [...markerKeys, ...(withDefault ? ["default"] : [])]) theme[key] = (text) => `[${key}:${text}]`;
  return theme;
};

type Case = Record<string, unknown> & { kind: string };
const cases: Case[] = [];
const eager = ["python", "java", "go", "javascript", "cpp", "typescript", "php", "ruby", "c", "csharp", "nix", "bash", "rust", "scala", "kotlin", "swift", "dart", "groovy", "perl", "lua"];
const probes = [...eager, "ada", "json", "xml", "html", "yaml", "ts", "js", "py", "sh", "TypeScript", "c++", "h", "rs", "golang", "unknown", ""];

// Before loadAllHighlightLanguages: the eager registry.
for (const language of probes) cases.push({ kind: "supports", language });
for (const { language, code } of snippets.slice(0, 12)) cases.push({ kind: "highlight", language, code, default: false });
cases.push({ kind: "highlight", language: "json", code: '{"a": 1}', default: false });
cases.push({ kind: "highlight", language: "php", code: "<p><?php echo 1; ?></p>", default: false });
cases.push({ kind: "highlight", language: "typescript", code: "const x = html`<b>${y}</b>`; <div>a</div>;", default: false });
cases.push({ kind: "highlightCode", language: "json", code: '{"a": 1}\n' });
cases.push({ kind: "highlightCode", language: "python", code: "@decorator\ndef f(): pass" });
cases.push({ kind: "markdown", text: "```json\n{\"a\": [1, true]}\n```" });

// Upstream "highlights code through highlight.js".
cases.push({ kind: "highlight", language: "typescript", code: "const value = 1", default: false });
cases.push({ kind: "loadAll" });

// After: every language.
for (const language of probes) cases.push({ kind: "supports", language });
for (const [index, { language, code }] of snippets.entries()) cases.push({ kind: "highlight", language, code, default: index % 3 === 0 });
const codeCases: Array<[string | undefined, string]> = [
  ["diff", "-old\n+new\n"],
  ["javascript", "const re = /foo+/gi;"],
  ["python", "@decorator"],
  ["html", "<div></div>"],
  ["typescript", "interface A { b: string }\n// done\n"],
  ["rust", "fn main() {\n    println!(\"hi\");\n}"],
  ["json", '{"a": [1, 2.5, null]}'],
  ["yaml", "a: 1\nb: [x, y]\n"],
  ["sql", "SELECT * FROM t WHERE a = 'x';"],
  ["css", "a { color: red; }"],
  ["markdown", "# Title\n\n*em* **strong** `code`\n"],
  ["bash", "echo \"$HOME\" | grep -v x"],
  ["xml", "<a href=\"x\">t</a>"],
  ["unknownlang", "plain text"],
  [undefined, "no language"],
  ["", "empty language"],
  ["c", "/* a\n   b */\nint x;"],
];
for (const [language, code] of codeCases) cases.push({ kind: "highlightCode", language, code });
const markdown = [
  "```typescript\nconst a: number = 1; // one\n```",
  "Text before\n\n```python\ndef f(x):\n    return x * 2  # double\n```\n\nafter",
  "```diff\n-old\n+new\n```",
  "```\nno language\n```",
  "```nosuchlanguage\nplain\n```",
  "```html\n<div class=\"a\">hi</div>\n```",
  "```sh\nls -la | grep x\n```",
  "```json\n{\n  \"a\": [1, true]\n}\n```",
  "```go\npackage main\n\nfunc main() {}\n```",
];
for (const text of markdown) cases.push({ kind: "markdown", text });
const paths = ["a.ts", "b.TSX", "c.py", "Makefile", "dir/Dockerfile", "x.tar.gz", "noext", "file.", ".bashrc", "a.b/c", "script.SH", "main.rs", "x.yml", "x.hcl", "notes.md", "a.cxx", "a.ps1"];
for (const path of paths) cases.push({ kind: "path", path });
const htmls = [
  '<span class="hljs-keyword">const</span> value',
  "&lt;tag attr=&quot;value&quot;&gt;&amp;#x41;&#65;&lt;/tag&gt;",
  '<span class="hljs-string">a<span class="hljs-subst">${x}</span>b</span>',
  '<span class="hljs-string">a<span class="language-xml">b</span>c</span>',
  '<span class="hljs-meta hljs-keyword">x</span><span class="other hljs-title">y</span>',
  '<span class=\'hljs-number\'>1</span><span>plain</span><span\tclass="hljs-comment">c</span>',
  "&#x1F600;&#128512;&#xZZ;&#; &unknown; &amp &#x110000; & alone",
  '<spanx class="hljs-keyword">k</span>',
  "</span>unbalanced",
];
for (const html of htmls) cases.push({ kind: "html", html });

// Results, in order (loadAll switches the registry between the two halves).
const results: string[] = [];
for (const item of cases) {
  switch (item.kind) {
    case "supports": results.push(JSON.stringify(sh.supportsLanguage(item.language as string))); break;
    case "highlight": {
      let value: string | null;
      try { value = sh.highlight(item.code as string, { language: item.language as string, ignoreIllegals: true, theme: markerTheme(item.default as boolean) }); } catch { value = null; }
      results.push(JSON.stringify(value));
      break;
    }
    case "highlightCode": results.push(JSON.stringify(themeModule.highlightCode(item.code as string, item.language as string | undefined))); break;
    case "markdown": results.push(JSON.stringify(new Markdown(item.text as string, 1, 0, themeModule.getMarkdownTheme()).render(60))); break;
    case "path": results.push(JSON.stringify(themeModule.getLanguageFromPath(item.path as string) ?? null)); break;
    case "html": results.push(JSON.stringify(sh.renderHighlightedHtml(item.html as string, markerTheme(false)))); break;
    case "loadAll": await sh.loadAllHighlightLanguages(); results.push("null"); break;
  }
}
mkdirSync(out, { recursive: true });
writeFileSync(join(out, "cases.jsonl"), cases.map((c) => JSON.stringify(c)).join("\n") + "\n");
writeFileSync(join(out, "expected.jsonl"), results.join("\n") + "\n");
console.log(`${cases.length} syntax highlight cases`);
