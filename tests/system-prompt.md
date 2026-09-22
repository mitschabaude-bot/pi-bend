# Native system prompt construction

`core/system-prompt.bend` ports the pinned `46c9de402` pure APIs: `BuildSystemPromptOptions`, `NormalizedBuildSystemPromptOptions`, `SystemPromptSections`, `SystemPromptState`, normalization, ordered section construction, state construction, complete text rendering, and section diffs. `systemMessage` converts that state into the existing typed AI system message. `DocumentationPaths{readme,docs,examples}` is an explicit build argument; CLI configuration supplies these paths. `defaults(cwd)` constructs absent optional inputs. No filesystem access or hidden configuration lookup occurs here.

`core/skills.bend` contains the shared typed `Skill` and `SourceInfo` data and exact `formatSkillsForPrompt` behavior, including XML escaping, disabled-skill filtering, list order, and read/bash instructions. Its `FileReadTool` argument is explicit; `Read{}` is the upstream default. Discovery, frontmatter parsing, loading, diagnostics, package metadata conversion and source-info factory helpers remain pending. SDK/session prompt-update integration, extension hooks, and tool snippet declarations are not claimed by these pure tests.

The test-only reference harness executes the actual pinned source and all 16 cases in `system-prompt.test.ts`, the two pure section/state tests in `system-prompt-updates.test.ts`, and all seven `formatSkillsForPrompt` cases in `skills.test.ts`. It collects complete outputs while running their original assertions. Supplemental cases cover exact section insertion/override order, forced empty prompt precedence over invalid sections, nullable previous values and deletions, deduplicated guidelines, whitespace, Windows cwd conversion, skill priority, escaping, and invalid section names. In total, 25 named cases and 171 complete output comparisons pass on Bun and optimized native one/four workers, including actual rendering of a 157,500-byte project context.

Values are immutable; upstream defensive cloning becomes ordinary value semantics. Invalid section names return `InvalidSectionName{name}` instead of throwing. Section-name validation rejects a trailing newline that JavaScript's `$` regex anchor accidentally accepts; this follows the user's approved strict malformed-input policy and changes no pinned named assertion. Custom context-file path/content strings retain upstream's literal rendering, including its lack of XML escaping. Skill text is XML-escaped as upstream specifies.

Reproduce from the repository root (compiler path may point to another installed equivalent):

```sh
BEND=/home/agent/code/pi-bend/build/bend-native-toolchain/bend2/main.ts
"$BEND" tests/system-prompt.bend -o build/system-prompt.js
BEND="$BEND" sh scripts/build-pure.sh tests/system-prompt.bend build/system-prompt
python3 tests/system_prompt_check.py -- bun build/system-prompt.js
python3 tests/system_prompt_check.py -- build/system-prompt --threads 1
python3 tests/system_prompt_check.py -- build/system-prompt --threads 4
```

The large-context path prints the real rendered prompt directly and compares every character, avoiding command-line argument limits and keeping prompt construction independent of JSON test transport. This case also exposed an existing non-tail JSON string-escaping stack overflow when serialized on Bun; that library fix and its independent validation are tracked separately.
