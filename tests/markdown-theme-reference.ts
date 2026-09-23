import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';

const root = '/home/agent/code/pi-mono';
for (const [path, hash] of [
  ['packages/coding-agent/src/modes/interactive/theme/theme.ts', 'c3bf2e3b72f6bb782f34de0535fcc1758b9b6ea7a0d2e7d6f17244fa55c3f31a'],
  ['packages/tui/src/components/markdown.ts', '704c1c714a7ff6bdec55573ab38393726fa73a7b47cf4c1161ccc4f08530ac28'],
] as const) assert.equal(createHash('sha256').update(readFileSync(`${root}/${path}`)).digest('hex'), hash);
const { loadThemeFromPath, setThemeInstance, getMarkdownTheme } = await import(`${root}/packages/coding-agent/src/modes/interactive/theme/theme.ts`);
const { Markdown } = await import(`${root}/packages/tui/src/components/markdown.ts`);
setThemeInstance(loadThemeFromPath(`${root}/packages/coding-agent/src/modes/interactive/theme/dark.json`, 'truecolor'));
const cases = ['# Heading', '**bold** and *italic*', '[link](https://example.com)', '~~gone~~ and `code`', '> quoted'];
for (const source of cases) console.log(JSON.stringify(new Markdown(source, 0, 0, getMarkdownTheme()).render(42)));
