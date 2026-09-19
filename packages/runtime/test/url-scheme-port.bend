import Base
import ../src/url-scheme.bend as Scheme
import ../src/url-port.bend as Port
import ../src/string-split.bend as Split
import ./utf8-runner.bend as Text

def decode(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: decode(rest, reversed)
    case part <> rest: decode(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def optional(port: Maybe<&2, U32>) -> String:
  match port:
    case None{}: "-"
    case Some{value}: U32.show(value)

def showPort(result: Result<&2, &2, Port.Error, Maybe<&2, U32>>) -> String:
  match result:
    case Fail{Port.InvalidDigit{}}: "digit"
    case Fail{Port.OutOfRange{}}: "range"
    case Done{value}: optional(value)

def special(value: Bool) -> String:
  match value:
    case True{}: "special"
    case False{}: "other"

def show(result: Maybe<&2, Scheme.Scheme>, port: String) -> String:
  match result:
    case None{}: "invalid"
    case Some{+scheme}: Scheme.serialize(scheme) ++ ";" ++ special(Scheme.isSpecial(scheme)) ++ ";" ++ optional(Scheme.defaultPort(scheme)) ++ ";" ++ showPort(Port.parse(Scheme.defaultPort(scheme), port))

def run(parts: List<&2, String>) -> String:
  match parts:
    case scheme <> port <> Nil{}: show(Scheme.parse(decode(Split.split(scheme, ','), "")), decode(Split.split(port, ','), ""))
    case _: "bad fixture"

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
