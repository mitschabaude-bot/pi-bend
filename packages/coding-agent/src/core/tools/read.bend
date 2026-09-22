import Base
import ../../utils/paths.bend as Paths
import ../../utils/mime.bend as Mime
import ../../utils/image-process.bend as Images
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/schema-value.bend as Value
import ../../../../runtime/src/record.bend as Record
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/utf8.bend as Utf8
import ../../../../runtime/src/f64.bend as Number
import ../../../../runtime/src/unicode.bend as Unicode
import ../../../../runtime/src/url.bend as URL
import ../../../../runtime/src/idna.bend as IDNA
import ./truncate.bend as Truncate
import ../../../../runtime/src/string.bend as Strings

type ReadToolInput is Data:
  ReadToolInput{path: String, offset: Maybe<&2, Nat>, limit: Maybe<&2, Nat>}

type ReadToolDetails is Data:
  ReadToolDetails{truncation: Truncate.TruncationResult}

type TextResult is Data:
  TextResult{text: String, details: Maybe<&2, ReadToolDetails>}

type Error is Data:
  OffsetBeyondEnd{offset: Nat, totalLines: Nat}
  Filesystem{cause: FS.Error}
  Operation{message: String}
  InvalidEncoding{cause: Utf8.Error}
  InvalidPath{cause: Paths.Error}
  InvalidArguments{}
  Aborted{}

def filesystemMessage(cause: FS.Error) -> String:
  match cause:
    case FS.System{code,message}: "Error " ++ U32.show(code) ++ ": " ++ message
    case FS.InvalidPathEncoding{_}: "Invalid UTF-8 path"
    case FS.ReadAndClose{_,read,_,close}: read ++ "; close: " ++ close
    case FS.WriteAndClose{_,write,_,close}: write ++ "; close: " ++ close

def errorMessage(error: Error) -> String:
  match error:
    case OffsetBeyondEnd{offset, total}:
      "Offset " ++ Nat.show(offset) ++ " is beyond end of file (" ++ Nat.show(total) ++ " lines total)"
    case Filesystem{cause}: filesystemMessage(cause)
    case Operation{message}: message
    case InvalidEncoding{_}: "File contains invalid UTF-8"
    case InvalidPath{_}: "Invalid file path"
    case InvalidArguments{}: "Read tool input is invalid. Expected a path and optional natural offset/limit."
    case Aborted{}: "Operation aborted"

def continuation(cause: Maybe<&2, Truncate.Limit>) -> String:
  match cause:
    case Some{Truncate.Lines{}}: ""
    case _: " (" ++ Truncate.formatSize(Truncate.DEFAULT_MAX_BYTES()) ++ " limit)"

def remainingNotice(+text: String, start: Nat, +total: Nat, limited: Maybe<&2, Nat>) -> TextResult:
  match limited:
    case None{}: TextResult{text, None{}}
    case Some{count}:
      +end = start + count
      Bool.pick(Unit -> TextResult, Nat.is_lt(end, total),
        unused => TextResult{text ++ "\n\n[" ++ Nat.show(total - end) ++ " more lines in file. Use offset=" ++ Nat.show(1n + end) ++ " to continue.]", None{}},
        unused => TextResult{text, None{}})(Unit{})

def render(path: String, +start: Nat, total: Nat, firstLineBytes: Nat, limited: Maybe<&2, Nat>, +truncation: Truncate.TruncationResult) -> TextResult:
  match truncation:
    case Truncate.TruncationResult{_, _, _, _, _, _, _, _, True{}, _, _}:
      +line = Nat.show(1n + start)
      +maximum = Truncate.DEFAULT_MAX_BYTES()
      TextResult{"[Line " ++ line ++ " is " ++ Truncate.formatSize(firstLineBytes) ++ ", exceeds " ++ Truncate.formatSize(maximum) ++ " limit. Use bash: sed -n '" ++ line ++ "p' -- " ++ Strings.quoteShell(path) ++ " | head -c " ++ Nat.show(maximum) ++ "]", Some{ReadToolDetails{truncation}}}
    case Truncate.TruncationResult{content, True{}, cause, _, _, outputLines, _, _, False{}, _, _}:
      +end = start + outputLines
      TextResult{content ++ "\n\n[Showing lines " ++ Nat.show(1n + start) ++ "-" ++ Nat.show(end) ++ " of " ++ Nat.show(total) ++ continuation(cause) ++ ". Use offset=" ++ Nat.show(1n + end) ++ " to continue.]", Some{ReadToolDetails{truncation}}}
    case Truncate.TruncationResult{content, False{}, _, _, _, _, _, _, False{}, _, _}:
      remainingNotice(content, start, total, limited)

