import { UPSTREAM } from "./upstream_pin.mjs";
process.env.FORCE_COLOR = "1";
const { Theme, setThemeInstance } = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/theme/theme.ts");
const { renderDiff } = await import(UPSTREAM + "/packages/coding-agent/src/modes/interactive/components/diff.ts");
setThemeInstance(new Theme({ toolDiffRemoved: 1, toolDiffAdded: 2, toolDiffContext: 8, muted: 8, text: 7, thinkingXhigh: 4 }, { selectedBg: 0 }, "256color"));
for (const argument of process.argv.slice(2)) {
  const text = argument ? String.fromCodePoint(...argument.split(",").map(Number)) : "";
  console.log(Array.from(renderDiff(text), char => char.codePointAt(0)).join(","));
}
