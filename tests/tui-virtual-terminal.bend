import Base
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/tui.bend as T
import ../packages/tui/src/tui-base.bend as Tui
import ../packages/tui/src/tui-main-screen.bend as Screen
import ../packages/tui/src/tui-process.bend as Process
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
# {"op":"clear"} removes every child; {"op":"render","width":w,"height":h}
# draws a frame.

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
def lines(value: V.Value) -> List<&2, String>:
  match value:
    case V.ArrayValue{items}: texts(items)
    case _: Nil{}

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

type Harness is Data:
  Harness{tui: Tui.TuiBase, screen: Screen.State, contents: List<&2, Ref.Ref<List<&2, String>>>, next: Nat, mounted: List<&2, C.ComponentId>}

def draw(content: Ref.Ref<List<&2, String>>, width: Nat) -> IO(List<&2, String>):
  Ref.read(List<&2, String>, content)
def quiet(content: Ref.Ref<List<&2, String>>, unused: Unit) -> IO(Unit): IO.pure(Unit, Unit{})

def component(+id: Nat, +content: Ref.Ref<List<&2, String>>) -> IO(C.Component):
  do IO<C.Component>:
    render : Call.Callback<Nat, List<&2, String>> <- Call.create(~Ref.Ref<List<&2, String>>, ~Nat, ~List<&2, String>, ~draw, content)
    invalidate : Call.Callback<Unit, Unit> <- Call.create(~Ref.Ref<List<&2, String>>, ~Unit, ~Unit, ~quiet, content)
    return C.Component{C.ComponentId{id}, render, None{}, None{}, invalidate, None{}, False{}}

def created(+initial: List<&2, String>, +id: Nat) -> IO(C.Component & Ref.Ref<List<&2, String>>):
  do IO<C.Component & Ref.Ref<List<&2, String>>>:
    +content : Ref.Ref<List<&2, String>> <- Ref.new(List<&2, String>, initial)
    made : C.Component <- component(id, content)
    return (made, content)

def nth(values: List<&2, Ref.Ref<List<&2, String>>>, index: Nat) -> Maybe<&2, Ref.Ref<List<&2, String>>>:
  match values index:
    case Nil{} _: None{}
    case value <> _ Zero{}: Some{value}
    case _ <> rest Succ{before}: nth(rest, before)

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

def planned(plan: Result<&2, &2, Screen.RenderError, Screen.Plan>, +prepared: Tui.PreparedFrame, contents: List<&2, Ref.Ref<List<&2, String>>>, next: Nat, mounted: List<&2, C.ComponentId>) -> IO(Harness):
  match plan:
    case Fail{_}: IO.die(Harness, 1, "render failed")
    case Done{Screen.Plan{+state, output, _}}:
      do IO<Harness>:
        IO.print(Maybe.default(&2, String, Json.stringify(S.toJson(V.ArrayValue{events(output)})), "[]"))
        return Harness{Tui.commitFrame(prepared), state, contents, next, mounted}

def emitted(+prepared: Tui.PreparedFrame, harness: Harness, +width: Nat, +height: Nat) -> IO(Harness):
  match harness:
    case Harness{_, screen, contents, next, mounted}: planned(Process.planned(prepared, screen, False{}, width, height), prepared, contents, next, mounted)

def rendered(result: Tui.ResultOf(Tui.PreparedFrame), harness: Harness, +width: Nat, +height: Nat) -> IO(Harness):
  match result:
    case Fail{_}: IO.die(Harness, 1, "compose failed")
    case Done{prepared}: emitted(prepared, harness, width, height)

def render(+harness: Harness, +width: Nat, +height: Nat) -> IO(Harness):
  match harness:
    case Harness{+tui, screen, contents, next, mounted}:
      do IO<Harness>:
        prepared : Tui.ResultOf(Tui.PreparedFrame) <- Tui.renderRoot(tui, width, height)
        rendered(prepared, Harness{tui, screen, contents, next, mounted}, width, height)

def joined(pair: C.Component & Ref.Ref<List<&2, String>>, tui: Tui.TuiBase, screen: Screen.State, contents: List<&2, Ref.Ref<List<&2, String>>>, next: Nat, mounted: List<&2, C.ComponentId>) -> Harness:
  match pair:
    case (+made, content):
      Harness{Tui.added(tui, made), screen, List.append(&2, Ref.Ref<List<&2, String>>, contents, content <> Nil{}), next + 1n, C.id(made) <> mounted}

def add(harness: Harness, +initial: List<&2, String>) -> IO(Harness):
  match harness:
    case Harness{tui, screen, contents, +next, mounted}:
      do IO<Harness>:
        pair : C.Component & Ref.Ref<List<&2, String>> <- created(initial, next)
        return joined(pair, tui, screen, contents, next, mounted)

def replaced(found: Maybe<&2, Ref.Ref<List<&2, String>>>, +replacement: List<&2, String>) -> IO(Unit):
  match found:
    case None{}: IO.die(Unit, 1, "no such component")
    case Some{content}: Ref.write(List<&2, String>, content, replacement)

def set(harness: Harness, +index: Nat, +replacement: List<&2, String>) -> IO(Harness):
  match harness:
    case Harness{tui, screen, +contents, next, mounted}:
      do IO<Harness>:
        replaced(nth(contents, index), replacement)
        return Harness{tui, screen, contents, next, mounted}

def shown(change: Tui.OverlayChange, screen: Screen.State, contents: List<&2, Ref.Ref<List<&2, String>>>, next: Nat, mounted: List<&2, C.ComponentId>) -> Harness:
  match change:
    case Tui.OverlayChange{tui, _, _, _, _}: Harness{tui, screen, contents, next + 1n, mounted}

def placed(pair: C.Component & Ref.Ref<List<&2, String>>, options: V.Value, tui: Tui.TuiBase, screen: Screen.State, contents: List<&2, Ref.Ref<List<&2, String>>>, next: Nat, +mounted: List<&2, C.ComponentId>) -> Harness:
  match pair:
    case (made, _): shown(Tui.addOverlay(tui, made, geometry(options), False{}, True{}, mounted), screen, contents, next, mounted)

def overlay(harness: Harness, +initial: List<&2, String>, options: V.Value) -> IO(Harness):
  match harness:
    case Harness{tui, screen, contents, +next, mounted}:
      do IO<Harness>:
        pair : C.Component & Ref.Ref<List<&2, String>> <- created(initial, next)
        return placed(pair, options, tui, screen, contents, next, mounted)

def cleared(harness: Harness) -> Harness:
  match harness:
    case Harness{tui, screen, contents, next, mounted}: Harness{Tui.cleared(tui), screen, contents, next, mounted}

def dispatch(+kind: String, harness: Harness, +operation: V.Value) -> IO(Harness):
  match kind:
    case "add": add(harness, lines(get(operation, "lines")))
    case "set": set(harness, number(get(operation, "component")), lines(get(operation, "lines")))
    case "overlay": overlay(harness, lines(get(operation, "lines")), get(operation, "options"))
    case "clear": IO.pure(Harness, cleared(harness))
    case "render": render(harness, number(get(operation, "width")), number(get(operation, "height")))
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
    case Done{V.ArrayValue{operations}}: steps(operations, Harness{Tui.newTui(), Screen.initial(), Nil{}, 0n, Nil{}})
    case _: IO.die(Unit, 1, "expected a JSON array of operations")

def run(args: List<String>) -> IO(Unit):
  match args:
    case arg <> Nil{}: script(J.parse(arg))
    case _: IO.die(Unit, 1, "usage: tui-virtual-terminal '<operations>'")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
