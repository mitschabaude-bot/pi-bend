# Prompt templates

`core/prompt-templates.bend` ports the pure argument parser, substitution and expansion from pinned Pi `46c9de402`, `packages/coding-agent/src/core/prompt-templates.ts`. The loader reuses the shared native frontmatter/YAML and filesystem modules; it does not parse metadata independently.

The test-only oracle executes the original suite's pure assertions and captures all 127 calls to the three public functions. It then compares these and 436 additional calls against Bend, including positional defaults, argument slices, zero and very large indices, literal placeholder text inside replacements, Unicode whitespace, multiline commands, first matching template precedence and unknown commands. All 563 comparisons pass Bun and optimized native execution with explicit one and four workers. Eight unfinished-quote cases return typed errors. In-core 200KB literal replacement and 200KB unfinished-default inputs also pass all three backends.

Unclosed argument quotes are rejected with `UnclosedQuote`; upstream silently accepts the rest of the input. Empty quoted arguments are omitted, as the original suite explicitly requires. Backslashes remain literal; this parser is not a shell interpreter. Unrecognized placeholder syntax remains ordinary template text. Replacement values and defaults never reenter the scanner. Numeric indices saturate at one beyond the argument count, preserving out-of-range and slicing behavior without floating-point rounding or overflowing integers.

The scanner processes template text and replacement output with tail-recursive accumulators. After the first failed default scan, it remembers that no closing brace remains, avoiding quadratic rescanning of many unfinished defaults. Positional lookup and slicing traverse the argument list; joined all-argument text is computed once. This is not a claim that arbitrary repeated indexed lookups take constant time.

The loader passes seven pinned discovery scenarios comprising 65 templates on Bun and optimized native one/four workers. These include all five original `argument-hint` cases, defaults-before-explicit precedence, repeated paths, relative and file-URL inputs, symlinked files, skipped nested directories/nonfiles, BOM/newline normalization and 60-UTF16-unit descriptions. Additional checks cover explicit home/configuration input, invalid UTF-8, wrong recognized metadata types, malformed YAML and unreadable files. Source attribution preserves lexical selected paths and the global/project/temporary scopes.

Bun's `readdirSync(..., {withFileTypes:true})` returns raw OS order on this host; Node's `readdirSync` sorts via libuv. For loading comparisons, the oracle runs the unmodified pinned loader under Bun but supplies directory order from a real Node filesystem call, retaining real Dirents. Expected results are not sorted after loading. Production Bend sorts each directory by filename, then retains global/project/explicit group order and duplicate entries. The first matching name wins during expansion.

`loadPromptTemplates(environment, configDirName, options)` accepts explicit path/environment and package configuration dependencies. It returns `Result<Paths.Error, LoadResult>`; `LoadResult` contains templates and shared resource diagnostics. Bad individual files are skipped with an error diagnostic rather than silently ignored. Missing paths remain skipped. Recognized description/hint fields must be strings when present. Invalid file UTF-8 is rejected rather than replacement-decoded. At a description cutoff that would split a surrogate pair upstream, Bend retains only complete characters and adds the ellipsis. Frontmatter grammar and unsupported YAML features follow the shared parser's documented scope; this module does not imply complete parity with every feature of the npm YAML package.

The loader verification used the directory primitive candidate from `00cba19` and a temporary shared-parser snapshot (`yaml.bend` SHA256 `d798afd33bfb32611c9101749d78fd3a725357e89f159a6bdd3477a7cb56b474`, `frontmatter.bend` SHA256 `3636654097b6f068ac72a71242aa2386258807ec5119ff6e8f8337e456004804`). Those dependency files are owned by the other agents and excluded from the prompt commits. Recheck against their final integration.

Run with a toolchain containing the directory primitives and the shared parser modules present:

```sh
build/bend-native-toolchain/bend2/main.ts tests/prompt-templates.bend -o build/prompt-templates.js
sh scripts/build-pure.sh tests/prompt-templates.bend build/prompt-templates
python3 tests/prompt_templates_check.py --runner build/prompt-templates.js
python3 tests/prompt_templates_check.py --runner build/prompt-templates --threads 1
python3 tests/prompt_templates_check.py --runner build/prompt-templates --threads 4
python3 tests/prompt_templates_load_check.py --runner build/prompt-templates.js
python3 tests/prompt_templates_load_check.py --runner build/prompt-templates --threads 1
python3 tests/prompt_templates_load_check.py --runner build/prompt-templates --threads 4
```
