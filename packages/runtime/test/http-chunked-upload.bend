import Base
import ../src/http-message.bend as Upload
import ../src/http-message.bend as Body
import ../src/http-message.bend as Headers
import ../src/big-nat.bend as N
import ./utf8-runner.bend as Text

def zeros(count: Nat) -> List<&2, U32>:
  match count:
    case Zero{}: Nil{}
    case Succ{rest}: 0 <> zeros(rest)

def hexadecimal(value: Maybe<&2, N.BigNat>) -> String:
  match value:
    case None{}: "error"
    case Some{length}: Text.fromScalars(Upload.hexadecimal(length))

def show(value: Result<&2, &2, Body.BufferedBodyBodyError, Body.Prepared>) -> String:
  match value:
    case Done{Body.Prepared{_, _, Some{content}}}: String.join(Text.showNumbers(Upload.encode(content)), ",")
    case _: "error"

def run(argument: String) -> String:
  match argument:
    case SCon{Chr{104}, value}: hexadecimal(N.fromDecimal(value))
    case SCon{Chr{122}, value}: show(Body.prepare("POST", Headers.new(), Body.Bytes{zeros(U32.to_nat(Text.decimal(value, 0)))}))
    case SCon{Chr{98}, value}: show(Body.prepare("POST", Headers.new(), Body.Bytes{Text.parseNumbers(value)}))
    case _: "bad-fixture"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        IO.print(run(first))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
