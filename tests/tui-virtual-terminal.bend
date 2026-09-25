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
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/ai/src/utils/json.bend as Json
import ../packages/ai/src/utils/schema-json.bend as S

# Drives the native TUI through a JSON script and prints, per render, the
# ordered terminal writes as one JSON array of strings. The upstream
# VirtualTerminal (xterm headless) replays them in tests/tui_virtual_terminal.ts,
# which applies the upstream test assertions. Test-only.
#
# Operations: {"op":"add","lines":[...]} adds a component rendering those
# lines; {"op":"set","component":i,"lines":[...]} changes component i's lines;
# {"op":"overlay","lines":[...],"options":{...}} shows an overlay;
# {"op":"hide","overlay":k} hides the k-th overlay shown; {"op":"hideTop"}
# is upstream's tui.hideOverlay(); {"op":"clear"} removes every child;
# {"op":"clearOnShrink"} is tui.setClearOnShrink(true);
# {"op":"render","width":w,"height":h,"termux":b} draws a frame (as in Termux
# when b) and prints {"writes":[...],"widths":[...],"redraws":n}: the widths
# each component (by id) was last asked to render at, and the full redraws
# so far (upstream's tui.fullRedraws). A line is a string or
# {"prefix":p,"fill":c,"less":n,"suffix":s}: c repeated (width - n) times.

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

# A component's lines and the width it was last asked to render at.
type Content is Data: Content{lines: Ref.Ref<List<&2, Line>>, width: Ref.Ref<Maybe<&2, Nat>>}

type Harness is Data:
  Harness{tui: Tui.TuiBase, screen: Screen.State, contents: List<&2, Content>, overlays: List<&2, O.OverlayHandle>, mounted: List<&2, C.ComponentId>}

def drawn(content: Content, +width: Nat) -> IO(List<&2, String>):
  match content:
    case Content{lines, asked}:
      do IO<List<&2, String>>:
        Ref.write(Maybe<&2, Nat>, asked, Some{width})
        values : List<&2, Line> <- Ref.read(List<&2, Line>, lines)
        return showLines(width, values)
def draw(content: Content, width: Nat) -> IO(List<&2, String>): drawn(content, width)
def quiet(content: Content, unused: Unit) -> IO(Unit): IO.pure(Unit, Unit{})

def component(+id: Nat, +content: Content) -> IO(C.Component):
  do IO<C.Component>:
    render : Call.Callback<Nat, List<&2, String>> <- Call.create(~Content, ~Nat, ~List<&2, String>, ~draw, content)
    invalidate : Call.Callback<Unit, Unit> <- Call.create(~Content, ~Unit, ~Unit, ~quiet, content)
    return C.Component{C.ComponentId{id}, render, None{}, None{}, invalidate, None{}, False{}}

# A new component: its id is its index in `contents`.
def created(+initial: List<&2, Line>, +contents: List<&2, Content>) -> IO(C.Component & List<&2, Content>):
  do IO<C.Component & List<&2, Content>>:
    +lines : Ref.Ref<List<&2, Line>> <- Ref.new(List<&2, Line>, initial)
    +width : Ref.Ref<Maybe<&2, Nat>> <- Ref.new(Maybe<&2, Nat>, None{})
    made : C.Component <- component(List.length(&2, Content, contents), Content{lines, width})
    return (made, List.append(&2, Content, contents, Content{lines, width} <> Nil{}))

def nth(-A: Data, values: List<&2, A>, index: Nat) -> Maybe<&2, A>:
  match values index:
    case Nil{} _: None{}
    case value <> _ Zero{}: Some{value}
    case _ <> rest Succ{before}: nth(A, rest, before)

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
def widths(contents: List<&2, Content>) -> IO(List<&2, V.Value>):
  match contents:
    case Nil{}: IO.pure(List<&2, V.Value>, Nil{})
    case Content{_, width} <> rest:
      do IO<List<&2, V.Value>>:
        asked : Maybe<&2, Nat> <- Ref.read(Maybe<&2, Nat>, width)
        later : List<&2, V.Value> <- widths(rest)
        return widthValue(asked) <> later

def redraws(state: Screen.State) -> V.Value:
  match state:
    case Screen.State{_, _, count}: V.Number{T.dimension(count)}
