import Base
import ./native-agent.bend as Runner
import ./native-write-agent.bend as Writer
import ./native-openai.bend as Native
import ../packages/coding-agent/src/core/tools/write.bend as Write
import ../packages/coding-agent/src/core/tools/edit.bend as Edit
import ../packages/coding-agent/src/core/tools/file-mutation-queue.bend as Queue
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/agent/src/types.bend as Agent
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/tls-trust.bend as Trust
import ../packages/runtime/src/x509.bend as X509
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/test/utf8-runner.bend as Wire

type EditExecution is Data:
  EditExecution{callback: C.Callback<Agent.ToolExecutionInput<Edit.EditToolDetails>, Edit.ToolResult()>, counter: Ref.Ref<U32>}

def firstLine(value: Maybe<&2, Nat>) -> String:
  match value:
    case None{}: "none"
    case Some{line}: Nat.show(line)

# Only the integration harness erases heterogeneous details to Unit. Validate
# the actual edit result separately; model-visible content remains unchanged.
def editResult(value: Edit.ToolResult()) -> IO(Runner.ToolOutput()):
  match value:
    case Fail{error}: IO.pure(Runner.ToolOutput(), Fail{Edit.errorMessage(error)})
    case Done{Agent.AgentToolResult{content, Edit.EditToolDetails{diff, patch, first}, mutation, refresh}}:
      do IO<Runner.ToolOutput()>:
        IO.print("edit-details|" ++ Wire.showText(diff) ++ "|" ++ Wire.showText(patch) ++ "|" ++ firstLine(first))
        return Done{Agent.AgentToolResult{content, Unit{}, mutation, refresh}}

def invokeEdit(environment: EditExecution, input: Runner.ToolInput()) -> IO(Runner.ToolOutput()):
  match environment input:
    case EditExecution{callback, counter} Agent.ToolExecutionInput{id, params, signal, _}:
      do IO<Runner.ToolOutput()>:
        Ref.modify(U32, Unit, counter, value => ((value + 1 : U32), Unit{}))
        result : Edit.ToolResult() <- C.call(Agent.ToolExecutionInput<Edit.EditToolDetails>, Edit.ToolResult(), callback, Agent.ToolExecutionInput{id, params, signal, None{}})
        editResult(result)

def prepared(value: Edit.ResultOf(V.Value)) -> Result<&2, &2, String, V.Value>:
  match value:
    case Fail{error}: Fail{Edit.errorMessage(error)}
    case Done{arguments}: Done{arguments}

def prepareEdit(callback: C.Callback<V.Value, Edit.ResultOf(V.Value)>, input: V.Value) -> IO(Result<&2, &2, String, V.Value>):
  do IO<Result<&2, &2, String, V.Value>>:
    result : Edit.ResultOf(V.Value) <- C.call(V.Value, Edit.ResultOf(V.Value), callback, input)
    return prepared(result)

