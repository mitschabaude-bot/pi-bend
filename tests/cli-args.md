# Typed native CLI argument parsing

`packages/coding-agent/src/cli/args.bend` ports pinned `parseArgs`, `Args`, `Mode`, `isValidThinkingLevel`, and `normalizeSessionName`. Every public option field retains its name and has a concrete optional type; messages/files are ordered string lists, thinking levels reuse the existing AI type, and output/TUI/list-models choices are algebraic values. Native extension flags retain their original boolean/string distinction in an immutable dictionary for later registration handling. No JavaScript extension bridge or generic JSON Args representation is involved.

Parsing collects typed option occurrences and constructs the large public record once. Semantic field enums distinguish string, list, repeated-list and Boolean options; there is no per-flag reconstruction of the entire record. Scalar options use the latest occurrence, repeatable options retain command-line order, and replacing an unknown flag retains its dictionary position. A step consumes the current token and optionally its following value; the original token count bounds structural recursion without unsafe definitions.

The parser preserves option aliases, last-wins project approval, comma-list trimming/filtering, repeated extensions/skills/prompts/themes, print/YAML-frontmatter consumption, optional model search, the `--` delimiter, `@` file arguments, unknown long-flag equals syntax, unknown short-option diagnostics and ordered diagnostics. Unrestricted string options still accept values beginning with `--`. Missing and false remain distinct where the public API needs them.

Approved malformed-input changes:

- Known value-taking options at end of input produce an error diagnostic instead of being misclassified as unknown extension flags (or unknown short flags). Existing `--name`, `--use-theme`, and `--tui-mode` diagnostics retain their pinned behavior.
- Invalid `--mode` values produce an error instead of disappearing silently; an earlier valid mode remains intact.
- `--mode` and `--thinking` followed by another option report a missing value and leave that option available for parsing. `--tui-mode` already behaves this way upstream. Arbitrary string-valued options retain upstream consumption, and no new built-in equals syntax is invented.
- An ordinary invalid thinking-level value retains the pinned warning and leaves any previous valid thinking level intact.

None of the 81 named `args.test.ts` cases changes its expected result. The pinned source has no `resolveExtensionFlags` export; registration/type resolution is a separate session-services responsibility. This module preserves the parser's unknownFlags forwarding contract. `printHelp`, terminal styling/configuration constants and the executable CLI wiring remain pending; parsing a flag is not a claim that the corresponding feature is already integrated.

`cli_args_reference.ts` executes all pinned named assertions, including parameterized cases, while recording every parser/normalization invocation and its complete result. `cli_args_check.py` compares the Bend fixture against those full values, then adds deterministic randomized option combinations and explicit approved-rejection checks. JSON appears only in test transport. The harness executes the real pinned source rather than maintaining a second hand-written parser oracle.

```sh
build/bend-native-toolchain/bend2/main.ts tests/cli-args.bend -o build/cli-args.js
sh scripts/build-pure.sh tests/cli-args.bend build/cli-args
python3 tests/cli_args_check.py bun native-1 native-4
```

Native runners pass explicit `--threads 1` and `--threads 4`. The focused corpus contains 81 named upstream tests, 394 complete-result comparisons and 30 approved-rejection checks per backend.

All corpus checks pass on Bun and optimized (`-O1`) native one/four workers. The production module typechecks without unsafe annotations; there are no negative laws, compiler mutations or host parser dependencies in production.