def firstLineBytes(lines: List<&2, String>) -> Nat:
  match lines:
    case Nil{}: 0n
    case first <> _: Truncate.byteLength(first)

def selected(path: String, +start: Nat, +total: Nat, +remaining: List<&2, String>, limit: Maybe<&2, Nat>) -> TextResult:
  match limit:
    case None{}:
      render(path, start, total, firstLineBytes(remaining), None{}, Truncate.truncateHead(String.join(remaining, "\n"), Truncate.TruncationOptions{None{}, None{}}))
    case Some{+count}:
      render(path, start, total, firstLineBytes(remaining), Some{Nat.min(count, total - start)}, Truncate.truncateHead(String.join(List.take(&2, String, remaining, count), "\n"), Truncate.TruncationOptions{None{}, None{}}))

# Offset and limit are natural line counts. An absent or zero offset starts at
# the first line, as in Pi. The public argument decoder must reject fractions
# and negative counts before reaching this pure operation.
def readText(input: ReadToolInput, content: String) -> Result<&2, &2, Error, TextResult>:
  match input:
    case ReadToolInput{path, offset, limit}:
      +lines = Strings.split(content, '\n')
      +total = Truncate.countLines(lines, 0n)
      +offset = Maybe.default(&2, Nat, offset, 1n)
      +start = offset - 1n
      Bool.pick(Unit -> Result<&2, &2, Error, TextResult>, Nat.is_ge(start, total),
        unused => Fail{OffsetBeyondEnd{offset, total}},
        unused => Done{selected(path, start, total, List.drop(&2, String, lines, start), limit)})(Unit{})

# Local operations are owned by the factory. Injected operations and image
# processors remain borrowed; callers retire them only after executions settle.
def ResultOf(-A: Data) -> Data: Result<&2,&2,Error,A>
def ToolResult() -> Data: ResultOf(Agent.AgentToolResult<Maybe<&2,ReadToolDetails>>)

type ReadOperations is Data:
  ReadOperations{readFile: Callback.Callback<String,ResultOf(List<&2,U32>)>, access: Callback.Callback<String,ResultOf(Unit)>, detectImageMimeType: Maybe<&2,Callback.Callback<String,ResultOf(Maybe<&2,String>)>>}

type ImageInput is Data:
  ImageInput{bytes: List<&2,U32>, mimeType: String, autoResizeImages: Bool}

type ProcessedImage is Data:
  Processed{data: String, mimeType: String, hints: List<&2,String>}
  Unsupported{message: String}

type ReadToolOptions is Data:
  ReadToolOptions{autoResizeImages: Maybe<&2,Bool>, operations: Maybe<&2,ReadOperations>, imageProcessor: Maybe<&2,Callback.Callback<ImageInput,ResultOf(ProcessedImage)>>}

type ReadContext is Data:
  ReadContext{cwd: Maybe<&2,String>, supportsImages: Maybe<&2,Bool>}

type Invocation is Data:
  Invocation{paths: Paths.Environment, cwd: String, operations: ReadOperations, autoResizeImages: Bool, imageProcessor: Maybe<&2,Callback.Callback<ImageInput,ResultOf(ProcessedImage)>>}

type ToolOwner is Type:
  ToolOwner{tool: Agent.AgentTool<Maybe<&2,ReadToolDetails>,Error>, ownedOperations: Maybe<&2,ReadOperations>}

def continued(-A: Data, -B: Data, result: ResultOf(A), next: A -> IO(ResultOf(B))) -> IO(ResultOf(B)):
  match result:
    case Fail{error}: IO.pure(ResultOf(B),Fail{error})
    case Done{value}: next(value)

def then(-A: Data, -B: Data, action: IO(ResultOf(A)), next: A -> IO(ResultOf(B))) -> IO(ResultOf(B)):
  IO.bind(ResultOf(A),ResultOf(B),action,result => continued(A,B,result,next))

