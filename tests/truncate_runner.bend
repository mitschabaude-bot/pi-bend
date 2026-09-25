import Base
import ../packages/agent/src/harness/utils/truncate.bend as T
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/f64.bend as F
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson

def field(value: V.Value,key: String) -> V.Value:
  match value:
    case V.ObjectValue{fields}: Maybe.default(&2,V.Value,R.get(V.Value,fields,key),V.Null{})
    case _: V.Null{}
def text(value: V.Value) -> String:
  match value:
    case V.Text{value}: value
    case _: ""
def natural(value: V.Value) -> Nat:
  match value:
    case V.Number{value}: U32.to_nat(F64.to_u32(value))
    case _: 0n
def number(value: Nat) -> V.Value: V.Number{F.fromNat(value)}
def object(fields: List<&2,R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def property(key: String,value: V.Value) -> R.Property<V.Value>: R.Property{key,value}
def cause(value: T.TruncationBy) -> V.Value:
  match value:
    case T.NoLimit{}: V.Null{}
    case T.LineLimit{}: V.Text{"lines"}
    case T.ByteLimit{}: V.Text{"bytes"}
def encoded(value: T.TruncationResult) -> V.Value:
  match value:
    case T.TruncationResult{content,truncated,by,totalLines,totalBytes,outputLines,outputBytes,partial,first,maxLines,maxBytes}:
      object([
        property("content",V.Text{content}),
        property("truncated",V.Boolean{truncated}),
        property("truncatedBy",cause(by)),
        property("totalLines",number(totalLines)),
        property("totalBytes",number(totalBytes)),
        property("outputLines",number(outputLines)),
        property("outputBytes",number(outputBytes)),
        property("lastLinePartial",V.Boolean{partial}),
        property("firstLineExceedsLimit",V.Boolean{first}),
        property("maxLines",number(maxLines)),
        property("maxBytes",number(maxBytes))
      ])
def evaluate(+value: V.Value) -> V.Value:
  +content = text(field(value,"text"))
  +lines = natural(field(value,"lines"))
  +bytes = natural(field(value,"bytes"))
  object([
    property("head",encoded(T.truncateHead(content,T.TruncationOptions{Some{lines},Some{bytes}}))),
    property("tail",encoded(T.truncateTail(content,T.TruncationOptions{Some{lines},Some{bytes}})))
  ])
def cases(values: List<&2,V.Value>) -> List<&2,V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: evaluate(value) <> cases(rest)
def run(parsed: Result<&2,&2,Json.ParseError,V.Value>) -> IO(Unit):
  match parsed:
    case Done{V.ArrayValue{values}}: IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(V.ArrayValue{cases(values)})),"null"))
    case _: IO.die(Unit,1,"invalid truncation cases")
def read(result: Result<&2,&2,FS.Error,List<&2,U32>>) -> IO(Unit):
  match result:
    case Done{bytes}: run(Json.parse(Utf8.decodeBytes(bytes)))
    case Fail{_}: IO.die(Unit,1,"cannot read truncation cases")
def runArguments(arguments: List<String>) -> IO(Unit):
  match arguments:
    case path <> Nil{}:
      do IO<Unit>:
        result : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
        read(result)
    case _: IO.die(Unit,1,"expected cases file")
def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    runArguments(arguments)
