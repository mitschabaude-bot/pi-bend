# Upstream delta: 46c9de402 → v0.87.1 (f07218c4d)

On 2026-09-23 Gregor moved the port's target to the pi v0.87.1 release. That release already contains GPT-6 Sol/Luna/Astra, and its published `@earendil-works/pi-ai` package ships the generated model data behind our catalogs.

Between the two commits, 56 non-merge commits touch `packages/{ai,agent,coding-agent,tui}/src`. The 21 below change files the port already has; each needs porting or an explicit decision. The other 35 change modules that aren't ported yet (interactive mode, extensions, the experimental services, Pico, bug reporting, other providers, LaTeX, clipboard). Those arrive with their modules.

| Commit | Change | Ported files | Status |
|---|---|---|---|
| f5c946480 | image input limits | ai types; file-processor, agent-session, read tool, main | types and catalog done; behaviour pending |
| c596d09d9 | prompt cache warming | ai types (`promptCache`), agent-session, session-manager, settings-manager | `Model.promptCache` done; warming pending |
| 466db0fec | canonical session context boundaries | agent loop/agent/types, agent-session, compaction, session-manager | pending (AgentLoopConfig `finishTurn`/`prepareRequest` surface in tests/loop_config_types) |
| de2de549b | compaction cancellation races | agent-session | pending |
| 8bdcd4498 | compact oversized trailing tool results | compaction | done: last valid cut point as fallback; #9740 case in tests/compaction |
| d192bd6dc | avoid split-turn summary refusals | compaction | done: new prompt, `# Conversation`/`# Instructions` sections |
| dd01f5b24 | faster recent-session discovery | session-manager | pending |
| dfbf793b7 | progressive session picker | session-manager, main | pending |
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

- The YAML module keeps its own error prose; the `yaml` package's messages and code frames are pending.
- Frontmatter rejects `---suffix` fences and nonmapping frontmatter.
- The skills loader warns on unreadable directories and invalid ignore patterns where upstream stays silent.

Prompt templates were converted with b6419322e. The prompt-template load check compares YAML warnings by path and location only until the prose matches.
