import Base
import ../packages/runtime/src/glob.bend as Glob

def boolText(result: Bool) -> String:
  match result:
    case True{}: "true"
    case False{}: "false"

def printResult(result: Bool) -> IO(Unit):
  IO.print(boolText(result))

def runCompiled(result: Result<&2, &2, Glob.Error, Glob.Pattern>, text: String) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("error")
    case Done{compiled}: printResult(Glob.matches(compiled, text))

def runPair(pattern: String, text: String) -> IO(Unit):
  runCompiled(Glob.compile(pattern), text)

def runArgs(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case _ <> Nil{}: IO.print("error")
    case pattern <> text <> rest:
      do IO<Unit>:
        runPair(pattern, text)
        runArgs(rest)

def expectCompiled(result: Result<&2, &2, Glob.Error, Glob.Pattern>, text: String, wanted: Bool) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "unexpected invalid glob")
    case Done{compiled}:
      Bool.pick(IO(Unit), String.eq(boolText(Glob.matches(compiled, text)), boolText(wanted)), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "glob mismatch"))

def expect(pattern: String, text: String, wanted: Bool) -> IO(Unit):
  expectCompiled(Glob.compile(pattern), text, wanted)

def expectErrorCompiled(result: Result<&2, &2, Glob.Error, Glob.Pattern>) -> IO(Unit):
  match result:
    case Fail{_}: IO.pure(Unit, Unit{})
    case Done{_}: IO.die(Unit, 1, "expected invalid glob")

def expectError(pattern: String) -> IO(Unit):
  expectErrorCompiled(Glob.compile(pattern))

def selfCheck() -> IO(Unit):
  do IO<Unit>:
    expect("", "", True{})
    expect("", "x", False{})
    expect("a?c", "abc", True{})
    expect("a*c", "abbbc", True{})
    expect("a*c", "abbbd", False{})
    expect("*", "αβγ", True{})
    expect("?", "α", True{})
    expect("[a-c]", "b", True{})
    expect("[!a-c]", "δ", True{})
    expect("[!a-c]", "b", False{})
    expect("[a-]", "-", True{})
    expect("[-a]", "-", True{})
    expect("[\\]]", "]", True{})
    expect("\\*", "*", True{})
    expect("a*b*c*d", "axbyczd", True{})
    expectError("\\")
    expectError("[")
    expectError("[]")
    expectError("[z-a]")
    IO.print("PASS glob self-checks")

def mainArgs(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: selfCheck()
    case _: runArgs(arguments)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    mainArgs(arguments)
