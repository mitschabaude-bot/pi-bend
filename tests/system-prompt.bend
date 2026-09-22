import Base
import ../packages/coding-agent/src/core/system-prompt.bend as P
import ../packages/coding-agent/src/core/skills.bend as S
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/ai/src/utils/json.bend as Encoding
import ../packages/ai/src/utils/schema-json.bend as SchemaJson

# JSON is only transport for the pinned-source differential fixture.
def get(value: V.Value,key: String) -> Maybe<&2,V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value,fields,key)
    case _: None{}
def text(value: V.Value) -> String:
  match value:
    case V.Text{value}: value
    case _: ""
def textList(values: List<&2,V.Value>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: text(value) <> textList(rest)
def texts(value: V.Value) -> List<&2,String>:
  match value:
    case V.ArrayValue{values}: textList(values)
    case _: Nil{}
def optional(-A: Data,value: Maybe<&2,V.Value>,convert: V.Value -> A) -> Maybe<&2,A>:
  match value:
    case None{}: None{}
    case Some{value}: Some{convert(value)}
def field(value: V.Value,key: String) -> String: text(Maybe.default(&2,V.Value,get(value,key),V.Null{}))
def flag(value: Maybe<&2,V.Value>) -> Bool:
  match value:
    case Some{V.Boolean{value}}: value
    case _: False{}
def skill(+value: V.Value) -> S.Skill:
  S.Skill{field(value,"name"),field(value,"description"),field(value,"filePath"),field(value,"baseDir"),S.SourceInfo{field(value,"filePath"),"test",S.Temporary{},S.TopLevel{},None{}},flag(get(value,"disableModelInvocation"))}
def skillList(values: List<&2,V.Value>) -> List<&2,S.Skill>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: skill(value) <> skillList(rest)
def skills(value: V.Value) -> List<&2,S.Skill>:
  match value:
    case V.ArrayValue{values}: skillList(values)
    case _: Nil{}
def context(+value: V.Value) -> P.ContextFile: P.ContextFile{field(value,"path"),field(value,"content")}
def contextList(values: List<&2,V.Value>) -> List<&2,P.ContextFile>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: context(value) <> contextList(rest)
def contexts(value: V.Value) -> List<&2,P.ContextFile>:
  match value:
    case V.ArrayValue{values}: contextList(values)
    case _: Nil{}
def stringFields(fields: List<&2,R.Property<V.Value>>) -> List<&2,R.Property<String>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key,value} <> rest: R.Property{key,text(value)} <> stringFields(rest)
def stringMap(value: V.Value) -> R.Record<String>:
  match value:
    case V.ObjectValue{R.Record{fields}}: R.Record{stringFields(fields)}
    case _: R.new(String)
def rulesFields(fields: List<&2,R.Property<V.Value>>) -> List<&2,R.Property<List<&2,String>>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key,value} <> rest: R.Property{key,texts(value)} <> rulesFields(rest)
def rulesMap(value: V.Value) -> R.Record<List<&2,String>>:
  match value:
    case V.ObjectValue{R.Record{fields}}: R.Record{rulesFields(fields)}
    case _: R.new(List<&2,String>)
def options(+value: V.Value) -> P.BuildSystemPromptOptions:
  P.BuildSystemPromptOptions{
    optional(String,get(value,"customPrompt"),text),optional(String,get(value,"forceSystemPrompt"),text),
    optional(List<&2,String>,get(value,"selectedTools"),texts),optional(R.Record<String>,get(value,"toolSnippets"),stringMap),
    optional(R.Record<List<&2,String>>,get(value,"toolGuidelines"),rulesMap),
    optional(List<&2,String>,get(value,"promptGuidelines"),texts),optional(String,get(value,"appendSystemPrompt"),text),
    optional(R.Record<String>,get(value,"sections"),stringMap),field(value,"cwd"),
    optional(List<&2,P.ContextFile>,get(value,"contextFiles"),contexts),optional(List<&2,S.Skill>,get(value,"skills"),skills)}
def paths() -> P.DocumentationPaths: P.DocumentationPaths{"/pi/README.md","/pi/docs","/pi/examples"}
def error(value: P.Error) -> V.Value:
  match value:
    case P.InvalidSectionName{name}: V.ObjectValue{R.Record{R.Property{"error",V.Text{"Invalid system prompt section name: " ++ name}} <> Nil{}}}
def resultText(value: P.ResultOf(String)) -> V.Value:
  match value:
    case Done{value}: V.Text{value}
    case Fail{cause}: error(cause)
