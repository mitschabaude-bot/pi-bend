// Source-pinned oracle for tests/openrouter_images_check.py: runs upstream
// images.ts generateImages (PI_MONO at f07218c4d) with the pinned OpenAI SDK
// for one case of packages/ai/test/openrouter-images.bend and prints the same
// JSON lines. Run with Node (pi's runtime).
const root = process.env.PI_MONO!;
const { generateImages } = await import(`${root}/packages/ai/src/images.ts`);
const { getImageModel } = await import(`${root}/packages/ai/src/image-models.ts`);

const [mode, baseUrl] = process.argv.slice(2);
const cost = (input: number, output: number, cacheRead = 0, cacheWrite = 0) => ({ input, output, cacheRead, cacheWrite });
const geminiImage = () => ({
	id: "google/gemini-3.1-flash-image-preview",
	name: "Gemini 3.1 Flash Image Preview",
	api: "openrouter-images",
	provider: "openrouter",
	baseUrl,
	input: ["text", "image"],
	output: ["text", "image"],
	cost: cost(0.015, 0.03),
	headers: { "HTTP-Referer": "https://example.com" },
});
const flux = () => ({
	id: "black-forest-labs/flux.2-pro",
	name: "FLUX.2 Pro",
	api: "openrouter-images",
	provider: "openrouter",
	baseUrl,
	input: ["text", "image"],
	output: ["image"],
	cost: cost(0.015, 0.03),
});
const priced = () => ({
	id: "priced/image-model",
	name: "Priced",
	api: "openrouter-images",
	provider: "openrouter",
	baseUrl,
	input: ["text"],
	output: ["image", "text"],
	cost: cost(2, 4, 0.5, 1.25),
});
const dog = { input: [{ type: "text", text: "Generate a dog" }] };
const withImage = {
	input: [
		{ type: "text", text: "Make it blue" },
		{ type: "image", data: "aGVsbG8=", mimeType: "image/png" },
	],
};
const capture = (payload: unknown) => {
	console.log(`payload ${JSON.stringify(payload)}`);
	return undefined;
};
const observe = (response: unknown) => {
	console.log(`response ${JSON.stringify(response)}`);
};
const hooks = { onPayload: capture, onResponse: observe };

let run: () => Promise<unknown>;
switch (mode) {
	case "text-and-image":
		run = () => generateImages(geminiImage(), dog, { apiKey: "test", ...hooks });
		break;
	case "abort": {
		const controller = new AbortController();
		controller.abort();
		run = () => generateImages(flux(), dog, { apiKey: "test", signal: controller.signal });
		break;
	}
	case "flux":
		run = () => generateImages(flux(), dog, { apiKey: "test" });
		break;
	case "catalog":
		run = () =>
			generateImages({ ...getImageModel("openrouter", "google/gemini-2.5-flash-image"), baseUrl }, withImage, {
				apiKey: "test",
				...hooks,
			});
		break;
	case "usage":
		run = () => generateImages(priced(), dog, { apiKey: "test" });
		break;
	case "no-key":
		run = () => generateImages(flux(), dog, {});
		break;
	case "headers":
		run = () =>
			generateImages(geminiImage(), dog, {
				apiKey: "test",
				headers: { "HTTP-Referer": null, "X-Title": "pi-bend", "x-custom": "value" },
				...hooks,
			});
		break;
	case "replace":
		run = () =>
			generateImages(flux(), dog, {
				apiKey: "test",
				onPayload: (payload: unknown) => {
					console.log(`payload ${JSON.stringify(payload)}`);
					return {
						model: "black-forest-labs/flux.2-pro",
						messages: [{ role: "user", content: "replaced prompt" }],
						stream: false,
						modalities: ["image"],
						seed: 7,
					};
				},
			});
		break;
	case "retry":
		run = () => generateImages(flux(), dog, { apiKey: "test", maxRetries: 1, ...hooks });
		break;
	case "unregistered":
		run = () => generateImages({ ...flux(), api: "other-images" }, dog, { apiKey: "test" });
		break;
	default:
		run = () => generateImages(flux(), dog, { apiKey: "test", ...hooks });
}
try {
	const result = (await run()) as Record<string, unknown>;
	delete result.timestamp;
	console.log(`result ${JSON.stringify(result)}`);
} catch (error) {
	console.log(`thrown ${(error as Error).message}`);
}
