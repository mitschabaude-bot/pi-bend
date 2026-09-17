import Base
import ../src/native.bend as N
import ../src/json.bend as J
import ../src/util.bend as U
import ../src/tools.bend as T

def emit(result: T.ToolResult) -> IO(Unit):
  match result:
    case T.ToolResult{text, error}: IO.print(J.encode(J.Object{J.str_field("text", text, J.Field{"error", J.Boolean{error}, J.End{}})}))

def main() -> IO(Unit):
  do IO<Unit>:
    name : String <- N.arg(1n)
    raw : String <- N.arg(2n)
    args : J.Json <- U.parsed(J.parse(raw))
    cwd : String <- N.cwd()
    result : T.ToolResult <- T.execute(name, args, cwd)
    emit(result)
