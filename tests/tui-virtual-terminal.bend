import Base
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/tui.bend as T
import ../packages/tui/src/tui-base.bend as Tui
import ../packages/tui/src/tui-main-screen.bend as Screen
import ../packages/tui/src/tui-process.bend as Process
import ../packages/tui/src/overlays.bend as O
import ../packages/runtime/src/callback.bend as Call
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/ai/src/utils/json.bend as Json
import ../packages/ai/src/utils/schema-json.bend as S

# Drives the native TUI through a JSON script. Each render prints its ordered
# terminal writes; the upstream VirtualTerminal (xterm headless) replays them
# in tests/tui_virtual_terminal.ts, which applies the upstream test
# assertions. Test-only.
#
# Components are numbered in creation order. {"op":"component","lines":[...],
# "focusable":b,"on":{data:[operations]}} creates one: a focusable component
# records its input and `focused` flag, and on input `data` performs the listed
# operations. {"op":"add"} adds a child: a new component (the same fields) or
# {"component":i}; {"op":"set","component":i,"lines":[...]} changes its lines;
# {"op":"clear"} removes every child; {"op":"setFocus","component":i|null}.
# {"op":"overlay","options":{...}} shows a new component or {"component":i} as
# an overlay (options as upstream's OverlayOptions; "visible" is a boolean).
# Overlay handle operations take {"overlay":k}, the k-th overlay shown: "hide",
# "focus", "unfocus" (with an optional "target": i or null), "setHidden"
# ("hidden": b) and "visible" ("visible": b, the value its predicate now
# returns). {"op":"hideTop"} is tui.hideOverlay(); {"op":"input","data":d} is
# terminal.sendInput(d); {"op":"clearOnShrink"} is tui.setClearOnShrink(true).
# {"op":"check"} prints {"components":[{"width","inputs","focused"}],
# "focused":[...]}: per component the width it was last asked to render at,
# its input and focus; per overlay OverlayHandle.isFocused().
# {"op":"render","width":w,"height":h,"termux":b,"force":f} draws a frame (forced
# like requestRender(true) when f; as in Termux
# when b) and prints the same with "writes" and "redraws" (upstream's
# tui.fullRedraws). A line is a string or {"prefix":p,"fill":c,"less":n,
# "suffix":s}: c repeated (width - n) times.

def get(value: V.Value, key: String) -> V.Value:
  match value:
    case V.ObjectValue{fields}: Maybe.default(&2, V.Value, R.get(V.Value, fields, key), V.Null{})
    case _: V.Null{}
def text(value: V.Value) -> String:
  match value:
    case V.Text{value}: value
    case _: ""
def number(value: V.Value) -> Nat:
  match value:
    case V.Number{value}: U32.to_nat(F64.to_u32(value))
    case _: 0n
