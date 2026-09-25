# Small coding-agent regression suites

`tests/regressions_check.py` ports pi-mono's small `packages/coding-agent/test/suite/regressions/*.test.ts` suites. Each block cites its upstream file and test name and applies upstream's assertions to native results. It drives existing fixtures (`tests/agent-session.bend`, `tests/settings-manager.bend`, `tests/settings-files.bend`, `tests/frontmatter.bend`, `tests/cli-args.bend`, `tests/session-file.bend`) and `tests/regressions.bend`:

```sh
BEND=build/bend-native-toolchain/bend2/main.ts
for t in agent-session regressions settings-manager settings-files frontmatter cli-args session-file; do bun $BEND tests/$t.bend -o build/$t.js; done
python3 tests/regressions_check.py            # Bun lane
python3 tests/regressions_check.py --regressions build/regressions ...   # a native runner per fixture
```

`tests/regressions.bend` builds an `AgentSession` over a faux provider that streams like upstream's `registerFauxProvider`: a `start` event, then each block's start/delta/end events, with the text or the tool call's JSON arguments split into chunks, then `done`. Each request takes the next hold: it passes or waits at a gate (as in `tests/agent-session.bend`). The provider keeps the last request's abort signal, and a request whose signal is aborted when it proceeds ends as aborted, as upstream's faux does. Seed messages are stored in the session and loaded into the agent, as the harness's `agent.state.messages = buildSessionContext().messages`.

## Adaptations

- Chunks are a fixed four tokens (16 characters) instead of a random 3-5 tokens. Usage reports the output estimate `ceil(characters / 4)` without upstream's prompt estimate. Upstream's harness wires the built-in tools; the 7925 tool call runs against no tools and gets an error result, which the assertions don't cover.
- `harness.faux.state.callCount` is the number of scripted replies consumed (`remaining`).
- Session events are typed, so upstream's check that a session `message_update` has `message` and `partial` holds by construction. The fixture prints the session event's assistant message next to its wire form so usage can be compared (7911, 7925).
- Upstream injects compaction summaries through `session_before_compact` extension handlers, which the native extension runtime doesn't dispatch yet. 7150 holds the default summarizer's request open instead. Pre-prompt compaction scripts the summary as a provider reply, so "no continue" means the provider sees exactly the summary request and the prompt's request.
- `tree-during-streaming` holds the response at a gate and navigates meanwhile, instead of navigating from inside upstream's response factory.
- 7253 holds the second response until `compact()` has aborted it (the fixture waits for the request's signal), then releases it. The first response's `noop` tool call runs against no tools, and the manual summary is a scripted reply, so the result's summary contains it instead of equaling it.
- 5109 and 2835 run the runtime's tool resolution (`Runtime.resolveTools`, upstream createAgentSession's `tools`/`noTools`/`excludeTools`) over the built-in tools, a loadout assembled from its registry and active tools with the system prompt sections for them (`Runtime.activeTools`, `Runtime.sectionsForTools`), and the session's `getAllTools`, `getActiveToolNames`, `setActiveToolsByName` and `systemPrompt`. The registry's tools execute a stub; the scenarios never run them. The native extension API has no `registerTool`, so the extension tools of both suites (`ask_question`, `dynamic_tool`) are only unknown names in the lists.
- 6324 and 9178 run `AgentSession.navigateTreeWith` on seeded sessions. The provider logs each request's API key and last user text (`request` lines); 6324's summary reply carries upstream's usage (cost 0.25). 9178 holds the manual compaction's summary request instead of a `session_before_compact` handler; its second case (a navigation waiting in `session_before_tree`) needs extension events and stays pending.
- `tests/tree_navigation_check.py` ports agent-session-tree-navigation.test.ts on the `tree` scenario: prompts answered "reply N", then a navigation (optionally summarized, with custom instructions, or with the summary request held and `abortBranchSummary` called). Upstream runs it against a live model; the summary text is scripted, so the custom-instructions case checks the summarization request's text.
- 8328 spies `_runAutoCompaction`. The port observes the same decision as a `threshold` compaction, with `keepRecentTokens: 1` so that the compaction has something to cut.
- 7150's `preflightResult(false)` and rejection are the prompt's failed result.
- 3616's `DefaultResourceLoader.reload()` is the session's resource reload, `AgentSession.reload`, which reloads its settings manager.
- 7269 runs `parseArgs` through `tests/cli-args.bend` and prompts the session with the parsed message.
- 7497 lists sessions through `tests/session-file.bend`'s `listAll` operation (`SessionManager.listAll`) with the agent directory in `PI_CODING_AGENT_DIR`; a session's id is its file stem.
- 5661's registry half is a fixture of `tests/models_json_check.py` (differential against upstream's ModelRuntime, plus the literal request auth). Its migration half stays pending: the port has no `runMigrations`.
- 8337: settings files with a BOM go through `tests/settings-files.bend` (`SettingsManager.create`, then `setTheme` and flush). The merged getters are read from the global and project settings, which don't overlap. The port has no `splitBom` helper, so that assertion stays pending.
