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

def processMode(mode: String, resize: Bool) -> Read.ResultOf(Read.ProcessedImage):
  match mode:
    case "unsupported": Done{Read.Unsupported{"Unsupported test image"}}
    case "failed": Fail{Read.Operation{"processor failure"}}
    case _: Done{Read.Processed{"AQID","image/png",Bool.pick(List<&2,String>,resize,"resized" <> Nil{},Nil{})}}

def process(mode: String, input: Read.ImageInput) -> IO(Read.ResultOf(Read.ProcessedImage)):
  match input:
    case Read.ImageInput{71 <> 73 <> 70 <> 56 <> 57 <> 97 <> Nil{},"image/gif",resize}: IO.pure(Read.ResultOf(Read.ProcessedImage),processMode(mode,resize))
    case _: IO.pure(Read.ResultOf(Read.ProcessedImage),Fail{Read.Operation{"unexpected image input"}})

def parsed(value: Result<&2,&2,Json.ParseError,V.Value>) -> V.Value:
  match value:
    case Done{value}: value
    case Fail{_}: V.Null{}

def calls(args: List<String>, +callback: C.Callback<Agent.ToolExecutionInput<Maybe<&2,Read.ReadToolDetails>>,Read.ToolResult()>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        result : Read.ToolResult() <- C.call(Agent.ToolExecutionInput<Maybe<&2,Read.ReadToolDetails>>,Read.ToolResult(),callback,Agent.ToolExecutionInput{"test",parsed(Json.parse(value)),None{},None{}})
        IO.print(report(result))
        calls(rest,callback)

def runOwner(value: Read.ToolOwner & Agent.AgentTool<Maybe<&2,Read.ReadToolDetails>,Read.Error>, args: List<String>) -> IO(Unit):
  match value:
    case Tuple{owner,Agent.AgentTool{"read",_,_,Some{Ai.SamplingConfigured{Ai.JsonSchemaSampling{Ai.Prefer{}}}},"read",None{},callback,None{},None{}}}:
      do IO<Unit>:
        calls(args,callback)
        Read.disposeTool(owner)
    case _: IO.die(Unit,1,"invalid read metadata")

def run(args: List<String>) -> IO(Unit):
  match args:
    case +cwd <> home <> +mode <> rest:
      do IO<Unit>:
        +processor : C.Callback<Read.ImageInput,Read.ResultOf(Read.ProcessedImage)> <- C.create(~String,~Read.ImageInput,~Read.ResultOf(Read.ProcessedImage),~process,mode)
        tool : Read.ToolOwner <- Read.createReadTool(environment(cwd,home),cwd,Read.ReadToolOptions{Some{Bool.not(String.eq(mode,"noresize") || String.eq(mode,"native-noresize"))},None{},Bool.pick(Maybe<&2,C.Callback<Read.ImageInput,Read.ResultOf(Read.ProcessedImage)>>,String.eq(mode,"default") || String.eq(mode,"native-noresize"),None{},Some{processor})})
        runOwner(Read.borrowTool(tool),rest)
        C.dispose(Read.ImageInput,Read.ResultOf(Read.ProcessedImage),processor)
    case _: IO.die(Unit,1,"expected cwd, home, processor mode, JSON inputs")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
