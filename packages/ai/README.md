# pi-ai library port

Reference: `packages/ai` in pi-mono revision `46c9de402`. This is a partial library port. It is not wired into the bootstrap executable.

`src/types.bend` currently contains the complete field sets for `TextContent`, `ThinkingContent`, `ImageContent`, `Usage`, `ModelCostRates`, `ModelCostTier` and `ModelCost`, plus all `StopReason` variants. Their source names and field names are preserved. `UsageCost` names the anonymous upstream `Usage.cost` record. Content constructors encode the literal type discriminator; serializers must emit the original string tags. Optional fields use `Maybe` so an absent breakdown remains distinct from a reported zero, and absent redaction remains distinct from false. Numeric fields use the pure-Bend binary64 type.

The remainder of `types.ts`, schema-dependent generic relationships, the full model interface, messages, stream protocols, providers and library entry points remain unported. No provider implementation or core-type completion is implied by these initial records. In particular, `calculateCost` still needs its original model input, mutation/return semantics and upstream tests; an alternate helper taking only rates would not complete that API.
