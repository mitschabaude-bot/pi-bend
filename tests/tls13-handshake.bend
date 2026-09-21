import Base
import ../packages/runtime/src/tls13-handshake.bend as TLS
import ../packages/runtime/src/string-split.bend as Split
import ../packages/runtime/src/sha256.bend as SHA
import ../packages/runtime/src/tls13-record.bend as Record
import ../packages/runtime/test/utf8-runner.bend as Decimal
import ./aes128-gcm.bend as Bytes

def name(text: String) -> Maybe<&2, String>:
  match text:
    case "-": None{}
    case text: Some{text}

def error(cause: TLS.Error) -> String:
  match cause:
    case TLS.EntropyFailure{code, _}: "entropy:" ++ U32.show(code)
    case TLS.InvalidRandomness{}: "randomness"
    case TLS.InvalidServerName{}: "name"
    case TLS.KeyExchange{_}: "key"
    case TLS.MalformedServerHello{}: "malformed"
    case TLS.RejectedParameters{}: "parameters"
    case TLS.HelloRetryRequest{}: "retry"
    case TLS.Derivation{_}: "derivation"
    case TLS.InvalidKeyMaterial{}: "material"

def render(result: Result<&2, &1, TLS.Error, TLS.Started>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{TLS.Started{TLS.Pending{_, _, _, hello}, record}}:
      String.reverse.go(String.reverse(Bytes.show(record)), "|" ++ Bytes.show(hello))

def sent(result: Result<&2, &1, Record.Error, Record.Sent>) -> String:
  match result:
    case Fail{_}: "send-error"
    case Done{Record.Sent{_, wire}}: Bytes.show(wire)

def received(result: Result<&2, &1, Record.Error, Record.Received>) -> String:
  match result:
    case Fail{_}: "receive-error"
    case Done{Record.Received{_, Record.Content{kind, bytes}, _}}: U32.show(Record.code(kind)) ++ ":" ++ Bytes.show(bytes)

def negotiated(encrypted: List<&2, U32>, result: Result<&2, &1, TLS.Error, TLS.Handshake>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{TLS.Handshake{_, _, secret, client, server, write, read}}:
      Bytes.show(SHA.toBytes(secret)) ++ "|" ++ Bytes.show(client) ++ "|" ++ Bytes.show(server) ++ "|" ++
        sent(Record.send(write, Record.Content{Record.Handshake{}, 20 <> 0 <> 0 <> 0 <> Nil{}}, 0n)) ++ "|" ++ received(Record.receive(read, encrypted))

def accept(serverHello: List<&2, U32>, encrypted: List<&2, U32>, result: Result<&2, &1, TLS.Error, TLS.Started>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{TLS.Started{pending, _}}: negotiated(encrypted, TLS.acceptServerHello(pending, serverHello))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case "n" <> host <> seed <> hello <> encrypted <> Nil{}: IO.print(accept(Bytes.bytes(hello), Bytes.bytes(encrypted), TLS.initialize(name(host), Bytes.bytes(seed))))
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
