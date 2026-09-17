import Base
import ../../runtime/src/f64.bend as Number

# Source: pi-mono packages/ai/src/types.ts, revision 46c9de402.
# This module is a partial port: the records below are complete, while Model,
# messages, stream options/events and schema-dependent tool types remain open.
# JavaScript number fields use binary64; optional fields use Maybe.

type TextContent is Data:
  TextContent{text: String, textSignature: Maybe<&2, String>}

type ThinkingContent is Data:
  ThinkingContent{thinking: String, thinkingSignature: Maybe<&2, String>, redacted: Maybe<&2, Bool>}

type ImageContent is Data:
  ImageContent{data: String, mimeType: String}

# The content constructors supply the upstream literal "type" discriminator.
# UsageCost names the anonymous record declared as Usage.cost upstream.
type UsageCost is Data:
  UsageCost{input: Number.F64, output: Number.F64, cacheRead: Number.F64, cacheWrite: Number.F64, total: Number.F64}

type Usage is Data:
  Usage{input: Number.F64, output: Number.F64, cacheRead: Number.F64, cacheWrite: Number.F64, cacheWrite1h: Maybe<&2, Number.F64>, reasoning: Maybe<&2, Number.F64>, totalTokens: Number.F64, cost: UsageCost}

type StopReason is Data:
  Pending{}
  Stop{}
  Length{}
  ToolUse{}
  Error{}
  Aborted{}
  Deferred{}

type ModelCostRates is Data:
  ModelCostRates{input: Number.F64, output: Number.F64, cacheRead: Number.F64, cacheWrite: Number.F64}

# TypeScript interface extension is flattened without changing field names.
type ModelCostTier is Data:
  ModelCostTier{input: Number.F64, output: Number.F64, cacheRead: Number.F64, cacheWrite: Number.F64, inputTokensAbove: Number.F64}

type ModelCost is Data:
  ModelCost{input: Number.F64, output: Number.F64, cacheRead: Number.F64, cacheWrite: Number.F64, tiers: Maybe<&2, List<&2, ModelCostTier>>}
