import Base
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/tui.bend as T
import ../packages/runtime/src/callback.bend as Call
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/f64.bend as F
import ../packages/ai/src/utils/json.bend as Json
import ../packages/ai/src/utils/schema-json.bend as S

def get(value: V.Value,key: String) -> V.Value:
  match value:
    case V.ObjectValue{fields}: Maybe.default(&2,V.Value,R.get(V.Value,fields,key),V.Null{})
    case _: V.Null{}
def text(value: V.Value) -> String:
  match value:
    case V.Text{value}: value
    case _: ""
def number(value: V.Value) -> Nat:
  match value:
    case V.Number{value}: U32.to_nat(F64.to_u32(value))
    case _: 0n
def boolean(value: V.Value) -> Bool:
  match value:
    case V.Boolean{value}: value
    case _: False{}
def optionalBool(value: V.Value) -> Maybe<&2,Bool>:
  match value:
    case V.Boolean{value}: Some{value}
    case _: None{}
def boolValue(value: Maybe<&2,Bool>) -> V.Value:
  match value:
    case Some{value}: V.Boolean{value}
    case None{}: V.Null{}
def array(value: V.Value) -> List<&2,V.Value>:
  match value:
    case V.ArrayValue{items}: items
    case _: Nil{}
def n(value: Nat) -> V.Value: V.Number{T.dimension(value)}
def field(key: String,value: V.Value) -> R.Property<V.Value>: R.Property{key,value}
def object(fields: List<&2,R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def offset(value: V.Value) -> T.Offset:
  match value:
    case V.Number{+value}: Bool.pick(T.Offset,F.isGreater(F.compare(F.fromU32(0),value)),T.Backward{U32.to_nat(F64.to_u32(F.negate(value)))},T.Forward{U32.to_nat(F64.to_u32(value))})
    case _: T.Forward{0n}
def signed(value: T.Offset) -> V.Value:
  match value:
    case T.Forward{value}: n(value)
    case T.Backward{value}: V.Number{F.negate(T.dimension(value))}
def mouseKind(value: V.Value) -> T.TuiMouseEventType:
  match value:
    case V.Text{"release"}: T.MouseRelease{}
    case V.Text{"move"}: T.MouseMove{}
    case V.Text{"drag"}: T.MouseDrag{}
    case V.Text{"click"}: T.MouseClick{}
    case V.Text{"wheel"}: T.MouseWheel{}
    case _: T.MousePress{}
def optionalOffset(value: V.Value) -> Maybe<&2,T.Offset>:
  match value:
    case V.Number{value}: Some{offset(V.Number{value})}
    case _: None{}
def optionalNatural(value: V.Value) -> Maybe<&2,Nat>:
  match value:
    case V.Number{value}: Some{number(V.Number{value})}
    case _: None{}
def mouseButton(value: V.Value) -> T.TuiMouseButton:
  match value:
    case V.Text{"middle"}: T.MouseMiddle{}
    case V.Text{"right"}: T.MouseRight{}
    case V.Text{"none"}: T.NoButton{}
    case _: T.MouseLeft{}
def kindName(value: T.TuiMouseEventType) -> String:
  match value:
    case T.MousePress{}: "press"
    case T.MouseRelease{}: "release"
    case T.MouseMove{}: "move"
    case T.MouseDrag{}: "drag"
    case T.MouseClick{}: "click"
    case T.MouseWheel{}: "wheel"
def buttonName(value: T.TuiMouseButton) -> String:
  match value:
    case T.MouseLeft{}: "left"
    case T.MouseMiddle{}: "middle"
    case T.MouseRight{}: "right"
    case T.NoButton{}: "none"
def wheelValue(value: Maybe<&2,T.Offset>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{value}: signed(value)
def clicksValue(value: Maybe<&2,Nat>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{value}: n(value)
def mouse(+value: V.Value) -> T.TuiMouseEvent:
  T.TuiMouseEvent{mouseKind(get(value,"type")),mouseButton(get(value,"button")),offset(get(value,"x")),offset(get(value,"y")),offset(get(value,"screenX")),offset(get(value,"screenY")),number(get(value,"width")),number(get(value,"height")),boolean(get(value,"shift")),boolean(get(value,"alt")),boolean(get(value,"ctrl")),optionalOffset(get(value,"wheelDelta")),optionalNatural(get(value,"clickCount"))}
def event(value: T.TuiMouseEvent) -> V.Value:
  match value:
    case T.TuiMouseEvent{kind,button,x,y,sx,sy,width,height,shift,alt,ctrl,wheel,clicks}: object(field("type",V.Text{kindName(kind)}) <> field("button",V.Text{buttonName(button)}) <> field("wheelDelta",wheelValue(wheel)) <> field("clickCount",clicksValue(clicks)) <> field("x",signed(x)) <> field("y",signed(y)) <> field("screenX",signed(sx)) <> field("screenY",signed(sy)) <> field("width",n(width)) <> field("height",n(height)) <> field("shift",V.Boolean{shift}) <> field("alt",V.Boolean{alt}) <> field("ctrl",V.Boolean{ctrl}) <> Nil{})
def id(value: C.ComponentId) -> V.Value:
  match value:
    case C.ComponentId{value}: n(value)
def optionalId(value: Maybe<&2,C.ComponentId>) -> V.Value:
  match value:
    case Some{value}: id(value)
    case None{}: V.Null{}
def target(value: C.TuiMouseDispatchTarget) -> V.Value:
  match value:
    case C.TuiMouseDispatchTarget{component,x,y,width,height}: object(field("component",id(component)) <> field("originX",signed(x)) <> field("originY",signed(y)) <> field("width",n(width)) <> field("height",n(height)) <> Nil{})
def result(value: Maybe<&2,C.TuiMouseDispatchResult>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{C.TuiMouseDispatchResult{value,focusTarget,capture,focus,wantsRender}}: object(field("target",target(value)) <> field("focusTarget",optionalId(focusTarget)) <> field("capture",V.Boolean{capture}) <> field("focus",V.Boolean{focus}) <> field("render",boolValue(wantsRender)) <> Nil{})
def parsedTarget(+value: V.Value) -> C.TuiMouseDispatchTarget:
  C.TuiMouseDispatchTarget{C.ComponentId{number(get(value,"component"))},offset(get(value,"originX")),offset(get(value,"originY")),number(get(value,"width")),number(get(value,"height"))}
def response(+value: V.Value) -> Maybe<&2,C.MouseResponse>:
  match value:
    case V.Null{}: None{}
    case _:
      Bool.pick(Maybe<&2,C.MouseResponse>,boolean(get(value,"forward")),
        Some{C.DispatchedResult{C.TuiMouseDispatchResult{parsedTarget(get(value,"target")),Some{C.ComponentId{number(get(value,"focusTarget"))}},boolean(get(value,"capture")),boolean(get(value,"focus")),optionalBool(get(value,"render"))}}},
        Some{C.LocalResult{T.TuiMouseEventResult{boolean(get(value,"handled")),boolean(get(value,"capture")),boolean(get(value,"focus")),optionalBool(get(value,"render"))}}})
type Fixture is Data:
  Fixture{spec: V.Value,calls: Ref.Ref<List<&2,V.Value>>}
def record(calls: Ref.Ref<List<&2,V.Value>>,value: V.Value) -> IO(Unit):
  Ref.modify(List<&2,V.Value>,Unit,calls,previous => (value <> previous,Unit{}))
def logCall(fixture: Fixture,kind: String,value: V.Value) -> IO(Unit):
  match fixture:
    case Fixture{spec,calls}: record(calls,V.ArrayValue{V.Text{kind} <> get(spec,"id") <> value <> Nil{}})
def lines(+ident: Nat,count: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match count:
    case Zero{}: reversed
    case Succ{+count}: lines(ident,count,(Nat.show(ident) ++ ":" ++ Nat.show(count)) <> reversed)
def draw(fixture: Fixture,width: Nat) -> IO(List<&2,String>):
  match fixture:
    case Fixture{+spec,calls}:
      +width = {width: Nat}
      do IO<List<&2,String>>:
        logCall(Fixture{spec,calls},"render",n(width))
        return lines(number(get(spec,"id")),number(get(spec,"height")) + Bool.pick(Nat,boolean(get(spec,"variable")),width % 3n,0n),Nil{})
def invalidate(fixture: Fixture,unused: Unit) -> IO(Unit): logCall(fixture,"invalidate",V.Null{})
def input(fixture: Fixture,value: String) -> IO(Unit): logCall(fixture,"input",V.Text{value})
def focused(fixture: Fixture,value: Bool) -> IO(Unit): logCall(fixture,"focus",V.Boolean{value})
def handleMouse(fixture: Fixture,value: T.TuiMouseEvent) -> IO(Maybe<&2,C.MouseResponse>):
  match fixture:
    case Fixture{+spec,calls}:
      do IO<Maybe<&2,C.MouseResponse>>:
        logCall(Fixture{spec,calls},"mouse",event(value))
        return response(get(spec,"response"))
def create(+spec: V.Value,calls: Ref.Ref<List<&2,V.Value>>) -> IO(C.Component):
  +fixture = {Fixture{spec,calls}: Fixture}
  do IO<C.Component>:
    renderCallback : Call.Callback<Nat,List<&2,String>> <- Call.create(~Fixture,~Nat,~List<&2,String>,~draw,fixture)
    invalidate : Call.Callback<Unit,Unit> <- Call.create(~Fixture,~Unit,~Unit,~invalidate,fixture)
    input : Call.Callback<String,Unit> <- Call.create(~Fixture,~String,~Unit,~input,fixture)
    mouse : Call.Callback<T.TuiMouseEvent,Maybe<&2,C.MouseResponse>> <- Call.create(~Fixture,~T.TuiMouseEvent,~Maybe<&2,C.MouseResponse>,~handleMouse,fixture)
    focus : Call.Callback<Bool,Unit> <- Call.create(~Fixture,~Bool,~Unit,~focused,fixture)
    return C.Component{C.ComponentId{number(get(spec,"id"))},renderCallback,Some{input},Some{mouse},invalidate,Some{focus},False{}}
def createAll(specs: List<&2,V.Value>,+calls: Ref.Ref<List<&2,V.Value>>,reversed: List<&2,C.Component>) -> IO(List<&2,C.Component>):
  match specs:
    case Nil{}: IO.pure(List<&2,C.Component>,List.reverse(&2,C.Component,reversed))
    case spec <> rest:
      do IO<List<&2,C.Component>>:
        child : C.Component <- create(spec,calls)
        createAll(rest,calls,child <> reversed)
def dispose(components: List<&2,C.Component>) -> IO(Unit):
  match components:
    case Nil{}: IO.pure(Unit,Unit{})
    case C.Component{_,renderCallback,Some{input},Some{mouse},invalidate,Some{focus},_} <> rest:
      do IO<Unit>:
        Call.dispose(Nat,List<&2,String>,renderCallback)
        Call.dispose(String,Unit,input)
        Call.dispose(T.TuiMouseEvent,Maybe<&2,C.MouseResponse>,mouse)
        Call.dispose(Unit,Unit,invalidate)
        Call.dispose(Bool,Unit,focus)
        dispose(rest)
    case _: IO.die(Unit,1,"Fixture callback ownership mismatch")
def find(components: List<&2,C.Component>,+ident: Nat) -> Maybe<&2,C.Component>:
  match components:
    case Nil{}: None{}
    case +component <> rest: Bool.pick(Unit -> Maybe<&2,C.Component>,C.same(C.id(component),C.ComponentId{ident}),_ => Some{component},_ => find(rest,ident))(Unit{})
def add(container: C.Container,component: Maybe<&2,C.Component>) -> C.Container:
  match component:
    case Some{component}: C.addChild(container,component)
    case None{}: container
def stringValues(values: List<&2,String>,reversed: List<&2,V.Value>) -> V.Value:
  match values:
    case Nil{}: V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case value <> rest: stringValues(rest,V.Text{value} <> reversed)
def rendered(pair: C.Container & List<&2,String>) -> C.Container & V.Value:
  match pair:
    case Tuple{state,lines}: (state,stringValues(lines,Nil{}))
def step(+command: V.Value,operation: String,+components: List<&2,C.Component>,+state: C.Container) -> IO(C.Container & V.Value):
  match operation:
    case "render":
      do IO<C.Container & V.Value>:
        pair : C.Container & List<&2,String> <- C.renderContainer(state,number(get(command,"width")))
        return rendered(pair)
    case "add": IO.pure(C.Container & V.Value,(add(state,find(components,number(get(command,"id")))),V.Null{}))
    case "remove": IO.pure(C.Container & V.Value,(C.removeChild(state,C.ComponentId{number(get(command,"id"))}),V.Null{}))
    case "clear": IO.pure(C.Container & V.Value,(C.clear(state),V.Null{}))
    case "invalidate":
      do IO<C.Container & V.Value>:
        C.invalidateContainer(state)
        return (state,V.Null{})
    case "retarget": IO.pure(C.Container & V.Value,(state,event(C.retargetMouseEvent(mouse(get(command,"event")),parsedTarget(get(command,"target"))))))
    case _:
      do IO<C.Container & V.Value>:
        dispatched : Maybe<&2,C.TuiMouseDispatchResult> <- C.handleMouse(state,C.ComponentId{999n},boolean(get(command,"delegates")),mouse(get(command,"event")))
        return (state,result(dispatched))
def steps(commands: List<&2,V.Value>,+components: List<&2,C.Component>,pair: C.Container & V.Value,reversed: List<&2,V.Value>) -> IO(List<&2,V.Value>):
  match commands pair:
    case Nil{} Tuple{_,last}: IO.pure(List<&2,V.Value>,List.reverse(&2,V.Value,last <> reversed))
    case (command <> rest) Tuple{state,last}:
      +command = {command: V.Value}
      do IO<List<&2,V.Value>>:
        next : C.Container & V.Value <- step(command,text(get(command,"op")),components,state)
        steps(rest,components,next,last <> reversed)
def query(+value: V.Value) -> IO(V.Value):
  do IO<V.Value>:
    +calls : Ref.Ref<List<&2,V.Value>> <- Ref.new(List<&2,V.Value>,Nil{})
    +components : List<&2,C.Component> <- createAll(array(get(value,"children")),calls,Nil{})
    results : List<&2,V.Value> <- steps(array(get(value,"steps")),components,(C.new(),V.Null{}),Nil{})
    dispose(components)
    recorded : List<&2,V.Value> <- Ref.dispose(List<&2,V.Value>,calls)
    return object(field("results",V.ArrayValue{results}) <> field("calls",V.ArrayValue{List.reverse(&2,V.Value,recorded)}) <> Nil{})
def queries(values: List<&2,V.Value>,reversed: List<&2,V.Value>) -> IO(V.Value):
  match values:
    case Nil{}: IO.pure(V.Value,V.ArrayValue{List.reverse(&2,V.Value,reversed)})
    case value <> rest:
      do IO<V.Value>:
        result : V.Value <- query(value)
        queries(rest,result <> reversed)
def program(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{values}}:
      do IO<Unit>:
        result : V.Value <- queries(values,Nil{})
        IO.print(Maybe.default(&2,String,Json.stringify(S.toJson(result)),"null"))
    case _: IO.die(Unit,1,"Expected component fixtures")
def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case arg <> rest:
      do IO<Unit>:
        program(J.parse(arg))
        run(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
