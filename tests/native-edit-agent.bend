import Base
import ./native-agent.bend as Runner
import ./native-write-agent.bend as Writer
import ./native-openai.bend as Native
import ../packages/coding-agent/src/core/tools/write.bend as Write
import ../packages/coding-agent/src/core/tools/edit.bend as Edit
import ../packages/coding-agent/src/core/tools/read.bend as Read
import ../packages/coding-agent/src/core/tools/bash.bend as Bash
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
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx

type EditExecution is Data:
  EditExecution{callback: C.Callback<Agent.ToolExecutionInput<Edit.EditToolDetails>, Edit.ToolResult()>, counter: Ref.Ref<U32>}

type ReadExecution is Data:
  ReadExecution{callback: C.Callback<Agent.ToolExecutionInput<Read.ReadToolDetails>, Read.ToolResult()>, counter: Ref.Ref<U32>}

type BashExecution is Data:
  BashExecution{callback: C.Callback<Agent.ToolExecutionInput<Bash.BashToolDetails>,Bash.ToolResult()>, counter: Ref.Ref<U32>}

# Details erasure is confined to this heterogeneous integration harness; it
# keeps whether a tool reported details at all.
def erased(-D: Data, value: Maybe<&2, D>) -> Maybe<&2, Unit>:
  match value:
    case None{}: None{}
    case Some{_}: Some{Unit{}}

# Forward real streaming updates into the canonical loop before final results.
def bashContent(value: Agent.AgentToolResult<Bash.BashToolDetails>) -> Agent.AgentToolResult<Unit>:
  match value:
    case Agent.AgentToolResult{content,own,mutation,refresh}: Agent.AgentToolResult{content,erased(Bash.BashToolDetails,own),mutation,refresh}