def runOwned(bundle: List<&2, X509.Certificate>, name: String, base: String, prompt: String, write: Write.ToolOwner & Agent.AgentTool<Unit, Write.Error>, edit: Edit.ToolOwner & Agent.AgentTool<Edit.EditToolDetails, Edit.Error>) -> IO(Runner.Outcome()):
  match write edit:
    case Tuple{writeOwner, Agent.AgentTool{wn, wd, wp, ws, wl, None{}, wc, wr, wm}} Tuple{editOwner, Agent.AgentTool{en, ed, ep, es, el, Some{prepare}, ec, er, em}}:
      do IO<Runner.Outcome()>:
        +writes : Ref.Ref<U32> <- Ref.new(U32, 0)
        +edits : Ref.Ref<U32> <- Ref.new(U32, 0)
        +writeBridge : C.Callback<Runner.ToolInput(), Runner.ToolOutput()> <- C.create(~Writer.Execution, ~Runner.ToolInput(), ~Runner.ToolOutput(), ~Writer.invoke, Writer.Execution{wc, writes})
        +editBridge : C.Callback<Runner.ToolInput(), Runner.ToolOutput()> <- C.create(~EditExecution, ~Runner.ToolInput(), ~Runner.ToolOutput(), ~invokeEdit, EditExecution{ec, edits})
        +prepareBridge : C.Callback<V.Value, Result<&2, &2, String, V.Value>> <- C.create(~C.Callback<V.Value, Edit.ResultOf(V.Value)>, ~V.Value, ~Result<&2, &2, String, V.Value>, ~prepareEdit, prepare)
        tools : List<&2, Agent.AgentTool<Unit, String>> = Agent.AgentTool{wn, wd, wp, ws, wl, None{}, writeBridge, wr, wm} <> Agent.AgentTool{en, ed, ep, es, el, Some{prepareBridge}, editBridge, er, em} <> Nil{}
        result : Runner.Outcome() <- Runner.runTools(bundle, name, base, prompt, tools, 4096)
        C.dispose(Runner.ToolInput(), Runner.ToolOutput(), writeBridge)
        C.dispose(Runner.ToolInput(), Runner.ToolOutput(), editBridge)
        C.dispose(V.Value, Result<&2, &2, String, V.Value>, prepareBridge)
        Write.disposeTool(writeOwner)
        Edit.disposeTool(editOwner)
        writeCount : U32 <- Ref.dispose(U32, writes)
        editCount : U32 <- Ref.dispose(U32, edits)
        IO.print("executions write=" ++ U32.show(writeCount) ++ " edit=" ++ U32.show(editCount))
        return result
    case _ _: IO.die(Runner.Outcome(), 1, "unexpected native tool metadata")

def runQueue(bundle: List<&2, X509.Certificate>, name: String, base: String, prompt: String, +cwd: String, +environment: Paths.Environment, queue: Queue.Owner & Queue.Queue) -> IO(Unit):
  match queue:
    case (owner, +handle):
      do IO<Unit>:
        write : Write.ToolOwner <- Write.createWriteTool(environment, handle, cwd, Write.WriteToolOptions{None{}})
        edit : Edit.ToolOwner <- Edit.createEditTool(environment, handle, cwd, Edit.EditToolOptions{None{}})
        result : Runner.Outcome() <- runOwned(bundle, name, base, prompt, Write.borrowTool(write), Edit.borrowTool(edit))
        Queue.dispose(owner)
        Runner.report(result)

def loadedEnvironment(bundle: List<&2, X509.Certificate>, name: String, base: String, prompt: String, cwd: String, environment: Result<&2, &2, FS.Error, Paths.Environment>) -> IO(Unit):
  match environment:
    case Fail{error}: IO.die(Unit, 1, Writer.fileError(error))
    case Done{value}:
      do IO<Unit>:
        queue : Queue.Owner <- Queue.create()
        runQueue(bundle, name, base, prompt, cwd, value, Queue.borrow(queue))

def loaded(name: String, base: String, prompt: String, cwd: String, certificates: Result<&2, &2, Trust.Error, List<&2, X509.Certificate>>) -> IO(Unit):
  match certificates:
    case Fail{_}: IO.die(Unit, 1, "trust bundle failed")
    case Done{bundle}:
      do IO<Unit>:
        environment : Result<&2, &2, FS.Error, Paths.Environment> <- Paths.loadEnvironment(Native.urlContext())
        loadedEnvironment(bundle, name, base, prompt, cwd, environment)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case bundle <> name <> base <> prompt <> cwd <> Nil{}:
      do IO<Unit>:
        certificates : Result<&2, &2, Trust.Error, List<&2, X509.Certificate>> <- Trust.load(bundle, 1048576n)
        loaded(name, base, prompt, cwd, certificates)
    case _: IO.die(Unit, 1, "expected trust-bundle model base-url prompt cwd")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
