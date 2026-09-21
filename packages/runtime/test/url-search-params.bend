import Base
import ../src/url-search-params.bend as Params
import ../src/url-form.bend as Form
import ./utf8-runner.bend as Text
import ../src/string-split.bend as Split

def numbers(parts: List<&2, String>, reversed: List<&2, U32>) -> List<&2, U32>:
  match parts:
    case Nil{}: List.reverse(&2, U32, reversed)
    case SNil{} <> rest: numbers(rest, reversed)
    case part <> rest: numbers(rest, Text.decimal(part, 0) <> reversed)

def parseNumbers(text: String) -> List<&2, U32>: numbers(Split.split(text, ','), Nil{})

def buildText(values: List<&2, U32>, reversed: String) -> String:
  match values:
    case Nil{}: String.reverse(reversed)
    case code <> rest: buildText(rest, SCon{Chr{code}, reversed})

def text(value: String) -> String: buildText(parseNumbers(value), "")

def entries(values: List<&2, Form.Entry>) -> String:
  match values:
    case Nil{}: ""
    case Form.Entry{name, value} <> rest: Text.showText(name) ++ ":" ++ Text.showText(value) ++ "/" ++ entries(rest)

def count(n: Nat) -> U32:
  match n:
    case Zero{}: 0
    case Succ{rest}: (1 + count(rest) : U32)

def show(+params: Params.URLSearchParams) -> String:
  Params.toString(params) ++ "~" ++ entries(Params.entries(params)) ++ "~" ++ U32.show(count(Params.size(params)))

def optional(value: String) -> Maybe<&2, String>:
  match value:
    case SCon{'+', rest}: Some{text(rest)}
    case _: None{}

def found(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "-"
    case Some{value}: "+" ++ Text.showText(value)

def values(all: List<&2, String>) -> String:
  match all:
    case Nil{}: ""
    case value <> rest: "+" ++ Text.showText(value) ++ "/" ++ values(rest)

def updated(+before: Params.URLSearchParams, +after: Params.URLSearchParams) -> Params.URLSearchParams & String:
  (after, show(before) ++ ">" ++ show(after))

def operation(parts: List<&2, String>, +params: Params.URLSearchParams) -> Params.URLSearchParams & String:
  match parts:
    case "a" <> name <> value <> Nil{}: updated(params, Params.append(params, text(name), text(value)))
    case "s" <> name <> value <> Nil{}: updated(params, Params.set(params, text(name), text(value)))
    case "d" <> name <> value <> Nil{}: updated(params, Params.delete(params, text(name), optional(value)))
    case "k" <> Nil{}: (params, values(Params.keys(params)))
    case "v" <> Nil{}: (params, values(Params.values(params)))
    case "r" <> Nil{}: updated(params, Params.sort(params))
    case "g" <> name <> Nil{}: (params, found(Params.get(params, text(name))))
    case "l" <> name <> Nil{}: (params, values(Params.getAll(params, text(name))))
    case "h" <> name <> value <> Nil{}: (params, Bool.pick(String, Params.has(params, text(name), optional(value)), "yes", "no"))
    case _: (params, "invalid-operation")

def operations(parts: List<&2, String>, state: Params.URLSearchParams & String, reversed: List<&2, String>) -> String:
  match parts state:
    case Nil{} Tuple{_, output}: String.join(List.reverse(&2, String, output <> reversed), "#")
    case part <> rest Tuple{params, output}: operations(rest, operation(Split.split(part, ':'), params), output <> reversed)

def run(parts: List<&2, String>) -> String:
  match parts:
    case "q" <> initial <> ops <> Nil{}:
      +params = Params.parse(text(initial))
      operations(Split.split(ops, '|'), (params, show(params)), Nil{})
    case "p" <> value <> Nil{}: show(Params.parse(text(value)))
    case "f" <> value <> Nil{}: entries(Form.parse(text(value)))
    case "n" <> name <> value <> Nil{}: show(Params.fromEntries(Form.Entry{text(name), text(value)} <> Nil{}))
    case _: "invalid-case"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(run(Split.split(value, ';')))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
