import Base
import ../packages/tui/src/components/editor-component.bend as Live
import ../packages/tui/src/components/editor.bend as Editor
import ../packages/tui/src/components/select-list.bend as Select
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/keybindings.bend as Keybindings
import ../packages/tui/src/keys.bend as Keys
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/record.bend as Record
import ../packages/runtime/src/word-segmenter.bend as Segmenter
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/coding-agent/src/modes/interactive/components/custom-editor.bend as CustomEditor

# upstream test/custom-editor-history-keybindings.test.ts
def check(value: Bool,+name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),value,_ => IO.print("ok " ++ name),_ => IO.die(Unit,1,"FAIL " ++ name))(Unit{})
def identity(ignored: Unit,value: String) -> IO(String): IO.pure(String,value)
def counted(cycles: Ref.Ref<Nat>,action: CustomEditor.AppAction) -> IO(Unit):
  match action:
    case CustomEditor.AppAction{"app.model.cycleForward",_}: Ref.modify(Nat,Unit,cycles,count => (count + 1n,Unit{}))
    case _: IO.pure(Unit,Unit{})
def ctrl(char: Char) -> List<&2,Keys.KeyId>: [Keys.KeyId{Keys.Printable{char},Keys.Modifiers{False{},False{},True{},False{}}}]
def bindings() -> Keybindings.KeybindingsManager:
  Keybindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),Record.set(List<&2,Keys.KeyId>,Record.set(List<&2,Keys.KeyId>,Record.new(List<&2,Keys.KeyId>),"tui.editor.historyPrevious",ctrl('p')),"tui.editor.historyNext",ctrl('n')))

def exercise(borrowed: CustomEditor.Owner & Component.Component,+handle: Live.Handle,cycles: Ref.Ref<Nat>) -> IO(Unit):
  match borrowed:
    case (custom,+component):
      do IO<Unit>:
        Live.setText(handle,"draft")
        Component.handleInput(component,"\u{10}")
        previous : String <- Live.text(handle)
        count : Nat <- Ref.read(Nat,cycles)
        check(String.eq(previous,"previous prompt") && Nat.is_eq(count,0n),"gives an explicit history binding precedence over model cycling")
        Component.handleInput(component,"\u{e}")
        draft : String <- Live.text(handle)
        check(String.eq(draft,"draft"),"history next restores the draft")
        CustomEditor.dispose(custom)
# Supplement: with the default bindings Ctrl+P reaches the registered action.
def exerciseDefault(borrowed: CustomEditor.Owner & Component.Component,cycles: Ref.Ref<Nat>) -> IO(Unit):
  match borrowed:
    case (custom,component):
      do IO<Unit>:
        Component.handleInput(component,"\u{10}")
        count : Nat <- Ref.read(Nat,cycles)
        check(Nat.is_eq(count,1n),"default Ctrl+P cycles models")
        CustomEditor.dispose(custom)
def run(pair: Live.Owner & Component.Component & Live.Handle,+cycles: Ref.Ref<Nat>,+onAction: Callback.Callback<CustomEditor.AppAction,Unit>) -> IO(Unit):
  match pair:
    case (owner,+inner,handle):
      do IO<Unit>:
        +editor : Live.Handle <- IO.pure(Live.Handle,handle)
        custom : CustomEditor.Owner <- CustomEditor.create(CustomEditor.Host{editor,inner,bindings(),Keys.defaults(),["app.model.cycleForward"],onAction})
        exercise(CustomEditor.borrow(custom),editor,cycles)
        defaults : CustomEditor.Owner <- CustomEditor.create(CustomEditor.Host{editor,inner,Keybindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),Record.new(List<&2,Keys.KeyId>)),Keys.defaults(),["app.model.cycleForward"],onAction})
        exerciseDefault(CustomEditor.borrow(defaults),cycles)
        Live.dispose(owner)

def main() -> IO(Unit):
  do IO<Unit>:
    +rows : Ref.Ref<Nat> <- Ref.new(Nat,24n)
    +cycles : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +paint : Callback.Callback<String,String> <- Callback.create(~Unit,~String,~String,~identity,Unit{})
    +onAction : Callback.Callback<CustomEditor.AppAction,Unit> <- Callback.create(~Ref.Ref<Nat>,~CustomEditor.AppAction,~Unit,~counted,cycles)
    editor : Editor.Editor <- Editor.new(Editor.EditorTheme{paint,Select.SelectListTheme{paint,paint,paint,paint,paint}},None{})
    owner : Live.Owner <- Live.create(Component.ComponentId{1n},Editor.addToHistory(editor,"previous prompt"),Segmenter.Pending{"packages/runtime/data"},bindings(),Keys.defaults(),rows)
    run(Live.borrow(owner),cycles,onAction)
    Callback.dispose(String,String,paint)
    Callback.dispose(CustomEditor.AppAction,Unit,onAction)
    oldRows : Nat <- Ref.dispose(Nat,rows)
    oldCycles : Nat <- Ref.dispose(Nat,cycles)
    return Unit{}
