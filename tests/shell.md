# POSIX shell utilities

`packages/coding-agent/src/utils/shell.bend` ports POSIX shell selection, environment policy and binary-output sanitization from pinned `packages/coding-agent/src/utils/shell.ts`. `ShellConfig` retains `shell`, `args` and optional `commandTransport` (`Argv`/`Stdin`); ordinary POSIX shells preserve the upstream absent transport field and `[-c]` arguments.

`getShellConfig(customPath)` reads PATH and applies the shared `getShellConfigWith(customPath, defaultBash, pathEntries)` algorithm: an explicitly supplied nonempty path, then `/bin/bash`, then executable `bash` on PATH, then bare `sh`. Custom/default paths retain upstream's existence check; the subsequent spawn reports execute-permission or invalid-image errors. PATH candidates require executable access and a regular file, following symlinks without opening content. Directories, FIFOs, sockets and broken links are skipped. No external `which` process participates in production lookup.

PATH components are searched in order. Empty components denote the current directory; their result uses `./bash` so execution refers to the selected file rather than performing another PATH search. The local reference `which` incorrectly returns no result for a wholly empty PATH, although `:` searches the current directory. Bend follows POSIX empty-component semantics for both; this is a deliberate difference from that host-utility quirk.

`getShellEnv(binDir, environment)` is pure over a list of named immutable variables. It preserves the first case-insensitive PATH spelling, prepends the supplied Pi bin directory only when the exact nonempty entry is absent, preserves existing empty path components, and leaves every other variable untouched. Configuration supplies `binDir`; this module does not invent another config singleton. `fromEntries` and `toEntries` translate the process primitive's `List<String>` boundary. Malformed entries, embedded NULs and duplicate exact variable names are rejected at decoding. `loadShellEnv(binDir)` reads `IO.environment()` once and applies the same policy.

`sanitizeBinaryOutput` follows the actual pinned filter: it removes C0 controls except tab/LF/CR and code points FFF9–FFFB. It does not broaden that filter to all Unicode format characters based on the upstream comment; DEL, C1, joiners, bidi formatting and BOM remain unchanged. Bend strings contain Unicode scalars, so JavaScript lone UTF-16 surrogates are not representable inputs. Valid supplementary characters are preserved.

Build `tests/shell.bend` with the native process/environment and `File.is_file` primitive patches, then run:

```sh
python3 tests/shell_check.py --runner build/shell.js
python3 tests/shell_check.py --runner build/shell --threads 1
python3 tests/shell_check.py --runner build/shell --threads 4
```

Bun and ordinary-O1 native execution with explicit one/four workers each pass 152 comparisons with the actual pinned TypeScript implementation, 24 executable-search/fallback checks, four malformed-environment checks and ambient environment loading. Filesystem fixtures cover executable and non-executable regular files, directories, symlinks, broken links, FIFOs and Unix sockets. `which` is used only as an independent test oracle for the PATH cases, with the explicitly specified empty-PATH adaptation checked separately. The isolated candidate combines the existing process/files primitives with `File.is_file` commit `7bcf5d4`; this module installs no compiler changes.

Windows Git Bash lookup, legacy WSL stdin transport, PowerShell and detached-process tracking/termination are not implemented by this POSIX module. Process execution and Bash tool integration remain separate work; these checks do not mark the full upstream shell/tool suite ported.
