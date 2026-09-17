# Upstream test parity

The behavioral target is the pinned pi-mono revision recorded in `upstream-inventory.json`. Port the upstream assertions, fixtures, failure cases and regression scenarios with each component. Additional local smoke tests and successful live model calls do not establish parity.

The inventory includes every discovered upstream test/spec source, including packages whose applicability still needs review. `pending` means unported, `partial` means some assertions have native equivalents, and `ported` requires every applicable assertion to pass. A suite may be excluded only with a written scope reason. JavaScript extension loading is excluded by the user's request, but extension hooks, lifecycle and behavior remain requirements for Bend extensions.

Check the pinned source and inventory with `python3 scripts/test-inventory.py`. Changes to upstream source hashes require review. Never change expectations solely to make the Bend implementation pass.

`truncate_differential.py` compares native results with upstream code through a test-only TypeScript oracle. This is supplemental coverage, not a substitute for porting the named upstream tests. Production code does not import or execute TypeScript.

The truncation suite exposed isolated UTF-16 surrogate handling, which is now preserved by JSON and replaced with U+FFFD when a partial UTF-8 tail is decoded. All nine upstream truncation tests have native equivalents, including the exhaustive and seeded fuzz cases. The grep line helper counts UTF-16 units. Terminal tests still require a virtual-terminal harness and native editor/rendering implementation; API-specific Unicode sanitization remains a separate provider requirement.

The five generic event-stream cases are ported in `packages/ai/test/event-stream.bend`, retaining their names and assertions. `sh tests/event-stream.sh` runs them on one and four runtime threads, alongside four supplementary lifecycle/shared-identity regressions. Exact integer fixtures use U32 as the generic event type, and the string-result fixture remains a separate instantiation. This test suite does not cover all async-generator protocol methods or JavaScript scheduler behavior; those module gaps remain explicit in `packages/ai/README.md`.
