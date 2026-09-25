# Upstream delta: 46c9de402 → v0.87.1 (f07218c4d)

On 2026-09-23 Gregor moved the port's target to the pi v0.87.1 release. That release already contains GPT-6 Sol/Luna/Astra, and its published `@earendil-works/pi-ai` package ships the generated model data behind our catalogs.

Between the two commits, 56 non-merge commits touch `packages/{ai,agent,coding-agent,tui}/src`. The 21 below change files the port already has; each needs porting or an explicit decision. The other 35 change modules that aren't ported yet (interactive mode, extensions, the experimental services, Pico, bug reporting, other providers, LaTeX, clipboard). Those arrive with their modules.

| Commit | Change | Ported files | Status |
|---|---|---|---|
| f5c946480 | image input limits | ai types; file-processor, agent-session, read tool, main | done: models.json `inputLimits` and overrides; the read tool uses the context model's resize profile (else its own `resizeOptions`); `@file` images are attached unresized and AgentSession processes prompt images with the current model's profile, adding processing hints to the prompt text. Tool results enter the history with their images normalized under the same setting and profile (`utils/tool-result-images.bend`, AgentSession's `afterToolCall` hook). Not ported: the `before_agent_start` event that may pick the model first |
| c596d09d9, 3390bd936 | prompt cache warming | ai types (`promptCache`), cache-warmer, agent-session, session-manager, settings-manager, cache-stats, usage-totals, interactive | done except the `cache_warming_decision` extension event and historical notices (see "Cache warming" below) |
| 466db0fec | canonical session context boundaries | agent loop/agent/types, agent-session, compaction, session-manager | agent package done (`finishTurn`, `prepareRequest`, `peekQueuedMessages`, 24 new named tests); session-manager context edits, `buildSessionProjection` and projected compaction done (session-context-edit.test.ts ported); agent-session request projection, durable recovery omission and projection-aware compaction done; extension boundaries (`turn_end`, `agent_before_settle`) wait for the extension module |
| de2de549b | compaction cancellation races | agent-session | done: user abort stops retry, compaction and continuation (`requestAbort`/`abort`), cancellation read from the abort signal, automatic compaction cancellable from `compaction_start`; interactive aborts already go through `AgentSession.abort`. Not ported: the abort signal for summarization auth (`getAuth` takes none; auth is resolved in the stream call) |
| 8bdcd4498 | compact oversized trailing tool results | compaction | done: last valid cut point as fallback; #9740 case in tests/compaction |
| d192bd6dc | avoid split-turn summary refusals | compaction | done: new prompt, `# Conversation`/`# Instructions` sections |
| dd01f5b24 | faster recent-session discovery | session-manager | done: every candidate stat'ed first (`Stats.mtimeMs`), headers read newest first; a failed stat makes discovery unavailable |
| dfbf793b7 | progressive session picker | session-manager, main | session-manager and main done: cancellable listings (rejected with the abort reason), reverse-collation file order, all projects loaded newest `mtimeMs` first, periodic sorted snapshots, exact-id lookup through headers before the prefix listing; the startup `--resume` picker loads progressively and drops a cancelled load. The interactive `/resume` selector (Codex) still lists without progress or cancellation (tests/session-persistence.md) |
| 3c75b2747 | bug reporting | agent-session | pending (module not ported) |
| 890f92088 | unknown providers default to non-strict tools | ai types | done: doc-only in ported code (completions API not ported) |
| cf8d5fac3 | Pico storage foundation | agent/ai types, diagnostics | done: TypeScript-level JSON typing only; typed arguments already |
| b73412a37 | Meta provider | ai types, cli/args | pending (provider not ported) |
| 0e283203c, 661619e87 | overflow detection (z.ai, Cerebras) | ai/utils/overflow | done: 170 retry/overflow cases agree, incl. provider-scoped Cerebras |
| e40126f57 | reject invalid `--mode` | cli/args | done: already rejected; message wording updated |
| b6419322e | report invalid prompt frontmatter | prompt-templates, resource-loader | done in prompt-templates (warnings with Node messages, lenient fields, replacement decoding); the resource loader's prompt aggregation is not ported yet |
| 47a18e37b | complete GIF signatures | utils/mime | done |
| 59eb4c393 | copy shortcut description | keybindings | done |
| d7951ec36, bfa686240, 590144609 | autocomplete ranking, CJK punctuation, fuzzy latency | tui | Codex (TUI owner) |

Model catalogs are regenerated with `scripts/generate-model-catalog.py` from the published package's `dist/providers/data`. The generator rejects unknown fields, which is how `inputLimits` and `promptCache` surfaced.

## Retiring strict-policy deviations

Before 2026-09-23 some loaders deliberately deviated from upstream. They rejected malformed input where upstream tolerates it, and reported errors where upstream is silent. Gregor's rule now is exact upstream behaviour, so these deviations are to be retired module by module:

- The YAML module keeps its own error prose; the `yaml` package's messages and code frames are pending. Locations are being aligned: a block mapping value's error is reported at the value's column (prompt-templates' `description: Broken: unquoted colon` is line 1, column 14, as upstream); inline flow and quoted-scalar errors still report where the value starts rather than the failing token.
- Frontmatter rejects `---suffix` fences and nonmapping frontmatter.
- The skills loader warns on unreadable directories and invalid ignore patterns where upstream stays silent.
- Default tool-argument validation rejects coercible scalar mismatches that upstream coerces (`packages/agent/test/agent-validation.bend`, `packages/agent/README.md`).

