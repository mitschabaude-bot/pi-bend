import Base
import ../src/dns-message.bend as DNS
import ../src/string.bend as Split
import ./utf8-runner.bend as Scalar

def numbers(parts: List<&2, String>, reversed: List<&2, U32>) -> List<&2, U32>:
  match parts:
    case Nil{}: List.reverse(&2, U32, reversed)
    case SNil{} <> rest: numbers(rest, reversed)
    case item <> rest: numbers(rest, Scalar.decimal(item, 0) <> reversed)

def bytes(text: String) -> List<&2, U32>:
  numbers(Split.split(text, ','), Nil{})

def labels(parts: List<&2, String>, reversed: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match parts:
    case Nil{}: List.reverse(&2, List<&2, U32>, reversed)
    case label <> rest: labels(rest, bytes(label) <> reversed)

def name(text: String) -> DNS.Name:
  match text:
    case SNil{}: DNS.Name{Nil{}}
    case other: DNS.Name{labels(Split.split(other, '/'), Nil{})}

def showBytes(values: List<&2, U32>) -> String:
  String.join(Scalar.showNumbers(values), ",")

def showLabels(values: List<&2, List<&2, U32>>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case label <> rest: showBytes(label) <> showLabels(rest)

def error(value: DNS.DomainNameError) -> String:
  match value:
    case DNS.NameInvalidByte{}: "InvalidByte"
    case DNS.InvalidLabel{}: "InvalidLabel"
    case DNS.NameTooLong{}: "NameTooLong"
    case DNS.PacketTooLong{}: "PacketTooLong"
    case DNS.NameTruncated{}: "Truncated"
    case DNS.ReservedLabel{}: "ReservedLabel"
    case DNS.InvalidPointer{}: "InvalidPointer"

def encoded(value: Result<&2, &2, DNS.DomainNameError, List<&2, U32>>) -> String:
  match value:
    case Fail{why}: "error:" ++ error(why)
    case Done{bytes}: "ok:" ++ showBytes(bytes)

def decoded(value: Result<&2, &2, DNS.DomainNameError, DNS.Decoded>) -> String:
  match value:
    case Fail{why}: "error:" ++ error(why)
    case Done{DNS.Decoded{DNS.Name{labels}, next}}: "ok:" ++ U32.show(next) ++ ":" ++ String.join(showLabels(labels), "/")

def packet(value: Result<&2, &2, DNS.DomainNameError, DNS.Packet>, position: U32) -> String:
  match value:
    case Fail{why}: "error:" ++ error(why)
    case Done{packet}: decoded(DNS.decodeName(packet, position))

def decoding(parts: List<&2, String>) -> String:
  match parts:
    case offset <> values <> Nil{}: packet(DNS.parsePacket(bytes(values)), Scalar.decimal(offset, 0))
    case _: "bad test input"

def zeros(fuel: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case Zero{}: acc
    case Succ{rest}: zeros(rest, 0 <> acc)

def run(input: String) -> String:
  match input:
    case SCon{'e', text}: encoded(DNS.encodeName(name(text)))
    case SCon{'d', text}: decoding(Split.split(text, ':'))
    case SCon{'l', text}: packet(DNS.parsePacket(zeros(U32.to_nat(Scalar.decimal(text, 0)), Nil{})), 0)
    case _: "bad test mode"

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
