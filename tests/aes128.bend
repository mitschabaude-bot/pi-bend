import Base
import ../packages/runtime/src/aes128.bend as AES
import ../packages/runtime/src/string.bend as Split
import ../packages/runtime/test/utf8-runner.bend as Bytes

def parse(text: String) -> Maybe<&2, AES.Block>:
  AES.fromBytes(Bytes.numbers(Split.split(text, ',')))

def show(block: AES.Block) -> String: String.join(Bytes.showNumbers(AES.toBytes(block)), ",")

def encrypt(key: Maybe<&2, AES.Block>, block: Maybe<&2, AES.Block>) -> String:
  match key block:
    case Some{key} Some{block}: show(AES.encrypt(AES.expand(key), block))
    case _ _: "invalid"

def keys(values: List<&2, AES.Block>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case head <> rest: show(head) <> keys(rest)

def schedule(key: Maybe<&2, AES.Block>) -> String:
  match key:
    case None{}: "invalid"
    case Some{+key}: String.join(keys(key <> AES.expandRounds(10n, key, 1)), "|")

def request(parts: List<&2, String>) -> String:
  match parts:
    case key <> block <> Nil{}: encrypt(parse(key), parse(block))
    case key <> Nil{}: schedule(parse(key))
    case _: "invalid"

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(request(Split.split(head, ':')))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