def report(output: Screen.Stream, asked: List<&2, V.Value>, state: Screen.State) -> String:
  Maybe.default(&2, String, Json.stringify(S.toJson(V.ObjectValue{R.Record{R.Property{"writes", V.ArrayValue{events(output)}} <> R.Property{"widths", V.ArrayValue{asked}} <> R.Property{"redraws", redraws(state)} <> Nil{}}})), "null")

def planned(plan: Result<&2, &2, Screen.RenderError, Screen.Plan>, +prepared: Tui.PreparedFrame, +contents: List<&2, Content>, overlays: List<&2, O.OverlayHandle>, mounted: List<&2, C.ComponentId>) -> IO(Harness):
  match plan:
    case Fail{_}: IO.die(Harness, 1, "render failed")
    case Done{Screen.Plan{+state, output, _}}:
      do IO<Harness>:
        asked : List<&2, V.Value> <- widths(contents)
        IO.print(report(output, asked, state))
        return Harness{Tui.commitFrame(prepared), state, contents, overlays, mounted}

def emitted(+prepared: Tui.PreparedFrame, harness: Harness, +width: Nat, +height: Nat, termux: Bool) -> IO(Harness):
  match harness:
    case Harness{_, screen, contents, overlays, mounted}: planned(Process.planned(prepared, screen, termux, width, height), prepared, contents, overlays, mounted)

def rendered(result: Tui.ResultOf(Tui.PreparedFrame), harness: Harness, +width: Nat, +height: Nat, termux: Bool) -> IO(Harness):
  match result:
    case Fail{_}: IO.die(Harness, 1, "compose failed")
    case Done{prepared}: emitted(prepared, harness, width, height, termux)

def render(+harness: Harness, +width: Nat, +height: Nat, termux: Bool) -> IO(Harness):
  match harness:
    case Harness{+tui, screen, contents, overlays, mounted}:
      do IO<Harness>:
        prepared : Tui.ResultOf(Tui.PreparedFrame) <- Tui.renderRoot(tui, width, height)
        rendered(prepared, Harness{tui, screen, contents, overlays, mounted}, width, height, termux)

def joined(pair: C.Component & List<&2, Content>, tui: Tui.TuiBase, screen: Screen.State, overlays: List<&2, O.OverlayHandle>, mounted: List<&2, C.ComponentId>) -> Harness:
  match pair:
    case (+made, contents): Harness{Tui.added(tui, made), screen, contents, overlays, C.id(made) <> mounted}

def add(harness: Harness, +initial: List<&2, Line>) -> IO(Harness):
  match harness:
    case Harness{tui, screen, contents, overlays, mounted}:
      do IO<Harness>:
        pair : C.Component & List<&2, Content> <- created(initial, contents)
        return joined(pair, tui, screen, overlays, mounted)

def replaced(found: Maybe<&2, Content>, +replacement: List<&2, Line>) -> IO(Unit):
  match found:
    case None{}: IO.die(Unit, 1, "no such component")
    case Some{Content{lines, _}}: Ref.write(List<&2, Line>, lines, replacement)

def set(harness: Harness, +index: Nat, +replacement: List<&2, Line>) -> IO(Harness):
  match harness:
    case Harness{tui, screen, +contents, overlays, mounted}:
      do IO<Harness>:
        replaced(nth(Content, contents, index), replacement)
        return Harness{tui, screen, contents, overlays, mounted}

def changed(change: Tui.OverlayChange, screen: Screen.State, contents: List<&2, Content>, overlays: List<&2, O.OverlayHandle>, mounted: List<&2, C.ComponentId>) -> Harness:
  match change:
    case Tui.OverlayChange{tui, _, _, _, _}: Harness{tui, screen, contents, overlays, mounted}

def shownOverlay(change: Tui.OverlayChange, screen: Screen.State, contents: List<&2, Content>, overlays: List<&2, O.OverlayHandle>, mounted: List<&2, C.ComponentId>) -> Harness:
  match change:
    case Tui.OverlayChange{tui, handle, _, _, _}: Harness{tui, screen, contents, List.append(&2, O.OverlayHandle, overlays, handle <> Nil{}), mounted}

