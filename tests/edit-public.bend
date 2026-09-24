import Base
import ../packages/coding-agent/src/core/tools/edit.bend as E
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
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/test/utf8-runner.bend as Wire
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx

def environment(cwd: String, home: String) -> Paths.Environment:
  Paths.Environment{cwd, home, URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}}

def line(value: Maybe<&2, Nat>) -> String:
  match value:
    case None{}: "none"
    case Some{value}: Nat.show(value)

def report(result: E.ToolResult()) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("error|" ++ Wire.showText(E.errorMessage(error)))
    case Done{Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{text, _}} <> Nil{}, E.EditToolDetails{diff, patch, first}, _, _}}:
      IO.print("ok|" ++ Wire.showText(text) ++ "|" ++ Wire.showText(diff) ++ "|" ++ Wire.showText(patch) ++ "|" ++ line(first))
    case _: IO.die(Unit, 1, "invalid edit result")

def execute(callback: C.Callback<Agent.ToolExecutionInput<E.EditToolDetails>, E.ToolResult()>, prepared: E.ResultOf(V.Value)) -> IO(Unit):
  match prepared:
    case Fail{error}: report(Fail{error})
    case Done{arguments}:
      do IO<Unit>:
        result : E.ToolResult() <- C.call(Agent.ToolExecutionInput<E.EditToolDetails>, E.ToolResult(), callback, Agent.ToolExecutionInput{"edit-1", arguments, None{}, None{}})
        report(result)

def call(pair: E.ToolOwner & Agent.AgentTool<E.EditToolDetails, E.Error>, arguments: V.Value) -> IO(Unit):
  match pair:
    case (owner, Agent.AgentTool{name, _, _, Some{Ai.SamplingConfigured{Ai.JsonSchemaSampling{Ai.Prefer{}}}}, label, Some{prepare}, callback, None{}, None{}}):
      do IO<Unit>:
        Test.check(String.eq(name, "edit") && String.eq(label, "edit"), "edit metadata")
        prepared : E.ResultOf(V.Value) <- C.call(V.Value, E.ResultOf(V.Value), prepare, arguments)
        execute(callback, prepared)
        E.disposeTool(owner)
    case _: IO.die(Unit, 1, "invalid edit metadata")

def runQueue(pair: Q.Owner & Q.Queue, +cwd: String, arguments: V.Value) -> IO(Unit):
  match pair:
    case (owner, queue):
      do IO<Unit>:
        +unbound1 : Ctx.ContextSource() <- Ctx.create()
        tool : E.ToolOwner <- E.createEditTool(environment(cwd, cwd), queue, cwd, E.EditToolOptions{None{}},unbound1)
        call(E.borrowTool(tool), arguments)
        Q.dispose(owner)

def parsed(cwd: String, result: Result<&2, &2, Json.ParseError, V.Value>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "invalid JSON fixture argument")
    case Done{arguments}:
      do IO<Unit>:
        owner : Q.Owner <- Q.create()
        runQueue(Q.borrow(owner), cwd, arguments)

def run(args: List<String>) -> IO(Unit):
  match args:
    case cwd <> json <> Nil{}: parsed(cwd, Json.parse(json))
    case _: IO.die(Unit, 1, "invalid edit fixture arguments")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
