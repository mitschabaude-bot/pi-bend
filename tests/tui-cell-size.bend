import Base
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/deferred.bend as Deferred
import ../packages/runtime/src/ref.bend as Ref
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/terminal.bend as Terminal
import ../packages/tui/src/terminal-image.bend as Image
import ../packages/tui/src/terminal-query.bend as Query
import ../packages/tui/src/tui-base.bend as Tui
import ../packages/tui/src/tui-main-screen.bend as Screen
import ../packages/tui/src/tui-process.bend as Process

# upstream test/tui-cell-size-input.test.ts through a real terminal
# (tests/tui_cell_size_check.py): an InputRecorder is focused; each input it
# receives is reported as "input:<codepoints>", and "q" stops the TUI after
# reporting the current cell dimensions. Invalidations are reported too.
type Recorder is Data: Recorder{stop: Deferred.Deferred<Unit>,queries: Ref.Ref<Maybe<&2,Query.Handle>>}
def render(unused: Unit,width: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,"" <> Nil{})
def invalidate(unused: Unit,value: Unit) -> IO(Unit): IO.print_err("invalidated")
def codes(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{point},rest}: U32.show(point) ++ " " ++ codes(rest)
def show(value: F64) -> String: U32.show(F64.to_u32(value))
def cellsShown(value: Image.CellDimensions) -> IO(Unit):
  match value:
    case Image.CellDimensions{width,height}: IO.print_err("cells:" ++ show(width) ++ "x" ++ show(height))
def cells(queries: Maybe<&2,Query.Handle>) -> IO(Unit):
  match queries:
    case None{}: IO.print_err("cells:unknown")
    case Some{handle}:
      do IO<Unit>:
        value : Image.CellDimensions <- Query.getCellDimensions(handle)
        cellsShown(value)
def stopped(recorder: Recorder,+key: String) -> IO(Unit):
  match recorder:
    case Recorder{stop,queries}:
      Bool.pick(Unit -> IO(Unit),String.eq(key,"q"),
        _ => do IO<Unit>:
          handle : Maybe<&2,Query.Handle> <- Ref.read(Maybe<&2,Query.Handle>,queries)
          cells(handle)
          settled : Bool <- Deferred.resolve(Unit,stop,Unit{})
          return Unit{},
        _ => IO.pure(Unit,Unit{}))(Unit{})
def record(recorder: Recorder,data: String) -> IO(Unit):
  do IO<Unit>:
    +key : String <- IO.pure(String,data)
    IO.print_err("input:" ++ codes(key))
    stopped(recorder,key)
def ready(queries: Ref.Ref<Maybe<&2,Query.Handle>>,value: Process.QueryReady) -> IO(Unit):
  match value:
    case Process.QueryReady{handle,_,_,_,_}: Ref.write(Maybe<&2,Query.Handle>,queries,Some{handle})
def requireFocus(result: Tui.ResultOf(Tui.TuiBase)) -> IO(Tui.TuiBase):
  match result:
    case Fail{_}: IO.die(Tui.TuiBase,1,"focus rejected")
    case Done{tui}: IO.pure(Tui.TuiBase,tui)
def prepare(+component: Component.Component) -> IO(Process.Active):
  do IO<Process.Active>:
    focused : Tui.ResultOf(Tui.TuiBase) <- Tui.setFocus(Tui.added(Tui.newTui(),component),component <> Nil{},Component.id(component) <> Nil{},Some{Component.id(component)})
    tui : Tui.TuiBase <- requireFocus(focused)
    return Process.active(Process.Session{tui,Process.Main{Screen.initial()}},component <> Nil{},Component.id(component) <> Nil{})
def requireRun(value: Result<&2,&2,Terminal.Error,Process.Active>) -> IO(Unit):
  match value:
    case Done{Process.Active{_,_,_,None{},_,_}}: IO.print_err("done")
    case _: IO.die(Unit,1,"cell size process failed")
def main() -> IO(Unit):
  do IO<Unit>:
    +stop : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +queries : Ref.Ref<Maybe<&2,Query.Handle>> <- Ref.new(Maybe<&2,Query.Handle>,None{})
    +renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Unit,~Nat,~List<&2,String>,~render,Unit{})
    +inputCallback : Callback.Callback<String,Unit> <- Callback.create(~Recorder,~String,~Unit,~record,Recorder{stop,queries})
    +invalidateCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~invalidate,Unit{})
    +readyCallback : Callback.Callback<Process.QueryReady,Unit> <- Callback.create(~Ref.Ref<Maybe<&2,Query.Handle>>,~Process.QueryReady,~Unit,~ready,queries)
    state : Process.Active <- prepare(Component.Component{Component.ComponentId{1n},renderCallback,Some{inputCallback},None{},invalidateCallback,None{},False{}})
    result : Result<&2,&2,Terminal.Error,Process.Active> <- Process.runProcessWithQueries(state,stop,False{},readyCallback)
    requireRun(result)
    Callback.dispose(Process.QueryReady,Unit,readyCallback)
    Callback.dispose(Nat,List<&2,String>,renderCallback)
    Callback.dispose(String,Unit,inputCallback)
    Callback.dispose(Unit,Unit,invalidateCallback)
    Deferred.dispose(Unit,stop)
    old : Maybe<&2,Query.Handle> <- Ref.dispose(Maybe<&2,Query.Handle>,queries)
    return Unit{}
