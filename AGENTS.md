# Faithful pi port

The user requires a close port of pi-mono's modular libraries, internal main types, public APIs and behavior, including terminal UI and dependencies. A working CLI or matching a few visible behaviors does not satisfy the task. The sole intentional scope exclusion is loading JavaScript/TypeScript extensions; extension APIs and lifecycle behavior must support Bend implementations.

Reference: sibling `../pi-mono`, commit `46c9de402`. Preserve the upstream package/module boundaries under `packages/`. Preserve public type, field, function and event names where Bend permits them. Document language-driven changes individually; do not collapse typed models into generic JSON, flatten library layers into the CLI, omit hooks, or replace injectable interfaces with hard-coded implementations.

The current `src/` executable is a bootstrap prototype. Its networking/authentication checks and live subagent demonstrations are useful evidence for the native runtime, not acceptance evidence for the library port. Do not grow this prototype into a separate approximate architecture. Introduce canonical library modules with upstream tests and migrate the entry points onto those modules.

Port pi-mono tests with their original assertions, test names, edge cases and event ordering. Keep a source-to-port map in `tests/upstream-inventory.json`. Distinguish pending, partial and fully ported suites. Supplement with differential tests and native tests where runtime differences require them. Never weaken expectations to fit the implementation or mark skipped cases as complete.

Push tested milestones to the authorized public GitHub repository. Never commit authentication, tokens, private sessions, generated binaries or vendor downloads. Keep limitations explicit in the README and parity records.