def bashUpdate(callback: Maybe<&2,Agent.AgentToolUpdateCallback(Unit)>, value: Agent.AgentToolResult<Bash.BashToolDetails>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: C.call(Agent.AgentToolResult<Unit>,Unit,callback,bashContent(value))

def bashResult(value: Bash.ToolResult()) -> Runner.ToolOutput():
  match value:
    case Fail{error}: Fail{Bash.errorMessage(error)}
    case Done{result}: Done{bashContent(result)}

def invokeBash(environment: BashExecution, input: Runner.ToolInput()) -> IO(Runner.ToolOutput()):
  match environment input:
    case BashExecution{callback,counter} Agent.ToolExecutionInput{id,params,signal,update}:
      do IO<Runner.ToolOutput()>:
        Ref.modify(U32,Unit,counter,value => ((value + 1 : U32),Unit{}))
        +bridge : Agent.AgentToolUpdateCallback(Bash.BashToolDetails) <- C.create(~Maybe<&2,Agent.AgentToolUpdateCallback(Unit)>,~Agent.AgentToolResult<Bash.BashToolDetails>,~Unit,~bashUpdate,update)
        result : Bash.ToolResult() <- C.call(Agent.ToolExecutionInput<Bash.BashToolDetails>,Bash.ToolResult(),callback,Agent.ToolExecutionInput{id,params,signal,Some{bridge}})
        C.dispose(Agent.AgentToolResult<Bash.BashToolDetails>,Unit,bridge)
        return bashResult(result)

def readResult(value: Read.ToolResult()) -> Runner.ToolOutput():
  match value:
    case Fail{error}: Fail{Read.errorMessage(error)}
    case Done{Agent.AgentToolResult{content,own,mutation,refresh}}: Done{Agent.AgentToolResult{content,erased(Read.ReadToolDetails,own),mutation,refresh}}

def invokeRead(environment: ReadExecution, input: Runner.ToolInput()) -> IO(Runner.ToolOutput()):
  match environment input:
    case ReadExecution{callback,counter} Agent.ToolExecutionInput{id,params,signal,_}:
      do IO<Runner.ToolOutput()>:
        Ref.modify(U32,Unit,counter,value => ((value + 1 : U32),Unit{}))
        result : Read.ToolResult() <- C.call(Agent.ToolExecutionInput<Read.ReadToolDetails>,Read.ToolResult(),callback,Agent.ToolExecutionInput{id,params,signal,None{}})
        return readResult(result)

def firstLine(value: Maybe<&2, Nat>) -> String:
  match value:
    case None{}: "none"
    case Some{line}: Nat.show(line)

# Only the integration harness erases heterogeneous details to Unit. Validate
# the actual edit result separately; model-visible content remains unchanged.
def editResult(value: Edit.ToolResult()) -> IO(Runner.ToolOutput()):
  match value:
    case Fail{error}: IO.pure(Runner.ToolOutput(), Fail{Edit.errorMessage(error)})
    case Done{Agent.AgentToolResult{content, Some{Edit.EditToolDetails{diff, patch, first}}, mutation, refresh}}:
      do IO<Runner.ToolOutput()>:
        IO.print("edit-details|" ++ Wire.showText(diff) ++ "|" ++ Wire.showText(patch) ++ "|" ++ firstLine(first))
        return Done{Agent.AgentToolResult{content, Some{Unit{}}, mutation, refresh}}
    case Done{_}: IO.die(Runner.ToolOutput(), 1, "edit result lacks details")

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

def runOwned(bundle: List<&2, X509.Certificate>, name: String, base: String, prompt: String, write: Write.ToolOwner & Agent.AgentTool<Unit, Write.Error>, edit: Edit.ToolOwner & Agent.AgentTool<Edit.EditToolDetails, Edit.Error>, read: Read.ToolOwner & Agent.AgentTool<Read.ReadToolDetails,Read.Error>, bash: Bash.ToolOwner & Agent.AgentTool<Bash.BashToolDetails,Bash.Error>) -> IO(Runner.Outcome()):
  match write edit read bash:
    case Tuple{writeOwner, Agent.AgentTool{wn, wd, wp, ws, wl, None{}, wc, wr, wm}} Tuple{editOwner, Agent.AgentTool{en, ed, ep, es, el, Some{prepare}, ec, er, em}} Tuple{readOwner,Agent.AgentTool{rn,rd,rp,rs,rl,None{},rc,rr,rm}} Tuple{bashOwner,Agent.AgentTool{bn,bd,bp,bs,bl,None{},bc,br,bm}}:
      do IO<Runner.Outcome()>:
        +bashes : Ref.Ref<U32> <- Ref.new(U32,0)
        +bashBridge : C.Callback<Runner.ToolInput(),Runner.ToolOutput()> <- C.create(~BashExecution,~Runner.ToolInput(),~Runner.ToolOutput(),~invokeBash,BashExecution{bc,bashes})
        +reads : Ref.Ref<U32> <- Ref.new(U32,0)
        +readBridge : C.Callback<Runner.ToolInput(),Runner.ToolOutput()> <- C.create(~ReadExecution,~Runner.ToolInput(),~Runner.ToolOutput(),~invokeRead,ReadExecution{rc,reads})
        +writes : Ref.Ref<U32> <- Ref.new(U32, 0)
        +edits : Ref.Ref<U32> <- Ref.new(U32, 0)
        +writeBridge : C.Callback<Runner.ToolInput(), Runner.ToolOutput()> <- C.create(~Writer.Execution, ~Runner.ToolInput(), ~Runner.ToolOutput(), ~Writer.invoke, Writer.Execution{wc, writes})
        +editBridge : C.Callback<Runner.ToolInput(), Runner.ToolOutput()> <- C.create(~EditExecution, ~Runner.ToolInput(), ~Runner.ToolOutput(), ~invokeEdit, EditExecution{ec, edits})
        +prepareBridge : C.Callback<V.Value, Result<&2, &2, String, V.Value>> <- C.create(~C.Callback<V.Value, Edit.ResultOf(V.Value)>, ~V.Value, ~Result<&2, &2, String, V.Value>, ~prepareEdit, prepare)
        tools : List<&2, Agent.AgentTool<Unit, String>> = Agent.AgentTool{wn, wd, wp, ws, wl, None{}, writeBridge, wr, wm} <> Agent.AgentTool{en, ed, ep, es, el, Some{prepareBridge}, editBridge, er, em} <> Agent.AgentTool{rn,rd,rp,rs,rl,None{},readBridge,rr,rm} <> Agent.AgentTool{bn,bd,bp,bs,bl,None{},bashBridge,br,bm} <> Nil{}
        result : Runner.Outcome() <- Runner.runTools(bundle, name, base, prompt, tools, 4096)
        C.dispose(Runner.ToolInput(),Runner.ToolOutput(),bashBridge)
        Bash.disposeTool(bashOwner)
        bashCount : U32 <- Ref.dispose(U32,bashes)
        C.dispose(Runner.ToolInput(),Runner.ToolOutput(),readBridge)
        Read.disposeTool(readOwner)
        readCount : U32 <- Ref.dispose(U32,reads)
        C.dispose(Runner.ToolInput(), Runner.ToolOutput(), writeBridge)
        C.dispose(Runner.ToolInput(), Runner.ToolOutput(), editBridge)
        C.dispose(V.Value, Result<&2, &2, String, V.Value>, prepareBridge)
        Write.disposeTool(writeOwner)
        Edit.disposeTool(editOwner)
        writeCount : U32 <- Ref.dispose(U32, writes)
        editCount : U32 <- Ref.dispose(U32, edits)
        IO.print("executions write=" ++ U32.show(writeCount) ++ " edit=" ++ U32.show(editCount) ++ " read=" ++ U32.show(readCount) ++ " bash=" ++ U32.show(bashCount))
        return result
    case _ _ _ _: IO.die(Runner.Outcome(), 1, "unexpected native tool metadata")

def runQueue(bundle: List<&2, X509.Certificate>, name: String, base: String, prompt: String, +cwd: String, +environment: Paths.Environment, queue: Queue.Owner & Queue.Queue) -> IO(Unit):
  match queue:
    case (owner, +handle):
      do IO<Unit>:
        +unbound1 : Ctx.ContextSource() <- Ctx.create()
        write : Write.ToolOwner <- Write.createWriteTool(environment, handle, cwd, Write.WriteToolOptions{None{}},unbound1)
        +unbound2 : Ctx.ContextSource() <- Ctx.create()
        edit : Edit.ToolOwner <- Edit.createEditTool(environment, handle, cwd, Edit.EditToolOptions{None{}},unbound2)
        +unbound3 : Ctx.ContextSource() <- Ctx.create()
        read : Read.ToolOwner <- Read.createReadTool(environment,cwd,Read.ReadToolOptions{None{},None{},None{},None{}},unbound3)
        +unbound4 : Ctx.ContextSource() <- Ctx.create()
        bash : Bash.ToolOwner <- Bash.createBashTool(cwd ++ "/.pi/bin",cwd,Bash.defaults(),unbound4)
        result : Runner.Outcome() <- runOwned(bundle, name, base, prompt, Write.borrowTool(write), Edit.borrowTool(edit),Read.borrowTool(read),Bash.borrowTool(bash))
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
