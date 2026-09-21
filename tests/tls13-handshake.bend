import Base
import ../packages/runtime/src/tls13-handshake.bend as TLS
import ../packages/runtime/src/string-split.bend as Split
import ../packages/runtime/test/utf8-runner.bend as Decimal
import ./aes128-gcm.bend as Bytes

def name(text: String) -> Maybe<&2, String>:
  match text:
    case "-": None{}
    case text: Some{text}

def render(result: Result<&2, &1, TLS.Error, TLS.Started>) -> String:
  match result:
    case Fail{TLS.EntropyFailure{code, _}}: "entropy:" ++ U32.show(code)
    case Fail{TLS.InvalidRandomness{}}: "randomness"
    case Fail{TLS.InvalidServerName{}}: "name"
    case Fail{TLS.KeyExchange{_}}: "key"
    case Done{TLS.Started{TLS.Pending{_, _, _, hello}, record}}:
      String.reverse.go(String.reverse(Bytes.show(record)), "|" ++ Bytes.show(hello))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case "d" <> host <> seed <> Nil{}: IO.print(render(TLS.initialize(name(host), Bytes.bytes(seed))))
    case "os" <> host <> Nil{}:
      do IO<Unit>:
        started : Result<&2, &1, TLS.Error, TLS.Started> <- TLS.start(name(host))
        IO.print(render(started))
    case "e" <> code <> Nil{}: IO.print(render(TLS.fromEntropy(None{}, Fail{Tuple{Decimal.decimal(code, 0), "test source failure"}})))
    case _: IO.print("invalid")

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        run(Split.split(head, ':'))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
