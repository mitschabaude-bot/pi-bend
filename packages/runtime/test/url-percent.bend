import Base
import ../src/url.bend as Percent
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

def encoding(code: String) -> Percent.EncodeSet:
  match code:
    case "0": Percent.Controls{}
    case "1": Percent.Fragment{}
    case "2": Percent.Query{}
    case "3": Percent.SpecialQuery{}
    case "4": Percent.Path{}
    case "5": Percent.UserInfo{}
    case "6": Percent.Component{}
    case _: Percent.Form{}

def run(parts: List<&2, String>) -> String:
  match parts:
    case "e" <> mode <> value <> Nil{}: Text.showText(Percent.encode(encoding(mode), text(value)))
    case "d" <> value <> Nil{}: String.join(Text.showNumbers(Percent.decodePercent(parseNumbers(value))), ",")
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
