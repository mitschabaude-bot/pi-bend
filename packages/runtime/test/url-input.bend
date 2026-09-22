import Base
import ../src/url.bend as Input
import ../src/url.bend as Scheme
import ../src/string.bend as Split
import ./utf8-runner.bend as Text

def decode(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: decode(rest, reversed)
    case part <> rest: decode(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def show(value: Input.InputPrefix) -> String:
  match value:
    case Input.Relative{input}: "relative;;" ++ Text.showText(input)
    case Input.Absolute{scheme, remainder}: "absolute;" ++ Text.showText(Scheme.serializeScheme(scheme)) ++ ";" ++ Text.showText(remainder)

def report(+input: String, +prepared: String) -> String:
  Text.showText(prepared) ++ ";" ++ Text.showText(Input.removeTabsAndNewlines(input)) ++ ";" ++ show(Input.prefixInput(prepared))

def run(+input: String) -> String: report(input, Input.prepareInput(input))

# Compact fixture expansion keeps long inputs below the OS per-argument limit.
def repeated(count: Nat, +block: String, reversed: String) -> String:
  match count:
    case Zero{}: String.reverse(reversed)
    case Succ{rest}: repeated(rest, block, String.reverse(block) ++ reversed)

def input(parts: List<&2, String>) -> String:
  match parts:
    case value <> Nil{}: decode(Split.split(value, ','), "")
    case prefix <> count <> block <> Nil{}: repeated(U32.to_nat(Text.decimal(count, 0)), decode(Split.split(block, ','), ""), String.reverse(decode(Split.split(prefix, ','), "")))
    case _: "bad fixture"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(input(Split.split(head, ';'))))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
