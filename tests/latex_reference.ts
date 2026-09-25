// Test-only oracle for tests/latex.bend: pi-mono's packages/tui/src/latex.ts
// and the TUI Markdown component. Writes the cases (cases.jsonl), upstream's
// result for each (expected.jsonl) and a label per case (labels.jsonl).
//
// - Every assertion of packages/tui/test/latex.test.ts, with its test name:
//   the pinned test file runs with describe/it/assert/renderLatex replaced
//   by recorders, so the inputs and expectations are upstream's own.
// - The LaTeX tests of packages/tui/test/markdown.test.ts, transcribed with
//   their names; each expectation is checked against upstream here.
// - A differential corpus: hand-written inputs and seeded combinations of
//   fragments, inline and display, and LaTeX-bearing Markdown.
//
//   bun tests/latex_reference.ts OUT_DIR [PI_MONO]
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

const out = resolve(process.argv[2] ?? "build/latex");
const root = process.argv[3] ?? "/home/agent/code/pi-mono";
mkdirSync(out, { recursive: true });
const pinned: Record<string, string> = {
	"packages/tui/src/latex.ts": "c4ef99bef1d3a54c73006912c9a7fa67ef99412b4f6cd28d608cf0e07b38cece",
	"packages/tui/test/latex.test.ts": "870a9507190a830e1aac7398d4b4f6c2b2cc6982b9fac288aa4b299956561ebf",
	"packages/tui/src/components/markdown.ts": "704c1c714a7ff6bdec55573ab38393726fa73a7b47cf4c1161ccc4f08530ac28",
	"packages/tui/test/markdown.test.ts": "1060dbf84302c3984479b7a33ad4aaf21ae0616b8c02a45f066ba6e8f200f14d",
};
for (const [path, hash] of Object.entries(pinned)) {
	assert.equal(createHash("sha256").update(readFileSync(join(root, path))).digest("hex"), hash, path);
}
const { renderLatex } = await import(`${root}/packages/tui/src/latex.ts`);
const { Markdown } = await import(`${root}/packages/tui/src/components/markdown.ts`);

const cases: string[] = [];
const expected: string[] = [];
const labels: string[] = [];
function latexCase(label: string, source: string, display: boolean): void {
	cases.push(JSON.stringify({ kind: "latex", source, display }));
	expected.push(JSON.stringify(renderLatex(source, { display }) ?? null));
	labels.push(JSON.stringify(label));
}
const plain = (text: string) => text;
const theme = Object.fromEntries(
	["heading", "link", "linkUrl", "code", "codeBlock", "codeBlockBorder", "quote", "quoteBorder", "hr", "listBullet", "bold", "italic", "strikethrough", "underline"].map((key) => [key, plain]),
);
function markdownLines(text: string, width: number, latex: boolean): string[] {
	return new Markdown(text, 0, 0, theme, undefined, { renderLatex: latex }).render(width);
}
function markdownCase(label: string, text: string, width = 80, latex = true): void {
	cases.push(JSON.stringify({ kind: "markdown", text, width: String(width), renderLatex: latex }));
	expected.push(JSON.stringify(markdownLines(text, width, latex)));
	labels.push(JSON.stringify(label));
}

// latex.test.ts, run with recording stand-ins for its imports.
{
	const names: string[] = [];
	let current = "";
	const pending: { source: string; display: boolean; result: string | undefined }[] = [];
	(globalThis as Record<string, unknown>).__latexHarness = {
		describe(name: string, body: () => void) {
			names.push(name);
			body();
			names.pop();
		},
		it(name: string, body: () => void) {
			current = [...names, name].join(" > ");
			body();
			assert.equal(pending.length, 0, `unasserted call in ${current}`);
		},
		assert: {
			strictEqual(actual: unknown, want: string | undefined) {
				const call = pending.shift();
				assert.ok(call, `assertion without a call in ${current}`);
				assert.equal(actual, call.result);
				assert.equal(call.result, want, current);
				latexCase(`latex.test.ts: ${current}`, call.source, call.display);
			},
		},
		renderLatex(source: string, options?: { display?: boolean }) {
			const result = renderLatex(source, options);
			pending.push({ source, display: options?.display === true, result });
			return result;
		},
	};
	const header = 'import assert from "node:assert";\nimport { describe, it } from "node:test";\nimport { renderLatex } from "../src/index.ts";\n';
	const text = readFileSync(join(root, "packages/tui/test/latex.test.ts"), "utf8");
	assert.ok(text.startsWith(header));
	const copy = join(out, "latex.test.harnessed.ts");
	writeFileSync(copy, `const { assert, describe, it, renderLatex } = (globalThis as any).__latexHarness;\n${text.slice(header.length)}`);
	await import(copy);
}
const upstreamLatex = cases.length;

