// Upstream tool-system-prompt-contributions.test.ts on the native tools.
// Upstream checks that each built-in tool definition's promptSnippet and
// promptGuidelines equal its exported *ToolSystemPromptContribution. The port
// has one source for both, Tools.promptSnippet/promptGuidelines, which the
// system prompt builder reads; tests/tool-prompt-contributions.bend prints
// them and this test compares them with upstream's contribution constants,
// imported from the pinned pi-mono (tests/upstream_pin.mjs). Test-only.
// "keeps %s session-environment guidance conditional" checks the bash
// definition built with exposeSessionEnvironment false: upstream's undefined
// guidelines are an empty list. Pending: the powershell rows (not ported).
//
// Usage: bun test tests/tool_prompt_contributions.test.ts
//        TOOL_PROMPT_RUNNER=build/tool-prompt-contributions bun test tests/tool_prompt_contributions.test.ts
import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { UPSTREAM } from "./upstream_pin.mjs";

const ROOT = path.resolve(import.meta.dir, "..");

type Contribution = { snippet: string; guidelines: string[] };

function nativeContributions(): Map<string, Contribution> {
	const command = process.env.TOOL_PROMPT_RUNNER
		? [path.resolve(ROOT, process.env.TOOL_PROMPT_RUNNER)]
		: ["bun", path.join(ROOT, "build/tool-prompt-contributions.js")];
	const result = spawnSync(command[0], command.slice(1), { encoding: "utf8" });
	if (result.status !== 0) throw new Error(`tool prompt dump failed: ${result.stderr}`);
	const entries = JSON.parse(result.stdout) as Array<Contribution & { name: string }>;
	return new Map(entries.map(({ name, snippet, guidelines }) => [name, { snippet, guidelines }]));
}

const NATIVE = nativeContributions();

async function upstream(name: string): Promise<Contribution> {
	const module = await import(`${UPSTREAM}/packages/coding-agent/src/core/tools/${name}.ts`);
	return module[`${name}ToolSystemPromptContribution`] as Contribution;
}

const cases = ["read", "bash", "edit", "write", "grep", "find", "ls"] as const;

describe("built-in tool system prompt contributions", () => {
	test.each(cases)("keeps the %s tool definition aligned with its contribution", async (name) => {
		const contribution = await upstream(name);
		const definition = NATIVE.get(name);

		expect(definition?.snippet).toBe(contribution.snippet);
		expect(definition?.guidelines ?? []).toEqual([...contribution.guidelines]);
	});

	test.each(["bash"] as const)("keeps %s session-environment guidance conditional", (name) => {
		const definition = NATIVE.get(`${name}:noSessionEnvironment`);

		expect(definition).toBeDefined();
		expect(definition?.guidelines).toEqual([]);
	});
});
