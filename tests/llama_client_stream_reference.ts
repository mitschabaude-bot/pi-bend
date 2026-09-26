import { UPSTREAM } from "./upstream_pin.mjs";
const { LlamaClient } = await import(`${UPSTREAM}/packages/coding-agent/src/extensions/llama/client.ts`);
const [base, mode] = process.argv.slice(2);
const client = new LlamaClient(base, "test-key");
const controller = new AbortController();
const progress: string[] = [];
const report = (p: any) => progress.push(`${p.message}|${p.ratio ?? "-"}|${p.detail ?? "-"}`);
const modelText = (model: any) => `${model.id}|${model.status.value}`;
let timeout;
if (mode === "cancel") timeout = setTimeout(() => controller.abort(), 150);
try {
  if (mode === "download") {
    console.log((await client.downloadAndWait("owner/repo:Q4_K_M", report, controller.signal)).map(modelText).join("\n"));
  } else {
    console.log(modelText(await client.loadAndWait("test-model", report, controller.signal)));
  }
} catch (error) {
  if (mode !== "cancel" && mode !== "failure") throw error;
  console.log(`error|${error.message}`);
} finally { clearTimeout(timeout); }
for (const p of progress) console.log(p);
