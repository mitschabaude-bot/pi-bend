import Base
import ../src/utils/provider-retry-error.bend as E
import ../src/utils/provider-retry.bend as R
import ../src/utils/provider-retry-policy.bend as P
import ../../runtime/src/f64.bend as F
import ../../runtime/src/f64-round.bend as Round
import ../../runtime/src/u64.bend as W
import ../../runtime/test/utf8-runner.bend as H

def bits(value: W.U64) -> String:
  match value:
    case W.U64{high, low}: U32.show(high) ++ ":" ++ U32.show(low)

def shown(value: Result<&2, &2, E.FormattingError, E.RenderedError>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "number formatting failed")
    case Done{E.RenderedError{name, message}}: IO.print(name ++ ":" ++ message)

def original(value: String) -> E.RenderedError: E.RenderedError{"CustomError", value}

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case "c" <> hi <> lo <> Nil{}:
      IO.print(bits(F.toBits(Round.ceil(F.fromBits(H.decimal(hi, 0), H.decimal(lo, 0))))))
    case "d" <> hi <> lo <> mh <> ml <> Nil{}:
      shown(E.delayError(P.ServerDelayTooLong{F.fromBits(H.decimal(hi, 0), H.decimal(lo, 0)), F.fromBits(H.decimal(mh, 0), H.decimal(ml, 0))}, "provider failure 🙂"))
    case "a" <> Nil{}: shown(Done{E.createAbortError()})
    case "o" <> Nil{}: shown(E.render(String, R.RequestFailed{R.Other{"original"}}, value => original(value)))
    case "p" <> Nil{}: shown(E.render(String, R.RequestFailed{R.Provider{R.ProviderError{"original", "ignored rendering", None{}, None{}, None{}, None{}}}}, value => original(value)))
    case "r" <> Nil{}: shown(E.render(String, R.RequestAborted{}, value => original(value)))
    case _: IO.die(Unit, 1, "invalid retry-error test")

def cases(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        run(String.split(value, ';'))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    cases(values)
