import Base
import ../src/idna.bend as ACE
import ../src/punycode.bend as Core
import ../src/string-split.bend as Split
import ./utf8-runner.bend as Text

def text(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: text(rest, reversed)
    case part <> rest: text(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def show(value: Result<&2, &2, ACE.Error, ACE.Label>) -> String:
  match value:
    case Fail{ACE.NonASCIIEncoding{}}: "non-ascii"
    case Fail{ACE.ASCIIOnlyDecodedLabel{}}: "ascii-only"
    case Fail{ACE.InvalidPunycode{Core.InvalidInput{}}}: "invalid"
    case Fail{ACE.InvalidPunycode{Core.Overflow{}}}: "overflow"
    case Done{ACE.Label{input, False{}}}: "plain;" ++ Text.showText(input)
    case Done{ACE.Label{input, True{}}}: "decoded;" ++ Text.showText(input)

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(show(ACE.decode(text(Split.split(head, ','), ""))))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
