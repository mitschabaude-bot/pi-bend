import Base
import ../../../ai/src/types.bend as Ai
import ../../../runtime/src/record.bend as Record
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/text.bend as Space

type Mode is Data:
  Text{}
  Json{}
  Rpc{}
type TuiMode is Data:
  Regular{}
  Fullscreen{}
type ListModels is Data:
  AllModels{}
  SearchModels{pattern: String}
type FlagValue is Data:
  BooleanFlag{value: Bool}
  StringFlag{value: String}
type Diagnostic is Data:
  Warning{message: String}
  Error{message: String}

# Absent values remain optional, including explicit false project approval.
# Unknown extension flags are ordinary typed dictionary entries, not JS objects.
type Args is Data:
  Args{provider: Maybe<&2,String>, model: Maybe<&2,String>, apiKey: Maybe<&2,String>, systemPrompt: Maybe<&2,String>, appendSystemPrompt: Maybe<&2,List<&2,String>>, thinking: Maybe<&2,Ai.ModelThinkingLevel>, continue: Maybe<&2,Bool>, resume: Maybe<&2,Bool>, help: Maybe<&2,Bool>, version: Maybe<&2,Bool>, mode: Maybe<&2,Mode>, name: Maybe<&2,String>, noSession: Maybe<&2,Bool>, session: Maybe<&2,String>, sessionId: Maybe<&2,String>, fork: Maybe<&2,String>, sessionDir: Maybe<&2,String>, models: Maybe<&2,List<&2,String>>, tools: Maybe<&2,List<&2,String>>, excludeTools: Maybe<&2,List<&2,String>>, noTools: Maybe<&2,Bool>, noBuiltinTools: Maybe<&2,Bool>, extensions: Maybe<&2,List<&2,String>>, noExtensions: Maybe<&2,Bool>, print: Maybe<&2,Bool>, export: Maybe<&2,String>, noSkills: Maybe<&2,Bool>, skills: Maybe<&2,List<&2,String>>, promptTemplates: Maybe<&2,List<&2,String>>, noPromptTemplates: Maybe<&2,Bool>, themes: Maybe<&2,List<&2,String>>, useTheme: Maybe<&2,String>, noThemes: Maybe<&2,Bool>, noContextFiles: Maybe<&2,Bool>, listModels: Maybe<&2,ListModels>, offline: Maybe<&2,Bool>, tuiMode: Maybe<&2,TuiMode>, verbose: Maybe<&2,Bool>, projectTrustOverride: Maybe<&2,Bool>, messages: List<&2,String>, fileArgs: List<&2,String>, unknownFlags: Record.Record<FlagValue>, diagnostics: List<&2,Diagnostic>}

type TextField is Data:
  ProviderField{}
  ModelField{}
  ApiKeyField{}
  SystemPromptField{}
  NameField{}
  SessionField{}
  SessionIdField{}
  ForkField{}
  SessionDirField{}
  ExportField{}
  UseThemeField{}

def sameTextField(left: TextField, right: TextField) -> Bool:
  match left right:
    case ProviderField{} ProviderField{}: True{}
    case ModelField{} ModelField{}: True{}
    case ApiKeyField{} ApiKeyField{}: True{}
    case SystemPromptField{} SystemPromptField{}: True{}
    case NameField{} NameField{}: True{}
    case SessionField{} SessionField{}: True{}
    case SessionIdField{} SessionIdField{}: True{}
    case ForkField{} ForkField{}: True{}
    case SessionDirField{} SessionDirField{}: True{}
    case ExportField{} ExportField{}: True{}
    case UseThemeField{} UseThemeField{}: True{}
    case _ _: False{}

type ListField is Data:
  ModelsField{}
  ToolsField{}
  ExcludeToolsField{}

def sameListField(left: ListField, right: ListField) -> Bool:
  match left right:
    case ModelsField{} ModelsField{}: True{}
    case ToolsField{} ToolsField{}: True{}
    case ExcludeToolsField{} ExcludeToolsField{}: True{}
    case _ _: False{}

type RepeatedField is Data:
  AppendSystemPromptField{}
  ExtensionsField{}
  SkillsField{}
  PromptTemplatesField{}
  ThemesField{}

