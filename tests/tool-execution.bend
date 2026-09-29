import Base
import ../packages/coding-agent/src/modes/interactive/components/tool-execution.bend as Tool
import ../packages/coding-agent/src/core/extensions/tool-render.bend as ToolRender
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/runtime/src/schema-value.bend as Value
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/callback.bend as Callback
import ../packages/ai/src/types.bend as Ai
import ../packages/agent/src/types.bend as Agent
import ../packages/tui/src/utils.bend as U
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/tui.bend as Tui
import ../packages/runtime/src/ref.bend as Ref
import ../packages/tui/src/terminal-image.bend as TerminalImage
import ../packages/runtime/src/f64.bend as F
import ../packages/coding-agent/src/core/tools/renderers/read.bend as ReadRenderer
import ../packages/coding-agent/src/core/tools/edit-diff.bend as Edits
import ./edit-preview.bend as Fixture

def loaded(value: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Theme.Theme):
  match value: case Done{theme}: IO.pure(Theme.Theme,theme) case Fail{_}: IO.die(Theme.Theme,1,"theme load failed")
def output(label: String,lines: List<&2,String>) -> IO(Unit): IO.print(label ++ "\u{1e}" ++ String.join(lines,"\u{1f}"))
def show(label: String,state: Tool.ToolExecution) -> IO(Unit):
  do IO<Unit>:
    lines : List<&2,String> <- Tool.render(state,28n)
    output(label,lines)
def showWide(label: String,state: Tool.ToolExecution) -> IO(Unit):
  do IO<Unit>:
    lines : List<&2,String> <- Tool.render(state,80n)
    output(label,lines)
def showImage(label: String,state: Tool.ToolExecution,context: Tool.ToolContext) -> IO(Unit):
  do IO<Unit>:
    lines : List<&2,String> <- Tool.renderWithPreview(state,28n,None{},None{},None{},Some{context},None{})
    output(label,lines)
def text(value: String) -> Ai.TextImageContent: Ai.TextImageText{Ai.TextContent{value,None{}}}
def result(value: String,error: Bool) -> ToolRender.ToolResult: ToolRender.ToolResult{text(value) <> Nil{},error,None{}}
def pixel() -> String: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="
def imageResult() -> ToolRender.ToolResult:
  ToolRender.ToolResult{text("picture") <> Ai.TextImageImage{Ai.ImageContent{pixel(),"image/png"}} <> Nil{},False{},None{}}
def builtinArgs(name: String) -> Value.Value:
  match name:
    case "bash": Value.ObjectValue{R.Record{R.Property{"command",Value.Text{"printf hello"}} <> Nil{}}}
    case "write": Value.ObjectValue{R.Record{R.Property{"path",Value.Text{"notes.txt"}} <> R.Property{"content",Value.Text{"one\ntwo"}} <> Nil{}}}
    case _: Value.ObjectValue{R.Record{R.Property{"path",Value.Text{"notes.txt"}} <> Nil{}}}
def ensure(yes: Bool,label: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),yes,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,label))(Unit{})
def builtin(+name: String,+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +pending : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new(name,name,builtinArgs(name),theme,Tool.Generic{}))
    show(name ++ "-pending",pending)
    +partial : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.updateResult(pending,result("one\ntwo\nthree",False{}),True{}))
    show(name ++ "-partial",partial)
    +final : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.updateResult(partial,result("one\ntwo\nthree",False{}),False{}))
    show(name ++ "-final",final)
    show(name ++ "-error",Tool.updateResult(final,result("bad input",True{}),False{}))
def sameBashDisplay(builtin: Tool.ToolExecution,alias: Tool.ToolExecution,label: String) -> IO(Unit):
  do IO<Unit>:
    first : List<&2,String> <- Tool.renderWithDuration(builtin,80n,Some{F.fromU32(1500)},None{})
    second : List<&2,String> <- Tool.renderWithDuration(alias,80n,Some{F.fromU32(1500)},None{})
    ensure(String.eq(String.join(first,"\n"),String.join(second,"\n")),"renamed Bash display differs from built-in: " ++ label)
