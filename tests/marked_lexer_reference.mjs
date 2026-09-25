// Test-only oracle for tests/marked-lexer.bend: marked 18.0.11's Lexer from
// pi-mono's installed package, and the inputs and expectations of marked's
// own tests from its v18.0.11 source archive (downloaded by
// tests/marked_lexer_check.py):
//
// - test/unit/Lexer.test.js: every expectTokens/expectInlineTokens call under
//   its test name, with the test's expected tokens (and links);
// - the Markdown of test/specs (CommonMark and GFM examples, new/, original/,
//   redos/), lexed by marked with the options of each spec;
// - a hand-written corpus and seeded random documents.
//
// Writes cases.jsonl (input), expected.jsonl and labels.jsonl to OUT_DIR.
//   bun tests/marked_lexer_reference.mjs OUT_DIR MARKED_SOURCE [PI_MONO]
import { readFileSync, writeFileSync, readdirSync, mkdirSync } from "node:fs";
import assert from "node:assert/strict";

const [out, source, pi = "/home/agent/code/pi-mono"] = process.argv.slice(2);
mkdirSync(out, { recursive: true });
const { Lexer } = await import(`${pi}/node_modules/marked/lib/marked.esm.js`);

// The fields of packages/runtime/src/marked/tokens.bend; absent optional
// fields are null, an absent text-token list empty, `escaped` false.
const orNull = (value) => (value === undefined ? null : value);
function token(t) {
	const tokens = (list) => (list ?? []).map(token);
	switch (t.type) {
		case "blockquote": return { type: t.type, raw: t.raw, text: t.text, tokens: tokens(t.tokens) };
		case "br": case "hr": case "space": return { type: t.type, raw: t.raw };
		case "checkbox": return { type: t.type, raw: t.raw, checked: t.checked };
		case "code": return { type: t.type, raw: t.raw, codeBlockStyle: orNull(t.codeBlockStyle), lang: orNull(t.lang), text: t.text };
		case "codespan": case "escape": return { type: t.type, raw: t.raw, text: t.text };
		case "def": return { type: t.type, raw: t.raw, tag: t.tag, href: t.href, title: orNull(t.title) };
		case "del": case "em": case "strong": case "paragraph": return { type: t.type, raw: t.raw, text: t.text, tokens: tokens(t.tokens) };
		case "heading": return { type: t.type, raw: t.raw, depth: t.depth, text: t.text, tokens: tokens(t.tokens) };
		case "html": return t.block
			? { type: t.type, raw: t.raw, pre: !!t.pre, text: t.text, block: true }
			: { type: t.type, raw: t.raw, inLink: !!t.inLink, inRawBlock: !!t.inRawBlock, text: t.text, block: false };
		case "image": case "link": return { type: t.type, raw: t.raw, href: t.href, title: orNull(t.title), text: t.text, tokens: tokens(t.tokens) };
		case "list": return { type: t.type, raw: t.raw, ordered: t.ordered, start: t.start === "" ? null : t.start, loose: t.loose, items: tokens(t.items) };
		case "list_item": return { type: t.type, raw: t.raw, task: t.task, checked: orNull(t.checked), loose: t.loose, text: t.text, tokens: tokens(t.tokens) };
		case "table": {
			const cell = (c) => ({ text: c.text, tokens: tokens(c.tokens), header: c.header, align: c.align });
			return { type: t.type, raw: t.raw, align: t.align, header: t.header.map(cell), rows: t.rows.map((row) => row.map(cell)) };
		}
		case "text": return { type: t.type, raw: t.raw, text: t.text, tokens: tokens(t.tokens), escaped: !!t.escaped };
		default: return { type: t.type, raw: t.raw };
	}
}
const linksOf = (links) => Object.fromEntries(Object.entries(links ?? {}).map(([tag, link]) => [tag, { href: link.href, title: orNull(link.title) }]));

const cases = [], expected = [], labels = [];
// Options the port has: GFM (marked's default) with or without breaks.
const supported = (options) => options === undefined || (options.gfm === true && !options.pedantic && Object.keys(options).every((key) => ["gfm", "breaks"].includes(key)));
function add(label, md, { options, inline = false, links = {}, tokens, lexedLinks } = {}) {
	const breaks = !!options?.breaks;
	cases.push(JSON.stringify({ text: md, inline, breaks, links: Object.entries(links).map(([tag, link]) => [tag, link.href, orNull(link.title)]) }));
	expected.push(JSON.stringify(inline ? { tokens } : { tokens, links: lexedLinks }));
	labels.push(supported(options) ? label : `unsupported options ${JSON.stringify(options)}: ${label}`);
}
function lexed(md, options) {
	const lexer = new Lexer({ ...(options ?? { gfm: true }) });
	const tokens = lexer.lex(md);
	return { tokens: tokens.map(token), lexedLinks: linksOf(tokens.links) };
}