def sameRepeatedField(left: RepeatedField, right: RepeatedField) -> Bool:
  match left right:
    case AppendSystemPromptField{} AppendSystemPromptField{}: True{}
    case ExtensionsField{} ExtensionsField{}: True{}
    case SkillsField{} SkillsField{}: True{}
    case PromptTemplatesField{} PromptTemplatesField{}: True{}
    case ThemesField{} ThemesField{}: True{}
    case _ _: False{}

type BoolField is Data:
  ContinueField{}
  ResumeField{}
  HelpField{}
  VersionField{}
  NoSessionField{}
  NoToolsField{}
  NoBuiltinToolsField{}
  NoExtensionsField{}
  PrintField{}
  NoSkillsField{}
  NoPromptTemplatesField{}
  NoThemesField{}
  NoContextFilesField{}
  OfflineField{}
  VerboseField{}
  ProjectTrustOverrideField{}

def sameBoolField(left: BoolField, right: BoolField) -> Bool:
  match left right:
    case ContinueField{} ContinueField{}: True{}
    case ResumeField{} ResumeField{}: True{}
    case HelpField{} HelpField{}: True{}
    case VersionField{} VersionField{}: True{}
    case NoSessionField{} NoSessionField{}: True{}
    case NoToolsField{} NoToolsField{}: True{}
    case NoBuiltinToolsField{} NoBuiltinToolsField{}: True{}
    case NoExtensionsField{} NoExtensionsField{}: True{}
    case PrintField{} PrintField{}: True{}
    case NoSkillsField{} NoSkillsField{}: True{}
    case NoPromptTemplatesField{} NoPromptTemplatesField{}: True{}
    case NoThemesField{} NoThemesField{}: True{}
    case NoContextFilesField{} NoContextFilesField{}: True{}
    case OfflineField{} OfflineField{}: True{}
    case VerboseField{} VerboseField{}: True{}
    case ProjectTrustOverrideField{} ProjectTrustOverrideField{}: True{}
    case _ _: False{}

# Occurrences are retained newest-first; Args is constructed only once.
type Option is Data:
  TextOption{field: TextField, value: String}
  ListOption{field: ListField, value: List<&2,String>}
  RepeatedOption{field: RepeatedField, value: String}
  BoolOption{field: BoolField, value: Bool}
  ModeOption{value: Mode}
  TuiOption{value: TuiMode}
  ThinkingOption{value: Ai.ModelThinkingLevel}
  ListModelsOption{value: ListModels}

type State is Data:
  State{options: List<&2,Option>, messages: List<&2,String>, files: List<&2,String>, unknown: Record.Record<FlagValue>, diagnostics: List<&2,Diagnostic>}

def emit(option: Option, state: State) -> State:
  match state:
    case State{options,messages,files,unknown,diagnostics}: State{option <> options,messages,files,unknown,diagnostics}

def diagnose(diagnostic: Diagnostic, state: State) -> State:
  match state:
    case State{options,messages,files,unknown,diagnostics}: State{options,messages,files,unknown,diagnostic <> diagnostics}

def positional(value: String, state: State) -> State:
  match value state:
    case SCon{'@',path} State{options,messages,files,unknown,diagnostics}: State{options,messages,path <> files,unknown,diagnostics}
    case message State{options,messages,files,unknown,diagnostics}: State{options,message <> messages,files,unknown,diagnostics}

def unknownFlag(name: String,value: FlagValue,state: State) -> State:
  match state:
    case State{options,messages,files,unknown,diagnostics}: State{options,messages,files,Record.set(FlagValue,unknown,name,value),diagnostics}

def getText(+field: TextField,options: List<&2,Option>) -> Maybe<&2,String>:
  match options:
    case Nil{}: None{}
    case TextOption{key,value} <> rest:
      Bool.pick(Unit -> Maybe<&2,String>,sameTextField(field,key),_ => Some{value},_ => getText(field,rest))(Unit{})
    case _ <> rest: getText(field,rest)

def getList(+field: ListField,options: List<&2,Option>) -> Maybe<&2,List<&2,String>>:
  match options:
    case Nil{}: None{}
    case ListOption{key,value} <> rest:
      Bool.pick(Unit -> Maybe<&2,List<&2,String>>,sameListField(field,key),_ => Some{value},_ => getList(field,rest))(Unit{})
    case _ <> rest: getList(field,rest)

