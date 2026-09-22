import Base
import ../../../../agent/src/types.bend as Agent
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/posix-path.bend as Path
import ../../utils/paths.bend as Paths
import ./read.bend as Read
import ./bash.bend as Bash
import ./edit.bend as Edit
import ./write.bend as Write
import ./find.bend as Find
import ./file-mutation-queue.bend as Queue

# The public coding tools behind one agent-tool type. Upstream erases each
# tool's details to `any`; here the details and errors are explicit sums, and
# every tool is bridged into AgentTool<ToolDetails, ToolError> without
# changing what the model sees. powershell, grep and ls are not registered yet.

type ToolName is Data:
  ReadTool{}
  BashTool{}
  EditTool{}
  WriteTool{}
  FindTool{}

def allToolNames() -> List<&2, ToolName>: [ReadTool{}, BashTool{}, EditTool{}, WriteTool{}]

def toolName(name: ToolName) -> String:
  match name:
    case ReadTool{}: "read"
    case BashTool{}: "bash"
    case EditTool{}: "edit"
    case WriteTool{}: "write"
    case FindTool{}: "find"

def parseToolName(text: String) -> Maybe<&2, ToolName>:
  match text:
    case "read": Some{ReadTool{}}
    case "bash": Some{BashTool{}}
    case "edit": Some{EditTool{}}
    case "write": Some{WriteTool{}}
    case "find": Some{FindTool{}}
    case _: None{}

type ToolDetails is Data:
  ReadDetails{value: Maybe<&2, Read.ReadToolDetails>}
  BashDetails{value: Maybe<&2, Bash.BashToolDetails>}
  EditDetails{value: Edit.EditToolDetails}
  WriteDetails{}
  FindDetails{value: Maybe<&2, Find.FindToolDetails>}

# Failure carries loop-level messages (validation, declaration, provider)
# that upstream raises as plain Errors alongside tool failures.
type ToolError is Data:
  ReadFailed{cause: Read.Error}
  BashFailed{cause: Bash.Error}
  EditFailed{cause: Edit.Error}
  WriteFailed{cause: Write.Error}
  FindFailed{cause: Find.Error}
  Failure{message: String}

def fileError(error: FS.Error) -> String:
  match error:
    case FS.System{_, message}: message
    case FS.InvalidPathEncoding{_}: "Invalid filename encoding"
    case FS.WriteAndClose{_, write, _, close}: write ++ "; close: " ++ close
    case FS.ReadAndClose{_, read, _, close}: read ++ "; close: " ++ close

def writeMessage(error: Write.Error) -> String:
  match error:
    case Write.Aborted{}: "Operation aborted"
    case Write.Operation{message}: message
    case Write.Filesystem{cause}: fileError(cause)
    case Write.InvalidPath{_}: "Invalid write path"
    case Write.InvalidArguments{}: "write expects string path and content"

def errorMessage(error: ToolError) -> String:
  match error:
    case ReadFailed{cause}: Read.errorMessage(cause)
    case BashFailed{cause}: Bash.errorMessage(cause)
    case EditFailed{cause}: Edit.errorMessage(cause)
    case WriteFailed{cause}: writeMessage(cause)
    case FindFailed{cause}: Find.errorMessage(cause)
    case Failure{message}: message

def failure(message: String) -> ToolError: Failure{message}

def Tool() -> Data: Agent.AgentTool<ToolDetails, ToolError>
def Input() -> Data: Agent.ToolExecutionInput<ToolDetails>
def Output() -> Data: Result<&2, &2, ToolError, Agent.AgentToolResult<ToolDetails>>
def Update() -> Data: Maybe<&2, Agent.AgentToolUpdateCallback(ToolDetails)>

# System prompt contributions
# ---------------------------

def promptSnippet(name: ToolName) -> String:
  match name:
    case ReadTool{}: "Read file contents"
    case BashTool{}: "Execute bash commands (ls, grep, find, etc.)"
    case EditTool{}: "Make precise file edits with exact text replacement, including multiple disjoint edits in one call"
    case WriteTool{}: "Create or overwrite files"
    case FindTool{}: "Find files by glob pattern (respects .gitignore)"

