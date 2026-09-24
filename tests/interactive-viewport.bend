import Base
import ../packages/coding-agent/src/modes/interactive/viewport.bend as View
import ../packages/runtime/src/callback.bend as Callback
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/tui-base.bend as Tui
import ../packages/tui/src/utils.bend as Utils

def lines(value: List<&2,String>,_: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,value)
def ignore(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def focus(_: Unit,_: Bool) -> IO(Unit): IO.pure(Unit,Unit{})
def checked(value: Tui.ResultOf(Tui.TuiBase)) -> IO(Tui.TuiBase):
  match value:
    case Done{base}: IO.pure(Tui.TuiBase,base)
    case Fail{_}: IO.die(Tui.TuiBase,1,"viewport focus failed")
def mounted(pair: View.View & View.Handle & Tui.ResultOf(Tui.TuiBase)) -> IO(View.View & View.Handle & Tui.TuiBase):
  match pair:
    case (view,handle,result):
      do IO<View.View & View.Handle & Tui.TuiBase>:
        base : Tui.TuiBase <- checked(result)
        return (view,handle,base)
def clean(rows: List<&2,String>) -> List<&2,String>:
  match rows:
    case Nil{}: Nil{}
    case value <> rest: Utils.trimEnd(Utils.stripTerminalSequences(value)) <> clean(rest)
def frame(value: Tui.ResultOf(Tui.PreparedFrame)) -> IO(String):
  match value:
    case Done{Tui.PreparedFrame{_,_,rows,_}}: IO.pure(String,String.join(clean(rows),"|"))
    case Fail{_}: IO.die(String,1,"viewport render failed")
def same(+actual: String,expected: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),String.eq(actual,expected),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"viewport mismatch: " ++ actual))(Unit{})
def runMounted(view: View.View,+handle: View.Handle,+base: Tui.TuiBase,message: Component.Component) -> IO(Unit):
  do IO<Unit>:
        first : Tui.ResultOf(Tui.PreparedFrame) <- Tui.renderRoot(base,12n,8n)
        empty : String <- frame(first)
        same(empty,"|editor|footer")
        View.append(handle,message)
        second : Tui.ResultOf(Tui.PreparedFrame) <- Tui.renderRoot(base,12n,8n)
        filled : String <- frame(second)
        same(filled,"one|two|three|four||editor|footer")
        # An overflowing transcript keeps the line above the editor: upstream's
        # widgetContainerAbove is a plain Spacer(1) (parity scenario whats-new).
        overflow : Tui.ResultOf(Tui.PreparedFrame) <- Tui.renderRoot(base,12n,4n)
        short : String <- frame(overflow)
        same(short,"four||editor|footer")
        View.clear(handle)
        third : Tui.ResultOf(Tui.PreparedFrame) <- Tui.renderRoot(base,12n,8n)
        cleared : String <- frame(third)
        same(cleared,"|editor|footer")
        View.dispose(view)
def runPair(pair: View.View & View.Handle & Tui.TuiBase,message: Component.Component) -> IO(Unit):
  match pair:
    case (view,handle,base): runMounted(view,handle,base,message)
def main() -> IO(Unit):
  do IO<Unit>:
    +none : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    +onFocus : Callback.Callback<Bool,Unit> <- Callback.create(~Unit,~Bool,~Unit,~focus,Unit{})
    +messageRender : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~lines,"one" <> "two" <> "three" <> "four" <> Nil{})
    +editorRender : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~lines,"editor" <> Nil{})
    +footerRender : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~lines,"footer" <> Nil{})
    +message : Component.Component <- IO.pure(Component.Component,Component.Component{Component.ComponentId{4n},messageRender,None{},None{},none,None{},False{}})
    +editor : Component.Component <- IO.pure(Component.Component,Component.Component{Component.ComponentId{2n},editorRender,None{},None{},none,Some{onFocus},False{}})
    +footer : Component.Component <- IO.pure(Component.Component,Component.Component{Component.ComponentId{3n},footerRender,None{},None{},none,None{},False{}})
    view : View.View <- View.create(Component.ComponentId{1n})
    setup : View.View & View.Handle & Tui.ResultOf(Tui.TuiBase) <- View.mount(view,editor,footer)
    pair : View.View & View.Handle & Tui.TuiBase <- mounted(setup)
    runPair(pair,message)
    Callback.dispose(Nat,List<&2,String>,messageRender)
    Callback.dispose(Nat,List<&2,String>,editorRender)
    Callback.dispose(Nat,List<&2,String>,footerRender)
    Callback.dispose(Unit,Unit,none)
    Callback.dispose(Bool,Unit,onFocus)
    IO.print("interactive viewport retains editor and follows transcript")
