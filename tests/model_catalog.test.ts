// Upstream model-catalog suites run against the native catalog.
// tests/model-catalog.bend prints every built-in model in pi-ai's public JSON
// shape; getModel/getModels/getProviders below read that dump instead of
// upstream's models.generated.ts, and the test bodies are upstream's.
// Test-only: no production behavior comes from here.
//
// Usage: bun test tests/model_catalog.test.ts                  (Bun lane)
//        MODEL_CATALOG_RUNNER=build/model-catalog bun test tests/model_catalog.test.ts
import { describe, expect, it } from "bun:test";
import { spawnSync } from "node:child_process";
import path from "node:path";

const ROOT = path.resolve(import.meta.dir, "..");
type Model = Record<string, any> & { id: string; provider: string; api: string };

function dump(): Model[] {
	const command = process.env.MODEL_CATALOG_RUNNER
		? [path.resolve(ROOT, process.env.MODEL_CATALOG_RUNNER)]
		: [path.join(ROOT, "build/bend-native-toolchain/bend2/main.ts"), path.join(ROOT, "tests/model-catalog.bend")];
	const result = spawnSync(command[0], command.slice(1), { encoding: "utf8", maxBuffer: 1 << 28 });
	if (result.status !== 0) throw new Error(`catalog dump failed: ${result.stderr}`);
	return result.stdout.split("\n").filter((line) => line.length > 0).map((line) => JSON.parse(line));
}

const MODELS = dump();
const getProviders = () => [...new Set(MODELS.map((model) => model.provider))];
const getModels = (provider: string) => MODELS.filter((model) => model.provider === provider);
const getModel = (provider: string, id: string): Model => {
	const found = MODELS.find((model) => model.provider === provider && model.id === id);
	if (!found) throw new Error(`no built-in model ${provider}/${id}`);
	return found;
};
const getBuiltinModel = getModel;

// xiaomi-models.test.ts
{
	const XIAOMI_PROVIDERS = ["xiaomi", "xiaomi-token-plan-cn", "xiaomi-token-plan-ams", "xiaomi-token-plan-sgp"] as const;
	const DEPRECATED_MODEL_IDS = ["mimo-v2-flash", "mimo-v2-omni", "mimo-v2-pro"] as const;
	const REPLACEMENT_MODEL_IDS = ["mimo-v2.5", "mimo-v2.5-pro"] as const;

	describe("Xiaomi MiMo models", () => {
		it.each(XIAOMI_PROVIDERS)("omits deprecated models from %s", (provider) => {
			const modelIds = getModels(provider).map((model) => model.id);
			for (const modelId of DEPRECATED_MODEL_IDS) expect(modelIds).not.toContain(modelId);
		});

		it.each(XIAOMI_PROVIDERS)("keeps replacement models on %s", (provider) => {
			const modelIds = getModels(provider).map((model) => model.id);
			for (const modelId of REPLACEMENT_MODEL_IDS) expect(modelIds).toContain(modelId);
		});
	});
}

// openrouter-cache-control-models.test.ts
{
	const OPENROUTER_ANTHROPIC_LATEST_MODEL_IDS = [
		"~anthropic/claude-fable-latest",
		"~anthropic/claude-haiku-latest",
		"~anthropic/claude-opus-latest",
		"~anthropic/claude-sonnet-latest",
	] as const;

	describe("OpenRouter Anthropic latest alias metadata", () => {
		it.each(OPENROUTER_ANTHROPIC_LATEST_MODEL_IDS)("keeps completions cache control for %s", (modelId) => {
			const model = getModel("openrouter", modelId);
			expect(model.api).toBe("openai-completions");
			if (model.api !== "openai-completions") throw new Error(`Unexpected API for ${modelId}`);
			expect(model.compat?.cacheControlFormat).toBe("anthropic");
		});
	});
}

// zai-coding-plan-models.test.ts
it("exposes GLM-4.6V on the China Coding Plan catalog", () => {
	const model = getBuiltinModel("zai-coding-cn", "glm-4.6v");

	expect(model).toMatchObject({
		id: "glm-4.6v",
		provider: "zai-coding-cn",
		api: "openai-completions",
		baseUrl: "https://open.bigmodel.cn/api/coding/paas/v4",
		reasoning: true,
		input: ["text", "image"],
		cost: { input: 0.3, output: 0.9, cacheRead: 0, cacheWrite: 0 },
		contextWindow: 128000,
		maxTokens: 32768,
		compat: {
			maxTokensField: "max_tokens",
			thinkingFormat: "zai",
			zaiToolStream: true,
		},
	});
});

it("uses API-equivalent reference costs for Coding Plan models", () => {
	expect(getBuiltinModel("zai", "glm-5.2").cost).toEqual({
		input: 1.4,
		output: 4.4,
		cacheRead: 0.26,
		cacheWrite: 0,
	});
	for (const provider of ["zai", "zai-coding-cn"] as const) {
		expect(getBuiltinModel(provider, "glm-5.3").cost).toEqual({
			input: 1.4,
			output: 4.4,
			cacheRead: 0.26,
			cacheWrite: 0,
		});
	}
});

it("keeps zero costs for Coding Plan models without a matching API price", () => {
	const zeroCost = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };

	expect(getBuiltinModel("zai", "glm-5.2-highspeed").cost).toEqual(zeroCost);

	for (const provider of ["zai", "zai-coding-cn"] as const) {
		expect(getBuiltinModel(provider, "glm-5.3-highspeed").cost).toEqual(zeroCost);
	}
});

