import Base
import ../packages/coding-agent/src/modes/interactive/components/tool-execution.bend as Tool
import ../packages/coding-agent/src/core/extensions/tool-render.bend as ToolRender
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/core/tools/edit.bend as Edit
import ../packages/coding-agent/src/core/tools/edit-diff.bend as Edits
import ../packages/coding-agent/src/core/tools/diff.bend as Diff
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/schema-value.bend as Value
import ../packages/runtime/src/record.bend as Record
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/tui-main-screen.bend as Screen
import ../packages/tui/src/utils.bend as Layout
import ../packages/ai/src/types.bend as Ai
import ./edit-preview.bend as Fixture

# Ports the three named contracts in pi-mono edit-tool-no-full-redraw.test.ts.
# Native rendering has an explicit owned preflight context instead of promises
# hidden inside a mutable JS component; Screen plans expose terminal writes.
def checked(condition: Bool,message: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),condition,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,message))(Unit{})
type Computation is Data: Computation{paths: Paths.Environment,calls: Ref.Ref<Nat>}
def computed(environment: Computation,request: Tool.PreviewRequest) -> IO(Edits.Preview()):
  match environment request:
    case Computation{paths,calls} Tool.PreviewRequest{cwd,Edit.EditToolInput{path,edits}}:
      do IO<Edits.Preview()>:
        Ref.modify(Nat,Unit,calls,count => (count + 1n,Unit{}))
        Edits.computeEditsDiff(paths,path,edits,cwd)
def requestCount(calls: Ref.Ref<Nat>,expected: Nat) -> IO(Unit):
  do IO<Unit>:
    actual : Nat <- Ref.read(Nat,calls)
    checked(Nat.is_eq(actual,expected),"preflight computed incomplete args, replay, or duplicated a request")
def notified(channel: Chan(Unit),_: Unit) -> IO(Unit):
  do IO<Unit>:
    delivered : Bool <- Chan.send(Unit,channel,Unit{})
    Ref.requireSent(delivered)