def filesystem(-A: Data, result: Result<&2,&2,FS.Error,A>) -> ResultOf(A):
  match result:
    case Done{value}: Done{value}
    case Fail{cause}: Fail{Filesystem{cause}}

def localRead(environment: Unit, path: String) -> IO(ResultOf(List<&2,U32>)):
  do IO<ResultOf(List<&2,U32>)>:
    value : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
    return filesystem(List<&2,U32>,value)

def localAccess(environment: Unit, path: String) -> IO(ResultOf(Unit)):
  do IO<ResultOf(Unit)>:
    value : Result<&1,&1,U32 & String,Unit> <- File.access(path,4)
    return filesystem(Unit,FS.system(Unit,value))

def localMime(environment: Unit, path: String) -> IO(ResultOf(Maybe<&2,String>)):
  do IO<ResultOf(Maybe<&2,String>)>:
    value : Result<&2,&2,FS.Error,Maybe<&2,String>> <- Mime.detectSupportedImageMimeTypeFromFile(path)
    return filesystem(Maybe<&2,String>,value)

def defaultReadOperations() -> IO(ReadOperations):
  do IO<ReadOperations>:
    reader : Callback.Callback<String,ResultOf(List<&2,U32>)> <- Callback.create(~Unit,~String,~ResultOf(List<&2,U32>),~localRead,Unit{})
    access : Callback.Callback<String,ResultOf(Unit)> <- Callback.create(~Unit,~String,~ResultOf(Unit),~localAccess,Unit{})
    mime : Callback.Callback<String,ResultOf(Maybe<&2,String>)> <- Callback.create(~Unit,~String,~ResultOf(Maybe<&2,String>),~localMime,Unit{})
    return ReadOperations{reader,access,Some{mime}}

def disposeMime(value: Maybe<&2,Callback.Callback<String,ResultOf(Maybe<&2,String>)>>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: Callback.dispose(String,ResultOf(Maybe<&2,String>),callback)

def dispose(operations: ReadOperations) -> IO(Unit):
  match operations:
    case ReadOperations{reader,access,mime}:
      do IO<Unit>:
        Callback.dispose(String,ResultOf(List<&2,U32>),reader)
        Callback.dispose(String,ResultOf(Unit),access)
        disposeMime(mime)

def cancellation(aborted: Bool) -> ResultOf(Unit):
  match aborted:
    case True{}: Fail{Aborted{}}
    case False{}: Done{Unit{}}

def check(signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(Unit)):
  match signal:
    case None{}: IO.pure(ResultOf(Unit),Done{Unit{}})
    case Some{value}:
      do IO<ResultOf(Unit)>:
        aborted : Bool <- Abort.aborted(Unit,value)
        return cancellation(aborted)

# A finished in-flight callback belongs to its caller even after cancellation.
# Cancellation takes precedence over its result, without detaching IO work.
def settled(-A: Data, signal: Maybe<&2,Abort.AbortSignal<Unit>>, result: ResultOf(A)) -> IO(ResultOf(A)):
  then(Unit,A,check(signal),_ => IO.pure(ResultOf(A),result))

def nonVision(note: Maybe<&2,Bool>) -> String:
  match note:
    case Some{False{}}: "\n[Current model does not support images. The image will be omitted from this request.]"
    case _: ""

def imageResult(original: String, note: Maybe<&2,Bool>, processed: ProcessedImage) -> Agent.AgentToolResult<Maybe<&2,ReadToolDetails>>:
  match processed:
    case Unsupported{message}:
      Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{"Read image file [" ++ original ++ "]\n" ++ message ++ nonVision(note),None{}}} <> Nil{},None{},None{},None{}}
    case Processed{data,+mime,+hints}:
      text = "Read image file [" ++ mime ++ "]" ++ Bool.pick(String,List.is_empty(&2,String,hints),"","\n" ++ String.join(hints,"\n")) ++ nonVision(note)
      Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{text,None{}}} <> Ai.TextImageImage{Ai.ImageContent{data,mime}} <> Nil{},None{},None{},None{}}

def textResult(value: ResultOf(TextResult)) -> ToolResult():
  match value:
    case Fail{error}: Fail{error}
    case Done{TextResult{text,details}}: Done{Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{text,None{}}} <> Nil{},details,None{},None{}}}

