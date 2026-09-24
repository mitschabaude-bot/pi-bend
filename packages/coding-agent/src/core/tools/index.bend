import Base
import ../../../../ai/src/utils/message-json.bend as Json
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
import ./ls.bend as Ls
import ../../../../runtime/src/collation.bend as Collation
import ./grep.bend as Grep
import ../../utils/tools-manager.bend as Manager
import ./truncate.bend as Truncate
import ./file-mutation-queue.bend as Queue
import ../extensions/context.bend as Ctx

# The public coding tools behind one agent-tool type. Upstream erases each
# tool's details to `any`; here the details and errors are explicit sums, and
# every tool is bridged into AgentTool<ToolDetails, ToolError> without
# changing what the model sees. powershell and ls are not registered yet.

type ToolName is Data:
  ReadTool{}
  BashTool{}
  EditTool{}
  WriteTool{}
  FindTool{}
  GrepTool{}
  LsTool{}

def allToolNames() -> List<&2, ToolName>: [ReadTool{}, BashTool{}, EditTool{}, WriteTool{}]

def toolName(name: ToolName) -> String:
  match name:
    case ReadTool{}: "read"
    case BashTool{}: "bash"
    case EditTool{}: "edit"
    case WriteTool{}: "write"
    case FindTool{}: "find"
    case GrepTool{}: "grep"
    case LsTool{}: "ls"

def parseToolName(text: String) -> Maybe<&2, ToolName>:
  match text:
    case "read": Some{ReadTool{}}
    case "bash": Some{BashTool{}}
    case "edit": Some{EditTool{}}
    case "write": Some{WriteTool{}}
    case "find": Some{FindTool{}}
    case "grep": Some{GrepTool{}}
    case "ls": Some{LsTool{}}
    case _: None{}

# RawDetails holds tool details restored from a session file: upstream stores
# them untyped, and a stored value is kept as JSON rather than guessed at.
type ToolDetails is Data:
  ReadDetails{value: Maybe<&2, Read.ReadToolDetails>}
  BashDetails{value: Maybe<&2, Bash.BashToolDetails>}
  EditDetails{value: Edit.EditToolDetails}
  WriteDetails{}
  FindDetails{value: Maybe<&2, Find.FindToolDetails>}
  GrepDetails{value: Maybe<&2, Grep.GrepToolDetails>}
  LsDetails{value: Maybe<&2, Ls.LsToolDetails>}
  RawDetails{value: V.Value}

# Failure carries loop-level messages (validation, declaration, provider)
# that upstream raises as plain Errors alongside tool failures.
type ToolError is Data:
  ReadFailed{cause: Read.Error}
  BashFailed{cause: Bash.Error}
  EditFailed{cause: Edit.Error}
  WriteFailed{cause: Write.Error}
  FindFailed{cause: Find.Error}
  GrepFailed{cause: Grep.Error}
  LsFailed{cause: Ls.Error}
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
    case GrepFailed{cause}: Grep.errorMessage(cause)
    case LsFailed{cause}: Ls.errorMessage(cause)
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
    case GrepTool{}: Grep.promptSnippet()
    case LsTool{}: "List directory contents"

def promptGuidelines(name: ToolName) -> List<&2, String>:
  match name:
    case ReadTool{}: ["Use read to examine files instead of cat or sed."]
    case BashTool{}: ["You can inspect PI_* environment variables for current model and session details."]
    case EditTool{}: ["Use edit for precise changes (edits[].oldText must match exactly)", "When changing multiple separate locations in one file, use one edit call with multiple entries in edits[] instead of multiple edit calls", "Each edits[].oldText is matched against the original file, not after earlier edits are applied. Do not emit overlapping or nested edits. Merge nearby changes into one edit.", "Keep edits[].oldText as small as possible while still being unique in the file. Do not pad with large unchanged regions."]
    case WriteTool{}: ["Use write only for new files or complete rewrites."]
    case FindTool{}: Nil{}
    case GrepTool{}: Nil{}
    case LsTool{}: Nil{}

# Bridges
# -------

