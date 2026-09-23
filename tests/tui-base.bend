import Base
import ../packages/tui/src/tui-base.bend as B
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/overlays.bend as O
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref
import ../packages/tui/src/tui.bend as T
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson

def get(value: V.Value,key: String) -> V.Value:
  match value:
    case V.ObjectValue{fields}: Maybe.default(&2,V.Value,R.get(V.Value,fields,key),V.Null{})
    case _: V.Null{}
def natural(value: V.Value) -> Nat:
  match value:
    case V.Number{value}: U32.to_nat(F64.to_u32(F.maximum(F.fromU32(0),value)))
    case _: 0n
def percent(value: Result<&2,&2,J.ParseError,V.Value>) -> Maybe<&2,T.SizeValue>:
  match value:
    case Done{V.Number{value}}: Some{T.Percent{value}}
    case _: Some{T.Percent{F.nan()}}
def size(value: V.Value) -> Maybe<&2,T.SizeValue>:
  match value:
    case V.Null{}: None{}
    case V.Number{value}: Some{T.Cells{natural(V.Number{value})}}
    case V.Text{+value}: percent(J.parse(String.take(value,String.length(value) - 1n)))
    case _: Some{T.Percent{F.nan()}}
def offset(value: V.Value) -> T.Offset:
  match value:
    case V.Number{+value}: Bool.pick(Unit -> T.Offset,F.isGreater(F.compare(F.fromU32(0),value)),_ => T.Backward{U32.to_nat(F64.to_u32(F.negate(value)))},_ => T.Forward{U32.to_nat(F64.to_u32(value))})(Unit{})
    case _: T.Forward{0n}
def anchor(value: V.Value) -> T.OverlayAnchor:
  match value:
    case V.Text{"top-left"}: T.TopLeft{}
    case V.Text{"top-right"}: T.TopRight{}
    case V.Text{"bottom-left"}: T.BottomLeft{}
    case V.Text{"bottom-right"}: T.BottomRight{}
    case V.Text{"top-center"}: T.TopCenter{}
    case V.Text{"bottom-center"}: T.BottomCenter{}
    case V.Text{"left-center"}: T.LeftCenter{}
    case V.Text{"right-center"}: T.RightCenter{}
    case _: T.Center{}
def margin(+value: V.Value) -> T.OverlayMargin:
  match value:
    case V.Number{_}: T.OverlayMargin{natural(value),natural(value),natural(value),natural(value)}
    case _: T.OverlayMargin{natural(get(value,"top")),natural(get(value,"right")),natural(get(value,"bottom")),natural(get(value,"left"))}
def options(+value: V.Value) -> T.OverlayGeometry:
  T.OverlayGeometry{size(get(value,"width")),natural(get(value,"minWidth")),size(get(value,"maxHeight")),anchor(get(value,"anchor")),offset(get(value,"offsetX")),offset(get(value,"offsetY")),size(get(value,"row")),size(get(value,"col")),margin(get(value,"margin"))}
def count(value: Nat) -> V.Value: V.Number{T.dimension(value)}

def text(value: V.Value) -> String:
  match value:
    case V.Text{value}: value
    case _: ""
def boolean(value: V.Value) -> Bool:
  match value:
    case V.Boolean{value}: value
    case _: False{}
def array(value: V.Value) -> List<&2,V.Value>:
  match value:
    case V.ArrayValue{values}: values
    case _: Nil{}
def strings(values: List<&2,V.Value>,reversed: List<&2,String>) -> List<&2,String>:
  match values:
    case Nil{}: List.reverse(&2,String,reversed)
    case V.Text{value} <> rest: strings(rest,value <> reversed)
    case _: Nil{}
def shown(lines: List<&2,String>,reversed: List<&2,V.Value>) -> V.Value:
  match lines:
    case Nil{}: V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case line <> rest: shown(rest,V.Text{line} <> reversed)
