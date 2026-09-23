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

def normalizeSessionName(value: String) -> Maybe<&2,String>:
  +name = String.reverse(Space.trimStart(String.reverse(Space.trimStart(value))))
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

# printHelp without extension flags; the port has no extension registry yet.
# The text is the pinned upstream template with pi's default identity.
def helpLines(+appName: String) -> List<&2, String>:
  [appName ++ " - AI coding assistant with read, bash, edit, write tools", "", "Usage:", "  " ++ appName ++ " [options] [--] [@files...] [messages...]", "", "Commands:", "  " ++ appName ++ " install <source> [-l]     Install extension source and add to settings", "  " ++ appName ++ " remove <source> [-l]      Remove extension source from settings", "  " ++ appName ++ " uninstall <source> [-l]   Alias for remove", "  " ++ appName ++ " update [source|self|pi]   Update pi, extensions, or model catalogs", "  " ++ appName ++ " list                      List installed extensions from settings", "  " ++ appName ++ " config [-l]               Open TUI to enable/disable package resources (Tab switches scope)", "  " ++ appName ++ " auth <command>            Print credentials or check provider readiness", "  " ++ appName ++ " <command> --help          Show help for install/remove/uninstall/update/list/config/auth", "", "Options:", "  --provider <name>              Provider name (default: google)", "  --model <pattern>              Model pattern or ID (supports \"provider/id\" and optional \":<thinking>\")", "  --api-key <key>                API key (defaults to env vars)", "  --system-prompt <text>         System prompt (default: coding assistant prompt)", "  --append-system-prompt <text>  Append text or file contents to the system prompt (can be used multiple times)", "  --mode <mode>                  Output mode: text (default), json, or rpc", "  --print, -p                    Non-interactive mode: process prompt and exit", "  --continue, -c                 Continue previous session", "  --resume, -r                   Select a session to resume", "  --session <path|id>            Use specific session file or partial UUID", "  --session-id <id>              Use exact project session ID, creating it if missing", "  --fork <path|id>               Fork specific session file or partial UUID into a new session", "  --session-dir <dir>            Directory for session storage and lookup", "  --no-session                   Don't save session (ephemeral)", "  --name, -n <name>              Set session display name", "  --models <patterns>            Comma-separated model patterns for Ctrl+P cycling", "                                 Supports globs (anthropic/*, *sonnet*) and fuzzy matching", "  --no-tools, -nt                Disable all tools by default (built-in and extension)", "  --no-builtin-tools, -nbt       Disable built-in tools by default but keep extension/custom tools enabled", "  --tools, -t <tools>            Comma-separated allowlist of tool names to enable", "                                 Applies to built-in, extension, and custom tools", "  --exclude-tools, -xt <tools>   Comma-separated denylist of tool names to disable", "                                 Applies to built-in, extension, and custom tools", "  --thinking <level>             Set thinking level: off, minimal, low, medium, high, xhigh, max", "  --extension, -e <path>         Load an extension file (can be used multiple times)", "  --no-extensions, -ne           Disable extension discovery (explicit -e paths still work)", "  --skill <path>                 Load a skill file or directory (can be used multiple times)", "  --no-skills, -ns               Disable skills discovery and loading", "  --prompt-template <path>       Load a prompt template file or directory (can be used multiple times)", "  --no-prompt-templates, -np     Disable prompt template discovery and loading", "  --theme <path>                 Load a theme file or directory (can be used multiple times)", "  --use-theme <name[/name]>      Set the initial interactive theme for this run", "  --no-themes                    Disable theme discovery and loading", "  --no-context-files, -nc        Disable AGENTS.md and CLAUDE.md discovery and loading", "  --export <file>                Export session file to HTML and exit", "  --list-models [search]         List available models (with optional fuzzy search)", "  --verbose                      Force verbose startup (overrides quietStartup setting)", "  --tui-mode <mode>              TUI mode: regular (default) or fullscreen", "  --approve, -a                  Trust project-local files for this run", "  --no-approve, -na              Ignore project-local files for this run", "  --offline                      Disable startup network operations (same as PI_OFFLINE=1)", "  --                             End option parsing; treat remaining arguments as messages/files", "  --help, -h                     Show this help", "  --version, -v                  Show version number", "", "Extensions can register additional flags (e.g., --plan from plan-mode extension).", "", "Examples:", "  # Print a provider API key for an external client", "  " ++ appName ++ " auth print-api-key --provider openai", "", "  # Print an OAuth bearer token for an external client (refreshes if expired)", "  " ++ appName ++ " auth print-bearer-token --provider openai-codex", "", "  # Interactive mode", "  " ++ appName, "", "  # Interactive mode with initial prompt", "  " ++ appName ++ " \"List all .ts files in src/\"", "", "  # Include files in initial message", "  " ++ appName ++ " @prompt.md @image.png \"What color is the sky?\"", "", "  # Non-interactive mode (process and exit)", "  " ++ appName ++ " -p \"List all .ts files in src/\"", "", "  # Prompt beginning with a dash", "  " ++ appName ++ " -p -- \"- Summarize these points\"", "", "  # Multiple messages (interactive)", "  " ++ appName ++ " \"Read package.json\" \"What dependencies do we have?\"", "", "  # Continue previous session", "  " ++ appName ++ " --continue \"What did we discuss?\"", "", "  # Start a named session", "  " ++ appName ++ " --name \"Refactor auth module\"", "", "  # Use different model", "  " ++ appName ++ " --provider openai --model gpt-4o-mini \"Help me refactor this code\"", "", "  # Use model with provider prefix (no --provider needed)", "  " ++ appName ++ " --model openai/gpt-4o \"Help me refactor this code\"", "", "  # Use model with thinking level shorthand", "  " ++ appName ++ " --model sonnet:high \"Solve this complex problem\"", "", "  # Limit model cycling to specific models", "  " ++ appName ++ " --models claude-sonnet,claude-haiku,gpt-4o", "", "  # Limit to a specific provider with glob pattern", "  " ++ appName ++ " --models \"github-copilot/*\"", "", "  # Cycle models with fixed thinking levels", "  " ++ appName ++ " --models sonnet:high,haiku:low", "", "  # Start with a specific thinking level", "  " ++ appName ++ " --thinking high \"Solve this complex problem\"", "", "  # Read-only mode (no file modifications possible)", "  " ++ appName ++ " --tools read,grep,find,ls -p \"Review the code in src/\"", "", "  # Disable one tool while keeping the rest available", "  " ++ appName ++ " --exclude-tools ask_question", "", "  # Export a session file to HTML", "  " ++ appName ++ " --export ~/.pi/agent/sessions/--path--/session.jsonl", "  " ++ appName ++ " --export session.jsonl output.html", "", "Environment Variables:", "  ANTHROPIC_AUTH_TOKEN             - Anthropic bearer auth token", "  ANTHROPIC_API_KEY                - Anthropic Claude API key", "  ANTHROPIC_OAUTH_TOKEN            - Anthropic OAuth token (alternative to API key)", "  ANT_LING_API_KEY                 - Ant Ling API key", "  OPENAI_API_KEY                   - OpenAI GPT API key", "  AZURE_OPENAI_API_KEY             - Azure OpenAI API key", "  AZURE_OPENAI_BASE_URL            - Azure OpenAI/Cognitive Services base URL (e.g. https://{resource}.openai.azure.com)", "  AZURE_OPENAI_RESOURCE_NAME       - Azure OpenAI resource name (alternative to base URL)", "  AZURE_OPENAI_API_VERSION         - Azure OpenAI API version (default: v1)", "  AZURE_OPENAI_DEPLOYMENT_NAME_MAP - Azure OpenAI model=deployment map (comma-separated)", "  DEEPSEEK_API_KEY                 - DeepSeek API key", "  NVIDIA_API_KEY                   - NVIDIA NIM API key", "  GEMINI_API_KEY                   - Google Gemini API key", "  GROQ_API_KEY                     - Groq API key", "  CEREBRAS_API_KEY                 - Cerebras API key", "  XAI_API_KEY                      - xAI Grok API key", "  FIREWORKS_API_KEY                - Fireworks API key", "  TOGETHER_API_KEY                 - Together AI API key", "  BASETEN_API_KEY                  - Baseten API key", "  OPENROUTER_API_KEY               - OpenRouter API key", "  AI_GATEWAY_API_KEY               - Vercel AI Gateway API key", "  ZAI_API_KEY                      - ZAI Coding Plan API key (Global)", "  ZAI_CODING_CN_API_KEY            - ZAI Coding Plan API key (China)", "  MISTRAL_API_KEY                  - Mistral API key", "  MINIMAX_API_KEY                  - MiniMax API key", "  MOONSHOT_API_KEY                 - Moonshot AI API key", "  OPENCODE_API_KEY                 - OpenCode Zen/OpenCode Go API key", "  KIMI_API_KEY                     - Kimi For Coding API key", "  CLOUDFLARE_API_KEY               - Cloudflare API token (Workers AI and AI Gateway)", "  CLOUDFLARE_ACCOUNT_ID            - Cloudflare account id (required for both)", "  CLOUDFLARE_GATEWAY_ID            - Cloudflare AI Gateway slug (required for AI Gateway)", "  QWEN_TOKEN_PLAN_API_KEY          - Qwen Token Plan API key (international region)", "  QWEN_TOKEN_PLAN_CN_API_KEY       - Qwen Token Plan API key (China region)", "  XIAOMI_API_KEY                   - Xiaomi MiMo API key (api.xiaomimimo.com billing)", "  XIAOMI_TOKEN_PLAN_CN_API_KEY     - Xiaomi MiMo Token Plan API key (China region)", "  XIAOMI_TOKEN_PLAN_AMS_API_KEY    - Xiaomi MiMo Token Plan API key (Amsterdam region)", "  XIAOMI_TOKEN_PLAN_SGP_API_KEY    - Xiaomi MiMo Token Plan API key (Singapore region)", "  AWS_PROFILE                      - AWS profile for Amazon Bedrock", "  AWS_ACCESS_KEY_ID                - AWS access key for Amazon Bedrock", "  AWS_SECRET_ACCESS_KEY            - AWS secret key for Amazon Bedrock", "  AWS_BEARER_TOKEN_BEDROCK         - Bedrock API key (bearer token)", "  AWS_REGION                       - AWS region for Amazon Bedrock (e.g., us-east-1)", "  PI_CODING_AGENT_DIR              - Config directory (default: ~/.pi/agent)", "  PI_CODING_AGENT_SESSION_DIR      - Session storage directory (overridden by --session-dir)", "  PI_PACKAGE_DIR                   - Override package directory (for Nix/Guix store paths)", "  PI_OFFLINE                       - Disable startup network operations when set to 1/true/yes", "  PI_TELEMETRY                     - Override install telemetry when set to 1/true/yes or 0/false/no", "  PI_SHARE_VIEWER_URL              - Base URL for /share command (default: https://pi.dev/session/)", "", "Built-in Tool Names:", "  read       - Read file contents", "  bash       - Execute bash commands", "  powershell - Execute PowerShell commands on Windows", "  edit       - Edit files with find/replace", "  write      - Write files (creates/overwrites)", "  grep       - Search file contents (read-only, off by default)", "  find       - Find files by glob pattern (read-only, off by default)", "  ls         - List directory contents (read-only, off by default)", ""]

def helpText(appName: String) -> String:
  String.join(helpLines(appName), "\n")
