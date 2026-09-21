import Base
import ../packages/runtime/src/string-split.bend as Split
import ../packages/runtime/src/sha256.bend as SHA
import ../packages/runtime/src/hmac-sha256.bend as HMAC
import ../packages/runtime/test/utf8-runner.bend as Bytes

def chunks(parts: List<&2, String>, state: HMAC.State) -> Result<&2, &2, SHA.Error, HMAC.State>:
  match parts:
    case Nil{}: Done{state}
    case text <> rest:
      Result.bind(&2, &2, SHA.Error, HMAC.State, HMAC.State, HMAC.update(Bytes.numbers(Split.split(text, ',')), state), next => chunks(rest, next))

def show(result: Result<&2, &2, SHA.Error, SHA.Digest>) -> String:
  match result:
    case Done{hash}: String.join(Bytes.showNumbers(SHA.toBytes(hash)), ",")
    case Fail{SHA.InvalidByte{value}}: "byte:" ++ U32.show(value)
    case Fail{SHA.MessageTooLong{}}: "length"
    case Fail{SHA.InvalidState{}}: "state"

def request(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case key <> data <> Nil{}:
      IO.print(show(Result.bind(&2, &2, SHA.Error, HMAC.State, SHA.Digest, HMAC.create(Bytes.numbers(Split.split(key, ','))), state =>
        Result.bind(&2, &2, SHA.Error, HMAC.State, SHA.Digest, chunks(Split.split(data, '|'), state), HMAC.finish))))
    case _: IO.print("request")

def one(text: String) -> IO(Unit): request(Split.split(text, ':'))

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
