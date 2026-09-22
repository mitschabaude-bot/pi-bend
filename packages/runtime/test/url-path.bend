import Base
import ../src/url.bend as Path
import ../src/url.bend as Scheme
import ../src/string.bend as Split
import ./utf8-runner.bend as Text

def decode(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: decode(rest, reversed)
    case part <> rest: decode(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def optional(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "absent;"
    case Some{value}: "present;" ++ Text.showText(value)

def pathText(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case head <> rest: pathText(rest, String.reverse(head) ++ SCon{'/', reversed})

def show(value: Path.PathParsed) -> String:
  match value:
    case Path.PathParsed{segments, query, fragment}: Text.showText(pathText(segments, "")) ++ ";" ++ optional(query) ++ ";" ++ optional(fragment)

def run(scheme: Maybe<&2, Scheme.Scheme>, text: String, base: List<&2, String>) -> String:
  match scheme:
    case None{}: "invalid scheme"
    case Some{value}: show(Path.parsePath(text, value, base))

def start(scheme: Maybe<&2, Scheme.Scheme>, text: String) -> String:
  match scheme:
    case None{}: "invalid scheme"
    case Some{value}: show(Path.startPath(text, value, Nil{}))

def baseParts(text: String) -> List<&2, String>:
  match text:
    case "-": Nil{}
    case other: Split.split(other, '/')

def dispatch(mode: String, base: String, text: String) -> String:
  match mode:
    case "s": start(Scheme.parseScheme(base), decode(Split.split(text, ','), ""))
    case scheme: run(Scheme.parseScheme(scheme), decode(Split.split(text, ','), ""), baseParts(base))

def entry(parts: List<&2, String>) -> String:
  match parts:
    case mode <> base <> text <> Nil{}: dispatch(mode, base, text)
    case _: "bad fixture"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(entry(Split.split(head, ';')))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
