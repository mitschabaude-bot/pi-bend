// Upstream oracle for tests/models-json.bend: the real ModelRuntime with the
// given models.json, in-memory credentials and no catalog refresh.
// Usage: bun models_json_reference.ts <pi-mono/packages/coding-agent> <models.json> [<provider>/<model> ...]
const [root, modelsPath, ...references] = process.argv.slice(2);
const { ModelRuntime } = await import(root + "/src/core/model-runtime.ts");
const { InMemoryCredentialStore } = await import(root + "/../ai/src/index.ts").catch(() => ({}));
const credentials = InMemoryCredentialStore
	? new InMemoryCredentialStore()
	: { read: async () => undefined, list: async () => [], modify: async () => undefined, delete: async () => {} };
const runtime = await ModelRuntime.create({ credentials, modelsPath, refreshOnCreate: false, allowModelNetwork: false });

const authValue = (result: any) =>
	result === undefined
		? null
		: { apiKey: result.auth.apiKey ?? null, headers: result.auth.headers ?? null, source: result.source ?? null };
const settle = async (fn: () => Promise<any>) => {
	try {
		return authValue(await fn());
	} catch (error) {
		return { error: error instanceof Error ? error.message : String(error) };
	}
};

// Only models.json providers that the native port also ships as built-ins, or
// that are custom, are compared; see models_json_check.py.
const configured = [];
for (const id of runtime["config"].getProviderIds()) {
	const provider = runtime.getProvider(id);
	if (!provider) continue;
	configured.push({
		id,
		name: provider.name,
		baseUrl: provider.baseUrl ?? "",
		models: provider.getModels(),
		available: (await runtime.checkAuth(id)) !== undefined,
		auth: await settle(() => runtime.getAuth(id)),
	});
}
const modelAuth: Record<string, unknown> = {};
for (const reference of references) {
	const [provider, ...rest] = reference.split("/");
	const model = runtime.getModel(provider, rest.join("/"));
	modelAuth[reference] = model ? await settle(() => runtime.getAuth(model)) : null;
}
console.log(
	JSON.stringify({
		error: runtime.getError() ?? null,
		providers: runtime.getProviders().map((provider: { id: string }) => provider.id),
		configured,
		modelAuth,
	}),
);