Prompt templates were converted with b6419322e. The prompt-template load check compares YAML warnings by path and location only until the prose matches.

## Test inventory

`tests/upstream-inventory.json` now pins f07218c4d. Suites whose upstream file changed and that were already ported or partial were marked `needs-review` (18) until their diffs were ported; changed suites that were never ported stay pending. On 2026-09-25 all but autocomplete.test.ts (Codex, TUI owner) were reviewed against `git diff 46c9de402 f07218c4d`:

- Ported: constrained-sampling (annotation only), max-thinking (all cases, including the five catalog ids and the Codex `max` payload), overflow (exact z.ai and Cerebras inputs), args (the `--mode` block), image-process (GIF87a/GIF89a in the mime corpus), prompt-templates (invalid frontmatter keeps valid siblings) and file-operations (cancelled listing; the 512 MiB string-limit case stays pending, so the suite is partial).
- Still partial, with the new or changed cases pending: agent-session-concurrent (slow extension handlers), agent-session-compaction (#9652 request boundary, oversized tool result in the same run), agent-session-prompt and image-resize-callers (f5c946480 image limits behaviour), resource-loader (DefaultResourceLoader prompt diagnostics). Partial suites whose diff was type-only or already ported: validation, agent-session-model-extension, compaction (#9740), settings-manager (cacheWarming), agent-session-retry-events (the #9340 abort case).
- The new suite suite/regressions/9340-9777-auto-compaction-cancellation.test.ts is partial (three of six cases; see tests/agent-session.md).

## Cache warming (2026-09-25)

`core/cache-warmer.bend` ports `cache-warmer.ts`. The warmer is an immutable state machine (`Warmer`, `ActiveRun`) whose transitions (`started`, `fired`, `decided`, `replayed`, `settledState`, `modeChangedState`, `cancelled`, `statusOf`) take the clock, the global mode, the session's current model and transcript, and the branch's last prompt size as values and return their effects (a controller to abort, a usage record, the worker's next action). The I/O shell runs one worker per run: it sleeps on the run's abort signal, asks the decide hook, replays the request with `maxTokens` 1, `maxRetries` 0 and the run's own signal, and records successful refreshes; each transition is applied atomically on the warmer's `Ref`. Language-driven changes:

- Upstream's `this.run === run` identity is a run generation number; a replaced or stopped run's worker exits at its next transition.
- Upstream's `isCurrent` closure compares message identity. The port keeps the request's `CacheContext` (provider, model id, agent transcript) and compares it with the current one structurally (messages through their session JSON), so an equal transcript is current; a shorter or edited one is not.
- `status` is an `IO` read (mode, context and branch are observed, then the pure `statusOf` runs); `extensionOverride` is a `Bool` (upstream's absent flag reads as false).
- The warmer is created by `AgentSession.create`, which replaces the agent's stream function with the warming hook (upstream sdk's `streamFn`; session requests only) and restores it on dispose. `dispose` cancels and waits for workers, so no refresh touches a disposed session. The decide hook is pi's own decision: the extension runner and its `cache_warming_decision` event are not ported.
- A refresh can append while the agent persists a message, so AgentSession appends now hold the shared session state across their persistence (`Ref.update`, new in `runtime/src/ref.bend`); before, a read-append-write could lose a concurrent entry.

The `usage` session entry (`UsageEntry`, `appendUsage`, JSONL `type: "usage"`), its branches in cache-stats, usage totals, session stats and footer totals, the tree filter, the global-only `cacheWarming` setting (an unknown value stays an unknown field and reads as streaming), the settings selector row, `AgentSession.cacheWarmingStatus`/`setCacheWarmingMode`, the `/session` "Cache Warming" section and the live "Cache warmed" notice (behind cache notices) are ported. Not ported: rendering stored cache-warm notices when a session is resumed (the transcript is seeded from messages; upstream's entry-level rebuild, custom entries and compaction cost notices are not ported either) and the `cache_warming_decision` extension event. The Anthropic provider does not yet read `PI_CACHE_RETENTION`, while the warmer does, so with `PI_CACHE_RETENTION=long` the warmer would assume a one-hour entry for a five-minute write.

Tests: `tests/cache-warmer.bend` (eight upstream cases, two shell cases with real timers), `tests/cache-stats.bend` (new case), `tests/settings-cache-warming.bend` (both settings cases on real files), `tests/agent-session-stats.bend` (the cache-warming case and the usage JSONL line).

## Context edits: typed replacement content

Upstream's `ContextEditEntry.replacement.content` is the union of the editable roles' content types, assigned to the target message as-is. The port types it as text or a list of text, image, thinking and tool-call blocks, fitted to the target role when projected; text becomes a text block for assistant and tool-result targets, as upstream normalizes it. Blocks a role cannot hold (an image in assistant content, thinking or a tool call in user content) cannot form a typed message, so `appendContextEdit` rejects them and projecting such an edit read from a file fails with `UnfitContextEdit`. Upstream would store the edit and send an ill-typed message to the provider. No upstream test covers this case; this deviation awaits Gregor's review.