// Lexer.test.js
{
	let text = readFileSync(`${source}/test/unit/Lexer.test.js`, "utf8");
	text = text.replace(/^import .*$/gm, "").replace(/function expectTokens\(/, "function expectTokensUpstream(").replace(/function expectInlineTokens\(/, "function expectInlineTokensUpstream(");
	const names = [];
	let current = "";
	const describe = (name, body) => { names.push(name); body(); names.pop(); };
	const it = (name, body) => { names.push(name); current = names.join(" > "); body(); names.pop(); };
	const expectTokens = ({ md, options, tokens = [], links = {} }) => {
		const wanted = { tokens: tokens.map(token), lexedLinks: linksOf(links) };
		// The test's expectation is marked's result.
		assert.deepEqual(new Lexer(options && { ...options }).lex(md).map(token), wanted.tokens);
		add(`Lexer.test.js: ${current}`, md, { options, ...wanted });
	};
	const expectInlineTokens = ({ md, options, tokens, links = {} }) => {
		add(`Lexer.test.js: ${current}`, md, { options, inline: true, links, tokens: tokens.map(token) });
	};
	new Function("describe", "it", "assert", "Lexer", "expectTokens", "expectInlineTokens", text)(describe, it, assert, Lexer, expectTokens, expectInlineTokens);
}

// Spec Markdown, lexed by marked.
function frontMatter(md) {
	const match = /^---\n([\s\S]*?)\n---\n/.exec(md);
	if (!match) return { md, options: {} };
	const options = {};
	for (const line of match[1].split("\n")) {
		const [key, value] = line.split(":").map((part) => part.trim());
		if (key) options[key] = value === "true" ? true : value === "false" ? false : value;
	}
	return { md: md.slice(match[0].length), options };
}
for (const [file, group] of [["gfm/commonmark.0.31.2.json", "CommonMark"], ["gfm/gfm.0.29.json", "GFM"]]) {
	for (const example of JSON.parse(readFileSync(`${source}/test/specs/${file}`, "utf8"))) {
		add(`${group} example ${example.example} (${example.section})`, example.markdown, lexed(example.markdown));
	}
}
for (const directory of ["new", "original", "redos"]) {
	for (const name of readdirSync(`${source}/test/specs/${directory}`).filter((name) => name.endsWith(".md")).sort()) {
		const { md, options } = frontMatter(readFileSync(`${source}/test/specs/${directory}/${name}`, "utf8"));
		const lexerOptions = { gfm: options.gfm ?? true, ...(options.breaks ? { breaks: true } : {}), ...(options.pedantic ? { pedantic: true } : {}) };
		add(`specs/${directory}: ${name}`, md, { options: lexerOptions, ...lexed(md, lexerOptions) });
	}
}

// Hand-written corpus: pi's answers, soft line breaks, nesting, references.
const corpus = [
	"**bold\nstill bold** end", "*it\nalic*", "`code\nspan`", "para [link\ntext](https://x.y) z",
	"- a\n  - b\n    - c\n- d", "1. one\n\n2. two\n\n   para", "> quote\nlazy\n> - item\n>   more", "> > nested\n> back",
	"Title\n=====\n\nSub\n---", "[ref]: https://example.com \"T\"\n\nSee [ref] and [text][ref] and [none].", "<div>\nblock\n</div>\n\ninline <span>x</span>",
	"&amp; &copy; \\* \\_ \\\\ \\`", "| a | b |\n|:-|-:|\n| 1 | 2 |\n| 3 |", "- [ ] todo\n- [x] done\n\n- [ ] loose", "~~del~~ ~one~ ~~~three~~~",
	"www.example.com, https://x.y/z?q=1). user@example.com", "***strong em*** __a__ _b_ *c*", "line  \nbreak\\\nhere", "```js\nconst x = 1;\n```\n\n~~~\ntilde\n~~~",
	"    indented\n    code\n\npara", "# H1 #\n## H2 ##\n###### H6", "Text with $x^2$ math and \\(y\\)", "A\n***\nB\n___\nC", "1) paren\n2) list", "* star\n+ plus\n- dash",
	"<!-- comment -->\n\n<?php x ?>", "![img](a.png \"t\") [a](<b c>) [d](e 'f')", "**nested *em* in strong**", "a_b_c snake_case __init__", "\t tab\n\ttabbed",
];
corpus.forEach((md, index) => add(`corpus ${index + 1}`, md, lexed(md)));

// Seeded random documents from block and inline fragments.
let seed = 0x2545f491;
const random = () => { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return (seed >>> 0) / 4294967296; };
const pick = (items) => items[Math.floor(random() * items.length)];
const inlines = ["word", "two words", "**b**", "*i*", "_u_", "`c`", "~~s~~", "[l](http://a.b)", "[r]", "<b>", "\\*", "&amp;", "http://x.y", "a@b.co", "$m$", "**", "*", "_", "`", "~", "[", "]", "(", ")", "!", "<", ">", "\\", "  ", "é", "😀", "中文"];
const blockStarts = ["", "", "", "# ", "## ", "> ", "- ", "* ", "1. ", "2) ", "    ", "- [ ] ", "| ", "```\n", "---\n", "***\n", "[r]: http://r.s\n", "<div>\n", "Setext\n===\n", "\t"];
for (let index = 0; index < 400; index++) {
	const lines = [];
	const count = 1 + Math.floor(random() * 6);
	for (let line = 0; line < count; line++) {
		let text = pick(blockStarts);
		const words = 1 + Math.floor(random() * 6);
		for (let word = 0; word < words; word++) text += (word > 0 && random() < 0.7 ? " " : "") + pick(inlines);
		lines.push(text);
		if (random() < 0.3) lines.push("");
		if (random() < 0.15) lines.push("  " + pick(inlines));
	}
	const md = lines.join("\n");
	add(`random ${index + 1}`, md, lexed(md));
}

writeFileSync(`${out}/cases.jsonl`, cases.join("\n") + "\n");
writeFileSync(`${out}/expected.jsonl`, expected.join("\n") + "\n");
writeFileSync(`${out}/labels.jsonl`, labels.map((label) => JSON.stringify(label)).join("\n") + "\n");
