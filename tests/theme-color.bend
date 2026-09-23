import Base
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as C

def report(result: Result<&2,&2,C.Error,C.Rgb>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"invalid color")
    case Done{+rgb}:
      IO.print(Nat.show(C.rgbTo256(rgb)) ++ "|" ++ C.foreground(C.RgbColor{rgb},C.TrueColor{}) ++ "|" ++ C.foreground(C.RgbColor{rgb},C.Palette256{}) ++ "|" ++ C.background(C.RgbColor{rgb},C.TrueColor{}) ++ "|" ++ C.background(C.RgbColor{rgb},C.Palette256{}))
def all(colors: List<String>) -> IO(Unit):
  match colors:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        report(C.parseHex(value))
        all(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    colors : List<String> <- IO.args()
    all(colors)