def getBool(+field: BoolField,options: List<&2,Option>) -> Maybe<&2,Bool>:
  match options:
    case Nil{}: None{}
    case BoolOption{key,value} <> rest:
      Bool.pick(Unit -> Maybe<&2,Bool>,sameBoolField(field,key),_ => Some{value},_ => getBool(field,rest))(Unit{})
    case _ <> rest: getBool(field,rest)

def repeated(+field: RepeatedField,options: List<&2,Option>,+values: List<&2,String>) -> Maybe<&2,List<&2,String>>:
  match options:
    case Nil{}: Bool.pick(Maybe<&2,List<&2,String>>,List.is_empty(&2,String,values),None{},Some{values})
    case RepeatedOption{key,value} <> rest:
      repeated(field,rest,Bool.pick(List<&2,String>,sameRepeatedField(field,key),value <> values,values))
    case _ <> rest: repeated(field,rest,values)

def getMode(options: List<&2,Option>) -> Maybe<&2,Mode>:
  match options:
    case Nil{}: None{}
    case ModeOption{value} <> _: Some{value}
    case _ <> rest: getMode(rest)

def getTui(options: List<&2,Option>) -> Maybe<&2,TuiMode>:
  match options:
    case Nil{}: None{}
    case TuiOption{value} <> _: Some{value}
    case _ <> rest: getTui(rest)

def getThinking(options: List<&2,Option>) -> Maybe<&2,Ai.ModelThinkingLevel>:
  match options:
    case Nil{}: None{}
    case ThinkingOption{value} <> _: Some{value}
    case _ <> rest: getThinking(rest)

def getListModels(options: List<&2,Option>) -> Maybe<&2,ListModels>:
  match options:
    case Nil{}: None{}
    case ListModelsOption{value} <> _: Some{value}
    case _ <> rest: getListModels(rest)

def materialize(state: State) -> Args:
  match state:
    case State{+options,messages,files,unknown,diagnostics}:
      Args{
        getText(ProviderField{},options),
        getText(ModelField{},options),
        getText(ApiKeyField{},options),
        getText(SystemPromptField{},options),
        repeated(AppendSystemPromptField{},options,Nil{}),
        getThinking(options),
        getBool(ContinueField{},options),
        getBool(ResumeField{},options),
        getBool(HelpField{},options),
        getBool(VersionField{},options),
        getMode(options),
        getText(NameField{},options),
        getBool(NoSessionField{},options),
        getText(SessionField{},options),
        getText(SessionIdField{},options),
        getText(ForkField{},options),
        getText(SessionDirField{},options),
        getList(ModelsField{},options),
        getList(ToolsField{},options),
        getList(ExcludeToolsField{},options),
        getBool(NoToolsField{},options),
        getBool(NoBuiltinToolsField{},options),
        repeated(ExtensionsField{},options,Nil{}),
        getBool(NoExtensionsField{},options),
        getBool(PrintField{},options),
        getText(ExportField{},options),
        getBool(NoSkillsField{},options),
        repeated(SkillsField{},options,Nil{}),
        repeated(PromptTemplatesField{},options,Nil{}),
        getBool(NoPromptTemplatesField{},options),
        repeated(ThemesField{},options,Nil{}),
        getText(UseThemeField{},options),
        getBool(NoThemesField{},options),
        getBool(NoContextFilesField{},options),
        getListModels(options),
        getBool(OfflineField{},options),
        getTui(options),
        getBool(VerboseField{},options),
        getBool(ProjectTrustOverrideField{},options),
        List.reverse(&2,String,messages),List.reverse(&2,String,files),unknown,List.reverse(&2,Diagnostic,diagnostics)}

# Prefix decisions inspect only the first few characters, even for long prompts.
def optionToken(value: String) -> Bool:
  match value:
    case SCon{'-',_}: True{}
    case _: False{}

def valueToken(value: String) -> Bool:
  match value:
    case SCon{'-',_}: False{}
    case SCon{'@',_}: False{}
    case _: True{}

