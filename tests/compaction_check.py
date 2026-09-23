#!/usr/bin/env python3
"""Pinned expectations of upstream compaction.test.ts and compaction-serialization.test.ts
against tests/compaction.bend (packages/coding-agent/src/core/compaction)."""
import argparse, json, subprocess
from pathlib import Path

SCENARIOS = ['tokens', 'last-usage', 'estimate', 'should-compact', 'cut-tokens', 'cut-none', 'cut-fits', 'cut-split', 'cut-custom-tiny', 'cut-custom-fits',
             'context-plain', 'context-single', 'context-multiple', 'context-first', 'context-changes', 'prepare-system', 'prepare-skip', 'prepare-move',
             'serialize-long', 'serialize-short', 'serialize-plain', 'serialize-mixed', 'file-ops']

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', required=True)
    parser.add_argument('--threads', default='1')
    args = parser.parse_args()
    runner = str(Path(args.runner).resolve())
    command = ['bun', runner] if runner.endswith('.js') else [runner, '--threads', args.threads, '--']
    output = subprocess.run(command + SCENARIOS, capture_output=True, text=True, check=True).stdout.splitlines()
    r = dict(zip(SCENARIOS, (json.loads(line) for line in output)))
    assert len(r) == len(SCENARIOS), output
    checks = 0
    # Token calculation
    assert r['tokens'] == {'full': 1800, 'zero': 0}, r['tokens']
    checks += 2
    # getLastAssistantUsage
    assert r['last-usage'] == {'last': 200, 'aborted': 100, 'zero': 100, 'none': None}, r['last-usage']
    checks += 4
    # estimateContextTokens uses the last non-zero assistant usage as the context anchor
    e = r['estimate']
    assert e['usageTokens'] == 150 and e['lastUsageIndex'] == 1 and e['trailingTokens'] > 0 and e['tokens'] == 150 + e['trailingTokens'], e
    checks += 1
    # shouldCompact
    assert r['should-compact'] == {'above': True, 'below': False, 'disabled': False}, r['should-compact']
    checks += 2
    # findCutPoint
    assert r['cut-tokens']['role'] in ('user', 'assistant'), r['cut-tokens']
    assert r['cut-none']['firstKeptEntryIndex'] == 0
    assert r['cut-fits']['firstKeptEntryIndex'] == 0
    split = r['cut-split']
    assert split['role'] != 'assistant' or (split['isSplitTurn'] and split['turnStartIndex'] == 2), split
    tiny, fits = r['cut-custom-tiny'], r['cut-custom-fits']
    assert (tiny['firstKeptEntryIndex'], tiny['isSplitTurn'], tiny['turnStartIndex']) == (3, True, 2), tiny
    assert (fits['firstKeptEntryIndex'], fits['isSplitTurn'], fits['turnStartIndex']) == (2, False, None), fits
    checks += 5
    # buildSessionContext
    plain = r['context-plain']
    assert plain['count'] == 4 and plain['thinkingLevel'] == 'off' and plain['model'] == {'provider': 'anthropic', 'modelId': 'claude-sonnet-4-5'}, plain
    single = r['context-single']
    assert single['count'] == 5 and single['first'] == 'compactionSummary' and 'Summary of 1,a,2,b' in single['firstText'], single
    multiple = r['context-multiple']
    assert multiple['count'] == 5 and 'Second summary' in multiple['firstText'], multiple
    assert r['context-first']['count'] == 5, r['context-first']
    changes = r['context-changes']
    assert changes['model'] == {'provider': 'anthropic', 'modelId': 'claude-sonnet-4-5'} and changes['thinkingLevel'] == 'high', changes
    checks += 5
    # prepareCompaction
    system = r['prepare-system']
    assert system is not None and system['firstKeptEntryId'] == 'test-id-2' and system['isSplitTurn'] and system['summarized'] == '' and system['prefix'] == 'one long turn', system
    assert r['prepare-skip'] is None, r['prepare-skip']
    move = r['prepare-move']
    assert move is not None and 'user msg 2 - kept by compaction1' in move['summarized'] and 'user msg 3 - kept by compaction1' in move['summarized'] and 'First summary' not in move['summarized'] and move['previousSummary'] == 'First summary', move
    checks += 3
    # serializeConversation
    long = r['serialize-long']
    assert '[Tool result]:' in long and '[... 3000 more characters truncated]' in long and 'x' * 3000 not in long and 'x' * 2000 in long, long[:80]
    short = r['serialize-short']
    assert 'x' * 1500 in short and 'truncated' not in short
    plainText = r['serialize-plain']
    assert 'u' * 3000 in plainText and 'a' * 3000 in plainText and 'truncated' not in plainText
    assert r['serialize-mixed'] == '[User]: hi\n\n[Assistant thinking]: why\n\n[Assistant]: hello\n\n[Assistant tool calls]: read(path="a.txt", limit=3)\n\n[Tool result]: done', r['serialize-mixed']
    checks += 4
    # file operations: modified files exclude read-only ones, sorted, formatted sections
    assert r['file-ops'] == {'read': ['b.txt'], 'modified': ['a.txt', 'c.txt'], 'formatted': '\n\n<read-files>\nb.txt\n</read-files>\n\n<modified-files>\na.txt\nc.txt\n</modified-files>'}, r['file-ops']
    checks += 1
    print('compaction: %d checks passed' % checks)

if __name__ == '__main__':
    main()
