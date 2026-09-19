import Base
import ../src/url-authority.bend as Authority
import ../src/string-split.bend as Split
import ./utf8-runner.bend as Text

def decode(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: decode(rest, reversed)
    case part <> rest: decode(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def user(value: Maybe<&2, Authority.Credentials>) -> String:
  match value:
    case None{}: "absent;;"
    case Some{Authority.Credentials{username, password}}: "present;" ++ Text.showText(username) ++ ";" ++ Text.showText(password)

def port(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "absent;"
    case Some{value}: "present;" ++ Text.showText(value)

def show(tokens: Authority.Tokens) -> String:
  match tokens:
    case Authority.Tokens{credentials, host, value}: user(credentials) ++ ";" ++ Text.showText(host) ++ ";" ++ port(value)

def prefix(value: Authority.Prefix) -> String:
  match value:
    case Authority.Prefix{tokens, remainder}: show(tokens) ++ ";" ++ Text.showText(remainder)

def entry(parts: List<&2, String>) -> String:
  match parts:
    case "t" <> input <> Nil{}: show(Authority.parse(decode(Split.split(input, ','), ""))) ++ ";"
    case "s" <> input <> Nil{}: prefix(Authority.read(decode(Split.split(input, ','), ""), True{}))
    case "n" <> input <> Nil{}: prefix(Authority.read(decode(Split.split(input, ','), ""), False{}))
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
