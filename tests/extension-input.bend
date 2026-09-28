import Base
import ../packages/runtime/src/record.bend as Record
import ../packages/runtime/src/word-segmenter.bend as Words
import ../packages/tui/src/keybindings.bend as Bindings
import ../packages/tui/src/keys.bend as Keys
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/coding-agent/src/modes/interactive/components/extension-input.bend as Input
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme

def emit(label: String,pair: Input.State & List<&2,String>) -> IO(Input.State):
  match pair:
    case (state,rows):
      do IO<Input.State>:
        IO.print(label ++ "\u{1e}" ++ String.join(rows,"\u{1f}"))
        return state
def stateOf(pair: Input.State & Input.Action) -> Input.State:
  match pair: case (state,_): state
def actionOf(pair: Input.State & Input.Action) -> Input.Action:
  match pair: case (_,action): action
def submitted(action: Input.Action,text: String) -> Bool:
  match action: case Input.Submit{value}: String.eq(value,text) case _: False{}
def check(value: Bool,name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),value,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"FAIL " ++ name))(Unit{})
def run(+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +bindings : Bindings.KeybindingsManager <- IO.pure(Bindings.KeybindingsManager,Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),Record.new(List<&2,Keys.KeyId>)))
    +keyboard : Keys.Context <- IO.pure(Keys.Context,Keys.defaults())
    +source : Words.Source <- IO.pure(Words.Source,Words.Pending{"packages/runtime/data"})
    +initial : Input.State <- IO.pure(Input.State,Input.create("Enter value","seed",Some{"A description"}))
    initialFrame : Input.State & List<&2,String> <- Input.render(initial,theme,bindings,32n)
    first : Input.State <- emit("initial",initialFrame)
    changed : Input.State & Input.Action <- Input.handleInput(first,source,bindings,keyboard,"x")
    +typed : Input.State <- IO.pure(Input.State,stateOf(changed))
    typedFrame : Input.State & List<&2,String> <- Input.render(typed,theme,bindings,32n)
    next : Input.State <- emit("typed",typedFrame)
    answer : Input.State & Input.Action <- Input.handleInput(next,source,bindings,keyboard,"\n")
    check(submitted(actionOf(answer),"xseed"),"submit typed value")
    +empty : Input.State <- IO.pure(Input.State,Input.create("Empty","",None{}))
    emptyFrame : Input.State & List<&2,String> <- Input.render(empty,theme,bindings,12n)
    final : Input.State <- emit("empty",emptyFrame)
    check(String.eq(Input.value(final),""),"empty value")
def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Unit):
  match result: case Done{theme}: run(theme) case Fail{_}: IO.die(Unit,1,"dark theme missing")
def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.Palette256{})
    loaded(result)
