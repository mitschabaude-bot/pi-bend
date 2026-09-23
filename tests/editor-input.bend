import Base
import ../packages/tui/src/components/editor.bend as E
import ../packages/tui/src/components/select-list.bend as Select
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref
import ../packages/tui/src/word-navigation.bend as Word
import ../packages/tui/src/keybindings.bend as KB
import ../packages/tui/src/keys.bend as Keys
import ../packages/tui/src/tui.bend as Tui
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/json.bend as J
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson

def get(value: V.Value,key: String) -> V.Value:
  match value:
    case V.ObjectValue{fields}: Maybe.default(&2,V.Value,R.get(V.Value,fields,key),V.Null{})
    case _: V.Null{}
def text(value: V.Value) -> String:
  match value:
    case V.Text{value}: value
    case _: ""
def n(value: V.Value) -> Nat:
  match value:
    case V.Number{value}: U32.to_nat(F64.to_u32(value))
    case _: 0n
def obj(fields: List<&2,R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def c(n: Nat) -> V.Value: V.Number{U32.to_f64(U32.from_nat(n))}
def boolean(v: V.Value) -> Bool:
  match v:
    case V.Boolean{value}: value
    case _: False{}
def identity(unused: Unit,value: String) -> IO(String): IO.pure(String,value)
type Sink is Data: Sink{events: Ref.Ref<List<&2,String>>,prefix: String}
def record(sink: Sink,value: String) -> IO(Unit):
  match sink:
    case Sink{events,prefix}: Ref.modify(List<&2,String>,Unit,events,old => ((prefix ++ value) <> old,Unit{}))
def redraw(events: Ref.Ref<List<&2,String>>,unused: Unit) -> IO(Unit): Ref.modify(List<&2,String>,Unit,events,old => ("R" <> old,Unit{}))
def part(+v: V.Value) -> Word.Segment: Word.Segment{text(get(v,"text")),boolean(get(v,"word"))}
def parts(items: List<&2,V.Value>) -> List<&2,Word.Segment>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: part(item) <> parts(rest)
def array(v: V.Value) -> List<&2,V.Value>:
  match v:
    case V.ArrayValue{items}: items
    case _: Nil{}
def dictionary(fields: List<&2,R.Property<V.Value>>,result: R.Record<List<&2,Word.Segment>>) -> R.Record<List<&2,Word.Segment>>:
  match fields:
    case Nil{}: result
    case R.Property{key,value} <> rest: dictionary(rest,R.set(List<&2,Word.Segment>,result,key,parts(array(value))))
def context(v: V.Value) -> R.Record<List<&2,Word.Segment>>:
  match v:
    case V.ObjectValue{R.Record{fields}}: dictionary(fields,R.new(List<&2,Word.Segment>))
    case _: R.new(List<&2,Word.Segment>)
def segment(context: R.Record<List<&2,Word.Segment>>,text: String) -> Word.ResultOf(List<&2,Word.Segment>):
  Maybe.default(&2,Word.ResultOf(List<&2,Word.Segment>),Maybe.map(&2,List<&2,Word.Segment>,Word.ResultOf(List<&2,Word.Segment>),parts => Done{parts},R.get(List<&2,Word.Segment>,context,text)),Fail{Word.MissingWordEngine{"oracle fixture omitted segmentation input"}})
def unwrap(result: E.ResultOf(E.Editor)) -> IO(E.Editor):
  match result:
    case Done{value}: IO.pure(E.Editor,value)
    case Fail{_}: IO.die(E.Editor,1,"editor operation failed")
def unwrapMouse(result: E.ResultOf(E.MouseResult)) -> IO(E.Editor):
  match result:
    case Done{E.MouseResult{value,_}}: IO.pure(E.Editor,value)
    case Fail{_}: IO.die(E.Editor,1,"editor mouse operation failed")
def mouseEvent(+v: V.Value) -> Tui.TuiMouseEvent:
  Tui.TuiMouseEvent{Tui.MouseClick{},Tui.MouseLeft{},Tui.Forward{n(get(v,"x"))},Tui.Forward{n(get(v,"y"))},Tui.Forward{0n},Tui.Forward{0n},n(get(v,"width")),24n,False{},False{},False{},None{},Some{1n}}
def renderResult(result: E.Editor & List<&2,String>) -> IO(E.Editor & Maybe<&2,List<&2,String>>):
  match result:
    case Tuple{value,lines}: IO.pure(E.Editor & Maybe<&2,List<&2,String>>,(value,Some{lines}))
def dispatch(value: E.Editor,op: String,+v: V.Value,words: R.Record<List<&2,Word.Segment>>,manager: KB.KeybindingsManager) -> IO(E.Editor & Maybe<&2,List<&2,String>>):
  match op:
    case "render":
      do IO<E.Editor & Maybe<&2,List<&2,String>>>:
        result : E.Editor & List<&2,String> <- E.render(value,n(get(v,"width")),24n)
        renderResult(result)
    case "set":
      do IO<E.Editor & Maybe<&2,List<&2,String>>>:
        value : E.Editor <- E.setText(value,text(get(v,"text")))
        return (value,None{})
    case "insert":
      do IO<E.Editor & Maybe<&2,List<&2,String>>>:
        value : E.Editor <- E.insertTextAtCursor(value,text(get(v,"text")))
        return (value,None{})
    case "add": IO.pure(E.Editor & Maybe<&2,List<&2,String>>,(E.addToHistory(value,text(get(v,"text"))),None{}))
    case "disable": IO.pure(E.Editor & Maybe<&2,List<&2,String>>,(E.setDisableSubmit(value,boolean(get(v,"value"))),None{}))
    case "focus": IO.pure(E.Editor & Maybe<&2,List<&2,String>>,(E.setFocused(value,boolean(get(v,"value"))),None{}))
    case "input":
      do IO<E.Editor & Maybe<&2,List<&2,String>>>:
        result : E.ResultOf(E.Editor) <- E.handleInput(~R.Record<List<&2,Word.Segment>>,~segment,words,value,manager,Keys.Context{False{},False{}},text(get(v,"text")),24n)
        value : E.Editor <- unwrap(result)
        return (value,None{})
    case "mouse":
      do IO<E.Editor & Maybe<&2,List<&2,String>>>:
        result : E.ResultOf(E.MouseResult) <- E.handleMouse(value,mouseEvent(v))
        value : E.Editor <- unwrapMouse(result)
        return (value,None{})
    case _: IO.pure(E.Editor & Maybe<&2,List<&2,String>>,(value,None{}))
def lineList(items: List<&2,String>) -> List<&2,V.Value>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: V.Text{item} <> lineList(rest)
def maybeLines(lines: Maybe<&2,List<&2,String>>) -> V.Value:
  match lines:
    case None{}: V.Null{}
    case Some{lines}: V.ArrayValue{lineList(lines)}
def output(+value: E.Editor,events: List<&2,String>,lines: Maybe<&2,List<&2,String>>) -> V.Value:
  match value:
    case E.Editor{E.Editing{E.EditorSnapshot{E.EditorState{_,line,column},_,count},_,_,_,_,_},_,_,_,_,_,_}:
      obj([R.Property{"text",V.Text{E.getText(value)}},R.Property{"expanded",V.Text{E.getExpandedText(value)}},R.Property{"line",c(line)},R.Property{"col",c(column)},R.Property{"pasteCounter",c(count)},R.Property{"events",V.ArrayValue{lineList(events)}},R.Property{"rendered",maybeLines(lines)}])
type Step is Data: Step{editor: E.Editor,output: V.Value}
def captured(result: E.Editor & Maybe<&2,List<&2,String>>,events: List<&2,String>) -> Step:
  match result:
    case Tuple{+value,lines}: Step{value,output(value,events,lines)}
def step(value: E.Editor,+v: V.Value,words: R.Record<List<&2,Word.Segment>>,manager: KB.KeybindingsManager,events: Ref.Ref<List<&2,String>>) -> IO(Step):
  do IO<Step>:
    result : E.Editor & Maybe<&2,List<&2,String>> <- dispatch(value,text(get(v,"op")),v,words,manager)
    emitted : List<&2,String> <- Ref.modify(List<&2,String>,List<&2,String>,events,old => (Nil{},List.reverse(&2,String,old)))
    return captured(result,emitted)
def stepOutput(value: Step) -> V.Value:
  match value:
    case Step{_,output}: output
@unsafe
def trace(ops: List<&2,V.Value>,current: Step,+words: R.Record<List<&2,Word.Segment>>,+manager: KB.KeybindingsManager,+events: Ref.Ref<List<&2,String>>,reversed: List<&2,V.Value>) -> IO(V.Value):
  match ops current:
    case Nil{} Step{value,_}:
      do IO<V.Value>:
        E.dispose(value)
        return V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case op <> rest Step{value,_}:
      do IO<V.Value>:
        +next : Step <- step(value,op,words,manager,events)
        trace(rest,next,words,manager,events,stepOutput(next) <> reversed)
def query(+v: V.Value) -> IO(V.Value):
  do IO<V.Value>:
    +events : Ref.Ref<List<&2,String>> <- Ref.new(List<&2,String>,Nil{})
    +paint : C.Callback<String,String> <- C.create(~Unit,~String,~String,~identity,Unit{})
    +change : C.Callback<String,Unit> <- C.create(~Sink,~String,~Unit,~record,Sink{events,"C"})
    +submit : C.Callback<String,Unit> <- C.create(~Sink,~String,~Unit,~record,Sink{events,"S"})
    +render : C.Callback<Unit,Unit> <- C.create(~Ref.Ref<List<&2,String>>,~Unit,~Unit,~redraw,events)
    value : E.Editor <- E.new(E.EditorTheme{paint,Select.SelectListTheme{paint,paint,paint,paint,paint}},None{})
    result : V.Value <- trace(array(get(v,"ops")),Step{E.setCallbacks(value,E.EditorCallbacks{Some{change},Some{submit},Some{render},None{}}),V.Null{}},context(get(v,"words")),KB.create(KB.TUI_KEYBINDINGS(),R.new(List<&2,Keys.KeyId>)),events,Nil{})
    C.dispose(String,String,paint)
    C.dispose(String,Unit,change)
    C.dispose(String,Unit,submit)
    C.dispose(Unit,Unit,render)
    unused : List<&2,String> <- Ref.dispose(List<&2,String>,events)
    return result
def queryList(items: List<&2,V.Value>,reversed: List<&2,V.Value>) -> IO(V.Value):
  match items:
    case Nil{}: IO.pure(V.Value,V.ArrayValue{List.reverse(&2,V.Value,reversed)})
    case item <> rest:
      do IO<V.Value>:
        value : V.Value <- query(item)
        queryList(rest,value <> reversed)
def program(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{items}}:
      do IO<Unit>:
        result : V.Value <- queryList(items,Nil{})
        IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(result)),"null"))
    case _: IO.die(Unit,1,"invalid input")
def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case input <> rest:
      do IO<Unit>:
        program(J.parse(input))
        run(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
