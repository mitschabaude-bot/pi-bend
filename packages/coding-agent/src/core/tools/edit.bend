import Base
import ./edit-diff.bend as Edits
import ./diff.bend as Diff
import ./file-mutation-queue.bend as Queue
import ../../utils/paths.bend as Paths
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/schema-value.bend as Value
import ../../../../runtime/src/record.bend as Record
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/utf8.bend as Utf8
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/abort.bend as Abort

type EditToolInput is Data:
  EditToolInput{path: String, edits: List<&2, Edits.Edit>}
type EditToolDetails is Data:
  EditToolDetails{diff: String, patch: String, firstChangedLine: Maybe<&2, Nat>}
type Error is Data:
  Filesystem{cause: FS.Error}
  Operation{message: String}
  Access{path: String, message: String}
  Matching{cause: Edits.Error, path: String, count: Nat}
  InvalidEncoding{cause: Utf8.Error}
  InvalidPath{cause: Paths.Error}
  InvalidArguments{}
  EmptyEdits{}
  Aborted{}

def ResultOf(-A: Data) -> Data: Result<&2, &2, Error, A>
def ToolResult() -> Data: ResultOf(Agent.AgentToolResult<EditToolDetails>)

type EditOperations is Data:
  EditOperations{readFile: Callback.Callback<String, ResultOf(List<&2, U32>)>, writeFile: Callback.Callback<(String & String), ResultOf(Unit)>, access: Callback.Callback<String, ResultOf(Unit)>}
type EditToolOptions is Data:
  EditToolOptions{operations: Maybe<&2, EditOperations>}
type Invocation is Data:
  Invocation{paths: Paths.Environment, cwd: String, queue: Queue.Queue, operations: EditOperations}
type ToolOwner is Type:
  ToolOwner{tool: Agent.AgentTool<EditToolDetails, Error>, ownedOperations: Maybe<&2, EditOperations>}

def filesystemMessage(cause: FS.Error) -> String:
  match cause:
    case FS.System{code, message}: "Error " ++ U32.show(code) ++ ": " ++ message
    case FS.InvalidPathEncoding{_}: "Invalid UTF-8 path"
    case FS.WriteAndClose{_, write, _, close}: write ++ "; close: " ++ close
    case FS.ReadAndClose{_, read, _, close}: read ++ "; close: " ++ close

def errorMessage(error: Error) -> String:
  match error:
    case Filesystem{cause}: filesystemMessage(cause)
    case Operation{message}: message
    case Access{path, message}: "Could not edit file: " ++ path ++ ". " ++ message ++ "."
    case Matching{cause, path, count}: Edits.errorMessage(cause, path, count)
    case InvalidEncoding{_}: "File contains invalid UTF-8"
    case InvalidPath{_}: "Invalid file path"
    case InvalidArguments{}: "Edit tool input is invalid. Expected a path and an array of text replacements."
    case EmptyEdits{}: "Edit tool input is invalid. edits must contain at least one replacement."
    case Aborted{}: "Operation aborted"

# Sequence typed failures without detaching an operation from its queue owner.
def continued(-A: Data, -B: Data, result: ResultOf(A), next: A -> IO(ResultOf(B))) -> IO(ResultOf(B)):
  match result:
    case Fail{error}: IO.pure(ResultOf(B), Fail{error})
    case Done{value}: next(value)

def then(-A: Data, -B: Data, action: IO(ResultOf(A)), next: A -> IO(ResultOf(B))) -> IO(ResultOf(B)):
  IO.bind(ResultOf(A), ResultOf(B), action, result => continued(A, B, result, next))

def filesystem(-A: Data, result: Result<&2, &2, FS.Error, A>) -> ResultOf(A):
  match result:
    case Fail{cause}: Fail{Filesystem{cause}}
    case Done{value}: Done{value}

def localRead(environment: Unit, path: String) -> IO(ResultOf(List<&2, U32>)):
  do IO<ResultOf(List<&2, U32>)>:
    result : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
    return filesystem(List<&2, U32>, result)

def localWrite(environment: Unit, input: String & String) -> IO(ResultOf(Unit)):
  match input:
    case (path, content):
      do IO<ResultOf(Unit)>:
        result : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(path, content)
        return filesystem(Unit, result)

