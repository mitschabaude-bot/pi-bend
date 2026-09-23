import Base
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/tui.bend as T
import ../packages/tui/src/overlays.bend as O
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
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
def array(value: V.Value) -> List<&2,V.Value>:
  match value:
    case V.ArrayValue{items}: items
    case _: Nil{}
def n(value: Nat) -> V.Value: V.Number{T.dimension(value)}
def field(key: String,value: V.Value) -> R.Property<V.Value>: R.Property{key,value}
def object(fields: List<&2,R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def component(value: V.Value) -> Maybe<&2,C.ComponentId>:
  match value:
    case V.Number{value}: Some{C.ComponentId{number(V.Number{value})}}
    case _: None{}
def identifier(value: C.ComponentId) -> V.Value:
  match value:
    case C.ComponentId{value}: n(value)
def focus(value: Maybe<&2,C.ComponentId>) -> V.Value:
  match value:
    case Some{value}: identifier(value)
    case None{}: V.Null{}
def handle(value: O.OverlayHandle) -> V.Value:
  match value:
    case O.OverlayHandle{value}: n(value)
def entry(value: O.Entry) -> V.Value:
  match value:
    case O.Entry{h,c,p,hidden,visible,passive,order}: object(field("handle",handle(h)) <> field("component",identifier(c)) <> field("previous",focus(p)) <> field("hidden",V.Boolean{hidden}) <> field("visible",V.Boolean{visible}) <> field("passive",V.Boolean{passive}) <> field("order",n(order)) <> Nil{})
def entriesValue(values: List<&2,O.Entry>) -> List<&2,V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: entry(value) <> entriesValue(rest)
def resumed(h: O.OverlayHandle,c: C.ComponentId,value: O.Resume) -> V.Value:
  match value:
    case O.RestoreOverlay{}: object(field("status",V.Text{"blocked"}) <> field("overlay",handle(h)) <> field("blockedBy",identifier(c)) <> field("resume",V.Text{"restore-overlay"}) <> field("target",V.Null{}) <> Nil{})
    case O.FocusTarget{value}: object(field("status",V.Text{"blocked"}) <> field("overlay",handle(h)) <> field("blockedBy",identifier(c)) <> field("resume",V.Text{"focus-target"}) <> field("target",focus(value)) <> Nil{})
def restore(value: O.Restore) -> V.Value:
  match value:
    case O.Inactive{}: object(field("status",V.Text{"inactive"}) <> Nil{})
    case O.Eligible{h}: object(field("status",V.Text{"eligible"}) <> field("overlay",handle(h)) <> Nil{})
    case O.Blocked{h,c,resume}: resumed(h,c,resume)
def focusCall(value: Maybe<&2,C.ComponentId>,flag: Bool) -> List<&2,V.Value>:
  match value:
    case None{}: Nil{}
    case Some{value}: V.ArrayValue{identifier(value) <> V.Boolean{flag} <> Nil{}} <> Nil{}
def calls(changes: List<&2,O.FocusChange>) -> List<&2,V.Value>:
  match changes:
    case Nil{}: Nil{}
    case O.FocusChange{previous,next} <> rest: List.append(&2,V.Value,focusCall(previous,False{}),List.append(&2,V.Value,focusCall(next,True{}),calls(rest)))
def observation(state: O.State,changes: List<&2,O.FocusChange>,hide: Bool,render: Bool) -> V.Value:
  match state:
    case O.State{entries,current,pending,order,_}: object(field("entries",V.ArrayValue{entriesValue(entries)}) <> field("focus",focus(current)) <> field("restore",restore(pending)) <> field("order",n(order)) <> field("calls",V.ArrayValue{calls(changes)}) <> field("hide",V.Boolean{hide}) <> field("render",V.Boolean{render}) <> Nil{})
def explicit(value: V.Value) -> Maybe<&2,Maybe<&2,C.ComponentId>>:
  match value:
    case V.ObjectValue{fields}: Maybe.map(&2,V.Value,Maybe<&2,C.ComponentId>,component,R.get(V.Value,fields,"target"))
    case _: None{}
def truth(value: V.Value) -> Bool:
  match value:
    case V.Boolean{flag}: flag
    case _: True{}
def shown(value: O.Change & O.OverlayHandle) -> O.Change:
  match value:
    case (change,_): change
def transition(operation: String,state: O.State,mounted: List<&2,C.ComponentId>,+step: V.Value) -> O.Change:
  match operation:
    case "show": shown(O.showOverlay(state,mounted,C.ComponentId{number(get(step,"component"))},boolean(get(step,"passive")),truth(get(step,"visible"))))
    case "focus": O.setFocus(state,mounted,component(get(step,"target")))
    case "hide": O.hide(state,mounted,O.OverlayHandle{number(get(step,"handle"))})
    case "pop": O.hideOverlay(state,mounted)
    case "hidden": O.setHidden(state,mounted,O.OverlayHandle{number(get(step,"handle"))},boolean(get(step,"value")))
    case "visible": O.unchanged(O.setVisibility(state,O.OverlayHandle{number(get(step,"handle"))},boolean(get(step,"value"))))
    case "focusOverlay": O.focusOverlay(state,mounted,O.OverlayHandle{number(get(step,"handle"))})
    case "unfocus": O.unfocus(state,mounted,O.OverlayHandle{number(get(step,"handle"))},explicit(step))
    case "input": O.prepareInput(state,mounted)
    case _: O.unchanged(state)
def components(values: List<&2,V.Value>) -> List<&2,C.ComponentId>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: C.ComponentId{number(value)} <> components(rest)
def mountedFrom(value: V.Value,current: List<&2,C.ComponentId>) -> List<&2,C.ComponentId>:
  match value:
    case V.ArrayValue{items}: components(items)
    case _: current
type Work is Data: Work{state: O.State,mounted: List<&2,C.ComponentId>,reversed: List<&2,V.Value>}
def accept(change: O.Change,mounted: List<&2,C.ComponentId>,reversed: List<&2,V.Value>) -> Work:
  match change:
    case O.Change{+state,changes,hide,render}: Work{state,mounted,observation(state,changes,hide,render) <> reversed}
def advance(value: Work,+step: V.Value) -> Work:
  match value:
    case Work{state,mounted,reversed}:
      +mounted = mountedFrom(get(step,"mounted"),mounted)
      accept(transition(text(get(step,"op")),state,mounted,step),mounted,reversed)
def sequence(steps: List<&2,V.Value>,work: Work) -> V.Value:
  match steps work:
    case Nil{} Work{_,_,reversed}: V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case step <> rest work: sequence(rest,advance(work,step))
def query(value: V.Value) -> V.Value: sequence(array(value),Work{O.new(),Nil{},Nil{}})
def queries(values: List<&2,V.Value>) -> List<&2,V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: query(value) <> queries(rest)
def program(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{values}}: IO.print(Maybe.default(&2,String,Json.stringify(S.toJson(V.ArrayValue{queries(values)})),"null"))
    case _: IO.die(Unit,1,"Expected overlay fixtures")
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
