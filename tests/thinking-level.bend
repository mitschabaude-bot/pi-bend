import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/thinking-levels.bend as Levels
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/record.bend as Record
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/word-segmenter.bend as Segmenter
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/tui/src/keybindings.bend as Keybindings
import ../packages/tui/src/keys.bend as Keys
import ../packages/coding-agent/src/cli/args.bend as Args
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/coding-agent/src/modes/interactive/components/thinking-selector.bend as Picker
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as C
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/utils/ansi.bend as Ansi

# upstream test/thinking-selector.test.ts and test/max-thinking.test.ts.
# Adaptations: the selector's state is a value driven through Picker.input and
# Picker.rendered; a save choice is Chosen{level, True} (upstream's
# onSelectAsDefault callback). The port's selector always has a default level;
# upstream's tests pass none, so they get `off`, which is not offered. The
# legacy theme is parsed from the edited dark.json text (upstream writes it to
# a file for loadThemeFromPath, which reads and parses it).

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def medium() -> Ai.ModelThinkingLevel: Ai.Thinking{Ai.Medium{}}
def high() -> Ai.ModelThinkingLevel: Ai.Thinking{Ai.High{}}

def environment() -> AppKeys.Environment: AppKeys.Environment{"linux", None{}, None{}}

def ctrl(char: Char) -> List<&2, Keys.KeyId>: [Keys.KeyId{Keys.Printable{char}, Keys.Modifiers{False{}, False{}, True{}, False{}}}]

def bindings(user: Record.Record<List<&2, Keys.KeyId>>) -> Keybindings.KeybindingsManager:
  Keybindings.create(AppKeys.KEYBINDINGS(environment()), user)

def defaults() -> Keybindings.KeybindingsManager: bindings(Record.new(List<&2, Keys.KeyId>))

def words() -> Segmenter.Source: Segmenter.Pending{"/nonexistent"}

def selector() -> Picker.State: Picker.create([medium(), high()], medium(), Ai.Off{})

