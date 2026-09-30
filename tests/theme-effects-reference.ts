import { UPSTREAM } from "./upstream_pin.mjs";
const { loadThemeFromPath } = await import(UPSTREAM + '/packages/coding-agent/src/modes/interactive/theme/theme.ts');
const theme = loadThemeFromPath(UPSTREAM + '/packages/coding-agent/src/modes/interactive/theme/dark.json', 'truecolor');
for (const text of process.argv.slice(2)) {
  for (const name of ['bold', 'italic', 'underline', 'inverse', 'strikethrough'] as const) {
    process.stdout.write(theme[name](text) + '\n');
  }
  process.stdout.write(theme.bold(theme.italic(text)) + '\n');
  for (const name of ['bold', 'italic', 'underline', 'strikethrough'] as const) {
    process.stdout.write(theme[name](text) + '\n');
  }
}