def printToken(value: String) -> Bool:
  match value:
    case SCon{'-',SCon{'-',SCon{'-',_}}}: True{}
    case SCon{'-',_}: False{}
    case SCon{'@',_}: False{}
    case _: True{}

def trimStart(value: String) -> String:
  match value:
    case SNil{}: ""
    case SCon{Chr{+code},+rest}:
      Bool.pick(Unit -> String,Space.whitespace(code),_ => trimStart(rest),_ => SCon{Chr{code},rest})(Unit{})

def normalizeSessionName(value: String) -> Maybe<&2,String>:
  +name = String.reverse(trimStart(String.reverse(trimStart(value))))
  Bool.pick(Maybe<&2,String>,Strings.equal(name,""),None{},Some{name})

def listValues(values: List<&2,String>,+keepEmpty: Bool,+result: List<&2,String>) -> List<&2,String>:
  match values:
    case Nil{}: List.reverse(&2,String,result)
    case value <> rest:
      +trimmed = Maybe.default(&2,String,normalizeSessionName(value),"")
      listValues(rest,keepEmpty,Bool.pick(List<&2,String>,keepEmpty || Bool.not(Strings.equal(trimmed,"")),trimmed <> result,result))

def thinkingLevel(value: String) -> Maybe<&2,Ai.ModelThinkingLevel>:
  match value:
    case "off": Some{Ai.Off{}}
    case "minimal": Some{Ai.Thinking{Ai.Minimal{}}}
    case "low": Some{Ai.Thinking{Ai.Low{}}}
    case "medium": Some{Ai.Thinking{Ai.Medium{}}}
    case "high": Some{Ai.Thinking{Ai.High{}}}
    case "xhigh": Some{Ai.Thinking{Ai.XHigh{}}}
    case "max": Some{Ai.Thinking{Ai.Max{}}}
    case _: None{}

def isValidThinkingLevel(value: String) -> Bool:
  Bool.not(Maybe.is_none(&2,Ai.ModelThinkingLevel,thinkingLevel(value)))

type Command is Data:
  Switch{field: BoolField,value: Bool}
  TakeText{field: TextField}
  TakeList{field: ListField,keepEmpty: Bool}
  Append{field: RepeatedField}
  OutputMode{}
  Thinking{}
  Tui{}
  Theme{}
  Print{}
  Models{}
  Other{}

def command(arg: String) -> Command:
  match arg:
    case "--provider": TakeText{ProviderField{}}
    case "--model": TakeText{ModelField{}}
    case "--api-key": TakeText{ApiKeyField{}}
    case "--system-prompt": TakeText{SystemPromptField{}}
    case "--name": TakeText{NameField{}}
    case "--session": TakeText{SessionField{}}
    case "--session-id": TakeText{SessionIdField{}}
    case "--fork": TakeText{ForkField{}}
    case "--session-dir": TakeText{SessionDirField{}}
    case "--export": TakeText{ExportField{}}
    case "-n": TakeText{NameField{}}
    case "--models": TakeList{ModelsField{},True{}}
    case "--tools": TakeList{ToolsField{},False{}}
    case "--exclude-tools": TakeList{ExcludeToolsField{},False{}}
    case "-t": TakeList{ToolsField{},False{}}
    case "-xt": TakeList{ExcludeToolsField{},False{}}
    case "--append-system-prompt": Append{AppendSystemPromptField{}}
    case "--extension": Append{ExtensionsField{}}
    case "--skill": Append{SkillsField{}}
    case "--prompt-template": Append{PromptTemplatesField{}}
    case "--theme": Append{ThemesField{}}
    case "-e": Append{ExtensionsField{}}
    case "--help": Switch{HelpField{},True{}}
    case "-h": Switch{HelpField{},True{}}
    case "--version": Switch{VersionField{},True{}}
    case "-v": Switch{VersionField{},True{}}
    case "--continue": Switch{ContinueField{},True{}}
    case "-c": Switch{ContinueField{},True{}}
    case "--resume": Switch{ResumeField{},True{}}
    case "-r": Switch{ResumeField{},True{}}
    case "--no-session": Switch{NoSessionField{},True{}}
    case "--no-tools": Switch{NoToolsField{},True{}}
    case "-nt": Switch{NoToolsField{},True{}}
    case "--no-builtin-tools": Switch{NoBuiltinToolsField{},True{}}
    case "-nbt": Switch{NoBuiltinToolsField{},True{}}
    case "--no-extensions": Switch{NoExtensionsField{},True{}}
    case "-ne": Switch{NoExtensionsField{},True{}}
    case "--no-skills": Switch{NoSkillsField{},True{}}
    case "-ns": Switch{NoSkillsField{},True{}}
    case "--no-prompt-templates": Switch{NoPromptTemplatesField{},True{}}
    case "-np": Switch{NoPromptTemplatesField{},True{}}
    case "--no-themes": Switch{NoThemesField{},True{}}
    case "--no-context-files": Switch{NoContextFilesField{},True{}}
    case "-nc": Switch{NoContextFilesField{},True{}}
    case "--offline": Switch{OfflineField{},True{}}
    case "--verbose": Switch{VerboseField{},True{}}
    case "--approve": Switch{ProjectTrustOverrideField{},True{}}
    case "-a": Switch{ProjectTrustOverrideField{},True{}}
    case "--no-approve": Switch{ProjectTrustOverrideField{},False{}}
    case "-na": Switch{ProjectTrustOverrideField{},False{}}
    case "--mode": OutputMode{}
    case "--thinking": Thinking{}
    case "--tui-mode": Tui{}
    case "--use-theme": Theme{}
    case "--print": Print{}
    case "-p": Print{}
    case "--list-models": Models{}
    case _: Other{}

