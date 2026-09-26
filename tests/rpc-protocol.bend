import Base
import ../packages/coding-agent/src/modes/rpc.bend as Rpc
import ../packages/coding-agent/src/modes/jsonl.bend as Jsonl
import ../packages/ai/src/utils/message-json.bend as Json
import ../packages/runtime/src/schema-value.bend as V

def values(lines: List<&2,String>) -> List<&2,V.Value>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: V.Text{line} <> values(rest)
def emit(value: Jsonl.Frame) -> IO(Unit):
  match value:
    case Jsonl.Frame{records,pending}:
      IO.write(Rpc.line(Json.object(Json.field("records",V.ArrayValue{values(records)},Json.field("pending",V.Text{pending},Nil{})))))
def combined(records: List<&2,String>,value: Jsonl.Frame) -> Jsonl.Frame:
  match value:
    case Jsonl.Frame{more,tail}: Jsonl.Frame{List.append(&2,String,records,more),tail}
def appended(first: Jsonl.Frame,chunk: String) -> Jsonl.Frame:
  match first:
    case Jsonl.Frame{records,pending}: combined(records,Jsonl.frame(pending,chunk))
def main() -> IO(Unit):
  do IO<Unit>:
    emit(Jsonl.frame("","{\"a\":1}\r\n{\"b\":2}\r\n"))
    emit(Jsonl.frame("","{\"text\":\"a\u{2028}b\u{2029}c\"}\n"))
    emit(Jsonl.frame("","{\"a\":1}"))
    emit(appended(Jsonl.frame("","{\"a\":"),"1}\n{\"b\":2}"))
    IO.write(Rpc.line(Rpc.ok(Some{"r1"},"abort")))
    IO.write(Rpc.line(Rpc.failure(None{},"unknown","Unknown command: unknown")))
