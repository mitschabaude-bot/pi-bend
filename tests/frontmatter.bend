import Base
import ../packages/runtime/src/yaml.bend as Y
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/record.bend as R
import ../packages/coding-agent/src/utils/frontmatter.bend as FM
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/json.bend as Encode

type Work is Data:
  Value{value: Y.Value}
  Array{values: List<&2,Y.Value>,first: Bool}
  Object{fields: List<&2,R.Property<Y.Value>>,first: Bool}
  Fragment{value: String}
@unsafe def render(work: List<&2,Work>,reversed: List<&2,String>) -> String:
  match work:
    case Nil{}: String.join(List.reverse(&2,String,reversed),"")
    case Fragment{value} <> rest: render(rest,value <> reversed)
    case Value{Y.Null{}} <> rest: render(rest,"null" <> reversed)
    case Value{Y.Boolean{value}} <> rest: render(rest,Bool.pick(String,value,"true","false") <> reversed)
    case Value{Y.Number{value}} <> rest: render(rest,Maybe.default(&2,String,Encode.stringify(Ai.JsonNumber{value}),"null") <> reversed)
    case Value{Y.Text{value}} <> rest: render(rest,Json.quote(value) <> reversed)
    case Value{Y.Sequence{values}} <> rest: render(Array{values,True{}} <> Fragment{"]"} <> rest,"[" <> reversed)
    case Value{Y.Mapping{fields}} <> rest: render(Object{R.entries(Y.Value,fields),True{}} <> Fragment{"}"} <> rest,"{" <> reversed)
    case Array{Nil{},_} <> rest: render(rest,reversed)
    case Array{head <> tail,first} <> rest: render(Value{head} <> Array{tail,False{}} <> rest,Bool.pick(String,first,"",",") <> reversed)
    case Object{Nil{},_} <> rest: render(rest,reversed)
    case Object{R.Property{key,value} <> tail,first} <> rest: render(Value{value} <> Object{tail,False{}} <> rest,(Bool.pick(String,first,"",",") ++ Json.quote(key) ++ ":") <> reversed)
def error(cause: Y.Error) -> String:
  "{\"ok\":false,\"error\":" ++ Json.quote(Y.errorMessage(cause)) ++ "}"
def frontmatter(result: Y.ResultOf(FM.Frontmatter)) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{FM.Frontmatter{fields,body}}: "{\"ok\":true,\"frontmatter\":" ++ render(Value{Y.Mapping{fields}} <> Nil{},Nil{}) ++ ",\"body\":" ++ Json.quote(body) ++ "}"
def yaml(result: Y.ResultOf(Y.Value)) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{value}: "{\"ok\":true,\"value\":" ++ render(Value{value} <> Nil{},Nil{}) ++ "}"
def run(values: List<String>,+raw: Bool) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case +value <> rest:
      do IO<Unit>:
        IO.print(Bool.pick(Unit -> String,raw,_ => yaml(Y.parse(value)),_ => frontmatter(FM.parseFrontmatter(value)))(Unit{}))
        run(rest,raw)
def args(values: List<String>) -> IO(Unit):
  match values:
    case "--yaml" <> rest: run(rest,True{})
    case other: run(other,False{})
def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
