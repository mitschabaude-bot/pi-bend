// Test-only oracle for tests/markdown-render.bend: pi-mono's Markdown
// component (packages/tui/src/components/markdown.ts with marked 18.0.11).
// Writes cases.jsonl, expected.jsonl (the rendered lines) and labels.jsonl.
//
// Each Markdown source renders with several themes (plain; markers that show
// every style's extent and the inline style restoration; ANSI styles with a
// full reset in code spans; a code highlighter), default text styles,
// options and widths. Sources: the task's cross-line cases, a hand-written
// corpus of blocks, inline constructs and LLM-style answers, the Markdown of
// marked's spec tests (MARKED_SOURCE, see tests/markdown_render_check.py) and
// seeded random documents.
//
//   bun tests/markdown_render_reference.ts OUT_DIR MARKED_SOURCE [PI_MONO]
import { readFileSync, writeFileSync, readdirSync, mkdirSync } from "node:fs";
import { createHash } from "node:crypto";
import assert from "node:assert/strict";

const [out, source, root = "/home/agent/code/pi-mono"] = process.argv.slice(2);
mkdirSync(out, { recursive: true });
assert.equal(createHash("sha256").update(readFileSync(`${root}/packages/tui/src/components/markdown.ts`)).digest("hex"), "704c1c714a7ff6bdec55573ab38393726fa73a7b47cf4c1161ccc4f08530ac28");
const { Markdown } = await import(`${root}/packages/tui/src/components/markdown.ts`);
const { setCapabilities } = await import(`${root}/packages/tui/src/terminal-image.ts`);

const plain = (text: string) => text;
const wrap = (open: string, close: string) => (text: string) => `${open}${text}${close}`;
const themes: Record<string, any> = {
	plain: { heading: plain, link: plain, linkUrl: plain, code: plain, codeBlock: plain, codeBlockBorder: plain, quote: plain, quoteBorder: plain, hr: plain, listBullet: plain, bold: plain, italic: plain, strikethrough: plain, underline: plain },
	marker: {
		heading: wrap("{H:", ":H}"), link: wrap("{L:", ":L}"), linkUrl: wrap("{U:", ":U}"), code: wrap("{C:", ":C}"), codeBlock: wrap("{K:", ":K}"),
		codeBlockBorder: wrap("{F:", ":F}"), quote: wrap("{Q:", ":Q}"), quoteBorder: wrap("{q:", ":q}"), hr: wrap("{R:", ":R}"), listBullet: wrap("{B:", ":B}"),
		bold: wrap("{b:", ":b}"), italic: wrap("{i:", ":i}"), strikethrough: wrap("{s:", ":s}"), underline: wrap("{u:", ":u}"),
	},
	ansi: {
		heading: wrap("\x1b[36m", "\x1b[39m"), link: wrap("\x1b[34m", "\x1b[39m"), linkUrl: wrap("\x1b[90m", "\x1b[39m"), code: wrap("\x1b[33m", "\x1b[0m"), codeBlock: wrap("\x1b[32m", "\x1b[39m"),
		codeBlockBorder: wrap("\x1b[90m", "\x1b[39m"), quote: wrap("\x1b[35m", "\x1b[39m"), quoteBorder: wrap("\x1b[90m", "\x1b[39m"), hr: wrap("\x1b[90m", "\x1b[39m"), listBullet: wrap("\x1b[36m", "\x1b[39m"),
		bold: wrap("\x1b[1m", "\x1b[22m"), italic: wrap("\x1b[3m", "\x1b[23m"), strikethrough: wrap("\x1b[9m", "\x1b[29m"), underline: wrap("\x1b[4m", "\x1b[24m"),
	},
};
// The marker theme with a code highlighter and its own code block indent.
themes.highlight = { ...themes.marker, codeBlockIndent: "| ", highlightCode: (code: string, lang?: string) => code.split("\n").map((line) => `<${lang ?? "?"}>${line}`) };
const styles: Record<string, any> = {
	none: undefined,
	grayItalic: { color: wrap("{g:", ":g}"), italic: true },
	allFlags: { color: wrap("{c:", ":c}"), bold: true, italic: true, strikethrough: true, underline: true },
	background: { bgColor: wrap("{bg:", ":bg}"), color: wrap("\x1b[37m", "\x1b[39m") },
};

const cases: string[] = [], expected: string[] = [], labels: string[] = [];
type Options = { preserveOrderedListMarkers?: boolean; preserveBackslashEscapes?: boolean; renderLatex?: boolean; hyperlinks?: boolean };
function add(label: string, text: string, width: number, theme = "plain", style = "none", options: Options = {}, paddingX = 0, paddingY = 0) {
	setCapabilities({ images: null, trueColor: false, hyperlinks: !!options.hyperlinks });
	const { hyperlinks, ...markdownOptions } = options;
	const lines = new Markdown(text, paddingX, paddingY, themes[theme], styles[style], markdownOptions).render(width);
	cases.push(JSON.stringify({ text, width, theme, style, paddingX, paddingY, preserveOrderedListMarkers: !!options.preserveOrderedListMarkers, preserveBackslashEscapes: !!options.preserveBackslashEscapes, renderLatex: options.renderLatex !== false, hyperlinks: !!hyperlinks }));
	expected.push(JSON.stringify(lines));
	labels.push(JSON.stringify(label));
}

