import Base
import ../src/string-split.bend as Split
import ./utf8-runner.bend as Text

def grow(count: Nat, text: String) -> String:
  match count:
    case Zero{}: text
    case Succ{rest}: grow(rest, SCon{'x', text})

def scalars(text: String, total: U32) -> U32:
  match text:
    case SNil{}: total
    case SCon{_, rest}: scalars(rest, (total + 1 : U32))

def summary(parts: List<&2, String>, count: U32, total: U32) -> String:
  match parts:
    case Nil{}: U32.show(count) ++ ";" ++ U32.show(total)
    case text <> rest: summary(rest, (count + 1 : U32), scalars(text, total))

def show(parts: List<&2, String>) -> String:
  match parts:
    case Nil{}: ""
    case text <> rest: "+" ++ Text.showText(text) ++ "/" ++ show(rest)

def run(parts: List<&2, String>) -> String:
  match parts:
    case "s" <> text <> separator <> Nil{}: show(Split.split(Text.fromScalars(Text.parseNumbers(text)), Chr{Text.decimal(separator, 0)}))
    case "g" <> size <> separator <> Nil{}: summary(Split.split(grow(U32.to_nat(Text.decimal(size, 0)), ""), Chr{Text.decimal(separator, 0)}), 0, 0)
    case _: "invalid-case"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        IO.print(run(Split.split(text, ';')))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
