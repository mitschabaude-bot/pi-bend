// Pinned PackageManager.resolve (pi-mono v0.87.1) for tests/package_manager_check.py.
// Run from ../pi-mono/packages/coding-agent: bun <this file> <cwd> <agentDir>.
// pi runs on Node, whose readdirSync returns names in byte order (libuv
// scandir); Bun returns directory order, so the listing is sorted first.
import { plugin } from "bun";
import { readFileSync } from "node:fs";
(globalThis as any).__nodeReaddir = (list: any[]) => {
  const nameOf = (entry: any) => Buffer.from(typeof entry === "string" ? entry : entry.name);
  return list.sort((a, b) => Buffer.compare(nameOf(a), nameOf(b)));
};
plugin({
  name: "node-readdir-order",
  setup(build) {
    build.onLoad({ filter: /pi-mono\/packages\/coding-agent\/src\/.*\.ts$/ }, ({ path }) => ({
      contents: readFileSync(path, "utf8").replace(/\breaddirSync\(([^()]*(?:\([^()]*\))?[^()]*)\)/g, "(globalThis as any).__nodeReaddir(readdirSync($1))"),
      loader: "ts",
    }));
  },
});
const { DefaultPackageManager } = await import("../../pi-mono/packages/coding-agent/src/core/package-manager.ts");
const { SettingsManager } = await import("../../pi-mono/packages/coding-agent/src/core/settings-manager.ts");
const [cwd, agentDir] = process.argv.slice(2);
const settingsManager = SettingsManager.create(cwd, agentDir);
const resolved = await new DefaultPackageManager({ cwd, agentDir, settingsManager }).resolve();
const rows = (list: any[]) => list.map((r) => ({ path: r.path, enabled: r.enabled, source: r.metadata.source, scope: r.metadata.scope, baseDir: r.metadata.baseDir ?? null }));
console.log(JSON.stringify({ skills: rows(resolved.skills), prompts: rows(resolved.prompts), themes: rows(resolved.themes) }));
