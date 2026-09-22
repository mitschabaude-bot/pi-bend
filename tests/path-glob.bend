import Base
import ../packages/runtime/src/path-glob.bend as G

def report(pattern: Result<&2,&2,G.Error,G.Pattern>, text: String) -> IO(Unit):
  match pattern:
    case Fail{_}: IO.print("error")
    case Done{pattern}: IO.print(Bool.pick(String,G.matches(pattern,text),"true","false"))

def run(args: List<String>) -> IO(Unit):
  match args:
    case pattern <> text <> rest:
      do IO<Unit>:
        report(G.compile(pattern),text)
        run(rest)
    case Nil{}: IO.pure(Unit,Unit{})
    case _: IO.die(Unit,1,"expected pattern/text pairs")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
