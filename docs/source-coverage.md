# Reviewing upstream source coverage

The pinned upstream tree supplies the list of source modules. [The review records](source-coverage-reviews.json) contain only modules whose coverage someone has checked; an absent record means **unreviewed**, not missing. [The test inventory](../tests/upstream-inventory.json) separately tracks upstream test suites. Do not infer behavioral coverage from a matching filename or copy suite status into a source review.

From the repository root, list unreviewed modules in bounded output:

```bash
comm -23 \
  <(cd ../pi-mono && rg --files packages/{ai,agent,tui,coding-agent}/src -g '*.ts' -g '*.tsx' -g '!*.d.ts' | sort) \
  <(jq -r '.reviews | keys[]' docs/source-coverage-reviews.json | sort) \
  | head -40
```

List reviewed modules with work remaining:

```bash
jq -r '.reviews | to_entries[] | select(.value.state == "partial" or .value.state == "missing") | [.key, .value.state, .value.note] | @tsv' docs/source-coverage-reviews.json | head -40
```

Review one module at a time. Inspect its upstream source, public callers and relevant tests in targeted sections; inspect the Bend implementation if one exists. Record `partial`, `ported`, `missing` or `excluded` only after that review. The `note` should say what behavior exists and the specific remaining gap, or why the module is excluded. Use `ports` only when Bend targets cannot be inferred from the same relative path. Run the relevant tests or terminal/request parity scenario before claiming `ported`. Keep the test results in their existing test inventory or parity checks, not duplicated in this record.

When recording or revising a finding, calculate `source_sha256` for the reviewed upstream file and `port_sha256` for each Bend target. The latter is an empty object for `missing` or `excluded` entries with no targets. After working on a `partial` or `missing` module, rerun the relevant checks and update its state, note, targets and hashes in the **same commit** as the code. Hash updates mean “I rechecked this finding against these bytes,” not an automatic acceptance of changed code.

Run `python3 scripts/test-inventory.py` before committing. It checks the pinned upstream revision, reviewed source and Bend hashes, target existence and suite inventory. If a reviewed file changes, the check fails until its finding is revisited; newly added upstream modules appear automatically in the unreviewed query. This catches stale records, while behavioral completeness still requires human review and tests. This document describes the procedure only; live coverage state comes from the queries above.