def plain(lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: Ansi.stripAnsi(line) <> plain(rest)

def rowOf(lines: List<&2, String>, +text: String) -> String:
  match lines:
    case Nil{}: ""
    case +line <> rest: Bool.pick(String, String.contains(line, text), line, rowOf(rest, text))

def linesOf(pair: Picker.State & List<&2, String>) -> List<&2, String>:
  match pair:
    case (_, lines): plain(lines)

def stateOf(pair: Picker.State & Picker.Action) -> Picker.State:
  match pair:
    case (state, _): state

# upstream's SelectItem label: the current-level mark and the level.
def labelOf(entry: Maybe<&2, Picker.Entry>) -> String:
  match entry:
    case Some{Picker.Entry{+level, _}}: Bool.pick(String, Picker.same(level, medium()), "✓ ", "  ") ++ Levels.name(level)
    case None{}: ""

def selectedLabel(state: Picker.State) -> String: labelOf(Picker.selected(state))

def keepsCurrentMarked(+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +state : Picker.State <- IO.pure(Picker.State, selector())
    check(String.eq(selectedLabel(state), "✓ medium"), "keeps the current thinking level marked while browsing: selected label")
    before : Picker.State & List<&2, String> <- Picker.rendered(state, theme, defaults(), 80n)
    +first : List<&2, String> = linesOf(before)
    check(String.starts_with(rowOf(first, "medium"), "→ ✓ medium"), "keeps the current thinking level marked while browsing: initial row")
    moved : Picker.State & Picker.Action <- Picker.input(state, words(), defaults(), Keys.defaults(), "\u{1b}[B")
    after : Picker.State & List<&2, String> <- Picker.rendered(stateOf(moved), theme, defaults(), 80n)
    +second : List<&2, String> = linesOf(after)
    check(String.starts_with(rowOf(second, "medium"), "  ✓ medium") && String.starts_with(rowOf(second, "high"), "→   high"), "keeps the current thinking level marked while browsing: after down")

def saved(action: Picker.Action) -> Maybe<&2, Ai.ModelThinkingLevel>:
  match action:
    case Picker.Chosen{level, True{}}: Some{level}
    case _: None{}

def savedOf(pair: Picker.State & Picker.Action) -> Maybe<&2, Ai.ModelThinkingLevel>:
  match pair:
    case (_, action): saved(action)

def isMedium(level: Maybe<&2, Ai.ModelThinkingLevel>) -> Bool:
  match level:
    case Some{Ai.Thinking{Ai.Medium{}}}: True{}
    case _: False{}

def thenCtrlR(custom: Keybindings.KeybindingsManager, old: Picker.State & Picker.Action) -> IO(Unit):
  match old:
    case (state, action):
      do IO<Unit>:
        check(Maybe.is_none(&2, Ai.ModelThinkingLevel, saved(action)), "uses the configured save binding: ctrl+s does not save")
        new : Picker.State & Picker.Action <- Picker.input(state, words(), custom, Keys.defaults(), "\u{12}")
        check(isMedium(savedOf(new)), "uses the configured save binding: ctrl+r saves medium")

def usesConfiguredSave(+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +custom : Keybindings.KeybindingsManager <- IO.pure(Keybindings.KeybindingsManager, bindings(Record.set(List<&2, Keys.KeyId>, Record.new(List<&2, Keys.KeyId>), "app.thinking.save", ctrl('r'))))
    shown : Picker.State & List<&2, String> <- Picker.rendered(selector(), theme, custom, 80n)
    check(String.contains(String.join(linesOf(shown), "\n"), "Ctrl+R to set as default"), "uses the configured save binding: hint")
    old : Picker.State & Picker.Action <- Picker.input(selector(), words(), custom, Keys.defaults(), "\u{13}")
    thenCtrlR(custom, old)

# max-thinking.test.ts: is accepted by CLI and settings
def settingsLevel(pair: Settings.InMemorySettingsStorage & Settings.SettingsManager) -> Maybe<&2, Ai.ModelThinkingLevel>:
  match pair:
    case (_, manager): Settings.getDefaultThinkingLevel(manager)

def flushedLevel(storage: Settings.InMemorySettingsStorage, set: Settings.Outcome(Settings.SettingsManager)) -> IO(Maybe<&2, Ai.ModelThinkingLevel>):
  match set:
    case Fail{_}: IO.pure(Maybe<&2, Ai.ModelThinkingLevel>, None{})
    case Done{next}:
      do IO<Maybe<&2, Ai.ModelThinkingLevel>>:
        flushed : Settings.InMemorySettingsStorage & Settings.SettingsManager <- Settings.flush(~Settings.InMemorySettingsStorage, ~Settings.memoryWithLock, storage, next)
        return settingsLevel(flushed)

def flushedMax(pair: Settings.InMemorySettingsStorage & Settings.SettingsManager) -> IO(Maybe<&2, Ai.ModelThinkingLevel>):
  match pair:
    case (storage, manager): flushedLevel(storage, Settings.setDefaultThinkingLevel(Ai.Thinking{Ai.Max{}}, manager))

def isMax(level: Maybe<&2, Ai.ModelThinkingLevel>) -> Bool:
  match level:
    case Some{Ai.Thinking{Ai.Max{}}}: True{}
    case _: False{}

def acceptsMax() -> IO(Unit):
  do IO<Unit>:
    check(Args.isValidThinkingLevel("max"), "is accepted by CLI and settings: CLI")
    loaded : Settings.InMemorySettingsStorage & Settings.SettingsManager <- Settings.inMemory(Settings.empty(), Settings.options())
    level : Maybe<&2, Ai.ModelThinkingLevel> <- flushedMax(loaded)
    check(isMax(level), "is accepted by CLI and settings: settings")

# max-thinking.test.ts: falls back to thinkingXhigh for legacy themes.
# upstream getThinkingBorderColor(level) paints with the level's theme key
# (thinkingMax for max, thinkingXhigh for xhigh).
def legacyColors(colors: V.Value) -> V.Value:
  match colors:
    case V.ObjectValue{fields}: V.ObjectValue{Record.remove(V.Value, fields, "thinkingMax")}
    case other: other

def legacy(value: V.Value) -> V.Value:
  match value:
    case V.ObjectValue{+fields}: V.ObjectValue{Record.set(V.Value, Record.set(V.Value, fields, "name", V.Text{"legacy-theme"}), "colors", legacyColors(Maybe.default(&2, V.Value, Record.get(V.Value, fields, "colors"), V.Null{})))}
    case other: other

def legacyText(parsed: Result<&2, &2, Json.ParseError, V.Value>) -> String:
  match parsed:
    case Done{value}: Maybe.default(&2, String, Render.stringify(SchemaJson.toJson(legacy(value))), "")
    case Fail{_}: ""

def fallsBack(result: Result<&2, &2, Theme.Error, Theme.Theme>) -> IO(Unit):
  match result:
    case Fail{_}: check(False{}, "falls back to thinkingXhigh for legacy themes: parse")
    case Done{+theme}: check(String.eq(Theme.fg(theme, "thinkingMax", "border"), Theme.fg(theme, "thinkingXhigh", "border")), "falls back to thinkingXhigh for legacy themes")

def decodedText(bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> String:
  match bytes:
    case Done{values}: Result.default(&2, &2, Utf8.Error, String, Utf8.decodeStrict(values), "")
    case Fail{_}: ""

def readText(path: String) -> IO(String):
  do IO<String>:
    bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
    return decodedText(bytes)

def withTheme(result: Result<&2, &2, Theme.LoadError, Theme.Theme>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "FAIL cannot load the dark theme")
    case Done{+theme}:
      do IO<Unit>:
        keepsCurrentMarked(theme)
        usesConfiguredSave(theme)

def darkPath() -> String: "packages/coding-agent/src/modes/interactive/theme/dark.json"

def main() -> IO(Unit):
  do IO<Unit>:
    dark : Result<&2, &2, Theme.LoadError, Theme.Theme> <- Theme.loadFromPath(darkPath(), C.TrueColor{})
    withTheme(dark)
    acceptsMax()
    text : String <- readText(darkPath())
    fallsBack(Theme.parse(legacyText(Json.parse(text)), C.TrueColor{}))
