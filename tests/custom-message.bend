import Base
import ../packages/tui/src/fullscreen-mouse.bend as Gestures
import ../packages/tui/src/tui-base.bend as Tui
import ../packages/tui/src/layout.bend as Layout
import ../packages/tui/src/tui.bend as Mouse
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/schema-value.bend as Value
import ../packages/ai/src/types.bend as Ai
import ../packages/coding-agent/src/core/messages.bend as Core
import ../packages/coding-agent/src/core/extensions/types.bend as Extensions
import ../packages/coding-agent/src/core/extensions/loader.bend as Loader
import ../packages/coding-agent/src/core/extensions/runner.bend as Runner
import ../packages/coding-agent/src/modes/interactive/transcript.bend as Transcript
import ../packages/coding-agent/src/modes/interactive/viewport.bend as View
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/agent/src/types.bend as Agent
import ./model-runtime-fixture.bend as Fixture
import ../packages/coding-agent/src/modes/interactive/components/custom-message.bend as Custom
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/modes/interactive/theme/markdown-theme.bend as Styles
import ../packages/coding-agent/src/utils/syntax-highlight.bend as Highlight
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/components/markdown.bend as Markdown
import ../packages/tui/src/utils.bend as Visual
import ../packages/tui/src/components/text.bend as Text

type Counts is Data: Counts{calls: Nat, retired: Nat, invalidated: Nat}
def snapshot(label: String, rows: List<&2,String>) -> IO(Unit): IO.print(label ++ "\u{1e}" ++ String.join(rows,"\u{1f}"))
def check(value: Bool, message: String) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)
def called(state: Counts) -> Counts & Unit:
  match state: case Counts{calls, retired, invalidated}: (Counts{calls + 1n, retired, invalidated}, Unit{})
def closed(state: Counts) -> Counts & Unit:
  match state: case Counts{calls, retired, invalidated}: (Counts{calls, retired + 1n, invalidated}, Unit{})
def invalidated(state: Counts) -> Counts & Unit:
  match state: case Counts{calls, retired, invalidated}: (Counts{calls, retired, invalidated + 1n}, Unit{})
def text(text: String, width: Nat) -> IO(List<&2, String>): IO.pure(List<&2, String>, text <> Nil{})
def invalidate(counter: Ref.Ref<Counts>, _: Unit) -> IO(Unit): Ref.modify(Counts, Unit, counter, invalidated)
def retire(counter: Ref.Ref<Counts>, render: C.Callback<Nat, List<&2, String>>, invalidate: C.Callback<Unit, Unit>) -> IO(Unit):
  do IO<Unit>:
    C.dispose(Nat, List<&2, String>, render)
    C.dispose(Unit, Unit, invalidate)
    Ref.modify(Counts, Unit, counter, closed)
def renderer(counter: Ref.Ref<Counts>, input: Extensions.MessageRenderInput) -> IO(Extensions.MessageRenderResult()):
  match input:
    case Extensions.MessageRenderInput{Core.CustomMessage{label, _, _, _, _}, Extensions.MessageRenderOptions{expanded, pad}, _}:
      do IO<Extensions.MessageRenderResult()>:
        +shared : Ref.Ref<Counts> = counter
        Ref.modify(Counts, Unit, shared, called)
        +render : C.Callback<Nat, List<&2, String>> <- C.create(~String, ~Nat, ~List<&2, String>, ~text, label ++ ":" ++ Bool.show(expanded) ++ ":" ++ Nat.show(pad))
        +invalidate : C.Callback<Unit, Unit> <- C.create(~Ref.Ref<Counts>, ~Unit, ~Unit, ~invalidate, shared)
        return Done{Some{Component.Owner{Component.Component{Component.ComponentId{99n}, render, None{}, None{}, invalidate, None{}, False{}}, _ => retire(shared, render, invalidate)}}}
def textLines(pair: Text.Text & List<&2,String>) -> List<&2,String>:
  match pair: case (_,rows): rows
