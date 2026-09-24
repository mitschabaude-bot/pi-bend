import Base
import ../packages/coding-agent/src/core/tools/write.bend as W
import ../packages/coding-agent/src/core/tools/file-mutation-queue.bend as Q
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties
import ./file-mutation-queue.bend as Test
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx

def environment(cwd: String, home: String) -> Paths.Environment:
  Paths.Environment{cwd, home, URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}}

def arguments(path: String, content: String) -> V.Value:
  V.ObjectValue{R.Record{R.Property{"path", V.Text{path}} <> R.Property{"content", V.Text{content}} <> Nil{}}}

def report(path: String, value: W.ToolResult()) -> IO(Unit):
  match value:
    case Done{Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{+text, None{}}} <> Nil{}, None{}, None{}, None{}}}:
      do IO<Unit>:
        Test.check(String.eq(text, "Successfully wrote to " ++ path), "write result text")
        IO.print(text)
    case Fail{W.InvalidPath{_}}: IO.print("path error")
    case Fail{W.InvalidArguments{}}: IO.print("argument error")
    case _: IO.die(Unit, 1, "unexpected public write outcome")

def call(pair: W.ToolOwner & Agent.AgentTool<Unit, W.Error>, +path: String, content: String) -> IO(Unit):
  match pair:
    case (owner, Agent.AgentTool{name, description, _, Some{Ai.SamplingConfigured{Ai.JsonSchemaSampling{Ai.Prefer{}}}}, label, None{}, callback, None{}, None{}}):
      do IO<Unit>:
        Test.check(String.eq(name, "write") && String.eq(label, "write") && String.eq(description, "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories."), "write metadata")
        result : W.ToolResult() <- C.call(Agent.ToolExecutionInput<Unit>, W.ToolResult(), callback, Agent.ToolExecutionInput{"call-1", arguments(path, content), None{}, None{}})
        report(path, result)
        W.disposeTool(owner)
    case _: IO.die(Unit, 1, "unexpected public write metadata")

def runQueue(pair: Q.Owner & Q.Queue, +cwd: String, home: String, path: String, content: String) -> IO(Unit):
  match pair:
    case (owner, queue):
      do IO<Unit>:
        +unbound1 : Ctx.ContextSource() <- Ctx.create()
        tool : W.ToolOwner <- W.createWriteTool(environment(cwd, home), queue, cwd, W.WriteToolOptions{None{}},unbound1)
        call(W.borrowTool(tool), path, content)
        Q.dispose(owner)

def run(args: List<String>) -> IO(Unit):
  match args:
    case cwd <> home <> path <> content <> Nil{}:
      do IO<Unit>:
        owner : Q.Owner <- Q.create()
        runQueue(Q.borrow(owner), cwd, home, path, content)
    case _: IO.die(Unit, 1, "invalid public write fixture arguments")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
