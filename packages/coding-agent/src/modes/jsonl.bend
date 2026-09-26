import Base
import ../../../runtime/src/schema-value.bend as V
import ../../../ai/src/utils/json.bend as Json
import ../../../ai/src/utils/schema-json.bend as SchemaJson

# pi v0.87.1 modes/rpc/jsonl.ts: strict LF-delimited JSON records, shared by
# the RPC endpoint and RpcClient. U+2028/U+2029 stay unescaped inside payloads
# and only LF separates records; a trailing CR is removed from each record.

# upstream serializeJsonLine
def serializeJsonLine(value: V.Value) -> String:
  Maybe.default(&2,String,Json.stringify(SchemaJson.toJson(value)),"null") ++ "\n"

# upstream attachJsonlLineReader's buffer step, over already decoded text: the
# complete records of `buffer ++ chunk` and the unterminated remainder. The
# caller emits `pending` itself at end of stream, as upstream's onEnd does.
type Frame is Data: Frame{records: List<&2,String>,pending: String}
def withoutCR(+value: String) -> String:
  Bool.pick(String,String.ends_with(value,"\r"),String.take(value,String.length(value) - 1n),value)
def prependRecord(head: String,value: Frame) -> Frame:
  match value:
    case Frame{records,pending}: Frame{withoutCR(head) <> records,pending}
def collect(parts: List<&2,String>) -> Frame:
  match parts:
    case Nil{}: Frame{Nil{},""}
    case tail <> Nil{}: Frame{Nil{},tail}
    case head <> rest: prependRecord(head,collect(rest))
def frame(buffer: String,chunk: String) -> Frame:
  collect(String.split(buffer ++ chunk,'\n'))
