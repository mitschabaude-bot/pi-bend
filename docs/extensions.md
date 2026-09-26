# Native extensions: design

pi's extensions are TypeScript modules loaded at runtime (`core/extensions/loader.ts` with jiti). AGENTS.md excludes JavaScript/TypeScript extension compatibility: pi-bend's extensions are Bend modules compiled into the binary. This note fixes the shape of that runtime so the built-in llama.cpp extension and later user extensions share one API. It follows upstream `core/extensions/{types,runner,index}.ts` at f07218c4d.

## What stays the same

- **Names and concepts.** `ExtensionAPI`, `ExtensionContext`, `ExtensionCommandContext`, `ExtensionUIContext`, `RegisteredCommand`/`ResolvedCommand`, `InlineExtension`, `ExtensionRunner` and the event names (`session_start`, `tool_call`, `input`, …) keep their upstream names and meaning.
- **Registration.** An extension is a factory run once per runtime with an `ExtensionAPI`. It registers commands, providers, tools, shortcuts, flags and renderers, and subscribes to events. Upstream's `builtInExtensions` list becomes a Bend list of `InlineExtension{name, factory, hidden}`.
- **Dispatch order.** Handlers run in registration order. Results chain the way upstream's `emit*` functions chain them. For example, `tool_call` stops at the first block, `context` threads messages through handlers, and `input` can transform or handle the input. A handler failure becomes an `ExtensionError` for the owner and does not stop dispatch, as `emitError` does upstream.
- **Command names.** An extension command that shadows a built-in keeps its `invocationName` suffix rules and the conflict diagnostics (`getBuiltInCommandConflictDiagnostics`).

## What changes, and why