# A tool's result lifted into the registry's details and error sums.
def lifted(~D: Data, ~E: Data, ~details: D -> ToolDetails, ~failed: E -> ToolError, value: Result<&2, &2, E, Agent.AgentToolResult<D>>) -> Output():
  match value:
    case Fail{error}: Fail{failed(error)}
    case Done{Agent.AgentToolResult{content, own, usage, terminate}}: Done{Agent.AgentToolResult{content, details(own), usage, terminate}}

# Tools without streaming updates run with the loop's id, arguments and signal.
def invokeLifted(~D: Data, ~E: Data, ~details: D -> ToolDetails, ~failed: E -> ToolError, callback: C.Callback<Agent.ToolExecutionInput<D>, Result<&2, &2, E, Agent.AgentToolResult<D>>>, input: Input()) -> IO(Output()):
  match input:
    case Agent.ToolExecutionInput{id, params, signal, _}:
      do IO<Output()>:
        result : Result<&2, &2, E, Agent.AgentToolResult<D>> <- C.call(Agent.ToolExecutionInput<D>, Result<&2, &2, E, Agent.AgentToolResult<D>>, callback, Agent.ToolExecutionInput{id, params, signal, None{}})
        return lifted(~D, ~E, ~details, ~failed, result)

def readDetails(value: Maybe<&2, Read.ReadToolDetails>) -> ToolDetails: ReadDetails{value}
def readFailed(error: Read.Error) -> ToolError: ReadFailed{error}
def bashDetails(value: Maybe<&2, Bash.BashToolDetails>) -> ToolDetails: BashDetails{value}
def bashFailed(error: Bash.Error) -> ToolError: BashFailed{error}
def editDetails(value: Edit.EditToolDetails) -> ToolDetails: EditDetails{value}
def editFailed(error: Edit.Error) -> ToolError: EditFailed{error}
def writeDetails(value: Unit) -> ToolDetails: WriteDetails{}
def writeFailed(error: Write.Error) -> ToolError: WriteFailed{error}
def findDetails(value: Maybe<&2, Find.FindToolDetails>) -> ToolDetails: FindDetails{value}
def lsDetails(value: Maybe<&2, Ls.LsToolDetails>) -> ToolDetails: LsDetails{value}
def lsFailed(error: Ls.Error) -> ToolError: LsFailed{error}
def findFailed(error: Find.Error) -> ToolError: FindFailed{error}
def grepDetails(value: Maybe<&2, Grep.GrepToolDetails>) -> ToolDetails: GrepDetails{value}
def grepFailed(error: Grep.Error) -> ToolError: GrepFailed{error}

# Streaming updates are forwarded into the loop wrapped in the details sum.
def bashUpdate(callback: Update(), value: Agent.AgentToolResult<Maybe<&2, Bash.BashToolDetails>>) -> IO(Unit):
  match callback value:
    case None{} _: IO.pure(Unit, Unit{})
    case Some{callback} Agent.AgentToolResult{content, details, usage, terminate}: C.call(Agent.AgentToolResult<ToolDetails>, Unit, callback, Agent.AgentToolResult{content, BashDetails{details}, usage, terminate})

def invokeBash(callback: C.Callback<Agent.ToolExecutionInput<Maybe<&2, Bash.BashToolDetails>>, Bash.ToolResult()>, input: Input()) -> IO(Output()):
  match input:
    case Agent.ToolExecutionInput{id, params, signal, update}:
      do IO<Output()>:
        +bridge : Agent.AgentToolUpdateCallback(Maybe<&2, Bash.BashToolDetails>) <- C.create(~Update(), ~Agent.AgentToolResult<Maybe<&2, Bash.BashToolDetails>>, ~Unit, ~bashUpdate, update)
        result : Bash.ToolResult() <- C.call(Agent.ToolExecutionInput<Maybe<&2, Bash.BashToolDetails>>, Bash.ToolResult(), callback, Agent.ToolExecutionInput{id, params, signal, Some{bridge}})
        C.dispose(Agent.AgentToolResult<Maybe<&2, Bash.BashToolDetails>>, Unit, bridge)
        return lifted(~Maybe<&2, Bash.BashToolDetails>, ~Bash.Error, ~bashDetails, ~bashFailed, result)