def textContent(input: ReadToolInput, decoded: Result<&2,&2,Utf8.Error,String>) -> ToolResult():
  match decoded:
    case Fail{cause}: Fail{InvalidEncoding{cause}}
    case Done{text}: textResult(readText(input,text))

def defaultProcessed(value: Images.ProcessImageResult) -> ResultOf(ProcessedImage):
  match value:
    case Images.Processed{data,mime,hints}: Done{Processed{data,mime,hints}}
    case Images.Unsupported{message}: Done{Unsupported{message}}

def processed(processor: Maybe<&2,Callback.Callback<ImageInput,ResultOf(ProcessedImage)>>, bytes: List<&2,U32>, mime: String, resize: Bool) -> IO(ResultOf(ProcessedImage)):
  match processor:
    case None{}: IO.pure(ResultOf(ProcessedImage),defaultProcessed(Images.processImage(bytes,mime,Images.ProcessImageOptions{Some{resize},None{}})))
    case Some{callback}: Callback.call(ImageInput,ResultOf(ProcessedImage),callback,ImageInput{bytes,mime,resize})

def content(input: ReadToolInput, bytes: List<&2,U32>, mime: Maybe<&2,String>, resize: Bool, processor: Maybe<&2,Callback.Callback<ImageInput,ResultOf(ProcessedImage)>>, note: Maybe<&2,Bool>) -> IO(ToolResult()):
  match mime:
    case None{}: IO.pure(ToolResult(),textContent(input,Utf8.decodeWith(Utf8.Preserve{},bytes)))
    case Some{+mime}:
      then(ProcessedImage,Agent.AgentToolResult<Maybe<&2,ReadToolDetails>>,processed(processor,bytes,mime,resize),value => IO.pure(ToolResult(),Done{imageResult(mime,note,value)}))

def nonempty(value: Maybe<&2,String>) -> Maybe<&2,String>:
  match value:
    case None{}: None{}
    case Some{+mime}: Bool.pick(Maybe<&2,String>,String.is_empty(mime),None{},Some{mime})

def detect(callback: Maybe<&2,Callback.Callback<String,ResultOf(Maybe<&2,String>)>>, path: String) -> IO(ResultOf(Maybe<&2,String>)):
  match callback:
    case None{}: IO.pure(ResultOf(Maybe<&2,String>),Done{None{}})
    case Some{callback}:
      do IO<ResultOf(Maybe<&2,String>)>:
        result : ResultOf(Maybe<&2,String>) <- Callback.call(String,ResultOf(Maybe<&2,String>),callback,path)
        return Result.map(&2,&2,Error,Maybe<&2,String>,Maybe<&2,String>,nonempty,result)

def read(operations: ReadOperations, +absolute: String, input: ReadToolInput, resize: Bool, processor: Maybe<&2,Callback.Callback<ImageInput,ResultOf(ProcessedImage)>>, note: Maybe<&2,Bool>, +signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ToolResult()):
  match operations:
    case ReadOperations{reader,access,mime}:
      then(Unit,Agent.AgentToolResult<Maybe<&2,ReadToolDetails>>,check(signal),_ =>
        then(Unit,Agent.AgentToolResult<Maybe<&2,ReadToolDetails>>,Callback.call(String,ResultOf(Unit),access,absolute),_ =>
          then(Unit,Agent.AgentToolResult<Maybe<&2,ReadToolDetails>>,check(signal),_ =>
            then(Maybe<&2,String>,Agent.AgentToolResult<Maybe<&2,ReadToolDetails>>,detect(mime,absolute),detected =>
              then(List<&2,U32>,Agent.AgentToolResult<Maybe<&2,ReadToolDetails>>,Callback.call(String,ResultOf(List<&2,U32>),reader,absolute),bytes =>
                content(input,bytes,detected,resize,processor,note))))))

# Pi probes real filenames before trying its macOS screenshot spelling variants.
def screenshot(path: String, reversed: String) -> String:
  match path:
    case SCon{' ',SCon{+a,SCon{+m,SCon{'.',rest}}}}:
      +amPm = (Char.is_eq(a,'A') || Char.is_eq(a,'a') || Char.is_eq(a,'P') || Char.is_eq(a,'p')) && (Char.is_eq(m,'M') || Char.is_eq(m,'m'))
      screenshot(rest,SCon{'.',SCon{m,SCon{a,SCon{Bool.pick(Char,amPm,'\u{202f}',' '),reversed}}}})
    case SCon{char,rest}: screenshot(rest,SCon{char,reversed})
    case SNil{}: String.reverse(reversed)