def waitPreview(channel: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    arrived : Maybe<&1,Unit> <- Chan.recv(Unit,channel)
    checked(Maybe.is_some(&1,Unit,arrived),"preflight stopped without notifying")
def args(path: String,edits: List<&2,Edits.Edit>) -> Value.Value:
  Value.ObjectValue{Record.Record{Record.Property{"path",Value.Text{path}} <> Record.Property{"edits",Value.ArrayValue{Edit.editValues(edits)}} <> Nil{}}}
def largeEdits(targets: List<&2,Nat>) -> List<&2,Edits.Edit>:
  match targets:
    case Nil{}: Nil{}
    case +n <> rest:
      Edits.Edit{"line " ++ Nat.show(n - 1n) ++ "\nline " ++ Nat.show(n) ++ "\nline " ++ Nat.show(n + 1n),"line " ++ Nat.show(n - 1n) ++ "\nline " ++ Nat.show(n) ++ " changed\nline " ++ Nat.show(n + 1n)} <> largeEdits(rest)
def clean(lines: List<&2,String>) -> String:
  match lines:
    case Nil{}: ""
    case line <> Nil{}: Layout.stripTerminalSequences(line)
    case line <> rest: Layout.stripTerminalSequences(line) ++ "\n" ++ clean(rest)
def planResult(result: Result<&2,&2,Screen.RenderError,Screen.Plan>) -> IO(Screen.Plan):
  match result:
    case Done{plan}: IO.pure(Screen.Plan,plan)
    case Fail{_}: IO.die(Screen.Plan,1,"invalid tool frame")
def history(n: Nat) -> List<&2,String>:
  match n:
    case Zero{}: Nil{}
    case Succ{+rest}: ("history " ++ Nat.show(rest)) <> history(rest)
def frame(previous: Screen.State,lines: List<&2,String>) -> IO(Screen.Plan):
  planResult(Screen.checkedPlan(previous,Screen.Frame{List.append(&2,String,history(200n),lines),None{},80n,24n},Screen.defaultOptions()))
def screenState(plan: Screen.Plan) -> Screen.State:
  match plan: case Screen.Plan{state,_,_}: state
def fullRedraws(plan: Screen.Plan) -> Nat:
  match plan: case Screen.Plan{Screen.State{_,_,count,_},_,_}: count
# Screen.nextEffect consumes a finite plan; its computed decrease is opaque to the checker.
@unsafe def writes(batch: Maybe<&2,Screen.Batch>) -> String:
  match batch:
    case None{}: ""
    case Some{Screen.Batch{Screen.Write{text},rest}}: text ++ writes(Screen.nextEffect(rest))
    case Some{Screen.Batch{_,rest}}: writes(Screen.nextEffect(rest))
def noClear(plan: Screen.Plan) -> IO(Unit):
  match plan:
    case Screen.Plan{_,output,None{}}: checked(Bool.not(String.contains(writes(Screen.nextEffect(output)),"\u{1b}[2J\u{1b}[H\u{1b}[3J")),"settling emitted a full clear")
    case _: IO.die(Unit,1,"settling requested a full redraw")
def details(preview: Edits.Preview()) -> IO(Tools.ToolDetails):
  match preview:
    case Done{Diff.DiffResult{diff,first}}: IO.pure(Tools.ToolDetails,Tools.EditDetails{Edit.EditToolDetails{diff,"",first}})
    case Fail{message}: IO.die(Tools.ToolDetails,1,message)
def settled(+handle: Tool.Handle,preview: Tools.ToolDetails) -> IO(Unit):
  do IO<Unit>:
    current : Tool.ToolExecution <- Tool.current(handle)
    Tool.set(handle,Tool.updateResult(current,ToolRender.ToolResult{Ai.TextImageText{Ai.TextContent{"Successfully replaced blocks.",None{}}} <> Nil{},False{},Some{preview}},False{}))
def largeMounted(pair: Tool.Owner & Component.Component & Tool.Handle,+context: Tool.ToolContext,channel: Chan(Unit),+paths: Paths.Environment,+cwd: String,+edits: List<&2,Edits.Edit>) -> IO(Unit):
  match pair:
    case (owner,component,handle):
      do IO<Unit>:
        +draw : Component.Component = component
        +mounted : Tool.Handle = handle
        initial : List<&2,String> <- Component.render(draw,80n)
        initialPlan : Screen.Plan <- frame(Screen.initial(),initial)
        current : Tool.ToolExecution <- Tool.current(mounted)
        Tool.set(mounted,Tool.setArgsComplete(current))
        waitPreview(channel)
        +previewLines : List<&2,String> <- Component.render(draw,80n)
        +display : String = clean(previewLines)
        checked(String.contains(display,"edit") && String.contains(display,"line 50 changed") && String.contains(display,"line 950 changed"),"large call preview lost distant edits")
        +before : Screen.Plan <- frame(screenState(initialPlan),previewLines)
        preview : Edits.Preview() <- Edits.computeEditsDiff(paths,"large.txt",edits,cwd)
        result : Tools.ToolDetails <- details(preview)
        settled(mounted,result)
        +finalLines : List<&2,String> <- Component.render(draw,80n)
        +after : Screen.Plan <- frame(screenState(before),finalLines)
        checked(Nat.is_eq(fullRedraws(before),fullRedraws(after)),"result increased full redraw count")
        noClear(after)
        checked(String.eq(display,clean(finalLines)),"settled diff moved or changed")
        checked(Bool.not(String.contains(clean(finalLines),"Successfully replaced")),"success text duplicated diff")
        Tool.dispose(owner)
        IO.print("renders the large diff in the call preview and does not full-redraw when the result settles")
def largeCase(+context: Tool.ToolContext,channel: Chan(Unit),+paths: Paths.Environment,+cwd: String,theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +edits : List<&2,Edits.Edit> = largeEdits(50n <> 150n <> 250n <> 350n <> 450n <> 550n <> 650n <> 750n <> 850n <> 950n <> Nil{})
    owner : Tool.Owner <- Tool.createWithContext(Component.ComponentId{1n},Tool.new("edit","large",args("large.txt",edits),theme,Tool.Generic{}),Some{context})
    largeMounted(Tool.borrow(owner),context,channel,paths,cwd,edits)
def historicalDetails(details: Tools.ToolDetails) -> Tools.ToolDetails:
  match details:
    case Tools.EditDetails{Edit.EditToolDetails{diff,_,_}}: Tools.RawDetails{Value.ObjectValue{Record.Record{Record.Property{"diff",Value.Text{diff}} <> Nil{}}}}
    case details: details
def historicalMounted(pair: Tool.Owner & Component.Component & Tool.Handle,details: Tools.ToolDetails,expected: String) -> IO(Unit):
  match pair:
    case (owner,component,handle):
      do IO<Unit>:
        settled(handle,Tools.restoreDetails("edit",historicalDetails(details)))
        rows : List<&2,String> <- Component.render(component,80n)
        checked(String.eq(String.join(rows,"\n"),expected),"historical edit metadata lost its saved diff or colors")
        Tool.dispose(owner)
def replayMounted(pair: Tool.Owner & Component.Component & Tool.Handle,+result: Tools.ToolDetails,theme: Theme.Theme) -> IO(Unit):
  match pair:
    case (owner,component,handle):
      do IO<Unit>:
        settled(handle,result)
        +lines : List<&2,String> <- Component.render(component,80n)
        +display : String = clean(lines)
        checked(String.contains(display,"line 50 changed") && String.contains(display,"line 150 changed"),"saved result needs its deleted source file")
        +legacyArgs : Value.Value = Value.ObjectValue{Record.Record{Record.Property{"path",Value.Text{"replay.txt"}} <> Record.Property{"oldText",Value.Text{"before"}} <> Record.Property{"newText",Value.Text{"after"}} <> Nil{}}}
        legacy : Tool.Owner <- Tool.create(Component.ComponentId{12n},Tool.new("edit","historical",legacyArgs,theme,Tool.Generic{}))
        historicalMounted(Tool.borrow(legacy),result,String.join(lines,"\n"))
        Tool.dispose(owner)
        IO.print("reconstructs the boxed preview from a settled result without argsComplete")
def replayCase(+context: Tool.ToolContext,+paths: Paths.Environment,+cwd: String,+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +edits : List<&2,Edits.Edit> = largeEdits(50n <> 150n <> Nil{})
    preview : Edits.Preview() <- Edits.computeEditsDiff(paths,"replay.txt",edits,cwd)
    result : Tools.ToolDetails <- details(preview)
    removed : Result<&2,&2,FS.Error,Unit> <- FS.remove(cwd ++ "/replay.txt",False{},False{})
    owner : Tool.Owner <- Tool.createWithContext(Component.ComponentId{2n},Tool.new("edit","replay",args("replay.txt",edits),theme,Tool.Generic{}),Some{context})
    replayMounted(Tool.borrow(owner),result,theme)
def errorMounted(pair: Tool.Owner & Component.Component & Tool.Handle,channel: Chan(Unit)) -> IO(Unit):
  match pair:
    case (owner,component,handle):
      do IO<Unit>:
        +draw : Component.Component = component
        +mounted : Tool.Handle = handle
        current : Tool.ToolExecution <- Tool.current(mounted)
        Tool.set(mounted,Tool.setArgsComplete(current))
        waitPreview(channel)
        lines : List<&2,String> <- Component.render(draw,80n)
        +display : String = clean(lines)
        checked(String.contains(display,"Could not find"),"preflight error missing")
        checked(Bool.not(String.contains(display,"+1 ")) && Bool.not(String.contains(display,"-1 ")),"failed preflight displayed a diff")
        Tool.dispose(owner)
        IO.print("shows a preflight error without rendering a diff when the edits do not apply")
def errorCase(context: Tool.ToolContext,channel: Chan(Unit),theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    edits : List<&2,Edits.Edit> = Edits.Edit{"does not exist","replacement"} <> Nil{}
    owner : Tool.Owner <- Tool.createWithContext(Component.ComponentId{3n},Tool.new("edit","error",args("error.txt",edits),theme,Tool.Generic{}),Some{context})
    errorMounted(Tool.borrow(owner),channel)
# Controlled completions exercise A -> B -> A without timing assumptions.
# Disposal joins the first read, then the external notification count proves
# it could not publish over the newer revision, despite equal arguments.
type Race is Data: Race{calls: Ref.Ref<Nat>,entered: Chan(Unit),release: Chan(Unit)}
type Notices is Data: Notices{count: Ref.Ref<Nat>,ready: Chan(Unit)}
def raceFinished(entered: Chan(Unit),release: Chan(Unit),index: Nat) -> IO(Edits.Preview()):
  match index:
    case Zero{}:
      do IO<Edits.Preview()>:
        delivered : Bool <- Chan.send(Unit,entered,Unit{})
        Ref.requireSent(delivered)
        waitPreview(release)
        return Done{Diff.DiffResult{"+1 stale-preview",Some{1n}}}
    case _: IO.pure(Edits.Preview(),Done{Diff.DiffResult{"+1 latest-preview",Some{1n}}})
def raceComputed(environment: Race,_: Tool.PreviewRequest) -> IO(Edits.Preview()):
  match environment:
    case Race{calls,entered,release}:
      do IO<Edits.Preview()>:
        index : Nat <- Ref.modify(Nat,Nat,calls,+count => (count + 1n,count))
        raceFinished(entered,release,index)
def raceNotified(environment: Notices,_: Unit) -> IO(Unit):
  match environment:
    case Notices{count,ready}:
      do IO<Unit>:
        Ref.modify(Nat,Unit,count,n => (n + 1n,Unit{}))
        notified(ready,Unit{})
def raceMounted(pair: Tool.Owner & Component.Component & Tool.Handle,+original: Value.Value,entered: Chan(Unit),release: Chan(Unit),+ready: Chan(Unit),calls: Ref.Ref<Nat>,+notices: Ref.Ref<Nat>) -> IO(Unit):
  match pair:
    case (owner,component,handle):
      do IO<Unit>:
        +draw : Component.Component = component
        +mounted : Tool.Handle = handle
        current : Tool.ToolExecution <- Tool.current(mounted)
        Tool.set(mounted,Tool.setArgsComplete(current))
        waitPreview(entered)
        changing : Tool.ToolExecution <- Tool.current(mounted)
        Tool.set(mounted,Tool.updateArgs(changing,args("other.txt",Edits.Edit{"x","y"} <> Nil{})))
        waitPreview(ready)
        restoring : Tool.ToolExecution <- Tool.current(mounted)
        Tool.set(mounted,Tool.updateArgs(restoring,original))
        waitPreview(ready)
        lines : List<&2,String> <- Component.render(draw,80n)
        checked(String.contains(clean(lines),"latest-preview"),"newest input did not publish its preview")
        requestCount(notices,2n)
        released : Bool <- Chan.send(Unit,release,Unit{})
        Ref.requireSent(released)
        Tool.dispose(owner)
        requestCount(calls,3n)
        requestCount(notices,2n)
        IO.print("input revisions discard old completions and disposal joins owned reads")
def raceCase(cwd: String,theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +calls : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +notices : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +entered : Chan(Unit) <- Chan.new(Unit,1)
    +release : Chan(Unit) <- Chan.new(Unit,1)
    +ready : Chan(Unit) <- Chan.new(Unit,8)
    +compute : Callback.Callback<Tool.PreviewRequest,Edits.Preview()> <- Callback.create(~Race,~Tool.PreviewRequest,~Edits.Preview(),~raceComputed,Race{calls,entered,release})
    +notify : Callback.Callback<Unit,Unit> <- Callback.create(~Notices,~Unit,~Unit,~raceNotified,Notices{notices,ready})
    +redraw : Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Unit,Unit>>,Some{notify})
    +original : Value.Value = args("same.txt",Edits.Edit{"x","y"} <> Nil{})
    owner : Tool.Owner <- Tool.createWithContext(Component.ComponentId{4n},Tool.new("edit","race",original,theme,Tool.Generic{}),Some{Tool.ToolContext{cwd,compute,redraw,None{},None{},None{}}})
    raceMounted(Tool.borrow(owner),original,entered,release,ready,calls,notices)
    Callback.dispose(Tool.PreviewRequest,Edits.Preview(),compute)
    retired : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw)
    Callback.dispose(Unit,Unit,notify)
    retiredCalls : Nat <- Ref.dispose(Nat,calls)
    retiredNotices : Nat <- Ref.dispose(Nat,notices)
    Chan.close(Unit,entered)
    Chan.close(Unit,release)
    Chan.close(Unit,ready)
def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Theme.Theme):
  match result:
    case Done{theme}: IO.pure(Theme.Theme,theme)
    case Fail{_}: IO.die(Theme.Theme,1,"theme load failed")
def run(arguments: List<String>) -> IO(Unit):
  match arguments:
    case +cwd <> Nil{}:
      do IO<Unit>:
        +paths : Paths.Environment = Fixture.environment(cwd,cwd)
        +calls : Ref.Ref<Nat> <- Ref.new(Nat,0n)
        +compute : Callback.Callback<Tool.PreviewRequest,Edits.Preview()> <- Callback.create(~Computation,~Tool.PreviewRequest,~Edits.Preview(),~computed,Computation{paths,calls})
        +channel : Chan(Unit) <- Chan.new(Unit,8)
        +notify : Callback.Callback<Unit,Unit> <- Callback.create(~Chan(Unit),~Unit,~Unit,~notified,channel)
        +redraw : Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Unit,Unit>>,Some{notify})
        +context : Tool.ToolContext = Tool.ToolContext{cwd,compute,redraw,None{},None{},None{}}
        ready : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.Palette256{})
        +theme : Theme.Theme <- loaded(ready)
        largeCase(context,channel,paths,cwd,theme)
        requestCount(calls,1n)
        replayCase(context,paths,cwd,theme)
        requestCount(calls,1n)
        errorCase(context,channel,theme)
        requestCount(calls,2n)
        raceCase(cwd,theme)
        Callback.dispose(Tool.PreviewRequest,Edits.Preview(),compute)
        retiredCalls : Nat <- Ref.dispose(Nat,calls)
        retired : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw)
        Callback.dispose(Unit,Unit,notify)
        Chan.close(Unit,channel)
    case _: IO.die(Unit,1,"expected fixture directory")
def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    run(arguments)
