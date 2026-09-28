import Base
import ../packages/runtime/src/record.bend as Record
import ../packages/tui/src/keybindings.bend as Bindings
import ../packages/tui/src/keys.bend as Keys
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/coding-agent/src/modes/interactive/components/extension-selector.bend as Selector
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme

def check(value: Bool,name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),value,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"FAIL " ++ name))(Unit{})
def chosen(action: Selector.Action,value: String) -> Bool:
  match action: case Selector.Select{selected}: String.eq(selected,value) case _: False{}
def actionOf(pair: Selector.State & Selector.Action) -> Selector.Action:
  match pair: case (_,action): action
def stateOf(pair: Selector.State & Selector.Action) -> Selector.State:
  match pair: case (state,_): state
def continued(action: Selector.Action) -> Bool:
  match action: case Selector.Continue{}: True{} case _: False{}
def emit(label: String,rows: List<&2,String>) -> IO(Unit):
  IO.print(label ++ "\u{1e}" ++ String.join(rows,"\u{1f}"))
def run(+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +bindings : Bindings.KeybindingsManager <- IO.pure(Bindings.KeybindingsManager,Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),Record.new(List<&2,Keys.KeyId>)))
    +keyboard : Keys.Context <- IO.pure(Keys.Context,Keys.defaults())
    +initial : Selector.State <- IO.pure(Selector.State,Selector.create("Choose one",["first","second"],Some{"For this run"}))
    initialRows : List<&2,String> <- Selector.render(initial,theme,bindings,32n)
    emit("initial",initialRows)
    first : Selector.State & Selector.Action <- IO.pure(Selector.State & Selector.Action,Selector.handleInput(initial,bindings,keyboard,"\n"))
    check(chosen(actionOf(first),"first"),"initial selection")
    second : Selector.State & Selector.Action <- IO.pure(Selector.State & Selector.Action,Selector.handleInput(initial,bindings,keyboard,"j"))
    +state : Selector.State <- IO.pure(Selector.State,stateOf(second))
    selection : Selector.State & Selector.Action <- IO.pure(Selector.State & Selector.Action,Selector.handleInput(state,bindings,keyboard,"\n"))
    check(chosen(actionOf(selection),"second"),"down then select")
    +rows : List<&2,String> <- Selector.render(state,theme,bindings,32n)
    check(Bool.not(List.is_empty(&2,String,rows)),"renders selector")
    emit("down",rows)
    narrow : List<&2,String> <- Selector.render(state,theme,bindings,12n)
    emit("down-narrow",narrow)
    +empty : Selector.State <- IO.pure(Selector.State,Selector.create("Empty",Nil{},None{}))
    none : Selector.State & Selector.Action <- IO.pure(Selector.State & Selector.Action,Selector.handleInput(empty,bindings,keyboard,"\n"))
    check(continued(actionOf(none)),"empty selection")
    emptyRows : List<&2,String> <- Selector.render(empty,theme,bindings,32n)
    emit("empty",emptyRows)
def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Unit):
  match result: case Done{theme}: run(theme) case Fail{_}: IO.die(Unit,1,"dark theme missing")
def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.Palette256{})
    loaded(result)
