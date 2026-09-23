import Base
import ../packages/coding-agent/src/modes/rpc.bend as Rpc
import ../packages/ai/src/utils/message-json.bend as Json
import ../packages/runtime/src/schema-value.bend as V

def values(lines: List<&2,String>) -> List<&2,V.Value>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: V.Text{line} <> values(rest)
def emit(value: Rpc.Frame) -> IO(Unit):
  match value:
    case Rpc.Frame{records,pending}:
      IO.write(Rpc.line(Json.object(Json.field("records",V.ArrayValue{values(records)},Json.field("pending",V.Text{pending},Nil{})))))
def combined(records: List<&2,String>,value: Rpc.Frame) -> Rpc.Frame:
  match value:
    case Rpc.Frame{more,tail}: Rpc.Frame{List.append(&2,String,records,more),tail}
def appended(first: Rpc.Frame,chunk: String) -> Rpc.Frame:
  match first:
    case Rpc.Frame{records,pending}: combined(records,Rpc.frame(pending,chunk))
def main() -> IO(Unit):
  do IO<Unit>:
    emit(Rpc.frame("","{\"a\":1}\r\n{\"b\":2}\r\n"))
    emit(Rpc.frame("","{\"text\":\"a\u{2028}b\u{2029}c\"}\n"))
    emit(Rpc.frame("","{\"a\":1}"))
    emit(appended(Rpc.frame("","{\"a\":"),"1}\n{\"b\":2}"))
    IO.write(Rpc.line(Rpc.ok(Some{"r1"},"abort")))
    IO.write(Rpc.line(Rpc.failure(None{},"unknown","Unknown command: unknown")))
