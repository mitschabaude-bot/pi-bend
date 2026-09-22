import Base
import ../src/idna.bend as Policy
import ../src/idna.bend as Label
import ../src/idna.bend as Bidi
import ../src/string.bend as Split
import ./utf8-runner.bend as Text

def bit(value: Bool) -> String:
  match value:
    case True{}: "1"
    case False{}: "0"

def bidiLabel(code: U32) -> Label.ValidatedLabel:
  match code:
    case 97: Label.ValidatedLabel{"a", False{}, Bidi.Analysis{False{}, True{}}}
    case 98: Label.ValidatedLabel{"1", False{}, Bidi.Analysis{False{}, False{}}}
    case 99: Label.ValidatedLabel{"א", False{}, Bidi.Analysis{True{}, True{}}}
    case 100: Label.ValidatedLabel{"aא", False{}, Bidi.Analysis{True{}, False{}}}
    case _: Label.ValidatedLabel{"", True{}, Bidi.Analysis{False{}, False{}}}

def bidiLabels(input: String, reversed: List<&2, Label.ValidatedLabel>) -> List<&2, Label.ValidatedLabel>:
  match input:
    case SNil{}: List.reverse(&2, Label.ValidatedLabel, reversed)
    case SCon{Chr{code}, rest}: bidiLabels(rest, bidiLabel(code) <> reversed)

def text(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: text(rest, reversed)
    case part <> rest: text(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def run(parts: List<&2, String>) -> String:
  match parts:
    case "b" <> input <> Nil{}: bit(Policy.bidiValid(bidiLabels(input, Nil{})))
    case "d" <> input <> Nil{}: bit(Policy.dnsLengthValid(Split.split(text(Split.split(input, ','), ""), '.')))
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
