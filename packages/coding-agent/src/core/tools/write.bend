import Base
import ../../utils/paths.bend as Paths
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/schema-value.bend as Value
import ../../../../runtime/src/record.bend as Record
import ./file-mutation-queue.bend as Queue
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/callback.bend as Callback
import ../extensions/context.bend as Ctx
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/string.bend as Strings

# Native write tool and filesystem execution. Extension ToolDefinition and
# terminal rendering remain separate public-boundary integration work.
type WriteToolInput is Data:
  WriteToolInput{path: String, content: String}

type Error is Data:
  Filesystem{cause: FS.Error}
  Operation{message: String}
  Aborted{}
  InvalidPath{cause: Paths.Error}
  InvalidArguments{}

def Outcome() -> Data: Result<&2, &2, Error, Unit>

type WriteOperations is Data:
  WriteOperations{writeFile: Callback.Callback<(String & String), Outcome()>, mkdir: Callback.Callback<String, Outcome()>}

def filesystem(result: Result<&2, &2, FS.Error, Unit>) -> Outcome():
  match result:
    case Done{value}: Done{value}
    case Fail{cause}: Fail{Filesystem{cause}}

def localWrite(environment: Unit, input: String & String) -> IO(Outcome()):
  match input:
    case (path, content):
      do IO<Outcome()>:
        value : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(path, content)
        return filesystem(value)

def localMkdir(environment: Unit, path: String) -> IO(Outcome()):
  do IO<Outcome()>:
    value : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(path)
    return filesystem(value)

def defaultWriteOperations() -> IO(WriteOperations):
  do IO<WriteOperations>:
    writer : Callback.Callback<(String & String), Outcome()> <- Callback.create(~Unit, ~(String & String), ~Outcome(), ~localWrite, Unit{})
    mkdir : Callback.Callback<String, Outcome()> <- Callback.create(~Unit, ~String, ~Outcome(), ~localMkdir, Unit{})
    return WriteOperations{writer, mkdir}

# The owner retires callbacks only after every invocation has settled.
def dispose(operations: WriteOperations) -> IO(Unit):
  match operations:
    case WriteOperations{writer, mkdir}:
      do IO<Unit>:
        Callback.dispose(String & String, Outcome(), writer)
        Callback.dispose(String, Outcome(), mkdir)

def cancellation(aborted: Bool) -> Outcome():
  match aborted:
    case True{}: Fail{Aborted{}}
    case False{}: Done{Unit{}}

def check(signal: Maybe<&2, Abort.AbortSignal<Unit>>, previous: Outcome()) -> IO(Outcome()):
  match signal previous:
    case _ Fail{error}: IO.pure(Outcome(), Fail{error})
    case None{} Done{Unit{}}: IO.pure(Outcome(), Done{Unit{}})
    case Some{value} Done{Unit{}}:
      do IO<Outcome()>:
        aborted : Bool <- Abort.aborted(Unit, value)
        return cancellation(aborted)

# Paths reaching this core have already been normalized to absolute paths.
def parentParts(parts: List<&2, String>) -> String:
  match parts:
    case _ <> "" <> Nil{}: "/"
    case _ <> rest: String.join(List.reverse(&2, String, rest), "/")
    case Nil{}: "/"

def parent(path: String) -> String:
  parentParts(List.reverse(&2, String, Strings.split(path, '/')))

def makeDirectory(callback: Callback.Callback<String, Outcome()>, path: String, previous: Outcome()) -> IO(Outcome()):
  match previous:
    case Fail{error}: IO.pure(Outcome(), Fail{error})
    case Done{Unit{}}: Callback.call(String, Outcome(), callback, path)

def writeFile(callback: Callback.Callback<(String & String), Outcome()>, path: String, content: String, previous: Outcome()) -> IO(Outcome()):
  match previous:
    case Fail{error}: IO.pure(Outcome(), Fail{error})
    case Done{Unit{}}: Callback.call(String & String, Outcome(), callback, (path, content))

def write(operations: WriteOperations, +absolutePath: String, content: String, +signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Outcome()):
  match operations:
    case WriteOperations{writer, mkdir}:
      do IO<Outcome()>:
        before : Outcome() <- check(signal, Done{Unit{}})
        made : Outcome() <- makeDirectory(mkdir, parent(absolutePath), before)
        ready : Outcome() <- check(signal, made)
        written : Outcome() <- writeFile(writer, absolutePath, content, ready)
        check(signal, written)

def queued(result: Result<&2, &1, FS.Error, Outcome()>) -> Outcome():
  match result:
    case Fail{cause}: Fail{Filesystem{cause}}
    case Done{value}: value

# No cancellation race detaches filesystem work. Queue ownership lasts until
# write returns, including a write that finishes after cancellation was requested.
def execute(queue: Queue.Queue, operations: WriteOperations, +absolutePath: String, content: String, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Outcome()):
  do IO<Outcome()>:
    value : Result<&2, &1, FS.Error, Outcome()> <- Queue.withFileMutationQueue(Outcome(), queue, absolutePath, _ => write(operations, absolutePath, content, signal))
    return queued(value)


type WriteToolOptions is Data:
  WriteToolOptions{operations: Maybe<&2, WriteOperations>}

type Invocation is Data:
  Invocation{paths: Paths.Environment, cwd: String, queue: Queue.Queue, operations: WriteOperations}

# The owner retains its execution callback and any default operations it created.
# Injected operations are borrowed and remain owned by the caller.
type ToolOwner is Type:
  ToolOwner{tool: Agent.AgentTool<Unit, Error>, ownedOperations: Maybe<&2, WriteOperations>}

def ToolResult() -> Data: Result<&2, &2, Error, Agent.AgentToolResult<Unit>>