def prepared(value: Edit.ResultOf(V.Value)) -> Result<&2, &2, ToolError, V.Value>:
  match value:
    case Fail{error}: Fail{EditFailed{error}}
    case Done{arguments}: Done{arguments}

def prepareEdit(callback: C.Callback<V.Value, Edit.ResultOf(V.Value)>, input: V.Value) -> IO(Result<&2, &2, ToolError, V.Value>):
  do IO<Result<&2, &2, ToolError, V.Value>>:
    result : Edit.ResultOf(V.Value) <- C.call(V.Value, Edit.ResultOf(V.Value), callback, input)
    return prepared(result)

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
  OwnedGrep{owner: Grep.ToolOwner}
  OwnedLs{owner: Ls.ToolOwner}

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
    case OwnedGrep{owner}: Grep.disposeTool(owner)
    case OwnedLs{owner}: Ls.disposeTool(owner)

def disposeTool(owner: ToolOwner) -> IO(Unit):
  match owner:
    case ToolOwner{_, execute, owned}:
      do IO<Unit>:
        C.dispose(Input(), Output(), execute)
        disposeOwned(owned)

type ToolsOptions is Data:
  ToolsOptions{read: Maybe<&2, Read.ReadToolOptions>, bash: Maybe<&2, Bash.BashToolOptions>, edit: Maybe<&2, Edit.EditToolOptions>, write: Maybe<&2, Write.WriteToolOptions>, find: Maybe<&2, Find.FindToolOptions>, grep: Maybe<&2, Grep.GrepToolOptions>, ls: Maybe<&2, Ls.LsToolOptions>}

def defaultOptions() -> ToolsOptions: ToolsOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}}

# What every tool constructor needs besides its own options: the resolved
# path environment, the working directory, the manager of pi's bin directory
# (fd, rg) and the shared file-mutation queue.
type Environment is Data:
  Environment{paths: Paths.Environment, cwd: String, tools: Manager.ToolsManager, queue: Queue.Queue, data: String, context: Ctx.ContextSource()}

# The bridged tool keeps the tool's metadata and runs through the registry's
# execution callback; tools without argument preparation share it.
def bridged(~D: Data, ~E: Data, ~details: D -> ToolDetails, ~failed: E -> ToolError, owned: Owned, tool: Agent.AgentTool<D, E>) -> IO(ToolOwner):
  match tool:
    case Agent.AgentTool{name, description, parameters, sampling, label, _, callback, replay, mode}:
      do IO<ToolOwner>:
        +execute : Execute() <- C.create(~C.Callback<Agent.ToolExecutionInput<D>, Result<&2, &2, E, Agent.AgentToolResult<D>>>, ~Input(), ~Output(), ~invokeLifted(~D, ~E, ~details, ~failed), callback)
        return ToolOwner{Agent.AgentTool{name, description, parameters, sampling, label, None{}, execute, replay, mode}, execute, owned}

def bridgedRead(pair: Read.ToolOwner & Agent.AgentTool<Maybe<&2, Read.ReadToolDetails>, Read.Error>) -> IO(ToolOwner):
  match pair:
    case (owner, tool): bridged(~Maybe<&2, Read.ReadToolDetails>, ~Read.Error, ~readDetails, ~readFailed, OwnedRead{owner}, tool)

def createReadTool(environment: Environment, options: Maybe<&2, Read.ReadToolOptions>) -> IO(ToolOwner):
  match environment:
    case Environment{paths, cwd, _, _, _, context}:
      do IO<ToolOwner>:
        owner : Read.ToolOwner <- Read.createReadTool(paths, cwd, Maybe.default(&2, Read.ReadToolOptions, options, Read.ReadToolOptions{None{}, None{}, None{}}), context)
        bridgedRead(Read.borrowTool(owner))

def bridgedFind(pair: Find.ToolOwner & Agent.AgentTool<Maybe<&2, Find.FindToolDetails>, Find.Error>) -> IO(ToolOwner):
  match pair:
    case (owner, tool): bridged(~Maybe<&2, Find.FindToolDetails>, ~Find.Error, ~findDetails, ~findFailed, OwnedFind{owner}, tool)

