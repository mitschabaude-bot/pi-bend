import Base
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/record.bend as Record
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/word-segmenter.bend as Words
import ../packages/tui/src/components/editor.bend as Editor
import ../packages/tui/src/components/select-list.bend as Select
import ../packages/tui/src/keybindings.bend as Bindings
import ../packages/tui/src/keys.bend as Keys
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/coding-agent/src/modes/interactive/components/extension-editor.bend as Extension
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/modes/interactive/theme/markdown-theme.bend as MarkdownTheme
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme

def emit(label: String,pair: Extension.State & List<&2,String>) -> IO(Extension.State):
  match pair:
    case (state,rows):
      do IO<Extension.State>:
        IO.print(label ++ "\u{1e}" ++ String.join(rows,"\u{1f}"))
        return state
def stateOf(pair: Extension.State & Extension.Action) -> Extension.State:
  match pair: case (state,_): state
def actionOf(pair: Extension.State & Extension.Action) -> Extension.Action:
  match pair: case (_,action): action
def submitted(action: Extension.Action,text: String) -> Bool:
  match action: case Extension.Submit{value}: String.eq(value,text) case _: False{}
def check(value: Bool,name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),value,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"FAIL " ++ name))(Unit{})
def run(+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +live : Ref.Ref<Theme.Theme> <- Ref.new(Theme.Theme,theme)
    +border : Callback.Callback<String,String> <- MarkdownTheme.color(live,"borderMuted")
    +accent : Callback.Callback<String,String> <- MarkdownTheme.color(live,"accent")
    +muted : Callback.Callback<String,String> <- MarkdownTheme.color(live,"muted")
    +bindings : Bindings.KeybindingsManager <- IO.pure(Bindings.KeybindingsManager,Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),Record.new(List<&2,Keys.KeyId>)))
    +keyboard : Keys.Context <- IO.pure(Keys.Context,Keys.defaults())
    +source : Words.Source <- IO.pure(Words.Source,Words.Pending{"packages/runtime/data"})
    state : Extension.State <- Extension.create("Compose","seed",Some{"A description"},Editor.EditorTheme{border,Select.SelectListTheme{accent,accent,muted,muted,muted}},None{})
    firstFrame : Extension.State & List<&2,String> <- Extension.render(state,theme,bindings,32n,24n)
    first : Extension.State <- emit("initial",firstFrame)
    typed : Extension.State & Extension.Action <- Extension.handleInput(first,source,bindings,keyboard,"x",24n)
    typedFrame : Extension.State & List<&2,String> <- Extension.render(stateOf(typed),theme,bindings,32n,24n)
    +next : Extension.State <- emit("typed",typedFrame)
    +text : String <- IO.pure(String,Extension.value(next))
    answer : Extension.State & Extension.Action <- Extension.handleInput(next,source,bindings,keyboard,"\n",24n)
    check(submitted(actionOf(answer),text),"submit edited value")
    empty : Extension.State <- Extension.create("Empty","",None{},Editor.EditorTheme{border,Select.SelectListTheme{accent,accent,muted,muted,muted}},None{})
    emptyFrame : Extension.State & List<&2,String> <- Extension.render(empty,theme,bindings,12n,24n)
    final : Extension.State <- emit("empty",emptyFrame)
    check(String.eq(Extension.value(final),""),"empty value")
    Callback.dispose(String,String,border)
    Callback.dispose(String,String,accent)
    Callback.dispose(String,String,muted)
    old : Theme.Theme <- Ref.dispose(Theme.Theme,live)
    return Unit{}
def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Unit):
  match result: case Done{theme}: run(theme) case Fail{_}: IO.die(Unit,1,"dark theme missing")
def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.Palette256{})
    loaded(result)
