import Base
import ../packages/coding-agent/src/modes/interactive/components/header.bend as Header
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/core/diagnostics.bend as D
import ../packages/coding-agent/src/core/skills.bend as Skills
import ../packages/runtime/src/ref.bend as R
import ../packages/tui/src/component.bend as Component

def cases() -> List<&2,Header.ExtensionIssue>:
  [Header.ExtensionIssue{D.warning("Reserved key is skipped","/home/agent/.pi/agent/extension.bend"),Some{Skills.SourceInfo{"/home/agent/.pi/agent/extension.bend","local",Skills.User{},Skills.TopLevel{},None{}}}},
   Header.ExtensionIssue{D.warning("Later extension wins","/project/.pi/extension.bend"),Some{Skills.SourceInfo{"/project/.pi/extension.bend","local",Skills.Project{},Skills.TopLevel{},None{}}}},
   Header.ExtensionIssue{D.warning("Clipboard override","<inline:demo>"),Some{Skills.SourceInfo{"<inline:demo>","inline",Skills.Temporary{},Skills.TopLevel{},None{}}}},
   Header.ExtensionIssue{D.ResourceDiagnostic{D.Error{},"Handler error",Some{"/tmp/extension.bend"},None{}},Some{Skills.SourceInfo{"/tmp/extension.bend","cli",Skills.Temporary{},Skills.TopLevel{},None{}}}},
   Header.ExtensionIssue{D.ResourceDiagnostic{D.Warning{},"Unattributed warning",None{},None{}},None{}}]
def check(value: Bool,message: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),value,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,message))(Unit{})
def quiet(pair: Header.Owner & Component.Component & Header.Handle) -> IO(Unit):
  match pair:
    case (owner,component,handle):
      do IO<Unit>:
        +component : Component.Component <- IO.pure(Component.Component,component)
        +handle : Header.Handle <- IO.pure(Header.Handle,handle)
        Header.setExtensionIssues(handle,cases())
        +initial : List<&2,String> <- Component.render(component,1000n)
        check(String.contains(String.join(initial,"\n"),"[Extension issues]"),"quiet startup hid diagnostics")
        Header.setResources(handle,Nil{},Nil{})
        refreshed : List<&2,String> <- Component.render(component,1000n)
        check(String.eq(String.join(initial,"\n"),String.join(refreshed,"\n")),"resource refresh lost diagnostics")
        Header.setExtensionIssues(handle,Nil{})
        cleared : List<&2,String> <- Component.render(component,1000n)
        check(Nat.is_eq(List.length(&2,String,cleared),0n),"quiet startup retained cleared diagnostics")
        Header.dispose(owner)
def run(result: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"cannot load theme")
    case Done{+theme}:
      do IO<Unit>:
        text : String <- Header.issueText(theme,cases(),Some{"/home/agent"})
        IO.print(text)
        +current : R.Ref<Theme.Theme> <- R.new(Theme.Theme,theme)
        owner : Header.Owner <- Header.create(current,True{},"/project",Some{"/home/agent"},Nil{},Nil{},"build/no-header-themes")
        quiet(Header.borrow(owner))
        old : Theme.Theme <- R.dispose(Theme.Theme,current)
        return Unit{}
def main() -> IO(Unit):
  do IO<Unit>:
    theme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.TrueColor{})
    run(theme)