def texts(values: List<&2, V.Value>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: text(value) <> texts(rest)
type Line is Data:
  Plain{text: String}
  Fill{prefix: String, fill: String, less: Nat, suffix: String}
def line(+value: V.Value) -> Line:
  match value:
    case V.Text{text}: Plain{text}
    case _: Fill{text(get(value, "prefix")), text(get(value, "fill")), number(get(value, "less")), text(get(value, "suffix"))}
def lineList(values: List<&2, V.Value>) -> List<&2, Line>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: line(value) <> lineList(rest)
def lines(value: V.Value) -> List<&2, Line>:
  match value:
    case V.ArrayValue{items}: lineList(items)
    case _: Nil{}
def repeated(+fill: String, count: Nat) -> String:
  match count:
    case Zero{}: ""
    case Succ{rest}: fill ++ repeated(fill, rest)
def shown(width: Nat, value: Line) -> String:
  match value:
    case Plain{text}: text
    case Fill{prefix, fill, less, suffix}: prefix ++ repeated(fill, width - less) ++ suffix
def showLines(+width: Nat, values: List<&2, Line>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: shown(width, value) <> showLines(width, rest)

# Overlay options as upstream's OverlayOptions; the runner writes "N%" as
# {"percent": N}.
def fraction(value: V.Value) -> F64:
  match value:
    case V.Number{value}: value
    case _: U32.to_f64(0)
def size(+value: V.Value) -> Maybe<&2, T.SizeValue>:
  match value:
    case V.Number{cells}: Some{T.Cells{U32.to_nat(F64.to_u32(cells))}}
    case V.ObjectValue{_}: Some{T.Percent{fraction(get(value, "percent"))}}
    case _: None{}
def signedOffset(+value: F64) -> T.Offset:
  Bool.pick(T.Offset, F64.is_lt(value, U32.to_f64(0)), T.Backward{U32.to_nat(F64.to_u32(F64.neg(value)))}, T.Forward{U32.to_nat(F64.to_u32(value))})
def offset(value: V.Value) -> T.Offset:
  match value:
    case V.Number{value}: signedOffset(value)
    case _: T.Forward{0n}
def anchor(+name: String) -> T.OverlayAnchor:
  match name:
    case "top-left": T.TopLeft{}
    case "top-right": T.TopRight{}
    case "bottom-left": T.BottomLeft{}
    case "bottom-right": T.BottomRight{}
    case "top-center": T.TopCenter{}
    case "bottom-center": T.BottomCenter{}
    case "left-center": T.LeftCenter{}
    case "right-center": T.RightCenter{}
    case _: T.Center{}
def margin(+value: V.Value) -> T.OverlayMargin:
  match value:
    case V.Number{_}: T.OverlayMargin{number(value), number(value), number(value), number(value)}
    case V.ObjectValue{_}: T.OverlayMargin{number(get(value, "top")), number(get(value, "right")), number(get(value, "bottom")), number(get(value, "left"))}
    case _: T.OverlayMargin{0n, 0n, 0n, 0n}
def geometry(+options: V.Value) -> T.OverlayGeometry:
  T.OverlayGeometry{size(get(options, "width")), number(get(options, "minWidth")), size(get(options, "maxHeight")), anchor(text(get(options, "anchor"))), offset(get(options, "offsetX")), offset(get(options, "offsetY")), size(get(options, "row")), size(get(options, "col")), margin(get(options, "margin"))}
# A component: its lines, the width it was last asked to render at, and, when
# focusable, the input it received and its `focused` flag.
type Content is Data: Content{lines: Ref.Ref<List<&2, Line>>, width: Ref.Ref<Maybe<&2, Nat>>, inputs: Ref.Ref<List<&2, String>>, focused: Ref.Ref<Bool>}

def drawn(content: Content, +width: Nat) -> IO(List<&2, String>):
  match content:
    case Content{lines, asked, _, _}:
      do IO<List<&2, String>>:
        Ref.write(Maybe<&2, Nat>, asked, Some{width})
        values : List<&2, Line> <- Ref.read(List<&2, Line>, lines)
        return showLines(width, values)
def draw(content: Content, width: Nat) -> IO(List<&2, String>): drawn(content, width)
def quiet(content: Content, unused: Unit) -> IO(Unit): IO.pure(Unit, Unit{})

# A focusable component's handleInput records the data and queues the
# operations its script lists under that data ("on"). The harness runs them as
# soon as the input dispatch returns; upstream runs them inside handleInput,
# after which dispatch returns at once.
type Reactor is Data: Reactor{inputs: Ref.Ref<List<&2, String>>, pending: Ref.Ref<List<&2, V.Value>>, on: V.Value}
def reaction(value: V.Value) -> List<&2, V.Value>:
  match value:
    case V.ArrayValue{operations}: operations
    case _: Nil{}
def appended(-A: Data, +reference: Ref.Ref<List<&2, A>>, more: List<&2, A>) -> IO(Unit):
  do IO<Unit>:
    values : List<&2, A> <- Ref.read(List<&2, A>, reference)
    Ref.write(List<&2, A>, reference, List.append(&2, A, values, more))
def reacted(reactor: Reactor, +data: String) -> IO(Unit):
  match reactor:
    case Reactor{inputs, pending, on}:
      do IO<Unit>:
        appended(String, inputs, data <> Nil{})
        appended(V.Value, pending, reaction(get(on, data)))
def react(reactor: Reactor, data: String) -> IO(Unit): reacted(reactor, data)
def setFlag(flag: Ref.Ref<Bool>, value: Bool) -> IO(Unit): Ref.write(Bool, flag, value)

def plain(+id: Nat, +content: Content) -> IO(C.Component):
  do IO<C.Component>:
    render : Call.Callback<Nat, List<&2, String>> <- Call.create(~Content, ~Nat, ~List<&2, String>, ~draw, content)
    invalidate : Call.Callback<Unit, Unit> <- Call.create(~Content, ~Unit, ~Unit, ~quiet, content)
    return C.Component{C.ComponentId{id}, render, None{}, None{}, invalidate, None{}, False{}}
def withFocus(made: C.Component, input: Call.Callback<String, Unit>, focus: Call.Callback<Bool, Unit>) -> C.Component:
  match made:
    case C.Component{id, render, _, mouse, invalidate, _, release}: C.Component{id, render, Some{input}, mouse, invalidate, Some{focus}, release}
def focusable(+id: Nat, +content: Content, reactor: Reactor) -> IO(C.Component):
  match content:
    case Content{lines, width, inputs, +flag}:
      do IO<C.Component>:
        made : C.Component <- plain(id, Content{lines, width, inputs, flag})
        input : Call.Callback<String, Unit> <- Call.create(~Reactor, ~String, ~Unit, ~react, reactor)
        focus : Call.Callback<Bool, Unit> <- Call.create(~Ref.Ref<Bool>, ~Bool, ~Unit, ~setFlag, flag)
        return withFocus(made, input, focus)

def nth(-A: Data, values: List<&2, A>, index: Nat) -> Maybe<&2, A>:
  match values index:
    case Nil{} _: None{}
    case value <> _ Zero{}: Some{value}
    case _ <> rest Succ{before}: nth(A, rest, before)

# Components are numbered in creation order (their ComponentId); `overlays`
# holds the handles in the order shown; `mounted` the root children, which
# upstream's isComponentMounted walks.
type Scene is Data:
  Scene{contents: List<&2, Content>, registry: List<&2, C.Component>, overlays: List<&2, O.OverlayHandle>, mounted: List<&2, C.ComponentId>, pending: Ref.Ref<List<&2, V.Value>>}
type Harness is Data: Harness{tui: Tui.TuiBase, screen: Screen.State, scene: Scene}

def flag(value: V.Value) -> Bool:
  match value:
    case V.Boolean{value}: value
    case _: False{}
def field(value: V.Value, key: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, key)
    case _: None{}

def made(+component: C.Component, contents: List<&2, Content>, +content: Content, registry: List<&2, C.Component>, overlays: List<&2, O.OverlayHandle>, mounted: List<&2, C.ComponentId>, pending: Ref.Ref<List<&2, V.Value>>) -> C.Component & Scene:
  (component, Scene{List.append(&2, Content, contents, content <> Nil{}), List.append(&2, C.Component, registry, component <> Nil{}), overlays, mounted, pending})
def build(+id: Nat, +content: Content, +operation: V.Value, +pending: Ref.Ref<List<&2, V.Value>>) -> IO(C.Component):
  match content:
    case Content{_, _, +inputs, _}:
      Bool.pick(Unit -> IO(C.Component), flag(get(operation, "focusable")), _ => focusable(id, content, Reactor{inputs, pending, get(operation, "on")}), _ => plain(id, content))(Unit{})
def assembled(+content: Content, operation: V.Value, scene: Scene) -> IO(C.Component & Scene):
  match scene:
    case Scene{+contents, registry, overlays, mounted, +pending}:
      do IO<C.Component & Scene>:
        component : C.Component <- build(List.length(&2, Content, contents), content, operation, pending)
        return made(component, contents, content, registry, overlays, mounted, pending)
# {"lines":[...],"focusable":b,"on":{data:[operations]}} as a new component.
def create(scene: Scene, +operation: V.Value) -> IO(C.Component & Scene):
  do IO<C.Component & Scene>:
    shown : Ref.Ref<List<&2, Line>> <- Ref.new(List<&2, Line>, lines(get(operation, "lines")))
    width : Ref.Ref<Maybe<&2, Nat>> <- Ref.new(Maybe<&2, Nat>, None{})
    inputs : Ref.Ref<List<&2, String>> <- Ref.new(List<&2, String>, Nil{})
    focused : Ref.Ref<Bool> <- Ref.new(Bool, False{})
    assembled(Content{shown, width, inputs, focused}, operation, scene)
def existing(found: Maybe<&2, C.Component>, scene: Scene) -> IO(C.Component & Scene):
  match found:
    case None{}: IO.die(C.Component & Scene, 1, "no such component")
    case Some{component}: IO.pure(C.Component & Scene, (component, scene))
def registryOf(scene: Scene) -> List<&2, C.Component>:
  match scene:
    case Scene{_, registry, _, _, _}: registry
# An existing component ({"component": i}) or a new one.
def obtained(index: Maybe<&2, V.Value>, +scene: Scene, operation: V.Value) -> IO(C.Component & Scene):
  match index:
    case Some{index}: existing(nth(C.Component, registryOf(scene), number(index)), scene)
    case None{}: create(scene, operation)
def obtain(scene: Scene, +operation: V.Value) -> IO(C.Component & Scene): obtained(field(operation, "component"), scene, operation)
def componentId(value: V.Value) -> Maybe<&2, C.ComponentId>:
  match value:
    case V.Number{_}: Some{C.ComponentId{number(value)}}
    case _: None{}

def written(value: Screen.Effect) -> V.Value:
  match value:
    case Screen.Write{text}: V.Text{text}
    case Screen.Visibility{True{}}: V.Text{"\u{1b}[?25h"}
    case Screen.Visibility{False{}}: V.Text{"\u{1b}[?25l"}
@unsafe def drained(batch: Maybe<&2, Screen.Batch>, acc: List<&2, V.Value>) -> List<&2, V.Value>:
  match batch:
    case None{}: List.reverse(&2, V.Value, acc)
    case Some{Screen.Batch{effect, rest}}: drained(Screen.nextEffect(rest), written(effect) <> acc)
def events(stream: Screen.Stream) -> List<&2, V.Value>: drained(Screen.nextEffect(stream), Nil{})

def widthValue(value: Maybe<&2, Nat>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{width}: V.Number{T.dimension(width)}
def object(properties: List<&2, R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{properties}}
def seen(inputs: List<&2, String>) -> List<&2, V.Value>:
  match inputs:
    case Nil{}: Nil{}
    case value <> rest: V.Text{value} <> seen(rest)
# Per component: the width it was last asked to render at, its input and focus.
def states(contents: List<&2, Content>) -> IO(List<&2, V.Value>):
  match contents:
    case Nil{}: IO.pure(List<&2, V.Value>, Nil{})
    case Content{_, width, inputs, focused} <> rest:
      do IO<List<&2, V.Value>>:
        asked : Maybe<&2, Nat> <- Ref.read(Maybe<&2, Nat>, width)
        received : List<&2, String> <- Ref.read(List<&2, String>, inputs)
        focus : Bool <- Ref.read(Bool, focused)
        later : List<&2, V.Value> <- states(rest)
        return object(R.Property{"width", widthValue(asked)} <> R.Property{"inputs", V.ArrayValue{seen(received)}} <> R.Property{"focused", V.Boolean{focus}} <> Nil{}) <> later
def handlesFocused(+tui: Tui.TuiBase, handles: List<&2, O.OverlayHandle>) -> List<&2, V.Value>:
  match handles:
    case Nil{}: Nil{}
    case handle <> rest: V.Boolean{Tui.isOverlayFocused(tui, handle)} <> handlesFocused(tui, rest)
def printed(properties: List<&2, R.Property<V.Value>>) -> IO(Unit):
  IO.print(Maybe.default(&2, String, Json.stringify(S.toJson(object(properties))), "null"))
# Every report has "components" and "focused" (OverlayHandle.isFocused per
# overlay shown); a render adds its "writes" and "redraws" (upstream's
# tui.fullRedraws).
def reported(+tui: Tui.TuiBase, scene: Scene, more: List<&2, R.Property<V.Value>>) -> IO(Unit):
  match scene:
    case Scene{contents, _, overlays, _, _}:
      do IO<Unit>:
        components : List<&2, V.Value> <- states(contents)
        printed(List.append(&2, R.Property<V.Value>, more, R.Property{"components", V.ArrayValue{components}} <> R.Property{"focused", V.ArrayValue{handlesFocused(tui, overlays)}} <> Nil{}))
def check(harness: Harness) -> IO(Harness):
  match harness:
    case Harness{+tui, screen, +scene}:
      do IO<Harness>:
        reported(tui, scene, Nil{})
        return Harness{tui, screen, scene}

def redraws(state: Screen.State) -> V.Value:
  match state:
    case Screen.State{_, _, count}: V.Number{T.dimension(count)}
def planned(plan: Result<&2, &2, Screen.RenderError, Screen.Plan>, +prepared: Tui.PreparedFrame, +scene: Scene) -> IO(Harness):
  match plan:
    case Fail{_}: IO.die(Harness, 1, "render failed")
    case Done{Screen.Plan{+state, output, _}}:
      +tui = Tui.commitFrame(prepared)
      do IO<Harness>:
        reported(tui, scene, R.Property{"writes", V.ArrayValue{events(output)}} <> R.Property{"redraws", redraws(state)} <> Nil{})
        return Harness{tui, state, scene}
# A forced render resets the screen state first, as tui-process does for
# the scheduler's ResetRenderState effect (upstream requestRender(true)).
def fresh(screen: Screen.State, force: Bool) -> Screen.State:
  match force:
    case True{}: Screen.resetRenderState(screen)
    case False{}: screen
def rendered(result: Tui.ResultOf(Tui.PreparedFrame), harness: Harness, +width: Nat, +height: Nat, termux: Bool, force: Bool) -> IO(Harness):
  match result harness:
    case Fail{_} _: IO.die(Harness, 1, "compose failed")
    case Done{+prepared} Harness{_, screen, scene}: planned(Process.planned(prepared, fresh(screen, force), termux, width, height), prepared, scene)
def render(+harness: Harness, +width: Nat, +height: Nat, termux: Bool, force: Bool) -> IO(Harness):
  match harness:
    case Harness{tui, _, _}:
      do IO<Harness>:
        prepared : Tui.ResultOf(Tui.PreparedFrame) <- Tui.renderRoot(tui, width, height)
        rendered(prepared, harness, width, height, termux, force)

# Focus changes run in source order through the components' setFocused.
def focusApplied(result: Tui.ResultOf(Tui.TuiBase), screen: Screen.State, scene: Scene) -> IO(Harness):
  match result:
    case Fail{_}: IO.die(Harness, 1, "focus change failed")
    case Done{tui}: IO.pure(Harness, Harness{tui, screen, scene})
def applied(change: Tui.OverlayChange, screen: Screen.State, +scene: Scene) -> IO(Harness):
  do IO<Harness>:
    result : Tui.ResultOf(Tui.TuiBase) <- Tui.applyOverlayChange(change, registryOf(scene))
    focusApplied(result, screen, scene)
def mountedOf(scene: Scene) -> List<&2, C.ComponentId>:
  match scene:
    case Scene{_, _, _, mounted, _}: mounted
def overlaysOf(scene: Scene) -> List<&2, O.OverlayHandle>:
  match scene:
    case Scene{_, _, overlays, _, _}: overlays
def withHandle(scene: Scene, handle: O.OverlayHandle) -> Scene:
  match scene:
    case Scene{contents, registry, overlays, mounted, pending}: Scene{contents, registry, List.append(&2, O.OverlayHandle, overlays, handle <> Nil{}), mounted, pending}
def mounting(scene: Scene, component: C.ComponentId) -> Scene:
  match scene:
    case Scene{contents, registry, overlays, mounted, pending}: Scene{contents, registry, overlays, List.append(&2, C.ComponentId, mounted, component <> Nil{}), pending}
def unmounted(scene: Scene) -> Scene:
  match scene:
    case Scene{contents, registry, overlays, _, pending}: Scene{contents, registry, overlays, Nil{}, pending}

def adding(pair: C.Component & Scene, tui: Tui.TuiBase, screen: Screen.State) -> Harness:
  match pair:
    case (+component, scene): Harness{Tui.added(tui, component), screen, mounting(scene, C.id(component))}
def add(harness: Harness, +operation: V.Value) -> IO(Harness):
  match harness:
    case Harness{tui, screen, scene}:
      do IO<Harness>:
        pair : C.Component & Scene <- obtain(scene, operation)
        return adding(pair, tui, screen)
def created(pair: C.Component & Scene, tui: Tui.TuiBase, screen: Screen.State) -> Harness:
  match pair:
    case (_, scene): Harness{tui, screen, scene}
def component(harness: Harness, +operation: V.Value) -> IO(Harness):
  match harness:
    case Harness{tui, screen, scene}:
      do IO<Harness>:
        pair : C.Component & Scene <- create(scene, operation)
        return created(pair, tui, screen)

def shownOverlay(change: Tui.OverlayChange, screen: Screen.State, scene: Scene) -> IO(Harness):
  match change:
    case Tui.OverlayChange{tui, +handle, changes, hide, render}: applied(Tui.OverlayChange{tui, handle, changes, hide, render}, screen, withHandle(scene, handle))
def showing(pair: C.Component & Scene, +options: V.Value, tui: Tui.TuiBase, screen: Screen.State) -> IO(Harness):
  match pair:
    case (component, +scene):
      shownOverlay(Tui.addOverlay(tui, component, geometry(options), flag(get(options, "nonCapturing")), Maybe.default(&2, Bool, Maybe.map(&2, V.Value, Bool, flag, field(options, "visible")), True{}), mountedOf(scene)), screen, scene)
def overlay(harness: Harness, +operation: V.Value) -> IO(Harness):
  match harness:
    case Harness{tui, screen, scene}:
      do IO<Harness>:
        pair : C.Component & Scene <- obtain(scene, operation)
        showing(pair, get(operation, "options"), tui, screen)

def replaced(found: Maybe<&2, Content>, +replacement: List<&2, Line>) -> IO(Unit):
  match found:
    case None{}: IO.die(Unit, 1, "no such component")
    case Some{Content{shown, _, _, _}}: Ref.write(List<&2, Line>, shown, replacement)
def contentsOf(scene: Scene) -> List<&2, Content>:
  match scene:
    case Scene{contents, _, _, _, _}: contents
def set(harness: Harness, +operation: V.Value) -> IO(Harness):
  match harness:
    case Harness{tui, screen, +scene}:
      do IO<Harness>:
        replaced(nth(Content, contentsOf(scene), number(get(operation, "component"))), lines(get(operation, "lines")))
        return Harness{tui, screen, scene}

# Overlay handle operations take {"overlay": k}, the k-th overlay shown.
type HandleOp is Data:
  Hide{}
  Focus{}
  Unfocus{target: Maybe<&2, Maybe<&2, C.ComponentId>>}
  SetHidden{hidden: Bool}
  Visible{shown: Bool}
def handled(operation: HandleOp, tui: Tui.TuiBase, +handle: O.OverlayHandle, screen: Screen.State, +scene: Scene) -> IO(Harness):
  match operation:
    case Hide{}: applied(Tui.overlayRemoved(tui, handle, mountedOf(scene)), screen, scene)
    case Focus{}: applied(Tui.focusOverlay(tui, handle, mountedOf(scene)), screen, scene)
    case Unfocus{target}: applied(Tui.unfocusOverlay(tui, handle, target, mountedOf(scene)), screen, scene)
    case SetHidden{hidden}: applied(Tui.setOverlayHidden(tui, handle, hidden, mountedOf(scene)), screen, scene)
    case Visible{shown}: IO.pure(Harness, Harness{Tui.withVisibility(tui, Tui.Visibility{handle, shown} <> Nil{}), screen, scene})
def onFound(found: Maybe<&2, O.OverlayHandle>, action: HandleOp, harness: Harness) -> IO(Harness):
  match found harness:
    case None{} _: IO.die(Harness, 1, "no such overlay")
    case Some{handle} Harness{tui, screen, scene}: handled(action, tui, handle, screen, scene)
def onHandle(harness: Harness, +operation: V.Value, action: HandleOp) -> IO(Harness):
  match harness:
    case Harness{tui, screen, +scene}: onFound(nth(O.OverlayHandle, overlaysOf(scene), number(get(operation, "overlay"))), action, Harness{tui, screen, scene})
def unfocusTarget(value: Maybe<&2, V.Value>) -> Maybe<&2, Maybe<&2, C.ComponentId>>:
  match value:
    case None{}: None{}
    case Some{target}: Some{componentId(target)}

def toppled(change: Maybe<&2, Tui.OverlayChange>, harness: Harness) -> IO(Harness):
  match change harness:
    case None{} _: IO.pure(Harness, harness)
    case Some{done} Harness{_, screen, scene}: applied(done, screen, scene)
def hideTop(harness: Harness) -> IO(Harness):
  match harness:
    case Harness{+tui, screen, +scene}: toppled(Tui.hideOverlay(tui, mountedOf(scene)), Harness{tui, screen, scene})

def setFocus(harness: Harness, +operation: V.Value) -> IO(Harness):
  match harness:
    case Harness{tui, screen, +scene}:
      do IO<Harness>:
        result : Tui.ResultOf(Tui.TuiBase) <- Tui.setFocus(tui, registryOf(scene), mountedOf(scene), componentId(get(operation, "component")))
        focusApplied(result, screen, scene)

# terminal.sendInput; `steps` then runs the operations the input queued.
def inputHandled(result: Tui.ResultOf(Tui.InputResult), screen: Screen.State, scene: Scene) -> IO(Harness):
  match result:
    case Fail{_}: IO.die(Harness, 1, "input dispatch failed")
    case Done{Tui.InputResult{tui, _, _}}: IO.pure(Harness, Harness{tui, screen, scene})
def input(harness: Harness, +operation: V.Value) -> IO(Harness):
  match harness:
    case Harness{tui, screen, +scene}:
      do IO<Harness>:
        result : Tui.ResultOf(Tui.InputResult) <- Tui.dispatchInput(tui, registryOf(scene), mountedOf(scene), text(get(operation, "data")))
        inputHandled(result, screen, scene)

def clearingOnShrink(harness: Harness) -> Harness:
  match harness:
    case Harness{tui, screen, scene}: Harness{Tui.setTerminalPreferences(tui, False{}, True{}), screen, scene}
def cleared(harness: Harness) -> Harness:
  match harness:
    case Harness{tui, screen, scene}: Harness{Tui.cleared(tui), screen, unmounted(scene)}

def dispatch(+kind: String, harness: Harness, +operation: V.Value) -> IO(Harness):
  match kind:
    case "component": component(harness, operation)
    case "add": add(harness, operation)
    case "set": set(harness, operation)
    case "overlay": overlay(harness, operation)
    case "hide": onHandle(harness, operation, Hide{})
    case "focus": onHandle(harness, operation, Focus{})
    case "unfocus": onHandle(harness, operation, Unfocus{unfocusTarget(field(operation, "target"))})
    case "setHidden": onHandle(harness, operation, SetHidden{flag(get(operation, "hidden"))})
    case "visible": onHandle(harness, operation, Visible{flag(get(operation, "visible"))})
    case "hideTop": hideTop(harness)
    case "setFocus": setFocus(harness, operation)
    case "input": input(harness, operation)
    case "clear": IO.pure(Harness, cleared(harness))
    case "clearOnShrink": IO.pure(Harness, clearingOnShrink(harness))
    case "check": check(harness)
    case "render": render(harness, number(get(operation, "width")), number(get(operation, "height")), flag(get(operation, "termux")), flag(get(operation, "force")))
    case _: IO.die(Harness, 1, "unknown operation")

def step(harness: Harness, +operation: V.Value) -> IO(Harness): dispatch(text(get(operation, "op")), harness, operation)

# Reactions are operations a component queued while handling input; they run
# before the rest of the script. They send no input, so queue nothing more.
def reactions(operations: List<&2, V.Value>, harness: Harness) -> IO(Harness):
  match operations:
    case Nil{}: IO.pure(Harness, harness)
    case operation <> rest:
      do IO<Harness>:
        next : Harness <- step(harness, operation)
        reactions(rest, next)
def steps(operations: List<&2, V.Value>, harness: Harness, +pending: Ref.Ref<List<&2, V.Value>>) -> IO(Unit):
  match operations:
    case Nil{}: IO.pure(Unit, Unit{})
    case operation <> rest:
      do IO<Unit>:
        next : Harness <- step(harness, operation)
        queued : List<&2, V.Value> <- Ref.swap(List<&2, V.Value>, pending, Nil{})
        after : Harness <- reactions(queued, next)
        steps(rest, after, pending)

def started(operations: List<&2, V.Value>, +pending: Ref.Ref<List<&2, V.Value>>) -> IO(Unit):
  steps(operations, Harness{Tui.newTui(), Screen.initial(), Scene{Nil{}, Nil{}, Nil{}, Nil{}, pending}}, pending)
def script(value: Result<&2, &2, J.ParseError, V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{operations}}:
      do IO<Unit>:
        pending : Ref.Ref<List<&2, V.Value>> <- Ref.new(List<&2, V.Value>, Nil{})
        started(operations, pending)
    case _: IO.die(Unit, 1, "expected a JSON array of operations")

# The script is the argument, or read from the file named after "@" (for
# scripts larger than one command-line argument may be).
def scriptText(text: Result<&2, &2, Utf8.Error, String>) -> IO(Unit):
  match text:
    case Fail{_}: IO.die(Unit, 1, "the script file is not UTF-8")
    case Done{text}: script(J.parse(text))
def scriptFile(bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> IO(Unit):
  match bytes:
    case Fail{_}: IO.die(Unit, 1, "cannot read the script file")
    case Done{bytes}: scriptText(Utf8.decodeStrict(bytes))
def argumentAt(file: Bool, +arg: String) -> IO(Unit):
  match file:
    case True{}:
      do IO<Unit>:
        bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(String.drop(arg, 1n))
        scriptFile(bytes)
    case False{}: script(J.parse(arg))
def argument(+arg: String) -> IO(Unit): argumentAt(String.starts_with(arg, "@"), arg)
def run(args: List<String>) -> IO(Unit):
  match args:
    case arg <> Nil{}: argument(arg)
    case _: IO.die(Unit, 1, "usage: tui-virtual-terminal '<operations>' | @file")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