def curly(path: String, reversed: String) -> String:
  match path:
    case SCon{+char,rest}: curly(rest,SCon{Bool.pick(Char,Char.is_eq(char,'\''),'\u{2019}',char),reversed})
    case SNil{}: String.reverse(reversed)

def normalization(environment: Paths.Environment) -> Unicode.Tables:
  match environment:
    case Paths.Environment{_,_,URL.Context{IDNA.Context{_,tables,_},_}}: tables

def exists(result: Result<&1,&1,U32 & String,Unit>) -> Bool:
  match result:
    case Done{Unit{}}: True{}
    case Fail{_}: False{}

def findPath(candidates: List<&2,String>, +original: String, found: Maybe<&2,String>) -> IO(String):
  match candidates found:
    case _ Some{path}: IO.pure(String,path)
    case Nil{} None{}: IO.pure(String,original)
    case +path <> rest None{}:
      do IO<String>:
        value : Result<&1,&1,U32 & String,Unit> <- File.access(path,0)
        findPath(rest,original,Bool.pick(Maybe<&2,String>,exists(value),Some{path},None{}))

def resolvedPath(environment: Paths.Environment, +original: String) -> IO(String):
  +nfd = Unicode.nfd(normalization(environment),original)
  findPath(original <> screenshot(original,"") <> nfd <> curly(original,"") <> curly(nfd,"") <> Nil{},original,None{})

def numeric(value: Result<&2,&2,Number.Error,Nat>) -> ResultOf(Maybe<&2,Nat>):
  match value:
    case Done{count}: Done{Some{count}}
    case Fail{_}: Fail{InvalidArguments{}}

def countArgument(value: Maybe<&2,Value.Value>) -> ResultOf(Maybe<&2,Nat>):
  match value:
    case None{}: Done{None{}}
    case Some{Value.Number{number}}: numeric(Number.convert(number))
    case _: Fail{InvalidArguments{}}

def parameters(path: Maybe<&2,Value.Value>, offset: ResultOf(Maybe<&2,Nat>), limit: ResultOf(Maybe<&2,Nat>)) -> ResultOf(ReadToolInput):
  match path offset limit:
    case Some{Value.Text{path}} Done{offset} Done{limit}: Done{ReadToolInput{path,offset,limit}}
    case _ _ _: Fail{InvalidArguments{}}

def parseInput(value: Value.Value) -> ResultOf(ReadToolInput):
  match value:
    case Value.ObjectValue{+fields}: parameters(Record.get(Value.Value,fields,"path"),countArgument(Record.get(Value.Value,fields,"offset")),countArgument(Record.get(Value.Value,fields,"limit")))
    case _: Fail{InvalidArguments{}}

def execute(environment: Invocation, +input: ReadToolInput, note: Maybe<&2,Bool>, +signal: Maybe<&2,Abort.AbortSignal<Unit>>, resolved: Result<&2,&2,Paths.Error,String>) -> IO(ToolResult()):
  match environment resolved:
    case _ Fail{cause}: IO.pure(ToolResult(),Fail{InvalidPath{cause}})
    case Invocation{paths,_,operations,resize,processor} Done{path}:
      do IO<ToolResult()>:
        absolute : String <- resolvedPath(paths,path)
        value : ToolResult() <- read(operations,absolute,input,resize,processor,note,signal)
        settled(Agent.AgentToolResult<Maybe<&2,ReadToolDetails>>,signal,value)

def resolveInput(environment: Paths.Environment, cwd: String, input: ReadToolInput) -> Result<&2,&2,Paths.Error,String>:
  match input:
    case ReadToolInput{path,_,_}: Paths.resolveToCwd(environment,path,cwd)

def workingDirectory(override: Maybe<&2,String>, +fallback: String) -> String:
  match override:
    case None{}: fallback
    case Some{+value}: Bool.pick(String,String.is_empty(value),fallback,value)

