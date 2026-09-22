import Base
import ../src/utils/provider-retry.bend as O
import ../src/utils/provider-retry.bend as Retry
import ../../runtime/src/f64.bend as Natural
import ../../runtime/src/f64.bend as F
import ../../runtime/src/u64.bend as W
import ../../runtime/test/utf8-runner.bend as H

def bits(value: W.U64) -> String:
  match value:
    case W.U64{high, low}: U32.show(high) ++ ":" ++ U32.show(low)

def countText(value: Maybe<&2, Nat>) -> String:
  match value:
    case None{}: "none"
    case Some{number}: Nat.show(number)

def limitText(value: Maybe<&2, F.F64>) -> String:
  match value:
    case None{}: "none"
    case Some{number}: bits(F.toBits(number))

def shown(value: Result<&2, &2, O.OptionsError, Retry.ProviderRetryOptions<String>>) -> String:
  match value:
    case Fail{O.InvalidRetryCount{Natural.Unrepresentable{number}}}: "count:" ++ bits(F.toBits(number))
    case Fail{O.InvalidDelayLimit{number}}: "limit:" ++ bits(F.toBits(number))
    case Done{Retry.ProviderRetryOptions{retries, limit, _}}: "ok:" ++ countText(retries) ++ ":" ++ limitText(limit)

def optional(parts: List<&2, String>) -> Maybe<&2, F.F64>:
  match parts:
    case hi <> lo <> Nil{}: Some{F.fromBits(H.decimal(hi, 0), H.decimal(lo, 0))}
    case _: None{}

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case retries <> limit <> Nil{}: IO.print(shown(O.resolve(String, optional(String.split(retries, ';')), optional(String.split(limit, ';')), None{})))
    case _: IO.die(Unit, 1, "expected retries,limit")

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
