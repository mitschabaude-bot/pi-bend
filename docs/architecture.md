# Architecture contract

Pi-bend ports pi's modular programming model into native Bend. This page states design requirements, not implementation progress. The upstream revision under review is recorded in the checked [test inventory](../tests/upstream-inventory.json) and [source reviews](source-coverage-reviews.json); this page does not duplicate it.

## Package boundaries

| Package | Responsibility |
| --- | --- |
| `ai` | Typed messages, content, usage, models, provider adapters, credentials, transcript normalization and streaming contracts |
| `agent` | Agent state and loop, tool preparation and execution, hooks, event ordering, queues, cancellation and settlement |
| `agent/harness` | Execution environments, resources, tools, sessions, compaction and conformance interfaces where applicable to the pinned upstream API |
| `tui` | Terminal input, editor, reusable components, layout and rendering |
| `coding-agent` | Session orchestration, settings, resources, tools, print/JSON/RPC/interactive modes and extensions |

Preserve each package's meaningful public types, names and call contracts. Supporting upstream packages and dependencies must be assessed through their actual use by these libraries. A CLI demonstration or a matching file path does not establish library parity.

## Native representation

Use Bend records and algebraic data types for messages, schemas, tools, contexts and events. Model optional fields explicitly, including the distinction between absence and `null` where it affects behavior. Keep JSON at serialization boundaries and at fields whose contract is arbitrary JSON. Ordinary state transitions return new values; effectful synchronization is reserved for concurrent work and resource ownership.

Preserve meaningful behavior without recreating JavaScript reflection, prototypes, sparse arrays or incidental reference identity. Tool declarations compare structurally and emitted events are immutable snapshots. [Native semantics](native-bend.md) records the reviewed language-driven differences.

## Effects and dependencies

Implement protocol, parsing, cryptographic and Unicode logic in Bend, with small operating-system effects underneath. Keep transports, clocks, filesystem access and other effects injectable where the upstream library exposes them. Define cancellation, errors, callback ordering, backpressure and resource lifetime at those interfaces; verify both pure behavior and effectful composition. Missing Bend primitives are implementation work, while compiler/runtime defects belong in the [Bend issue record](bend-issues.md).

## Completion evidence

For a module, review its upstream source and public contract, identify the Bend targets, validate relevant upstream assertions and integration behavior, then update the [source review record](source-coverage-reviews.json) and [test inventory](../tests/upstream-inventory.json). The [review procedure](source-coverage.md) describes that step. Terminal and request parity checks cover behaviors that isolated module tests cannot establish. These checked records carry live coverage; this architecture page does not list completed or pending modules.