def createFindTool(environment: Environment, options: Maybe<&2, Find.FindToolOptions>) -> IO(ToolOwner):
  match environment:
    case Environment{paths, cwd, tools, _, _, context}:
      do IO<ToolOwner>:
        owner : Find.ToolOwner <- Find.createFindTool(paths, tools, cwd, Maybe.default(&2, Find.FindToolOptions, options, Find.FindToolOptions{None{}}), context)
        bridgedFind(Find.borrowTool(owner))

def bridgedGrep(pair: Grep.ToolOwner & Agent.AgentTool<Maybe<&2, Grep.GrepToolDetails>, Grep.Error>) -> IO(ToolOwner):
  match pair:
    case (owner, tool): bridged(~Maybe<&2, Grep.GrepToolDetails>, ~Grep.Error, ~grepDetails, ~grepFailed, OwnedGrep{owner}, tool)

def createGrepTool(environment: Environment, options: Maybe<&2, Grep.GrepToolOptions>) -> IO(ToolOwner):
  match environment:
    case Environment{paths, cwd, tools, _, _, context}:
      do IO<ToolOwner>:
        owner : Grep.ToolOwner <- Grep.createGrepTool(paths, tools, cwd, Maybe.default(&2, Grep.GrepToolOptions, options, Grep.GrepToolOptions{None{}}), context)
        bridgedGrep(Grep.borrowTool(owner))

def bridgedBash(pair: Bash.ToolOwner & Agent.AgentTool<Maybe<&2, Bash.BashToolDetails>, Bash.Error>) -> IO(ToolOwner):
  match pair:
    case (owner, Agent.AgentTool{name, description, parameters, sampling, label, _, callback, replay, mode}):
      do IO<ToolOwner>:
        +execute : Execute() <- C.create(~C.Callback<Agent.ToolExecutionInput<Maybe<&2, Bash.BashToolDetails>>, Bash.ToolResult()>, ~Input(), ~Output(), ~invokeBash, callback)
        return ToolOwner{Agent.AgentTool{name, description, parameters, sampling, label, None{}, execute, replay, mode}, execute, OwnedBash{owner}}

def createBashTool(environment: Environment, options: Maybe<&2, Bash.BashToolOptions>) -> IO(ToolOwner):
  match environment:
    case Environment{_, cwd, Manager.ToolsManager{binDir, _, _}, _, _, context}:
      do IO<ToolOwner>:
        owner : Bash.ToolOwner <- Bash.createBashTool(binDir, cwd, Maybe.default(&2, Bash.BashToolOptions, options, Bash.BashToolOptions{None{}, None{}, None{}, None{}, None{}}), context)
        bridgedBash(Bash.borrowTool(owner))

def bridgedPrepare(callback: Maybe<&2, C.Callback<V.Value, Edit.ResultOf(V.Value)>>) -> IO(Prepare()):
  match callback:
    case None{}: C.create(~Unit, ~V.Value, ~Result<&2, &2, ToolError, V.Value>, ~(unused => input => IO.pure(Result<&2, &2, ToolError, V.Value>, Done{input})), Unit{})
    case Some{callback}: C.create(~C.Callback<V.Value, Edit.ResultOf(V.Value)>, ~V.Value, ~Result<&2, &2, ToolError, V.Value>, ~prepareEdit, callback)

def bridgedEdit(pair: Edit.ToolOwner & Agent.AgentTool<Edit.EditToolDetails, Edit.Error>) -> IO(ToolOwner):
  match pair:
    case (owner, Agent.AgentTool{name, description, parameters, sampling, label, prepare, callback, replay, mode}):
      do IO<ToolOwner>:
        +execute : Execute() <- C.create(~C.Callback<Agent.ToolExecutionInput<Edit.EditToolDetails>, Edit.ToolResult()>, ~Input(), ~Output(), ~invokeLifted(~Edit.EditToolDetails, ~Edit.Error, ~editDetails, ~editFailed), callback)
        +prepared : Prepare() <- bridgedPrepare(prepare)
        return ToolOwner{Agent.AgentTool{name, description, parameters, sampling, label, Some{prepared}, execute, replay, mode}, execute, OwnedEdit{owner, prepared}}

