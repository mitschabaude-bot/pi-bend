import Base
import ../src/url.bend as Input
import ../src/url.bend as Host
import ../src/string-split.bend as Split
import ./utf8-runner.bend as Text

def text(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: text(rest, reversed)
    case part <> rest: text(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def show(value: Result<&2, &2, Host.HostError, Input.Prepared>) -> String:
  match value:
    case Fail{_}: "invalid"
    case Done{Input.Literal{host}}: "literal;" ++ Text.showText(Host.serializeHost(host))
    case Done{Input.DomainInput{value}}: "domain;" ++ Text.showText(value)

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(show(Input.prepare(text(Split.split(head, ','), ""))))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
