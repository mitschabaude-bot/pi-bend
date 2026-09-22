import Base
import ../packages/runtime/src/random.bend as Index
import ../packages/runtime/src/string.bend as Split
import ./dns-server-rotation.bend as Test

def parsed(text: String, fail: Bool) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  match fail:
    case True{}: Fail{(11, "unavailable")}
    case False{}: Done{Test.numbers(Split.split(text, ','), Nil{})}

def rendered(result: Result<&2, &2, Index.Error, U32>) -> String:
  match result:
    case Done{value}: U32.show(value)
    case Fail{Index.SourceFailure{code, message}}: "error:" ++ U32.show(code) ++ ":" ++ message
    case Fail{Index.InvalidBytes{}}: "bytes"
    case Fail{Index.InvalidBound{}}: "bound"

def args(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case +text <> rest:
      do IO<Unit>:
        IO.print(rendered(Index.decoded(parsed(text, String.eq(text, "error")))))
        args(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
