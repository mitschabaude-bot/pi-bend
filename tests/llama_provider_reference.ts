import { UPSTREAM } from "./upstream_pin.mjs";
const { createLlamaProvider } = await import(`${UPSTREAM}/packages/coding-agent/src/extensions/llama/provider.ts`);
const [base, mode, data] = process.argv.slice(2);
const controller = createLlamaProvider();
const models = JSON.parse(data).data;
const signal = new AbortController().signal;
const credential = { type: "api_key", key: "local", env: { LLAMA_BASE_URL: base } };
const ctx = { env: async (name: string) => name === "LLAMA_BASE_URL" ? base : name === "LLAMA_API_KEY" ? "env-key" : undefined };
if (mode === "login") {
  process.env.LLAMA_BASE_URL = base;
  const result = await controller.provider.auth.apiKey.login({ signal,
    prompt: async (p: any) => {
      console.log(`prompt|${p.message}|${p.placeholder ?? "-"}`);
      return p.type === "text" ? base + "/v1/" : " key ";
    }, notify: () => {} });
  console.log(`credential|${result.key ?? "-"}|${result.env.LLAMA_BASE_URL}`);
} else if (mode === "resolve") {
  const result = await controller.provider.auth.apiKey.resolve({ ctx, credential: undefined, signal });
  console.log(result ? `auth|${result.auth.apiKey}|${result.auth.baseUrl}|${result.source}` : "none");
} else if (mode === "cached") {
  let stored: any;
  await controller.provider.refreshModels({ credential, stored: undefined, allowNetwork: true, signal,
    publish: async (p: any) => { if (p.persist) stored = structuredClone(p.persist); p.update?.(); return true; } });
  for (const model of controller.provider.getModels()) console.log(JSON.stringify(model));
  if (!stored?.models || typeof stored.checkedAt !== "number") throw new Error("catalog not persisted");
  const second = createLlamaProvider();
  await second.provider.refreshModels({ credential, stored, allowNetwork: false, signal,
    publish: async (p: any) => { if (p.persist !== undefined) throw new Error("offline restore changed storage"); console.log("restored"); p.update?.(); return true; } });
  for (const model of second.provider.getModels()) console.log(JSON.stringify(model));
} else if (mode === "refresh" || mode === "thinking") {
  await controller.provider.refreshModels({ credential, stored: undefined, allowNetwork: true, signal,
    publish: async (p: any) => { p.update?.(); return true; } });
  for (const model of controller.provider.getModels()) console.log(JSON.stringify(model));
} else {
  controller.setCatalog(models, base, { routerAutoload: mode === "autoload" });
  for (const model of controller.provider.getModels()) console.log(JSON.stringify(model));
}
