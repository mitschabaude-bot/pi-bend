import Base
import ../packages/coding-agent/src/core/tools/read.bend as Read
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx
import ../packages/coding-agent/src/utils/image-resize.bend as Resize
import ../packages/runtime/src/f64.bend as F

def environment(cwd: String, home: String) -> Paths.Environment:
  Paths.Environment{cwd,home,URL.Context{IDNA.Context{Mapping.table(),Normalization.tables(),Properties.table()},IDNA.Options{IDNA.LabelOptions{False{},False{},True{},IDNA.Nontransitional{}},True{},False{}}}}

def parts(values: List<&2,Ai.TextImageContent>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case Ai.TextImageText{Ai.TextContent{text,_}} <> rest: ("[\"text\"," ++ Json.quote(text) ++ "]") <> parts(rest)
    case Ai.TextImageImage{Ai.ImageContent{data,mime}} <> rest: ("[\"image\"," ++ Json.quote(data) ++ "," ++ Json.quote(mime) ++ "]") <> parts(rest)

def report(value: Read.ToolResult()) -> String:
  match value:
    case Fail{cause}: "{\"error\":" ++ Json.quote(Read.errorMessage(cause)) ++ "}"
    case Done{Agent.AgentToolResult{values,details,_,_}}:
      "{\"content\":[" ++ String.join(parts(values),",") ++ "],\"truncated\":" ++ Bool.pick(String,Maybe.is_none(&2,Read.ReadToolDetails,details),"false","true") ++ "}"

# The resize profile the processor received, as JSON.stringify renders it.
def field(name: String, value: Maybe<&2,Nat>) -> List<&2,String>:
  match value:
    case None{}: Nil{}
    case Some{number}: ("\"" ++ name ++ "\":" ++ Nat.show(number)) <> Nil{}
def profileJson(profile: Maybe<&2,Resize.ImageResizeOptions>) -> String:
  match profile:
    case None{}: "null"
    case Some{Resize.ImageResizeOptions{w,h,b,q}}: "{" ++ String.join(List.concat(&2,String,[field("maxWidth",Maybe.map(&2,U32,Nat,U32.to_nat,w)),field("maxHeight",Maybe.map(&2,U32,Nat,U32.to_nat,h)),field("maxBytes",b),field("jpegQuality",Maybe.map(&2,U32,Nat,U32.to_nat,q))]),",") ++ "}"

def profiled(profile: Maybe<&2,Resize.ImageResizeOptions>) -> Read.ResultOf(Read.ProcessedImage):
  Done{Read.Processed{"AQID","image/png",("resize:" ++ profileJson(profile)) <> Nil{}}}

def processMode(mode: String, resize: Bool, profile: Maybe<&2,Resize.ImageResizeOptions>) -> Read.ResultOf(Read.ProcessedImage):
  match mode:
    case "unsupported": Done{Read.Unsupported{"Unsupported test image"}}
    case "failed": Fail{Read.Operation{"processor failure"}}
    case "profile": profiled(profile)
    case "fallback": profiled(profile)
    case "profile-over-fallback": profiled(profile)
    case _: Done{Read.Processed{"AQID","image/png",Bool.pick(List<&2,String>,resize,"resized" <> Nil{},Nil{})}}

def process(mode: String, input: Read.ImageInput) -> IO(Read.ResultOf(Read.ProcessedImage)):
  match input:
    case Read.ImageInput{71 <> 73 <> 70 <> 56 <> 57 <> 97 <> Nil{},"image/gif",resize,profile}: IO.pure(Read.ResultOf(Read.ProcessedImage),processMode(mode,resize,profile))
    case _: IO.pure(Read.ResultOf(Read.ProcessedImage),Fail{Read.Operation{"unexpected image input"}})

def parsed(value: Result<&2,&2,Json.ParseError,V.Value>) -> V.Value:
  match value:
    case Done{value}: value
    case Fail{_}: V.Null{}

def calls(args: List<String>, +callback: C.Callback<Agent.ToolExecutionInput<Read.ReadToolDetails>,Read.ToolResult()>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        result : Read.ToolResult() <- C.call(Agent.ToolExecutionInput<Read.ReadToolDetails>,Read.ToolResult(),callback,Agent.ToolExecutionInput{"test",parsed(Json.parse(value)),None{},None{}})
        IO.print(report(result))
        calls(rest,callback)

def runOwner(value: Read.ToolOwner & Agent.AgentTool<Read.ReadToolDetails,Read.Error>, args: List<String>) -> IO(Unit):
  match value:
    case Tuple{owner,Agent.AgentTool{"read",_,_,Some{Ai.SamplingConfigured{Ai.JsonSchemaSampling{Ai.Prefer{}}}},"read",None{},callback,None{},None{}}}:
      do IO<Unit>:
        calls(args,callback)
        Read.disposeTool(owner)
    case _: IO.die(Unit,1,"invalid read metadata")

# image-resize-callers.test.ts "passes the current model resize profile to the read tool": the
# execution context's model, as upstream's test model.
def whole(value: U32) -> Maybe<&2,F64>: Some{F.fromU32(value)}
def visionModel() -> Ai.Model<Ai.JsonValue>:
  +zero = F.fromU32(0)
  Ai.Model{"vision-model","Vision model",Ai.OpenAIResponsesApi{},"test","https://example.com",False{},None{},[Ai.InputText{},Ai.InputImage{}],Some{Ai.ModelInputLimits{None{},Some{Ai.ModelImageInputLimits{Some{Ai.ModelImageResizeOptions{whole(1234),whole(1000),whole(500000),whole(70)}},None{},None{}}}}},Ai.ModelCost{zero,zero,zero,zero,None{}},None{},F.fromU32(1000),F.fromU32(100),None{},None{},None{}}

# The tool's own fallback profile (ReadToolOptions.resizeOptions).
def fallbackProfile(+mode: String) -> Maybe<&2,Resize.ImageResizeOptions>:
  Bool.pick(Maybe<&2,Resize.ImageResizeOptions>,String.eq(mode,"fallback") || String.eq(mode,"profile-over-fallback"),Some{Resize.ImageResizeOptions{Some{1100},None{},None{},None{}}},None{})

def contextCalls(args: List<String>, +invocation: Read.Invocation, +cwd: String) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        result : Read.ToolResult() <- Read.invokeWithContext(invocation,Read.toolContext(Some{Ctx.ContextView{cwd,Some{visionModel()},"session",None{},Ai.Off{}}}),Agent.ToolExecutionInput{"test",parsed(Json.parse(value)),None{},None{}})
        IO.print(report(result))
        contextCalls(rest,invocation,cwd)

def runContext(+cwd: String, home: String, +mode: String, rest: List<String>) -> IO(Unit):
  do IO<Unit>:
    +processor : C.Callback<Read.ImageInput,Read.ResultOf(Read.ProcessedImage)> <- C.create(~String,~Read.ImageInput,~Read.ResultOf(Read.ProcessedImage),~process,mode)
    +operations : Read.ReadOperations <- Read.defaultReadOperations()
    contextCalls(rest,Read.Invocation{environment(cwd,home),cwd,operations,True{},fallbackProfile(mode),Some{processor}},cwd)
    Read.dispose(operations)
    C.dispose(Read.ImageInput,Read.ResultOf(Read.ProcessedImage),processor)

def run(args: List<String>) -> IO(Unit):
  match args:
    case +cwd <> home <> "profile" <> rest: runContext(cwd,home,"profile",rest)
    case +cwd <> home <> "profile-over-fallback" <> rest: runContext(cwd,home,"profile-over-fallback",rest)
    case +cwd <> home <> +mode <> rest:
      do IO<Unit>:
        +processor : C.Callback<Read.ImageInput,Read.ResultOf(Read.ProcessedImage)> <- C.create(~String,~Read.ImageInput,~Read.ResultOf(Read.ProcessedImage),~process,mode)
        +unbound1 : Ctx.ContextSource() <- Ctx.create()
        tool : Read.ToolOwner <- Read.createReadTool(environment(cwd,home),cwd,Read.ReadToolOptions{Some{Bool.not(String.eq(mode,"noresize") || String.eq(mode,"native-noresize"))},fallbackProfile(mode),None{},Bool.pick(Maybe<&2,C.Callback<Read.ImageInput,Read.ResultOf(Read.ProcessedImage)>>,String.eq(mode,"default") || String.eq(mode,"native-noresize"),None{},Some{processor})},unbound1)
        runOwner(Read.borrowTool(tool),rest)
        C.dispose(Read.ImageInput,Read.ResultOf(Read.ProcessedImage),processor)
    case _: IO.die(Unit,1,"expected cwd, home, processor mode, JSON inputs")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
