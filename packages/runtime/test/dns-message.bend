import Base
import ../src/dns-message.bend as DNS
import ../src/dns-name.bend as Name
import ../src/string-split.bend as Split
import ./utf8-runner.bend as Scalar

def numbers(parts: List<&2, String>, reversed: List<&2, U32>) -> List<&2, U32>:
  match parts:
    case Nil{}: List.reverse(&2, U32, reversed)
    case SNil{} <> rest: numbers(rest, reversed)
    case item <> rest: numbers(rest, Scalar.decimal(item, 0) <> reversed)

def bytes(text: String) -> List<&2, U32>:
  numbers(Split.split(text, ','), Nil{})

def labelValues(parts: List<&2, String>, reversed: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match parts:
    case Nil{}: List.reverse(&2, List<&2, U32>, reversed)
    case label <> rest: labelValues(rest, bytes(label) <> reversed)

def inputName(text: String) -> Name.Name:
  match text:
    case SNil{}: Name.Name{Nil{}}
    case other: Name.Name{labelValues(Split.split(other, '/'), Nil{})}

def showBytes(values: List<&2, U32>) -> String:
  String.join(Scalar.showNumbers(values), ",")

def showLabels(values: List<&2, List<&2, U32>>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case label <> rest: showBytes(label) <> showLabels(rest)

def nameError(value: Name.Error) -> String:
  match value:
    case Name.InvalidByte{}: "InvalidByte"
    case Name.InvalidLabel{}: "InvalidLabel"
    case Name.NameTooLong{}: "NameTooLong"
    case Name.PacketTooLong{}: "PacketTooLong"
    case Name.Truncated{}: "Truncated"
    case Name.ReservedLabel{}: "ReservedLabel"
    case Name.InvalidPointer{}: "InvalidPointer"

def name(value: Name.Name) -> String:
  match value:
    case Name.Name{labels}: String.join(showLabels(labels), "/")

def header(value: DNS.Header) -> String:
  match value:
    case DNS.Header{id, flags, qd, an, ns, ar}: showBytes(id <> flags <> qd <> an <> ns <> ar <> Nil{})

def questions(values: List<&2, DNS.Question>, reversed: List<&2, String>) -> String:
  match values:
    case Nil{}: String.join(List.reverse(&2, String, reversed), ";")
    case DNS.Question{value, kind, class} <> rest: questions(rest, (name(value) ++ ":" ++ showBytes(kind <> class <> Nil{})) <> reversed)

def records(values: List<&2, DNS.Record>, reversed: List<&2, String>) -> String:
  match values:
    case Nil{}: String.join(List.reverse(&2, String, reversed), ";")
    case DNS.Record{value, kind, class, ttl, start, length} <> rest: records(rest, (name(value) ++ ":" ++ showBytes(kind <> class <> ttl <> start <> length <> Nil{})) <> reversed)

def error(value: DNS.Error) -> String:
  match value:
    case DNS.NameError{why}: "name:" ++ nameError(why)
    case DNS.Truncated{}: "Truncated"
    case DNS.TrailingData{}: "TrailingData"
    case DNS.InvalidField{}: "InvalidField"

def show(value: Result<&2, &2, DNS.Error, DNS.Message>) -> String:
  match value:
    case Fail{why}: "error:" ++ error(why)
    case Done{DNS.Message{_, h, q, a, n, r}}: "ok:" ++ header(h) ++ "|" ++ questions(q, Nil{}) ++ "|" ++ records(a, Nil{}) ++ "|" ++ records(n, Nil{}) ++ "|" ++ records(r, Nil{})

def query(value: Result<&2, &2, DNS.Error, List<&2, U32>>) -> String:
  match value:
    case Fail{why}: "error:" ++ error(why)
    case Done{wire}: "ok:" ++ showBytes(wire)

def querying(parts: List<&2, String>) -> String:
  match parts:
    case id <> flags <> kind <> class <> domainText <> Nil{}: query(DNS.query(Scalar.decimal(id, 0), Scalar.decimal(flags, 0), DNS.Question{inputName(domainText), Scalar.decimal(kind, 0), Scalar.decimal(class, 0)}))
    case _: "bad test input"

def run(input: String) -> String:
  match input:
    case SCon{'p', text}: show(DNS.parse(bytes(text)))
    case SCon{'q', text}: querying(Split.split(text, ':'))
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