- **No loader.** Extensions are linked at build time. Discovery, package installation and jiti are replaced by the compiled list. User extensions would be Bend packages built into a custom binary. That is outside this design and recorded as a limitation.
- **Typed callbacks instead of closures over mutable objects.** The factory receives an `ExtensionAPI` record of registration callbacks. Handlers are `Callback`s over typed event and result records, one sum type per result family. They are not `unknown`-typed JavaScript functions.
- **Registrations are data.** The runner keeps an immutable `Registrations` record: commands, providers, tools, shortcuts, flags, handlers per event and renderers. It lives in a serialized resource. Registering is an explicit state transition. Reads take snapshots.
- **Unsubscribe.** `on` returns an unsubscribe callback (upstream's `() => void`). It removes the handler by its registration id, not by function identity.
- **Context.** `ExtensionContext` is built per call from the live session (cwd, model, scoped models, thinking level, mode, `hasUI`, abort), as upstream's `createContext`. Actions that act on the session (`newSession`, `fork`, `switchSession`, `waitForIdle`) are callbacks bound by the mode, matching `bindCommandContext`.
- **UI context.** `notify`, `select`, `confirm`, `input`, `setStatus`, `setWorkingMessage`/`setWorkingVisible` and `custom` are callbacks the interactive mode binds. Print and RPC modes bind the no-UI variant (`hasUI = false`). `custom` receives a Bend component factory rather than a TypeScript component class.

## Phases

1. **Commands, providers, notify: the llama.cpp extension.**
   - Types: `ExtensionAPI` (`registerCommand`, `registerProvider`), `ExtensionCommandContext` (`ui.notify`, `ui.custom`, `modelRegistry.refresh`/`getProviderAuth`, `env`, `mode`), `InlineExtension`, `ExtensionRunner` (commands, providers, diagnostics).
   - Integration: extension providers join `ModelRuntime`, including dynamic catalogs refreshed on demand. Interactive `/name` dispatch falls through to extension commands before it submits a prompt. Autocomplete lists extension commands with source tags and argument completions. RPC `get_commands` includes them.
   - Port `extensions/llama/*` with its tests.
2. **Session and agent events.** `session_start`/`shutdown`/`before_*`, `before_agent_start`, `agent_*`, `turn_*`, `message_*`, `tool_execution_*`, `model_select`, `thinking_level_select`, `context`, `before_provider_request`/`headers`, `after_provider_response`, `cache_warming_decision`, `tool_call`/`tool_result`, `user_bash`, `input`. These are wired at the AgentSession and agent-loop points where upstream calls `emit*`, with upstream's tests.
3. **Tools, shortcuts, flags, renderers, UI dialogs.** `registerTool` (joined to the tool registry with `sourceInfo`), `registerShortcut` (the keybinding conflict rules), `registerFlag`, message/entry renderers and markdown transformers, `select`/`confirm`/`input` dialogs and autocomplete provider wrappers.

Each phase ports the upstream test files it covers (`test/extensions-*.test.ts`) and records them in `tests/upstream-inventory.json`.

## Phase 1 core: implementation notes

Modules: `core/extensions/context.bend` (`ExtensionContext`, `ExtensionCommandContext`, `ExtensionUIContext`, context actions), `types.bend` (commands, events, `ExtensionError`, `InlineExtension`, runtime state), `loader.bend` (`createExtensionRuntime`, the `ExtensionAPI` operations, `loadExtensionFromFactory`, `loadExtensionFactories`, provider binding), `runner.bend` (`ExtensionRunner`) and `extensions/index.bend` (`builtInExtensions`, empty until llama.cpp is ported). Model runtime: `ModelRuntime.refresh`, `registerNativeProvider`, `unregisterProvider`; pi-ai `Provider.refreshModels`, `RefreshModelsContext`, `ModelsPublication`, `createProvider`'s fetch refresh (`fetchedRefresh`, `mergeModels`) and `models-store.bend`.

Language-driven changes:

- **API as a handle.** `ExtensionAPI` is `{runtime, extension}`; its methods are `loader.bend` functions (`registerCommand(pi, name, options)`, `registerProvider`, `unregisterProvider`, `on`). They return `Result` instead of throwing; a failed extension's API fails with upstream's message.
- **Context as a handle.** `ExtensionContext` holds the runner's cwd, model runtime and bindings. Upstream's lazy getters are IO accessors (`Ctx.model(ctx)`, `Ctx.isIdle(ctx)`, `Ctx.notify(ctx, …)`), so they read the session at call time. `sessionManager` is reduced to the session id and file.
- **Publication carries the catalog.** Upstream's `update` closure replaces a provider's private model list. Here `ModelsPublication.models` is that list, and the model runtime keeps it per provider. A superseded refresh keeps running, but its publications are rejected by generation. It is not aborted.
- **`custom`** receives a component factory and a `done` callback and answers when `done` runs. The generic result travels through the extension's own state.
- **Inline factories are functions.** `InlineExtension` is `Type`-kinded and consumed on load.

Not yet ported: config-form `registerProvider(name, config)` and its validation, models.json overlays on extension providers, reloading models.json on refresh, `FileModelsStore` (models-store.json), stale-context invalidation, `withSession`/`setup` continuations, extension error listeners in the modes, re-running factories on `/reload`, and the interactive UI binding. The UI binding is left to the interactive mode.

## Phase 2 progress

Ported: `agent_start`, `agent_end`, `agent_settled`, `turn_start` (with the run's turn index), `message_start`/`message_update`/`message_end` and `tool_execution_*` reach extensions before the session's listeners (`AgentSession` `handleEvent`). `message_end` handlers may replace the finalized message with one of the same role (`emitMessageEnd`); the listeners, the session entry and the agent's context carry the replacement. `tool_call` handlers run in the agent's `beforeToolCall` (first block wins, a failing handler blocks the call) and `tool_result` handlers patch the result in `afterToolCall` before image normalization (`emitToolResult`). `pi.sendMessage` and `pi.sendUserMessage` are bound by the session (`ExtensionActions`); before binding they fail with upstream's "not initialized" message. Deliveries that queue or append happen at once; one that starts a turn runs on its own task, and failures become `<runtime>` extension errors.

Pending: the `turn_end`/`agent_before_settle` boundaries (entry drafts, continuation), `session_*` events (`session_start`, `session_before_compact`/`tree`/`switch`/`fork`, `session_compact`, `session_shutdown`), `context`/`context_with_system`, `before_agent_start`, `input`, `user_bash`, provider request/response events, `model_select`/`thinking_level_select`, `appendEntry` and the other action methods, the `_isEmittingAgentSettled` deferral of prompts sent from `agent_settled` handlers, and upstream's in-place replacement of the original message in `turn_end`/`agent_end` payloads.