def sectionEntries(fields: List<&2,R.Property<String>>) -> List<&2,V.Value>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{name,value} <> rest: V.ArrayValue{V.Text{name} <> V.Text{value} <> Nil{}} <> sectionEntries(rest)
def sectionValues(value: R.Record<String>) -> V.Value: V.ArrayValue{sectionEntries(R.entries(String,value))}
def resultSections(value: P.ResultOf(P.SystemPromptSections())) -> V.Value:
  match value:
    case Done{value}: sectionValues(value)
    case Fail{cause}: error(cause)
def sectionOption(value: Maybe<&2,P.SystemPromptSections()>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{value}: sectionValues(value)
def resultState(value: P.ResultOf(P.SystemPromptState)) -> V.Value:
  match value:
    case Done{P.SystemPromptState{content,sections}}: V.ArrayValue{V.Text{content} <> sectionOption(sections) <> Nil{}}
    case Fail{cause}: error(cause)
def nullable(value: V.Value) -> Maybe<&2,String>:
  match value:
    case V.Null{}: None{}
    case V.Text{value}: Some{value}
    case _: None{}
def priorFields(fields: List<&2,R.Property<V.Value>>) -> List<&2,R.Property<Maybe<&2,String>>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key,value} <> rest: R.Property{key,nullable(value)} <> priorFields(rest)
def priorMap(value: V.Value) -> R.Record<Maybe<&2,String>>:
  match value:
    case V.ObjectValue{R.Record{fields}}: R.Record{priorFields(fields)}
    case _: R.new(Maybe<&2,String>)
def encodeNullable(value: Maybe<&2,String>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{value}: V.Text{value}
def patchEntries(fields: List<&2,R.Property<Maybe<&2,String>>>) -> List<&2,V.Value>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{name,value} <> rest: V.ArrayValue{V.Text{name} <> encodeNullable(value) <> Nil{}} <> patchEntries(rest)
def patch(value: Maybe<&2,R.Record<Maybe<&2,String>>>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{value}: V.ArrayValue{patchEntries(R.entries(Maybe<&2,String>,value))}
def readTool(value: String) -> S.FileReadTool:
  match value:
    case "bash": S.Bash{}
    case _: S.Read{}
def largeContent(remaining: Nat,content: String) -> String:
  match remaining:
    case 0n: content
    case 1n+n: largeContent(n,"Project instructions.\n" ++ content)
def largeOptions() -> P.BuildSystemPromptOptions:
  P.BuildSystemPromptOptions{None{},None{},None{},None{},None{},None{},None{},None{},"/large",Some{P.ContextFile{"/large/AGENTS.md",largeContent(7500n,"")} <> Nil{}},None{}}
def perform(op: String,+value: V.Value) -> V.Value:
  match op:
    case "large": resultText(P.buildSystemPrompt(paths(),largeOptions()))
    case "prompt": resultText(P.buildSystemPrompt(paths(),options(Maybe.default(&2,V.Value,get(value,"options"),V.Null{}))))
    case "sections": resultSections(P.buildSystemPromptSections(paths(),options(Maybe.default(&2,V.Value,get(value,"options"),V.Null{}))))
    case "state": resultState(P.buildSystemPromptState(paths(),options(Maybe.default(&2,V.Value,get(value,"options"),V.Null{}))))
    case "diff": patch(P.diffSystemPromptSections(priorMap(Maybe.default(&2,V.Value,get(value,"previous"),V.Null{})),stringMap(Maybe.default(&2,V.Value,get(value,"current"),V.Null{}))))
    case "skills": V.Text{S.formatSkillsForPrompt(skills(Maybe.default(&2,V.Value,get(value,"skills"),V.Null{})),readTool(field(value,"readTool")))}
    case _: V.Null{}
def parsed(value: Result<&2,&2,Json.ParseError,V.Value>) -> V.Value:
  match value:
    case Done{+value}: perform(field(value,"op"),value)
    case _: V.Null{}
def run(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(Maybe.default(&2,String,Encoding.stringify(SchemaJson.toJson(parsed(Json.parse(value)))),"null"))
        run(rest)
def rawPrompt(value: P.ResultOf(String)) -> IO(Unit):
  match value:
    case Done{value}: IO.print(value)
    case Fail{_}: IO.print("unexpected prompt failure")
def arguments(values: List<String>) -> IO(Unit):
  match values:
    case "--large-context" <> Nil{}: rawPrompt(P.buildSystemPrompt(paths(),largeOptions()))
    case other: run(other)
def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