// markdown.test.ts "LaTeX math", transcribed. Upstream strips ANSI from
// the default theme's output and trims line ends; the plain theme here
// has no ANSI, so the untrimmed lines are compared and the trimmed ones
// are checked against upstream's expectations.
function namedMarkdown(name: string, text: string, want: string[] | ((lines: string[]) => void), latex = true): void {
	const lines = markdownLines(text, 80, latex).map((line) => line.trimEnd());
	if (typeof want === "function") want(lines);
	else assert.deepEqual(lines, want, name);
	markdownCase(`markdown.test.ts: Markdown component > LaTeX math > ${name}`, text, 80, latex);
}
namedMarkdown(
	"renders inline dollar and parenthesis delimiters",
	String.raw`A map $\mathbb{C}^3 \to \mathbb{C}^3$, $xy$, $x-y$, $-x$, $\frac{1}{2}$, $\rightarrow$, and \(s \to \infty\).`,
	["A map ℂ³ → ℂ³, xy, x-y, -x, 1/2, →, and s → ∞."],
);
namedMarkdown(
	"renders display dollar delimiters without Markdown escape corruption",
	String.raw`Before

$$\{3x+2y,\; x \in \{0, \pm 1\}\}$$

after`,
	["Before", "", "{3x+2y, x ∈ {0, ± 1}}", "", "after"],
);
namedMarkdown(
	"renders display bracket delimiters",
	String.raw`Before

\[
E \approx \frac{0.1\ \text{lux}}{100\ \text{lm/W}}
\]

after`,
	["Before", "", "    0.1 lux", "E ≈ ────────", "    100 lm/W", "", "after"],
);
namedMarkdown(
	"aligns matrix rows with the opening delimiter",
	String.raw`Consider the matrix

\[
A=
\begin{pmatrix}
\pi & 0\\
0 & \frac{1}{\pi}
\end{pmatrix}.
\]`,
	["Consider the matrix", "", "A = ⎛ π │ 0   ⎞", "    ⎝ 0 │ 1/π ⎠."],
);
namedMarkdown(
	"renders lower limits beneath display operators",
	String.raw`\[
\lim_{x\to 0}\frac{\frac{\sin x}{x}-1}{\frac{e^x-1}{x}-1}=0
\]`,
	["     (sin x)/x-1", "lim  ─────────── = 0", "x→0  (eˣ-1)/x-1"],
);
namedMarkdown(
	"renders math inside lists and tables",
	String.raw`- Formula: $F_1 = u^2$

| Value |
| --- |
| $\mathbb{C}^3$ |`,
	(lines) => {
		const output = lines.join("\n");
		assert.ok(output.includes("- Formula: F₁ = u²"));
		assert.ok(output.includes("│ ℂ³"));
	},
);
{
	const name = "does not treat currency, shell variables, or code spans as math";
	const source = "Costs $5 and $10 or $8k–$12k; use `$x$`, $HOME, and $" + "{PATH}.";
	namedMarkdown(name, source, ["Costs $5 and $10 or $8k–$12k; use $x$, $HOME, and $" + "{PATH}."]);
	const shellVariables = "Paths: $HOME/$USER and $XDG_CONFIG_HOME/$APP_CONFIG";
	namedMarkdown(name, shellVariables, [shellVariables]);
}
for (const source of [String.raw`Unknown $x + \unknown{y}$ after`, String.raw`Streaming $\mathbb{C}^3`]) {
	namedMarkdown("preserves unsupported and incomplete LaTeX exactly", source, [source]);
}
namedMarkdown("preserves incomplete backslash delimiters while streaming", String.raw`Map \(\mathbb{C}^3`, [String.raw`Map \(\mathbb{C}^3`]);
namedMarkdown("preserves incomplete backslash delimiters while streaming", "\\[\nx^2", ["\\[", "x^2"]);
namedMarkdown(
	"does not render LaTeX inside escaped delimiters or code fences",
	[String.raw`Escaped \$x-y\$.`, "", "```text", String.raw`$\mathbb{C}^3$`, "```"].join("\n"),
	["Escaped $x-y$.", "", "```text", "  $\\mathbb{C}^3$", "```"],
);
namedMarkdown(
	"allows LaTeX rendering to be disabled",
	String.raw`$$
\widetilde Y_{sf}
=
(1-w_{sf})\mu_{sf}^{\mathrm{MAR}}
$$

Inline \(A_{sf}\)`,
	["$$", String.raw`\widetilde Y_{sf}`, "=", String.raw`(1-w_{sf})\mu_{sf}^{\mathrm{MAR}}`, "$$", "", String.raw`Inline \(A_{sf}\)`],
	false,
);
namedMarkdown("switches from raw to rendered math when a streamed delimiter closes", String.raw`Map $\mathbb{C}^3`, [String.raw`Map $\mathbb{C}^3`]);
namedMarkdown("switches from raw to rendered math when a streamed delimiter closes", String.raw`Map $\mathbb{C}^3$`, ["Map ℂ³"]);
const upstreamMarkdown = cases.length - upstreamLatex;

