import { UPSTREAM } from "./upstream_pin.mjs";
const { InteractiveMode } = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/interactive-mode.ts");
const themes = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/theme/theme.ts");
themes.setThemeInstance(themes.loadThemeFromPath(UPSTREAM + "/packages/coding-agent/src/modes/interactive/theme/dark.json", "truecolor"));
const view = Object.create(InteractiveMode.prototype);
const diagnostics = [
  { type: "warning", message: "Reserved key is skipped", path: "/home/agent/.pi/agent/extension.bend" },
  { type: "warning", message: "Later extension wins", path: "/project/.pi/extension.bend" },
  { type: "warning", message: "Clipboard override", path: "<inline:demo>" },
  { type: "error", message: "Handler error", path: "/tmp/extension.bend" },
  { type: "warning", message: "Unattributed warning" },
];
const sources = new Map([
  [diagnostics[0].path, { source: "local", scope: "user" }],
  [diagnostics[1].path, { source: "local", scope: "project" }],
  [diagnostics[2].path, { source: "inline", scope: "temporary" }],
  [diagnostics[3].path, { source: "cli", scope: "temporary" }],
]);
process.stdout.write(themes.theme.fg("warning", "[Extension issues]") + "\n" + view.formatDiagnostics(diagnostics, sources) + "\n");