// anthropic-adaptive-thinking-models.test.ts
{
	const EXPECTED_CURRENT_ADAPTIVE_THINKING_MODELS = [
		"anthropic/claude-fable-5",
		"anthropic/claude-opus-4-8",
		"anthropic/claude-opus-5",
		"anthropic/claude-sonnet-5",
		"cloudflare-ai-gateway/claude-fable-5",
		"fireworks/accounts/fireworks/models/deepseek-v4-flash-0731",
		"fireworks/accounts/fireworks/models/gpt-oss-120b",
		"fireworks/accounts/fireworks/models/qwen3p8-max",
		"kimi-coding/kimi-for-coding",
		"kimi-coding/k3",
		"kimi-coding/kimi-for-coding-highspeed",
		"opencode/claude-opus-4-8",
		"opencode/claude-opus-5",
		"vercel-ai-gateway/anthropic/claude-opus-4.8",
		"vercel-ai-gateway/anthropic/claude-opus-5",
		"vercel-ai-gateway/anthropic/claude-sonnet-5",
	];

	function getAllModels(): Model[] {
		return getProviders().flatMap((provider) => getModels(provider));
	}

	describe("Anthropic adaptive thinking model metadata", () => {
		it("marks built-in Anthropic Messages models that use adaptive thinking", () => {
			const flaggedModels = getAllModels()
				.filter((model) => model.api === "anthropic-messages")
				.filter((model) => model.compat?.forceAdaptiveThinking === true)
				.map((model) => `${model.provider}/${model.id}`)
				.sort();

			expect(flaggedModels).toEqual(expect.arrayContaining([...EXPECTED_CURRENT_ADAPTIVE_THINKING_MODELS].sort()));
			expect(flaggedModels).toEqual(
				flaggedModels.filter(
					(modelId) =>
						// Regression for #9323: Fireworks uses catalog effort metadata and
						// verified fallbacks, not a fixed set of adaptive model names.
						modelId.startsWith("fireworks/") ||
						/(opus[-.](4[-.][678]|5)|sonnet[-.]4[-.]6|sonnet[-.]5|fable[-.]5|kimi-coding\/)/.test(modelId),
				),
			);
		});
	});
}

// together-models.test.ts (catalog cases; the environment API-key case is
// covered by the provider environment tests)
describe("Together models", () => {
	it("registers the default Kimi K2.6 model via OpenAI-compatible Chat Completions API", () => {
		const model = getModel("together", "moonshotai/Kimi-K2.6");

		expect(model).toBeDefined();
		expect(model.api).toBe("openai-completions");
		expect(model.provider).toBe("together");
		expect(model.baseUrl).toBe("https://api.together.ai/v1");
		expect(model.reasoning).toBe(true);
		expect(model.thinkingLevelMap).toEqual({ minimal: null, low: null, medium: null });
		expect(model.input).toEqual(["text", "image"]);
		expect(model.contextWindow).toBe(262144);
		expect(model.maxTokens).toBe(131000);
		expect(model.cost).toEqual({
			input: 1.2,
			output: 4.5,
			cacheRead: 0.2,
			cacheWrite: 0,
		});
		expect(model.compat).toEqual({
			supportsStore: false,
			supportsDeveloperRole: false,
			supportsReasoningEffort: false,
			maxTokensField: "max_tokens",
			thinkingFormat: "together",
			supportsStrictMode: false,
			supportsLongCacheRetention: false,
		});
	});

	it("models Together reasoning controls from the Together API surface", () => {
		const gptOss = getModel("together", "openai/gpt-oss-120b");
		expect(gptOss.thinkingLevelMap).toEqual({
			off: null,
			minimal: null,
			low: "low",
			medium: "medium",
			high: "high",
			max: null,
			xhigh: null,
		});
		expect(gptOss.compat).toMatchObject({
			supportsReasoningEffort: true,
			thinkingFormat: "openai",
		});

		const deepSeekV4 = getModel("together", "deepseek-ai/DeepSeek-V4-Pro");
		expect(deepSeekV4.thinkingLevelMap).toEqual({
			minimal: null,
			low: null,
			medium: null,
			high: "high",
			xhigh: null,
		});
		expect(deepSeekV4.compat).toMatchObject({
			supportsReasoningEffort: true,
			thinkingFormat: "together",
		});

		const minimax = getModel("together", "MiniMaxAI/MiniMax-M2.7");
		expect(minimax.thinkingLevelMap).toEqual({ off: null, minimal: null, low: null, medium: null });
		expect(minimax.compat?.thinkingFormat).toBeUndefined();
		expect(minimax.compat?.supportsReasoningEffort).toBe(false);
	});
});

// model-catalog-types.test.ts: its compile-time expectTypeOf assertions have
// no runtime counterpart; the runtime ones are upstream's.
it("routes GitHub Copilot Grok 4.5 through the Responses API", () => {
	expect(getModel("github-copilot", "grok-4.5").api).toBe("openai-responses");
});

// Regression test for https://github.com/earendil-works/pi/issues/9209
it("routes all GitHub Copilot GPT models through the Responses API", () => {
	const gptModels = getModels("github-copilot").filter((model) => model.id.startsWith("gpt-"));
	expect(gptModels.length).toBeGreaterThan(0);
	expect(gptModels.every((model) => model.api === "openai-responses")).toBe(true);
	for (const modelId of ["gpt-6-sol", "gpt-6-luna"] as const) {
		const model = getModel("github-copilot", modelId);
		expect(model).toMatchObject({
			api: "openai-responses",
			contextWindow: 1000000,
			maxTokens: 128000,
			thinkingLevelMap: { off: "none", max: "max" },
		});
	}
});