def namedAccess(code: U32, message: String, name: Maybe<&2, String>) -> ResultOf(Unit):
  match name:
    case Some{name}: Fail{Operation{"Error code: " ++ name}}
    case None{}: Fail{Filesystem{FS.System{code, message}}}

def accessResult(result: Result<&1, &1, U32 & String, Unit>) -> IO(ResultOf(Unit)):
  match result:
    case Done{Unit{}}: IO.pure(ResultOf(Unit), Done{Unit{}})
    case Fail{(+code, message)}:
      do IO<ResultOf(Unit)>:
        name : Maybe<&2, String> <- System.error_name(code)
        return namedAccess(code, message, name)

def localAccess(environment: Unit, path: String) -> IO(ResultOf(Unit)):
  do IO<ResultOf(Unit)>:
    result : Result<&1, &1, U32 & String, Unit> <- File.access(path, 6)
    accessResult(result)

def defaultEditOperations() -> IO(EditOperations):
  do IO<EditOperations>:
    reader : Callback.Callback<String, ResultOf(List<&2, U32>)> <- Callback.create(~Unit, ~String, ~ResultOf(List<&2, U32>), ~localRead, Unit{})
    writer : Callback.Callback<(String & String), ResultOf(Unit)> <- Callback.create(~Unit, ~(String & String), ~ResultOf(Unit), ~localWrite, Unit{})
    access : Callback.Callback<String, ResultOf(Unit)> <- Callback.create(~Unit, ~String, ~ResultOf(Unit), ~localAccess, Unit{})
    return EditOperations{reader, writer, access}

def dispose(operations: EditOperations) -> IO(Unit):
  match operations:
    case EditOperations{reader, writer, access}:
      do IO<Unit>:
        Callback.dispose(String, ResultOf(List<&2, U32>), reader)
        Callback.dispose(String & String, ResultOf(Unit), writer)
        Callback.dispose(String, ResultOf(Unit), access)

def cancellation(aborted: Bool) -> ResultOf(Unit):
  match aborted:
    case True{}: Fail{Aborted{}}
    case False{}: Done{Unit{}}

def check(signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(ResultOf(Unit)):
  match signal:
    case None{}: IO.pure(ResultOf(Unit), Done{Unit{}})
    case Some{signal}:
      do IO<ResultOf(Unit)>:
        aborted : Bool <- Abort.aborted(Unit, signal)
        return cancellation(aborted)

def accessChecked(path: String, result: ResultOf(Unit), checked: ResultOf(Unit)) -> ResultOf(Unit):
  match result checked:
    case _ Fail{error}: Fail{error}
    case Fail{error} Done{Unit{}}: Fail{Access{path, errorMessage(error)}}
    case Done{Unit{}} Done{Unit{}}: Done{Unit{}}

# Upstream gives cancellation precedence over access failures, but not failed
# read/write operations. In-flight IO always settles before releasing the queue.
def accessible(callback: Callback.Callback<String, ResultOf(Unit)>, absolute: String, path: String, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(ResultOf(Unit)):
  do IO<ResultOf(Unit)>:
    result : ResultOf(Unit) <- Callback.call(String, ResultOf(Unit), callback, absolute)
    checked : ResultOf(Unit) <- check(signal)
    return accessChecked(path, result, checked)

type Prepared is Data:
  Prepared{original: String, updated: String, disk: String, count: Nat}

def applied(bom: String, ending: String, +path: String, +count: Nat, result: Result<&2, &2, Edits.Error, Edits.AppliedEditsResult>) -> ResultOf(Prepared):
  match result:
    case Fail{cause}: Fail{Matching{cause, path, count}}
    case Done{Edits.AppliedEditsResult{original, +updated}}: Done{Prepared{original, updated, bom ++ Edits.restoreLineEndings(updated, ending), count}}

def normalized(bom: String, +content: String, edits: List<&2, Edits.Edit>, path: String, count: Nat) -> ResultOf(Prepared):
  applied(bom, Edits.detectLineEnding(content), path, count, Edits.applyEditsToNormalizedContent(Edits.normalizeToLF(content), edits))

def withoutBOM(+content: String, edits: List<&2, Edits.Edit>, path: String, count: Nat) -> ResultOf(Prepared):
  match content:
    case SCon{Chr{65279}, rest}: normalized(SCon{Chr{65279}, SNil{}}, rest, edits, path, count)
    case _: normalized("", content, edits, path, count)

def prepareContent(edits: List<&2, Edits.Edit>, path: String, count: Nat, decoded: Result<&2, &2, Utf8.Error, String>) -> ResultOf(Prepared):
  match decoded:
    case Fail{cause}: Fail{InvalidEncoding{cause}}
    case Done{content}: withoutBOM(content, edits, path, count)

def resultDetails(path: String, count: Nat, patch: String, result: Diff.DiffResult) -> Agent.AgentToolResult<EditToolDetails>:
  match result:
    case Diff.DiffResult{diff, firstChangedLine}: Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{"Successfully replaced " ++ Nat.show(count) ++ " block(s) in " ++ path ++ ".", None{}}} <> Nil{}, EditToolDetails{diff, patch, firstChangedLine}, None{}, None{}}

