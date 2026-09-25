// Upstream export-html template suites on the port's export assets.
// packages/coding-agent/src/core/export-html/ ships template.js and
// template.css, which export-html/index.bend loads and inlines into every
// export; the test bodies below are upstream's, reading those files.
// Pending: export-html-whitespace's ansiLinesToHtml and custom tool renderer
// cases (the port has no pre-rendered extension tool HTML).
//
// Usage: bun test tests/export_html_template.test.ts
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";

const ASSETS = new URL("../packages/coding-agent/src/core/export-html/", import.meta.url);

// export-html-skill-block.test.ts
describe("export HTML skill block rendering", () => {
	const templateJs = readFileSync(new URL("template.js", ASSETS), "utf-8");

	it("strips skill wrapper XML from user message rendering", () => {
		// Skill commands store a structural wrapper in the raw user message:
		//   <skill name="..." location="...">\n...\n</skill>\n\nactual prompt
		// The export renderer must detect that wrapper and render only the user-visible prompt,
		// not the Pi-generated <skill>...</skill> XML tags.
		expect(templateJs).toMatch(/parseSkillBlock/);
		expect(templateJs).toMatch(/skillBlock\.userMessage/);
	});

	it("renders skill invocation and user message as separate sibling blocks", () => {
		// The skill block and user message should render as separate entry-level elements,
		// matching the TUI layout where SkillInvocationMessageComponent and
		// UserMessageComponent are siblings, not nested.
		expect(templateJs).toMatch(/skill-invocation/);

		// When a skill block has a userMessage, the user-message div must be emitted
		// as a separate block after the skill-invocation div, containing the user-authored text.
		// Verify the code checks hasUserContent so the user-message div is only omitted
		// when the skill block has no user prompt and no images.
		expect(templateJs).toMatch(/hasUserContent/);
	});

	it("renders skill content as markdown, not raw text", () => {
		// The skill block body is markdown (from the SKILL.md file).
		// It should be rendered through safeMarkedParse, not escaped as raw text.
		expect(templateJs).toMatch(/safeMarkedParse\(skillBlock\.content\)/);
	});

	it("shows skill name and user message in the sidebar tree", () => {
		// The sidebar tree should display both the skill name and the user prompt,
		// not just one or the other.
		expect(templateJs).toMatch(/tree-role-skill/);
	});
});

// export-html-xss.test.ts
describe("export HTML markdown link sanitization", () => {
	const templateJs = readFileSync(new URL("template.js", ASSETS), "utf-8");

	it("overrides the marked link renderer to use scheme allow-list sanitization", () => {
		expect(templateJs).toMatch(/link\s*\(\s*token\s*\)/);
		expect(templateJs).toMatch(/sanitizeMarkdownUrl\(token\.href\)/);
		expect(templateJs).toMatch(/\^\(https\?\|mailto\|tel\|ftp\)/);
	});

	it("overrides the marked image renderer to use scheme allow-list sanitization", () => {
		expect(templateJs).toMatch(/image\s*\(\s*token\s*\)/);
		expect(templateJs).toMatch(/sanitizeMarkdownUrl\(token\.href\)/);
	});

	it("strips C0 controls before checking and emitting markdown URLs", () => {
		expect(templateJs).toContain("replace(/[\\x00-\\x1f\\x7f]/g, '')");
		expect(templateJs).not.toMatch(/\^\\s\*\(javascript\|vbscript\|data\):/i);
	});

	it("escapes href attributes in the custom link renderer", () => {
		// The link renderer must escape href values to prevent attribute breakout
		expect(templateJs).toMatch(/escapeHtml\(href\)/);
	});

	it("escapes image mimeType attributes", () => {
		// Image mimeType must be escaped to prevent attribute breakout
		expect(templateJs).not.toMatch(/\$\{img\.mimeType\}/);
		expect(templateJs).toMatch(/escapeHtml\(img\.mimeType/);
	});

	it("escapes image data attributes", () => {
		// Image data is embedded in src attributes and must not allow attribute breakout.
		expect(templateJs).not.toMatch(/;base64,\$\{img\.data\}"/);
		expect(templateJs).toMatch(/;base64,\$\{escapeHtml\(img\.data \|\| (?:''|"")\)\}"/);
	});

	it("escapes entry IDs before inserting them into attributes", () => {
		// Session entry IDs are embedded in id and data-entry-id attributes.
		expect(templateJs).not.toMatch(/id="\$\{entryId\}"/);
		expect(templateJs).not.toMatch(/data-entry-id="\$\{entryId\}"/);
		expect(templateJs).toMatch(/entry-\$\{escapeHtml\(entry\.id\)\}/);
		expect(templateJs).toMatch(/data-entry-id="\$\{escapeHtml\(entryId\)\}"/);
	});

	it("escapes tree metadata rendered from session fields", () => {
		// The tree renders session metadata via innerHTML, so dynamic fields must be escaped.
		expect(templateJs).not.toMatch(/\[\$\{msg\.toolName \|\| 'tool'\}\]/);
		expect(templateJs).not.toMatch(/\[\$\{msg\.role\}\]/);
		expect(templateJs).not.toMatch(/\[model: \$\{entry\.modelId\}\]/);
		expect(templateJs).not.toMatch(/\[thinking: \$\{entry\.thinkingLevel\}\]/);
		expect(templateJs).not.toMatch(/\[\$\{entry\.type\}\]/);
		expect(templateJs).toMatch(/\$\{escapeHtml\(msg\.toolName \|\| 'tool'\)\}/);
		expect(templateJs).toMatch(/\$\{escapeHtml\(msg\.role\)\}/);
		expect(templateJs).toMatch(/\$\{escapeHtml\(entry\.modelId\)\}/);
		expect(templateJs).toMatch(/\$\{escapeHtml\(entry\.thinkingLevel\)\}/);
		expect(templateJs).toMatch(/\$\{escapeHtml\(entry\.type\)\}/);
	});

	it("escapes model names in the exported header", () => {
		// Assistant message provider/model values are collected from the session and rendered with innerHTML.
		expect(templateJs).not.toMatch(/\$\{globalStats\.models\.join\(', '\) \|\| 'unknown'\}/);
		expect(templateJs).toMatch(/\$\{escapeHtml\(globalStats\.models\.join\(', '\) \|\| 'unknown'\)\}/);
	});
});

// export-html-whitespace.test.ts (first case)
describe("export HTML tool output whitespace", () => {
	it("preserves whitespace for plain-text tool output lines without preserving template whitespace", () => {
		const css = readFileSync(new URL("template.css", ASSETS), "utf-8");

		expect(css).toMatch(
			/\.output-preview > div:not\(\.expand-hint\),\s*\.output-full > div:not\(\.expand-hint\) \{[\s\S]*?white-space:\s*pre-wrap;/,
		);
		expect(css).toMatch(/\.ansi-line\s*\{[\s\S]*?white-space:\s*pre;/);
		expect(css).not.toMatch(/\.output-preview,\s*\.output-full\s*\{[\s\S]*?white-space:\s*pre-wrap;/);
	});
});
