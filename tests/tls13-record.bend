import Base
import ../packages/runtime/src/aes128.bend as AES
import ../packages/runtime/src/aes128-gcm.bend as GCM
import ../packages/runtime/src/tls13-record.bend as TLS
import ../packages/runtime/src/u64.bend as Word
import ../packages/runtime/src/string.bend as Split
import ../packages/runtime/test/utf8-runner.bend as Decimal
import ./aes128-gcm.bend as Bytes

def error(value: TLS.Error) -> String:
  match value:
    case TLS.InvalidByte{}: "byte"
    case TLS.RecordOverflow{}: "overflow"
    case TLS.UnexpectedMessage{}: "unexpected"
    case TLS.BadRecordMac{}: "mac"
    case TLS.Truncated{}: "truncated"
    case TLS.SequenceExhausted{}: "exhausted"

def sequence(value: Maybe<&2, Word.U64>) -> String:
  match value:
    case None{}: "exhausted"
    case Some{Word.U64{high, low}}: U32.show(high) ++ "," ++ U32.show(low)

def sent(result: Result<&2, &1, TLS.Error, TLS.Sent>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{TLS.Sent{TLS.Traffic{_, _, count}, record}}: sequence(count) ++ "|" ++ Bytes.show(record)

def received(result: Result<&2, &1, TLS.Error, TLS.Received>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{TLS.Received{TLS.Traffic{_, _, count}, TLS.Content{kind, bytes}, rest}}:
      sequence(count) ++ "|" ++ U32.show(TLS.code(kind)) ++ "|" ++ String.reverse.go(String.reverse(Bytes.show(bytes)), "|" ++ Bytes.show(rest))

def kind(code: U32) -> TLS.ContentType:
  match code:
    case 21: TLS.Alert{}
    case 22: TLS.Handshake{}
    case _: TLS.Application{}

def send(traffic: TLS.Traffic, contentType: String, padding: String, bytes: String) -> String:
  sent(TLS.send(traffic, TLS.Content{kind(Decimal.decimal(contentType, 0)), Bytes.bytes(bytes)}, U32.to_nat(Decimal.decimal(padding, 0))))

def second(first: List<&2, U32>, result: Result<&2, &1, TLS.Error, TLS.Sent>) -> String:
  String.reverse.go(String.reverse(Bytes.show(first)), "|" ++ sent(result))

def first(bytes: List<&2, U32>, result: Result<&2, &1, TLS.Error, TLS.Sent>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{TLS.Sent{traffic, record}}: second(record, TLS.send(traffic, TLS.Content{TLS.Application{}, bytes}, 0n))

def receiveAgain(result: Result<&2, &1, TLS.Error, TLS.Received>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{TLS.Received{traffic, _, rest}}: received(TLS.receive(traffic, rest))

def request(traffic: TLS.Traffic, fields: List<&2, String>) -> String:
  match fields:
    case "s" <> contentType <> padding <> bytes <> Nil{}: send(traffic, contentType, padding, bytes)
    case "r" <> wire <> Nil{}: receiveAgain(TLS.receive(traffic, Bytes.bytes(wire)))
    case "o" <> wire <> Nil{}: received(TLS.receive(traffic, Bytes.bytes(wire)))
    case "c" <> bytes <> Nil{}:
      +data = Bytes.bytes(bytes)
      first(data, TLS.send(traffic, TLS.Content{TLS.Application{}, data}, 0n))
    case _: "invalid"

def run(key: Maybe<&2, AES.Block>, iv: Maybe<&2, GCM.Nonce>, high: String, low: String, fields: List<&2, String>) -> String:
  match key iv:
    case Some{key} Some{iv}: request(TLS.Traffic{GCM.key(key), iv, Some{Word.U64{Decimal.decimal(high, 0), Decimal.decimal(low, 0)}}}, fields)
    case _ _: "invalid"

def parse(parts: List<&2, String>) -> String:
  match parts:
    case key <> iv <> high <> low <> fields: run(AES.fromBytes(Bytes.bytes(key)), Bytes.parseNonce(iv), high, low, fields)
    case _: "invalid"

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(parse(Split.split(head, ':')))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
