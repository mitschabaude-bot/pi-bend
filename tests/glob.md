# Native-agent glob feature

`runtime/glob.bend` was authored through the native OpenAI/provider/agent/read-write-edit-Bash stack in an isolated worktree. It supplies a typed single-string glob compiler and matcher: Unicode scalar literals, escapes, `?`, `*`, bracket sets/ranges and `!` negation. Slash and leading dot are ordinary characters. Dangling escapes, empty/unfinished sets and reversed ranges return typed errors. This is a string-matching primitive, not a claim that filesystem globbing, minimatch or the find tool is fully ported.

The matcher remembers the latest star and advances its candidate text position on failure, avoiding exponential branching. A structural step bound of `(token count + 2) * (text length + 2)` makes recursion total; length scans and range searches are tail-recursive. Its worst-case work is quadratic in source-pattern/text size. General matching equivalence and the step bound have not been machine-proved; the checks below are runtime evidence.

`glob-agent.bend` contains the native agent's own self-checks and a pattern/text-pair runner. `glob_check.py` is an independently authored dynamic-programming oracle, covering 7,478 generated and boundary comparisons plus five long-input checks for literal patterns, large sets and star matching. All pass on Bun and optimized native one/four workers. The harness places arbitrary inputs after the runtime argument delimiter; Bun itself consumes one delimiter, so the hosted command supplies two.

```sh
bend tests/glob-agent.bend -o build/glob-agent.js
sh scripts/build-pure.sh tests/glob-agent.bend build/glob-agent
build/glob-agent --threads 1
build/glob-agent --threads 4
python3 tests/glob_check.py build/glob-agent.js
python3 tests/glob_check.py build/glob-agent --threads 1
python3 tests/glob_check.py build/glob-agent --threads 4
```

The native authoring run needed review feedback on ownership and tail recursion. The supervisor supplied the independent oracle and diagnostics, but did not edit the implementation. A later request failed with `request.headers.socket.os.104` (connection reset before headers); implementation and self-checks were already saved and were independently verified. That transport failure is not recorded as a successful final agent response, nor does this feature establish completion of the pi port.
