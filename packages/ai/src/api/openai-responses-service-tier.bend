import Base
import ../types.bend as T
import ./openai-responses-stream-pricing.bend as Pricing
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/callback.bend as C

# Pinned provider policy from openai-responses.ts. An unchanged tier preserves
# the original usage, including its total; scaling recomputes the cost total.
type Adjustment is Data:
  Unchanged{}
  Scaled{factor: F.F64}

def adjustment(modelId: String, serviceTier: Maybe<&2, String>) -> Adjustment:
  match serviceTier:
    case Some{"flex"}: Scaled{F.fromBits(1071644672, 0)}
    case Some{"priority"}: Scaled{Bool.pick(F.F64, String.eq(modelId, "gpt-5.5"), F.fromBits(1074003968, 0), F.fromU32(2))}
    case _: Unchanged{}

def scaleCosts(+factor: F.F64, costs: T.UsageCost) -> T.UsageCost:
  match costs:
    case T.UsageCost{input, output, read, write, _}:
      +input = F.multiply(input, factor)
      +output = F.multiply(output, factor)
      +read = F.multiply(read, factor)
      +write = F.multiply(write, factor)
      T.UsageCost{input, output, read, write, F.add(F.add(F.add(input, output), read), write)}

def adjusted(value: Adjustment, usage: T.Usage) -> T.Usage:
  match value usage:
    case Unchanged{} original: original
    case Scaled{factor} T.Usage{input, output, read, write, longWrite, reasoning, total, costs}:
      T.Usage{input, output, read, write, longWrite, reasoning, total, scaleCosts(factor, costs)}

# Immutable replacement for the upstream in-place cost update. Token counts,
# optional counters and their total are independent of the pricing tier.
def applyServiceTierPricing(modelId: String, serviceTier: Maybe<&2, String>, usage: T.Usage) -> T.Usage:
  adjusted(adjustment(modelId, serviceTier), usage)

def invoke(~E: Data, modelId: String, request: Pricing.PricingRequest) -> IO(Result<&2, &2, E, T.Usage>):
  match request:
    case Pricing.PricingRequest{usage, serviceTier}: IO.pure(Result<&2, &2, E, T.Usage>, Done{applyServiceTierPricing(modelId, serviceTier, usage)})

# The provider owns this callback; stream pricing borrows it through completion.
def create(~E: Data, modelId: String) -> IO(C.Callback<Pricing.PricingRequest, Result<&2, &2, E, T.Usage>>):
  C.create(~String, ~Pricing.PricingRequest, ~Result<&2, &2, E, T.Usage>, ~(invoke(~E)), modelId)