def invokeInput(+environment: Invocation, context: ReadContext, +signal: Maybe<&2,Abort.AbortSignal<Unit>>, input: ResultOf(ReadToolInput)) -> IO(ToolResult()):
  match environment context input:
    case _ _ Fail{error}: IO.pure(ToolResult(),Fail{error})
    case Invocation{+paths,cwd,_,_,_} ReadContext{override,note} Done{+value}:
      then(Unit,Agent.AgentToolResult<Maybe<&2,ReadToolDetails>>,check(signal),_ => execute(environment,value,note,signal,resolveInput(paths,workingDirectory(override,cwd),value)))

# Extension adapters can pass dynamic cwd/model capability here. AgentTool's
# public execute input has no ExtensionContext and uses the absent context.
def invokeWithContext(environment: Invocation, context: ReadContext, request: Agent.ToolExecutionInput<Maybe<&2,ReadToolDetails>>) -> IO(ToolResult()):
  match request:
    case Agent.ToolExecutionInput{_,arguments,signal,_}: invokeInput(environment,context,signal,parseInput(arguments))

def invoke(environment: Invocation, request: Agent.ToolExecutionInput<Maybe<&2,ReadToolDetails>>) -> IO(ToolResult()):
  invokeWithContext(environment,ReadContext{None{},None{}},request)

def parameter(kind: String, description: String) -> Value.Value:
  Value.ObjectValue{Record.Record{Record.Property{"type",Value.Text{kind}} <> Record.Property{"description",Value.Text{description}} <> Nil{}}}

def readSchema() -> Value.Value:
  Value.ObjectValue{Record.Record{
    Record.Property{"type",Value.Text{"object"}} <>
    Record.Property{"properties",Value.ObjectValue{Record.Record{
      Record.Property{"path",parameter("string","Path to the file to read (relative or absolute)")} <>
      Record.Property{"offset",parameter("number","Line number to start reading from (1-indexed)")} <>
      Record.Property{"limit",parameter("number","Maximum number of lines to read")} <> Nil{}}}} <>
    Record.Property{"required",Value.ArrayValue{Value.Text{"path"} <> Nil{}}} <> Nil{}}}

def created(environment: Invocation, owned: Maybe<&2,ReadOperations>) -> IO(ToolOwner):
  do IO<ToolOwner>:
    callback : Callback.Callback<Agent.ToolExecutionInput<Maybe<&2,ReadToolDetails>>,ToolResult()> <- Callback.create(~Invocation,~Agent.ToolExecutionInput<Maybe<&2,ReadToolDetails>>,~ToolResult(),~invoke,environment)
    return ToolOwner{Agent.AgentTool{"read","Read the contents of a file. Supports text files and images (jpg, png, gif, webp, bmp). Images are sent as attachments. For text files, output is truncated to 2000 lines or 50KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete.",readSchema(),Some{Ai.SamplingConfigured{Ai.JsonSchemaSampling{Ai.Prefer{}}}},"read",None{},callback,None{},None{}},owned}

def createReadTool(paths: Paths.Environment, cwd: String, options: ReadToolOptions) -> IO(ToolOwner):
  match options:
    case ReadToolOptions{resize,Some{operations},processor}: created(Invocation{paths,cwd,operations,Maybe.default(&2,Bool,resize,True{}),processor},None{})
    case ReadToolOptions{resize,None{},processor}:
      do IO<ToolOwner>:
        +operations : ReadOperations <- defaultReadOperations()
        created(Invocation{paths,cwd,operations,Maybe.default(&2,Bool,resize,True{}),processor},Some{operations})

def borrowTool(owner: ToolOwner) -> ToolOwner & Agent.AgentTool<Maybe<&2,ReadToolDetails>,Error>:
  match owner:
    case ToolOwner{+tool,operations}: (ToolOwner{tool,operations},tool)

def disposeOwned(value: Maybe<&2,ReadOperations>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{operations}: dispose(operations)

def disposeTool(owner: ToolOwner) -> IO(Unit):
  match owner:
    case ToolOwner{Agent.AgentTool{_,_,_,_,_,_,callback,_,_},owned}:
      do IO<Unit>:
        Callback.dispose(Agent.ToolExecutionInput<Maybe<&2,ReadToolDetails>>,ToolResult(),callback)
        disposeOwned(owned)