def promptGuidelines(name: ToolName) -> List<&2, String>:
  match name:
    case ReadTool{}: ["Use read to examine files instead of cat or sed."]
    case BashTool{}: ["You can inspect PI_* environment variables for current model and session details."]
    case EditTool{}: ["Use edit for precise changes (edits[].oldText must match exactly)", "When changing multiple separate locations in one file, use one edit call with multiple entries in edits[] instead of multiple edit calls", "Each edits[].oldText is matched against the original file, not after earlier edits are applied. Do not emit overlapping or nested edits. Merge nearby changes into one edit.", "Keep edits[].oldText as small as possible while still being unique in the file. Do not pad with large unchanged regions."]
    case WriteTool{}: ["Use write only for new files or complete rewrites."]
    case FindTool{}: Nil{}

# Bridges
# -------

# Streaming updates are forwarded into the loop wrapped in the details sum.
def bashUpdate(callback: Update(), value: Agent.AgentToolResult<Maybe<&2, Bash.BashToolDetails>>) -> IO(Unit):
  match callback value:
    case None{} _: IO.pure(Unit, Unit{})
    case Some{callback} Agent.AgentToolResult{content, details, usage, terminate}: C.call(Agent.AgentToolResult<ToolDetails>, Unit, callback, Agent.AgentToolResult{content, BashDetails{details}, usage, terminate})

def bashOutput(value: Bash.ToolResult()) -> Output():
  match value:
    case Fail{error}: Fail{BashFailed{error}}
    case Done{Agent.AgentToolResult{content, details, usage, terminate}}: Done{Agent.AgentToolResult{content, BashDetails{details}, usage, terminate}}

def invokeBash(callback: C.Callback<Agent.ToolExecutionInput<Maybe<&2, Bash.BashToolDetails>>, Bash.ToolResult()>, input: Input()) -> IO(Output()):
  match input:
    case Agent.ToolExecutionInput{id, params, signal, update}:
      do IO<Output()>:
        +bridge : Agent.AgentToolUpdateCallback(Maybe<&2, Bash.BashToolDetails>) <- C.create(~Update(), ~Agent.AgentToolResult<Maybe<&2, Bash.BashToolDetails>>, ~Unit, ~bashUpdate, update)
        result : Bash.ToolResult() <- C.call(Agent.ToolExecutionInput<Maybe<&2, Bash.BashToolDetails>>, Bash.ToolResult(), callback, Agent.ToolExecutionInput{id, params, signal, Some{bridge}})
        C.dispose(Agent.AgentToolResult<Maybe<&2, Bash.BashToolDetails>>, Unit, bridge)
        return bashOutput(result)

def readOutput(value: Read.ToolResult()) -> Output():
  match value:
    case Fail{error}: Fail{ReadFailed{error}}
    case Done{Agent.AgentToolResult{content, details, usage, terminate}}: Done{Agent.AgentToolResult{content, ReadDetails{details}, usage, terminate}}

def invokeRead(callback: C.Callback<Agent.ToolExecutionInput<Maybe<&2, Read.ReadToolDetails>>, Read.ToolResult()>, input: Input()) -> IO(Output()):
  match input:
    case Agent.ToolExecutionInput{id, params, signal, _}:
      do IO<Output()>:
        result : Read.ToolResult() <- C.call(Agent.ToolExecutionInput<Maybe<&2, Read.ReadToolDetails>>, Read.ToolResult(), callback, Agent.ToolExecutionInput{id, params, signal, None{}})
        return readOutput(result)

def findOutput(value: Find.ToolResult()) -> Output():
  match value:
    case Fail{error}: Fail{FindFailed{error}}
    case Done{Agent.AgentToolResult{content, details, usage, terminate}}: Done{Agent.AgentToolResult{content, FindDetails{details}, usage, terminate}}

def invokeFind(callback: C.Callback<Agent.ToolExecutionInput<Maybe<&2, Find.FindToolDetails>>, Find.ToolResult()>, input: Input()) -> IO(Output()):
  match input:
    case Agent.ToolExecutionInput{id, params, signal, _}:
      do IO<Output()>:
        result : Find.ToolResult() <- C.call(Agent.ToolExecutionInput<Maybe<&2, Find.FindToolDetails>>, Find.ToolResult(), callback, Agent.ToolExecutionInput{id, params, signal, None{}})
        return findOutput(result)

def editOutput(value: Edit.ToolResult()) -> Output():
  match value:
    case Fail{error}: Fail{EditFailed{error}}
    case Done{Agent.AgentToolResult{content, details, usage, terminate}}: Done{Agent.AgentToolResult{content, EditDetails{details}, usage, terminate}}

