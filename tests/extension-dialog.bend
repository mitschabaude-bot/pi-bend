import Base
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/record.bend as Record
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/word-segmenter.bend as Words
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/keybindings.bend as Bindings
import ../packages/tui/src/keys.bend as Keys
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/coding-agent/src/modes/interactive/components/extension-dialog.bend as Dialog
import ../packages/coding-agent/src/modes/interactive/components/extension-selector.bend as Selector
import ../packages/coding-agent/src/modes/interactive/components/extension-input.bend as Input
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme

def blank(_: Unit,_: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,["editor"])
def ignore(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def signal(channel: Chan(Unit),_: Unit) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(Unit,channel,Unit{})
    return Unit{}
def accepted(value: Maybe<&1,Dialog.Answer()>,expected: String) -> Bool:
  match value:
    case Some{Some{answer}}: String.eq(answer,expected)
    case _: False{}
def cancelled(value: Maybe<&1,Dialog.Answer()>) -> Bool:
  match value: case Some{None{}}: True{} case _: False{}
def check(value: Bool,name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),value,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"FAIL " ++ name))(Unit{})
def hosted(borrowed: Dialog.Owner & Dialog.Host & Component.Component,render: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>,redraw: Callback.Callback<Unit,Unit>,+signalChannel: Chan(Unit),rows: Ref.Ref<Nat>,themeRef: Ref.Ref<Theme.Theme>) -> IO(Unit):
  match borrowed:
    case (owner,host,component):
      do IO<Unit>:
        +host : Dialog.Host <- IO.pure(Dialog.Host,host)
        +component : Component.Component <- IO.pure(Component.Component,component)
        +task : Chan(Dialog.Answer()) <- IO.fork(Dialog.Answer(),Dialog.select(host,Selector.create("Async",["chosen"],None{})))
        ready : Maybe<&1,Unit> <- Chan.recv(Unit,signalChannel)
        Component.handleInput(component,"\n")
        asyncAnswer : Maybe<&1,Dialog.Answer()> <- Chan.recv(Dialog.Answer(),task)
        check(accepted(asyncAnswer,"chosen"),"asynchronous selector")
        Chan.close(Dialog.Answer(),task)
        +first : Dialog.Reply() <- Chan.new(Dialog.Answer(),1)
        Dialog.replace(host,Dialog.Selecting{Selector.create("Pick",["one","two"],None{}),first})
        Component.handleInput(component,"j")
        Component.handleInput(component,"\n")
        choice : Maybe<&1,Dialog.Answer()> <- Chan.recv(Dialog.Answer(),first)
        check(accepted(choice,"two"),"select")
        Chan.close(Dialog.Answer(),first)
        +second : Dialog.Reply() <- Chan.new(Dialog.Answer(),1)
        Dialog.replace(host,Dialog.Typing{Input.create("Input","seed",None{}),second})
        Component.handleInput(component,"x")
        Component.handleInput(component,"\n")
        text : Maybe<&1,Dialog.Answer()> <- Chan.recv(Dialog.Answer(),second)
        check(accepted(text,"xseed"),"input")
        Chan.close(Dialog.Answer(),second)
        +third : Dialog.Reply() <- Chan.new(Dialog.Answer(),1)
        Dialog.replace(host,Dialog.Selecting{Selector.create("Replace",["old"],None{}),third})
        +fourth : Dialog.Reply() <- Chan.new(Dialog.Answer(),1)
        Dialog.replace(host,Dialog.Selecting{Selector.create("Current",["new"],None{}),fourth})
        replaced : Maybe<&1,Dialog.Answer()> <- Chan.recv(Dialog.Answer(),third)
        check(cancelled(replaced),"replacement cancels previous prompt")
        Chan.close(Dialog.Answer(),third)
        screen : List<&2,String> <- Component.render(component,32n)
        check(Bool.not(List.is_empty(&2,String,screen)),"mounted prompt renders")
        Component.handleInput(component,"\n")
        replacement : Maybe<&1,Dialog.Answer()> <- Chan.recv(Dialog.Answer(),fourth)
        check(accepted(replacement,"new"),"replacement receives input")
        Chan.close(Dialog.Answer(),fourth)
        +fifth : Dialog.Reply() <- Chan.new(Dialog.Answer(),1)
        Dialog.replace(host,Dialog.Selecting{Selector.create("Cancel",["one"],None{}),fifth})
        Dialog.close(host)
        dismissed : Maybe<&1,Dialog.Answer()> <- Chan.recv(Dialog.Answer(),fifth)
        check(cancelled(dismissed),"close cancels prompt")
        Chan.close(Dialog.Answer(),fifth)
        Dialog.dispose(owner)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(Unit,Unit,invalidate)
        Callback.dispose(Unit,Unit,redraw)
        Chan.close(Unit,signalChannel)
        oldRows : Nat <- Ref.dispose(Nat,rows)
        oldTheme : Theme.Theme <- Ref.dispose(Theme.Theme,themeRef)
        return Unit{}
def run(theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +themeRef : Ref.Ref<Theme.Theme> <- Ref.new(Theme.Theme,theme)
    +rows : Ref.Ref<Nat> <- Ref.new(Nat,24n)
    +signalChannel : Chan(Unit) <- Chan.new(Unit,16)
    +redraw : Callback.Callback<Unit,Unit> <- Callback.create(~Chan(Unit),~Unit,~Unit,~signal,signalChannel)
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Unit,~Nat,~List<&2,String>,~blank,Unit{})
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    +bindings : Bindings.KeybindingsManager <- IO.pure(Bindings.KeybindingsManager,Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),Record.new(List<&2,Keys.KeyId>)))
    owner : Dialog.Owner <- Dialog.create(Component.Component{Component.ComponentId{1n},render,None{},None{},invalidate,None{},False{}},themeRef,Words.Pending{"packages/runtime/data"},bindings,Keys.defaults(),rows,redraw)
    borrowed : Dialog.Owner & Dialog.Host & Component.Component <- IO.pure(Dialog.Owner & Dialog.Host & Component.Component,Dialog.borrow(owner))
    hosted(borrowed,render,invalidate,redraw,signalChannel,rows,themeRef)
def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Unit):
  match result: case Done{theme}: run(theme) case Fail{_}: IO.die(Unit,1,"dark theme missing")
def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.Palette256{})
    loaded(result)