def placed(pair: C.Component & List<&2, Content>, +options: V.Value, tui: Tui.TuiBase, screen: Screen.State, overlays: List<&2, O.OverlayHandle>, +mounted: List<&2, C.ComponentId>) -> Harness:
  match pair:
    case (made, contents): shownOverlay(Tui.addOverlay(tui, made, geometry(options), False{}, True{}, mounted), screen, contents, overlays, mounted)

def overlay(harness: Harness, +initial: List<&2, Line>, +options: V.Value) -> IO(Harness):
  match harness:
    case Harness{tui, screen, contents, overlays, mounted}:
      do IO<Harness>:
        pair : C.Component & List<&2, Content> <- created(initial, contents)
        return placed(pair, options, tui, screen, overlays, mounted)

def hiddenBy(found: Maybe<&2, O.OverlayHandle>, harness: Harness) -> IO(Harness):
  match found harness:
    case None{} _: IO.die(Harness, 1, "no such overlay")
    case Some{handle} Harness{tui, screen, contents, overlays, +mounted}: IO.pure(Harness, changed(Tui.overlayRemoved(tui, handle, mounted), screen, contents, overlays, mounted))

def hide(harness: Harness, index: Nat) -> IO(Harness):
  match harness:
    case Harness{tui, screen, contents, +overlays, mounted}: hiddenBy(nth(O.OverlayHandle, overlays, index), Harness{tui, screen, contents, overlays, mounted})

def toppled(change: Maybe<&2, Tui.OverlayChange>, harness: Harness) -> Harness:
  match change harness:
    case None{} _: harness
    case Some{done} Harness{_, screen, contents, overlays, mounted}: changed(done, screen, contents, overlays, mounted)

def hideTop(harness: Harness) -> Harness:
  match harness:
    case Harness{+tui, screen, contents, overlays, +mounted}: toppled(Tui.hideOverlay(tui, mounted), Harness{tui, screen, contents, overlays, mounted})

def flag(value: V.Value) -> Bool:
  match value:
    case V.Boolean{value}: value
    case _: False{}

def clearingOnShrink(harness: Harness) -> Harness:
  match harness:
    case Harness{tui, screen, contents, overlays, mounted}: Harness{Tui.setTerminalPreferences(tui, False{}, True{}), screen, contents, overlays, mounted}

def cleared(harness: Harness) -> Harness:
  match harness:
    case Harness{tui, screen, contents, overlays, mounted}: Harness{Tui.cleared(tui), screen, contents, overlays, mounted}

def dispatch(+kind: String, harness: Harness, +operation: V.Value) -> IO(Harness):
  match kind:
    case "add": add(harness, lines(get(operation, "lines")))
    case "set": set(harness, number(get(operation, "component")), lines(get(operation, "lines")))
    case "overlay": overlay(harness, lines(get(operation, "lines")), get(operation, "options"))
    case "hide": hide(harness, number(get(operation, "overlay")))
    case "hideTop": IO.pure(Harness, hideTop(harness))
    case "clear": IO.pure(Harness, cleared(harness))
    case "clearOnShrink": IO.pure(Harness, clearingOnShrink(harness))
    case "render": render(harness, number(get(operation, "width")), number(get(operation, "height")), flag(get(operation, "termux")))
    case _: IO.die(Harness, 1, "unknown operation")

def step(harness: Harness, +operation: V.Value) -> IO(Harness): dispatch(text(get(operation, "op")), harness, operation)

def steps(operations: List<&2, V.Value>, harness: Harness) -> IO(Unit):
  match operations:
    case Nil{}: IO.pure(Unit, Unit{})
    case operation <> rest:
      do IO<Unit>:
        next : Harness <- step(harness, operation)
        steps(rest, next)

def script(value: Result<&2, &2, J.ParseError, V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{operations}}: steps(operations, Harness{Tui.newTui(), Screen.initial(), Nil{}, Nil{}, Nil{}})
    case _: IO.die(Unit, 1, "expected a JSON array of operations")

def run(args: List<String>) -> IO(Unit):
  match args:
    case arg <> Nil{}: script(J.parse(arg))
    case _: IO.die(Unit, 1, "usage: tui-virtual-terminal '<operations>'")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
