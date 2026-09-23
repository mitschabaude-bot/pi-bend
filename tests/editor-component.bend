import Base
import ../packages/tui/src/components/editor.bend as E
import ../packages/tui/src/components/select-list.bend as Select
import ../packages/runtime/src/callback.bend as C
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
def color(unused: Unit,value: String) -> IO(String): IO.pure(String,"<" ++ value ++ ">")
def positioned(value: E.Editor,line: Nat,col: Nat) -> E.Editor:
  match value:
    case E.Editor{editing,history,geometry,settings,autocomplete,paste,jump}: E.Editor{E.moveTo(editing,line,col),history,geometry,settings,autocomplete,paste,jump}
def lineList(items: List<&2,String>) -> List<&2,V.Value>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: V.Text{item} <> lineList(rest)
def linesValue(items: List<&2,String>) -> V.Value:
  match items:
    case Nil{}: V.ArrayValue{Nil{}}
    case items: V.ArrayValue{lineList(items)}
def rendered(result: E.Editor & List<&2,String>) -> IO(V.Value):
  match result:
    case Tuple{editor,lines}:
      do IO<V.Value>:
        E.dispose(editor)
        return linesValue(lines)
def query(+value: V.Value) -> IO(V.Value):
  do IO<V.Value>:
    +paint : C.Callback<String,String> <- C.create(~Unit,~String,~String,~color,Unit{})
    editor : E.Editor <- E.new(E.EditorTheme{paint,Select.SelectListTheme{paint,paint,paint,paint,paint}},Some{E.EditorOptions{n(get(value,"padding")),5n}})
    editor : E.Editor <- E.setText(editor,text(get(value,"text")))
    result : E.Editor & List<&2,String> <- E.render(E.setFocused(positioned(editor,n(get(value,"line")),n(get(value,"col"))),boolean(get(value,"focused"))),n(get(value,"width")),n(get(value,"rows")))
    output : V.Value <- rendered(result)
    C.dispose(String,String,paint)
    return output
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
