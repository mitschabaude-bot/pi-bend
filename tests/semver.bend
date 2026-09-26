import Base
import ../packages/runtime/src/semver.bend as Semver
import ../packages/runtime/test/utf8-runner.bend as Wire

# Differential fixture for tests/semver_check.py: each argument is a pair of
# versions as code points "a;b"; each line is valid(a)|valid(b)|compare(a,b)
# ("-" for an invalid version or an undefined comparison).

def shown(value: Maybe<&2, String>) -> String: Maybe.default(&2, String, Maybe.map(&2, String, String, Wire.showText, value), "-")

def order(value: Cmp) -> String:
  match value:
    case LT{}: "-1"
    case EQ{}: "0"
    case GT{}: "1"

def compared(left: Maybe<&2, Semver.SemVer>, right: Maybe<&2, Semver.SemVer>) -> String:
  match left right:
    case Some{a} Some{b}: order(Semver.compareSemVer(a, b))
    case _ _: "-"

def line(+left: String, +right: String) -> String:
  shown(Semver.valid(left)) ++ "|" ++ shown(Semver.valid(right)) ++ "|" ++ compared(Semver.parse(left), Semver.parse(right))

def pair(parts: List<&2, String>) -> String:
  match parts:
    case a <> b <> Nil{}: line(Wire.fromScalars(Wire.parseNumbers(a)), Wire.fromScalars(Wire.parseNumbers(b)))
    case a <> Nil{}: line(Wire.fromScalars(Wire.parseNumbers(a)), "")
    case _: "bad"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        IO.print(pair(String.split(arg, ';')))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
