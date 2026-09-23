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

def identity(ignored: Unit,value: String) -> IO(String): IO.pure(String,value)
def submitted(output: Ref.Ref<List<&2,String>>,value: String) -> IO(Unit):
  Ref.modify(List<&2,String>,Unit,output,values => (value <> values,Unit{}))
def check(value: Bool,message: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),value,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,message))(Unit{})
def run(owner: Live.Owner,+component: Component.Component,+handle: Live.Handle,rows: Ref.Ref<Nat>,output: Ref.Ref<List<&2,String>>) -> IO(Unit):
  do IO<Unit>:
    Component.setFocused(component,True{})
    initial : List<&2,String> <- Component.render(component,40n)
    check(Nat.is_gt(List.length(&2,String,initial),0n),"editor rendered no lines")
    Ref.write(Nat,rows,12n)
    Component.handleInput(component,"h")
    Component.handleInput(component,"i")
    current : String <- Live.text(handle)
    check(String.eq(current,"hi"),"editor input was not retained")
    Component.handleInput(component,"\r")
    values : List<&2,String> <- Ref.read(List<&2,String>,output)
    check(String.eq(Maybe.default(&2,String,List.get(&2,String,values,0n),""),"hi"),"submit callback was not delivered")
    error : Maybe<&2,Editor.Error> <- Live.lastError(handle)
    check(Maybe.is_none(&2,Editor.Error,error),"editor input returned an error")
    Live.dispose(owner)
def borrowed(pair: Live.Owner & Component.Component & Live.Handle,rows: Ref.Ref<Nat>,output: Ref.Ref<List<&2,String>>) -> IO(Unit):
  match pair:
    case (owner,component,handle): run(owner,component,handle,rows,output)
def runLoaded(words: Segmenter.Context) -> IO(Unit):
  do IO<Unit>:
    +rows : Ref.Ref<Nat> <- Ref.new(Nat,24n)
    +output : Ref.Ref<List<&2,String>> <- Ref.new(List<&2,String>,Nil{})
    +paint : Callback.Callback<String,String> <- Callback.create(~Unit,~String,~String,~identity,Unit{})
    +submit : Callback.Callback<String,Unit> <- Callback.create(~Ref.Ref<List<&2,String>>,~String,~Unit,~submitted,output)
    editor : Editor.Editor <- Editor.new(Editor.EditorTheme{paint,Select.SelectListTheme{paint,paint,paint,paint,paint}},None{})
    owner : Live.Owner <- Live.create(Component.ComponentId{1n},Editor.setCallbacks(editor,Editor.EditorCallbacks{None{},Some{submit},None{}}),words,Keybindings.create(Keybindings.TUI_KEYBINDINGS(),Record.new(List<&2,Keys.KeyId>)),Keys.defaults(),rows)
    borrowed(Live.borrow(owner),rows,output)
    Callback.dispose(String,String,paint)
    Callback.dispose(String,Unit,submit)
    oldRows : Nat <- Ref.dispose(Nat,rows)
    oldOutput : List<&2,String> <- Ref.dispose(List<&2,String>,output)
    IO.print("editor component rendered, accepted input and submitted")
def loaded(result: Segmenter.Loaded(Segmenter.Context)) -> IO(Unit):
  match result:
    case Done{words}: runLoaded(words)
    case Fail{_}: IO.die(Unit,1,"word assets did not load")
def main() -> IO(Unit):
  do IO<Unit>:
    words : Segmenter.Loaded(Segmenter.Context) <- Segmenter.loadDefault("packages/runtime/data")
    loaded(words)
