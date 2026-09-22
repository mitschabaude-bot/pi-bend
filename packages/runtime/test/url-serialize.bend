import Base
import ../src/url.bend as Record
import ../src/url.bend as Serialize
import ../src/url.bend as Scheme
import ../src/url.bend as Host
import ../src/url.bend as V4
import ../src/url.bend as V6
import ../src/string.bend as Split
import ./utf8-runner.bend as Text

def decode(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: decode(rest, reversed)
    case part <> rest: decode(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def text(value: String) -> String: decode(Split.split(value, ','), "")

def optional(value: String) -> Maybe<&2, String>:
  match value:
    case "-": None{}
    case other: Some{text(other)}

def port(value: String) -> Maybe<&2, U32>:
  match value:
    case "-": None{}
    case other: Some{Text.decimal(other, 0)}

def host(kind: String, value: String) -> Maybe<&2, Host.Host>:
  match kind:
    case "n": None{}
    case "e": Some{Host.Empty{}}
    case "d": Some{Host.Domain{text(value)}}
    case "o": Some{Host.Opaque{text(value)}}
    case "4": Some{Host.IPv4{V4.Address{Text.decimal(value, 0)}}}
    case _: Some{Host.IPv6{V6.Ipv6Address{0, 0, 0, 1}}}

def parts(values: List<&2, String>, reversed: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: List.reverse(&2, String, reversed)
    case value <> rest: parts(rest, text(value) <> reversed)

def hierarchical(value: String) -> Record.RecordPath:
  match value:
    case "-": Record.Hierarchical{Nil{}}
    case other: Record.Hierarchical{parts(Split.split(other, ':'), Nil{})}

def path(kind: String, value: String) -> Record.RecordPath:
  match kind:
    case "o": Record.RecordOpaque{text(value)}
    case _: hierarchical(value)

def render(+value: Record.URL) -> String:
  Text.showText(Serialize.serializeSerialize(value, False{})) ++ ";" ++ Text.showText(Serialize.serializeSerialize(value, True{}))

def entry(values: List<&2, String>) -> String:
  match values:
    case scheme <> username <> password <> hostKind <> hostValue <> number <> pathKind <> pathValue <> query <> fragment <> Nil{}: render(Record.URL{Scheme.classify(scheme), text(username), text(password), host(hostKind, hostValue), port(number), path(pathKind, pathValue), optional(query), optional(fragment)})
    case _: "bad fixture"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(entry(Split.split(head, ';')))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
