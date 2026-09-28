import Base
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref
import ../packages/tui/src/component.bend as Component
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx
import ../packages/coding-agent/src/modes/interactive/components/extension-widgets.bend as Widgets
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme

def editor(_: Unit,_: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,["editor"])
def customRow(_: Unit,_: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,["custom"])
def ignore(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
type FactoryEnv is Data: FactoryEnv{render: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>,retired: Ref.Ref<Bool>}
def customFactory(env: FactoryEnv,_: Unit) -> IO(Component.Owner):
  match env:
    case FactoryEnv{render,invalidate,retired}:
      IO.pure(Component.Owner,Component.Owner{Component.Component{Component.ComponentId{1001n},render,None{},None{},invalidate,None{},False{}},_ => Ref.write(Bool,retired,True{})})
def check(ok: Bool,name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),ok,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"FAIL " ++ name))(Unit{})
def contains(rows: List<&2,String>,text: String) -> Bool: String.contains(String.join(rows,"\n"),text)
def renderMounted(mounted: Ref.Ref<Component.Component>) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    component : Component.Component <- Ref.read(Component.Component,mounted)
    Component.render(component,40n)
def exercise(borrowed: Widgets.Owner & Widgets.Host & Component.Component,theme: Ref.Ref<Theme.Theme>,render: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>,redraw: Callback.Callback<Unit,Unit>) -> IO(Unit):
  match borrowed:
    case (owner,+host,component):
      do IO<Unit>:
        +mounted : Ref.Ref<Component.Component> <- Ref.new(Component.Component,component)
        initial : List<&2,String> <- renderMounted(mounted)
        check(contains(initial,"editor"),"initial editor")
        Widgets.setWidget(host,Ctx.WidgetUpdate{"above",Some{Ctx.WidgetLines{["first"]}},None{}})
        Widgets.setWidget(host,Ctx.WidgetUpdate{"below",Some{Ctx.WidgetLines{["last"]}},Some{Ctx.BelowEditor{}}})
        +shown : List<&2,String> <- renderMounted(mounted)
        check(contains(shown,"first") && contains(shown,"editor") && contains(shown,"last"),"above and below")
        Widgets.setWidget(host,Ctx.WidgetUpdate{"above",Some{Ctx.WidgetLines{["replacement"]}},None{}})
        +replaced : List<&2,String> <- renderMounted(mounted)
        check(contains(replaced,"replacement") && Bool.not(contains(replaced,"first")),"replace by key")
        Widgets.setWidget(host,Ctx.WidgetUpdate{"above",None{},None{}})
        +removed : List<&2,String> <- renderMounted(mounted)
        check(Bool.not(contains(removed,"replacement")) && contains(removed,"last"),"remove by key")
        +retiredFlag : Ref.Ref<Bool> <- Ref.new(Bool,False{})
        +customRender : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Unit,~Nat,~List<&2,String>,~customRow,Unit{})
        +customInvalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
        +factory : Ctx.WidgetFactory() <- Callback.create(~FactoryEnv,~Unit,~Component.Owner,~customFactory,FactoryEnv{customRender,customInvalidate,retiredFlag})
        Widgets.setWidget(host,Ctx.WidgetUpdate{"custom",Some{Ctx.WidgetComponent{factory}},None{}})
        custom : List<&2,String> <- renderMounted(mounted)
        check(contains(custom,"custom"),"factory component")
        Widgets.setWidget(host,Ctx.WidgetUpdate{"custom",None{},None{}})
        retired : Bool <- Ref.read(Bool,retiredFlag)
        check(retired,"replaced component retires")
        Widgets.dispose(owner)
        Callback.dispose(Unit,Component.Owner,factory)
        Callback.dispose(Nat,List<&2,String>,customRender)
        Callback.dispose(Unit,Unit,customInvalidate)
        flag : Bool <- Ref.dispose(Bool,retiredFlag)
        retired : Component.Component <- Ref.dispose(Component.Component,mounted)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(Unit,Unit,invalidate)
        Callback.dispose(Unit,Unit,redraw)
        old : Theme.Theme <- Ref.dispose(Theme.Theme,theme)
        return Unit{}
def run(theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +themeRef : Ref.Ref<Theme.Theme> <- Ref.new(Theme.Theme,theme)
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Unit,~Nat,~List<&2,String>,~editor,Unit{})
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    +redraw : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    owner : Widgets.Owner <- Widgets.create(Component.Component{Component.ComponentId{2n},render,None{},None{},invalidate,None{},False{}},themeRef,redraw)
    borrowed : Widgets.Owner & Widgets.Host & Component.Component <- IO.pure(Widgets.Owner & Widgets.Host & Component.Component,Widgets.borrow(owner))
    exercise(borrowed,themeRef,render,invalidate,redraw)
def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Unit):
  match result: case Done{theme}: run(theme) case Fail{_}: IO.die(Unit,1,"dark theme missing")
def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.Palette256{})
    loaded(result)
