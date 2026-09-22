import Base
import ../packages/runtime/src/tls13-client.bend as C
import ../packages/runtime/src/tls13-handshake.bend as H
import ../packages/runtime/src/tls13-record.bend as R
import ../packages/runtime/src/x509.bend as X
import ../packages/runtime/src/string.bend as Split
import ./aes128-gcm.bend as Bytes
import ./tls13-handshake.bend as HandshakeTest

# Test-only authorization: an exact, explicitly supplied leaf certificate pin.
# Production callers supply their own trust-path and identity validation.
def pin(expected: List<&2, U32>, certificates: List<&2, X.Certificate>) -> Result<&2, &2, X.Error, X.PublicKey>:
  match certificates:
    case +leaf <> _:
      Result.bind(&2, &2, X.Error, X.Certificate, X.PublicKey, X.parse(expected), cert =>
        Result.bind(&2, &2, X.Error, Unit, X.PublicKey,
          Bool.pick(Result<&2, &2, X.Error, Unit>, X.sameCertificate(leaf, cert), Done{Unit{}}, Fail{X.NoTrustedPath{}}), unused => X.publicKey(leaf)))
    case _: Fail{X.NoTrustedPath{}}

def state(client: C.Client) -> String:
  match client:
    case C.Client{C.Hello{_, _}, _, _, _}: "hello"
    case C.Client{C.Authenticating{_, C.Extensions{_}}, _, _, _}: "extensions"
    case C.Client{C.Authenticating{_, C.Certificate{_, _}}, _, _, _}: "certificate"
    case C.Client{C.Authenticating{_, C.Verify{_, _}}, _, _, _}: "verify"
    case C.Client{C.Authenticating{_, C.Finished{_}}, _, _, _}: "finished"
    case C.Client{C.Connected{None{}, None{}, _, _, _}, _, _, _}: "closed"
    case C.Client{C.Connected{None{}, Some{_}, _, _, _}, _, _, _}: "write-closed"
    case C.Client{C.Connected{Some{_}, None{}, _, _, _}, _, _, _}: "read-closed"
    case C.Client{C.Connected{Some{_}, Some{_}, _, _, _}, _, _, _}: "connected"

def renderError(cause: C.Error) -> String:
  match cause:
    case C.HandshakeFailure{cause}: "handshake:" ++ HandshakeTest.error(cause)
    case C.RecordFailure{R.BadRecordMac{}}: "record:mac"
    case C.RecordFailure{_}: "record"
    case C.FramingFailure{_}: "framing"
    case C.UnexpectedMessage{}: "unexpected"
    case C.PeerAlert{description}: "alert:" ++ U32.show(description)

def outputs(+prefix: String, records: List<&2, List<&2, U32>>) -> IO(Unit):
  match records:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(prefix ++ Bytes.show(head))
        outputs(prefix, rest)

def operation(client: C.Client, text: String) -> C.Reception:
  match text:
    case SCon{'r', body}: C.receive(client, Bytes.bytes(body))
    case SCon{'s', body}: C.finishInput(Nil{}, Nil{}, C.send(client, Bytes.bytes(body)))
    case SCon{'c', SNil{}}: C.finishInput(Nil{}, Nil{}, C.close(client))
    case SCon{'u', body}: C.finishInput(Nil{}, Nil{}, C.update(client, String.eq(body, "1")))
    case _: C.Reception{Fail{C.UnexpectedMessage{}}, Nil{}, Nil{}}

def commands(parts: List<&2, String>, result: C.Reception) -> IO(Unit):
  match parts result:
    case _ C.Reception{Fail{cause}, outgoing, incoming}:
      do IO<Unit>:
        outputs("out:", outgoing)
        outputs("in:", incoming)
        IO.print("error:" ++ renderError(cause))
    case Nil{} C.Reception{Done{client}, outgoing, incoming}:
      do IO<Unit>:
        outputs("out:", outgoing)
        outputs("in:", incoming)
        IO.print("state:" ++ state(client))
    case head <> rest C.Reception{Done{client}, outgoing, incoming}:
      do IO<Unit>:
        outputs("out:", outgoing)
        outputs("in:", incoming)
        commands(rest, operation(client, head))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case seed <> certificate <> rest:
      commands(rest, C.finishInput(Nil{}, Nil{}, C.initialize(Some{"localhost"}, Bytes.bytes(seed), C.Authorization{chain => pin(Bytes.bytes(certificate), chain)}, 1048576)))
    case _: IO.print("arguments")

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
