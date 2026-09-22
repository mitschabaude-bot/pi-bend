# Session persistence

`packages/coding-agent/src/core/session-persistence.bend` is the upstream `SessionManager` class surface over the immutable state in `session-manager.bend`: `create`, `open`, `continueRecent`, `inMemory` (with optional stored entries), `forkFrom`, `findById`, `list`, `listAll`, `findMostRecentSession`, `loadEntriesFromFile`, `readSessionHeader`, `newSession`, `setSessionFile`, the persisting appends (`appendMessage`, `appendThinkingLevelChange`, `appendModelChange`, `appendCompaction`, `appendCustomEntry`, `appendCustomMessageEntry`, `appendSessionInfo`, `appendLabelChange`, `branchWithSummary`), `branch`, `resetLeaf`, `createBranchedSession`, and the accessors `getSessionFile`, `getSessionDir`, `getCwd`, `getSessionId`, `isPersisted`, `usesDefaultSessionDir`. `packages/coding-agent/src/core/session-json.bend` is the JSONL file format: entries render in upstream's member order, read back through typed decoders, and migrate on the parsed JSON objects (v1 → v2 ids/parent chains and compaction indices, v2 → v3 `hookMessage` → `custom`). Typed `Ai.Message` decoding is the new second half of `packages/ai/src/utils/message-json.bend`.

## Language-driven differences

- The session is an immutable record; every mutating method returns the next `Session` (appends return `Appended{session, id}`), and file effects happen in `IO`. Pure tree queries go through `stateOf` and the state module (`S.getEntries`, `S.getBranch`, `S.getTree`, ...) instead of forwarding methods.
- `SessionManager` upstream is generic only in the custom-entry payload; the port keeps the state's three parameters (diagnostic details, tool details, custom data) and takes their JSON encoders/decoders as compile-time function parameters, because Bend's template parameters must be definitions, not values in a record.
- The agent directory (upstream's process-global `getDefaultAgentDir()`) and the process working directory are explicit arguments.
- `loadEntriesFromFile` returns the entries as written, like upstream; entries older than version 2 carry no ids and cannot be typed, so they are absent from that view. Opening a session migrates on the JSON objects first (and rewrites the file), and `forkFrom` copies the migrated entries, so a fork of a v1 session is a current file rather than upstream's raw copy.
- An object that parses as JSON but does not decode as a session entry is skipped like a malformed line; upstream would carry it untyped.
- Usage members `totalTokens` and `cost` absent from sessions written before they existed read as zero.
- `inMemory` with typed entries cannot carry a `hookMessage` role; the v2-header case is checked through the header version and entry ids, and the headerless `hookMessage` case is not representable.
- Session listings summarize files one after another; upstream loads ten concurrently.
- Session ids are validated by a character walk equivalent to `/^[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?$/`; short entry ids are eight hex digits from four OS-random bytes, collision-checked against the index, with a UUIDv7 after 100 collisions, as upstream.

## Primitives

Modification times come from `File.modified_time` (native-tls's `bend-file-lock-effects.patch`, exact seconds and nanoseconds), rounded to milliseconds as Node's `Stats.mtime.getTime()` by `FS.modified`; `FS.appendFile` and `FS.writeFileExclusive` wrap the existing open modes.

## Validation

`tests/session_file_reference.ts` drives the actual pinned `SessionManager` with JSON operations; `tests/session-file.bend` answers the same operations through the port; `tests/session_file_check.py` writes the fixture files, runs both, asserts the upstream expectations on each, and compares the two result streams after normalizing generated ids, timestamps and timestamped file names.

Ported by name: file-operations.test.ts (`loadEntriesFromFile` ×9, header discovery ×3, the scan-limit cases, `findMostRecentSession` ×9, the flat custom directory case, `setSessionFile` with corrupted files ×5), load-entries.test.ts (13 of 14; "adopts headerless entries as current-version without migrating them" is not representable), migration.test.ts (2), save-entry.test.ts (1), custom-session-id.test.ts (13) and session-info-modified-timestamp.test.ts (1). "opens session files larger than Node's max string length" writes a 512 MiB sparse file to exercise a JavaScript string limit and is not ported.

```sh
build/bend-process-files/bend2/main.ts tests/session-file.bend -o build/session-file.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/session-file.bend build/session-file
python3 tests/session_file_check.py --runner build/session-file.js
python3 tests/session_file_check.py --runner build/session-file --threads 1
python3 tests/session_file_check.py --runner build/session-file --threads 4
```

## CLI

`packages/coding-agent/src/main.bend` ports upstream's `createSessionManager`, `validateForkFlags`, `validateSessionIdFlags`, `getMissingSessionCwdIssue` and the `--name` handling; the agent runtime (`core/agent-runtime.bend`) takes a `SessionSeed` (context messages, recorded model, recorded thinking level) and records the chosen model and thinking level on the session as the SDK does. The agent's custom message type is now pi's coding message union (`Messages.CodingMessage`, converted by `convertToLlm`), so restored bash executions and extension messages survive a resume; tool details restored from a file stay `RawDetails` JSON. `--session` for a session of another project asks "Fork this session into current directory? [y/N]" and reads the answer from standard input to its end (there is no line primitive). `--resume` reports that the interactive selector is not ported. `tests/print_cli_check.py` covers the flag conflicts, the invalid id, the not-a-session file (session-file-invalid.test.ts), the missing stored cwd and an unknown id offline, and with `PI_BEND_LIVE=1` a run against a stored session (header from the file, thinking level recorded, no new messages yet).


Root integration with the shared process/files compiler passes 364 operations on native one/four threads, adding discovery across pre-epoch and post-epoch file timestamps. FS.modified interprets the syscall’s seconds as signed two’s-complement before converting to milliseconds. The shared compiler does not carry the experimental explicit-stack JS emitter: its Bun run fails the oversized-header fixture with a machine-stack overflow. Earlier Bun results above used the other agent’s patched private compiler; they do not establish a pass on the shared unpatched compiler.

The combined native CLI rebuild also passes `PI_BEND_CODEX_LIVE=1 python3 tests/print_cli_check.py`: offline argument/session-file checks and a live request through the existing stored Codex OAuth login. This still does not claim that newly generated messages are persisted; that requires the AgentSession integration described above.