def parameters(path: Maybe<&2, Value.Value>, content: Maybe<&2, Value.Value>) -> Result<&2, &2, Error, WriteToolInput>:
  match path content:
    case Some{Value.Text{path}} Some{Value.Text{content}}: Done{WriteToolInput{path, content}}
    case _ _: Fail{InvalidArguments{}}

def parseInput(value: Value.Value) -> Result<&2, &2, Error, WriteToolInput>:
  match value:
    case Value.ObjectValue{+fields}: parameters(Record.get(Value.Value, fields, "path"), Record.get(Value.Value, fields, "content"))
    case _: Fail{InvalidArguments{}}

def toolResult(path: String, value: Outcome()) -> ToolResult():
  match value:
    case Fail{error}: Fail{error}
    case Done{Unit{}}: Done{Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{"Successfully wrote to " ++ path, None{}}} <> Nil{}, None{}, None{}, None{}}}

def resolvedInput(queue: Queue.Queue, operations: WriteOperations, path: String, content: String, signal: Maybe<&2, Abort.AbortSignal<Unit>>, resolved: Result<&2, &2, Paths.Error, String>) -> IO(ToolResult()):
  match resolved:
    case Fail{cause}: IO.pure(ToolResult(), Fail{InvalidPath{cause}})
    case Done{absolutePath}:
      do IO<ToolResult()>:
        result : Outcome() <- execute(queue, operations, absolutePath, content, signal)
        return toolResult(path, result)

def invokeInput(environment: Invocation, context: Maybe<&2, Ctx.ExtensionContext>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, parsed: Result<&2, &2, Error, WriteToolInput>) -> IO(ToolResult()):
  match environment parsed:
    case _ Fail{error}: IO.pure(ToolResult(), Fail{error})
    case Invocation{paths, cwd, queue, operations} Done{WriteToolInput{+path, content}}:
      resolvedInput(queue, operations, path, content, signal, Paths.resolveToCwd(paths, path, Ctx.cwdOr(context, cwd)))

# upstream wrapToolDefinition: the registered tool resolves paths against the
# session's cwd when it runs, or its own without a bound session.
type Registered is Data: Registered{environment: Invocation, source: Ctx.ContextSource()}
def invokeRequest(environment: Invocation, context: Maybe<&2, Ctx.ExtensionContext>, request: Agent.ToolExecutionInput<Unit>) -> IO(ToolResult()):
  match request:
    case Agent.ToolExecutionInput{_, arguments, signal, _}: invokeInput(environment, context, signal, parseInput(arguments))

def invoke(registered: Registered, request: Agent.ToolExecutionInput<Unit>) -> IO(ToolResult()):
  match registered:
    case Registered{environment, source}:
      do IO<ToolResult()>:
        context : Maybe<&2, Ctx.ExtensionContext> <- Ctx.current(source)
        invokeRequest(environment, context, request)

def stringParameter(description: String) -> Value.Value:
  Value.ObjectValue{Record.Record{Record.Property{"type", Value.Text{"string"}} <> Record.Property{"description", Value.Text{description}} <> Nil{}}}

def writeSchema() -> Value.Value:
  Value.ObjectValue{Record.Record{
    Record.Property{"type", Value.Text{"object"}} <>
    Record.Property{"properties", Value.ObjectValue{Record.Record{
      Record.Property{"path", stringParameter("Path to the file to write (relative or absolute)")} <>
      Record.Property{"content", stringParameter("Content to write to the file")} <> Nil{}}}} <>
    Record.Property{"required", Value.ArrayValue{Value.Text{"path"} <> Value.Text{"content"} <> Nil{}}} <> Nil{}}}

def created(environment: Registered, owned: Maybe<&2, WriteOperations>) -> IO(ToolOwner):
  do IO<ToolOwner>:
    callback : Callback.Callback<Agent.ToolExecutionInput<Unit>, ToolResult()> <- Callback.create(~Registered, ~Agent.ToolExecutionInput<Unit>, ~ToolResult(), ~invoke, environment)
    return ToolOwner{Agent.AgentTool{"write", "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories.", writeSchema(), Some{Ai.SamplingConfigured{Ai.JsonSchemaSampling{Ai.Prefer{}}}}, "write", None{}, callback, None{}, None{}}, owned}

# Environment and shared queue are explicit native runtime dependencies.
def createWriteTool(environment: Paths.Environment, queue: Queue.Queue, cwd: String, options: WriteToolOptions, source: Ctx.ContextSource()) -> IO(ToolOwner):
  match options:
    case WriteToolOptions{Some{operations}}: created(Registered{Invocation{environment, cwd, queue, operations}, source}, None{})
    case WriteToolOptions{None{}}:
      do IO<ToolOwner>:
        +operations : WriteOperations <- defaultWriteOperations()
        created(Registered{Invocation{environment, cwd, queue, operations}, source}, Some{operations})

def borrowTool(owner: ToolOwner) -> ToolOwner & Agent.AgentTool<Unit, Error>:
  match owner:
    case ToolOwner{+tool, operations}: (ToolOwner{tool, operations}, tool)

def disposeOwned(owned: Maybe<&2, WriteOperations>) -> IO(Unit):
  match owned:
    case None{}: IO.pure(Unit, Unit{})
    case Some{operations}: dispose(operations)

def disposeTool(owner: ToolOwner) -> IO(Unit):
  match owner:
    case ToolOwner{Agent.AgentTool{_, _, _, _, _, _, callback, _, _}, operations}:
      do IO<Unit>:
        Callback.dispose(Agent.ToolExecutionInput<Unit>, ToolResult(), callback)
        disposeOwned(operations)
