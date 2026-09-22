import Base
import ../src/utils/provider-retry.bend as P
import ../../runtime/src/parse-float.bend as Parse
import ../../runtime/src/number-string.bend as Number
import ../../runtime/src/f64.bend as F
import ../../runtime/src/u64.bend as W
import ../../runtime/test/utf8-runner.bend as H

def bitText(value: W.U64) -> String:
  match value:
    case W.U64{hi, lo}: U32.show(hi) ++ ":" ++ U32.show(lo)

def numberText(+value: F.F64) -> String:
  Bool.pick(String, F.isNaN(value), "nan", bitText(F.toBits(value)))

def optionalText(value: String) -> Maybe<&2, String>:
  match value:
    case "-": None{}
    case other: Some{H.fromScalars(H.parseNumbers(other))}

def optionalNumber(value: String) -> Maybe<&2, F.F64>:
  match value:
    case "-": None{}
    case other: Some{Number.toNumber(other)}

def delayResult(value: Result<&2, &2, P.DelayError, F.F64>) -> String:
  match value:
    case Done{scalar}: "ok:" ++ numberText(scalar)
    case Fail{P.ServerDelayTooLong{delay, maximum}}: "limit:" ++ numberText(delay) ++ ":" ++ numberText(maximum)

def sourceResult(source: P.DelaySource, maximum: Maybe<&2, F.F64>, index: Nat, random: F.F64) -> String:
  match source:
    case P.Backoff{}: "backoff:" ++ numberText(P.backoffDelay(index, random))
    case P.ServerMilliseconds{value}: delayResult(P.validateServerRetryDelayMs(value, maximum))
    case P.ServerDate{text}: "date:" ++ H.showText(text)

def check(actual: String, expected: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(actual, expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "retry policy mismatch"))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case "p" <> value <> expected <> Nil{}: check(numberText(Parse.parseFloat(H.fromScalars(H.parseNumbers(value)))), expected)
    case "d" <> epoch <> now <> maximum <> expected <> Nil{}: check(delayResult(P.resolveServerDate(Number.toNumber(epoch), Number.toNumber(now), optionalNumber(maximum))), expected)
    case "r" <> status <> shouldRetry <> ms <> seconds <> maximum <> index <> random <> expected <> Nil{}:
      actual = Bool.pick(String, P.isRetryableProviderError(optionalNumber(status), optionalText(shouldRetry)), "1", "0") ++ "|" ++ sourceResult(P.selectDelaySource(optionalText(ms), optionalText(seconds)), optionalNumber(maximum), U32.to_nat(H.decimal(index, 0)), Number.toNumber(random))
      check(actual, expected)
    case _: IO.die(Unit, 1, "invalid retry fixture")

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.print("PASS retry policy")
    case head <> rest:
      do IO<Unit>:
        run(String.split(head, ';'))
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