def createEditTool(environment: Environment, options: Maybe<&2, Edit.EditToolOptions>) -> IO(ToolOwner):
  match environment:
    case Environment{paths, cwd, _, queue, _, context}:
      do IO<ToolOwner>:
        owner : Edit.ToolOwner <- Edit.createEditTool(paths, queue, cwd, Maybe.default(&2, Edit.EditToolOptions, options, Edit.EditToolOptions{None{}}), context)
        bridgedEdit(Edit.borrowTool(owner))

def bridgedWrite(pair: Write.ToolOwner & Agent.AgentTool<Unit, Write.Error>) -> IO(ToolOwner):
  match pair:
    case (owner, tool): bridged(~Unit, ~Write.Error, ~writeDetails, ~writeFailed, OwnedWrite{owner}, tool)

def createWriteTool(environment: Environment, options: Maybe<&2, Write.WriteToolOptions>) -> IO(ToolOwner):
  match environment:
    case Environment{paths, cwd, _, queue, _, context}:
      do IO<ToolOwner>:
        owner : Write.ToolOwner <- Write.createWriteTool(paths, queue, cwd, Maybe.default(&2, Write.WriteToolOptions, options, Write.WriteToolOptions{None{}}), context)
        bridgedWrite(Write.borrowTool(owner))

def bridgedLs(pair: Ls.ToolOwner & Agent.AgentTool<Maybe<&2, Ls.LsToolDetails>, Ls.Error>) -> IO(ToolOwner):
  match pair:
    case (owner, tool): bridged(~Maybe<&2, Ls.LsToolDetails>, ~Ls.Error, ~lsDetails, ~lsFailed, OwnedLs{owner}, tool)

def codePointLe(left: String, right: String) -> Bool: String.is_le(left, right)

# The collation data ships with pi's runtime data; without it entries fall
# back to code point order.
def lsWithCollator(paths: Paths.Environment, cwd: String, options: Ls.LsToolOptions, context: Ctx.ContextSource(), loaded: Result<&2, &2, Collation.LoadError, Collation.Collator>) -> IO(Ls.ToolOwner):
  match loaded:
    case Done{collator}: Ls.createLsTool(collator, paths, cwd, options, context)
    case Fail{_}: Ls.createLsToolWithComparator(~codePointLe, paths, cwd, options, context)

def createLsTool(environment: Environment, options: Maybe<&2, Ls.LsToolOptions>) -> IO(ToolOwner):
  match environment:
    case Environment{paths, cwd, _, _, data, context}:
      do IO<ToolOwner>:
        loaded : Result<&2, &2, Collation.LoadError, Collation.Collator> <- Collation.load(data)
        owner : Ls.ToolOwner <- lsWithCollator(paths, cwd, Maybe.default(&2, Ls.LsToolOptions, options, Ls.LsToolOptions{None{}}), context, loaded)
        bridgedLs(Ls.borrowTool(owner))

def createTool(name: ToolName, environment: Environment, options: ToolsOptions) -> IO(ToolOwner):
  match name options:
    case ReadTool{} ToolsOptions{read, _, _, _, _, _, _}: createReadTool(environment, read)
    case BashTool{} ToolsOptions{_, bash, _, _, _, _, _}: createBashTool(environment, bash)
    case EditTool{} ToolsOptions{_, _, edit, _, _, _, _}: createEditTool(environment, edit)
    case WriteTool{} ToolsOptions{_, _, _, write, _, _, _}: createWriteTool(environment, write)
    case FindTool{} ToolsOptions{_, _, _, _, find, _, _}: createFindTool(environment, find)
    case GrepTool{} ToolsOptions{_, _, _, _, _, grep, _}: createGrepTool(environment, grep)
    case LsTool{} ToolsOptions{_, _, _, _, _, _, ls}: createLsTool(environment, ls)

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

# JSON details
# ------------
# The JSON shape of each tool's details, as the tools' plain objects render
# upstream; JSON events and session files share it.