def bashAlias(+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +args : Value.Value <- IO.pure(Value.Value,builtinArgs("bash"))
    +builtin : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("bash","original",args,theme,Tool.Generic{}))
    +alias : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("run_shell","alias",args,theme,Tool.NativeBuiltin{"bash"}))
    +partialText : ToolRender.ToolResult <- IO.pure(ToolRender.ToolResult,result("one\ntwo\nthree\nfour\nfive\nsix",False{}))
    +running : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.updateResult(builtin,partialText,True{}))
    +aliasRunning : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.updateResult(alias,partialText,True{}))
    +done : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.updateResult(running,partialText,False{}))
    +aliasDone : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.updateResult(aliasRunning,partialText,False{}))
    pendingCheck : Unit <- sameBashDisplay(builtin,alias,"pending")
    runningCheck : Unit <- sameBashDisplay(running,aliasRunning,"streaming")
    completeCheck : Unit <- sameBashDisplay(done,aliasDone,"completed")
    expandedCheck : Unit <- sameBashDisplay(Tool.setExpanded(done,True{}),Tool.setExpanded(aliasDone,True{}),"expanded")
    sameBashDisplay(Tool.updateResult(done,result("failed",True{}),False{}),Tool.updateResult(aliasDone,result("failed",True{}),False{}),"error")
def args1() -> Value.Value: Value.ObjectValue{R.Record{R.Property{"path",Value.Text{"notes.txt"}} <> Nil{}}}
def args2() -> Value.Value: Value.ObjectValue{R.Record{R.Property{"path",Value.Text{"notes.txt"}} <> R.Property{"limit",Value.Number{F64{1073741824,0}}} <> Nil{}}}
@unsafe def lines(+from: Nat,count: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match count:
    case Zero{}: List.reverse(&2,String,reversed)
    case Succ{rest}: lines(from + 1n,rest,("line-" ++ Nat.show(from)) <> reversed)
def draw(label: String,context: ToolRender.RenderContext) -> IO(ToolRender.RenderResult()):
  match context:
    case ToolRender.RenderContext{_,_,_,_,_,_,_,_,width,_,_,_,_}:
      +label = {label: String}
      IO.pure(ToolRender.RenderResult(),Done{ToolRender.RenderLines{U.padResult(label,U.visibleWidth(label),width,True{}) <> Nil{}}})
def drawEmpty(label: String,context: ToolRender.RenderContext) -> IO(ToolRender.RenderResult()): IO.pure(ToolRender.RenderResult(),Done{ToolRender.RenderLines{Nil{}}})
def mountedImageCheck(pair: Tool.Owner & Component.Component & Tool.Handle) -> IO(Unit):
  match pair:
    case (owner,component,handle):
      do IO<Unit>:
        +draw : Component.Component = component
        +mounted : Tool.Handle = handle
        +first : List<&2,String> <- Component.render(draw,28n)
        before : Tool.ToolExecution <- Tool.current(mounted)
        Tool.set(mounted,Tool.setExpanded(before,True{}))
        second : List<&2,String> <- Component.render(draw,28n)
        ensure(String.contains(String.join(first,"\n"),"\u{1b}_G"),"Kitty tool image was not emitted")
        ensure(String.eq(String.join(first,"\n"),String.join(second,"\n")),"unchanged tool image was retransmitted after a state redraw")
        current : Tool.ToolExecution <- Tool.current(mounted)
        Tool.set(mounted,Tool.setShowImages(current,False{}))
        +hidden : List<&2,String> <- Component.render(draw,28n)
        ensure(Bool.not(String.contains(String.join(hidden,"\n"),"\u{1b}_G")) && String.contains(String.join(hidden,"\n"),"[Image:"),"hiding a mounted tool image did not show its placeholder")
        Tool.dispose(owner)
def bumped(counter: Ref.Ref<Nat>) -> IO(Unit): Ref.modify(Nat,Unit,counter,n => (n + 1n,Unit{}))
def click(+row: Nat) -> Tui.TuiMouseEvent:
  Tui.TuiMouseEvent{Tui.MouseClick{},Tui.MouseLeft{},Tui.Forward{2n},Tui.Forward{row},Tui.Forward{2n},Tui.Forward{row},80n,20n,False{},False{},False{},None{},Some{1n}}
def probeMouse(counter: Ref.Ref<Nat>,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse()>):
  do IO<Maybe<&2,Component.MouseResponse()>>:
    bumped(counter)
    return Some{Component.LocalResult{Tui.TuiMouseEventResult{True{},False{},False{},Some{True{}}}}}
type ComponentProbe is Data: ComponentProbe{phase: Ref.Ref<Nat>,calls: Ref.Ref<Nat>,paints: Ref.Ref<Nat>,retired: Ref.Ref<Nat>,withLast: Ref.Ref<Nat>}
def paintedProbe(probe: ComponentProbe,width: Nat) -> IO(List<&2,String>):
  match probe:
    case ComponentProbe{_,_,paints,_,_}:
      do IO<List<&2,String>>:
        bumped(paints)
        return ["component " ++ Nat.show(width)]
def probeInvalidated(_: Unit,unit: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def probeOwner(+probe: ComponentProbe) -> IO(Component.Owner):
  match probe:
    case ComponentProbe{_,_,_,+retired,+withLast}:
      do IO<Component.Owner>:
        +draw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~ComponentProbe,~Nat,~List<&2,String>,~paintedProbe,probe)
        +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~probeInvalidated,Unit{})
        +mouse : Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>> <- Callback.create(~Ref.Ref<Nat>,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse()>,~probeMouse,withLast)
        return Component.Owner{Component.Component{Component.ComponentId{901n},draw,None{},Some{mouse},invalidate,None{},False{}},_ => do IO<Unit>:
          bumped(retired)
          Callback.dispose(Nat,List<&2,String>,draw)
          Callback.dispose(Unit,Unit,invalidate)
          Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>,mouse)}