def invokeEdit(callback: C.Callback<Agent.ToolExecutionInput<Edit.EditToolDetails>, Edit.ToolResult()>, input: Input()) -> IO(Output()):
  match input:
    case Agent.ToolExecutionInput{id, params, signal, _}:
      do IO<Output()>:
        result : Edit.ToolResult() <- C.call(Agent.ToolExecutionInput<Edit.EditToolDetails>, Edit.ToolResult(), callback, Agent.ToolExecutionInput{id, params, signal, None{}})
        return editOutput(result)

def prepared(value: Edit.ResultOf(V.Value)) -> Result<&2, &2, ToolError, V.Value>:
  match value:
    case Fail{error}: Fail{EditFailed{error}}
    case Done{arguments}: Done{arguments}

def prepareEdit(callback: C.Callback<V.Value, Edit.ResultOf(V.Value)>, input: V.Value) -> IO(Result<&2, &2, ToolError, V.Value>):
  do IO<Result<&2, &2, ToolError, V.Value>>:
    result : Edit.ResultOf(V.Value) <- C.call(V.Value, Edit.ResultOf(V.Value), callback, input)
    return prepared(result)

def writeOutput(value: Write.ToolResult()) -> Output():
  match value:
    case Fail{error}: Fail{WriteFailed{error}}
    case Done{Agent.AgentToolResult{content, _, usage, terminate}}: Done{Agent.AgentToolResult{content, WriteDetails{}, usage, terminate}}

def invokeWrite(callback: C.Callback<Agent.ToolExecutionInput<Unit>, Write.ToolResult()>, input: Input()) -> IO(Output()):
  match input:
    case Agent.ToolExecutionInput{id, params, signal, _}:
      do IO<Output()>:
        result : Write.ToolResult() <- C.call(Agent.ToolExecutionInput<Unit>, Write.ToolResult(), callback, Agent.ToolExecutionInput{id, params, signal, None{}})
        return writeOutput(result)

# Owners
# ------

def Execute() -> Data: C.Callback<Input(), Output()>
def Prepare() -> Data: C.Callback<V.Value, Result<&2, &2, ToolError, V.Value>>

type Owned is Type:
  OwnedRead{owner: Read.ToolOwner}
  OwnedBash{owner: Bash.ToolOwner}
  OwnedEdit{owner: Edit.ToolOwner, prepare: Prepare()}
  OwnedWrite{owner: Write.ToolOwner}
  OwnedFind{owner: Find.ToolOwner}

# The bridged tool borrows the underlying tool's callbacks; dispose retires
# the bridges before the tool.
type ToolOwner is Type:
  ToolOwner{tool: Tool(), execute: Execute(), owned: Owned}

def borrowTool(owner: ToolOwner) -> ToolOwner & Tool():
  match owner:
    case ToolOwner{+tool, execute, owned}: (ToolOwner{tool, execute, owned}, tool)

def disposeOwned(owned: Owned) -> IO(Unit):
  match owned:
    case OwnedRead{owner}: Read.disposeTool(owner)
    case OwnedBash{owner}: Bash.disposeTool(owner)
    case OwnedEdit{owner, prepare}:
      do IO<Unit>:
        C.dispose(V.Value, Result<&2, &2, ToolError, V.Value>, prepare)
        Edit.disposeTool(owner)
    case OwnedWrite{owner}: Write.disposeTool(owner)
    case OwnedFind{owner}: Find.disposeTool(owner)

def disposeTool(owner: ToolOwner) -> IO(Unit):
  match owner:
    case ToolOwner{_, execute, owned}:
      do IO<Unit>:
        C.dispose(Input(), Output(), execute)
        disposeOwned(owned)

type ToolsOptions is Data:
  ToolsOptions{read: Maybe<&2, Read.ReadToolOptions>, bash: Maybe<&2, Bash.BashToolOptions>, edit: Maybe<&2, Edit.EditToolOptions>, write: Maybe<&2, Write.WriteToolOptions>, find: Maybe<&2, Find.FindToolOptions>}

def defaultOptions() -> ToolsOptions: ToolsOptions{None{}, None{}, None{}, None{}, None{}}

# What every tool constructor needs besides its own options: the resolved
# path environment, the working directory, pi's managed bin directory (fd, rg)
# and the shared file-mutation queue.
type Environment is Data:
  Environment{paths: Paths.Environment, cwd: String, binDir: String, queue: Queue.Queue}

