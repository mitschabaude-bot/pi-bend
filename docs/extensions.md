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
