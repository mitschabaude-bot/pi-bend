import Base
import ./skills.bend as Skills
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/utils/text.bend as AiText
import ../../../runtime/src/record.bend as Record
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/text.bend as Space
import ../../../runtime/src/f64.bend as F

type DocumentationPaths is Data:
  DocumentationPaths{readme: String,docs: String,examples: String}
type ContextFile is Data:
  ContextFile{path: String,content: String}
type BuildSystemPromptOptions is Data:
  BuildSystemPromptOptions{customPrompt: Maybe<&2,String>,forceSystemPrompt: Maybe<&2,String>,selectedTools: Maybe<&2,List<&2,String>>,toolSnippets: Maybe<&2,Record.Record<String>>,toolGuidelines: Maybe<&2,Record.Record<List<&2,String>>>,promptGuidelines: Maybe<&2,List<&2,String>>,appendSystemPrompt: Maybe<&2,String>,sections: Maybe<&2,Record.Record<String>>,cwd: String,contextFiles: Maybe<&2,List<&2,ContextFile>>,skills: Maybe<&2,List<&2,Skills.Skill>>}
type NormalizedBuildSystemPromptOptions is Data:
  NormalizedBuildSystemPromptOptions{customPrompt: Maybe<&2,String>,forceSystemPrompt: Maybe<&2,String>,selectedTools: List<&2,String>,toolSnippets: Record.Record<String>,toolGuidelines: Record.Record<List<&2,String>>,promptGuidelines: List<&2,String>,appendSystemPrompt: String,sections: Record.Record<String>,cwd: String,contextFiles: List<&2,ContextFile>,skills: List<&2,Skills.Skill>}

def SystemPromptSections() -> Data: Record.Record<String>
type SystemPromptState is Data:
  SystemPromptState{content: String,sections: Maybe<&2,SystemPromptSections()>}
type Error is Data:
  InvalidSectionName{name: String}
def ResultOf(-A: Data) -> Data: Result<&2,&2,Error,A>

def defaults(cwd: String) -> BuildSystemPromptOptions:
  BuildSystemPromptOptions{None{},None{},None{},None{},None{},None{},None{},None{},cwd,None{},None{}}

def normalizeBuildSystemPromptOptions(input: BuildSystemPromptOptions) -> NormalizedBuildSystemPromptOptions:
  match input:
    case BuildSystemPromptOptions{custom,forced,tools,snippets,rules,guidelines,append,sections,cwd,files,skills}:
      NormalizedBuildSystemPromptOptions{custom,forced,
        Maybe.default(&2,List<&2,String>,tools,"read" <> "bash" <> "edit" <> "write" <> Nil{}),
        Maybe.default(&2,Record.Record<String>,snippets,Record.new(String)),
        Maybe.default(&2,Record.Record<List<&2,String>>,rules,Record.new(List<&2,String>)),
        Maybe.default(&2,List<&2,String>,guidelines,Nil{}),Maybe.default(&2,String,append,""),
        Maybe.default(&2,Record.Record<String>,sections,Record.new(String)),cwd,
        Maybe.default(&2,List<&2,ContextFile>,files,Nil{}),Maybe.default(&2,List<&2,Skills.Skill>,skills,Nil{})}

def trimStart(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{+code},+rest}:
      Bool.pick(Unit -> String,Space.whitespace(code),_ => trimStart(rest),_ => SCon{Chr{code},rest})(Unit{})

def trim(text: String) -> String: String.reverse(trimStart(String.reverse(trimStart(text))))

def contains(values: List<&2,String>,+value: String) -> Bool:
  match values:
    case Nil{}: False{}
    case first <> rest: Bool.pick(Unit -> Bool,Strings.equal(first,value),_ => True{},_ => contains(rest,value))(Unit{})

def normalizedRule(+rule: String,+rules: List<&2,String>) -> List<&2,String>:
  Bool.pick(List<&2,String>,String.is_empty(rule) || contains(rules,rule),rules,rule <> rules)

def addRules(values: List<&2,String>,rules: List<&2,String>) -> List<&2,String>:
  match values:
    case Nil{}: rules
    case value <> rest: addRules(rest,normalizedRule(trim(value),rules))

def toolRules(tools: List<&2,String>,+guidelines: Record.Record<List<&2,String>>,rules: List<&2,String>) -> List<&2,String>:
  match tools:
    case Nil{}: rules
    case name <> rest: toolRules(rest,guidelines,addRules(Maybe.default(&2,List<&2,String>,Record.get(List<&2,String>,guidelines,name),Nil{}),rules))