// The divergences named in the task (soft line breaks inside inline
// constructs), each at width 40 in the plain and marker themes.
const crossLine = ["**bold\nstill bold** end", "*it\nalic*", "`code\nspan`", "para [link\ntext](https://x.y) z"];
for (const text of crossLine) for (const theme of ["plain", "marker"]) add(`cross-line ${theme}`, text, 40, theme);

const corpus: string[] = [
	// headings
	"# H1\n## H2\n### H3 with `code`\n#### H4 **bold**\n##### H5\n###### H6", "Setext one\n===\n\nSetext two\n---\n\nText", "# Closing #\n\n## Trailing ## hashes ##", "#No space\n\n#\tTab",
	// paragraphs and breaks
	"First line\nsecond line\nthird", "Hard  \nbreak and\\\nbackslash break", "A paragraph\n\n\n\nafter blank lines", "  leading spaces\n   more", "trailing spaces   ",
	// emphasis
	"**bold** *italic* ***both*** __b__ _i_ ___bi___", "**nested *em* inside** and *em **strong** em*", "snake_case and __init__ and a*b*c", "~~strike~~ ~single~ ~~multi\nline~~", "**unclosed bold and *em", "*a **b** c*", "**a**b**c**", "**foo*bar**", "a * b * c", "_under_score_", "***", "** not bold **",
	// code
	"Inline `code` and ``double `tick` code`` and ` spaced `", "```\nplain fence\n```", "```python\ndef f():\n    return 1\n```\nafter", "~~~js\ntilde fence\n~~~", "    indented code\n    block\n\nparagraph", "```\nunclosed fence\nline", "```js\ncode\n``", "```js\ncode\n`", "- item\n  ```\n  code in item\n  ```", "> ```\n> quoted code\n> ```",
	// lists
	"- one\n- two\n- three", "1. one\n2. two\n3. three", "3. three\n4. four", "- a\n  - b\n    - c\n      - d\n- e", "1. a\n   1. b\n   2. c\n2. d", "- loose\n\n- list\n\n- items", "- tight\n- list\n\n  continued para", "- [ ] todo\n- [x] done\n- [X] upper", "- [ ] loose task\n\n- [x] done task", "* star\n* list\n\n+ plus\n+ list", "- a\nlazy continuation\n- b", "1) paren\n2) list", "- \n- empty items\n-", "10. ten\n11. eleven", "- item with **bold** and `code` that is long enough to wrap at narrow widths for sure", "1. first\n\n   second paragraph of first\n\n2. second",
	"- parent\n  > quote in list", "- a\n\n  ```\n  code\n  ```\n- b",
	// blockquotes
	"> quote\n> more", "> quote\nlazy line", "> > nested\n> > quote\n> back", "> - list in quote\n> - more", "> # heading in quote\n> text", "> quote with **bold** and `code`\n\nafter", "> a\n>\n> b", ">no space", "> 1. one\n> 2. two\n\nparagraph",
	// tables
	"| a | b |\n|---|---|\n| 1 | 2 |", "| Left | Center | Right |\n|:-----|:------:|------:|\n| l | c | r |", "| a |\n|---|\n| only one column |", "a | b\n--|--\n1 | 2", "| h1 | h2 |\n|----|----|\n| x |", "| wide | table |\n|---|---|\n| this cell has quite a lot of text in it to wrap | short |\n| another | row |",
	"| `code` | **bold** | [link](http://x.y) |\n|---|---|---|\n| $x^2$ | ~~del~~ | *em* |", "| a | b | c | d | e |\n|---|---|---|---|---|\n| 1 | 2 | 3 | 4 | 5 |", "| escaped \\| pipe | b |\n|---|---|\n| c | d |", "|a|b|\n|-|-|\n|1|2|\n\nafter table",
	// rules, html, links
	"above\n\n---\n\nbelow", "***\n___\n- - -", "<div>\nhtml block\n</div>\n\ntext <span>inline</span> html", "<!-- comment -->\n\ntext", "[link](https://example.com) and [titled](https://e.x \"Title\") and <https://auto.link>", "https://bare.url/path?q=1 and www.example.com and user@example.com", "[ref link][ref] and [ref]\n\n[ref]: https://ref.example.com", "[undefined ref] text", "![image alt](https://img.png)", "[mail](mailto:a@b.c) <a@b.c>", "[same](https://same.com) [https://same.com](https://same.com)",
	// entities and escapes
	"&amp; &lt; &copy; &#35; &#x22;", "\\*not em\\* \\_not\\_ \\# \\[x\\] \\\\ \\`", "a \\\n b", "5 * 3 * 2", "Price: $5 and $10", "$HOME/bin and $PATH:x",
	// LaTeX
	"Inline $x^2 + y^2$ math", "$$\n\\frac{a}{b}\n$$", "\\(\\alpha\\) and \\[\\beta\\]", "$$x$$ inline double", "Pending $\\frac{1", "$$\n\\sum_{i=0}^n i\n", "- a\n  $$\n  x\n  $$", "a $x+1 **b**\nc$",
	// unicode
	"日本語のテキスト **太字** と *斜体*", "Emoji 😀 **bold 🎉** end", "Ünïcödé ß and العربية",
	// LLM-style answers
	"## Summary\n\nHere's what I changed:\n\n1. **Parser**: rewrote `lex()` to handle nested blocks.\n2. **Renderer**: added support for tables.\n   - Column widths now shrink.\n   - Cells wrap.\n3. Tests pass.\n\n```ts\nexport function lex(src: string) {\n  return tokens;\n}\n```\n\n> **Note:** run `npm test` before committing.\n\n| File | Change |\n|------|--------|\n| lexer.ts | +120 |\n| render.ts | -40 |\n",
	"I found the bug. The issue is in `src/app.ts` where the handler\ncalls `process()` twice:\n\n```diff\n- process(input);\n+ const result = process(input);\n```\n\nThis happens because:\n\n- the event fires **twice** on reload\n- the guard `if (!done)` is checked *after* the call\n\nSee [the docs](https://docs.example.com/events) for details.",
	"### Steps\n\n1. Install dependencies:\n   ```bash\n   npm install\n   ```\n2. Run the build:\n   ```bash\n   npm run build\n   ```\n3. Start:\n\n   ```bash\n   npm start\n   ```\n\n---\n\n*Done!*",
];
const widths = [20, 40, 80];
corpus.forEach((text, index) => {
	for (const width of widths) add(`corpus ${index + 1} plain`, text, width);
	add(`corpus ${index + 1} marker`, text, 40, "marker");
	add(`corpus ${index + 1} ansi`, text, 30, "ansi");
	add(`corpus ${index + 1} highlight`, text, 50, "highlight");
	add(`corpus ${index + 1} default style`, text, 40, "marker", index % 2 ? "grayItalic" : "allFlags");
	add(`corpus ${index + 1} background padded`, text, 36, "ansi", "background", {}, 2, 1);
	add(`corpus ${index + 1} options`, text, 40, "marker", "none", { preserveOrderedListMarkers: true, preserveBackslashEscapes: true, renderLatex: false, hyperlinks: true });
	add(`corpus ${index + 1} narrow`, text, 8, "marker");
});