def bridgedRead(pair: Read.ToolOwner & Agent.AgentTool<Maybe<&2, Read.ReadToolDetails>, Read.Error>) -> IO(ToolOwner):
  match pair:
    case (owner, Agent.AgentTool{name, description, parameters, sampling, label, _, callback, replay, mode}):
      do IO<ToolOwner>:
        +execute : Execute() <- C.create(~C.Callback<Agent.ToolExecutionInput<Maybe<&2, Read.ReadToolDetails>>, Read.ToolResult()>, ~Input(), ~Output(), ~invokeRead, callback)
        return ToolOwner{Agent.AgentTool{name, description, parameters, sampling, label, None{}, execute, replay, mode}, execute, OwnedRead{owner}}

def createReadTool(environment: Environment, options: Maybe<&2, Read.ReadToolOptions>) -> IO(ToolOwner):
  match environment:
    case Environment{paths, cwd, _, _}:
      do IO<ToolOwner>:
        owner : Read.ToolOwner <- Read.createReadTool(paths, cwd, Maybe.default(&2, Read.ReadToolOptions, options, Read.ReadToolOptions{None{}, None{}, None{}}))
        bridgedRead(Read.borrowTool(owner))

def bridgedFind(pair: Find.ToolOwner & Agent.AgentTool<Maybe<&2, Find.FindToolDetails>, Find.Error>) -> IO(ToolOwner):
  match pair:
    case (owner, Agent.AgentTool{name, description, parameters, sampling, label, _, callback, replay, mode}):
      do IO<ToolOwner>:
        +execute : Execute() <- C.create(~C.Callback<Agent.ToolExecutionInput<Maybe<&2, Find.FindToolDetails>>, Find.ToolResult()>, ~Input(), ~Output(), ~invokeFind, callback)
        return ToolOwner{Agent.AgentTool{name, description, parameters, sampling, label, None{}, execute, replay, mode}, execute, OwnedFind{owner}}

def createFindTool(environment: Environment, options: Maybe<&2, Find.FindToolOptions>) -> IO(ToolOwner):
  match environment:
    case Environment{paths, cwd, _, _}:
      do IO<ToolOwner>:
        owner : Find.ToolOwner <- Find.createFindTool(paths, cwd, Maybe.default(&2, Find.FindToolOptions, options, Find.FindToolOptions{None{}}))
        bridgedFind(Find.borrowTool(owner))

def bridgedBash(pair: Bash.ToolOwner & Agent.AgentTool<Maybe<&2, Bash.BashToolDetails>, Bash.Error>) -> IO(ToolOwner):
  match pair:
    case (owner, Agent.AgentTool{name, description, parameters, sampling, label, _, callback, replay, mode}):
      do IO<ToolOwner>:
        +execute : Execute() <- C.create(~C.Callback<Agent.ToolExecutionInput<Maybe<&2, Bash.BashToolDetails>>, Bash.ToolResult()>, ~Input(), ~Output(), ~invokeBash, callback)
        return ToolOwner{Agent.AgentTool{name, description, parameters, sampling, label, None{}, execute, replay, mode}, execute, OwnedBash{owner}}

def createBashTool(environment: Environment, options: Maybe<&2, Bash.BashToolOptions>) -> IO(ToolOwner):
  match environment:
    case Environment{_, cwd, binDir, _}:
      do IO<ToolOwner>:
        owner : Bash.ToolOwner <- Bash.createBashTool(binDir, cwd, Maybe.default(&2, Bash.BashToolOptions, options, Bash.BashToolOptions{None{}, None{}, None{}, None{}, None{}}))
        bridgedBash(Bash.borrowTool(owner))

def bridgedPrepare(callback: Maybe<&2, C.Callback<V.Value, Edit.ResultOf(V.Value)>>) -> IO(Prepare()):
  match callback:
    case None{}: C.create(~Unit, ~V.Value, ~Result<&2, &2, ToolError, V.Value>, ~(unused => input => IO.pure(Result<&2, &2, ToolError, V.Value>, Done{input})), Unit{})
    case Some{callback}: C.create(~C.Callback<V.Value, Edit.ResultOf(V.Value)>, ~V.Value, ~Result<&2, &2, ToolError, V.Value>, ~prepareEdit, callback)