# Unknown flags preserve the original boolean/string distinction for native
# extension registration. Only unknown long flags recognize equals syntax.
def equals(value: String,reversed: String) -> String & Maybe<&2,String>:
  match value:
    case SNil{}: (String.reverse(reversed),None{})
    case SCon{'=',rest}: (String.reverse(reversed),Some{rest})
    case SCon{char,rest}: equals(rest,SCon{char,reversed})

type Step is Data:
  Step{remaining: List<&2,String>, state: State}

def advance(args: List<&2,String>,state: State) -> Step: Step{args,state}

def unknown(pair: String & Maybe<&2,String>,args: List<&2,String>,+state: State) -> Step:
  match pair args:
    case Tuple{name,Some{value}} rest: advance(rest,unknownFlag(name,StringFlag{value},state))
    case Tuple{+name,None{}} +next <> +rest:
      Bool.pick(Unit -> Step,valueToken(next),
        _ => advance(rest,unknownFlag(name,StringFlag{next},state)),
        _ => advance(next <> rest,unknownFlag(name,BooleanFlag{True{}},state)))(Unit{})
    case Tuple{name,None{}} Nil{}: advance(Nil{},unknownFlag(name,BooleanFlag{True{}},state))

def other(arg: String,args: List<&2,String>,state: State) -> Step:
  match arg:
    case SCon{'-',SCon{'-',rest}}: unknown(equals(rest,""),args,state)
    case SCon{'-',rest}: advance(args,diagnose(Error{"Unknown option: -" ++ rest},state))
    case value: advance(args,positional(value,state))

def missing(arg: String,state: State) -> State:
  match arg:
    case "-n": diagnose(Error{"--name requires a value"},state)
    case value: diagnose(Error{value ++ " requires a value"},state)

def enumMode(value: String,state: State) -> State:
  match value:
    case "text": emit(ModeOption{Text{}},state)
    case "json": emit(ModeOption{Json{}},state)
    case "rpc": emit(ModeOption{Rpc{}},state)
    case value: diagnose(Error{"Invalid mode \"" ++ value ++ "\". Valid values: text, json, rpc"},state)

def enumThinking(value: String,level: Maybe<&2,Ai.ModelThinkingLevel>,state: State) -> State:
  match level:
    case Some{level}: emit(ThinkingOption{level},state)
    case None{}: diagnose(Warning{"Invalid thinking level \"" ++ value ++ "\". Valid values: off, minimal, low, medium, high, xhigh, max"},state)

def enumTui(value: String,state: State) -> State:
  match value:
    case "regular": emit(TuiOption{Regular{}},state)
    case "fullscreen": emit(TuiOption{Fullscreen{}},state)
    case value: diagnose(Error{"Invalid TUI mode \"" ++ value ++ "\". Valid values: regular, fullscreen"},state)

