// Test-only oracle for tests/oauth_flows_check.py: pinned pi-mono's OAuth flow
// for one case, with the global fetch rewriting `https://<host><path>` to
// `<base>/<host><path>` (upstream's tests stub fetch the same way). Output
// matches packages/ai/test/oauth-flows.bend.
import { UPSTREAM } from "./upstream_pin.mjs";

const points = (text: string) => Array.from(text, (c) => c.codePointAt(0)).join(",");
const [base, path] = process.argv.slice(2);
const spec = JSON.parse(await Bun.file(path).text());

const modules: Record<string, [string, string]> = {
	xai: ["xai.ts", "xaiOAuth"],
	kimi: ["kimi-coding.ts", "kimiCodingOAuth"],
	meta: ["meta.ts", "metaOAuth"],
	openrouter: ["openrouter.ts", "openRouterOAuth"],
	copilot: ["github-copilot.ts", "githubCopilotOAuth"],
	anthropic: ["anthropic.ts", "anthropicOAuth"],
	codex: ["openai-codex.ts", "openaiCodexOAuth"],
};
const [file, name] = modules[spec.flow];
const oauth = (await import(`${UPSTREAM}/packages/ai/src/auth/oauth/${file}`))[name];

const realFetch = globalThis.fetch;
globalThis.fetch = ((input: any, init?: any) => {
	const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
	return realFetch(`${base}/${url.replace(/^https?:\/\//, "")}`, init);
}) as typeof fetch;

const emit = (tag: string, value: unknown) => console.log(`${tag} ${points(JSON.stringify(value))}`);
const controller = new AbortController();
const answers: string[] = [...(spec.prompts ?? [])];
// The browser of the loopback-callback tests (openrouter-oauth.test.ts).
let callbackUrl = "";
let authUrl = "";
const authParam = (name: string) => (authUrl ? (new URL(authUrl).searchParams.get(name) ?? "") : "");
let promptSignal: AbortSignal | undefined;
let first: Promise<number | null> | undefined;
let second: Promise<number | null> | undefined;
const visit = (url: URL) => realFetch(url).then((response) => response.status, () => null);
if (spec.preAborted) controller.abort();
const now = Date.now();
console.log(`S ${Math.floor(now / 1000)} ${now % 1000}`);
try {
	if (spec.action === "describe") {
		emit("D", { name: oauth.name, isSubscription: oauth.isSubscription ?? false, ...(oauth.loginLabel ? { loginLabel: oauth.loginLabel } : {}) });
	} else if (spec.action === "refresh") {
		emit("C", await oauth.refresh(spec.credential, controller.signal));
	} else if (spec.action === "toAuth") {
		emit("A", await oauth.toAuth(spec.credential));
	} else {
		const credential = await oauth.login({
			signal: controller.signal,
			prompt: async (prompt: any) => {
				const { signal: _signal, ...shown } = prompt;
				emit("P", shown);
				if (spec.pendingPrompt) {
					promptSignal = prompt.signal;
					return new Promise<string>(() => {});
				}
				if (spec.watchPromptSignal) promptSignal = prompt.signal;
				if (spec.promptError) throw new Error(spec.promptError);
				if (answers.length === 0) throw new Error("Unexpected prompt");
				return answers
					.shift()!
					.replaceAll("{callback}", authParam("callback_url"))
					.replaceAll("{redirect_uri}", authParam("redirect_uri"))
					.replaceAll("{state}", authParam("state"));
			},
			notify: (event: any) => {
				emit("N", event);
				if (spec.abortOnDeviceCode && event.type === "device_code") controller.abort();
				if (event.type !== "auth_url") return;
				authUrl = event.url;
				callbackUrl = new URL(event.url).searchParams.get("callback_url") ?? "";
				if (spec.abortOnAuthUrl) controller.abort();
				if (spec.callbackCode === undefined) return;
				const target = new URL(callbackUrl);
				target.searchParams.set("code", spec.callbackCode);
				first = visit(target);
				if (spec.secondCallbackMs !== undefined) second = Bun.sleep(spec.secondCallbackMs).then(() => visit(target));
			},
		});
		emit("C", credential);
	}
} catch (error) {
	console.log(`E ${points(error instanceof Error ? error.message : String(error))}`);
}
const shown = (status: number | null) => (status === null ? "refused" : String(status));
if (first) console.log(`B ${shown(await first)}`);
if (second) console.log(`B2 ${shown(await second)}`);
if (spec.pendingPrompt || spec.watchPromptSignal) console.log(`M ${promptSignal?.aborted === true}`);
if (spec.abortOnAuthUrl) console.log(`R ${shown(await visit(new URL(callbackUrl)))}`);