def bridgedEdit(pair: Edit.ToolOwner & Agent.AgentTool<Edit.EditToolDetails, Edit.Error>) -> IO(ToolOwner):
  match pair:
    case (owner, Agent.AgentTool{name, description, parameters, sampling, label, prepare, callback, replay, mode}):
      do IO<ToolOwner>:
        +execute : Execute() <- C.create(~C.Callback<Agent.ToolExecutionInput<Edit.EditToolDetails>, Edit.ToolResult()>, ~Input(), ~Output(), ~invokeEdit, callback)
        +prepared : Prepare() <- bridgedPrepare(prepare)
        return ToolOwner{Agent.AgentTool{name, description, parameters, sampling, label, Some{prepared}, execute, replay, mode}, execute, OwnedEdit{owner, prepared}}

def createEditTool(environment: Environment, options: Maybe<&2, Edit.EditToolOptions>) -> IO(ToolOwner):
  match environment:
    case Environment{paths, cwd, _, queue}:
      do IO<ToolOwner>:
        owner : Edit.ToolOwner <- Edit.createEditTool(paths, queue, cwd, Maybe.default(&2, Edit.EditToolOptions, options, Edit.EditToolOptions{None{}}))
        bridgedEdit(Edit.borrowTool(owner))

def bridgedWrite(pair: Write.ToolOwner & Agent.AgentTool<Unit, Write.Error>) -> IO(ToolOwner):
  match pair:
    case (owner, Agent.AgentTool{name, description, parameters, sampling, label, _, callback, replay, mode}):
      do IO<ToolOwner>:
        +execute : Execute() <- C.create(~C.Callback<Agent.ToolExecutionInput<Unit>, Write.ToolResult()>, ~Input(), ~Output(), ~invokeWrite, callback)
        return ToolOwner{Agent.AgentTool{name, description, parameters, sampling, label, None{}, execute, replay, mode}, execute, OwnedWrite{owner}}

def createWriteTool(environment: Environment, options: Maybe<&2, Write.WriteToolOptions>) -> IO(ToolOwner):
  match environment:
    case Environment{paths, cwd, _, queue}:
      do IO<ToolOwner>:
        owner : Write.ToolOwner <- Write.createWriteTool(paths, queue, cwd, Maybe.default(&2, Write.WriteToolOptions, options, Write.WriteToolOptions{None{}}))
        bridgedWrite(Write.borrowTool(owner))

def createTool(name: ToolName, environment: Environment, options: ToolsOptions) -> IO(ToolOwner):
  match name options:
    case ReadTool{} ToolsOptions{read, _, _, _, _}: createReadTool(environment, read)
    case BashTool{} ToolsOptions{_, bash, _, _, _}: createBashTool(environment, bash)
    case EditTool{} ToolsOptions{_, _, edit, _, _}: createEditTool(environment, edit)
    case WriteTool{} ToolsOptions{_, _, _, write, _}: createWriteTool(environment, write)
    case FindTool{} ToolsOptions{_, _, _, _, find}: createFindTool(environment, find)

def createTools(names: List<&2, ToolName>, +environment: Environment, +options: ToolsOptions) -> IO(List<&1, ToolOwner>):
  match names:
    case Nil{}: IO.pure(List<&1, ToolOwner>, Nil{})
    case name <> rest:
      do IO<List<&1, ToolOwner>>:
        owner : ToolOwner <- createTool(name, environment, options)
        others : List<&1, ToolOwner> <- createTools(rest, environment, options)
        return owner <> others

# read, bash, edit, write: the default tool set.
def createCodingTools(environment: Environment, options: ToolsOptions) -> IO(List<&1, ToolOwner>):
  createTools(allToolNames(), environment, options)

def borrowedTools(first: ToolOwner & Tool(), others: List<&1, ToolOwner> & List<&2, Tool()>) -> List<&1, ToolOwner> & List<&2, Tool()>:
  match first others:
    case Tuple{owner, tool} Tuple{owners, tools}: (owner <> owners, tool <> tools)

def borrowTools(owners: List<&1, ToolOwner>) -> List<&1, ToolOwner> & List<&2, Tool()>:
  match owners:
    case Nil{}: (Nil{}, Nil{})
    case owner <> rest: borrowedTools(borrowTool(owner), borrowTools(rest))

def disposeTools(owners: List<&1, ToolOwner>) -> IO(Unit):
  match owners:
    case Nil{}: IO.pure(Unit, Unit{})
    case owner <> rest:
      do IO<Unit>:
        disposeTool(owner)
        disposeTools(rest)
