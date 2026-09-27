// Test-only oracle for tests/node_http_proxy_check.py: pinned pi-mono's
// resolveHttpProxyUrlForTarget, printed as packages/ai/test/node-http-proxy.bend
// prints it.
import { UPSTREAM } from "./upstream_pin.mjs";

const { resolveHttpProxyUrlForTarget } = await import(`${UPSTREAM}/packages/ai/src/utils/node-http-proxy.ts`);
const [target, env] = process.argv.slice(2);
try {
	const url = resolveHttpProxyUrlForTarget(target, env === undefined ? undefined : JSON.parse(env));
	console.log(url === undefined ? "none" : `url ${url.toString()}`);
} catch (error) {
	console.log(`error ${(error as Error).message}`);
}
