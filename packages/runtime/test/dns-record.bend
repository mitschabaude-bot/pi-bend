import Base
import ../src/dns-message.bend as Record
import ../src/dns-message.bend as Message
import ../src/dns-message.bend as Name
import ../src/url.bend as IPv4
import ../src/url.bend as IPv6
import ../src/string.bend as Split
import ./utf8-runner.bend as Scalar

def numbers(parts: List<&2, String>, reversed: List<&2, U32>) -> List<&2, U32>:
  match parts:
    case Nil{}: List.reverse(&2, U32, reversed)
    case SNil{} <> rest: numbers(rest, reversed)
    case item <> rest: numbers(rest, Scalar.decimal(item, 0) <> reversed)

def octets(text: String) -> List<&2, U32>:
  numbers(Split.split(text, ','), Nil{})

def showNumbers(values: List<&2, U32>) -> String:
  String.join(Scalar.showNumbers(values), ",")

def labelStrings(values: List<&2, List<&2, U32>>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case label <> rest: showNumbers(label) <> labelStrings(rest)

def showName(value: Name.Name) -> String:
  match value:
    case Name.Name{labels}: String.join(labelStrings(labels), "/")

def show(value: Result<&2, &2, Record.RecordError, Record.Value>) -> String:
  match value:
    case Fail{_}: "error"
    case Done{Record.A{IPv4.Address{a}}}: "A:" ++ U32.show(a)
    case Done{Record.AAAA{IPv6.Ipv6Address{a, b, c, d}}}: "AAAA:" ++ showNumbers(a <> b <> c <> d <> Nil{})
    case Done{Record.CNAME{target}}: "CNAME:" ++ showName(target)
    case Done{Record.NS{target}}: "NS:" ++ showName(target)
    case Done{Record.PTR{target}}: "PTR:" ++ showName(target)
    case Done{Record.SOA{primary, mailbox, serial, refresh, retry, expire, minimum}}: "SOA:" ++ showName(primary) ++ ":" ++ showName(mailbox) ++ ":" ++ showNumbers(serial <> refresh <> retry <> expire <> minimum <> Nil{})
    case Done{Record.Opaque{Message.Record{owner, kind, class, ttl, start, length}}}: "opaque:" ++ showName(owner) ++ ":" ++ showNumbers(kind <> class <> ttl <> start <> length <> Nil{})

def direct(kind: U32, class: U32, start: U32, length: U32, value: Result<&2, &2, Name.NameErrorOfMessage, Name.Packet>) -> String:
  match value:
    case Fail{_}: "packet-error"
    case Done{packet}: show(Record.decodeRecord(packet, Message.Record{Name.Name{Nil{}}, kind, class, 123, start, length}))

def arguments(parts: List<&2, String>) -> String:
  match parts:
    case kind <> class <> start <> length <> wire <> Nil{}: direct(Scalar.decimal(kind, 0), Scalar.decimal(class, 0), Scalar.decimal(start, 0), Scalar.decimal(length, 0), Name.packet(octets(wire)))
    case _: "bad test input"

def records(+packet: Name.Packet, values: List<&2, Message.Record>, reversed: List<&2, String>) -> String:
  match values:
    case Nil{}: String.join(List.reverse(&2, String, reversed), "|")
    case record <> rest: records(packet, rest, show(Record.decodeRecord(packet, record)) <> reversed)

def message(value: Result<&2, &2, Message.Error, Message.Message>) -> String:
  match value:
    case Fail{_}: "message-error"
    case Done{Message.Message{+packet, _, _, answers, authorities, additional}}: records(packet, answers, Nil{}) ++ ";" ++ records(packet, authorities, Nil{}) ++ ";" ++ records(packet, additional, Nil{})

def run(input: String) -> String:
  match input:
    case SCon{'r', text}: arguments(Split.split(text, ':'))
    case SCon{'m', text}: message(Message.parse(octets(text)))
    case _: "bad mode"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        IO.print(run(arg))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
