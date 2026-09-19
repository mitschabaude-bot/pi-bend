import Base
import ../src/url-host.bend as Host
import ../src/string-split.bend as Split
import ./utf8-runner.bend as Text

def text(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: text(rest, reversed)
    case part <> rest: text(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def kind(host: Host.Host) -> String:
  match host:
    case Host.Domain{_}: "domain"
    case Host.IPv4{_}: "ipv4"
    case Host.IPv6{_}: "ipv6"
    case Host.Opaque{_}: "opaque"
    case Host.Empty{}: "empty"

def show(result: Result<&2, &2, Host.Error, Host.Host>) -> String:
  match result:
    case Fail{_}: "invalid"
    case Done{+host}: kind(host) ++ ";" ++ Text.showText(Host.serialize(host))

def run(parts: List<&2, String>) -> String:
  match parts:
    case "d" <> input <> Nil{}: show(Host.classifyDomain(text(Split.split(input, ','), "")))
    case "o" <> input <> Nil{}: show(Host.parseOpaque(text(Split.split(input, ','), "")))
    case "6" <> input <> Nil{}: show(Host.bracketed(text(Split.split(input, ','), "")))
    case _: "invalid-case"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(Split.split(head, ';')))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