def countLast(probe: ComponentProbe,last: Maybe<&2,Component.Component>) -> IO(Unit):
  match probe last:
    case ComponentProbe{_,_,_,_,withLast} Some{_}: bumped(withLast)
    case _ _: IO.pure(Unit,Unit{})
def probed(probe: ComponentProbe,context: ToolRender.RenderContext) -> IO(ToolRender.RenderResult()):
  match context probe:
    case ToolRender.RenderContext{_,_,_,_,_,_,_,_,_,_,_,last,_} ComponentProbe{+phase,+calls,+paints,+retired,+withLast}:
      do IO<ToolRender.RenderResult()>:
        bumped(calls)
        countLast(ComponentProbe{phase,calls,paints,retired,withLast},last)
        step : Nat <- Ref.read(Nat,phase)
        Bool.pick(Unit -> IO(ToolRender.RenderResult()),Nat.is_eq(step,1n),
          _ => IO.pure(ToolRender.RenderResult(),Done{ToolRender.ReuseComponent{}}),
          _ => do IO<ToolRender.RenderResult()>:
            owner : Component.Owner <- probeOwner(ComponentProbe{phase,calls,paints,retired,withLast})
            return Done{ToolRender.RenderComponent{owner}})(Unit{})
def readCount(counter: Ref.Ref<Nat>,expected: Nat,label: String) -> IO(Unit):
  do IO<Unit>:
    actual : Nat <- Ref.read(Nat,counter)
    Bool.pick(Unit -> IO(Unit),Nat.is_eq(actual,expected),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,label))(Unit{})