def limitValue(value: Maybe<&2, Truncate.Limit>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{Truncate.Lines{}}: V.Text{"lines"}
    case Some{Truncate.Bytes{}}: V.Text{"bytes"}

def truncationValue(value: Truncate.TruncationResult) -> V.Value:
  match value:
    case Truncate.TruncationResult{content, truncated, truncatedBy, totalLines, totalBytes, outputLines, outputBytes, lastLinePartial, firstLineExceedsLimit, maxLines, maxBytes}:
      Json.object(Json.field("content", V.Text{content}, Json.field("truncated", V.Boolean{truncated}, Json.field("truncatedBy", limitValue(truncatedBy), Json.field("totalLines", Json.natural(totalLines), Json.field("totalBytes", Json.natural(totalBytes), Json.field("outputLines", Json.natural(outputLines), Json.field("outputBytes", Json.natural(outputBytes), Json.field("lastLinePartial", V.Boolean{lastLinePartial}, Json.field("firstLineExceedsLimit", V.Boolean{firstLineExceedsLimit}, Json.field("maxLines", Json.natural(maxLines), Json.field("maxBytes", Json.natural(maxBytes), Nil{}))))))))))))

def readDetailsValue(value: Maybe<&2, Read.ReadToolDetails>) -> V.Value:
  match value:
    case None{}: Json.object(Nil{})
    case Some{Read.ReadToolDetails{result}}: Json.object(Json.field("truncation", truncationValue(result), Nil{}))

def bashDetailsValue(value: Maybe<&2, Bash.BashToolDetails>) -> V.Value:
  match value:
    case None{}: Json.object(Nil{})
    case Some{Bash.BashToolDetails{result, fullOutputPath}}: Json.object(Json.optional("truncation", Maybe.map(&2, Truncate.TruncationResult, V.Value, truncationValue, result), Json.optional("fullOutputPath", Maybe.map(&2, String, V.Value, path => V.Text{path}, fullOutputPath), Nil{})))

def editDetailsValue(value: Edit.EditToolDetails) -> V.Value:
  match value:
    case Edit.EditToolDetails{diff, patch, firstChangedLine}: Json.object(Json.field("diff", V.Text{diff}, Json.field("patch", V.Text{patch}, Json.optional("firstChangedLine", Maybe.map(&2, Nat, V.Value, Json.natural, firstChangedLine), Nil{}))))

def findDetailsValue(value: Maybe<&2, Find.FindToolDetails>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{Find.FindToolDetails{cut, resultLimit}}: Json.object(Json.optional("truncation", Maybe.map(&2, Truncate.TruncationResult, V.Value, truncationValue, cut), Json.optional("resultLimitReached", Maybe.map(&2, Nat, V.Value, Json.natural, resultLimit), Nil{})))

def grepDetailsValue(value: Maybe<&2, Grep.GrepToolDetails>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{Grep.GrepToolDetails{cut, limit, lines}}: Json.object(Json.optional("truncation", Maybe.map(&2, Truncate.TruncationResult, V.Value, truncationValue, cut), Json.optional("matchLimitReached", Maybe.map(&2, Nat, V.Value, Json.natural, limit), Json.optional("linesTruncated", Maybe.map(&2, Bool, V.Value, flag => V.Boolean{flag}, lines), Nil{}))))

def lsDetailsValue(value: Maybe<&2, Ls.LsToolDetails>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{Ls.LsToolDetails{cut, reached}}: Json.object(Json.optional("truncation", Maybe.map(&2, Truncate.TruncationResult, V.Value, truncationValue, cut), Json.optional("entryLimitReached", Maybe.map(&2, Nat, V.Value, Json.natural, reached), Nil{})))

def detailsValue(value: ToolDetails) -> V.Value:
  match value:
    case ReadDetails{details}: readDetailsValue(details)
    case BashDetails{details}: bashDetailsValue(details)
    case EditDetails{details}: editDetailsValue(details)
    case WriteDetails{}: Json.object(Nil{})
    case FindDetails{details}: findDetailsValue(details)
    case GrepDetails{details}: grepDetailsValue(details)
    case LsDetails{details}: lsDetailsValue(details)
    case RawDetails{raw}: raw

