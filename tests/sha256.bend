import Base
import ../packages/runtime/src/string-split.bend as Split
import ../packages/runtime/src/sha256.bend as SHA
import ../packages/runtime/test/utf8-runner.bend as Bytes

def chunks(parts: List<&2, String>, state: SHA.State) -> Result<&2, &2, SHA.Error, SHA.State>:
  match parts:
    case Nil{}: Done{state}
    case text <> rest:
      Result.bind(&2, &2, SHA.Error, SHA.State, SHA.State, SHA.update(Bytes.numbers(Split.split(text, ',')), state), next => chunks(rest, next))

def show(result: Result<&2, &2, SHA.Error, SHA.Digest>) -> String:
  match result:
    case Done{hash}: String.join(Bytes.showNumbers(SHA.toBytes(hash)), ",")
    case Fail{SHA.InvalidByte{value}}: "byte:" ++ U32.show(value)
    case Fail{SHA.MessageTooLong{}}: "length"
    case Fail{SHA.InvalidState{}}: "state"

def repeated(count: Nat, reversed: List<&2, U32>) -> List<&2, U32>:
  match count:
    case 0n: reversed
    case 1n+rest: repeated(rest, 97 <> reversed)

def one(text: String) -> IO(Unit):
  match text:
    case SCon{'m', SNil{}}: IO.print(show(SHA.digest(repeated(1000000n, Nil{}))))
    case value: IO.print(show(Result.bind(&2, &2, SHA.Error, SHA.State, SHA.Digest, chunks(Split.split(value, '|'), SHA.create()), SHA.finish)))

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        one(head)
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
