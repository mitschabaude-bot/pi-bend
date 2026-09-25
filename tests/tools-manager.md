# tools-manager and management HTTP

`coding-agent/src/utils/tools-manager.bend` ports upstream's `tools-manager.ts`, and `utils/management-http.bend` ports its `fetchWithRetry`. Upstream has no test file for the tools manager; `management-http.test.ts` is partly ported here (below), and the rest are native checks.

- **Lookup.** `getToolPath` checks the bin directory first, then the system names on PATH (`fd`/`fdfind`, `rg`). A candidate counts only if it can be started with `--version`, as in upstream's `commandExists`.
- **ensureTool.** `PI_OFFLINE` values `1`, `true` or `yes` (case-insensitive) skip the download with upstream's warning. Otherwise it reports "… not found. Downloading…" and then "… installed to …" or "Failed to download …: …" through the optional status callback.
- **downloadTool:**
  1. Resolve the latest version from the `github.com/<repo>/releases/latest` redirect: manual redirects, the `pi-coding-agent` user agent, a 10 s budget, a tag taken from the last path segment and URI-decoded, and a leading `v` removed.
  2. Download `https://github.com/<repo>/releases/download/<tag>/<asset>` into the bin directory: redirects followed, a 120 s budget covering the body, and the body streamed to the file.
  3. Extract it with the system `tar xzf` into `extract_tmp_<binary>_<pid>_<Date.now()>_<random>`.
  4. Locate the binary: under the versioned directory, then at the root, then by depth-first search.
  5. Rename it into place and `chmod 755` it.
  6. Remove the archive and the extraction directory whatever happened, as upstream's `finally` does.
- **fetchWithRetry.** Status codes 408, 425, 429, 500, 502, 503 and 504, and transport failures, are retried at once up to two more times within the shared deadline. Up to 20 redirects are followed per attempt, and `Location` is resolved as `new URL(location, base)` would resolve it.

## Language-driven differences

- **No global fetch.** Bend has no global `fetch`, so `ToolsManager{binDir, url, fetch}` carries the agent's transport. The tools registry passes it to grep and find, in the same way bash receives the bin directory. Without a fetch (tests), a download fails with "fetch failed: no network transport".
- **Platforms.** Only Linux assets are chosen. The architecture comes from the ELF header of `/proc/self/exe` (aarch64 or x86_64, like `os.arch()` for the built binary), and the process id from `/proc/self`. Android and Windows branches are outside this POSIX port.
- **Timeouts.** `timeoutMs` is required (the budget shared by all attempts and the body). `attemptTimeoutMs` gives each attempt its own deadline under the caller's signal: the attempt timeout or what is left of the budget, whichever is shorter, measured on the monotonic clock. Only an attempt timeout that fired before the budget ran out is retried; the successful attempt's deadline covers its body, as upstream's combined signal does.
- **New primitives.** Installation needed `File.rename`, `File.chmod`, `File.unlink` and `File.link_kind` (`patches/bend-file-rename-chmod-unlink.patch`). `FS.remove` implements Node's `rmSync` semantics over them: force, recursive, and links not followed.

## Checks

`tests/tools_manager_check.py` runs 20 scenarios on native one and four workers against a local HTTP server and generated archives:
- plain, relative and absolute redirects;
- the 21-request redirect limit on each of 3 attempts;
- retried 503/429 followed by success or a final status (management-http.test.ts: "retries transient HTTP responses and returns the successful response");
- two dropped connections followed by success (management-http.test.ts: "retries a transient transport failure once");
- a first attempt hanging past `attemptTimeoutMs` and a second that answers ("retries an attempt timeout"), attempts that keep hanging until the shared budget ends, and a caller signal aborted before the call, which makes no request ("does not retry caller cancellation");
- no retry for 404;
- versioned, root and nested archive layouts;
- a missing binary and a corrupt archive (with cleanup and 0755 checks);
- bin-directory and `fdfind` lookup;
- offline mode and the missing transport.

`PI_BEND_DOWNLOAD_LIVE=1` adds a live install of the latest ripgrep from GitHub through the CLI's own HTTPS transport, verified with `rg --version`.

```sh
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=4 sh scripts/build-pure.sh tests/tools-manager.bend build/tools-manager
python3 tests/tools_manager_check.py native-1 native-4
PI_BEND_DOWNLOAD_LIVE=1 python3 tests/tools_manager_check.py native-1 native-4
```