def shellRule(bash: Bool,powershell: Bool,search: Bool) -> List<&2,String>:
  match bash powershell search:
    case _ _ True{}: Nil{}
    case True{} True{} False{}: "Use bash or PowerShell for file operations like listing, searching, and finding files" <> Nil{}
    case True{} False{} False{}: "Use bash for file operations like ls, rg, find" <> Nil{}
    case False{} True{} False{}: "Use PowerShell for file operations like listing, searching, and finding files" <> Nil{}
    case _ _ _: Nil{}

def bulletRules(reversed: List<&2,String>,result: List<&2,String>) -> String:
  match reversed:
    case Nil{}: String.join(result,"\n")
    case rule <> rest: bulletRules(rest,("- " ++ rule) <> result)

def buildRules(+tools: List<&2,String>,guidelines: Record.Record<List<&2,String>>,prompt: List<&2,String>) -> String:
  initial = shellRule(contains(tools,"bash"),contains(tools,"powershell"),contains(tools,"grep") || contains(tools,"find") || contains(tools,"ls"))
  bulletRules(addRules("Be concise in your responses" <> "Show file paths clearly when working with files" <> Nil{},addRules(prompt,toolRules(tools,guidelines,initial))),Nil{})

def toolLine(name: String,snippet: Maybe<&2,String>,result: List<&2,String>) -> List<&2,String>:
  match snippet:
    case None{}: result
    case Some{""}: result
    case Some{text}: ("- " ++ name ++ ": " ++ text) <> result

def toolsText(tools: List<&2,String>,+snippets: Record.Record<String>,+reversed: List<&2,String>) -> String:
  match tools:
    case Nil{}:
      Bool.pick(String,List.is_empty(&2,String,reversed),"(none)",String.join(List.reverse(&2,String,reversed),"\n")) ++ "\n\nIn addition to the tools above, you may have access to other custom tools depending on the project."
    case +name <> rest: toolsText(rest,snippets,toolLine(name,Record.get(String,snippets,name),reversed))

def projectContext(files: List<&2,ContextFile>,reversed: List<&2,String>) -> String:
  match files:
    case Nil{}: String.join("Project-specific instructions and guidelines:" <> List.reverse(&2,String,reversed),"\n\n")
    case ContextFile{path,content} <> rest:
      projectContext(rest,("<project_instructions path=\"" ++ path ++ "\">\n" ++ content ++ "\n</project_instructions>") <> reversed)

def workingDirectory(value: String,reversed: String) -> String:
  match value:
    case SNil{}: String.reverse(reversed)
    case SCon{'\\',rest}: workingDirectory(rest,SCon{'/',reversed})
    case SCon{char,rest}: workingDirectory(rest,SCon{char,reversed})

def letter(+code: U32) -> Bool: U32.is_ge(code,97) && U32.is_le(code,122)
def nameRest(value: String) -> Bool:
  match value:
    case SNil{}: True{}
    case SCon{Chr{+code},rest}:
      Bool.pick(Unit -> Bool,letter(code) || (U32.is_ge(code,48) && U32.is_le(code,57)) || U32.is_eq(code,95) || U32.is_eq(code,45),_ => nameRest(rest),_ => False{})(Unit{})
def validName(+name: String) -> Bool:
  match name:
    case SNil{}: False{}
    case SCon{Chr{code},rest}: letter(code) && nameRest(rest) && Bool.not(Strings.equal(name,"preamble"))
def invalidName(fields: List<&2,Record.Property<String>>) -> Maybe<&2,String>:
  match fields:
    case Nil{}: None{}
    case Record.Property{+name,_} <> rest:
      Bool.pick(Unit -> Maybe<&2,String>,validName(name),_ => invalidName(rest),_ => Some{name})(Unit{})

def putNonEmpty(name: String,+content: String,+sections: SystemPromptSections()) -> SystemPromptSections():
  Bool.pick(Unit -> SystemPromptSections(),String.is_empty(content),_ => sections,_ => Record.set(String,sections,name,content))(Unit{})

def customSections(fields: List<&2,Record.Property<String>>,sections: SystemPromptSections()) -> SystemPromptSections():
  match fields:
    case Nil{}: sections
    case Record.Property{name,content} <> rest: customSections(rest,putNonEmpty(name,content,sections))

