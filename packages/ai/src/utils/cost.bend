import Base
import ../types.bend as T
import ../../../runtime/src/f64.bend as F

# Preserve binary64 evaluation order from models.ts calculateCost. Tier rates
# apply to the entire request, not just tokens above the selected threshold.
def greater(result: Maybe<&2, Cmp>) -> Bool:
  match result:
    case Some{GT{}}: True{}
    case _: False{}

def chooseTier(tier: T.ModelCostTier, +inputTokens: F.F64, +matched: F.F64, rates: T.ModelCostRates) -> F.F64 & T.ModelCostRates:
  match tier:
    case T.ModelCostTier{input, output, cacheRead, cacheWrite, +threshold}:
      Bool.pick(F.F64 & T.ModelCostRates, greater(F.compare(inputTokens, threshold)) && greater(F.compare(threshold, matched)), (threshold, T.ModelCostRates{input, output, cacheRead, cacheWrite}), (matched, rates))

def tiers(remaining: List<&2, T.ModelCostTier>, +inputTokens: F.F64, state: F.F64 & T.ModelCostRates) -> T.ModelCostRates:
  match remaining state:
    case Nil{} Tuple{_, rates}: rates
    case head <> tail Tuple{matched, rates}: tiers(tail, inputTokens, chooseTier(head, inputTokens, matched, rates))

def optionalTiers(value: Maybe<&2, List<&2, T.ModelCostTier>>) -> List<&2, T.ModelCostTier>:
  match value:
    case None{}: Nil{}
    case Some{values}: values

def rates(cost: T.ModelCost, inputTokens: F.F64) -> T.ModelCostRates:
  match cost:
    case T.ModelCost{input, output, cacheRead, cacheWrite, levels}: tiers(optionalTiers(levels), inputTokens, (F.negate(F.fromU32(1)), T.ModelCostRates{input, output, cacheRead, cacheWrite}))

def optionalNumber(value: Maybe<&2, F.F64>) -> F.F64:
  match value:
    case None{}: F.fromU32(0)
    case Some{number}: number

def atRates(selected: T.ModelCostRates, input: F.F64, output: F.F64, cacheRead: F.F64, cacheWrite: F.F64, +longWrite: F.F64) -> T.UsageCost:
  match selected:
    case T.ModelCostRates{+inputRate, outputRate, readRate, writeRate}:
      +million = F.fromU32(1000000)
      shortWrite = F.subtract(cacheWrite, longWrite)
      +inputCost = F.multiply(F.divide(inputRate, million), input)
      +outputCost = F.multiply(F.divide(outputRate, million), output)
      +readCost = F.multiply(F.divide(readRate, million), cacheRead)
      +writeCost = F.divide(F.add(F.multiply(writeRate, shortWrite), F.multiply(F.multiply(inputRate, F.fromU32(2)), longWrite)), million)
      total = F.add(F.add(F.add(inputCost, outputCost), readCost), writeCost)
      T.UsageCost{inputCost, outputCost, readCost, writeCost, total}

def compute(cost: T.ModelCost, usage: T.Usage) -> T.UsageCost:
  match usage:
    case T.Usage{+input, output, +cacheRead, +cacheWrite, longWrite, _, _, _}:
      selected = rates(cost, F.add(F.add(input, cacheRead), cacheWrite))
      atRates(selected, input, output, cacheRead, cacheWrite, optionalNumber(longWrite))

def modelCost(-SamplingValue: Data, model: T.Model<SamplingValue>) -> T.ModelCost:
  match model:
    case T.Model{_, _, _, _, _, _, _, _, cost, _, _, _, _, _}: cost

# Return the computed value; the caller decides where to retain it.
def calculate(-SamplingValue: Data, model: T.Model<SamplingValue>, usage: T.Usage) -> T.UsageCost:
  compute(modelCost(SamplingValue, model), usage)
