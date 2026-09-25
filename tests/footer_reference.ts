import { UPSTREAM } from "./upstream_pin.mjs";
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { strict as assert } from 'node:assert';
const { FooterComponent } = await import(UPSTREAM + '/packages/coding-agent/src/modes/interactive/components/footer.ts');
const { initTheme } = await import(UPSTREAM + '/packages/coding-agent/src/modes/interactive/theme/theme.ts');

// f07218c4d: compare against the actual upstream component, not copied output.
for (const [file, digest] of [
  ['components/footer.ts', '9e0f71e0f405a9f0fdae901de2778834649facd0f78a78b53c682179f8faf693'],
  ['theme/dark.json', '103a5aecb74a2dab5cc903c9741845ee6158658ce2ff6e5445948784116eaef8'],
] as const) {
  const path = UPSTREAM + '/packages/coding-agent/src/modes/interactive/' + file;
  assert.equal(createHash('sha256').update(readFileSync(path)).digest('hex'), digest);
}
initTheme('dark');

type Usage = { input: number; output: number; cacheRead: number; cacheWrite: number; cost: { total: number } };
const usage = (input: number, output: number, cacheRead: number, cacheWrite: number, cost: number): Usage => ({ input, output, cacheRead, cacheWrite, cost: { total: cost } });
type Case = {
  label: string; width: number; cwd: string; home?: string; branch?: string; name?: string;
  id?: string; provider?: string; reasoning?: boolean; thinking?: string; providerCount?: number;
  entries?: any[]; percent?: number | null; subscription?: boolean; auto?: boolean; statuses?: [string, string][];
};
const assistant = (entry: Usage) => ({ type: 'message', message: { role: 'assistant', usage: entry } });
const cases: Case[] = [
  { label: 'basic', width: 93, cwd: '/home/user/project', home: '/home/user', branch: 'main', name: '한글'.repeat(30), id: 'test-model', provider: 'test', percent: 12.3 },
  { label: 'wide-model', width: 60, cwd: '/tmp/project', branch: 'main', id: '模'.repeat(30), provider: '공급자', reasoning: true, thinking: 'high', providerCount: 2, entries: [assistant(usage(12345, 6789, 0, 0, 1.234))], percent: 12.3 },
  { label: 'cumulative', width: 120, cwd: '/home/user2', home: '/home/user', branch: 'main', id: 'test-model', provider: 'test', entries: [assistant(usage(100, 10, 0, 0, .5)), { type: 'branch_summary', usage: usage(20, 5, 0, 0, .25) }, { type: 'compaction', usage: usage(5, 2, 0, 0, .125) }, { type: 'message', message: { role: 'toolResult', usage: usage(15, 3, 0, 0, .375) } }], percent: 12.3 },
  { label: 'cache', width: 120, cwd: '/tmp/project', id: 'test-model', provider: 'test', entries: [assistant(usage(100, 10, 50, 50, .001))], percent: 72.5 },
  { label: 'subscription', width: 120, cwd: '/tmp/project', id: 'test-model', provider: 'anthropic', subscription: true, percent: 91.1, auto: false },
  { label: 'statuses', width: 48, cwd: '/tmp/project', id: 'test-model', provider: 'test', percent: null, statuses: [['z', ' build\n done '], ['a', ' lint\t pass  ']] },
];
for (const c of cases) {
  process.env.HOME = c.home ?? '/home/no-match';
  const session = {
    state: { model: { id: c.id, provider: c.provider, reasoning: c.reasoning ?? false, contextWindow: 200000 }, thinkingLevel: c.thinking ?? 'off' },
    sessionManager: { getEntries: () => c.entries ?? [], getSessionName: () => c.name ?? '', getCwd: () => c.cwd },
    getContextUsage: () => ({ contextWindow: 200000, percent: c.percent }),
    modelRuntime: { isUsingSubscription: () => c.subscription ?? false },
  };
  const provider = { getGitBranch: () => c.branch, getAvailableProviderCount: () => c.providerCount ?? 1, getExtensionStatuses: () => new Map(c.statuses ?? []) };
  const footer = new FooterComponent(session as any, provider as any);
  footer.setAutoCompactEnabled(c.auto ?? true);
  process.stdout.write(c.label + '\x1e' + footer.render(c.width).join('\x1f') + '\n');
}
