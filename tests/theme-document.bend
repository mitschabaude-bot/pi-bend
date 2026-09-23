import Base
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/runtime/src/record.bend as Record

def colors(values: List<&2,Record.Property<Color.Color>>,+mode: Color.Mode,+bg: Bool) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case Record.Property{key,+color} <> rest:
      do IO<Unit>:
        IO.print(Bool.pick(String,bg,"B","F") ++ "|" ++ key ++ "|" ++ Bool.pick(String,bg,Color.background(color,mode),Color.foreground(color,mode)))
        colors(rest,mode,bg)
def display(theme: Theme.Theme) -> IO(Unit):
  match theme:
    case Theme.Theme{name,+mode,fg,bg}:
      do IO<Unit>:
        IO.print("N|" ++ name)
        colors(Record.entries(Color.Color,fg),mode,False{})
        colors(Record.entries(Color.Color,bg),mode,True{})
def report(result: Result<&2,&2,Theme.Error,Theme.Theme>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"invalid theme")
    case Done{theme}: display(theme)
def reportLoaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"could not load theme")
    case Done{theme}: display(theme)
def load(path: String,mode: Color.Mode) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath(path,mode)
    reportLoaded(result)
def run(args: List<String>) -> IO(Unit):
  match args:
    case "file" <> path <> "truecolor" <> Nil{}: load(path,Color.TrueColor{})
    case "file" <> path <> "256color" <> Nil{}: load(path,Color.Palette256{})
    case content <> "truecolor" <> Nil{}: report(Theme.parse(content,Color.TrueColor{}))
    case content <> "256color" <> Nil{}: report(Theme.parse(content,Color.Palette256{}))
    case _: IO.die(Unit,1,"expected theme JSON and color mode")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
