import Base
import ../packages/tui/src/fuzzy.bend as Fuzzy
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R

def field(value: V.Value,key: String) -> V.Value:
  match value:
    case V.ObjectValue{fields}: Maybe.default(&2,V.Value,R.get(V.Value,fields,key),V.Null{})
    case _: V.Null{}
def string(value: V.Value) -> String:
  match value:
    case V.Text{text}: text
    case _: ""
def scoreBits(value: F64) -> String:
  match value:
    case F64{high,low}: U32.show(high) ++ "," ++ U32.show(low)
def matchResult(value: Fuzzy.FuzzyMatch) -> String:
  match value:
    case Fuzzy.FuzzyMatch{matches,score}: "[" ++ Bool.pick(String,matches,"true","false") ++ "," ++ scoreBits(score) ++ "]"
type Item is Data:
  Item{index: U32,text: String}
def itemText(value: Item) -> String:
  match value:
    case Item{_,text}: text
def items(values: List<&2,V.Value>,+index: U32,result: List<&2,Item>) -> List<&2,Item>:
  match values:
    case Nil{}: List.reverse(&2,Item,result)
    case value <> rest: items(rest,(index + 1 : U32),Item{index,string(value)} <> result)
def parsedItems(value: V.Value) -> List<&2,Item>:
  match value:
    case V.ArrayValue{values}: items(values,0,Nil{})
    case _: Nil{}
def indices(values: List<&2,Item>,result: List<&2,String>) -> String:
  match values:
    case Nil{}: "[" ++ String.join(List.reverse(&2,String,result),",") ++ "]"
    case Item{index,_} <> rest: indices(rest,U32.show(index) <> result)
def result(+value: V.Value,kind: String) -> String:
  match kind:
    case "match": matchResult(Fuzzy.fuzzyMatch(string(field(value,"query")),string(field(value,"text"))))
    case _: indices(Fuzzy.fuzzyFilter(~Item,~itemText,parsedItems(field(value,"labels")),string(field(value,"query"))),Nil{})
def parsed(value: Result<&2,&2,Json.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit,1,"invalid fixture JSON")
    case Done{+value}: IO.print(result(value,string(field(value,"kind"))))
def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case text <> rest:
      do IO<Unit>:
        parsed(Json.parse(text))
        run(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