def save(writer: Callback.Callback<(String & String), ResultOf(Unit)>, absolute: String, +path: String, +signal: Maybe<&2, Abort.AbortSignal<Unit>>, prepared: Prepared) -> IO(ToolResult()):
  match prepared:
    case Prepared{+original, +updated, disk, count}:
      then(Unit, Agent.AgentToolResult<EditToolDetails>, check(signal), _ =>
        then(Unit, Agent.AgentToolResult<EditToolDetails>, Callback.call(String & String, ResultOf(Unit), writer, (absolute, disk)), _ =>
          then(Unit, Agent.AgentToolResult<EditToolDetails>, check(signal), _ =>
            IO.pure(ToolResult(), Done{resultDetails(path, count, Diff.generateUnifiedPatch(path, original, updated, 4n), Diff.generateDiffString(original, updated, 4n))}))))

def edit(operations: EditOperations, +absolute: String, +path: String, +edits: List<&2, Edits.Edit>, +signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(ToolResult()):
  match operations:
    case EditOperations{reader, writer, access}:
      then(Unit, Agent.AgentToolResult<EditToolDetails>, check(signal), _ =>
        then(Unit, Agent.AgentToolResult<EditToolDetails>, accessible(access, absolute, path, signal), _ =>
          then(List<&2, U32>, Agent.AgentToolResult<EditToolDetails>, Callback.call(String, ResultOf(List<&2, U32>), reader, absolute), bytes =>
            then(Unit, Agent.AgentToolResult<EditToolDetails>, check(signal), _ =>
              continued(Prepared, Agent.AgentToolResult<EditToolDetails>, prepareContent(edits, path, List.length(&2, Edits.Edit, edits), Utf8.decodeWith(Utf8.Preserve{}, bytes)), prepared => save(writer, absolute, path, signal, prepared))))))

def queued(result: Result<&2, &1, FS.Error, ToolResult()>) -> ToolResult():
  match result:
    case Fail{cause}: Fail{Filesystem{cause}}
    case Done{value}: value

def execute(queue: Queue.Queue, operations: EditOperations, +absolute: String, path: String, edits: List<&2, Edits.Edit>, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(ToolResult()):
  do IO<ToolResult()>:
    result : Result<&2, &1, FS.Error, ToolResult()> <- Queue.withFileMutationQueue(ToolResult(), queue, absolute, _ => edit(operations, absolute, path, edits, signal))
    return queued(result)

def replacement(oldText: Maybe<&2, Value.Value>, newText: Maybe<&2, Value.Value>) -> ResultOf(Edits.Edit):
  match oldText newText:
    case Some{Value.Text{old}} Some{Value.Text{new}}: Done{Edits.Edit{old, new}}
    case _ _: Fail{InvalidArguments{}}

def parseEdit(value: Value.Value) -> ResultOf(Edits.Edit):
  match value:
    case Value.ObjectValue{+fields}: replacement(Record.get(Value.Value, fields, "oldText"), Record.get(Value.Value, fields, "newText"))
    case _: Fail{InvalidArguments{}}

def parsedEdits(result: ResultOf(List<&2, Edits.Edit>), first: ResultOf(Edits.Edit)) -> ResultOf(List<&2, Edits.Edit>):
  match result first:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{rest} Done{item}: Done{item <> rest}

def parseEdits(values: List<&2, Value.Value>) -> ResultOf(List<&2, Edits.Edit>):
  match values:
    case Nil{}: Done{Nil{}}
    case first <> rest: parsedEdits(parseEdits(rest), parseEdit(first))

def editsArgument(value: Maybe<&2, Value.Value>) -> ResultOf(List<&2, Edits.Edit>):
  match value:
    case None{}: Done{Nil{}}
    case Some{Value.ArrayValue{values}}: parseEdits(values)
    case _: Fail{InvalidArguments{}}

# Preserve the documented legacy pair, including appending it to a batch.
# Stringified arrays and other malformed shapes are deliberately rejected.
def legacy(edits: ResultOf(List<&2, Edits.Edit>), oldText: Maybe<&2, Value.Value>, newText: Maybe<&2, Value.Value>) -> ResultOf(List<&2, Edits.Edit>):
  match edits oldText newText:
    case Fail{error} _ _: Fail{error}
    case Done{edits} None{} None{}: Done{edits}
    case Done{edits} Some{Value.Text{old}} Some{Value.Text{new}}: Done{List.append(&2, Edits.Edit, edits, Edits.Edit{old, new} <> Nil{})}
    case _ _ _: Fail{InvalidArguments{}}

def input(path: Maybe<&2, Value.Value>, edits: ResultOf(List<&2, Edits.Edit>)) -> ResultOf(EditToolInput):
  match path edits:
    case _ Fail{error}: Fail{error}
    case Some{Value.Text{path}} Done{Nil{}}: Fail{EmptyEdits{}}
    case Some{Value.Text{path}} Done{edits}: Done{EditToolInput{path, edits}}
    case _ _: Fail{InvalidArguments{}}

def parseInput(value: Value.Value) -> ResultOf(EditToolInput):
  match value:
    case Value.ObjectValue{+fields}: input(Record.get(Value.Value, fields, "path"), legacy(editsArgument(Record.get(Value.Value, fields, "edits")), Record.get(Value.Value, fields, "oldText"), Record.get(Value.Value, fields, "newText")))
    case _: Fail{InvalidArguments{}}

def editValue(item: Edits.Edit) -> Value.Value:
  match item:
    case Edits.Edit{old, new}: Value.ObjectValue{Record.Record{Record.Property{"oldText", Value.Text{old}} <> Record.Property{"newText", Value.Text{new}} <> Nil{}}}

def editValues(edits: List<&2, Edits.Edit>) -> List<&2, Value.Value>:
  match edits:
    case Nil{}: Nil{}
    case item <> rest: editValue(item) <> editValues(rest)

def preparedArguments(fields: Record.Record<Value.Value>, parsed: ResultOf(EditToolInput)) -> ResultOf(Value.Value):
  match parsed:
    case Fail{error}: Fail{error}
    case Done{EditToolInput{_, edits}}: Done{Value.ObjectValue{Record.set(Value.Value, Record.remove(Value.Value, Record.remove(Value.Value, fields, "oldText"), "newText"), "edits", Value.ArrayValue{editValues(edits)})}}

def prepareArguments(environment: Unit, arguments: Value.Value) -> IO(ResultOf(Value.Value)):
  match arguments:
    case Value.ObjectValue{+fields}: IO.pure(ResultOf(Value.Value), preparedArguments(fields, parseInput(Value.ObjectValue{fields})))
    case _: IO.pure(ResultOf(Value.Value), Fail{InvalidArguments{}})

def resolved(environment: Invocation, path: String, edits: List<&2, Edits.Edit>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, result: Result<&2, &2, Paths.Error, String>) -> IO(ToolResult()):
  match environment result:
    case _ Fail{cause}: IO.pure(ToolResult(), Fail{InvalidPath{cause}})
    case Invocation{_, _, queue, operations} Done{absolute}: execute(queue, operations, absolute, path, edits, signal)

def invokeInput(+environment: Invocation, signal: Maybe<&2, Abort.AbortSignal<Unit>>, parsed: ResultOf(EditToolInput)) -> IO(ToolResult()):
  match environment parsed:
    case _ Fail{error}: IO.pure(ToolResult(), Fail{error})
    case Invocation{paths, cwd, _, _} Done{EditToolInput{+path, edits}}: resolved(environment, path, edits, signal, Paths.resolveToCwd(paths, path, cwd))

def invoke(environment: Invocation, request: Agent.ToolExecutionInput<EditToolDetails>) -> IO(ToolResult()):
  match request:
    case Agent.ToolExecutionInput{_, arguments, signal, _}: invokeInput(environment, signal, parseInput(arguments))

def stringParameter(description: String) -> Value.Value:
  Value.ObjectValue{Record.Record{Record.Property{"type", Value.Text{"string"}} <> Record.Property{"description", Value.Text{description}} <> Nil{}}}

def editSchema() -> Value.Value:
  Value.ObjectValue{Record.Record{
    Record.Property{"type", Value.Text{"object"}} <>
    Record.Property{"properties", Value.ObjectValue{Record.Record{
      Record.Property{"path", stringParameter("Path to the file to edit (relative or absolute)")} <>
      Record.Property{"edits", Value.ObjectValue{Record.Record{
        Record.Property{"type", Value.Text{"array"}} <>
        Record.Property{"description", Value.Text{"One or more targeted replacements. Each edit is matched against the original file, not incrementally. Do not include overlapping or nested edits. If two changes touch the same block or nearby lines, merge them into one edit instead."}} <>
        Record.Property{"items", Value.ObjectValue{Record.Record{
          Record.Property{"type", Value.Text{"object"}} <>
          Record.Property{"properties", Value.ObjectValue{Record.Record{
            Record.Property{"oldText", stringParameter("Exact text for one targeted replacement. It must be unique in the original file and must not overlap with any other edits[].oldText in the same call.")} <>
            Record.Property{"newText", stringParameter("Replacement text for this targeted edit.")} <> Nil{}}}} <>
          Record.Property{"required", Value.ArrayValue{Value.Text{"oldText"} <> Value.Text{"newText"} <> Nil{}}} <> Nil{}}}} <> Nil{}}}} <> Nil{}}}} <>
    Record.Property{"required", Value.ArrayValue{Value.Text{"path"} <> Value.Text{"edits"} <> Nil{}}} <> Nil{}}}

def created(environment: Invocation, owned: Maybe<&2, EditOperations>) -> IO(ToolOwner):
  do IO<ToolOwner>:
    prepare : Callback.Callback<Value.Value, ResultOf(Value.Value)> <- Callback.create(~Unit, ~Value.Value, ~ResultOf(Value.Value), ~prepareArguments, Unit{})
    callback : Callback.Callback<Agent.ToolExecutionInput<EditToolDetails>, ToolResult()> <- Callback.create(~Invocation, ~Agent.ToolExecutionInput<EditToolDetails>, ~ToolResult(), ~invoke, environment)
    return ToolOwner{Agent.AgentTool{"edit", "Edit a single file using exact text replacement. Every edits[].oldText must match a unique, non-overlapping region of the original file. If two changes affect the same block or nearby lines, merge them into one edit instead of emitting overlapping edits. Do not include large unchanged regions just to connect distant changes.", editSchema(), Some{Ai.SamplingConfigured{Ai.JsonSchemaSampling{Ai.Prefer{}}}}, "edit", Some{prepare}, callback, None{}, None{}}, owned}

# Explicit native runtime dependencies; injected callbacks remain caller-owned.
def createEditTool(environment: Paths.Environment, queue: Queue.Queue, cwd: String, options: EditToolOptions) -> IO(ToolOwner):
  match options:
    case EditToolOptions{Some{operations}}: created(Invocation{environment, cwd, queue, operations}, None{})
    case EditToolOptions{None{}}:
      do IO<ToolOwner>:
        +operations : EditOperations <- defaultEditOperations()
        created(Invocation{environment, cwd, queue, operations}, Some{operations})

def borrowTool(owner: ToolOwner) -> ToolOwner & Agent.AgentTool<EditToolDetails, Error>:
  match owner:
    case ToolOwner{+tool, operations}: (ToolOwner{tool, operations}, tool)

def disposeOwned(owned: Maybe<&2, EditOperations>) -> IO(Unit):
  match owned:
    case None{}: IO.pure(Unit, Unit{})
    case Some{operations}: dispose(operations)

def disposePrepare(callback: Maybe<&2, Callback.Callback<Value.Value, ResultOf(Value.Value)>>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit, Unit{})
    case Some{callback}: Callback.dispose(Value.Value, ResultOf(Value.Value), callback)

def disposeTool(owner: ToolOwner) -> IO(Unit):
  match owner:
    case ToolOwner{Agent.AgentTool{_, _, _, _, _, prepare, callback, _, _}, operations}:
      do IO<Unit>:
        Callback.dispose(Agent.ToolExecutionInput<EditToolDetails>, ToolResult(), callback)
        disposePrepare(prepare)
        disposeOwned(operations)
