import Base
import ../laws/openai-responses-service-tier.bend as Laws
import ../packages/ai/src/api/openai-responses-service-tier.bend as Tier
import ../packages/ai/src/types.bend as T

def Laws.unchanged_tier_preserves_entire_usage(usage): {==}
def Laws.pricing_preserves_all_token_counters(adjustment, usage):
  match adjustment usage:
    case Tier.Unchanged{} _: {==}
    case Tier.Scaled{_} T.Usage{_, _, _, _, _, _, _, _}: {==}
def Laws.absent_tier_preserves_entire_usage(modelId, usage): {==}
def Laws.flex_policy_is_model_independent(first, second): {==}
def Laws.scaled_cost_total_uses_component_order(factor, input, output, read, write, previous): {==}
