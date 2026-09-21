import Base
import ../src/api/openai-responses-stream-pricing.bend as Pricing
import ../../runtime/src/callback.bend as C
import ../src/api/openai-responses-service-tier.bend as Tier
import ../src/types.bend as T
import ../../runtime/src/f64.bend as F
import ../../runtime/src/u64.bend as W
import ./provider-retry-options.bend as Input

def bits(value: W.U64) -> String:
  match value:
    case W.U64{high, low}: U32.show(high) ++ ":" ++ U32.show(low)

def number(value: F.F64, decoded: F.Decoded) -> String:
  match decoded:
    case F.NotANumber{}: "nan"
    case _: bits(F.toBits(value))

def shownNumber(+value: F.F64) -> String: number(value, F.decode(value))

def shown(usage: T.Usage) -> String:
  match usage:
    case T.Usage{_, _, _, _, _, _, _, T.UsageCost{input, output, read, write, total}}:
      shownNumber(input) ++ "," ++ shownNumber(output) ++ "," ++ shownNumber(read) ++ "," ++ shownNumber(write) ++ "," ++ shownNumber(total)

def completed(value: Result<&2, &2, String, T.Usage>) -> IO(Unit):
  match value:
    case Done{usage}: IO.print(shown(usage))
    case Fail{_}: IO.die(Unit, 1, "unexpected pricing error")

def values(modelId: String, serviceTier: Maybe<&2, String>, input: Maybe<&2, F.F64>, output: Maybe<&2, F.F64>, read: Maybe<&2, F.F64>, write: Maybe<&2, F.F64>, total: Maybe<&2, F.F64>) -> IO(Unit):
  match input output read write total:
    case Some{a} Some{b} Some{c} Some{d} Some{e}:
      do IO<Unit>:
        +callback : C.Callback<Pricing.PricingRequest, Result<&2, &2, String, T.Usage>> <- Tier.create(~String, modelId)
        usage : Result<&2, &2, String, T.Usage> <- C.call(Pricing.PricingRequest, Result<&2, &2, String, T.Usage>, callback, Pricing.PricingRequest{T.Usage{F.fromU32(13), F.fromU32(17), F.fromU32(19), F.fromU32(23), Some{F.fromU32(29)}, None{}, F.fromU32(31), T.UsageCost{a, b, c, d, e}}, serviceTier})
        C.dispose(Pricing.PricingRequest, Result<&2, &2, String, T.Usage>, callback)
        completed(usage)
    case _ _ _ _ _: IO.die(Unit, 1, "expected five binary64 pairs")

def serviceTier(value: String) -> Maybe<&2, String>:
  match value:
    case "-": None{}
    case text: Some{text}

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case modelId <> tier <> input <> output <> read <> write <> total <> Nil{}:
      values(modelId, serviceTier(tier), Input.optional(String.split(input, ';')), Input.optional(String.split(output, ';')), Input.optional(String.split(read, ';')), Input.optional(String.split(write, ';')), Input.optional(String.split(total, ';')))
    case _: IO.die(Unit, 1, "expected model,tier,input,output,read,write,total")

def cases(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        run(String.split(value, ','))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    cases(values)
