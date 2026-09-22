# Native-agent glob feature

`runtime/glob.bend` was authored through the native OpenAI/provider/agent/read-write-edit-Bash stack in an isolated worktree. It supplies a typed single-string glob compiler and matcher: Unicode scalar literals, escapes, `?`, `*`, bracket sets/ranges and `!` negation. Slash and leading dot are ordinary characters. Dangling escapes, empty/unfinished sets and reversed ranges return typed errors. This is a string-matching primitive, not a claim that filesystem globbing, minimatch or the find tool is fully ported.

The matcher remembers the latest star and advances its candidate text position on failure, avoiding exponential branching. A structural step bound of `(token count + 2) * (text length + 2)` makes recursion total; length scans and range searches are tail-recursive. Its worst-case work is quadratic in source-pattern/text size. The generic `star_matches_every_string` law proves that a single star accepts every finite string using the public matcher’s actual step budget. General matching equivalence and sufficient fuel for arbitrary patterns remain unproved; the checks below provide complementary runtime evidence.

`glob-agent.bend` contains the native agent's own self-checks and a pattern/text-pair runner. `glob_check.py` is an independently authored dynamic-programming oracle, covering 7,478 generated and boundary comparisons plus five long-input checks for literal patterns, large sets and star matching. All pass on Bun and optimized native one/four workers. The harness places arbitrary inputs after the runtime argument delimiter; Bun itself consumes one delimiter, so the hosted command supplies two.

```sh
bend proofs/glob.bend
bend tests/glob-agent.bend -o build/glob-agent.js
sh scripts/build-pure.sh tests/glob-agent.bend build/glob-agent
build/glob-agent --threads 1
build/glob-agent --threads 4
python3 tests/glob_check.py build/glob-agent.js
python3 tests/glob_check.py build/glob-agent --threads 1
python3 tests/glob_check.py build/glob-agent --threads 4
```

The native authoring run needed review feedback on ownership and tail recursion. The supervisor supplied the independent oracle and diagnostics, but did not edit the implementation. A later request failed with `request.headers.socket.os.104` (connection reset before headers); the saved feature was independently verified, and local reset injection exposed the missing TLS network retry classification now fixed in `fetch.bend`.

The final live continuation used the native four-tool host with `PI_BEND_RETRY_REQUESTS=1`, OpenAI `gpt-5.5` and the native DNS/TLS/HTTP/provider/agent stack. It exited successfully after seven model turns and ten tool executions (one read, nine Bash), rebuilt the feature and ran its self-checks plus all 7,478 oracle comparisons and five long-input checks on Bun and native one/four workers. It returned a final report without further source edits. The implementation SHA256 is `64e2f4f9e7e5b7ad988df6c56789d76e1c84a3183e44337defd758b27893cb90`; the test fixture SHA256 is `40cabd21bf9b409a2b1033a77075f138ea3901b0761f5a4e0be95a95e340798b`. This establishes a native-agent-authored, verified feature, not completion of the pi port. The raw authoring logs and credentials are not committed.
