import Base
import ../packages/coding-agent/src/cli/args.bend as Args
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/json.bend as Json
import ../packages/ai/src/utils/json.bend as Encoding
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R

# JSON is test transport only; the production Args API is a typed record.
def textValues(values: List<&2,String>) -> List<&2,V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: V.Text{value} <> textValues(rest)
def strings(values: List<&2,String>) -> V.Value: V.ArrayValue{textValues(values)}
def boolean(value: Bool) -> V.Value: V.Boolean{value}
def encodeMode(value: Args.Mode) -> V.Value:
  match value:
    case Args.Text{}: V.Text{"text"}
    case Args.Json{}: V.Text{"json"}
    case Args.Rpc{}: V.Text{"rpc"}
def encodeTui(value: Args.TuiMode) -> V.Value:
  match value:
    case Args.Regular{}: V.Text{"regular"}
    case Args.Fullscreen{}: V.Text{"fullscreen"}
def encodeThinking(value: Ai.ModelThinkingLevel) -> V.Value:
  match value:
    case Ai.Off{}: V.Text{"off"}
    case Ai.Thinking{Ai.Minimal{}}: V.Text{"minimal"}
    case Ai.Thinking{Ai.Low{}}: V.Text{"low"}
    case Ai.Thinking{Ai.Medium{}}: V.Text{"medium"}
    case Ai.Thinking{Ai.High{}}: V.Text{"high"}
    case Ai.Thinking{Ai.XHigh{}}: V.Text{"xhigh"}
    case Ai.Thinking{Ai.Max{}}: V.Text{"max"}
def encodeModels(value: Args.ListModels) -> V.Value:
  match value:
    case Args.AllModels{}: V.Boolean{True{}}
    case Args.SearchModels{pattern}: V.Text{pattern}
def flag(value: Args.FlagValue) -> V.Value:
  match value:
    case Args.BooleanFlag{value}: V.Boolean{value}
    case Args.StringFlag{value}: V.Text{value}
def flags(values: List<&2,R.Property<Args.FlagValue>>) -> List<&2,V.Value>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name,value} <> rest: V.ArrayValue{V.Text{name} <> flag(value) <> Nil{}} <> flags(rest)
def diagnostic(kind: String,message: String) -> V.Value:
  V.ObjectValue{R.Record{R.Property{"type",V.Text{kind}} <> R.Property{"message",V.Text{message}} <> Nil{}}}
def diagnostics(values: List<&2,Args.Diagnostic>) -> List<&2,V.Value>:
  match values:
    case Nil{}: Nil{}
    case Args.Error{message} <> rest: diagnostic("error",message) <> diagnostics(rest)
    case Args.Warning{message} <> rest: diagnostic("warning",message) <> diagnostics(rest)
def property(-A: Data,name: String,value: Maybe<&2,A>,convert: A -> V.Value) -> List<&2,R.Property<V.Value>>:
  match value:
    case None{}: Nil{}
    case Some{value}: R.Property{name,convert(value)} <> Nil{}
def serialized(value: Args.Args) -> V.Value:
  match value:
    case Args.Args{provider,model,apiKey,systemPrompt,appendSystemPrompt,thinking,continue,resume,help,version,mode,name,noSession,session,sessionId,fork,sessionDir,models,tools,excludeTools,noTools,noBuiltinTools,extensions,noExtensions,print,export,noSkills,skills,promptTemplates,noPromptTemplates,themes,useTheme,noThemes,noContextFiles,listModels,offline,tuiMode,verbose,projectTrustOverride,messages,fileArgs,unknownFlags,issues}:
      V.ObjectValue{R.Record{List.concat(&2,R.Property<V.Value>,
        property(String,"provider",provider,value => V.Text{value}) <>
        property(String,"model",model,value => V.Text{value}) <>
        property(String,"apiKey",apiKey,value => V.Text{value}) <>
        property(String,"systemPrompt",systemPrompt,value => V.Text{value}) <>
        property(List<&2,String>,"appendSystemPrompt",appendSystemPrompt,strings) <>
        property(Ai.ModelThinkingLevel,"thinking",thinking,encodeThinking) <>
        property(Bool,"continue",continue,boolean) <>
        property(Bool,"resume",resume,boolean) <>
        property(Bool,"help",help,boolean) <>
        property(Bool,"version",version,boolean) <>
        property(Args.Mode,"mode",mode,encodeMode) <>
        property(String,"name",name,value => V.Text{value}) <>
        property(Bool,"noSession",noSession,boolean) <>
        property(String,"session",session,value => V.Text{value}) <>
        property(String,"sessionId",sessionId,value => V.Text{value}) <>
        property(String,"fork",fork,value => V.Text{value}) <>
        property(String,"sessionDir",sessionDir,value => V.Text{value}) <>
        property(List<&2,String>,"models",models,strings) <>
        property(List<&2,String>,"tools",tools,strings) <>
        property(List<&2,String>,"excludeTools",excludeTools,strings) <>
        property(Bool,"noTools",noTools,boolean) <>
        property(Bool,"noBuiltinTools",noBuiltinTools,boolean) <>
        property(List<&2,String>,"extensions",extensions,strings) <>
        property(Bool,"noExtensions",noExtensions,boolean) <>
        property(Bool,"print",print,boolean) <>
        property(String,"export",export,value => V.Text{value}) <>
        property(Bool,"noSkills",noSkills,boolean) <>
        property(List<&2,String>,"skills",skills,strings) <>
        property(List<&2,String>,"promptTemplates",promptTemplates,strings) <>
        property(Bool,"noPromptTemplates",noPromptTemplates,boolean) <>
        property(List<&2,String>,"themes",themes,strings) <>
        property(String,"useTheme",useTheme,value => V.Text{value}) <>
        property(Bool,"noThemes",noThemes,boolean) <>
        property(Bool,"noContextFiles",noContextFiles,boolean) <>
        property(Args.ListModels,"listModels",listModels,encodeModels) <>
        property(Bool,"offline",offline,boolean) <>
        property(Args.TuiMode,"tuiMode",tuiMode,encodeTui) <>
        property(Bool,"verbose",verbose,boolean) <>
        property(Bool,"projectTrustOverride",projectTrustOverride,boolean) <>
        (R.Property{"messages",strings(messages)} <> R.Property{"fileArgs",strings(fileArgs)} <>
         R.Property{"unknownFlags",V.ArrayValue{flags(R.entries(Args.FlagValue,unknownFlags))}} <>
         R.Property{"diagnostics",V.ArrayValue{diagnostics(issues)}} <> Nil{}) <> Nil{})}}
def list(values: List<&2,V.Value>,reversed: List<&2,String>) -> List<&2,String>:
  match values:
    case Nil{}: List.reverse(&2,String,reversed)
    case V.Text{value} <> rest: list(rest,value <> reversed)
    case _ <> rest: list(rest,reversed)
def normalized(value: Maybe<&2,String>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{value}: V.Text{value}
def parse(value: Result<&2,&2,Json.ParseError,V.Value>) -> V.Value:
  match value:
    case Done{V.ArrayValue{values}}: serialized(Args.parseArgs(list(values,Nil{})))
    case Done{V.Text{value}}: normalized(Args.normalizeSessionName(value))
    case _: V.Null{}
def run(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(Maybe.default(&2,String,Encoding.stringify(SchemaJson.toJson(parse(Json.parse(value)))),"null"))
        run(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    run(values)
