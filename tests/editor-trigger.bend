import Base
import ../packages/tui/src/components/editor.bend as E

# Arguments: the provider's extra trigger characters, then texts before the
# cursor. Prints whether each text is a symbol-completion context.
def report(+triggers: List<&2,Char>,texts: List<String>) -> IO(Unit):
  match texts:
    case Nil{}: IO.pure(Unit,Unit{})
    case text <> rest:
      do IO<Unit>:
        IO.print(Bool.show(E.symbolContext(text,triggers,True{})))
        report(triggers,rest)
def run(args: List<String>) -> IO(Unit):
  match args:
    case extra <> texts: report(E.triggerCharacters(String.to_list(extra),['@','#']),texts)
    case Nil{}: IO.die(Unit,1,"expected trigger characters")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
