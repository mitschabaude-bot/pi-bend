import Base
import ../src/dns-resolver.bend as Answer
import ../src/dns-message.bend as Message
import ../src/dns-message.bend as Name
import ../src/url-ipv4.bend as IPv4
import ../src/url-ipv6.bend as IPv6
import ../src/string-split.bend as Split
import ./utf8-runner.bend as Scalar

def numbers(parts: List<&2, String>, reversed: List<&2, U32>) -> List<&2, U32>:
  match parts:
    case Nil{}: List.reverse(&2, U32, reversed)
    case SNil{} <> rest: numbers(rest, reversed)
    case item <> rest: numbers(rest, Scalar.decimal(item, 0) <> reversed)

def csv(bytes: List<&2, U32>, acc: String) -> String:
  match bytes:
    case Nil{}: acc
    case byte <> rest: csv(rest, acc ++ U32.show(byte) ++ ",")

def encoded(result: Result<&2, &2, Name.NameErrorOfMessage, List<&2, U32>>) -> String:
  match result:
    case Fail{_}: "bad-name"
    case Done{bytes}: csv(bytes, "")

def addresses(values: List<&2, Answer.Address>, acc: String) -> String:
  match values:
    case Nil{}: acc
    case Answer.V4{IPv4.Address{word}, ttl} <> rest: addresses(rest, acc ++ "4," ++ U32.show(word) ++ "," ++ U32.show(ttl) ++ ";")
    case Answer.V6{IPv6.Address{a,b,c,d}, ttl} <> rest: addresses(rest, acc ++ "6," ++ U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d) ++ "," ++ U32.show(ttl) ++ ";")

def show(value: Result<&2, &2, Answer.Error, Answer.Selection>) -> String:
  match value:
    case Done{Answer.Selection{name, values}}: "ok:" ++ encoded(Name.encodeName(name)) ++ ":" ++ addresses(values, "")
    case Fail{Answer.InvalidName{_}}: "name"
    case Fail{Answer.InvalidRecord{_}}: "record"
    case Fail{Answer.InvalidExtension{_}}: "extension"
    case Fail{Answer.UnsupportedType{}}: "type"
    case Fail{Answer.ResponseCode{code}}: "rcode:" ++ U32.show(code)
    case Fail{Answer.AliasLoop{}}: "loop"
    case Fail{Answer.ConflictingAlias{}}: "conflict"

def parsed(kind: U32, result: Result<&2, &2, Message.Error, Message.Message>) -> String:
  match result:
    case Done{Message.Message{packet, header, Message.Question{+name, k, class} <> rest, answers, authority, extra}}: show(Answer.select(kind, name, Message.Message{packet, header, Message.Question{name, k, class} <> rest, answers, authority, extra}))
    case _: "parse"

def argument(parts: List<&2, String>) -> String:
  match parts:
    case kind <> wire <> Nil{}: parsed(Scalar.decimal(kind, 0), Message.parse(numbers(Split.split(wire, ','), Nil{})))
    case _: "bad-input"

def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(argument(Split.split(value, ':')))
        run(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