def paddedText(state: Text.Text, width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    result : Text.Text & List<&2,String> <- Text.render(state,width)
    return textLines(result)
def inert(_: Unit, _: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def retireText(render: C.Callback<Nat,List<&2,String>>, invalidate: C.Callback<Unit,Unit>) -> IO(Unit):
  do IO<Unit>:
    C.dispose(Nat,List<&2,String>,render)
    C.dispose(Unit,Unit,invalidate)
def paddingRenderer(_: Unit, input: Extensions.MessageRenderInput) -> IO(Extensions.MessageRenderResult()):
  match input:
    case Extensions.MessageRenderInput{_,Extensions.MessageRenderOptions{_,pad},_}:
      do IO<Extensions.MessageRenderResult()>:
        +render : C.Callback<Nat,List<&2,String>> <- C.create(~Text.Text,~Nat,~List<&2,String>,~paddedText,Text.new("custom",Some{pad},Some{0n},None{}))
        +invalidate : C.Callback<Unit,Unit> <- C.create(~Unit,~Unit,~Unit,~inert,Unit{})
        return Done{Some{Component.Owner{Component.Component{Component.ComponentId{98n},render,None{},None{},invalidate,None{},False{}},_ => retireText(render,invalidate)}}}
def failing(_: Unit, input: Extensions.MessageRenderInput) -> IO(Extensions.MessageRenderResult()): IO.pure(Extensions.MessageRenderResult(), Fail{"renderer failed"})
def empty(_: Unit, input: Extensions.MessageRenderInput) -> IO(Extensions.MessageRenderResult()): IO.pure(Extensions.MessageRenderResult(), Done{None{}})
def message() -> Core.CustomMessage<Value.Value>: Core.CustomMessage{"notice", Ai.UserText{"fallback body"}, True{}, None{}, F.fromU32(0)}
def requireTheme(result: Result<&2, &2, Theme.LoadError, Theme.Theme>) -> IO(Theme.Theme):
  match result:
    case Done{theme}: IO.pure(Theme.Theme, theme)
    case Fail{_}: IO.die(Theme.Theme, 1, "theme failed")
def verifyCounts(value: Counts, calls: Nat, retired: Nat, invalidated: Nat) -> IO(Unit):
  match value:
    case Counts{a, b, c}: check(Nat.is_eq(a, calls) && Nat.is_eq(b, retired) && Nat.is_eq(c, invalidated), "renderer lifecycle differs")
def fallbackCase(pair: Custom.Owner & Component.Component & Custom.Handle) -> IO(Unit):
  match pair:
    case (owner, component, _):
      do IO<Unit>:
        +rows : List<&2, String> <- Component.render(component, 80n)
        snapshot("fallback",rows)
        check(String.contains(Visual.stripTerminalSequences(String.join(rows, "\n")), "fallback body"), "renderer failure/absence did not fall back")
        Custom.dispose(owner)
def lifecycleOwner(owner: Custom.Owner, +component: Component.Component, +handle: Custom.Handle, +counter: Ref.Ref<Counts>) -> IO(Unit):
  do IO<Unit>:
    +initial : List<&2, String> <- Component.render(component, 80n)
    snapshot("initial",initial)
    check(String.eq(String.join(initial, "\n"), "\nnotice:False:1"), "renderer context or spacer differs")
    again : List<&2, String> <- Component.render(component, 30n)
    check(String.eq(String.join(again, "\n"), String.join(initial, "\n")), "width change recreated the renderer")
    Custom.setExpanded(handle, False{})
    Custom.setOutputPad(handle, 1n)
    first : Counts <- Ref.read(Counts, counter)
    verifyCounts(first, 1n, 0n, 0n)
    Custom.setExpanded(handle, True{})
    Custom.setOutputPad(handle, 3n)
    +changed : List<&2, String> <- Component.render(component, 80n)
    snapshot("options",changed)
    check(String.eq(String.join(changed, "\n"), "\nnotice:True:3"), "updated renderer options differ")
    Component.invalidate(component)
    current : Counts <- Ref.read(Counts, counter)
    verifyCounts(current, 4n, 2n, 1n)
    Custom.dispose(owner)
    final : Counts <- Ref.read(Counts, counter)
    verifyCounts(final, 4n, 4n, 1n)
def lifecycle(pair: Custom.Owner & Component.Component & Custom.Handle, counter: Ref.Ref<Counts>) -> IO(Unit):
  match pair:
    case (owner, component, handle): lifecycleOwner(owner, component, handle, counter)
def registered(result: Result<&2, &2, String, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{error}: IO.die(Unit, 1, error)
def replacing(+old: Extensions.MessageRenderer(), current: Extensions.MessageRenderer(), +api: Extensions.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    result : Result<&2, &2, String, Unit> <- Loader.registerMessageRenderer(api, "notice", old)
    registered(result)
    Loader.registerMessageRenderer(api, "notice", current)
def failingRegistration(callback: Extensions.MessageRenderer(), api: Extensions.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    result : Result<&2, &2, String, Unit> <- Loader.registerMessageRenderer(api, "failed", callback)
    registered(result)
    return Fail{"factory failed"}
def selected(result: Extensions.MessageRenderResult()) -> IO(Unit):
  match result:
    case Done{Some{Component.Owner{+component, retire}}}:
      do IO<Unit>:
        rows : List<&2, String> <- Component.render(component, 80n)
        check(String.eq(String.join(rows, "\n"), "notice:False:7"), "renderer replacement/precedence differs")
        retire(Unit{})
    case _: IO.die(Unit, 1, "registered renderer not selected")
def invokeSelected(value: Maybe<&2, Extensions.MessageRenderer()>, theme: Theme.Theme) -> IO(Unit):
  match value:
    case None{}: IO.die(Unit, 1, "registered renderer missing")
    case Some{callback}:
      do IO<Unit>:
        result : Extensions.MessageRenderResult() <- C.call(Extensions.MessageRenderInput, Extensions.MessageRenderResult(), callback, Extensions.MessageRenderInput{message(), Extensions.MessageRenderOptions{False{}, 7n}, theme})
        selected(result)
def registry(+current: Extensions.MessageRenderer(), +old: Extensions.MessageRenderer(), +theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +runtime : Extensions.ExtensionRuntime() <- Loader.createExtensionRuntime()
    first : Result<&2, &2, String, Unit> <- Loader.loadExtensionFromFactory(runtime, api => replacing(old, current, api), "<first>", False{})
    registered(first)
    second : Result<&2, &2, String, Unit> <- Loader.loadExtensionFromFactory(runtime, api => Loader.registerMessageRenderer(api, "notice", old), "<second>", False{})
    registered(second)
    failed : Result<&2, &2, String, Unit> <- Loader.loadExtensionFromFactory(runtime, api => failingRegistration(current, api), "<failed>", False{})
    state : Extensions.ExtensionRuntimeState <- Ref.dispose(Extensions.ExtensionRuntimeState, runtime)
    +loaded : List<&2, Extensions.Extension> = Loader.activeExtensions(Loader.extensionsOf(state))
    invokeSelected(Runner.messageRendererIn(loaded, "notice"), theme)
    check(Maybe.is_none(&2, Extensions.MessageRenderer(), Runner.messageRendererIn(loaded, "missing")), "missing renderer appeared")
    check(Maybe.is_none(&2, Extensions.MessageRenderer(), Runner.messageRendererIn(loaded, "failed")), "failed extension renderer appeared")
def transcriptOwner(pair: Transcript.Owner & Transcript.Handle, view: View.View, +document: Component.Component, +runner: Runner.ExtensionRunner, +counter: Ref.Ref<Counts>) -> IO(Unit):
  match pair:
    case (owner, +handle):
      do IO<Unit>:
        Transcript.setExtensions(handle,Some{runner})
        Transcript.seedCustom(handle,message())
        rows : List<&2,String> <- Component.render(document,80n)
        check(String.contains(String.join(rows,"\n"),"notice:False:1"),"live custom renderer did not mount")
        Transcript.seedCustom(handle,Core.CustomMessage{"notice",Ai.UserText{"hidden"},False{},None{},F.fromU32(0)})
        first : Counts <- Ref.read(Counts,counter)
        verifyCounts(first,1n,0n,0n)
        expanded : Bool <- Transcript.toggleExpanded(handle)
        Transcript.setOutputPad(handle,3n)
        Transcript.invalidate(handle)
        changed : List<&2,String> <- Component.render(document,80n)
        check(String.contains(String.join(changed,"\n"),"notice:True:3"),"transcript renderer options did not update")
        current : Counts <- Ref.read(Counts,counter)
        verifyCounts(current,4n,3n,1n)
        Transcript.clear(handle)
        cleared : Counts <- Ref.read(Counts,counter)
        verifyCounts(cleared,4n,4n,1n)
        Transcript.seedSession(handle,[Agent.CustomMessage{Core.Custom{message()}}])
        restored : List<&2,String> <- Component.render(document,80n)
        check(String.contains(String.join(restored,"\n"),"notice:True:3"),"replayed custom renderer did not mount")
        Transcript.dispose(owner)
        final : Counts <- Ref.read(Counts,counter)
        verifyCounts(final,6n,6n,1n)
        View.dispose(view)
        Runner.dispose(runner)
def transcriptView(pair: View.View & Component.Component & View.Handle, theme: Theme.Theme, markdown: Markdown.MarkdownTheme, runner: Runner.ExtensionRunner, counter: Ref.Ref<Counts>) -> IO(Unit):
  match pair:
    case (view,document,handle):
      do IO<Unit>:
        owner : Transcript.Owner <- Transcript.create(handle,theme,markdown)
        transcriptOwner(Transcript.borrow(owner),view,document,runner,counter)
def transcriptCase(theme: Theme.Theme, markdown: Markdown.MarkdownTheme) -> IO(Unit):
  do IO<Unit>:
    +counter : Ref.Ref<Counts> <- Ref.new(Counts,Counts{0n,0n,0n})
    +callback : Extensions.MessageRenderer() <- C.create(~Ref.Ref<Counts>,~Extensions.MessageRenderInput,~Extensions.MessageRenderResult(),~renderer,counter)
    +runtime : Extensions.ExtensionRuntime() <- Loader.createExtensionRuntime()
    result : Result<&2,&2,String,Unit> <- Loader.loadExtensionFromFactory(runtime,api => Loader.registerMessageRenderer(api,"notice",callback),"<transcript>",False{})
    registered(result)
    +models : Models.ModelRuntime <- Fixture.create(Nil{})
    runner : Runner.ExtensionRunner <- Runner.create(runtime,"/tmp",models)
    view : View.View <- View.create(Component.ComponentId{1n})
    transcriptView(View.borrow(view),theme,markdown,runner,counter)
    Models.dispose(models)
    C.dispose(Extensions.MessageRenderInput,Extensions.MessageRenderResult(),callback)
    counts : Counts <- Ref.dispose(Counts,counter)
    return Unit{}
def starts(rows: List<&2,String>, +prefix: String) -> Bool:
  match rows:
    case Nil{}: False{}
    case row <> rest: String.starts_with(Visual.stripTerminalSequences(row),prefix) || starts(rest,prefix)
def paddingOwner(pair: Custom.Owner & Component.Component & Custom.Handle) -> IO(Unit):
  match pair:
    case (owner,+component,handle):
      do IO<Unit>:
        +initial : List<&2,String> <- Component.render(component,40n)
        snapshot("padding1",initial)
        check(starts(initial," custom"),"provides output padding to custom renderers")
        Custom.setOutputPad(handle,0n)
        +changed : List<&2,String> <- Component.render(component,40n)
        snapshot("padding0",changed)
        check(starts(changed,"custom"),"updates output padding for custom renderers")
        Custom.dispose(owner)
def paddingCase(theme: Theme.Theme, markdown: Markdown.MarkdownTheme) -> IO(Unit):
  do IO<Unit>:
    +callback : Extensions.MessageRenderer() <- C.create(~Unit,~Extensions.MessageRenderInput,~Extensions.MessageRenderResult(),~paddingRenderer,Unit{})
    owner : Custom.Owner <- Custom.create(Component.ComponentId{14n},message(),Some{callback},theme,markdown,1n)
    paddingOwner(Custom.borrow(owner))
    C.dispose(Extensions.MessageRenderInput,Extensions.MessageRenderResult(),callback)
type Control is Data: Control{id: Nat,journal: Ref.Ref<String>,reentry: Maybe<&2,Ref.Ref<Maybe<&2,Custom.Handle>>>}
type Controls is Data: Controls{counter: Ref.Ref<Counts>,journal: Ref.Ref<String>,reentry: Maybe<&2,Ref.Ref<Maybe<&2,Custom.Handle>>>}
def expandOnce(handle: Maybe<&2,Custom.Handle>) -> IO(Unit):
  match handle:
    case None{}: IO.pure(Unit,Unit{})
    case Some{handle}: Custom.setExpanded(handle,True{})
def reenter(value: Maybe<&2,Ref.Ref<Maybe<&2,Custom.Handle>>>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{reference}:
      do IO<Unit>:
        handle : Maybe<&2,Custom.Handle> <- Ref.swap(Maybe<&2,Custom.Handle>,reference,None{})
        expandOnce(handle)
def controlInput(journal: Ref.Ref<String>,data: String) -> IO(Unit): Ref.modify(String,Unit,journal,old => (old ++ data,Unit{}))
def controlFocus(journal: Ref.Ref<String>,value: Bool) -> IO(Unit): IO.pure(Unit,Unit{})
def controlMouse(control: Control,event: Mouse.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse()>):
  match control event:
    case Control{id,journal,reentry} Mouse.TuiMouseEvent{_,_,_,Mouse.Forward{y},_,_,_,_,_,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse()>>:
        Ref.modify(String,Unit,journal,old => (old ++ Nat.show(id) ++ ":" ++ Nat.show(y) ++ ";",Unit{}))
        reenter(reentry)
        return Some{Component.LocalResult{Mouse.TuiMouseEventResult{True{},True{},True{},None{}}}}
    case _ _: IO.pure(Maybe<&2,Component.MouseResponse()>,None{})
def controlId(counts: Counts) -> Nat:
  match counts: case Counts{calls,_,_}: 10000n + calls
def retireControl(counter: Ref.Ref<Counts>,render: C.Callback<Nat,List<&2,String>>,input: C.Callback<String,Unit>,mouse: C.Callback<Mouse.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>>,invalidate: C.Callback<Unit,Unit>,focus: C.Callback<Bool,Unit>) -> IO(Unit):
  do IO<Unit>:
    C.dispose(String,Unit,input)
    C.dispose(Mouse.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>,mouse)
    C.dispose(Bool,Unit,focus)
    retire(counter,render,invalidate)
def controlRenderer(environment: Controls,input: Extensions.MessageRenderInput) -> IO(Extensions.MessageRenderResult()):
  match environment:
    case Controls{+counter,+journal,reentry}:
      do IO<Extensions.MessageRenderResult()>:
        Ref.modify(Counts,Unit,counter,called)
        count : Counts <- Ref.read(Counts,counter)
        +id : Nat = controlId(count)
        +render : C.Callback<Nat,List<&2,String>> <- C.create(~String,~Nat,~List<&2,String>,~text,"control")
        +input : C.Callback<String,Unit> <- C.create(~Ref.Ref<String>,~String,~Unit,~controlInput,journal)
        +mouse : C.Callback<Mouse.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>> <- C.create(~Control,~Mouse.TuiMouseEvent,~Maybe<&2,Component.MouseResponse()>,~controlMouse,Control{id,journal,reentry})
        +invalidate : C.Callback<Unit,Unit> <- C.create(~Ref.Ref<Counts>,~Unit,~Unit,~invalidate,counter)
        +focus : C.Callback<Bool,Unit> <- C.create(~Ref.Ref<String>,~Bool,~Unit,~controlFocus,journal)
        return Done{Some{Component.Owner{Component.Component{Component.ComponentId{id},render,Some{input},Some{mouse},invalidate,Some{focus},False{}},_ => retireControl(counter,render,input,mouse,invalidate,focus)}}}
def press(+row: Nat) -> Mouse.TuiMouseEvent:
  Mouse.TuiMouseEvent{Mouse.MousePress{},Mouse.MouseLeft{},Mouse.Forward{2n},Mouse.Forward{row},Mouse.Forward{2n},Mouse.Forward{row},80n,2n,False{},False{},False{},None{},None{}}
def verifyHitBounds(result: Maybe<&2,Component.TuiMouseDispatchResult()>,+wanted: Nat) -> IO(Unit):
  match result:
    case Some{Component.TuiMouseDispatchResult{Component.IdTarget{Component.ComponentId{id},_,Mouse.Forward{y},width,height},Some{Component.ComponentId{focus}},capture,focused,_}}:
      check(Nat.is_eq(id,wanted) && Nat.is_eq(focus,wanted) && Nat.is_eq(y,1n) && Nat.is_eq(width,80n) && Nat.is_eq(height,1n) && capture && focused,"custom child target/focus/capture coordinates differ")
    case _: IO.die(Unit,1,"custom child did not receive mouse input")
def verifyHit(result: Maybe<&2,Component.TuiMouseDispatchResult()>,wanted: Nat) -> IO(Unit):
  match result:
    case Some{Component.TuiMouseDispatchResult{target,focusTarget,capture,focus,render}}:
      verifyHitBounds(Some{Component.TuiMouseDispatchResult{Component.targetBounds(target),focusTarget,capture,focus,render}},wanted)
    case None{}: verifyHitBounds(None{},wanted)
def verifyFound(result: Maybe<&2,Component.Component>,wanted: Nat) -> IO(Unit):
  match result:
    case Some{component}: check(Component.same(Component.id(component),Component.ComponentId{wanted}),"custom child discovery differs")
    case None{}: IO.die(Unit,1,"custom child missing from transcript hierarchy")
def pendingDisplay(handle: View.Handle) -> View.Display:
  match handle:
    case View.Handle{document,_,exit}: View.Display{View.Pending{},document,None{},exit}
def verifyMouseResponse(response: Maybe<&2,Component.MouseResponse()>,wanted: Nat) -> IO(Unit):
  match response:
    case Some{Component.DispatchedResult{result}}: verifyHit(Some{result},wanted)
    case _: IO.die(Unit,1,"cached pending child did not receive mouse input")
def mouseContents(owner: Custom.Owner,+component: Component.Component,+handle: Custom.Handle,view: View.View,+document: Component.Component,+viewHandle: View.Handle,+counter: Ref.Ref<Counts>,+journal: Ref.Ref<String>) -> IO(Unit):
  do IO<Unit>:
    View.appendPending(viewHandle,component)
    rows : List<&2,String> <- Component.render(document,80n)
    pendingRows : List<&2,String> <- View.draw(pendingDisplay(viewHandle),80n)
    View.flushPending(viewHandle)
    pendingHit : Maybe<&2,Component.MouseResponse()> <- View.mouse(pendingDisplay(viewHandle),press(1n))
    verifyMouseResponse(pendingHit,10001n)
    emptyRows : List<&2,String> <- View.draw(pendingDisplay(viewHandle),80n)
    emptyHit : Maybe<&2,Component.MouseResponse()> <- View.mouse(pendingDisplay(viewHandle),press(1n))
    check(Maybe.is_none(&2,Component.MouseResponse(),emptyHit),"redrawn empty pending section receives mouse input")
    found : Maybe<&2,Component.Component> <- Component.lookup(document <> Nil{},Component.ComponentId{10001n})
    verifyFound(found,10001n)
    spacer : Maybe<&2,Component.TuiMouseDispatchResult()> <- Component.dispatchMouseEvent(document,press(0n))
    check(Maybe.is_none(&2,Component.TuiMouseDispatchResult(),spacer),"custom spacer consumes mouse input")
    initial : Maybe<&2,Component.TuiMouseDispatchResult()> <- Component.dispatchMouseEvent(document,press(1n))
    verifyHit(initial,10001n)
    Custom.setExpanded(handle,True{})
    removed : Maybe<&2,Component.Component> <- Component.lookup(document <> Nil{},Component.ComponentId{10001n})
    check(Maybe.is_none(&2,Component.Component,removed),"replaced child remains in current hierarchy")
    cached : Maybe<&2,Component.TuiMouseDispatchResult()> <- Component.dispatchMouseEvent(document,press(1n))
    verifyHit(cached,10001n)
    retained : Counts <- Ref.read(Counts,counter)
    verifyCounts(retained,2n,0n,0n)
    changed : List<&2,String> <- Component.render(document,80n)
    next : Maybe<&2,Component.TuiMouseDispatchResult()> <- Component.dispatchMouseEvent(document,press(1n))
    verifyHit(next,10002n)
    current : Counts <- Ref.read(Counts,counter)
    verifyCounts(current,2n,1n,0n)
    +events : String <- Ref.read(String,journal)
    check(String.eq(events,"10001:0;10001:0;10001:0;10002:0;"),"custom mouse routing or retained-child lifetime differs")
    snapshot("mouse",events <> Nil{})
    View.clear(viewHandle)
    Custom.dispose(owner)
    cleared : Maybe<&2,Component.TuiMouseDispatchResult()> <- Component.dispatchMouseEvent(document,press(1n))
    check(Maybe.is_none(&2,Component.TuiMouseDispatchResult(),cleared),"cleared transcript routes to retired callbacks")
    View.dispose(view)
    closed : Counts <- Ref.read(Counts,counter)
    verifyCounts(closed,2n,2n,0n)
def mouseCustom(custom: Custom.Owner & Component.Component & Custom.Handle,view: View.View,document: Component.Component,viewHandle: View.Handle,counter: Ref.Ref<Counts>,journal: Ref.Ref<String>) -> IO(Unit):
  match custom:
    case (owner,component,handle): mouseContents(owner,component,handle,view,document,viewHandle,counter,journal)
def mouseOwner(pair: View.View & Component.Component & View.Handle,custom: Custom.Owner & Component.Component & Custom.Handle,counter: Ref.Ref<Counts>,journal: Ref.Ref<String>) -> IO(Unit):
  match pair:
    case (view,document,handle): mouseCustom(custom,view,document,handle,counter,journal)
def gestureFrame(document: Component.Component) -> Layout.LayoutFrame:
  +rect = {Layout.LayoutRect{0n,0n,80n,2n}: Layout.LayoutRect}
  Layout.LayoutFrame{Layout.LayoutBox{Some{Component.id(document)},rect,rect,Nil{},None{},0n,0n},80n,24n,Nil{}}
def gestureMouse(result: Gestures.Outcome) -> Gestures.State:
  match result: case Gestures.Outcome{mouse,_,_,_,_}: mouse
def gestureTui(result: Gestures.Outcome) -> Tui.TuiBase:
  match result: case Gestures.Outcome{_,tui,_,_,_}: tui
def gestureResult(result: Gestures.Outcome) -> IO(Gestures.Outcome):
  match result:
    case Gestures.Outcome{mouse,tui,handled,render,None{}}: IO.pure(Gestures.Outcome,Gestures.Outcome{mouse,tui,handled,render,None{}})
    case _: IO.die(Gestures.Outcome,1,"captured gesture lost its replaced control")
def gestureStep(state: Gestures.State,tui: Tui.TuiBase,+document: Component.Component,raw: Gestures.Raw) -> IO(Gestures.Outcome):
  do IO<Gestures.Outcome>:
    result : Gestures.Outcome <- Gestures.dispatch(state,tui,Some{gestureFrame(document)},document <> Nil{},Component.id(document) <> Nil{},raw,80n,24n)
    gestureResult(result)
def gestureInput(result: Tui.ResultOf(Tui.InputResult)) -> IO(Tui.TuiBase):
  match result:
    case Done{Tui.InputResult{tui,True{},_}}: IO.pure(Tui.TuiBase,tui)
    case _: IO.die(Tui.TuiBase,1,"replaced focused control lost keyboard input")
def gestureFocusCleared(result: Tui.ResultOf(Tui.TuiBase)) -> IO(Unit):
  match result:
    case Done{tui}: Tui.disposeFocus(tui)
    case _: IO.die(Unit,1,"failed to clear replaced focus")
def gestureContents(owner: Custom.Owner,+component: Component.Component,+handle: Custom.Handle,view: View.View,+document: Component.Component,+viewHandle: View.Handle,+counter: Ref.Ref<Counts>,+journal: Ref.Ref<String>) -> IO(Unit):
  do IO<Unit>:
    View.append(viewHandle,component)
    rows : List<&2,String> <- Component.render(document,80n)
    +initial : Gestures.Outcome <- gestureStep(Gestures.initial(),Tui.newTui(),document,Gestures.Raw{0n,2n,1n,False{}})
    changed : List<&2,String> <- Component.render(document,80n)
    retained : Counts <- Ref.read(Counts,counter)
    verifyCounts(retained,2n,0n,0n)
    +dragged : Gestures.Outcome <- gestureStep(gestureMouse(initial),gestureTui(initial),document,Gestures.Raw{32n,2n,3n,False{}})
    +released : Gestures.Outcome <- gestureStep(gestureMouse(dragged),gestureTui(dragged),document,Gestures.Raw{0n,2n,3n,True{}})
    heldFocus : Counts <- Ref.read(Counts,counter)
    verifyCounts(heldFocus,2n,0n,0n)
    typed : Tui.ResultOf(Tui.InputResult) <- Tui.dispatchInput(gestureTui(released),document <> Nil{},Component.id(document) <> Nil{},"typed")
    +afterInput : Tui.TuiBase <- gestureInput(typed)
    +events : String <- Ref.read(String,journal)
    check(String.eq(events,"10001:0;10001:2;10001:2;typed"),"gesture or focused-input trace differs")
    snapshot("gesture",events <> Nil{})
    cleared : Tui.ResultOf(Tui.TuiBase) <- Tui.setFocus(afterInput,document <> Nil{},Component.id(document) <> Nil{},None{})
    gestureFocusCleared(cleared)
    disposedOld : Counts <- Ref.read(Counts,counter)
    verifyCounts(disposedOld,2n,1n,0n)
    Gestures.dispose(gestureMouse(released))
    View.clear(viewHandle)
    Custom.dispose(owner)
    View.dispose(view)
    final : Counts <- Ref.read(Counts,counter)
    verifyCounts(final,2n,2n,0n)
def gestureReady(owner: Custom.Owner,component: Component.Component,+handle: Custom.Handle,view: View.View,document: Component.Component,viewHandle: View.Handle,counter: Ref.Ref<Counts>,journal: Ref.Ref<String>,reentry: Ref.Ref<Maybe<&2,Custom.Handle>>) -> IO(Unit):
  do IO<Unit>:
    Ref.write(Maybe<&2,Custom.Handle>,reentry,Some{handle})
    gestureContents(owner,component,handle,view,document,viewHandle,counter,journal)
def gestureCustom(pair: Custom.Owner & Component.Component & Custom.Handle,view: View.View,document: Component.Component,viewHandle: View.Handle,counter: Ref.Ref<Counts>,journal: Ref.Ref<String>,reentry: Ref.Ref<Maybe<&2,Custom.Handle>>) -> IO(Unit):
  match pair:
    case (owner,component,handle): gestureReady(owner,component,handle,view,document,viewHandle,counter,journal,reentry)
def gestureView(pair: View.View & Component.Component & View.Handle,custom: Custom.Owner & Component.Component & Custom.Handle,counter: Ref.Ref<Counts>,journal: Ref.Ref<String>,reentry: Ref.Ref<Maybe<&2,Custom.Handle>>) -> IO(Unit):
  match pair:
    case (view,document,handle): gestureCustom(custom,view,document,handle,counter,journal,reentry)
def gestureCase(+theme: Theme.Theme,+markdown: Markdown.MarkdownTheme) -> IO(Unit):
  do IO<Unit>:
    +counter : Ref.Ref<Counts> <- Ref.new(Counts,Counts{0n,0n,0n})
    +journal : Ref.Ref<String> <- Ref.new(String,"")
    +reentry : Ref.Ref<Maybe<&2,Custom.Handle>> <- Ref.new(Maybe<&2,Custom.Handle>,None{})
    +callback : Extensions.MessageRenderer() <- C.create(~Controls,~Extensions.MessageRenderInput,~Extensions.MessageRenderResult(),~controlRenderer,Controls{counter,journal,Some{reentry}})
    view : View.View <- View.create(Component.ComponentId{20n})
    custom : Custom.Owner <- Custom.create(Component.ComponentId{21n},message(),Some{callback},theme,markdown,1n)
    gestureView(View.borrow(view),Custom.borrow(custom),counter,journal,reentry)
    oldReentry : Maybe<&2,Custom.Handle> <- Ref.dispose(Maybe<&2,Custom.Handle>,reentry)
    C.dispose(Extensions.MessageRenderInput,Extensions.MessageRenderResult(),callback)
    oldCount : Counts <- Ref.dispose(Counts,counter)
    oldJournal : String <- Ref.dispose(String,journal)
    return Unit{}
def mouseCase(+theme: Theme.Theme,+markdown: Markdown.MarkdownTheme) -> IO(Unit):
  do IO<Unit>:
    +counter : Ref.Ref<Counts> <- Ref.new(Counts,Counts{0n,0n,0n})
    +journal : Ref.Ref<String> <- Ref.new(String,"")
    +callback : Extensions.MessageRenderer() <- C.create(~Controls,~Extensions.MessageRenderInput,~Extensions.MessageRenderResult(),~controlRenderer,Controls{counter,journal,None{}})
    view : View.View <- View.create(Component.ComponentId{20n})
    custom : Custom.Owner <- Custom.create(Component.ComponentId{21n},message(),Some{callback},theme,markdown,1n)
    mouseOwner(View.borrow(view),Custom.borrow(custom),counter,journal)
    C.dispose(Extensions.MessageRenderInput,Extensions.MessageRenderResult(),callback)
    unusedCounts : Counts <- Ref.dispose(Counts,counter)
    unusedEvents : String <- Ref.dispose(String,journal)
    return Unit{}
def runStyle(pair: Styles.Styles & Markdown.MarkdownTheme, +theme: Theme.Theme) -> IO(Unit):
  match pair:
    case (styles, +markdown):
      do IO<Unit>:
        +counter : Ref.Ref<Counts> <- Ref.new(Counts, Counts{0n, 0n, 0n})
        +callback : Extensions.MessageRenderer() <- C.create(~Ref.Ref<Counts>, ~Extensions.MessageRenderInput, ~Extensions.MessageRenderResult(), ~renderer, counter)
        owner : Custom.Owner <- Custom.create(Component.ComponentId{10n}, message(), Some{callback}, theme, markdown, 1n)
        lifecycle(Custom.borrow(owner), counter)
        +failure : Extensions.MessageRenderer() <- C.create(~Unit, ~Extensions.MessageRenderInput, ~Extensions.MessageRenderResult(), ~failing, Unit{})
        failed : Custom.Owner <- Custom.create(Component.ComponentId{11n}, message(), Some{failure}, theme, markdown, 1n)
        fallbackCase(Custom.borrow(failed))
        registry(callback, failure, theme)
        C.dispose(Extensions.MessageRenderInput, Extensions.MessageRenderResult(), callback)
        C.dispose(Extensions.MessageRenderInput, Extensions.MessageRenderResult(), failure)
        +absent : Extensions.MessageRenderer() <- C.create(~Unit, ~Extensions.MessageRenderInput, ~Extensions.MessageRenderResult(), ~empty, Unit{})
        omitted : Custom.Owner <- Custom.create(Component.ComponentId{12n}, message(), Some{absent}, theme, markdown, 1n)
        fallbackCase(Custom.borrow(omitted))
        C.dispose(Extensions.MessageRenderInput, Extensions.MessageRenderResult(), absent)
        default : Custom.Owner <- Custom.create(Component.ComponentId{13n}, message(), None{}, theme, markdown, 1n)
        fallbackCase(Custom.borrow(default))
        unused : Counts <- Ref.dispose(Counts, counter)
        skill : Custom.Owner <- Custom.create(Component.ComponentId{15n},Core.CustomMessage{"skill",Ai.UserText{"fallback body"},True{},None{},F.fromU32(0)},None{},theme,markdown,1n)
        fallbackCase(Custom.borrow(skill))
        paddingCase(theme,markdown)
        transcriptCase(theme,markdown)
        mouseCase(theme,markdown)
        gestureCase(theme,markdown)
        Styles.dispose(styles)
        IO.print("custom renderer lifecycle and default fallbacks pass")
def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, Theme.LoadError, Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json", Color.Palette256{})
    +theme : Theme.Theme <- requireTheme(result)
    highlighter : Highlight.Highlighter <- Highlight.create("packages/runtime/data/highlight")
    styles : Styles.Styles <- Styles.create(theme, highlighter)
    runStyle(Styles.borrow(styles), theme)