// The Markdown of marked's spec tests.
const specs: string[] = [];
for (const file of ["gfm/commonmark.0.31.2.json", "gfm/gfm.0.29.json"]) for (const example of JSON.parse(readFileSync(`${source}/test/specs/${file}`, "utf8"))) specs.push(example.markdown);
for (const directory of ["new", "original"]) {
	for (const name of readdirSync(`${source}/test/specs/${directory}`).filter((name) => name.endsWith(".md")).sort()) {
		specs.push(readFileSync(`${source}/test/specs/${directory}/${name}`, "utf8").replace(/^---\n[\s\S]*?\n---\n/, ""));
	}
}
specs.forEach((text, index) => {
	add(`spec ${index + 1} plain`, text, 60);
	add(`spec ${index + 1} marker`, text, 32, "marker", index % 3 ? "none" : "grayItalic");
});

// Seeded random documents.
let seed = 0x6d2b79f5;
const random = () => { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return (seed >>> 0) / 4294967296; };
const pick = <T,>(items: T[]) => items[Math.floor(random() * items.length)];
const inlines = ["word", "longerword", "two words", "**b**", "*i*", "_u_", "`c`", "~~s~~", "[l](http://a.b)", "[r]", "<b>", "\\*", "&amp;", "http://x.y", "a@b.co", "$m^2$", "\\(x\\)", "**", "*", "_", "`", "~~", "[", "]", "!", "<", "\\", "  ", "é", "😀", "中文字", "$"];
const blockStarts = ["", "", "", "# ", "### ", "> ", "> > ", "- ", "  - ", "1. ", "- [ ] ", "| a | b |\n|---|---|\n| ", "```\n", "---\n", "[r]: http://r.s\n", "$$\n", "Title\n===\n", "    "];
for (let index = 0; index < 300; index++) {
	const lines: string[] = [];
	const count = 1 + Math.floor(random() * 7);
	for (let line = 0; line < count; line++) {
		let text = pick(blockStarts);
		const words = 1 + Math.floor(random() * 8);
		for (let word = 0; word < words; word++) text += (word > 0 && random() < 0.7 ? " " : "") + pick(inlines);
		lines.push(text);
		if (random() < 0.3) lines.push("");
	}
	const text = lines.join("\n");
	add(`random ${index + 1}`, text, pick([12, 24, 40, 72]), pick(["plain", "marker", "ansi", "highlight"]), pick(["none", "none", "grayItalic", "background"]), random() < 0.2 ? { preserveOrderedListMarkers: true, hyperlinks: true } : {});
}

writeFileSync(`${out}/cases.jsonl`, cases.join("\n") + "\n");
writeFileSync(`${out}/expected.jsonl`, expected.join("\n") + "\n");
writeFileSync(`${out}/labels.jsonl`, labels.join("\n") + "\n");
console.log(`${cases.length} cases`);
