import Base
import ../packages/runtime/src/utf16.bend as UTF16
import ../packages/runtime/src/string-split.bend as Split
import ../packages/runtime/test/utf8-runner.bend as Scalar

def source(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: source(rest, reversed)
    case item <> rest: source(rest, SCon{Chr{Scalar.decimal(item, 0)}, reversed})

def shown(text: String, acc: String) -> String:
  match text:
    case SNil{}: acc
    case SCon{Chr{code}, rest}: shown(rest, acc ++ U32.show(code) ++ ",")

def long(count: Nat, acc: String) -> String:
  match count:
    case Zero{}: acc
    case Succ{rest}: long(rest, SCon{'A', SCon{Chr{0}, SCon{Chr{65536}, SCon{Chr{128512}, SCon{Chr{1114111}, acc}}}}})

def digest(text: String, count: U32, value: U32) -> String:
  match text:
    case SNil{}: U32.show(count) ++ ":" ++ U32.show(value)
    case SCon{Chr{code}, rest}: digest(rest, (count + 1 : U32), U32.xor((value * 16777619 : U32), code))

def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(shown(UTF16.normalize(source(Split.split(value, ','), "")), ""))
        run(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(digest(UTF16.normalize(long(20000n, "")), 0, 2166136261))
    args : List<String> <- IO.args()
    run(args)