def withContext(files: List<&2,ContextFile>,sections: SystemPromptSections()) -> SystemPromptSections():
  match files:
    case Nil{}: sections
    case first <> rest: Record.set(String,sections,"project_context",projectContext(first <> rest,Nil{}))

def withSkills(+tools: List<&2,String>,skills: List<&2,Skills.Skill>,+sections: SystemPromptSections()) -> SystemPromptSections():
  +read = contains(tools,"read")
  Bool.pick(Unit -> SystemPromptSections(),read || contains(tools,"bash"),
    _ => putNonEmpty("skills",trim(Skills.formatSkillsForPrompt(skills,Bool.pick(Skills.FileReadTool,read,Skills.Read{},Skills.Bash{}))),sections),
    _ => sections)(Unit{})

def documentation(paths: DocumentationPaths) -> String:
  match paths:
    case DocumentationPaths{readme,docs,examples}: "Pi documentation (read only when the user asks about pi itself, its SDK, extensions, themes, skills, or TUI):\n- Main documentation: " ++ readme ++ "\n- Additional docs: " ++ docs ++ "\n- Examples: " ++ examples ++ " (extensions, custom tools, SDK)\n- When reading pi docs or examples, resolve docs/... under Additional docs and examples/... under Examples, not the current working directory\n- When asked about: extensions (docs/extensions.md, examples/extensions/), themes (docs/themes.md), skills (docs/skills.md), prompt templates (docs/prompt-templates.md), TUI components (docs/tui.md), keybindings (docs/keybindings.md), SDK integrations (docs/sdk.md), custom providers (docs/custom-provider.md), adding models (docs/models.md), pi packages (docs/packages.md), environment variables (docs/environment-variables.md)\n- When working on pi topics, read the docs and examples, and follow .md cross-references before implementing\n- Always read pi .md files completely and follow links to related docs (e.g., tui.md for TUI API details)"

def initialSections(paths: DocumentationPaths,custom: Maybe<&2,String>,tools: List<&2,String>,snippets: Record.Record<String>,guidelines: Record.Record<List<&2,String>>,promptGuidelines: List<&2,String>) -> SystemPromptSections():
  match custom:
    case Some{SCon{first,rest}}: Record.Record{Record.Property{"preamble",SCon{first,rest}} <> Nil{}}
    case _:
      +tools = tools
      Record.Record{
        Record.Property{"preamble","You are an expert coding assistant operating inside pi, a coding agent harness. You help users by reading files, executing commands, editing code, and writing new files."} <>
        Record.Property{"tools",toolsText(tools,snippets,Nil{})} <>
        Record.Property{"rules",buildRules(tools,guidelines,promptGuidelines)} <>
        Record.Property{"docs",documentation(paths)} <> Nil{}}

def wrapped(fields: List<&2,Record.Property<String>>,reversed: List<&2,Record.Property<String>>) -> SystemPromptSections():
  match fields:
    case Nil{}: Record.Record{List.reverse(&2,Record.Property<String>,reversed)}
    case Record.Property{+name,+content} <> rest:
      value = Bool.pick(String,Strings.equal(name,"preamble"),content,"<" ++ name ++ ">\n" ++ content ++ "\n</" ++ name ++ ">")
      wrapped(rest,Record.Property{name,value} <> reversed)

def buildNormalized(paths: DocumentationPaths,options: NormalizedBuildSystemPromptOptions) -> SystemPromptSections():
  match options:
    case NormalizedBuildSystemPromptOptions{custom,_,+tools,snippets,rules,guidelines,append,sections,cwd,files,skills}:
      initial = initialSections(paths,custom,tools,snippets,rules,guidelines)
      context = withContext(files,putNonEmpty("addendum",append,initial))
      assembled = Record.set(String,withSkills(tools,skills,context),"cwd",workingDirectory(cwd,""))
      wrapped(Record.entries(String,customSections(Record.entries(String,sections),assembled)),Nil{})

def checkedSections(paths: DocumentationPaths,options: NormalizedBuildSystemPromptOptions,invalid: Maybe<&2,String>) -> ResultOf(SystemPromptSections()):
  match invalid:
    case Some{name}: Fail{InvalidSectionName{name}}
    case None{}: Done{buildNormalized(paths,options)}

