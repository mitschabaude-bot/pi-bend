# Native YAML frontmatter

`utils/frontmatter.bend` exposes immutable `Frontmatter{frontmatter: Record<Yaml.Value>, body: String}`, `parseFrontmatter`, and `stripFrontmatter`, returning typed `Yaml.Error` values. BOM removal, CRLF/CR normalization, missing/unterminated frontmatter fallback, body trimming, and the pinned named examples are preserved. Fences must occupy a complete `---` line: unlike the upstream prefix search, `---suffix` is not treated as a delimiter. Nonmapping frontmatter is rejected explicitly rather than being cast to an object and interpreted later. These are strict malformed-input adaptations.

`runtime/yaml.bend` provides typed null, boolean, number, text, sequence and string-keyed mapping values. The implemented grammar covers block and flow collections, nested sequence mappings, plain/single/double-quoted scalars, YAML quoted escapes, core numeric/boolean/null resolution, comments, literal/folded block scalars with indentation and chomping, and scalar/flow anchors and aliases. Duplicate keys, recursive/unknown aliases and unsupported explicit tags return errors. `core/diagnostics.bend` supplies the real shared resource diagnostic/collision model; its `kind` field replaces upstream's `type`, a Bend keyword.

This is a working frontmatter dependency, not a claim of complete `yaml@2.9.0` package parity. Remaining grammar work includes block anchors, exact multiline plain/quoted blank-line folding, explicit tags/directives, arbitrary mapping keys, richer source spans and alias expansion budgets. The parser uses explicit frames and structurally decreasing input-derived fuel, avoiding recursive machine-stack growth on nested collections. No production host parser or subprocess is used.

The reference harness evaluates the pinned `46c9de402` frontmatter source and executes all eight named `frontmatter.test.ts` cases, retaining their nine complete outputs. It also compares 226 YAML cases against pinned `yaml@2.9.0`, including nested metadata, scalar types, flow errors, multiline descriptions and block chomping. Same-indent sequence values are supported at the root and inside nested mappings/sequence entries, including empty items, comments, block scalars and the next surrounding mapping entry. Structural boundary checks also reject mapping separators inside unquoted plain scalars while preserving literal colons in URLs and nonseparating text. The invalid-flow named case retains its asserted line 1, column 10 location. Unknown metadata is preserved as typed data rather than discarded by the parser. Skill/prompt loaders decide which fields they consume.

Reproduce with a compiler containing the project's installed effects:

```sh
npm install --ignore-scripts --no-audit --no-fund --prefix build/reference yaml@2.9.0
BEND=/home/agent/code/pi-bend-directory/build/bend-native-toolchain/bend2/main.ts
"$BEND" tests/frontmatter.bend -o build/frontmatter.js
BEND="$BEND" sh scripts/build-pure.sh tests/frontmatter.bend build/frontmatter
python3 tests/frontmatter_check.py -- bun build/frontmatter.js
python3 tests/frontmatter_check.py -- build/frontmatter --threads 1
python3 tests/frontmatter_check.py -- build/frontmatter --threads 4
```

The JSON renderer in the fixture is test transport only; production YAML and loader APIs remain typed. The original source's detailed parser exception prose is not cloned; typed error locations and meaningful validation failures are tested.
