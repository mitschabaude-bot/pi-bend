import Base
import ./native-agent.bend as Runner
import ./native-openai.bend as Native
import ../packages/coding-agent/src/core/tools/write.bend as Write
import ../packages/coding-agent/src/core/tools/file-mutation-queue.bend as Queue
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/agent/src/types.bend as Agent
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/tls-trust.bend as Trust
import ../packages/runtime/src/x509.bend as X509

type Execution is Data:
  Execution{callback: C.Callback<Runner.ToolInput(), Write.ToolResult()>, counter: Ref.Ref<U32>}

def fileError(error: FS.Error) -> String:
  match error:
    case FS.System{_, message}: message
    case FS.InvalidPathEncoding{_}: "Invalid filename encoding"
    case FS.WriteAndClose{_, write, _, close}: write ++ "; close: " ++ close

# This fixture uses String as the loop's error type. The canonical write tool
# still exposes its typed errors; only this host boundary formats them.
def writeResult(value: Write.ToolResult()) -> Runner.ToolOutput():
  match value:
    case Done{result}: Done{result}
    case Fail{Write.Aborted{}}: Fail{"Operation aborted"}
    case Fail{Write.Operation{message}}: Fail{message}
    case Fail{Write.Filesystem{error}}: Fail{fileError(error)}
    case Fail{Write.InvalidPath{_}}: Fail{"Invalid write path"}
    case Fail{Write.InvalidArguments{}}: Fail{"write expects string path and content"}

def invoke(environment: Execution, input: Runner.ToolInput()) -> IO(Runner.ToolOutput()):
  match environment:
    case Execution{callback, counter}:
      do IO<Runner.ToolOutput()>:
        Ref.modify(U32, Unit, counter, value => ((value + 1 : U32), Unit{}))
        result : Write.ToolResult() <- C.call(Runner.ToolInput(), Write.ToolResult(), callback, input)
        return writeResult(result)

def runOwned(bundle: List<&2, X509.Certificate>, name: String, base: String, prompt: String, owned: Write.ToolOwner & Agent.AgentTool<Unit, Write.Error>) -> IO(Runner.Outcome()):
  match owned:
    case (owner, Agent.AgentTool{toolName, description, parameters, sampling, label, None{}, callback, replay, mode}):
      do IO<Runner.Outcome()>:
        +counter : Ref.Ref<U32> <- Ref.new(U32, 0)
        +bridge : C.Callback<Runner.ToolInput(), Runner.ToolOutput()> <- C.create(~Execution, ~Runner.ToolInput(), ~Runner.ToolOutput(), ~invoke, Execution{callback, counter})
        result : Runner.Outcome() <- Runner.runTool(bundle, name, base, prompt, Agent.AgentTool{toolName, description, parameters, sampling, label, None{}, bridge, replay, mode}, 2048)
        C.dispose(Runner.ToolInput(), Runner.ToolOutput(), bridge)
        Write.disposeTool(owner)
        count : U32 <- Ref.dispose(U32, counter)
        IO.print("executions " ++ U32.show(count))
        return result
    case _: IO.die(Runner.Outcome(), 1, "unexpected write tool preparation callback")

def runQueue(bundle: List<&2, X509.Certificate>, name: String, base: String, prompt: String, +cwd: String, environment: Paths.Environment, queue: Queue.Owner & Queue.Queue) -> IO(Unit):
  match queue:
    case (owner, handle):
      do IO<Unit>:
        tool : Write.ToolOwner <- Write.createWriteTool(environment, handle, cwd, Write.WriteToolOptions{None{}})
        result : Runner.Outcome() <- runOwned(bundle, name, base, prompt, Write.borrowTool(tool))
        Queue.dispose(owner)
        Runner.report(result)

def loadedEnvironment(bundle: List<&2, X509.Certificate>, name: String, base: String, prompt: String, cwd: String, environment: Result<&2, &2, FS.Error, Paths.Environment>) -> IO(Unit):
  match environment:
    case Fail{error}: IO.die(Unit, 1, fileError(error))
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
