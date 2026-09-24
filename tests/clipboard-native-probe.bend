import Base
import ../packages/coding-agent/src/utils/clipboard.bend as Clipboard

def copied(result: Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.print("OK")
    case Fail{message}: IO.print("ERROR: " ++ message)
def shown(value: Maybe<&2,String>) -> IO(Unit):
  match value:
    case None{}: IO.print("EMPTY")
    case Some{text}: IO.print("TEXT: " ++ text)
def dispatch(args: List<String>) -> IO(Unit):
  match args:
    case "copy" <> text <> Nil{}:
      do IO<Unit>:
        result : Result<&2,&2,String,Unit> <- Clipboard.copy(text,".")
        copied(result)
    case "read" <> Nil{}:
      do IO<Unit>:
        value : Maybe<&2,String> <- Clipboard.read(".")
        shown(value)
    case _: IO.die(Unit,1,"expected copy TEXT or read")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    dispatch(args)