def mountedProbe(pair: Tool.Owner & Component.Component & Tool.Handle,probe: ComponentProbe) -> IO(Unit):
  match pair probe:
    case (owner,component,handle) ComponentProbe{+phase,+calls,+paints,+retired,+withLast}:
      do IO<Unit>:
        +draw : Component.Component = component
        +mounted : Tool.Handle = handle
        first : List<&2,String> <- Component.render(draw,40n)
        second : List<&2,String> <- Component.render(draw,60n)
        readCount(calls,1n,"component renderer reran on resize")
        readCount(paints,2n,"retained component did not repaint on resize")
        readCount(retired,0n,"component retired before replacement")
        Ref.write(Nat,phase,1n)
        current : Tool.ToolExecution <- Tool.current(mounted)
        Tool.set(mounted,Tool.updateArgs(current,args2()))
        reused : List<&2,String> <- Component.render(draw,60n)
        readCount(calls,2n,"component renderer missed state update")
        readCount(withLast,1n,"component renderer missed previous component")
        readCount(retired,0n,"reused component was retired")
        Ref.write(Nat,phase,2n)
        Component.invalidate(draw)
        replacement : List<&2,String> <- Component.render(draw,60n)
        readCount(calls,3n,"component renderer missed invalidation")
        readCount(withLast,2n,"invalidated renderer missed previous component")
        readCount(retired,1n,"replaced component was not retired")
        children : List<&2,Component.Component> <- Component.children(draw)
        ensure(Nat.is_eq(List.length(&2,Component.Component,children),1n),"mounted tool did not expose its child component")
        hit : Maybe<&2,Component.TuiMouseDispatchResult()> <- Component.dispatchMouseEvent(draw,click(1n))
        ensure(Maybe.is_some(&2,Component.TuiMouseDispatchResult(),hit),"custom child mouse handler was not reached")
        readCount(withLast,3n,"custom child mouse handler did not run")
        afterHit : Tool.ToolExecution <- Tool.current(mounted)
        ensure(Bool.not(Tool.expandedOf(afterHit)),"child-handled click expanded the tool")
        Tool.dispose(owner)
        readCount(retired,2n,"mounted component was not retired")
