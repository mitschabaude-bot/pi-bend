import Base
import ../packages/ai/src/api/openai-responses-service-tier.bend as Tier
import ../packages/ai/src/types.bend as T
import ../packages/runtime/src/f64.bend as F

type Counters is Data:
  Counters{input: F.F64, output: F.F64, read: F.F64, write: F.F64, longWrite: Maybe<&2, F.F64>, reasoning: Maybe<&2, F.F64>, total: F.F64}

def counters(usage: T.Usage) -> Counters:
  match usage:
    case T.Usage{input, output, read, write, longWrite, reasoning, total, _}: Counters{input, output, read, write, longWrite, reasoning, total}

law unchanged_tier_preserves_entire_usage:
  for usage: T.Usage
  {Tier.adjusted(Tier.Unchanged{}, usage) == usage : T.Usage}

law pricing_preserves_all_token_counters:
  for adjustment: Tier.Adjustment
  for usage: T.Usage
  {counters(Tier.adjusted(adjustment, usage)) == counters(usage) : Counters}

law absent_tier_preserves_entire_usage:
  for modelId: String
  for usage: T.Usage
  {Tier.applyServiceTierPricing(modelId, None{}, usage) == usage : T.Usage}

law flex_policy_is_model_independent:
  for first: String
  for second: String
  {Tier.adjustment(first, Some{"flex"}) == Tier.adjustment(second, Some{"flex"}) : Tier.Adjustment}

law scaled_cost_total_uses_component_order:
  for factor: F.F64
  for input: F.F64
  for output: F.F64
  for read: F.F64
  for write: F.F64
  for previous: F.F64
  {Tier.scaleCosts(factor, T.UsageCost{input, output, read, write, previous}) == T.UsageCost{F.multiply(input, factor), F.multiply(output, factor), F.multiply(read, factor), F.multiply(write, factor), F.add(F.add(F.add(F.multiply(input, factor), F.multiply(output, factor)), F.multiply(read, factor)), F.multiply(write, factor))} : T.UsageCost}