def field(name: String,value: V.Value) -> R.Property<V.Value>: R.Property{name,value}
def object(fields: List<&2,R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def signed(value: T.Offset) -> V.Value:
  match value:
    case T.Forward{value}: count(value)
    case T.Backward{value}: V.Number{F.negate(T.dimension(value))}
def id(value: C.ComponentId) -> V.Value:
  match value:
    case C.ComponentId{value}: count(value)
def target(value: C.TuiMouseDispatchTarget) -> V.Value:
  match value:
    case C.TuiMouseDispatchTarget{component,x,y,width,height}: object(field("id",id(component)) <> field("originX",signed(x)) <> field("originY",signed(y)) <> field("width",count(width)) <> field("height",count(height)) <> Nil{})
def response(value: Maybe<&2,C.TuiMouseDispatchResult>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{C.TuiMouseDispatchResult{mouseTarget,focusTarget,capture,focus,render}}: object(field("target",target(mouseTarget)) <> field("focusTarget",Maybe.default(&2,V.Value,Maybe.map(&2,C.ComponentId,V.Value,id,focusTarget),V.Null{})) <> field("capture",V.Boolean{capture}) <> field("focus",V.Boolean{focus}) <> field("render",Maybe.default(&2,V.Value,Maybe.map(&2,Bool,V.Value,value => V.Boolean{value},render),V.Null{})) <> Nil{})
def hit(value: B.MouseHit) -> V.Value:
  match value:
    case B.MouseHit{found,result}: object(field("hit",V.Boolean{found}) <> field("result",response(result)) <> Nil{})
def bounds(values: List<&2,B.OverlayBounds>,reversed: List<&2,V.Value>) -> V.Value:
  match values:
    case Nil{}: V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case B.OverlayBounds{_,_,C.TuiMouseDispatchTarget{component,x,y,width,height}} <> rest: bounds(rest,object(field("id",id(component)) <> field("col",signed(x)) <> field("row",signed(y)) <> field("width",count(width)) <> field("height",count(height)) <> Nil{}) <> reversed)
type Child is Data: Child{spec: V.Value,renders: Ref.Ref<List<&2,V.Value>>,calls: Ref.Ref<List<&2,V.Value>>}
def log(values: Ref.Ref<List<&2,V.Value>>,value: V.Value) -> IO(Unit):
  Ref.modify(List<&2,V.Value>,Unit,values,previous => (value <> previous,Unit{}))
def render(child: Child,width: Nat) -> IO(List<&2,String>):
  match child:
    case Child{+spec,renders,_}:
      do IO<List<&2,String>>:
        log(renders,object(field("id",get(spec,"id")) <> field("width",count(width)) <> Nil{}))
        return strings(array(get(spec,"lines")),Nil{})
def invalidate(unused: Unit,value: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def mouseResult(mode: String,event: T.TuiMouseEvent,+spec: V.Value) -> Maybe<&2,C.MouseResponse>:
  match mode event:
    case "none" _: None{}
    case "unhandled" _: Some{C.LocalResult{T.TuiMouseEventResult{False{},False{},False{},None{}}}}
    case "nested" T.TuiMouseEvent{_,_,x,y,screenX,screenY,_,_,_,_,_,_,_}: Some{C.DispatchedResult{C.TuiMouseDispatchResult{C.TuiMouseDispatchTarget{C.ComponentId{natural(get(spec,"id")) + 1000n},C.subtract(C.subtract(screenX,x),T.Backward{1n}),C.subtract(C.subtract(screenY,y),T.Backward{1n}),2n,1n},Some{C.ComponentId{natural(get(spec,"id")) + 1000n}},True{},True{},Some{False{}}}}}
    case "nested-no-focus" T.TuiMouseEvent{_,_,x,y,screenX,screenY,_,_,_,_,_,_,_}: Some{C.DispatchedResult{C.TuiMouseDispatchResult{C.TuiMouseDispatchTarget{C.ComponentId{natural(get(spec,"id")) + 1000n},C.subtract(C.subtract(screenX,x),T.Backward{1n}),C.subtract(C.subtract(screenY,y),T.Backward{1n}),2n,1n},Some{C.ComponentId{natural(get(spec,"id")) + 1000n}},True{},False{},Some{False{}}}}}
    case mode _:
      +mode = {mode: String}
      Some{C.LocalResult{T.TuiMouseEventResult{Bool.not(String.eq(mode,"focus") || String.eq(mode,"capture")),String.eq(mode,"capture"),String.eq(mode,"focus"),Some{False{}}}}}
def mouseCore(child: Child,+event: T.TuiMouseEvent) -> IO(Maybe<&2,C.MouseResponse>):
  match child event:
    case Child{+spec,_,calls} T.TuiMouseEvent{_,_,x,y,screenX,screenY,width,height,_,_,_,_,_}:
      do IO<Maybe<&2,C.MouseResponse>>:
        log(calls,object(field("id",get(spec,"id")) <> field("x",signed(x)) <> field("y",signed(y)) <> field("screenX",signed(screenX)) <> field("screenY",signed(screenY)) <> field("width",count(width)) <> field("height",count(height)) <> Nil{}))
        return mouseResult(text(get(spec,"mouse")),event,spec)
def mouse(child: Child,event: T.TuiMouseEvent) -> IO(Maybe<&2,C.MouseResponse>): mouseCore(child,event)
def child(+spec: V.Value,+renders: Ref.Ref<List<&2,V.Value>>,+calls: Ref.Ref<List<&2,V.Value>>) -> IO(C.Component):
  do IO<C.Component>:
    renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Child,~Nat,~List<&2,String>,~render,Child{spec,renders,calls})
    mouseCallback : Callback.Callback<T.TuiMouseEvent,Maybe<&2,C.MouseResponse>> <- Callback.create(~Child,~T.TuiMouseEvent,~Maybe<&2,C.MouseResponse>,~mouse,Child{spec,renders,calls})
    invalidateCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~invalidate,Unit{})
    return C.Component{C.ComponentId{natural(get(spec,"id"))},renderCallback,None{},Some{mouseCallback},invalidateCallback,None{},False{}}
def isVisible(value: V.Value) -> Bool:
  match value:
    case V.Boolean{False{}}: False{}
    case _: True{}
def entries(specs: List<&2,V.Value>,reversed: List<&2,O.Entry>) -> List<&2,O.Entry>:
  match specs:
    case Nil{}: List.reverse(&2,O.Entry,reversed)
    case +spec <> rest: entries(rest,O.Entry{O.OverlayHandle{natural(get(spec,"id"))},C.ComponentId{natural(get(spec,"id"))},None{},boolean(get(spec,"hidden")),isVisible(get(spec,"visible")),False{},natural(get(spec,"order"))} <> reversed)
def bindings(specs: List<&2,V.Value>,+renders: Ref.Ref<List<&2,V.Value>>,+calls: Ref.Ref<List<&2,V.Value>>,reversed: List<&2,B.Overlay>) -> IO(List<&2,B.Overlay>):
  match specs:
    case Nil{}: IO.pure(List<&2,B.Overlay>,List.reverse(&2,B.Overlay,reversed))
    case +spec <> rest:
      do IO<List<&2,B.Overlay>>:
        component : C.Component <- child(spec,renders,calls)
        bindings(rest,renders,calls,B.Overlay{O.OverlayHandle{natural(get(spec,"id"))},component,options(get(spec,"options"))} <> reversed)
def makeEvent(+spec: V.Value) -> T.TuiMouseEvent:
  T.TuiMouseEvent{T.MousePress{},T.MouseLeft{},T.Forward{777n},T.Forward{888n},offset(get(spec,"x")),offset(get(spec,"y")),0n,0n,False{},False{},False{},None{},None{}}
def events(values: List<&2,V.Value>,+frame: B.Frame,reversed: List<&2,V.Value>) -> IO(V.Value):
  match values:
    case Nil{}: IO.pure(V.Value,V.ArrayValue{List.reverse(&2,V.Value,reversed)})
    case value <> rest:
      do IO<V.Value>:
        result : B.MouseHit <- B.dispatchMouseToOverlay(frame,makeEvent(value))
        events(rest,frame,hit(result) <> reversed)
def observed(value: B.Frame,mouse: V.Value,renders: List<&2,V.Value>,calls: List<&2,V.Value>) -> V.Value:
  match value:
    case B.Frame{lines,layout}: object(field("lines",shown(lines,Nil{})) <> field("bounds",bounds(layout,Nil{})) <> field("renders",V.ArrayValue{List.reverse(&2,V.Value,renders)}) <> field("mouse",mouse) <> field("calls",V.ArrayValue{List.reverse(&2,V.Value,calls)}) <> Nil{})
def successful(value: B.ResultOf(B.Frame)) -> IO(B.Frame):
  match value:
    case Done{frame}: IO.pure(B.Frame,frame)
    case _: IO.die(B.Frame,1,"invalid frame fixture")
def dispose(values: List<&2,B.Overlay>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case B.Overlay{_,C.Component{_,render,_,Some{mouse},invalidate,_,_},_} <> rest:
      do IO<Unit>:
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(T.TuiMouseEvent,Maybe<&2,C.MouseResponse>,mouse)
        Callback.dispose(Unit,Unit,invalidate)
        dispose(rest)
    case _ <> rest: dispose(rest)
def query(+value: V.Value) -> IO(V.Value):
  do IO<V.Value>:
    +renders : Ref.Ref<List<&2,V.Value>> <- Ref.new(List<&2,V.Value>,Nil{})
    +calls : Ref.Ref<List<&2,V.Value>> <- Ref.new(List<&2,V.Value>,Nil{})
    +overlays : List<&2,B.Overlay> <- bindings(array(get(value,"overlays")),renders,calls,Nil{})
    result : B.ResultOf(B.Frame) <- B.compositeOverlays(O.State{entries(array(get(value,"overlays")),Nil{}),None{},O.Inactive{},0n,1n},overlays,strings(array(get(value,"base")),Nil{}),natural(get(value,"width")),natural(get(value,"height")))
    +frame : B.Frame <- successful(result)
    mouseResults : V.Value <- events(array(get(value,"events")),frame,Nil{})
    dispose(overlays)
    renderCalls : List<&2,V.Value> <- Ref.dispose(List<&2,V.Value>,renders)
    mouseCalls : List<&2,V.Value> <- Ref.dispose(List<&2,V.Value>,calls)
    return observed(frame,mouseResults,renderCalls,mouseCalls)
def queries(values: List<&2,V.Value>,reversed: List<&2,V.Value>) -> IO(V.Value):
  match values:
    case Nil{}: IO.pure(V.Value,V.ArrayValue{List.reverse(&2,V.Value,reversed)})
    case value <> rest:
      do IO<V.Value>:
        result : V.Value <- query(value)
        queries(rest,result <> reversed)
def parsed(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{values}}:
      do IO<Unit>:
        result : V.Value <- queries(values,Nil{})
        IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(result)),"null"))
    case _: IO.die(Unit,1,"expected fixture array")
def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    parsed(J.parse(Maybe.default(&1,String,List.head(&1,String,arguments),"[]")))
