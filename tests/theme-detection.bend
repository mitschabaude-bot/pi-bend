import Base
import ../packages/coding-agent/src/modes/interactive/theme/detection.bend as D
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as C

def theme(value: D.TerminalTheme) -> String:
  match value:
    case D.Dark{}: "dark"
    case D.Light{}: "light"
def sourceName(source: D.Source) -> String:
  match source:
    case D.TerminalBackground{}: "terminal background"
    case D.ColorFgBg{}: "COLORFGBG"
    case D.Fallback{}: "fallback"
def confidenceName(confidence: D.Confidence) -> String:
  match confidence:
    case D.High{}: "high"
    case D.Low{}: "low"
def detection(value: D.Detection) -> String:
  match value:
    case D.Detection{+result,source,detail,confidence}:
      theme(result) ++ "|" ++ sourceName(source) ++ "|" ++ detail ++ "|" ++ confidenceName(confidence)
@unsafe
def indices(+index: Nat) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),Nat.is_gt(index,255n),_ => IO.pure(Unit,Unit{}),_ => do IO<Unit>:
    IO.print("I|" ++ Nat.show(index) ++ "|" ++ detection(D.detectTerminalBackgroundFromEnv(Some{"0;" ++ Nat.show(index)})))
    indices(index + 1n))(Unit{})
def rgbBlue(+red: Nat,+green: Nat,values: List<&2,Nat>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case +blue <> rest:
      do IO<Unit>:
        IO.print("R|" ++ Nat.show(red) ++ "," ++ Nat.show(green) ++ "," ++ Nat.show(blue) ++ "|" ++ theme(D.getThemeForRgbColor(C.Rgb{red,green,blue})))
        rgbBlue(red,green,rest)
def rgbGreen(+red: Nat,values: List<&2,Nat>,+channels: List<&2,Nat>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case +green <> rest:
      do IO<Unit>:
        rgbBlue(red,green,channels)
        rgbGreen(red,rest,channels)
def rgbRed(values: List<&2,Nat>,+channels: List<&2,Nat>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case red <> rest:
      do IO<Unit>:
        rgbGreen(red,channels,channels)
        rgbRed(rest,channels)
def settings(values: List<&2,String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case +value <> rest:
      do IO<Unit>:
        IO.print("S|" ++ value ++ "|" ++ Maybe.default(&2,String,D.resolveThemeSetting(Some{value},D.Light{}),"undefined") ++ "|" ++ Maybe.default(&2,String,D.resolveThemeSetting(Some{value},D.Dark{}),"undefined"))
        settings(rest)
def channels() -> List<&2,Nat>:
  0n <> 1n <> 8n <> 63n <> 127n <> 128n <> 192n <> 240n <> 250n <> 254n <> 255n <> Nil{}
def main() -> IO(Unit):
  do IO<Unit>:
    settings("light/dark" <> " a / b " <> "dark" <> "" <> "a/b/c" <> "a/" <> "/b" <> Nil{})
    IO.print("E||" ++ detection(D.detectTerminalBackgroundFromEnv(None{})))
    IO.print("E|0;15;bad|" ++ detection(D.detectTerminalBackgroundFromEnv(Some{"0;15;bad"})))
    IO.print("A|" ++ theme(D.detectTerminalThemeForAuto(Some{D.Light{}},Some{C.Rgb{8n,8n,8n}},Some{"0;0"})))
    IO.print("A|" ++ theme(D.detectTerminalThemeForAuto(None{},Some{C.Rgb{250n,250n,250n}},Some{"0;0"})))
    IO.print("A|" ++ theme(D.detectTerminalThemeForAuto(None{},None{},Some{"0;15"})))
    indices(0n)
    rgbRed(channels(),channels())
