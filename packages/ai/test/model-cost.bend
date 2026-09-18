import Base
import ../src/types.bend as T
import ../src/models.bend as M
import ../../runtime/src/f64.bend as F
import ../../runtime/src/u64.bend as W
import ../../runtime/src/ref.bend as Ref

# Numerical usage inputs are separate only so each case can allocate its cost
# object and explicitly own its lifetime. The tested function receives Usage.
type Counters is Data:
  Counters{input: F.F64, output: F.F64, cacheRead: F.F64, cacheWrite: F.F64, cacheWrite1h: Maybe<&2, F.F64>, reasoning: Maybe<&2, F.F64>, totalTokens: F.F64}

def usage(values: Counters, cost: Ref.Ref<T.UsageCost>) -> T.Usage:
  match values:
    case Counters{input, output, cacheRead, cacheWrite, longWrite, reasoning, total}: T.Usage{input, output, cacheRead, cacheWrite, longWrite, reasoning, total, cost}

def model(cost: T.ModelCost) -> T.Model<Unit>:
  T.Model{"gpt-5.6-sol", "gpt-5.6-sol", T.CustomModelApi{"test-api"}, "openai", "https://example.test/v1", False{}, None{}, T.InputText{} <> Nil{}, cost, F.fromU32(10000), F.fromU32(1000), None{}, None{}, None{}}

def nan(value: F.Decoded) -> Bool:
  match value:
    case F.NotANumber{}: True{}
    case _: False{}

def sameNumber(+left: F.F64, +right: F.F64) -> Bool:
  W.equal(F.toBits(left), F.toBits(right)) || (nan(F.decode(left)) && nan(F.decode(right)))

def sameCost(left: T.UsageCost, right: T.UsageCost) -> Bool:
  match left right:
    case T.UsageCost{a, b, c, d, e} T.UsageCost{v, w, x, y, z}: sameNumber(a, v) && sameNumber(b, w) && sameNumber(c, x) && sameNumber(d, y) && sameNumber(e, z)

def assertion(ok: Bool, label: String) -> IO(Unit):
  Bool.pick(IO(Unit), ok, IO.pure(Unit, Unit{}), IO.die(Unit, 1, label))

def marker() -> T.UsageCost:
  T.UsageCost{F.fromU32(11), F.fromU32(22), F.fromU32(33), F.fromU32(44), F.fromU32(55)}

def check(rates: T.ModelCost, counters: Counters, +expected: T.UsageCost, +label: String) -> IO(Unit):
  do IO<Unit>:
    +original : Ref.Ref<T.UsageCost> <- Ref.new(T.UsageCost, marker())
    +returned : Ref.Ref<T.UsageCost> <- M.calculateCost(Unit, model(rates), usage(counters, original))
    value : T.UsageCost <- Ref.read(T.UsageCost, returned)
    assertion(sameCost(value, expected), label ++ " returned cost")
    value : T.UsageCost <- Ref.read(T.UsageCost, original)
    assertion(sameCost(value, expected), label ++ " existing cost mutation")
    Ref.write(T.UsageCost, returned, marker())
    value : T.UsageCost <- Ref.read(T.UsageCost, original)
    assertion(sameCost(value, marker()), label ++ " returned object identity")
    previous : T.UsageCost <- Ref.dispose(T.UsageCost, original)
    return Unit{}

def checkCharges(actual: T.UsageCost, input: F.F64, output: F.F64, read: F.F64, write: F.F64) -> IO(Unit):
  match actual:
    case T.UsageCost{a, b, c, d, _}: assertion(sameNumber(a, input) && sameNumber(b, output) && sameNumber(c, read) && sameNumber(d, write), "request-wide tier charges differ")

# Original models-runtime.test.ts pricing-tier case, retaining every assertion.
def main() -> IO(Unit):
  do IO<Unit>:
    +zero : F.F64 = F.fromU32(0)
    +rates : T.ModelCost = T.ModelCost{F.fromU32(5), F.fromU32(30), F.fromBits(1071644672, 0), F.fromBits(1075380224, 0), Some{T.ModelCostTier{F.fromU32(10), F.fromU32(45), F.fromU32(1), F.fromBits(1076428800, 0), F.fromU32(272000)} <> Nil{}}}
    +shortOriginal : Ref.Ref<T.UsageCost> <- Ref.new(T.UsageCost, T.UsageCost{zero, zero, zero, zero, zero})
    short : Ref.Ref<T.UsageCost> <- M.calculateCost(Unit, model(rates), T.Usage{F.fromU32(200000), F.fromU32(100000), F.fromU32(72000), zero, None{}, None{}, F.fromU32(372000), shortOriginal})
    shortValue : T.UsageCost <- Ref.read(T.UsageCost, short)
    checkCharges(shortValue, F.fromU32(1), F.fromU32(3), F.fromBits(1067609751, 2370821947), zero)
    +longOriginal : Ref.Ref<T.UsageCost> <- Ref.new(T.UsageCost, T.UsageCost{zero, zero, zero, zero, zero})
    long : Ref.Ref<T.UsageCost> <- M.calculateCost(Unit, model(rates), T.Usage{F.fromU32(200000), F.fromU32(100000), F.fromU32(72000), F.fromU32(1), None{}, None{}, F.fromU32(372001), longOriginal})
    longValue : T.UsageCost <- Ref.read(T.UsageCost, long)
    checkCharges(longValue, F.fromU32(2), F.fromBits(1074921472, 0), F.fromBits(1068658327, 2370821947), F.fromBits(1055536866, 3944497965))
    previous : T.UsageCost <- Ref.dispose(T.UsageCost, shortOriginal)
    previous : T.UsageCost <- Ref.dispose(T.UsageCost, longOriginal)
    IO.print("PASS applies request-wide pricing tiers above the configured input threshold")
