import Base
import ../packages/tui/src/terminal-colors.bend as C
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V

def rgb(value: Maybe<&2,C.RgbColor>) -> String:
  match value:
    case None{}: "null"
    case Some{C.RgbColor{r,g,b}}: "{\"r\":" ++ U32.show(r) ++ ",\"g\":" ++ U32.show(g) ++ ",\"b\":" ++ U32.show(b) ++ "}"
def scheme(value: Maybe<&2,C.TerminalColorScheme>) -> String:
  match value:
    case None{}: "null"
    case Some{C.Dark{}}: "\"dark\""
    case Some{C.Light{}}: "\"light\""
def result(+text: String) -> String:
  "[" ++ Bool.pick(String,C.isOsc11BackgroundColorResponse(text),"true","false") ++ "," ++ rgb(C.parseOsc11BackgroundColor(text)) ++ "," ++ scheme(C.parseTerminalColorSchemeReport(text)) ++ "]"
def run(values: List<&2,V.Value>) -> IO(Unit):
  match values:
    case V.Text{text} <> rest:
      do IO<Unit>:
        IO.print(result(text))
        run(rest)
    case Nil{}: IO.pure(Unit,Unit{})
    case _: IO.die(Unit,1,"strings required")
def parsed(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{values}}: run(values)
    case _: IO.die(Unit,1,"array required")
def arguments(values: List<String>) -> IO(Unit):
  match values:
    case text <> Nil{}: parsed(J.parse(text))
    case _: IO.die(Unit,1,"argument required")
def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
