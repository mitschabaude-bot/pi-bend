// Test-only oracle for tests/http_proxy_check.py: pinned pi-mono's
// configureHttpDispatcher (undici's EnvHttpProxyAgent with proxyTunnel) under
// the proxy environment the check sets and the given `httpProxy` setting
// (applyHttpProxySettings), fetching each URL in turn and printing
// what tests/http-proxy.bend prints. Run with Node (undici is Node's fetch).
import { UPSTREAM } from "./upstream_pin.mjs";

const { applyHttpProxySettings, configureHttpDispatcher } = await import(`${UPSTREAM}/packages/coding-agent/src/core/http-dispatcher.ts`);
const [setting, ...urls] = process.argv.slice(2);
applyHttpProxySettings(setting === "-" ? undefined : setting);
configureHttpDispatcher();
for (const url of urls) {
	try {
		const response = await fetch(url);
		console.log(`status ${response.status} ${await response.text()}`);
	} catch (error) {
		// undici reports a refused tunnel as fetch failed > Request was cancelled > the proxy message.
		let cause = error as { message?: string; cause?: unknown } | undefined;
		while (cause && !cause.message?.startsWith("Proxy response")) cause = cause.cause as typeof cause;
		console.log(cause?.message ? `error ${cause.message}` : "failed");
	}
}