def validatedSections(paths: DocumentationPaths,+options: NormalizedBuildSystemPromptOptions) -> ResultOf(SystemPromptSections()):
  match options:
    case NormalizedBuildSystemPromptOptions{_,_,_,_,_,_,_,sections,_,_,_}:
      checkedSections(paths,options,invalidName(Record.entries(String,sections)))

def buildSystemPromptSections(paths: DocumentationPaths,input: BuildSystemPromptOptions) -> ResultOf(SystemPromptSections()):
  validatedSections(paths,normalizeBuildSystemPromptOptions(input))

def stateResult(result: ResultOf(SystemPromptSections())) -> ResultOf(SystemPromptState):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{sections}: Done{SystemPromptState{"",Some{sections}}}

def buildSystemPromptState(paths: DocumentationPaths,+input: BuildSystemPromptOptions) -> ResultOf(SystemPromptState):
  match input:
    case BuildSystemPromptOptions{_,Some{forced},_,_,_,_,_,_,_,_,_}: Done{SystemPromptState{forced,None{}}}
    case _: stateResult(buildSystemPromptSections(paths,input))

def sectionUpdates(fields: List<&2,Record.Property<String>>,reversed: List<&2,Record.Property<Maybe<&2,String>>>) -> Record.Record<Maybe<&2,String>>:
  match fields:
    case Nil{}: Record.Record{List.reverse(&2,Record.Property<Maybe<&2,String>>,reversed)}
    case Record.Property{name,value} <> rest: sectionUpdates(rest,Record.Property{name,Some{value}} <> reversed)

def optionalSections(sections: Maybe<&2,SystemPromptSections()>) -> Maybe<&2,Record.Record<Maybe<&2,String>>>:
  match sections:
    case None{}: None{}
    case Some{sections}: Some{sectionUpdates(Record.entries(String,sections),Nil{})}

def systemMessage(state: SystemPromptState) -> Ai.SystemMessage<Unit>:
  match state:
    case SystemPromptState{content,sections}: Ai.SystemMessage{Ai.SystemText{content},optionalSections(sections),None{},None{},F.fromU32(0)}

def promptText(result: ResultOf(SystemPromptState)) -> ResultOf(String):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{state}: Done{AiText.renderComplete(Unit,systemMessage(state))}

def buildSystemPrompt(paths: DocumentationPaths,input: BuildSystemPromptOptions) -> ResultOf(String):
  promptText(buildSystemPromptState(paths,input))

def sameSection(previous: Maybe<&2,Maybe<&2,String>>,current: String) -> Bool:
  match previous:
    case Some{Some{value}}: Strings.equal(value,current)
    case _: False{}

def changed(fields: List<&2,Record.Property<String>>,+previous: Record.Record<Maybe<&2,String>>,patch: List<&2,Record.Property<Maybe<&2,String>>>) -> List<&2,Record.Property<Maybe<&2,String>>>:
  match fields:
    case Nil{}: patch
    case Record.Property{+name,+text} <> rest:
      +patch = patch
      changed(rest,previous,Bool.pick(List<&2,Record.Property<Maybe<&2,String>>>,sameSection(Record.get(Maybe<&2,String>,previous,name),text),patch,Record.Property{name,Some{text}} <> patch))

def removed(fields: List<&2,Record.Property<Maybe<&2,String>>>,+current: SystemPromptSections(),patch: List<&2,Record.Property<Maybe<&2,String>>>) -> List<&2,Record.Property<Maybe<&2,String>>>:
  match fields:
    case Nil{}: patch
    case Record.Property{+name,_} <> rest:
      +patch = patch
      removed(rest,current,Bool.pick(List<&2,Record.Property<Maybe<&2,String>>>,Maybe.is_none(&2,String,Record.get(String,current,name)),Record.Property{name,None{}} <> patch,patch))

def patchResult(reversed: List<&2,Record.Property<Maybe<&2,String>>>) -> Maybe<&2,Record.Record<Maybe<&2,String>>>:
  match reversed:
    case Nil{}: None{}
    case first <> rest: Some{Record.Record{List.reverse(&2,Record.Property<Maybe<&2,String>>,first <> rest)}}

def diffSystemPromptSections(+previous: Record.Record<Maybe<&2,String>>,+current: SystemPromptSections()) -> Maybe<&2,Record.Record<Maybe<&2,String>>>:
  patchResult(removed(Record.entries(Maybe<&2,String>,previous),current,changed(Record.entries(String,current),previous,Nil{})))
