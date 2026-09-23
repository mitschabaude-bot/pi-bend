import Base
import ../packages/tui/src/components/editor.bend as E
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
def dispatch(value: E.Editing,op: String,text: String) -> E.Editing:
  match op:
    case "set": E.setTextEdit(value,text)
    case "insert": E.insertTextEdit(value,text)
    case "type": E.insertCharacter(value,text)
    case "paste": E.handlePasteEdit(value,text)
    case "left": E.moveHorizontal(value,True{})
    case "right": E.moveHorizontal(value,False{})
    case "home": E.lineBoundary(value,True{})
    case "end": E.lineBoundary(value,False{})
    case "backspace": E.handleBackspaceEdit(value)
    case "delete": E.deleteHorizontal(value,False{})
    case "killStart": E.killLine(value,True{})
    case "killEnd": E.killLine(value,False{})
    case "yank": E.yankEdit(value)
    case "yankPop": E.yankPopEdit(value)
    case "undo": E.undoEdit(value)
    case _: value
def edit(value: E.Editing,+operation: V.Value) -> E.Editing: dispatch(value,text(get(operation,"op")),text(get(operation,"text")))
def output(+value: E.Editing) -> V.Value:
  match value:
    case E.Editing{E.EditorSnapshot{E.EditorState{_,line,column},_,count},_,_,_,_,_}:
      obj([R.Property{"text",V.Text{E.editingText(value)}},R.Property{"expanded",V.Text{E.expandedEditingText(value)}},R.Property{"line",c(line)},R.Property{"col",c(column)},R.Property{"pasteCounter",c(count)}])
def trace(ops: List<&2,V.Value>,value: E.Editing,reversed: List<&2,V.Value>) -> V.Value:
  match ops:
    case Nil{}: V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case op <> rest:
      +next = edit(value,op)
      trace(rest,next,output(next) <> reversed)
def query(value: V.Value) -> V.Value:
  match value:
    case V.ArrayValue{ops}: trace(ops,E.createEditing(),Nil{})
    case _: V.Null{}
def queryList(items: List<&2,V.Value>) -> List<&2,V.Value>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: query(item) <> queryList(rest)
def program(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{items}}:
      do IO<Unit>:
        result : V.Value <- IO.pure(V.Value,V.ArrayValue{queryList(items)})
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