def enumValue(kind: Command,+value: String,state: State) -> State:
  match kind:
    case OutputMode{}: enumMode(value,state)
    case Thinking{}: enumThinking(value,thinkingLevel(value),state)
    case Tui{}: enumTui(value,state)
    case _: diagnose(Error{"Invalid enum option"},state)

def enumMissing(kind: Command,state: State) -> State:
  match kind:
    case OutputMode{}: diagnose(Error{"--mode requires text, json or rpc"},state)
    case Thinking{}: diagnose(Error{"--thinking requires a value"},state)
    case Tui{}: diagnose(Error{"--tui-mode requires regular or fullscreen"},state)
    case _: diagnose(Error{"Invalid enum option"},state)

def enumArgument(+kind: Command,args: List<&2,String>,+state: State) -> Step:
  match args:
    case Nil{}: advance(Nil{},enumMissing(kind,state))
    case +value <> +rest:
      Bool.pick(Unit -> Step,optionToken(value),
        _ => advance(value <> rest,enumMissing(kind,state)),
        _ => advance(rest,enumValue(kind,value,state)))(Unit{})

def dispatch(kind: Command,arg: String,args: List<&2,String>,+state: State) -> Step:
  match kind args:
    case Switch{field,value} rest: advance(rest,emit(BoolOption{field,value},state))
    case TakeText{field} value <> rest: advance(rest,emit(TextOption{field,value},state))
    case TakeList{field,empty} value <> rest: advance(rest,emit(ListOption{field,listValues(Strings.split(value,','),empty,Nil{})},state))
    case Append{field} value <> rest: advance(rest,emit(RepeatedOption{field,value},state))
    case TakeText{_} Nil{}: advance(Nil{},missing(arg,state))
    case TakeList{_,_} Nil{}: advance(Nil{},missing(arg,state))
    case Append{_} Nil{}: advance(Nil{},missing(arg,state))
    case Print{} +next <> +rest:
      +state = emit(BoolOption{PrintField{},True{}},state)
      Bool.pick(Unit -> Step,printToken(next),_ => advance(rest,positional(next,state)),_ => advance(next <> rest,state))(Unit{})
    case Print{} Nil{}: advance(Nil{},emit(BoolOption{PrintField{},True{}},state))
    case Models{} +next <> +rest:
      Bool.pick(Unit -> Step,valueToken(next),
        _ => advance(rest,emit(ListModelsOption{SearchModels{next}},state)),
        _ => advance(next <> rest,emit(ListModelsOption{AllModels{}},state)))(Unit{})
    case Models{} Nil{}: advance(Nil{},emit(ListModelsOption{AllModels{}},state))
    case Theme{} +next <> +rest:
      Bool.pick(Unit -> Step,optionToken(next),
        _ => advance(next <> rest,diagnose(Error{"--use-theme requires a theme name"},state)),
        _ => advance(rest,emit(TextOption{UseThemeField{},next},state)))(Unit{})
    case Theme{} Nil{}: advance(Nil{},diagnose(Error{"--use-theme requires a theme name"},state))
    case Other{} rest: other(arg,rest,state)
    case kind rest: enumArgument(kind,rest,state)

def positionals(args: List<&2,String>,state: State) -> State:
  match args:
    case Nil{}: state
    case arg <> rest: positionals(rest,positional(arg,state))

# Every step consumes at least the current token. The input length supplies
# the structural recursion bound while a step may consume one additional value.
def scan(remaining: Nat,step: Step) -> State:
  match remaining step:
    case _ Step{Nil{},state}: state
    case 0n Step{_,state}: state
    case 1n+n Step{+arg <> +rest,+state}:
      Bool.pick(Unit -> State,Strings.equal(arg,"--"),_ => positionals(rest,state),_ => scan(n,dispatch(command(arg),arg,rest,state)))(Unit{})

def parseArgs(+args: List<&2,String>) -> Args:
  materialize(scan(List.length(&2,String,args),Step{args,State{Nil{},Nil{},Nil{},Record.new(FlagValue),Nil{}}}))