def retainedComponents(theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +phase : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +calls : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +paints : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +retired : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +withLast : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +probe : ComponentProbe = ComponentProbe{phase,calls,paints,retired,withLast}
    +renderer : ToolRender.Renderer() <- Callback.create(~ComponentProbe,~ToolRender.RenderContext,~ToolRender.RenderResult(),~probed,probe)
    owner : Tool.Owner <- Tool.create(Component.ComponentId{900n},Tool.new("probe","probe-1",args1(),theme,Tool.SelfRendered{Some{renderer},None{}}))
    mountedProbe(Tool.borrow(owner),probe)
    Callback.dispose(ToolRender.RenderContext,ToolRender.RenderResult(),renderer)
    p : Nat <- Ref.dispose(Nat,phase)
    c : Nat <- Ref.dispose(Nat,calls)
    a : Nat <- Ref.dispose(Nat,paints)
    r : Nat <- Ref.dispose(Nat,retired)
    l : Nat <- Ref.dispose(Nat,withLast)
    return Unit{}
def clickedRead(pair: Tool.Owner & Component.Component & Tool.Handle) -> IO(Unit):
  match pair:
    case (owner,component,handle):
      do IO<Unit>:
        +draw : Component.Component = component
        before : List<&2,String> <- Component.render(draw,80n)
        ensure(Bool.not(String.contains(String.join(before,"\n"),"hidden content")),"read result was visible before expansion")
        clicked : Maybe<&2,Component.TuiMouseDispatchResult()> <- Component.dispatchMouseEvent(draw,click(2n))
        ensure(Maybe.is_some(&2,Component.TuiMouseDispatchResult(),clicked),"read result click was not handled")
        after : List<&2,String> <- Component.render(draw,80n)
        ensure(String.contains(String.join(after,"\n"),"hidden content"),"read result click did not expand")
        Tool.dispose(owner)
def readClick(theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    value : Tool.ToolExecution = Tool.updateResult(Tool.new("read","click-read",args1(),theme,Tool.Generic{}),result("hidden content",False{}),False{})
    owner : Tool.Owner <- Tool.create(Component.ComponentId{910n},value)
    clickedRead(Tool.borrow(owner))
def unusedPreview(_: Unit,request: Tool.PreviewRequest) -> IO(Edits.Preview()):
  IO.die(Edits.Preview(),1,"read rendering invoked edit preflight")
def compactMounted(pair: Tool.Owner & Component.Component & Tool.Handle,+label: String) -> IO(Unit):
  match pair:
    case (owner,component,handle):
      do IO<Unit>:
        +draw : Component.Component = component
        +mounted : Tool.Handle = handle
        compact : List<&2,String> <- Component.render(draw,80n)
        output("read-compact-" ++ label,compact)
        current : Tool.ToolExecution <- Tool.current(mounted)
        Tool.set(mounted,Tool.setExpanded(current,True{}))
        expanded : List<&2,String> <- Component.render(draw,80n)
        output("read-ordinary-" ++ label,expanded)
        Tool.dispose(owner)
type CompactCase is Data: CompactCase{label: String,path: String}
def compactCases(cases: List<&2,CompactCase>,+context: Tool.ToolContext,+theme: Theme.Theme) -> IO(Unit):
  match cases:
    case Nil{}: IO.pure(Unit,Unit{})
    case CompactCase{+label,path} <> rest:
      do IO<Unit>:
        args : Value.Value = Value.ObjectValue{R.Record{R.Property{"path",Value.Text{path}} <> Nil{}}}
        owner : Tool.Owner <- Tool.createWithContext(Component.ComponentId{1n},Tool.new("read",label,args,theme,Tool.Generic{}),Some{context})
        compactMounted(Tool.borrow(owner),label)
        compactCases(rest,context,theme)
def compactReads(theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +compute : Callback.Callback<Tool.PreviewRequest,Edits.Preview()> <- Callback.create(~Unit,~Tool.PreviewRequest,~Edits.Preview(),~unusedPreview,Unit{})
    +redraw : Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Unit,Unit>>,None{})
    context : Tool.ToolContext = Tool.ToolContext{"/work/project",compute,redraw,Some{ReadRenderer.Context{Fixture.environment("/work/project","/home/tester"),"/package","ctrl+o"}},None{},None{}}
    compactCases(CompactCase{"skill","skills/check/SKILL.md"} <> CompactCase{"resource","AGENTS.md"} <> CompactCase{"override","../AGENTS.override.md"} <> CompactCase{"docs","/package/docs/how.md"} <> CompactCase{"examples","/package/examples/demo/main.bend"} <> CompactCase{"readme","/package/README.md"} <> CompactCase{"docs-skill","/package/docs/guide/SKILL.md"} <> CompactCase{"docs-resource","/package/docs/AGENTS.md"} <> CompactCase{"outside","/package-other/docs/README.md"} <> CompactCase{"outside-resource","/outside/CLAUDE.MD"} <> CompactCase{"ordinary","src/main.bend"} <> CompactCase{"resource-suffix","xAGENTS.md"} <> CompactCase{"tilde","~/AGENTS.md"} <> Nil{},context,theme)
    Callback.dispose(Tool.PreviewRequest,Edits.Preview(),compute)
    retired : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw)
    return Unit{}
def mainRun(+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +generic : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("custom_tool","g1",args1(),theme,Tool.Generic{}))
    show("generic-pending",generic)
    +args : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.updateArgs(generic,args2()))
    show("generic-args",args)
    +started : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.setArgsComplete(Tool.markExecutionStarted(args)))
    show("generic-started",started)
    +partial : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.updateResult(started,result("first\nsecond",False{}),True{}))
    show("generic-partial",partial)
    +success : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.updateResult(partial,result("first\nsecond",False{}),False{}))
    show("generic-success",success)
    show("generic-error",Tool.updateResult(success,result("bad\r\n\u{1b}[31mred\u{1b}[0m",True{}),False{}))
    +image : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.updateResult(Tool.new("custom_tool","image",Value.ObjectValue{R.Record{Nil{}}},theme,Tool.Generic{}),imageResult(),False{}))
    show("image-no-protocol",image)
    show("image-disabled",Tool.setShowImages(image,False{}))
    +computeImage : Callback.Callback<Tool.PreviewRequest,Edits.Preview()> <- Callback.create(~Unit,~Tool.PreviewRequest,~Edits.Preview(),~unusedPreview,Unit{})
    +redrawImage : Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Unit,Unit>>,None{})
    +environment : TerminalImage.Environment = TerminalImage.Environment{R.new(String),"linux","/home/tester"}
    +capabilities : TerminalImage.TerminalCapabilities = TerminalImage.TerminalCapabilities{TerminalImage.ITerm2{},False{},False{}}
    +imageContext : Tool.ToolContext = Tool.ToolContext{"/work/project",computeImage,redrawImage,None{},None{},Some{Tool.ImageConfig{environment,capabilities,F.fromU32(60),True{}}}}
    showImage("image-iterm",image,imageContext)
    showImage("image-iterm-disabled",Tool.setShowImages(image,False{}),imageContext)
    +boxedImage : Tool.ToolExecution = Tool.updateResult(Tool.new("custom_tool","image-boxed",Value.ObjectValue{R.Record{Nil{}}},theme,Tool.Boxed{None{},None{}}),imageResult(),False{})
    showImage("image-boxed-iterm",boxedImage,imageContext)
    +kittyContext : Tool.ToolContext = Tool.ToolContext{"/work/project",computeImage,redrawImage,None{},None{},Some{Tool.ImageConfig{environment,TerminalImage.TerminalCapabilities{TerminalImage.Kitty{},False{},False{}},F.fromU32(60),True{}}}}
    mountedImage : Tool.Owner <- Tool.createWithContext(Component.ComponentId{920n},Tool.updateResult(Tool.new("custom_tool","image-running",Value.ObjectValue{R.Record{Nil{}}},theme,Tool.Generic{}),imageResult(),True{}),Some{kittyContext})
    mountedImageCheck(Tool.borrow(mountedImage))
    Callback.dispose(Tool.PreviewRequest,Edits.Preview(),computeImage)
    retiredImage : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Unit,Unit>>,redrawImage)
    +fallback : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("custom_tool","f1",Value.ObjectValue{R.Record{R.Property{"foo",Value.Text{"bar"}} <> Nil{}}},theme,Tool.Boxed{None{},None{}}))
    show("fallback-pending",fallback)
    +preview : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.updateResult(fallback,result(String.join(lines(1n,12n,Nil{}),"\n"),False{}),False{}))
    show("fallback-preview",preview)
    +expanded : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.setExpanded(preview,True{}))
    show("fallback-expanded",expanded)
    show("fallback-error",Tool.updateResult(expanded,result("failed",True{}),False{}))
    +call : ToolRender.Renderer() <- Callback.create(~String,~ToolRender.RenderContext,~ToolRender.RenderResult(),~draw,"custom call")
    +resultCall : ToolRender.Renderer() <- Callback.create(~String,~ToolRender.RenderContext,~ToolRender.RenderResult(),~draw,"custom result")
    +rendered : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("custom_tool","r1",Value.ObjectValue{R.Record{Nil{}}},theme,Tool.Boxed{Some{call},Some{resultCall}}))
    show("rendered-call",rendered)
    show("rendered-result",Tool.updateResult(rendered,result("done",False{}),False{}))
    +ownCall : ToolRender.Renderer() <- Callback.create(~String,~ToolRender.RenderContext,~ToolRender.RenderResult(),~draw,"own call")
    +ownResult : ToolRender.Renderer() <- Callback.create(~String,~ToolRender.RenderContext,~ToolRender.RenderResult(),~draw,"own result")
    +self : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("custom_tool","s1",Value.ObjectValue{R.Record{Nil{}}},theme,Tool.SelfRendered{Some{ownCall},Some{ownResult}}))
    show("self-call",self)
    show("self-result",Tool.updateResult(self,result("done",False{}),False{}))
    +empty : ToolRender.Renderer() <- Callback.create(~String,~ToolRender.RenderContext,~ToolRender.RenderResult(),~drawEmpty,"")
    +emptyBox : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("custom_tool","e1",Value.ObjectValue{R.Record{Nil{}}},theme,Tool.Boxed{Some{empty},Some{empty}}))
    show("boxed-empty",emptyBox)
    +emptySelf : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("custom_tool","e2",Value.ObjectValue{R.Record{Nil{}}},theme,Tool.SelfRendered{Some{empty},Some{empty}}))
    show("self-empty",emptySelf)
    show("self-empty-result",Tool.updateResult(emptySelf,ToolRender.ToolResult{Nil{},False{},None{}},False{}))
    +callValue : Ai.ToolCall<Value.Value> <- IO.pure(Ai.ToolCall<Value.Value>,Ai.ToolCall{"a1","custom_tool",Value.ObjectValue{R.Record{Nil{}}},None{},None{}})
    +adapter : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.fromAiToolCall(callValue,theme,Tool.Generic{}))
    +agentResult : Agent.AgentToolResult<Value.Value> <- IO.pure(Agent.AgentToolResult<Value.Value>,Agent.AgentToolResult{text("from agent") <> Nil{},Some{Value.Null{}},None{},None{}})
    show("agent-adapter",Tool.updateFromAgent(Value.Value,adapter,agentResult,None{},False{},False{}))
    builtin("read",theme)
    builtin("bash",theme)
    bashAlias(theme)
    builtin("edit",theme)
    builtin("write",theme)
    +ranged : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("read","range",Value.ObjectValue{R.Record{R.Property{"path",Value.Text{"notes.txt"}} <> R.Property{"offset",Value.Number{F64{1074790400,0}}} <> R.Property{"limit",Value.Number{F64{1073741824,0}}} <> Nil{}}},theme,Tool.Generic{}))
    showWide("read-range",ranged)
    showWide("read-expanded",Tool.setExpanded(Tool.updateResult(ranged,result("one\ntwo",False{}),False{}),True{}))
    +readFailure : Tool.ToolExecution = Tool.updateResult(Tool.new("read","read-long",builtinArgs("read"),theme,Tool.Generic{}),result(String.join(lines(1n,15n,Nil{}),"\n") ++ "\n\n",True{}),False{})
    showWide("read-error-preview",readFailure)
    show("read-error-narrow",readFailure)
    showWide("read-error-expanded",Tool.setExpanded(readFailure,True{}))
    +longBash : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("bash","long",Value.ObjectValue{R.Record{R.Property{"command",Value.Text{"seq 7"}} <> Nil{}}},theme,Tool.Generic{}))
    showWide("bash-preview",Tool.updateResult(longBash,result(String.join(lines(1n,7n,Nil{}),"\n"),False{}),False{}))
    +longWrite : Tool.ToolExecution <- IO.pure(Tool.ToolExecution,Tool.new("write","long",Value.ObjectValue{R.Record{R.Property{"path",Value.Text{"notes.txt"}} <> R.Property{"content",Value.Text{String.join(lines(1n,12n,Nil{}),"\n")}} <> Nil{}}},theme,Tool.Generic{}))
    showWide("write-preview",longWrite)
    showWide("write-expanded",Tool.setExpanded(longWrite,True{}))
    compactReads(theme)
    retainedComponents(theme)
    readClick(theme)
    Callback.dispose(ToolRender.RenderContext,ToolRender.RenderResult(),call)
    Callback.dispose(ToolRender.RenderContext,ToolRender.RenderResult(),resultCall)
    Callback.dispose(ToolRender.RenderContext,ToolRender.RenderResult(),ownCall)
    Callback.dispose(ToolRender.RenderContext,ToolRender.RenderResult(),ownResult)
    Callback.dispose(ToolRender.RenderContext,ToolRender.RenderResult(),empty)
def main() -> IO(Unit):
  do IO<Unit>:
    loadedTheme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.Palette256{})
    +theme : Theme.Theme <- loaded(loadedTheme)
    mainRun(theme)
