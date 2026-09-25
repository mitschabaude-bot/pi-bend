import Base
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/record.bend as Record
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as C
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme

# upstream test/scrollbar-theme.test.ts ("fullscreen theme colors"): edited
# copies of dark.json loaded in truecolor mode. Adaptation: the edited JSON
# text is parsed with Theme.parse, the step of loadThemeFromPath after it
# reads the file upstream's test writes.

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def codeOf(found: Map<&2, String> & String) -> String:
  match found:
    case (_, code): code

# upstream theme.getFgAnsi(key) and getBgAnsi(key)
def getFgAnsi(theme: Theme.Theme, +key: String) -> String:
  match theme:
    case Theme.Theme{_, _, _, _, codes, _}: codeOf(Map.get(String, "", codes, key))

def getBgAnsi(theme: Theme.Theme, +key: String) -> String:
  match theme:
    case Theme.Theme{_, _, _, _, _, codes}: codeOf(Map.get(String, "", codes, key))

type Edit is Data:
  Delete{key: String}
  Put{key: String, value: String}

def edited(edits: List<&2, Edit>, +colors: Record.Record<V.Value>) -> Record.Record<V.Value>:
  match edits:
    case Nil{}: colors
    case Delete{key} <> rest: edited(rest, Record.remove(V.Value, colors, key))
    case Put{key, value} <> rest: edited(rest, Record.set(V.Value, colors, key, V.Text{value}))

def editedColors(colors: V.Value, edits: List<&2, Edit>) -> V.Value:
  match colors:
    case V.ObjectValue{fields}: V.ObjectValue{edited(edits, fields)}
    case other: other

def editedTheme(value: V.Value, +name: String, edits: List<&2, Edit>) -> V.Value:
  match value:
    case V.ObjectValue{+fields}: V.ObjectValue{Record.set(V.Value, Record.set(V.Value, fields, "name", V.Text{name}), "colors", editedColors(Maybe.default(&2, V.Value, Record.get(V.Value, fields, "colors"), V.Null{}), edits))}
    case other: other

def editedText(parsed: Result<&2, &2, Json.ParseError, V.Value>, +name: String, edits: List<&2, Edit>) -> String:
  match parsed:
    case Done{value}: Maybe.default(&2, String, Render.stringify(SchemaJson.toJson(editedTheme(value, name, edits))), "")
    case Fail{_}: ""

def load(+dark: String, +name: String, edits: List<&2, Edit>) -> Result<&2, &2, Theme.Error, Theme.Theme>:
  Theme.parse(editedText(Json.parse(dark), name, edits), C.TrueColor{})

def fgFallback(+token: String, +fallback: String, result: Result<&2, &2, Theme.Error, Theme.Theme>) -> IO(Unit):
  match result:
    case Fail{_}: check(False{}, "falls back to " ++ token ++ " when omitted")
    case Done{+theme}: check(String.eq(getFgAnsi(theme, token), getFgAnsi(theme, fallback)), "falls back to " ++ token ++ " when omitted")

def explicitScrollbar(result: Result<&2, &2, Theme.Error, Theme.Theme>) -> IO(Unit):
  match result:
    case Fail{_}: check(False{}, "uses explicitly configured scrollbar colors")
    case Done{+theme}: check(String.eq(getFgAnsi(theme, "scrollbarTrack"), "\u{1b}[38;2;101;67;33m") && String.eq(getFgAnsi(theme, "scrollbarThumb"), "\u{1b}[38;2;18;52;86m"), "uses explicitly configured scrollbar colors")

def searchFallback(result: Result<&2, &2, Theme.Error, Theme.Theme>) -> IO(Unit):
  match result:
    case Fail{_}: check(False{}, "falls back to existing selection and text colors for search highlights")
    case Done{+theme}: check(String.eq(getBgAnsi(theme, "searchMatchBg"), getBgAnsi(theme, "selectedBg")) && String.eq(getFgAnsi(theme, "searchMatchText"), getFgAnsi(theme, "text")), "falls back to existing selection and text colors for search highlights")

def explicitSearch(result: Result<&2, &2, Theme.Error, Theme.Theme>) -> IO(Unit):
  match result:
    case Fail{_}: check(False{}, "uses explicitly configured search highlight colors")
    case Done{+theme}: check(String.eq(getBgAnsi(theme, "searchMatchBg"), "\u{1b}[48;2;17;34;51m") && String.eq(getFgAnsi(theme, "searchMatchText"), "\u{1b}[38;2;34;51;68m"), "uses explicitly configured search highlight colors")

def decodedText(bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> String:
  match bytes:
    case Done{values}: Result.default(&2, &2, Utf8.Error, String, Utf8.decodeStrict(values), "")
    case Fail{_}: ""

def run(+dark: String) -> IO(Unit):
  do IO<Unit>:
    fgFallback("scrollbarTrack", "muted", load(dark, "missing-scrollbarTrack-theme", [Delete{"scrollbarTrack"}]))
    fgFallback("scrollbarThumb", "text", load(dark, "missing-scrollbarThumb-theme", [Delete{"scrollbarThumb"}]))
    explicitScrollbar(load(dark, "custom-scrollbar-theme", [Put{"scrollbarTrack", "#654321"}, Put{"scrollbarThumb", "#123456"}]))
    searchFallback(load(dark, "legacy-search-theme", [Delete{"searchMatchBg"}, Delete{"searchMatchText"}]))
    explicitSearch(load(dark, "custom-search-theme", [Put{"searchMatchBg", "#112233"}, Put{"searchMatchText", "#223344"}]))

def main() -> IO(Unit):
  do IO<Unit>:
    bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile("packages/coding-agent/src/modes/interactive/theme/dark.json")
    run(decodedText(bytes))