// Differential corpus.
const fragments = [
	"x", "y_1", "x^2", "x_i^2", "x^{n+1}", "a_{i,j}", "e^{-x^2}", "2^{10}", "x^{a b}", "x_{max}", "x^{A}", "x^*", "x_{i_j}", "x^{n^2}",
	"f(x)", "(a+b)", "[0,1]", "\\{1,2\\}", "a=b", "a<b", "a>b", "a = b", "a\\ne b", "a\\le b", "a\\geq b", "x\\in A", "A\\subseteq B",
	"\\alpha", "\\beta\\gamma", "\\Omega", "\\varepsilon", "\\infty", "\\partial", "\\nabla", "\\hbar", "\\ell", "\\aleph", "\\emptyset",
	"\\pm 1", "a\\times b", "a\\cdot b", "a\\div b", "\\to", "\\mapsto", "\\Rightarrow", "\\iff", "\\implies", "\\langle x\\rangle", "\\lfloor x\\rfloor",
	"\\frac{1}{2}", "\\frac{a+b}{c}", "\\frac{x}{y+1}", "\\dfrac{1}{x}", "\\tfrac{3}{4}", "\\frac12", "\\frac{\\pi}{4}", "\\frac{1.5}{2.25}", "\\frac{ab}{cd}",
	"\\sqrt{2}", "\\sqrt{x+1}", "\\sqrt[3]{x}", "\\sqrt[4]{y}", "\\sqrt[n]{z}", "\\sqrt[2]{w}", "\\sqrt[ab]{c}", "\\sqrt\\pi",
	"\\sum_{i=1}^n i", "\\sum_{k=0}^{\\infty} a_k", "\\prod_{j} x_j", "\\int_0^1 f(x)\\,dx", "\\int\\limits_a^b g", "\\int\\nolimits_0^1 h", "\\oint_C", "\\iint", "\\bigcup_{i} A_i",
	"\\lim_{x\\to 0} f", "\\lim_{n\\to\\infty}", "\\max_{x} f(x)", "\\min(a,b)", "\\sup_{t} g", "\\liminf_{n} a_n", "\\limsup", "\\argmax_x", "\\lim\\limits_{x}", "\\max\\nolimits_i",
	"\\sin x", "\\cos\\theta", "\\tan(x)", "\\log_2 n", "\\ln x", "\\exp(x)", "\\det A", "\\sin^2 x", "-\\sin\\theta", "2\\cos x", "\\gcd(a,b)", "\\Pr(A)", "x\\sin y",
	"\\operatorname{rank} A", "\\operatorname*{arg\\,min}_{x} f", "\\operatorname{Tr}(M)", "a\\bmod n", "a\\equiv b\\pmod{n}", "x\\pod{2}", "a\\mod b",
	"\\vec{x}", "\\hat{y}", "\\bar{z}", "\\tilde{a}", "\\dot{x}", "\\ddot{x}", "\\overline{AB}", "\\underline{x}", "\\widehat{xyz}", "\\overrightarrow{AB}", "\\check{c}", "\\breve{b}", "\\mathring{a}",
	"\\mathbb{R}", "\\mathbb{N}", "\\mathbb{Z}^n", "\\mathbb{Q}\\times\\mathbb{C}", "\\mathbb{X}", "\\mathcal{L}", "\\mathbf{v}", "\\mathrm{d}x", "\\text{if } x", "\\text{ spaced }", "\\textbf{bold}", "\\mbox{box}", "\\boldsymbol{\\mu}", "\\mathfrak{g}",
	"{\\rm roman}", "{\\bf B}", "{\\it i}", "\\displaystyle x", "\\textstyle y", "\\scriptstyle z", "\\big( x \\big)", "\\Bigl[ y \\Bigr]", "\\left( x \\right)", "\\left. x \\right|", "\\left\\{ a \\middle| b \\right\\}",
	"\\boxed{x=1}", "\\fbox{y}", "\\binom{n}{k}", "\\dbinom{a}{b}", "\\overset{!}{=}", "\\underset{n}{\\sum}", "\\stackrel{def}{=}", "\\not=", "\\not\\in", "\\not\\subset", "\\not{abc}", "\\not<", "\\not\\approx",
	"a\\,b", "a\\;b", "a\\:b", "a\\quad b", "a\\qquad b", "a\\!b", "\\sin\\!x", "a~b", "a\\ b", "a\\\\b", "a & b", "\\{", "\\}", "\\$", "\\%", "\\#", "\\_", "\\&", "\\|", "\\backslash",
	"\\begin{pmatrix}1&0\\\\0&1\\end{pmatrix}", "\\begin{bmatrix}a&b\\\\c&d\\end{bmatrix}", "\\begin{matrix}1&2\\end{matrix}", "\\begin{vmatrix}a&b\\\\c&d\\end{vmatrix}", "\\begin{Vmatrix}x\\end{Vmatrix}",
	"\\begin{Bmatrix}1\\\\2\\\\3\\end{Bmatrix}", "\\begin{array}{cc}1&2\\\\3&4\\end{array}", "\\begin{smallmatrix}a&b\\\\c&d\\end{smallmatrix}", "\\begin{pmatrix}\\frac{1}{2}&x^2\\\\y_1&\\sqrt{3}\\end{pmatrix}", "\\begin{pmatrix}1\\\\2\\end{pmatrix}.",
	"\\begin{cases}1&x>0\\\\0&\\text{otherwise}\\end{cases}", "\\begin{cases}a&\\text{if }b\\\\c&\\text{when }d\\\\e&\\text{for all }f\\end{cases}", "\\begin{cases}x,&y\\end{cases}", "\\begin{cases}1\\\\2\\\\3\\\\4\\end{cases}", "\\begin{cases*}p&q\\end{cases*}",
	"\\begin{aligned}a&=b\\\\c&=d\\end{aligned}", "\\begin{align*}x&=1\\\\[2pt]y&=2\\end{align*}", "\\begin{alignedat}{2}a&=b&c&=d\\end{alignedat}", "\\begin{gather}x\\\\y\\end{gather}", "\\begin{equation}E=mc^2\\end{equation}", "\\begin{split}a\\\\\\\\b\\end{split}",
	"\\begin{equation*}\\frac{a}{b}\\end{equation*}", "\\begin{displaymath}x\\end{displaymath}", "\\begin{multline}a+b\\\\+c\\end{multline}",
	"\\unknown", "\\foo{x}", "\\frac{1}{x", "x}", "{x", "\\begin{matrix}1", "\\begin{foo}x\\end{foo}", "\\end{matrix}", "x\\", "\\sqrt[3{x}", "\\begin{}x", "\\not{}", "_", "^", "x^", "x_{",
	"x_1^2_3", "x^1^2", "\\sum_1_2", "\\lim^a^b", "\\operatorname*{x}", "\\left", "\\mathbb{}", "\\hat{}", "\\hat{ab}", "\\text{}", "{}", "{{x}}",
	"   spaced   out   ", "a\n=\nb", "\\\\", "\\\r\nx", "a\\\nb", "\\,", "\\;\\;", "\t\tx", "x  =  y", "\\sin \\cos", "\\sin(x)\\cos(y)", "3\\sin x", ")\\sin", "\\sin\\sqrt{x}", "\\sin\\frac{1}{2}",
	"é^{é}", "α_β", "π^2", "ℝ^n", "x^{αβ}", "x_{ab}", "x_{AB}", "x^{a/b}", "x^{-1}", "x^{ - 1 }", "x_{ i = 0 }", "x^{+}", "x^{()}", "x_{ij}", "x^{abc}", "x^{xyz}", "x^{q}", "x_{b}", "x_{y}",
	"1.5", "0.001", "5{,}000", "10^{6}", "(1,-3/2)", "-2", "1 - 2", "x-y", "x - y", "a+-b", "a . b", "a..b", "x.", ". x", "\\cdots", "\\ldots", "\\vdots", "\\ddots",
	"\\Join", "\\bowtie", "\\ltimes", "\\leftouterjoin", "\\therefore", "\\because", "\\forall x\\exists y", "\\neg p\\land q\\lor r", "p\\vdash q", "\\models", "\\top\\bot", "\\square", "\\checkmark", "\\wp", "\\Re z", "\\Im z", "\\prime", "f'", "f''(x)",
	"\\colon", "f\\colon A\\to B", "\\lvert x\\rvert", "\\lVert v\\rVert", "\\vert", "\\Vert", "|x|", "\\mid", "\\parallel", "\\perp", "\\propto", "\\sim", "\\simeq", "\\cong", "\\approx",
];
function rng(seed: number): () => number {
	let state = seed >>> 0;
	return () => {
		state = (state + 0x6d2b79f5) >>> 0;
		let t = state;
		t = Math.imul(t ^ (t >>> 15), t | 1);
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}
for (const fragment of fragments) {
	latexCase("fragment", fragment, false);
	latexCase("fragment", fragment, true);
}
const random = rng(20260925);
const pick = <T>(items: readonly T[]): T => items[Math.floor(random() * items.length)] as T;
const joins = ["", " ", "+", "=", ",\\ ", "\\quad ", "\n", " & ", "\\\\", "-", "\\cdot "];
for (let index = 0; index < 1200; index++) {
	const count = 1 + Math.floor(random() * 4);
	let source = pick(fragments);
	for (let part = 1; part < count; part++) source += pick(joins) + pick(fragments);
	if (random() < 0.2) source = `\\frac{${source}}{${pick(fragments)}}`;
	else if (random() < 0.1) source = `${pick(fragments)}^{${source}}`;
	else if (random() < 0.1) source = `\\begin{pmatrix}${source}&${pick(fragments)}\\\\${pick(fragments)}&x\\end{pmatrix}`;
	else if (random() < 0.08) source = `\\boxed{${source}}`;
	latexCase("combination", source, random() < 0.5);
}
const upstreamCorpus = cases.length - upstreamLatex - upstreamMarkdown;

// LaTeX in Markdown.
const markdownSources = [
	"Inline $x^2$ and $$y_1$$ and \\(z\\) and \\[w\\].",
	"$\\frac{1}{2}$ at start",
	"end with $\\alpha$",
	"$$x$$",
	"$$\nx^2\n$$",
	"$$x^2$$ trailing",
	"   $$\n\\frac{a}{b}\n$$",
	"\\[\n\\sum_{i=0}^n x_i\n\\]",
	"\\[x\\]",
	"\\[x\\] after",
	"text\n$$\ny\n$$\nmore",
	"# Heading $x^2$",
	"## $\\alpha$ title",
	"> quote $\\beta$",
	"- item $a_1$\n- item $b_2$",
	"1. first $\\sqrt{2}$\n2. second",
	"**bold $x$** and *$y$*",
	"`$x$` code",
	"[link $x$](https://example.com)",
	"$ not math $",
	"$x $",
	"$ x$",
	"$5",
	"$5 and $6",
	"$x$5",
	"$HOME and $PATH",
	"$A$b",
	"$A_1$",
	"$HOME$",
	"cost $x`y$",
	"$a\nb$",
	"$$\n$$",
	"$$ $$",
	"$\\unknown$",
	"$$\\unknown$$",
	"\\[\\unknown\\]",
	"\\(\\unknown\\)",
	"$x^2",
	"$x",
	"$abc",
	"$$\\frac{1}{2}",
	"$$abc",
	"\\(x",
	"\\[x",
	"\\[\n\\frac{1}{2}",
	"a \\$x\\$ b",
	"a \\\\$x$ b",
	"a \\\\\\$x$ b",
	"$x\\$y$",
	"$x\\\\$",
	"| A | B |\n| --- | --- |\n| $x^2$ | $\\frac{1}{2}$ |",
	"```\n$x$\n```\n$y$",
	"para\n\n$$\n\\begin{pmatrix}1&0\\\\0&1\\end{pmatrix}\n$$\n\npara",
	"$$\n\\begin{cases}1&x>0\\\\0&x\\le0\\end{cases}\n$$",
	"$$\\lim_{n\\to\\infty}\\left(1+\\frac{1}{n}\\right)^n=e$$",
	"Euler: $e^{i\\pi}+1=0$. Done.",
	"Mixed $a$ and \\(b\\) and $$c$$ and \\[d\\] inline",
	"$x$$y$",
	"$$x$y$$",
	"$x$ $y$ $z$",
	"price: $10-$20",
	"- $$x$$\n- y",
	"> $$\n> x\n> $$",
	"text $$\n\\alpha\n$$",
	"$$\n\\alpha\n$$ tail",
	"\\[\n\\alpha\n\\]\n\n\\[\n\\beta\n\\]",
	"$\\text{a b}$",
	"$\\{x\\}$",
	"$a_{b_{c}}$",
	"~~$x$~~",
	"> text\n> $$\n> x^2\n> $$\n> more",
	"> $$x$$",
	"> \\[\n> \\frac{1}{2}\n> \\]",
	"> \\[\n> x",
	"> a\n> $$\n> \\unknown\n> $$",
	"para\n$$\nx\n$$",
	"para\n$$\nx\n$$\nafter",
	"- a\n\n$$\nx\n$$",
	"# Title\n$$\nx\n$$",
	"$$\n\\unknown\n$$",
	"$$ x $$  \nnext",
	"$$a$$b$$",
	"\\[\n\\begin{aligned}a&=b\\\\c&=d\\end{aligned}\n\\]",
	"$$\n\\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}.\n$$",
	"a\n\\[x",
	"a $ x$ b",
	"a $x　$ b",
	"snake_case_name and _em_ and a_b_c",
];
for (const source of markdownSources) {
	markdownCase("markdown", source);
	markdownCase("markdown (renderLatex false)", source, 80, false);
}
markdownCase("markdown (narrow)", "$$\n\\frac{a+b+c+d+e+f}{g}\n$$\n\ninline $\\alpha+\\beta+\\gamma+\\delta$ wraps here", 20);

// Known divergences, reported by tests/latex_check.py but not failed on.
// The Bend Markdown component renders a paragraph line by line and has no
// list-item continuation model: a `$` whose closing `$` is on a later line
// of the same paragraph, or an unclosed delimiter (which in pi swallows
// the rest of the paragraph while streaming), only sees its own line, and
// display math inside a list item loses the item's indentation.
for (const source of ["a $x+1 **b**\nc$", "$x^2\n**b**", "- a\n  $$\n  x\n  $$", "- a\n$$x$$", "1. $$\n   x\n   $$"]) {
	markdownCase("known divergence (line-based paragraphs and lists)", source);
}

writeFileSync(join(out, "cases.jsonl"), `${cases.join("\n")}\n`);
writeFileSync(join(out, "expected.jsonl"), `${expected.join("\n")}\n`);
writeFileSync(join(out, "labels.jsonl"), `${labels.join("\n")}\n`);
console.log(JSON.stringify({ upstreamLatex, upstreamMarkdown, corpus: upstreamCorpus, markdown: cases.length - upstreamLatex - upstreamMarkdown - upstreamCorpus }));
