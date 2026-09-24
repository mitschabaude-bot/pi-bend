import Base
import ../../../runtime/src/text.bend as Text
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/utils/uuid.bend as Uuid
import ../../../agent/src/types.bend as Agent
import ../../../ai/src/utils/json.bend as Render
import ../../../ai/src/utils/schema-json.bend as SchemaJson
import ../../../runtime/src/json.bend as J
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/number-string.bend as NumberString
import ../../../runtime/src/u64.bend as W
import ../utils/paths.bend as Paths
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/file-lock.bend as Lock

# Sparse typed settings. Constructors express known values; JSON is confined to
# decoding, persistence, and uninterpreted fields preserved for other versions.


type TuiMode is Data:
  Regular{}
  Fullscreen{}

type FullscreenExitOutput is Data:
  Transcript{}
  ResumeHint{}

type ScrollViewScrollbar is Data:
  ScrollAuto{}
  ScrollAlways{}
  ScrollHidden{}

type DefaultProjectTrust is Data:
  Ask{}
  Always{}
  Never{}

type DoubleEscapeAction is Data:
  Fork{}
  Tree{}
  NoDoubleEscape{}

type TreeFilterMode is Data:
  DefaultFilter{}
  NoTools{}
  UserOnly{}
  LabeledOnly{}
  AllEntries{}

type MermaidRenderingMode is Data:
  MermaidOff{}
  MermaidFinal{}
  MermaidStreaming{}

type OutputPadding is Data:
  NoPadding{}
  OnePadding{}

type AutomaticBoolean is Data:
  Automatic{}
  Enabled{}
  Disabled{}

type TerminalImages is Data:
  ImageAuto{}
  Kitty{}
  Iterm2{}
  NoImages{}

type CompactionModelOverride is Data:
  CompactionModelOverride{reserveTokens: Maybe<&2,W.U64>,keepRecentTokens: Maybe<&2,W.U64>}

type CompactionSettings is Data:
  CompactionSettings{enabled: Maybe<&2,Bool>,reserveTokens: Maybe<&2,W.U64>,keepRecentTokens: Maybe<&2,W.U64>,modelOverrides: Maybe<&2,R.Record<CompactionModelOverride>>}

type BranchSummarySettings is Data:
  BranchSummarySettings{reserveTokens: Maybe<&2,W.U64>,skipPrompt: Maybe<&2,Bool>}

type ProviderRetrySettings is Data:
  ProviderRetrySettings{timeoutMs: Maybe<&2,W.U64>,maxRetries: Maybe<&2,W.U64>,maxRetryDelayMs: Maybe<&2,W.U64>}

type RetrySettings is Data:
  RetrySettings{enabled: Maybe<&2,Bool>,maxRetries: Maybe<&2,W.U64>,baseDelayMs: Maybe<&2,W.U64>,maxAgentDelayMs: Maybe<&2,W.U64>,provider: Maybe<&2,ProviderRetrySettings>}

type TerminalSettings is Data:
  TerminalSettings{showImages: Maybe<&2,Bool>,imageWidthCells: Maybe<&2,W.U64>,clearOnShrink: Maybe<&2,Bool>,showTerminalProgress: Maybe<&2,Bool>,hyperlinks: Maybe<&2,AutomaticBoolean>,images: Maybe<&2,TerminalImages>,trueColor: Maybe<&2,AutomaticBoolean>}

type ImageSettings is Data:
  ImageSettings{autoResize: Maybe<&2,Bool>,blockImages: Maybe<&2,Bool>}

type ThinkingBudgetsSettings is Data:
  ThinkingBudgetsSettings{minimal: Maybe<&2,W.U64>,low: Maybe<&2,W.U64>,medium: Maybe<&2,W.U64>,high: Maybe<&2,W.U64>}

type MarkdownSettings is Data:
  MarkdownSettings{codeBlockIndent: Maybe<&2,String>,mermaid: Maybe<&2,MermaidRenderingMode>}

type WarningSettings is Data:
  WarningSettings{anthropicExtraUsage: Maybe<&2,Bool>}

type PackageFilter is Data:
  PackageFilter{autoload: Maybe<&2,Bool>,extensions: Maybe<&2,List<&2,String>>,skills: Maybe<&2,List<&2,String>>,prompts: Maybe<&2,List<&2,String>>,themes: Maybe<&2,List<&2,String>>}

type PackageSource is Data:
  PackageName{source: String}
  FilteredPackage{source: String,filter: PackageFilter,unknown: R.Record<V.Value>}

type Setting is Data:
  LastChangelogVersion{value: String}
  DefaultProvider{value: String}
  DefaultModel{value: String}
  Theme{value: String}
  ExternalEditor{value: String}
  ShellPath{value: String}
  ShellCommandPrefix{value: String}
  TrackingId{value: String}
  SessionDir{value: String}
  HttpProxy{value: String}
  HideThinkingBlock{value: Bool}
  ShowCacheMissNotices{value: Bool}
  QuietStartup{value: Bool}
  CollapseChangelog{value: Bool}
  EnableInstallTelemetry{value: Bool}
  EnableAnalytics{value: Bool}
  EnableSkillCommands{value: Bool}
  ShowHardwareCursor{value: Bool}
  FullscreenCopyOnSelect{value: Bool}
  EditorPaddingX{value: W.U64}
  AutocompleteMaxVisible{value: W.U64}
  HttpIdleTimeoutMs{value: W.U64}
  WebsocketConnectTimeoutMs{value: W.U64}
  NpmCommand{value: List<&2,String>}
  Extensions{value: List<&2,String>}
  Skills{value: List<&2,String>}
  Prompts{value: List<&2,String>}
  Themes{value: List<&2,String>}
  EnabledModels{value: List<&2,String>}
  DefaultTools{value: List<&2,String>}
  DefaultThinkingLevel{value: Ai.ModelThinkingLevel}
  ModelThinkingLevels{value: R.Record<Ai.ModelThinkingLevel>}
  Transport{value: Ai.Transport}
  SteeringMode{value: Agent.QueueMode}
  FollowUpMode{value: Agent.QueueMode}
  Packages{value: List<&2,PackageSource>}
  DefaultProjectTrust{value: DefaultProjectTrust}
  DoubleEscapeAction{value: DoubleEscapeAction}
  TreeFilterMode{value: TreeFilterMode}
  OutputPad{value: OutputPadding}
  TuiMode{value: TuiMode}
  FullscreenExitOutput{value: FullscreenExitOutput}
  FullscreenScrollbar{value: ScrollViewScrollbar}
  Compaction{value: CompactionSettings}
  BranchSummary{value: BranchSummarySettings}
  Retry{value: RetrySettings}
  Terminal{value: TerminalSettings}
  Images{value: ImageSettings}
  ThinkingBudgets{value: ThinkingBudgetsSettings}
  Markdown{value: MarkdownSettings}
  Warnings{value: WarningSettings}

type Settings is Data:
  Settings{fields: R.Record<Setting>,unknown: R.Record<V.Value>}
type Error is Data:
  InvalidJson{cause: J.ParseError}
  InvalidSetting{cause: J.Error}
  DuplicateSetting{path: String}
  UntrustedProject{}
  StorageFailure{message: String}
  FileFailure{cause: FS.Error}
  InvalidEncoding{cause: Utf8.Error}
  LockFailure{cause: Lock.Error}
  CleanupFailure{cause: Error,cleanup: Error}
def Outcome(-A: Data) -> Data: Result<&2,&2,Error,A>
def empty() -> Settings: Settings{R.new(Setting),R.new(V.Value)}
def boolean(value: V.Value) -> Result<&2,&2,J.Error,Bool>:
  match value:
    case V.Boolean{value}: Done{value}
    case _: Fail{J.WrongType{Nil{},"boolean"}}
def countMinimum(+a: W.U64,+b: W.U64) -> W.U64: Bool.pick(W.U64,W.atLeast(W.compare(a,b)),b,a)
def countMaximum(+a: W.U64,+b: W.U64) -> W.U64: Bool.pick(W.U64,W.atLeast(W.compare(a,b)),a,b)
def countFromNumber(+value: F64) -> W.U64:
  W.U64{F64.to_u32(F64.div(value,F64{1106247680,0})),F64.to_u32(F64.mod(value,F64{1106247680,0}))}
def natural(value: V.Value) -> Result<&2,&2,J.Error,W.U64>:
  match value:
    case V.Number{+number}:
      Bool.pick(Unit -> Result<&2,&2,J.Error,W.U64>,F.isInteger(number) && F64.is_ge(number,F64{0,0}) && F64.is_le(number,F64{1128267775,4294967295}),_ => Done{countFromNumber(number)},_ => Fail{J.InvalidValue{Nil{},"non-negative safe integer"}})(Unit{})
    case _: Fail{J.WrongType{Nil{},"non-negative safe integer"}}
# HTTP/WebSocket idle timeout syntax is intentional upstream configuration:
# case-insensitive "disabled", numeric strings, and fractional milliseconds.
def timeoutWord(text: String,word: String) -> Bool:
  match text word:
    case SNil{} SNil{}: True{}
    case SCon{Chr{actual},rest} SCon{Chr{wanted},remaining}: U32.is_eq(U32.or(actual,32),wanted) && timeoutWord(rest,remaining)
    case _ _: False{}
def timeoutText(+text: String) -> Result<&2,&2,J.Error,W.U64>:
  match text:
    case "": Fail{J.InvalidValue{Nil{},"timeout duration"}}
    case +text: Bool.pick(Result<&2,&2,J.Error,W.U64>,timeoutWord(text,"disabled"),Done{W.U64{0,0}},natural(V.Number{F64.floor(NumberString.toNumber(text))}))
def decodeTimeout(value: V.Value) -> Result<&2,&2,J.Error,W.U64>:
  match value:
    case V.Text{text}: timeoutText(Text.trim(text))
    case V.Number{number}: natural(V.Number{F64.floor(number)})
    case _: Fail{J.WrongType{Nil{},"timeout duration"}}
def decodeImageWidth(value: V.Value) -> Result<&2,&2,J.Error,W.U64>:
  match value:
    case V.Number{+number}: Bool.pick(Result<&2,&2,J.Error,W.U64>,F.isFinite(F.decode(number)),natural(V.Number{Bool.pick(F64,F64.is_lt(number,F64{1072693248,0}),F64{1072693248,0},F64.floor(number))}),Fail{J.InvalidValue{Nil{},"finite image width"}})
    case _: Fail{J.WrongType{Nil{},"image width"}}
def numberValue(value: W.U64) -> V.Value: V.Number{F.fromU64(value)}
def optional(-A: Data,+fields: R.Record<V.Value>,+key: String,parseItem: V.Value -> Result<&2,&2,J.Error,A>) -> Result<&2,&2,J.Error,Maybe<&2,A>>:
  Bool.pick(Unit -> Result<&2,&2,J.Error,Maybe<&2,A>>,Maybe.is_some(&2,V.Value,R.get(V.Value,fields,key)),_ => Result.map(&2,&2,J.Error,A,Maybe<&2,A>,value => Some{value},J.required(A,fields,key,parseItem)),_ => Done{None{}})(Unit{})
def property(-A: Data,key: String,value: Maybe<&2,A>,encode: A -> V.Value) -> List<&2,R.Property<V.Value>>:
  match value:
    case None{}: Nil{}
    case Some{value}: R.Property{key,encode(value)} <> Nil{}
def decodeStrings(value: V.Value) -> Result<&2,&2,J.Error,List<&2,String>>: J.list(~String,~J.string,value)
def encodeValues(~A: Data,~encode: A -> V.Value,values: List<&2,A>,reversed: List<&2,V.Value>) -> List<&2,V.Value>:
  match values:
    case Nil{}: List.reverse(&2,V.Value,reversed)
    case value <> rest: encodeValues(~A,~encode,rest,encode(value) <> reversed)
def encodeStrings(values: List<&2,String>) -> V.Value: V.ArrayValue{encodeValues(~String,~(value => V.Text{value}),values,Nil{})}


def decodeTuiMode(value: V.Value) -> Result<&2,&2,J.Error,TuiMode>:
  match value:
    case V.Text{"regular"}: Done{Regular{}}
    case V.Text{"fullscreen"}: Done{Fullscreen{}}
    case _: Fail{J.InvalidValue{Nil{},"TuiMode"}}

def encodeTuiMode(value: TuiMode) -> V.Value:
  match value:
    case Regular{}: V.Text{"regular"}
    case Fullscreen{}: V.Text{"fullscreen"}

def decodeFullscreenExitOutput(value: V.Value) -> Result<&2,&2,J.Error,FullscreenExitOutput>:
  match value:
    case V.Text{"transcript"}: Done{Transcript{}}
    case V.Text{"resume-hint"}: Done{ResumeHint{}}
    case _: Fail{J.InvalidValue{Nil{},"FullscreenExitOutput"}}

def encodeFullscreenExitOutput(value: FullscreenExitOutput) -> V.Value:
  match value:
    case Transcript{}: V.Text{"transcript"}
    case ResumeHint{}: V.Text{"resume-hint"}

def decodeScrollViewScrollbar(value: V.Value) -> Result<&2,&2,J.Error,ScrollViewScrollbar>:
  match value:
    case V.Text{"auto"}: Done{ScrollAuto{}}
    case V.Text{"always"}: Done{ScrollAlways{}}
    case V.Text{"hidden"}: Done{ScrollHidden{}}
    case _: Fail{J.InvalidValue{Nil{},"ScrollViewScrollbar"}}

def encodeScrollViewScrollbar(value: ScrollViewScrollbar) -> V.Value:
  match value:
    case ScrollAuto{}: V.Text{"auto"}
    case ScrollAlways{}: V.Text{"always"}
    case ScrollHidden{}: V.Text{"hidden"}

def decodeDefaultProjectTrust(value: V.Value) -> Result<&2,&2,J.Error,DefaultProjectTrust>:
  match value:
    case V.Text{"ask"}: Done{Ask{}}
    case V.Text{"always"}: Done{Always{}}
    case V.Text{"never"}: Done{Never{}}
    case _: Fail{J.InvalidValue{Nil{},"DefaultProjectTrust"}}

def encodeDefaultProjectTrust(value: DefaultProjectTrust) -> V.Value:
  match value:
    case Ask{}: V.Text{"ask"}
    case Always{}: V.Text{"always"}
    case Never{}: V.Text{"never"}

def decodeDoubleEscapeAction(value: V.Value) -> Result<&2,&2,J.Error,DoubleEscapeAction>:
  match value:
    case V.Text{"fork"}: Done{Fork{}}
    case V.Text{"tree"}: Done{Tree{}}
    case V.Text{"none"}: Done{NoDoubleEscape{}}
    case _: Fail{J.InvalidValue{Nil{},"DoubleEscapeAction"}}

def encodeDoubleEscapeAction(value: DoubleEscapeAction) -> V.Value:
  match value:
    case Fork{}: V.Text{"fork"}
    case Tree{}: V.Text{"tree"}
    case NoDoubleEscape{}: V.Text{"none"}

def decodeTreeFilterMode(value: V.Value) -> Result<&2,&2,J.Error,TreeFilterMode>:
  match value:
    case V.Text{"default"}: Done{DefaultFilter{}}
    case V.Text{"no-tools"}: Done{NoTools{}}
    case V.Text{"user-only"}: Done{UserOnly{}}
    case V.Text{"labeled-only"}: Done{LabeledOnly{}}
    case V.Text{"all"}: Done{AllEntries{}}
    case _: Fail{J.InvalidValue{Nil{},"TreeFilterMode"}}

def encodeTreeFilterMode(value: TreeFilterMode) -> V.Value:
  match value:
    case DefaultFilter{}: V.Text{"default"}
    case NoTools{}: V.Text{"no-tools"}
    case UserOnly{}: V.Text{"user-only"}
    case LabeledOnly{}: V.Text{"labeled-only"}
    case AllEntries{}: V.Text{"all"}

def decodeMermaidRenderingMode(value: V.Value) -> Result<&2,&2,J.Error,MermaidRenderingMode>:
  match value:
    case V.Text{"off"}: Done{MermaidOff{}}
    case V.Text{"final"}: Done{MermaidFinal{}}
    case V.Text{"streaming"}: Done{MermaidStreaming{}}
    case _: Fail{J.InvalidValue{Nil{},"MermaidRenderingMode"}}

def encodeMermaidRenderingMode(value: MermaidRenderingMode) -> V.Value:
  match value:
    case MermaidOff{}: V.Text{"off"}
    case MermaidFinal{}: V.Text{"final"}
    case MermaidStreaming{}: V.Text{"streaming"}

def decodeOutputPadding(value: V.Value) -> Result<&2,&2,J.Error,OutputPadding>:
  match value:
    case V.Number{F64{0,0}}: Done{NoPadding{}}
    case V.Number{F64{1072693248,0}}: Done{OnePadding{}}
    case _: Fail{J.InvalidValue{Nil{},"OutputPadding"}}

def encodeOutputPadding(value: OutputPadding) -> V.Value:
  match value:
    case NoPadding{}: V.Number{F64{0,0}}
    case OnePadding{}: V.Number{F64{1072693248,0}}

def decodeAutomaticBoolean(value: V.Value) -> Result<&2,&2,J.Error,AutomaticBoolean>:
  match value:
    case V.Text{"auto"}: Done{Automatic{}}
    case V.Boolean{True{}}: Done{Enabled{}}
    case V.Boolean{False{}}: Done{Disabled{}}
    case _: Fail{J.InvalidValue{Nil{},"AutomaticBoolean"}}

def encodeAutomaticBoolean(value: AutomaticBoolean) -> V.Value:
  match value:
    case Automatic{}: V.Text{"auto"}
    case Enabled{}: V.Boolean{True{}}
    case Disabled{}: V.Boolean{False{}}

def decodeTerminalImages(value: V.Value) -> Result<&2,&2,J.Error,TerminalImages>:
  match value:
    case V.Text{"auto"}: Done{ImageAuto{}}
    case V.Text{"kitty"}: Done{Kitty{}}
    case V.Text{"iterm2"}: Done{Iterm2{}}
    case V.Boolean{False{}}: Done{NoImages{}}
    case _: Fail{J.InvalidValue{Nil{},"TerminalImages"}}

def encodeTerminalImages(value: TerminalImages) -> V.Value:
  match value:
    case ImageAuto{}: V.Text{"auto"}
    case Kitty{}: V.Text{"kitty"}
    case Iterm2{}: V.Text{"iterm2"}
    case NoImages{}: V.Boolean{False{}}

def outputPadding(value: Result<&2,&2,J.Error,W.U64>) -> Result<&2,&2,J.Error,OutputPadding>:
  match value:
    case Done{W.U64{0,0}}: Done{NoPadding{}}
    case Done{W.U64{0,1}}: Done{OnePadding{}}
    case Fail{cause}: Fail{cause}
    case _: Fail{J.InvalidValue{Nil{},"zero or one"}}


def decodeThinking(value: V.Value) -> Result<&2,&2,J.Error,Ai.ModelThinkingLevel>:
  match value:
    case V.Text{"off"}: Done{Ai.Off{}}
    case V.Text{"minimal"}: Done{Ai.Thinking{Ai.Minimal{}}}
    case V.Text{"low"}: Done{Ai.Thinking{Ai.Low{}}}
    case V.Text{"medium"}: Done{Ai.Thinking{Ai.Medium{}}}
    case V.Text{"high"}: Done{Ai.Thinking{Ai.High{}}}
    case V.Text{"xhigh"}: Done{Ai.Thinking{Ai.XHigh{}}}
    case V.Text{"max"}: Done{Ai.Thinking{Ai.Max{}}}
    case _: Fail{J.InvalidValue{Nil{},"thinking level"}}
def encodeThinking(value: Ai.ModelThinkingLevel) -> V.Value:
  match value:
    case Ai.Off{}: V.Text{"off"}
    case Ai.Thinking{Ai.Minimal{}}: V.Text{"minimal"}
    case Ai.Thinking{Ai.Low{}}: V.Text{"low"}
    case Ai.Thinking{Ai.Medium{}}: V.Text{"medium"}
    case Ai.Thinking{Ai.High{}}: V.Text{"high"}
    case Ai.Thinking{Ai.XHigh{}}: V.Text{"xhigh"}
    case Ai.Thinking{Ai.Max{}}: V.Text{"max"}
def decodeTransport(value: V.Value) -> Result<&2,&2,J.Error,Ai.Transport>:
  match value:
    case V.Text{"auto"}: Done{Ai.AutoTransport{}}
    case V.Text{"sse"}: Done{Ai.Sse{}}
    case V.Text{"websocket"}: Done{Ai.WebSocket{}}
    case V.Text{"websocket-cached"}: Done{Ai.WebSocketCached{}}
    case _: Fail{J.InvalidValue{Nil{},"transport"}}
def encodeTransport(value: Ai.Transport) -> V.Value:
  match value:
    case Ai.AutoTransport{}: V.Text{"auto"}
    case Ai.Sse{}: V.Text{"sse"}
    case Ai.WebSocket{}: V.Text{"websocket"}
    case Ai.WebSocketCached{}: V.Text{"websocket-cached"}
def decodeQueue(value: V.Value) -> Result<&2,&2,J.Error,Agent.QueueMode>:
  match value:
    case V.Text{"all"}: Done{Agent.All{}}
    case V.Text{"one-at-a-time"}: Done{Agent.OneAtATime{}}
    case _: Fail{J.InvalidValue{Nil{},"queue mode"}}
def encodeQueue(value: Agent.QueueMode) -> V.Value:
  match value:
    case Agent.All{}: V.Text{"all"}
    case Agent.OneAtATime{}: V.Text{"one-at-a-time"}
def decodeProperties(~A: Data,~parseItem: V.Value -> Result<&2,&2,J.Error,A>,fields: List<&2,R.Property<V.Value>>,result: R.Record<A>) -> Result<&2,&2,J.Error,R.Record<A>>:
  match fields:
    case Nil{}: Done{result}
    case R.Property{+key,value} <> rest:
      do Result<&2,&2,J.Error,R.Record<A>>:
        parsed : A <- J.located(A,parseItem(value),J.Field{key})
        decodeProperties(~A,~parseItem,rest,R.set(A,result,key,parsed))
def decodeMap(~A: Data,~parseItem: V.Value -> Result<&2,&2,J.Error,A>,value: V.Value) -> Result<&2,&2,J.Error,R.Record<A>>:
  do Result<&2,&2,J.Error,R.Record<A>>:
    fields : R.Record<V.Value> <- J.object(value)
    decodeProperties(~A,~parseItem,R.entries(V.Value,fields),R.new(A))
def encodeProperties(~A: Data,~encode: A -> V.Value,fields: List<&2,R.Property<A>>) -> List<&2,R.Property<V.Value>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key,value} <> rest: R.Property{key,encode(value)} <> encodeProperties(~A,~encode,rest)
def encodeMap(~A: Data,~encode: A -> V.Value,fields: R.Record<A>) -> V.Value: V.ObjectValue{R.Record{encodeProperties(~A,~encode,R.entries(A,fields))}}


def decodeCompactionModelOverride(value: V.Value) -> Result<&2,&2,J.Error,CompactionModelOverride>:
  do Result<&2,&2,J.Error,CompactionModelOverride>:
    +fields : R.Record<V.Value> <- J.object(value)
    reserveTokens : Maybe<&2,W.U64> <- optional(W.U64,fields,"reserveTokens",natural)
    keepRecentTokens : Maybe<&2,W.U64> <- optional(W.U64,fields,"keepRecentTokens",natural)
    return CompactionModelOverride{reserveTokens,keepRecentTokens}

def encodeCompactionModelOverride(value: CompactionModelOverride) -> V.Value:
  match value:
    case CompactionModelOverride{reserveTokens,keepRecentTokens}:
      V.ObjectValue{R.Record{List.concat(&2,R.Property<V.Value>,
        property(W.U64,"reserveTokens",reserveTokens,numberValue) <>
        property(W.U64,"keepRecentTokens",keepRecentTokens,numberValue) <> Nil{})}}

def decodeCompactionSettings(value: V.Value) -> Result<&2,&2,J.Error,CompactionSettings>:
  do Result<&2,&2,J.Error,CompactionSettings>:
    +fields : R.Record<V.Value> <- J.object(value)
    enabled : Maybe<&2,Bool> <- optional(Bool,fields,"enabled",boolean)
    reserveTokens : Maybe<&2,W.U64> <- optional(W.U64,fields,"reserveTokens",natural)
    keepRecentTokens : Maybe<&2,W.U64> <- optional(W.U64,fields,"keepRecentTokens",natural)
    modelOverrides : Maybe<&2,R.Record<CompactionModelOverride>> <- optional(R.Record<CompactionModelOverride>,fields,"modelOverrides",value => decodeMap(~CompactionModelOverride,~decodeCompactionModelOverride,value))
    return CompactionSettings{enabled,reserveTokens,keepRecentTokens,modelOverrides}

def encodeCompactionSettings(value: CompactionSettings) -> V.Value:
  match value:
    case CompactionSettings{enabled,reserveTokens,keepRecentTokens,modelOverrides}:
      V.ObjectValue{R.Record{List.concat(&2,R.Property<V.Value>,
        property(Bool,"enabled",enabled,value => V.Boolean{value}) <>
        property(W.U64,"reserveTokens",reserveTokens,numberValue) <>
        property(W.U64,"keepRecentTokens",keepRecentTokens,numberValue) <>
        property(R.Record<CompactionModelOverride>,"modelOverrides",modelOverrides,value => encodeMap(~CompactionModelOverride,~encodeCompactionModelOverride,value)) <> Nil{})}}

def decodeBranchSummarySettings(value: V.Value) -> Result<&2,&2,J.Error,BranchSummarySettings>:
  do Result<&2,&2,J.Error,BranchSummarySettings>:
    +fields : R.Record<V.Value> <- J.object(value)
    reserveTokens : Maybe<&2,W.U64> <- optional(W.U64,fields,"reserveTokens",natural)
    skipPrompt : Maybe<&2,Bool> <- optional(Bool,fields,"skipPrompt",boolean)
    return BranchSummarySettings{reserveTokens,skipPrompt}

def encodeBranchSummarySettings(value: BranchSummarySettings) -> V.Value:
  match value:
    case BranchSummarySettings{reserveTokens,skipPrompt}:
      V.ObjectValue{R.Record{List.concat(&2,R.Property<V.Value>,
        property(W.U64,"reserveTokens",reserveTokens,numberValue) <>
        property(Bool,"skipPrompt",skipPrompt,value => V.Boolean{value}) <> Nil{})}}

def decodeProviderRetrySettings(value: V.Value) -> Result<&2,&2,J.Error,ProviderRetrySettings>:
  do Result<&2,&2,J.Error,ProviderRetrySettings>:
    +fields : R.Record<V.Value> <- J.object(value)
    timeoutMs : Maybe<&2,W.U64> <- optional(W.U64,fields,"timeoutMs",natural)
    maxRetries : Maybe<&2,W.U64> <- optional(W.U64,fields,"maxRetries",natural)
    maxRetryDelayMs : Maybe<&2,W.U64> <- optional(W.U64,fields,"maxRetryDelayMs",natural)
    return ProviderRetrySettings{timeoutMs,maxRetries,maxRetryDelayMs}

def encodeProviderRetrySettings(value: ProviderRetrySettings) -> V.Value:
  match value:
    case ProviderRetrySettings{timeoutMs,maxRetries,maxRetryDelayMs}:
      V.ObjectValue{R.Record{List.concat(&2,R.Property<V.Value>,
        property(W.U64,"timeoutMs",timeoutMs,numberValue) <>
        property(W.U64,"maxRetries",maxRetries,numberValue) <>
        property(W.U64,"maxRetryDelayMs",maxRetryDelayMs,numberValue) <> Nil{})}}

def decodeRetrySettings(value: V.Value) -> Result<&2,&2,J.Error,RetrySettings>:
  do Result<&2,&2,J.Error,RetrySettings>:
    +fields : R.Record<V.Value> <- J.object(value)
    enabled : Maybe<&2,Bool> <- optional(Bool,fields,"enabled",boolean)
    maxRetries : Maybe<&2,W.U64> <- optional(W.U64,fields,"maxRetries",natural)
    baseDelayMs : Maybe<&2,W.U64> <- optional(W.U64,fields,"baseDelayMs",natural)
    maxAgentDelayMs : Maybe<&2,W.U64> <- optional(W.U64,fields,"maxAgentDelayMs",natural)
    provider : Maybe<&2,ProviderRetrySettings> <- optional(ProviderRetrySettings,fields,"provider",decodeProviderRetrySettings)
    return RetrySettings{enabled,maxRetries,baseDelayMs,maxAgentDelayMs,provider}

def encodeRetrySettings(value: RetrySettings) -> V.Value:
  match value:
    case RetrySettings{enabled,maxRetries,baseDelayMs,maxAgentDelayMs,provider}:
      V.ObjectValue{R.Record{List.concat(&2,R.Property<V.Value>,
        property(Bool,"enabled",enabled,value => V.Boolean{value}) <>
        property(W.U64,"maxRetries",maxRetries,numberValue) <>
        property(W.U64,"baseDelayMs",baseDelayMs,numberValue) <>
        property(W.U64,"maxAgentDelayMs",maxAgentDelayMs,numberValue) <>
        property(ProviderRetrySettings,"provider",provider,encodeProviderRetrySettings) <> Nil{})}}

def decodeTerminalSettings(value: V.Value) -> Result<&2,&2,J.Error,TerminalSettings>:
  do Result<&2,&2,J.Error,TerminalSettings>:
    +fields : R.Record<V.Value> <- J.object(value)
    showImages : Maybe<&2,Bool> <- optional(Bool,fields,"showImages",boolean)
    imageWidthCells : Maybe<&2,W.U64> <- optional(W.U64,fields,"imageWidthCells",decodeImageWidth)
    clearOnShrink : Maybe<&2,Bool> <- optional(Bool,fields,"clearOnShrink",boolean)
    showTerminalProgress : Maybe<&2,Bool> <- optional(Bool,fields,"showTerminalProgress",boolean)
    hyperlinks : Maybe<&2,AutomaticBoolean> <- optional(AutomaticBoolean,fields,"hyperlinks",decodeAutomaticBoolean)
    images : Maybe<&2,TerminalImages> <- optional(TerminalImages,fields,"images",decodeTerminalImages)
    trueColor : Maybe<&2,AutomaticBoolean> <- optional(AutomaticBoolean,fields,"trueColor",decodeAutomaticBoolean)
    return TerminalSettings{showImages,imageWidthCells,clearOnShrink,showTerminalProgress,hyperlinks,images,trueColor}

def encodeTerminalSettings(value: TerminalSettings) -> V.Value:
  match value:
    case TerminalSettings{showImages,imageWidthCells,clearOnShrink,showTerminalProgress,hyperlinks,images,trueColor}:
      V.ObjectValue{R.Record{List.concat(&2,R.Property<V.Value>,
        property(Bool,"showImages",showImages,value => V.Boolean{value}) <>
        property(W.U64,"imageWidthCells",imageWidthCells,numberValue) <>
        property(Bool,"clearOnShrink",clearOnShrink,value => V.Boolean{value}) <>
        property(Bool,"showTerminalProgress",showTerminalProgress,value => V.Boolean{value}) <>
        property(AutomaticBoolean,"hyperlinks",hyperlinks,encodeAutomaticBoolean) <>
        property(TerminalImages,"images",images,encodeTerminalImages) <>
        property(AutomaticBoolean,"trueColor",trueColor,encodeAutomaticBoolean) <> Nil{})}}

def decodeImageSettings(value: V.Value) -> Result<&2,&2,J.Error,ImageSettings>:
  do Result<&2,&2,J.Error,ImageSettings>:
    +fields : R.Record<V.Value> <- J.object(value)
    autoResize : Maybe<&2,Bool> <- optional(Bool,fields,"autoResize",boolean)
    blockImages : Maybe<&2,Bool> <- optional(Bool,fields,"blockImages",boolean)
    return ImageSettings{autoResize,blockImages}

def encodeImageSettings(value: ImageSettings) -> V.Value:
  match value:
    case ImageSettings{autoResize,blockImages}:
      V.ObjectValue{R.Record{List.concat(&2,R.Property<V.Value>,
        property(Bool,"autoResize",autoResize,value => V.Boolean{value}) <>
        property(Bool,"blockImages",blockImages,value => V.Boolean{value}) <> Nil{})}}

def decodeThinkingBudgetsSettings(value: V.Value) -> Result<&2,&2,J.Error,ThinkingBudgetsSettings>:
  do Result<&2,&2,J.Error,ThinkingBudgetsSettings>:
    +fields : R.Record<V.Value> <- J.object(value)
    minimal : Maybe<&2,W.U64> <- optional(W.U64,fields,"minimal",natural)
    low : Maybe<&2,W.U64> <- optional(W.U64,fields,"low",natural)
    medium : Maybe<&2,W.U64> <- optional(W.U64,fields,"medium",natural)
    high : Maybe<&2,W.U64> <- optional(W.U64,fields,"high",natural)
    return ThinkingBudgetsSettings{minimal,low,medium,high}

def encodeThinkingBudgetsSettings(value: ThinkingBudgetsSettings) -> V.Value:
  match value:
    case ThinkingBudgetsSettings{minimal,low,medium,high}:
      V.ObjectValue{R.Record{List.concat(&2,R.Property<V.Value>,
        property(W.U64,"minimal",minimal,numberValue) <>
        property(W.U64,"low",low,numberValue) <>
        property(W.U64,"medium",medium,numberValue) <>
        property(W.U64,"high",high,numberValue) <> Nil{})}}

def decodeMarkdownSettings(value: V.Value) -> Result<&2,&2,J.Error,MarkdownSettings>:
  do Result<&2,&2,J.Error,MarkdownSettings>:
    +fields : R.Record<V.Value> <- J.object(value)
    codeBlockIndent : Maybe<&2,String> <- optional(String,fields,"codeBlockIndent",J.string)
    mermaid : Maybe<&2,MermaidRenderingMode> <- optional(MermaidRenderingMode,fields,"mermaid",decodeMermaidRenderingMode)
    return MarkdownSettings{codeBlockIndent,mermaid}

def encodeMarkdownSettings(value: MarkdownSettings) -> V.Value:
  match value:
    case MarkdownSettings{codeBlockIndent,mermaid}:
      V.ObjectValue{R.Record{List.concat(&2,R.Property<V.Value>,
        property(String,"codeBlockIndent",codeBlockIndent,value => V.Text{value}) <>
        property(MermaidRenderingMode,"mermaid",mermaid,encodeMermaidRenderingMode) <> Nil{})}}

def decodeWarningSettings(value: V.Value) -> Result<&2,&2,J.Error,WarningSettings>:
  do Result<&2,&2,J.Error,WarningSettings>:
    +fields : R.Record<V.Value> <- J.object(value)
    anthropicExtraUsage : Maybe<&2,Bool> <- optional(Bool,fields,"anthropicExtraUsage",boolean)
    return WarningSettings{anthropicExtraUsage}

def encodeWarningSettings(value: WarningSettings) -> V.Value:
  match value:
    case WarningSettings{anthropicExtraUsage}:
      V.ObjectValue{R.Record{List.concat(&2,R.Property<V.Value>,
        property(Bool,"anthropicExtraUsage",anthropicExtraUsage,value => V.Boolean{value}) <> Nil{})}}

def decodePackageFilter(value: V.Value) -> Result<&2,&2,J.Error,PackageFilter>:
  do Result<&2,&2,J.Error,PackageFilter>:
    +fields : R.Record<V.Value> <- J.object(value)
    autoload : Maybe<&2,Bool> <- optional(Bool,fields,"autoload",boolean)
    extensions : Maybe<&2,List<&2,String>> <- optional(List<&2,String>,fields,"extensions",decodeStrings)
    skills : Maybe<&2,List<&2,String>> <- optional(List<&2,String>,fields,"skills",decodeStrings)
    prompts : Maybe<&2,List<&2,String>> <- optional(List<&2,String>,fields,"prompts",decodeStrings)
    themes : Maybe<&2,List<&2,String>> <- optional(List<&2,String>,fields,"themes",decodeStrings)
    return PackageFilter{autoload,extensions,skills,prompts,themes}

def encodePackageFilter(value: PackageFilter) -> V.Value:
  match value:
    case PackageFilter{autoload,extensions,skills,prompts,themes}:
      V.ObjectValue{R.Record{List.concat(&2,R.Property<V.Value>,
        property(Bool,"autoload",autoload,value => V.Boolean{value}) <>
        property(List<&2,String>,"extensions",extensions,encodeStrings) <>
        property(List<&2,String>,"skills",skills,encodeStrings) <>
        property(List<&2,String>,"prompts",prompts,encodeStrings) <>
        property(List<&2,String>,"themes",themes,encodeStrings) <> Nil{})}}

def decodePackageSource(value: V.Value) -> Result<&2,&2,J.Error,PackageSource>:
  match value:
    case V.Text{source}: Done{PackageName{source}}
    case V.ObjectValue{+fields}:
      do Result<&2,&2,J.Error,PackageSource>:
        source : String <- J.required(String,fields,"source",J.string)
        filter : PackageFilter <- decodePackageFilter(V.ObjectValue{fields})
        return FilteredPackage{source,filter,R.remove(V.Value,R.remove(V.Value,R.remove(V.Value,R.remove(V.Value,R.remove(V.Value,R.remove(V.Value,fields,"source"),"autoload"),"extensions"),"skills"),"prompts"),"themes")}
    case _: Fail{J.WrongType{Nil{},"package source"}}
def packageProperties(values: List<&2,R.Property<V.Value>>,result: R.Record<V.Value>) -> R.Record<V.Value>:
  match values:
    case Nil{}: result
    case R.Property{key,value} <> rest: packageProperties(rest,R.set(V.Value,result,key,value))
def packageFields(value: V.Value,source: String,unknown: R.Record<V.Value>) -> V.Value:
  match value:
    case V.ObjectValue{fields}: V.ObjectValue{R.set(V.Value,packageProperties(R.entries(V.Value,fields),unknown),"source",V.Text{source})}
    case _: V.ObjectValue{R.new(V.Value)}
def encodePackageSource(value: PackageSource) -> V.Value:
  match value:
    case PackageName{source}: V.Text{source}
    case FilteredPackage{source,filter,unknown}: packageFields(encodePackageFilter(filter),source,unknown)


def name(value: Setting) -> String:
  match value:
    case LastChangelogVersion{_}: "lastChangelogVersion"
    case DefaultProvider{_}: "defaultProvider"
    case DefaultModel{_}: "defaultModel"
    case Theme{_}: "theme"
    case ExternalEditor{_}: "externalEditor"
    case ShellPath{_}: "shellPath"
    case ShellCommandPrefix{_}: "shellCommandPrefix"
    case TrackingId{_}: "trackingId"
    case SessionDir{_}: "sessionDir"
    case HttpProxy{_}: "httpProxy"
    case HideThinkingBlock{_}: "hideThinkingBlock"
    case ShowCacheMissNotices{_}: "showCacheMissNotices"
    case QuietStartup{_}: "quietStartup"
    case CollapseChangelog{_}: "collapseChangelog"
    case EnableInstallTelemetry{_}: "enableInstallTelemetry"
    case EnableAnalytics{_}: "enableAnalytics"
    case EnableSkillCommands{_}: "enableSkillCommands"
    case ShowHardwareCursor{_}: "showHardwareCursor"
    case FullscreenCopyOnSelect{_}: "fullscreenCopyOnSelect"
    case EditorPaddingX{_}: "editorPaddingX"
    case AutocompleteMaxVisible{_}: "autocompleteMaxVisible"
    case HttpIdleTimeoutMs{_}: "httpIdleTimeoutMs"
    case WebsocketConnectTimeoutMs{_}: "websocketConnectTimeoutMs"
    case NpmCommand{_}: "npmCommand"
    case Extensions{_}: "extensions"
    case Skills{_}: "skills"
    case Prompts{_}: "prompts"
    case Themes{_}: "themes"
    case EnabledModels{_}: "enabledModels"
    case DefaultTools{_}: "defaultTools"
    case DefaultThinkingLevel{_}: "defaultThinkingLevel"
    case ModelThinkingLevels{_}: "modelThinkingLevels"
    case Transport{_}: "transport"
    case SteeringMode{_}: "steeringMode"
    case FollowUpMode{_}: "followUpMode"
    case Packages{_}: "packages"
    case DefaultProjectTrust{_}: "defaultProjectTrust"
    case DoubleEscapeAction{_}: "doubleEscapeAction"
    case TreeFilterMode{_}: "treeFilterMode"
    case OutputPad{_}: "outputPad"
    case TuiMode{_}: "tuiMode"
    case FullscreenExitOutput{_}: "fullscreenExitOutput"
    case FullscreenScrollbar{_}: "fullscreenScrollbar"
    case Compaction{_}: "compaction"
    case BranchSummary{_}: "branchSummary"
    case Retry{_}: "retry"
    case Terminal{_}: "terminal"
    case Images{_}: "images"
    case ThinkingBudgets{_}: "thinkingBudgets"
    case Markdown{_}: "markdown"
    case Warnings{_}: "warnings"

def settingValue(value: Setting) -> V.Value:
  match value:
    case LastChangelogVersion{value}: V.Text{value}
    case DefaultProvider{value}: V.Text{value}
    case DefaultModel{value}: V.Text{value}
    case Theme{value}: V.Text{value}
    case ExternalEditor{value}: V.Text{value}
    case ShellPath{value}: V.Text{value}
    case ShellCommandPrefix{value}: V.Text{value}
    case TrackingId{value}: V.Text{value}
    case SessionDir{value}: V.Text{value}
    case HttpProxy{value}: V.Text{value}
    case HideThinkingBlock{value}: V.Boolean{value}
    case ShowCacheMissNotices{value}: V.Boolean{value}
    case QuietStartup{value}: V.Boolean{value}
    case CollapseChangelog{value}: V.Boolean{value}
    case EnableInstallTelemetry{value}: V.Boolean{value}
    case EnableAnalytics{value}: V.Boolean{value}
    case EnableSkillCommands{value}: V.Boolean{value}
    case ShowHardwareCursor{value}: V.Boolean{value}
    case FullscreenCopyOnSelect{value}: V.Boolean{value}
    case EditorPaddingX{value}: numberValue(value)
    case AutocompleteMaxVisible{value}: numberValue(value)
    case HttpIdleTimeoutMs{value}: numberValue(value)
    case WebsocketConnectTimeoutMs{value}: numberValue(value)
    case NpmCommand{value}: encodeStrings(value)
    case Extensions{value}: encodeStrings(value)
    case Skills{value}: encodeStrings(value)
    case Prompts{value}: encodeStrings(value)
    case Themes{value}: encodeStrings(value)
    case EnabledModels{value}: encodeStrings(value)
    case DefaultTools{value}: encodeStrings(value)
    case DefaultThinkingLevel{value}: encodeThinking(value)
    case ModelThinkingLevels{value}: encodeMap(~Ai.ModelThinkingLevel,~encodeThinking,value)
    case Transport{value}: encodeTransport(value)
    case SteeringMode{value}: encodeQueue(value)
    case FollowUpMode{value}: encodeQueue(value)
    case Packages{value}: V.ArrayValue{encodeValues(~PackageSource,~encodePackageSource,value,Nil{})}
    case DefaultProjectTrust{value}: encodeDefaultProjectTrust(value)
    case DoubleEscapeAction{value}: encodeDoubleEscapeAction(value)
    case TreeFilterMode{value}: encodeTreeFilterMode(value)
    case OutputPad{value}: encodeOutputPadding(value)
    case TuiMode{value}: encodeTuiMode(value)
    case FullscreenExitOutput{value}: encodeFullscreenExitOutput(value)
    case FullscreenScrollbar{value}: encodeScrollViewScrollbar(value)
    case Compaction{value}: encodeCompactionSettings(value)
    case BranchSummary{value}: encodeBranchSummarySettings(value)
    case Retry{value}: encodeRetrySettings(value)
    case Terminal{value}: encodeTerminalSettings(value)
    case Images{value}: encodeImageSettings(value)
    case ThinkingBudgets{value}: encodeThinkingBudgetsSettings(value)
    case Markdown{value}: encodeMarkdownSettings(value)
    case Warnings{value}: encodeWarningSettings(value)

def knownField(key: String,value: V.Value) -> Result<&2,&2,J.Error,Maybe<&2,Setting>>:
  match key:
    case "lastChangelogVersion": Result.map(&2,&2,J.Error,String,Maybe<&2,Setting>,parsed => Some{LastChangelogVersion{parsed}},J.string(value))
    case "defaultProvider": Result.map(&2,&2,J.Error,String,Maybe<&2,Setting>,parsed => Some{DefaultProvider{parsed}},J.string(value))
    case "defaultModel": Result.map(&2,&2,J.Error,String,Maybe<&2,Setting>,parsed => Some{DefaultModel{parsed}},J.string(value))
    case "theme": Result.map(&2,&2,J.Error,String,Maybe<&2,Setting>,parsed => Some{Theme{parsed}},J.string(value))
    case "externalEditor": Result.map(&2,&2,J.Error,String,Maybe<&2,Setting>,parsed => Some{ExternalEditor{parsed}},J.string(value))
    case "shellPath": Result.map(&2,&2,J.Error,String,Maybe<&2,Setting>,parsed => Some{ShellPath{parsed}},J.string(value))
    case "shellCommandPrefix": Result.map(&2,&2,J.Error,String,Maybe<&2,Setting>,parsed => Some{ShellCommandPrefix{parsed}},J.string(value))
    case "trackingId": Result.map(&2,&2,J.Error,String,Maybe<&2,Setting>,parsed => Some{TrackingId{parsed}},J.string(value))
    case "sessionDir": Result.map(&2,&2,J.Error,String,Maybe<&2,Setting>,parsed => Some{SessionDir{parsed}},J.string(value))
    case "httpProxy": Result.map(&2,&2,J.Error,String,Maybe<&2,Setting>,parsed => Some{HttpProxy{parsed}},J.string(value))
    case "hideThinkingBlock": Result.map(&2,&2,J.Error,Bool,Maybe<&2,Setting>,parsed => Some{HideThinkingBlock{parsed}},boolean(value))
    case "showCacheMissNotices": Result.map(&2,&2,J.Error,Bool,Maybe<&2,Setting>,parsed => Some{ShowCacheMissNotices{parsed}},boolean(value))
    case "quietStartup": Result.map(&2,&2,J.Error,Bool,Maybe<&2,Setting>,parsed => Some{QuietStartup{parsed}},boolean(value))
    case "collapseChangelog": Result.map(&2,&2,J.Error,Bool,Maybe<&2,Setting>,parsed => Some{CollapseChangelog{parsed}},boolean(value))
    case "enableInstallTelemetry": Result.map(&2,&2,J.Error,Bool,Maybe<&2,Setting>,parsed => Some{EnableInstallTelemetry{parsed}},boolean(value))
    case "enableAnalytics": Result.map(&2,&2,J.Error,Bool,Maybe<&2,Setting>,parsed => Some{EnableAnalytics{parsed}},boolean(value))
    case "enableSkillCommands": Result.map(&2,&2,J.Error,Bool,Maybe<&2,Setting>,parsed => Some{EnableSkillCommands{parsed}},boolean(value))
    case "showHardwareCursor": Result.map(&2,&2,J.Error,Bool,Maybe<&2,Setting>,parsed => Some{ShowHardwareCursor{parsed}},boolean(value))
    case "fullscreenCopyOnSelect": Result.map(&2,&2,J.Error,Bool,Maybe<&2,Setting>,parsed => Some{FullscreenCopyOnSelect{parsed}},boolean(value))
    case "editorPaddingX": Result.map(&2,&2,J.Error,W.U64,Maybe<&2,Setting>,parsed => Some{EditorPaddingX{parsed}},natural(value))
    case "autocompleteMaxVisible": Result.map(&2,&2,J.Error,W.U64,Maybe<&2,Setting>,parsed => Some{AutocompleteMaxVisible{parsed}},natural(value))
    case "httpIdleTimeoutMs": Result.map(&2,&2,J.Error,W.U64,Maybe<&2,Setting>,parsed => Some{HttpIdleTimeoutMs{parsed}},decodeTimeout(value))
    case "websocketConnectTimeoutMs": Result.map(&2,&2,J.Error,W.U64,Maybe<&2,Setting>,parsed => Some{WebsocketConnectTimeoutMs{parsed}},decodeTimeout(value))
    case "npmCommand": Result.map(&2,&2,J.Error,List<&2,String>,Maybe<&2,Setting>,parsed => Some{NpmCommand{parsed}},decodeStrings(value))
    case "extensions": Result.map(&2,&2,J.Error,List<&2,String>,Maybe<&2,Setting>,parsed => Some{Extensions{parsed}},decodeStrings(value))
    case "skills": Result.map(&2,&2,J.Error,List<&2,String>,Maybe<&2,Setting>,parsed => Some{Skills{parsed}},decodeStrings(value))
    case "prompts": Result.map(&2,&2,J.Error,List<&2,String>,Maybe<&2,Setting>,parsed => Some{Prompts{parsed}},decodeStrings(value))
    case "themes": Result.map(&2,&2,J.Error,List<&2,String>,Maybe<&2,Setting>,parsed => Some{Themes{parsed}},decodeStrings(value))
    case "enabledModels": Result.map(&2,&2,J.Error,List<&2,String>,Maybe<&2,Setting>,parsed => Some{EnabledModels{parsed}},decodeStrings(value))
    case "defaultTools": Result.map(&2,&2,J.Error,List<&2,String>,Maybe<&2,Setting>,parsed => Some{DefaultTools{parsed}},decodeStrings(value))
    case "defaultThinkingLevel": Result.map(&2,&2,J.Error,Ai.ModelThinkingLevel,Maybe<&2,Setting>,parsed => Some{DefaultThinkingLevel{parsed}},decodeThinking(value))
    case "modelThinkingLevels": Result.map(&2,&2,J.Error,R.Record<Ai.ModelThinkingLevel>,Maybe<&2,Setting>,parsed => Some{ModelThinkingLevels{parsed}},decodeMap(~Ai.ModelThinkingLevel,~decodeThinking,value))
    case "transport": Result.map(&2,&2,J.Error,Ai.Transport,Maybe<&2,Setting>,parsed => Some{Transport{parsed}},decodeTransport(value))
    case "steeringMode": Result.map(&2,&2,J.Error,Agent.QueueMode,Maybe<&2,Setting>,parsed => Some{SteeringMode{parsed}},decodeQueue(value))
    case "followUpMode": Result.map(&2,&2,J.Error,Agent.QueueMode,Maybe<&2,Setting>,parsed => Some{FollowUpMode{parsed}},decodeQueue(value))
    case "packages": Result.map(&2,&2,J.Error,List<&2,PackageSource>,Maybe<&2,Setting>,parsed => Some{Packages{parsed}},J.list(~PackageSource,~decodePackageSource,value))
    case "defaultProjectTrust": Result.map(&2,&2,J.Error,DefaultProjectTrust,Maybe<&2,Setting>,parsed => Some{DefaultProjectTrust{parsed}},decodeDefaultProjectTrust(value))
    case "doubleEscapeAction": Result.map(&2,&2,J.Error,DoubleEscapeAction,Maybe<&2,Setting>,parsed => Some{DoubleEscapeAction{parsed}},decodeDoubleEscapeAction(value))
    case "treeFilterMode": Result.map(&2,&2,J.Error,TreeFilterMode,Maybe<&2,Setting>,parsed => Some{TreeFilterMode{parsed}},decodeTreeFilterMode(value))
    case "outputPad": Result.map(&2,&2,J.Error,OutputPadding,Maybe<&2,Setting>,parsed => Some{OutputPad{parsed}},outputPadding(natural(value)))
    case "tuiMode": Result.map(&2,&2,J.Error,TuiMode,Maybe<&2,Setting>,parsed => Some{TuiMode{parsed}},decodeTuiMode(value))
    case "fullscreenExitOutput": Result.map(&2,&2,J.Error,FullscreenExitOutput,Maybe<&2,Setting>,parsed => Some{FullscreenExitOutput{parsed}},decodeFullscreenExitOutput(value))
    case "fullscreenScrollbar": Result.map(&2,&2,J.Error,ScrollViewScrollbar,Maybe<&2,Setting>,parsed => Some{FullscreenScrollbar{parsed}},decodeScrollViewScrollbar(value))
    case "compaction": Result.map(&2,&2,J.Error,CompactionSettings,Maybe<&2,Setting>,parsed => Some{Compaction{parsed}},decodeCompactionSettings(value))
    case "branchSummary": Result.map(&2,&2,J.Error,BranchSummarySettings,Maybe<&2,Setting>,parsed => Some{BranchSummary{parsed}},decodeBranchSummarySettings(value))
    case "retry": Result.map(&2,&2,J.Error,RetrySettings,Maybe<&2,Setting>,parsed => Some{Retry{parsed}},decodeRetrySettings(value))
    case "terminal": Result.map(&2,&2,J.Error,TerminalSettings,Maybe<&2,Setting>,parsed => Some{Terminal{parsed}},decodeTerminalSettings(value))
    case "images": Result.map(&2,&2,J.Error,ImageSettings,Maybe<&2,Setting>,parsed => Some{Images{parsed}},decodeImageSettings(value))
    case "thinkingBudgets": Result.map(&2,&2,J.Error,ThinkingBudgetsSettings,Maybe<&2,Setting>,parsed => Some{ThinkingBudgets{parsed}},decodeThinkingBudgetsSettings(value))
    case "markdown": Result.map(&2,&2,J.Error,MarkdownSettings,Maybe<&2,Setting>,parsed => Some{Markdown{parsed}},decodeMarkdownSettings(value))
    case "warnings": Result.map(&2,&2,J.Error,WarningSettings,Maybe<&2,Setting>,parsed => Some{Warnings{parsed}},decodeWarningSettings(value))
    case _: Done{None{}}

# JSON tree operations are limited to unknown-field retention. Explicit frames
# keep deeply nested extension metadata independent of the host call stack.
type TreeOperation is Data:
  MergeUnknown{}
  SubtractKnown{}
type TreeFrame is Data:
  TreeFrame{key: String,remaining: List<&2,R.Property<V.Value>>,other: R.Record<V.Value>,result: R.Record<V.Value>}
type TreeWalk is Data:
  Descend{left: V.Value,right: V.Value,parents: List<&2,TreeFrame>}
  Ascend{value: Maybe<&2,V.Value>,parents: List<&2,TreeFrame>}
  TreeDone{value: Maybe<&2,V.Value>}
def unknownEntry(value: Maybe<&2,V.Value>,key: String,result: R.Record<V.Value>) -> R.Record<V.Value>:
  match value:
    case None{}: result
    case Some{value}: R.set(V.Value,result,key,value)
def objectResult(operation: TreeOperation,fields: R.Record<V.Value>) -> Maybe<&2,V.Value>:
  match operation fields:
    case SubtractKnown{} R.Record{Nil{}}: None{}
    case _ other: Some{V.ObjectValue{other}}
def objectStep(operation: TreeOperation,fields: List<&2,R.Property<V.Value>>,+other: R.Record<V.Value>,+result: R.Record<V.Value>,parents: List<&2,TreeFrame>) -> TreeWalk:
  match operation fields:
    case operation Nil{}: Ascend{objectResult(operation,result),parents}
    case MergeUnknown{} R.Property{+key,value} <> rest:
      Descend{Maybe.default(&2,V.Value,R.get(V.Value,result,key),V.Null{}),value,TreeFrame{key,rest,other,result} <> parents}
    case SubtractKnown{} R.Property{+key,value} <> rest:
      Descend{value,Maybe.default(&2,V.Value,R.get(V.Value,other,key),V.Null{}),TreeFrame{key,rest,other,result} <> parents}
def treeStep(operation: TreeOperation,walk: TreeWalk) -> TreeWalk:
  match operation walk:
    case MergeUnknown{} Descend{V.ObjectValue{base},V.ObjectValue{overrides},parents}: objectStep(MergeUnknown{},R.entries(V.Value,overrides),R.new(V.Value),base,parents)
    case MergeUnknown{} Descend{_,value,parents}: Ascend{Some{value},parents}
    case SubtractKnown{} Descend{value,V.Null{},parents}: Ascend{Some{value},parents}
    case SubtractKnown{} Descend{V.ObjectValue{fields},V.ObjectValue{known},parents}: objectStep(SubtractKnown{},R.entries(V.Value,fields),known,R.new(V.Value),parents)
    case SubtractKnown{} Descend{_,_,parents}: Ascend{None{},parents}
    case _ Ascend{value,Nil{}}: TreeDone{value}
    case operation Ascend{value,TreeFrame{key,rest,other,result} <> parents}: objectStep(operation,rest,other,unknownEntry(value,key,result),parents)
    case _ TreeDone{value}: TreeDone{value}
@unsafe def treeWalk(+operation: TreeOperation,walk: TreeWalk) -> Maybe<&2,V.Value>:
  match walk:
    case TreeDone{value}: value
    case other: treeWalk(operation,treeStep(operation,other))
def mergeJson(base: V.Value,overrides: V.Value) -> V.Value:
  Maybe.default(&2,V.Value,treeWalk(MergeUnknown{},Descend{base,overrides,Nil{}}),V.Null{})
def valueRecord(value: Maybe<&2,V.Value>) -> R.Record<V.Value>:
  match value:
    case Some{V.ObjectValue{fields}}: fields
    case _: R.new(V.Value)
def mergeRecords(base: R.Record<V.Value>,overrides: R.Record<V.Value>) -> R.Record<V.Value>:
  valueRecord(Some{mergeJson(V.ObjectValue{base},V.ObjectValue{overrides})})
def unknownFields(original: R.Record<V.Value>,known: R.Record<V.Value>) -> R.Record<V.Value>:
  valueRecord(treeWalk(SubtractKnown{},Descend{V.ObjectValue{original},V.ObjectValue{known},Nil{}}))
def knownProperties(fields: List<&2,R.Property<Setting>>) -> List<&2,R.Property<V.Value>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key,value} <> rest: R.Property{key,settingValue(value)} <> knownProperties(rest)
def toValue(value: Settings) -> V.Value:
  match value:
    case Settings{fields,unknown}: V.ObjectValue{mergeRecords(unknown,R.Record{knownProperties(R.entries(Setting,fields))})}
def serialize(value: Settings) -> String:
  Maybe.default(&2,String,Render.stringifyPretty(SchemaJson.toJson(toValue(value))),"{}")
def fromKnown(value: Maybe<&2,Setting>,key: String,fields: R.Record<Setting>) -> R.Record<Setting>:
  match value:
    case None{}: fields
    case Some{value}: R.set(Setting,fields,key,value)
def typedFields(fields: List<&2,R.Property<V.Value>>,result: R.Record<Setting>) -> Result<&2,&2,J.Error,R.Record<Setting>>:
  match fields:
    case Nil{}: Done{result}
    case R.Property{+key,value} <> rest:
      do Result<&2,&2,J.Error,R.Record<Setting>>:
        value : Maybe<&2,Setting> <- J.located(Maybe<&2,Setting>,knownField(key,value),J.Field{key})
        typedFields(rest,fromKnown(value,key,result))
def typedResult(value: Result<&2,&2,J.Error,R.Record<Setting>>,original: R.Record<V.Value>) -> Outcome(Settings):
  match value:
    case Fail{cause}: Fail{InvalidSetting{cause}}
    case Done{+fields}: Done{Settings{fields,unknownFields(original,R.Record{knownProperties(R.entries(Setting,fields))})}}
def checkedObject(value: Result<&2,&2,J.Error,R.Record<V.Value>>) -> Outcome(Settings):
  match value:
    case Fail{cause}: Fail{InvalidSetting{cause}}
    case Done{+fields}: typedResult(typedFields(R.entries(V.Value,fields),R.new(Setting)),fields)
def decode(value: V.Value) -> Outcome(Settings): checkedObject(J.object(value))

# Four upstream format migrations run before schema validation.
def moved(old: Maybe<&2,V.Value>,new: Maybe<&2,V.Value>,fields: R.Record<V.Value>,oldKey: String,newKey: String) -> R.Record<V.Value>:
  match old new:
    case Some{value} None{}: R.set(V.Value,R.remove(V.Value,fields,oldKey),newKey,value)
    case _ _: fields
def websocketMigration(old: Maybe<&2,V.Value>,new: Maybe<&2,V.Value>,fields: R.Record<V.Value>) -> R.Record<V.Value>:
  match old new:
    case Some{V.Boolean{enabled}} None{}: R.set(V.Value,R.remove(V.Value,fields,"websockets"),"transport",V.Text{Bool.pick(String,enabled,"websocket","sse")})
    case _ _: fields
def legacyDirectories(value: Maybe<&2,V.Value>,fields: R.Record<V.Value>) -> R.Record<V.Value>:
  match value:
    case Some{V.ArrayValue{first <> rest}}: R.set(V.Value,fields,"skills",V.ArrayValue{first <> rest})
    case _: R.remove(V.Value,fields,"skills")
def legacySkills(value: Maybe<&2,V.Value>,+fields: R.Record<V.Value>) -> R.Record<V.Value>:
  match value:
    case Some{V.ObjectValue{+legacy}}:
      +next = moved(R.get(V.Value,legacy,"enableSkillCommands"),R.get(V.Value,fields,"enableSkillCommands"),fields,"skills","enableSkillCommands")
      legacyDirectories(R.get(V.Value,legacy,"customDirectories"),next)
    case _: fields
def legacyDelay(value: Maybe<&2,V.Value>,new: Maybe<&2,V.Value>,provider: R.Record<V.Value>) -> R.Record<V.Value>:
  match value new:
    case Some{V.Number{value}} None{}: R.set(V.Value,provider,"maxRetryDelayMs",V.Number{value})
    case Some{V.Number{value}} Some{V.Null{}}: R.set(V.Value,provider,"maxRetryDelayMs",V.Number{value})
    case _ _: provider
def objectOrEmpty(value: Maybe<&2,V.Value>) -> R.Record<V.Value>:
  match value:
    case Some{V.ObjectValue{fields}}: fields
    case _: R.new(V.Value)
def legacyProviderAllowed(value: Maybe<&2,V.Value>) -> Bool:
  match value:
    case None{}: True{}
    case Some{V.Null{}}: True{}
    case Some{V.ObjectValue{_}}: True{}
    case _: False{}
def retryMigration(value: Maybe<&2,V.Value>,fields: R.Record<V.Value>) -> R.Record<V.Value>:
  match value:
    case Some{V.ObjectValue{+retry}}:
      +provider = objectOrEmpty(R.get(V.Value,retry,"provider"))
      +merged = legacyDelay(R.get(V.Value,retry,"maxDelayMs"),R.get(V.Value,provider,"maxRetryDelayMs"),provider)
      next = Bool.pick(R.Record<V.Value>,legacyProviderAllowed(R.get(V.Value,retry,"provider")) && Maybe.is_some(&2,V.Value,R.get(V.Value,merged,"maxRetryDelayMs")),R.set(V.Value,retry,"provider",V.ObjectValue{merged}),retry)
      R.set(V.Value,fields,"retry",V.ObjectValue{R.remove(V.Value,next,"maxDelayMs")})
    case _: fields
def migrate(value: V.Value) -> V.Value:
  match value:
    case V.ObjectValue{+fields}:
      +queue = moved(R.get(V.Value,fields,"queueMode"),R.get(V.Value,fields,"steeringMode"),fields,"queueMode","steeringMode")
      +transport = websocketMigration(R.get(V.Value,queue,"websockets"),R.get(V.Value,queue,"transport"),queue)
      +skills = legacySkills(R.get(V.Value,transport,"skills"),transport)
      V.ObjectValue{retryMigration(R.get(V.Value,skills,"retry"),skills)}
    case other: other

def duplicate(parser: J.Parser,token: J.Token) -> Bool:
  match parser token:
    case J.Parser{J.ObjectNext{fields},_} J.Atom{V.Text{key}}: Maybe.is_some(&2,V.Value,R.get(V.Value,fields,key))
    case _ _: False{}
def strictJson(fuel: Nat,+parser: J.Parser,input: J.Lexeme) -> Outcome(V.Value):
  match fuel parser input:
    case 0n _ _: Fail{InvalidJson{J.InputLimit{}}}
    case _ J.Parser{J.Broken{cause},_} _: Fail{InvalidJson{cause}}
    case _ J.Parser{J.Finished{value},_} J.Lexeme{J.End{},_}: Done{value}
    case _ J.Parser{J.Finished{_},_} _: Fail{InvalidJson{J.TrailingInput{}}}
    case 1n+n _ J.Lexeme{+token,rest}:
      Bool.pick(Unit -> Outcome(V.Value),duplicate(parser,token),_ => Fail{DuplicateSetting{"JSON object"}},_ => strictJson(n,J.parserStep(parser,token),J.lex(rest)))(Unit{})
def stripBom(value: String) -> String:
  match value:
    case SCon{Chr{65279},rest}: rest
    case other: other
def parse(+content: String) -> Outcome(Settings):
  do Result<&2,&2,Error,Settings>:
    value : V.Value <- strictJson(2n+String.length(content),J.Parser{J.Value{},Nil{}},J.lex(stripBom(content)))
    decode(migrate(value))

def prefer(-A: Data,base: Maybe<&2,A>,override: Maybe<&2,A>) -> Maybe<&2,A>:
  match override:
    case None{}: base
    case other: other
def mergeOptional(~A: Data,~merge: A -> A -> A,base: Maybe<&2,A>,override: Maybe<&2,A>) -> Maybe<&2,A>:
  match base override:
    case Some{base} Some{override}: Some{merge(base,override)}
    case base override: prefer(A,base,override)
def mergeMapFields(~A: Data,~merge: A -> A -> A,fields: List<&2,R.Property<A>>,base: R.Record<A>) -> R.Record<A>:
  match fields:
    case Nil{}: base
    case R.Property{+key,+value} <> rest:
      +base = base
      mergeMapFields(~A,~merge,rest,R.set(A,base,key,Maybe.default(&2,A,mergeOptional(~A,~merge,R.get(A,base,key),Some{value}),value)))
def mergeMap(~A: Data,~merge: A -> A -> A,base: R.Record<A>,override: R.Record<A>) -> R.Record<A>:
  mergeMapFields(~A,~merge,R.entries(A,override),base)


def mergeCompactionModelOverride(base: CompactionModelOverride,override: CompactionModelOverride) -> CompactionModelOverride:
  match base override:
    case CompactionModelOverride{areserveTokens,akeepRecentTokens} CompactionModelOverride{breserveTokens,bkeepRecentTokens}:
      CompactionModelOverride{prefer(W.U64,areserveTokens,breserveTokens),
        prefer(W.U64,akeepRecentTokens,bkeepRecentTokens)}

def mergeCompactionSettings(base: CompactionSettings,override: CompactionSettings) -> CompactionSettings:
  match base override:
    case CompactionSettings{aenabled,areserveTokens,akeepRecentTokens,amodelOverrides} CompactionSettings{benabled,breserveTokens,bkeepRecentTokens,bmodelOverrides}:
      CompactionSettings{prefer(Bool,aenabled,benabled),
        prefer(W.U64,areserveTokens,breserveTokens),
        prefer(W.U64,akeepRecentTokens,bkeepRecentTokens),
        mergeOptional(~R.Record<CompactionModelOverride>,~(a => b => mergeMap(~CompactionModelOverride,~mergeCompactionModelOverride,a,b)),amodelOverrides,bmodelOverrides)}

def mergeBranchSummarySettings(base: BranchSummarySettings,override: BranchSummarySettings) -> BranchSummarySettings:
  match base override:
    case BranchSummarySettings{areserveTokens,askipPrompt} BranchSummarySettings{breserveTokens,bskipPrompt}:
      BranchSummarySettings{prefer(W.U64,areserveTokens,breserveTokens),
        prefer(Bool,askipPrompt,bskipPrompt)}

def mergeProviderRetrySettings(base: ProviderRetrySettings,override: ProviderRetrySettings) -> ProviderRetrySettings:
  match base override:
    case ProviderRetrySettings{atimeoutMs,amaxRetries,amaxRetryDelayMs} ProviderRetrySettings{btimeoutMs,bmaxRetries,bmaxRetryDelayMs}:
      ProviderRetrySettings{prefer(W.U64,atimeoutMs,btimeoutMs),
        prefer(W.U64,amaxRetries,bmaxRetries),
        prefer(W.U64,amaxRetryDelayMs,bmaxRetryDelayMs)}

def mergeRetrySettings(base: RetrySettings,override: RetrySettings) -> RetrySettings:
  match base override:
    case RetrySettings{aenabled,amaxRetries,abaseDelayMs,amaxAgentDelayMs,aprovider} RetrySettings{benabled,bmaxRetries,bbaseDelayMs,bmaxAgentDelayMs,bprovider}:
      RetrySettings{prefer(Bool,aenabled,benabled),
        prefer(W.U64,amaxRetries,bmaxRetries),
        prefer(W.U64,abaseDelayMs,bbaseDelayMs),
        prefer(W.U64,amaxAgentDelayMs,bmaxAgentDelayMs),
        mergeOptional(~ProviderRetrySettings,~mergeProviderRetrySettings,aprovider,bprovider)}

def mergeTerminalSettings(base: TerminalSettings,override: TerminalSettings) -> TerminalSettings:
  match base override:
    case TerminalSettings{ashowImages,aimageWidthCells,aclearOnShrink,ashowTerminalProgress,ahyperlinks,aimages,atrueColor} TerminalSettings{bshowImages,bimageWidthCells,bclearOnShrink,bshowTerminalProgress,bhyperlinks,bimages,btrueColor}:
      TerminalSettings{prefer(Bool,ashowImages,bshowImages),
        prefer(W.U64,aimageWidthCells,bimageWidthCells),
        prefer(Bool,aclearOnShrink,bclearOnShrink),
        prefer(Bool,ashowTerminalProgress,bshowTerminalProgress),
        prefer(AutomaticBoolean,ahyperlinks,bhyperlinks),
        prefer(TerminalImages,aimages,bimages),
        prefer(AutomaticBoolean,atrueColor,btrueColor)}

def mergeImageSettings(base: ImageSettings,override: ImageSettings) -> ImageSettings:
  match base override:
    case ImageSettings{aautoResize,ablockImages} ImageSettings{bautoResize,bblockImages}:
      ImageSettings{prefer(Bool,aautoResize,bautoResize),
        prefer(Bool,ablockImages,bblockImages)}

def mergeThinkingBudgetsSettings(base: ThinkingBudgetsSettings,override: ThinkingBudgetsSettings) -> ThinkingBudgetsSettings:
  match base override:
    case ThinkingBudgetsSettings{aminimal,alow,amedium,ahigh} ThinkingBudgetsSettings{bminimal,blow,bmedium,bhigh}:
      ThinkingBudgetsSettings{prefer(W.U64,aminimal,bminimal),
        prefer(W.U64,alow,blow),
        prefer(W.U64,amedium,bmedium),
        prefer(W.U64,ahigh,bhigh)}

def mergeMarkdownSettings(base: MarkdownSettings,override: MarkdownSettings) -> MarkdownSettings:
  match base override:
    case MarkdownSettings{acodeBlockIndent,amermaid} MarkdownSettings{bcodeBlockIndent,bmermaid}:
      MarkdownSettings{prefer(String,acodeBlockIndent,bcodeBlockIndent),
        prefer(MermaidRenderingMode,amermaid,bmermaid)}

def mergeWarningSettings(base: WarningSettings,override: WarningSettings) -> WarningSettings:
  match base override:
    case WarningSettings{aanthropicExtraUsage} WarningSettings{banthropicExtraUsage}:
      WarningSettings{prefer(Bool,aanthropicExtraUsage,banthropicExtraUsage)}

def mergePackageFilter(base: PackageFilter,override: PackageFilter) -> PackageFilter:
  match base override:
    case PackageFilter{aautoload,aextensions,askills,aprompts,athemes} PackageFilter{bautoload,bextensions,bskills,bprompts,bthemes}:
      PackageFilter{prefer(Bool,aautoload,bautoload),
        prefer(List<&2,String>,aextensions,bextensions),
        prefer(List<&2,String>,askills,bskills),
        prefer(List<&2,String>,aprompts,bprompts),
        prefer(List<&2,String>,athemes,bthemes)}

def mergeSetting(base: Maybe<&2,Setting>,override: Setting) -> Setting:
  match base override:
    case Some{Compaction{a}} Compaction{b}: Compaction{mergeCompactionSettings(a,b)}
    case Some{BranchSummary{a}} BranchSummary{b}: BranchSummary{mergeBranchSummarySettings(a,b)}
    case Some{Retry{a}} Retry{b}: Retry{mergeRetrySettings(a,b)}
    case Some{Terminal{a}} Terminal{b}: Terminal{mergeTerminalSettings(a,b)}
    case Some{Images{a}} Images{b}: Images{mergeImageSettings(a,b)}
    case Some{ThinkingBudgets{a}} ThinkingBudgets{b}: ThinkingBudgets{mergeThinkingBudgetsSettings(a,b)}
    case Some{Markdown{a}} Markdown{b}: Markdown{mergeMarkdownSettings(a,b)}
    case Some{Warnings{a}} Warnings{b}: Warnings{mergeWarningSettings(a,b)}
    case Some{ModelThinkingLevels{a}} ModelThinkingLevels{b}: ModelThinkingLevels{mergeMap(~Ai.ModelThinkingLevel,~(old => next => next),a,b)}
    case _ value: value

def mergeTypedFields(fields: List<&2,R.Property<Setting>>,base: R.Record<Setting>) -> R.Record<Setting>:
  match fields:
    case Nil{}: base
    case R.Property{+key,value} <> rest:
      +base = base
      mergeTypedFields(rest,R.set(Setting,base,key,mergeSetting(R.get(Setting,base,key),value)))
def mergeSettings(base: Settings,override: Settings) -> Settings:
  match base override:
    case Settings{a,unknownA} Settings{b,unknownB}: Settings{mergeTypedFields(R.entries(Setting,b),a),mergeRecords(unknownA,unknownB)}
def get(settings: Settings,key: String) -> Maybe<&2,Setting>:
  match settings:
    case Settings{fields,_}: R.get(Setting,fields,key)
def put(+value: Setting,settings: Settings) -> Settings:
  match settings:
    case Settings{fields,unknown}: Settings{R.set(Setting,fields,name(value),value),unknown}
def remove(settings: Settings,key: String) -> Settings:
  match settings:
    case Settings{fields,unknown}: Settings{R.remove(Setting,fields,key),unknown}


type SettingsScope is Data:
  Global{}
  Project{}
type SettingsManagerCreateOptions is Data:
  SettingsManagerCreateOptions{projectTrusted: Bool}
type SettingsPaths is Data:
  SettingsPaths{global: Maybe<&2,String>,project: Maybe<&2,String>}
type SettingsError is Data:
  SettingsError{scope: SettingsScope,path: Maybe<&2,String>,error: Error}
type DirtyField is Data:
  DirtyField{field: String,nested: Maybe<&2,String>}
type ScopedSettings is Data:
  ScopedSettings{settings: Settings,loadError: Maybe<&2,Error>,modified: List<&2,DirtyField>}
type PendingWrite is Data:
  PendingWrite{scope: SettingsScope,snapshot: Settings,modified: List<&2,DirtyField>}
type SettingsManager is Data:
  SettingsManager{global: ScopedSettings,project: ScopedSettings,effective: Settings,projectTrusted: Bool,pending: List<&2,PendingWrite>,errors: List<&2,SettingsError>,paths: SettingsPaths}
def options() -> SettingsManagerCreateOptions: SettingsManagerCreateOptions{True{}}
def scopedSettings(value: ScopedSettings) -> Settings:
  match value:
    case ScopedSettings{settings,_,_}: settings
def getGlobalSettings(value: SettingsManager) -> Settings:
  match value:
    case SettingsManager{global,_,_,_,_,_,_}: scopedSettings(global)
def getProjectSettings(value: SettingsManager) -> Settings:
  match value:
    case SettingsManager{_,project,_,_,_,_,_}: scopedSettings(project)
def effective(value: SettingsManager) -> Settings:
  match value:
    case SettingsManager{_,_,settings,_,_,_,_}: settings
def isProjectTrusted(value: SettingsManager) -> Bool:
  match value:
    case SettingsManager{_,_,_,trusted,_,_,_}: trusted
def sameScope(left: SettingsScope,right: SettingsScope) -> Bool:
  match left right:
    case Global{} Global{}: True{}
    case Project{} Project{}: True{}
    case _ _: False{}
def scopedPath(scope: SettingsScope,paths: SettingsPaths) -> Maybe<&2,String>:
  match scope paths:
    case Global{} SettingsPaths{path,_}: path
    case Project{} SettingsPaths{_,path}: path
def recorded(+scope: SettingsScope,cause: Error,state: SettingsManager) -> SettingsManager:
  match state:
    case SettingsManager{global,project,value,trusted,pending,errors,+paths}:
      SettingsManager{global,project,value,trusted,pending,List.append(&2,SettingsError,errors,SettingsError{scope,scopedPath(scope,paths),cause} <> Nil{}),paths}
def drainErrors(state: SettingsManager) -> SettingsManager & List<&2,SettingsError>:
  match state:
    case SettingsManager{global,project,value,trusted,pending,errors,paths}: (SettingsManager{global,project,value,trusted,pending,Nil{},paths},errors)
def applied(overrides: Settings,state: SettingsManager) -> SettingsManager:
  match state:
    case SettingsManager{global,project,value,trusted,pending,errors,paths}: SettingsManager{global,project,mergeSettings(value,overrides),trusted,pending,errors,paths}
def applyOverrides(overrides: Settings,state: SettingsManager) -> Outcome(SettingsManager):
  do Result<&2,&2,Error,SettingsManager>:
    valid : Settings <- decode(toValue(overrides))
    return applied(valid,state)
def enqueue(scope: SettingsScope,value: ScopedSettings,pending: List<&2,PendingWrite>) -> List<&2,PendingWrite>:
  match value:
    case ScopedSettings{_,Some{_},_}: pending
    case ScopedSettings{settings,None{},modified}: PendingWrite{scope,settings,modified} <> pending
def updated(scope: SettingsScope,+next: ScopedSettings,state: SettingsManager) -> SettingsManager:
  match scope state:
    case Global{} SettingsManager{_,+project,_,trusted,pending,errors,paths}:
      SettingsManager{next,project,mergeSettings(scopedSettings(next),scopedSettings(project)),trusted,enqueue(Global{},next,pending),errors,paths}
    case Project{} SettingsManager{+global,_,_,trusted,pending,errors,paths}:
      SettingsManager{global,next,mergeSettings(scopedSettings(global),scopedSettings(next)),trusted,enqueue(Project{},next,pending),errors,paths}
def selectedScope(scope: SettingsScope,state: SettingsManager) -> ScopedSettings:
  match scope state:
    case Global{} SettingsManager{global,_,_,_,_,_,_}: global
    case Project{} SettingsManager{_,project,_,_,_,_,_}: project
def changed(value: Settings,dirty: DirtyField,previous: ScopedSettings) -> ScopedSettings:
  match previous:
    case ScopedSettings{_,loadError,modified}: ScopedSettings{value,loadError,dirty <> modified}
def writeAllowed(scope: SettingsScope,trusted: Bool) -> Outcome(Unit):
  match scope trusted:
    case Project{} False{}: Fail{UntrustedProject{}}
    case _ _: Done{Unit{}}
def updateSettings(+scope: SettingsScope,value: Settings,dirty: DirtyField,+state: SettingsManager) -> Outcome(SettingsManager):
  do Result<&2,&2,Error,SettingsManager>:
    ignored : Unit <- writeAllowed(scope,isProjectTrusted(state))
    valid : Settings <- decode(toValue(value))
    return updated(scope,changed(valid,dirty,selectedScope(scope,state)),state)
def set(+value: Setting,+state: SettingsManager) -> Outcome(SettingsManager):
  updateSettings(Global{},put(value,getGlobalSettings(state)),DirtyField{name(value),None{}},state)
def setProject(+value: Setting,+state: SettingsManager) -> Outcome(SettingsManager):
  updateSettings(Project{},put(value,getProjectSettings(state)),DirtyField{name(value),None{}},state)
def unset(+key: String,+state: SettingsManager) -> Outcome(SettingsManager):
  updateSettings(Global{},remove(getGlobalSettings(state),key),DirtyField{key,None{}},state)
def setNested(value: Setting,field: String,nested: String,+state: SettingsManager) -> Outcome(SettingsManager):
  updateSettings(Global{},put(value,getGlobalSettings(state)),DirtyField{field,Some{nested}},state)

# A storage transaction returns settings to the caller and, independently, an
# optional replacement document. None means read-only, even for a missing file.
type StorageUpdate is Data:
  StorageUpdate{settings: Settings,next: Maybe<&2,String>}
def loadContent(value: Maybe<&2,String>) -> Outcome(Settings):
  match value:
    case None{}: Done{empty()}
    case Some{""}: Done{empty()}
    case Some{content}: parse(content)
def readTransaction(content: Maybe<&2,String>) -> Outcome(StorageUpdate):
  do Result<&2,&2,Error,StorageUpdate>:
    loaded : Settings <- loadContent(content)
    return StorageUpdate{loaded,None{}}
def patchField(value: Maybe<&2,V.Value>,key: String,fields: R.Record<V.Value>) -> R.Record<V.Value>:
  match value:
    case None{}: R.remove(V.Value,fields,key)
    case Some{value}: R.set(V.Value,fields,key,value)
def patchNested(value: Maybe<&2,V.Value>,+key: String,sub: String,+fields: R.Record<V.Value>) -> R.Record<V.Value>:
  R.set(V.Value,fields,key,V.ObjectValue{patchField(value,sub,objectOrEmpty(R.get(V.Value,fields,key)))})
def patchFields(dirty: List<&2,DirtyField>,+snapshot: R.Record<V.Value>,current: R.Record<V.Value>) -> R.Record<V.Value>:
  match dirty:
    case Nil{}: current
    case DirtyField{+key,None{}} <> rest: patchFields(rest,snapshot,patchField(R.get(V.Value,snapshot,key),key,current))
    case DirtyField{+key,Some{+sub}} <> rest: patchFields(rest,snapshot,patchNested(R.get(V.Value,objectOrEmpty(R.get(V.Value,snapshot,key)),sub),key,sub,current))
def persistenceValue(snapshot: V.Value,dirty: List<&2,DirtyField>,current: V.Value) -> V.Value:
  match snapshot current:
    case V.ObjectValue{snapshot} V.ObjectValue{current}: V.ObjectValue{patchFields(dirty,snapshot,current)}
    case _ _: V.ObjectValue{R.new(V.Value)}
def writeTransaction(snapshot: Settings,dirty: List<&2,DirtyField>,content: Maybe<&2,String>) -> Outcome(StorageUpdate):
  do Result<&2,&2,Error,StorageUpdate>:
    current : Settings <- loadContent(content)
    +next : Settings <- decode(persistenceValue(toValue(snapshot),dirty,toValue(current)))
    return StorageUpdate{next,Some{serialize(next)}}

# Storage policy is injectable as a closed function plus owned backend state.
# Transactions run exactly once under the backend's lock and return that state.
def SettingsStorage(-S: Type) -> Type:
  S -> SettingsScope -> Bool -> (Maybe<&2,String> -> Outcome(StorageUpdate)) -> IO(S & Outcome(Settings))
type InMemorySettingsStorage is Data:
  InMemorySettingsStorage{global: Maybe<&2,String>,project: Maybe<&2,String>}
def memoryResult(scope: SettingsScope,previous: InMemorySettingsStorage,result: Outcome(StorageUpdate)) -> InMemorySettingsStorage & Outcome(Settings):
  match scope previous result:
    case _ previous Fail{cause}: (previous,Fail{cause})
    case Global{} InMemorySettingsStorage{old,project} Done{StorageUpdate{settings,next}}: (InMemorySettingsStorage{prefer(String,old,next),project},Done{settings})
    case Project{} InMemorySettingsStorage{global,old} Done{StorageUpdate{settings,next}}: (InMemorySettingsStorage{global,prefer(String,old,next)},Done{settings})
def memoryContent(scope: SettingsScope,storage: InMemorySettingsStorage) -> Maybe<&2,String>:
  match scope storage:
    case Global{} InMemorySettingsStorage{content,_}: content
    case Project{} InMemorySettingsStorage{_,content}: content
def memoryWithLock(storage: InMemorySettingsStorage,scope: SettingsScope,writable: Bool,transaction: Maybe<&2,String> -> Outcome(StorageUpdate)) -> IO(InMemorySettingsStorage & Outcome(Settings)):
  +storage = storage
  +scope = scope
  IO.pure(InMemorySettingsStorage & Outcome(Settings),memoryResult(scope,storage,transaction(memoryContent(scope,storage))))
def loadedScope(value: Outcome(Settings)) -> ScopedSettings:
  match value:
    case Done{settings}: ScopedSettings{settings,None{},Nil{}}
    case Fail{cause}: ScopedSettings{empty(),Some{cause},Nil{}}
def loadErrors(+scope: SettingsScope,value: ScopedSettings,paths: SettingsPaths) -> List<&2,SettingsError>:
  match value:
    case ScopedSettings{_,None{},_}: Nil{}
    case ScopedSettings{_,Some{cause},_}: SettingsError{scope,scopedPath(scope,paths),cause} <> Nil{}
def initial(+global: ScopedSettings,+project: ScopedSettings,trusted: Bool,+paths: SettingsPaths) -> SettingsManager:
  SettingsManager{global,project,mergeSettings(scopedSettings(global),scopedSettings(project)),trusted,Nil{},List.append(&2,SettingsError,loadErrors(Global{},global,paths),loadErrors(Project{},project,paths)),paths}
def trustedProject(~S: Type,~withLock: SettingsStorage(S),trusted: Bool,storage: S) -> IO(S & Outcome(Settings)):
  match trusted:
    case True{}: withLock(storage,Project{},False{},readTransaction)
    case False{}: IO.pure(S & Outcome(Settings),(storage,Done{empty()}))
def initialized(~S: Type,value: S & Outcome(Settings),global: ScopedSettings,trusted: Bool,paths: SettingsPaths) -> S & SettingsManager:
  match value:
    case (storage,project): (storage,initial(global,loadedScope(project),trusted,paths))
def fromGlobal(~S: Type,~withLock: SettingsStorage(S),value: S & Outcome(Settings),+trusted: Bool,paths: SettingsPaths) -> IO(S & SettingsManager):
  match value:
    case (storage,global):
      do IO<S & SettingsManager>:
        project : S & Outcome(Settings) <- trustedProject(~S,~withLock,trusted,storage)
        return initialized(~S,project,loadedScope(global),trusted,paths)
def fromStorageWithPaths(~S: Type,~withLock: SettingsStorage(S),storage: S,options: SettingsManagerCreateOptions,paths: SettingsPaths) -> IO(S & SettingsManager):
  match options:
    case SettingsManagerCreateOptions{trusted}:
      do IO<S & SettingsManager>:
        global : S & Outcome(Settings) <- withLock(storage,Global{},False{},readTransaction)
        fromGlobal(~S,~withLock,global,trusted,paths)
def fromStorage(~S: Type,~withLock: SettingsStorage(S),storage: S,options: SettingsManagerCreateOptions) -> IO(S & SettingsManager):
  fromStorageWithPaths(~S,~withLock,storage,options,SettingsPaths{None{},None{}})
def inMemory(value: Settings,options: SettingsManagerCreateOptions) -> IO(InMemorySettingsStorage & SettingsManager):
  fromStorage(~InMemorySettingsStorage,~memoryWithLock,InMemorySettingsStorage{Some{serialize(value)},None{}},options)
def clearModified(value: ScopedSettings) -> ScopedSettings:
  match value:
    case ScopedSettings{settings,error,_}: ScopedSettings{settings,error,Nil{}}
def clearScope(scope: SettingsScope,state: SettingsManager) -> SettingsManager:
  match scope state:
    case Global{} SettingsManager{global,project,value,trusted,pending,errors,paths}: SettingsManager{clearModified(global),project,value,trusted,pending,errors,paths}
    case Project{} SettingsManager{global,project,value,trusted,pending,errors,paths}: SettingsManager{global,clearModified(project),value,trusted,pending,errors,paths}
def writeFinished(scope: SettingsScope,result: Outcome(Settings),state: SettingsManager) -> SettingsManager:
  match result:
    case Done{_}: clearScope(scope,state)
    case Fail{cause}: recorded(scope,cause,state)
def attempted(~S: Type,~withLock: SettingsStorage(S),allowed: Outcome(Unit),storage: S,scope: SettingsScope,snapshot: Settings,modified: List<&2,DirtyField>) -> IO(S & Outcome(Settings)):
  match allowed:
    case Fail{cause}: IO.pure(S & Outcome(Settings),(storage,Fail{cause}))
    case Done{_}: withLock(storage,scope,True{},content => writeTransaction(snapshot,modified,content))
def writePending(~S: Type,~withLock: SettingsStorage(S),storage: S,value: PendingWrite,trusted: Bool) -> IO(S & Outcome(Settings)):
  match value:
    case PendingWrite{+scope,snapshot,modified}: attempted(~S,~withLock,writeAllowed(scope,trusted),storage,scope,snapshot,modified)
def writeScope(value: PendingWrite) -> SettingsScope:
  match value:
    case PendingWrite{scope,_,_}: scope
def writeState(~S: Type,value: S & Outcome(Settings),scope: SettingsScope,state: SettingsManager) -> S & SettingsManager:
  match value:
    case (storage,result): (storage,writeFinished(scope,result,state))
def flushLoop(~S: Type,~withLock: SettingsStorage(S),writes: List<&2,PendingWrite>,value: S & SettingsManager) -> IO(S & SettingsManager):
  match writes value:
    case Nil{} value: IO.pure(S & SettingsManager,value)
    case +write <> rest Tuple{storage,+state}:
      do IO<S & SettingsManager>:
        result : S & Outcome(Settings) <- writePending(~S,~withLock,storage,write,isProjectTrusted(state))
        flushLoop(~S,~withLock,rest,writeState(~S,result,writeScope(write),state))
def flush(~S: Type,~withLock: SettingsStorage(S),storage: S,state: SettingsManager) -> IO(S & SettingsManager):
  match state:
    case SettingsManager{global,project,value,trusted,pending,errors,paths}:
      flushLoop(~S,~withLock,List.reverse(&2,PendingWrite,pending),(storage,SettingsManager{global,project,value,trusted,Nil{},errors,paths}))
def reloadedScope(value: Outcome(Settings),previous: ScopedSettings) -> ScopedSettings:
  match value:
    case Done{settings}: ScopedSettings{settings,None{},Nil{}}
    case Fail{cause}: ScopedSettings{scopedSettings(previous),Some{cause},Nil{}}
def reloaded(global: Outcome(Settings),project: Outcome(Settings),state: SettingsManager) -> SettingsManager:
  match state:
    case SettingsManager{oldGlobal,oldProject,_,trusted,pending,errors,+paths}:
      +global = reloadedScope(global,oldGlobal)
      +project = reloadedScope(project,oldProject)
      SettingsManager{global,project,mergeSettings(scopedSettings(global),scopedSettings(project)),trusted,pending,List.append(&2,SettingsError,errors,List.append(&2,SettingsError,loadErrors(Global{},global,paths),loadErrors(Project{},project,paths))),paths}
def reloadProjectResult(~S: Type,value: S & Outcome(Settings),global: Outcome(Settings),state: SettingsManager) -> S & SettingsManager:
  match value:
    case (storage,project): (storage,reloaded(global,project,state))
def reloadGlobalResult(~S: Type,~withLock: SettingsStorage(S),value: S & Outcome(Settings),+state: SettingsManager) -> IO(S & SettingsManager):
  match value:
    case (storage,global):
      do IO<S & SettingsManager>:
        project : S & Outcome(Settings) <- trustedProject(~S,~withLock,isProjectTrusted(state),storage)
        return reloadProjectResult(~S,project,global,state)
def reloadFlushed(~S: Type,~withLock: SettingsStorage(S),value: S & SettingsManager) -> IO(S & SettingsManager):
  match value:
    case (storage,state):
      do IO<S & SettingsManager>:
        global : S & Outcome(Settings) <- withLock(storage,Global{},False{},readTransaction)
        reloadGlobalResult(~S,~withLock,global,state)
def reload(~S: Type,~withLock: SettingsStorage(S),storage: S,state: SettingsManager) -> IO(S & SettingsManager):
  do IO<S & SettingsManager>:
    value : S & SettingsManager <- flush(~S,~withLock,storage,state)
    reloadFlushed(~S,~withLock,value)
def trustLoaded(result: Outcome(Settings),trusted: Bool,state: SettingsManager) -> SettingsManager:
  match state:
    case SettingsManager{+global,_,_,_,pending,errors,+paths}:
      +project = loadedScope(result)
      SettingsManager{global,project,mergeSettings(scopedSettings(global),scopedSettings(project)),trusted,pending,List.append(&2,SettingsError,errors,loadErrors(Project{},project,paths)),paths}
def trustResult(~S: Type,value: S & Outcome(Settings),trusted: Bool,state: SettingsManager) -> S & SettingsManager:
  match value:
    case (storage,result): (storage,trustLoaded(result,trusted,state))
def setProjectTrusted(~S: Type,~withLock: SettingsStorage(S),storage: S,+trusted: Bool,+state: SettingsManager) -> IO(S & SettingsManager):
  Bool.pick(S -> IO(S & SettingsManager),((trusted && isProjectTrusted(state)) || (Bool.not(trusted) && Bool.not(isProjectTrusted(state)))),storage => IO.pure(S & SettingsManager,(storage,state)),storage =>
    do IO<S & SettingsManager>:
      value : S & Outcome(Settings) <- trustedProject(~S,~withLock,trusted,storage)
      return trustResult(~S,value,trusted,state))(storage)
def selectedLastChangelogVersion(value: Maybe<&2,Setting>) -> Maybe<&2,String>:
  match value:
    case Some{LastChangelogVersion{value}}: Some{value}
    case _: None{}

def selectedDefaultProvider(value: Maybe<&2,Setting>) -> Maybe<&2,String>:
  match value:
    case Some{DefaultProvider{value}}: Some{value}
    case _: None{}

def selectedDefaultModel(value: Maybe<&2,Setting>) -> Maybe<&2,String>:
  match value:
    case Some{DefaultModel{value}}: Some{value}
    case _: None{}

def selectedTheme(value: Maybe<&2,Setting>) -> Maybe<&2,String>:
  match value:
    case Some{Theme{value}}: Some{value}
    case _: None{}

def selectedExternalEditor(value: Maybe<&2,Setting>) -> Maybe<&2,String>:
  match value:
    case Some{ExternalEditor{value}}: Some{value}
    case _: None{}

def selectedShellPath(value: Maybe<&2,Setting>) -> Maybe<&2,String>:
  match value:
    case Some{ShellPath{value}}: Some{value}
    case _: None{}

def selectedShellCommandPrefix(value: Maybe<&2,Setting>) -> Maybe<&2,String>:
  match value:
    case Some{ShellCommandPrefix{value}}: Some{value}
    case _: None{}

def selectedTrackingId(value: Maybe<&2,Setting>) -> Maybe<&2,String>:
  match value:
    case Some{TrackingId{value}}: Some{value}
    case _: None{}

def selectedSessionDir(value: Maybe<&2,Setting>) -> Maybe<&2,String>:
  match value:
    case Some{SessionDir{value}}: Some{value}
    case _: None{}

def selectedHttpProxy(value: Maybe<&2,Setting>) -> Maybe<&2,String>:
  match value:
    case Some{HttpProxy{value}}: Some{value}
    case _: None{}

def selectedHideThinkingBlock(value: Maybe<&2,Setting>) -> Maybe<&2,Bool>:
  match value:
    case Some{HideThinkingBlock{value}}: Some{value}
    case _: None{}

def selectedShowCacheMissNotices(value: Maybe<&2,Setting>) -> Maybe<&2,Bool>:
  match value:
    case Some{ShowCacheMissNotices{value}}: Some{value}
    case _: None{}

def selectedQuietStartup(value: Maybe<&2,Setting>) -> Maybe<&2,Bool>:
  match value:
    case Some{QuietStartup{value}}: Some{value}
    case _: None{}

def selectedCollapseChangelog(value: Maybe<&2,Setting>) -> Maybe<&2,Bool>:
  match value:
    case Some{CollapseChangelog{value}}: Some{value}
    case _: None{}

def selectedEnableInstallTelemetry(value: Maybe<&2,Setting>) -> Maybe<&2,Bool>:
  match value:
    case Some{EnableInstallTelemetry{value}}: Some{value}
    case _: None{}

def selectedEnableAnalytics(value: Maybe<&2,Setting>) -> Maybe<&2,Bool>:
  match value:
    case Some{EnableAnalytics{value}}: Some{value}
    case _: None{}

def selectedEnableSkillCommands(value: Maybe<&2,Setting>) -> Maybe<&2,Bool>:
  match value:
    case Some{EnableSkillCommands{value}}: Some{value}
    case _: None{}

def selectedShowHardwareCursor(value: Maybe<&2,Setting>) -> Maybe<&2,Bool>:
  match value:
    case Some{ShowHardwareCursor{value}}: Some{value}
    case _: None{}

def selectedFullscreenCopyOnSelect(value: Maybe<&2,Setting>) -> Maybe<&2,Bool>:
  match value:
    case Some{FullscreenCopyOnSelect{value}}: Some{value}
    case _: None{}

def selectedEditorPaddingX(value: Maybe<&2,Setting>) -> Maybe<&2,W.U64>:
  match value:
    case Some{EditorPaddingX{value}}: Some{value}
    case _: None{}

def selectedAutocompleteMaxVisible(value: Maybe<&2,Setting>) -> Maybe<&2,W.U64>:
  match value:
    case Some{AutocompleteMaxVisible{value}}: Some{value}
    case _: None{}

def selectedHttpIdleTimeoutMs(value: Maybe<&2,Setting>) -> Maybe<&2,W.U64>:
  match value:
    case Some{HttpIdleTimeoutMs{value}}: Some{value}
    case _: None{}

def selectedWebsocketConnectTimeoutMs(value: Maybe<&2,Setting>) -> Maybe<&2,W.U64>:
  match value:
    case Some{WebsocketConnectTimeoutMs{value}}: Some{value}
    case _: None{}

def selectedNpmCommand(value: Maybe<&2,Setting>) -> Maybe<&2,List<&2,String>>:
  match value:
    case Some{NpmCommand{value}}: Some{value}
    case _: None{}

def selectedExtensions(value: Maybe<&2,Setting>) -> Maybe<&2,List<&2,String>>:
  match value:
    case Some{Extensions{value}}: Some{value}
    case _: None{}

def selectedSkills(value: Maybe<&2,Setting>) -> Maybe<&2,List<&2,String>>:
  match value:
    case Some{Skills{value}}: Some{value}
    case _: None{}

def selectedPrompts(value: Maybe<&2,Setting>) -> Maybe<&2,List<&2,String>>:
  match value:
    case Some{Prompts{value}}: Some{value}
    case _: None{}

def selectedThemes(value: Maybe<&2,Setting>) -> Maybe<&2,List<&2,String>>:
  match value:
    case Some{Themes{value}}: Some{value}
    case _: None{}

def selectedEnabledModels(value: Maybe<&2,Setting>) -> Maybe<&2,List<&2,String>>:
  match value:
    case Some{EnabledModels{value}}: Some{value}
    case _: None{}

def selectedDefaultTools(value: Maybe<&2,Setting>) -> Maybe<&2,List<&2,String>>:
  match value:
    case Some{DefaultTools{value}}: Some{value}
    case _: None{}

def selectedDefaultThinkingLevel(value: Maybe<&2,Setting>) -> Maybe<&2,Ai.ModelThinkingLevel>:
  match value:
    case Some{DefaultThinkingLevel{value}}: Some{value}
    case _: None{}

def selectedModelThinkingLevels(value: Maybe<&2,Setting>) -> Maybe<&2,R.Record<Ai.ModelThinkingLevel>>:
  match value:
    case Some{ModelThinkingLevels{value}}: Some{value}
    case _: None{}

def selectedTransport(value: Maybe<&2,Setting>) -> Maybe<&2,Ai.Transport>:
  match value:
    case Some{Transport{value}}: Some{value}
    case _: None{}

def selectedSteeringMode(value: Maybe<&2,Setting>) -> Maybe<&2,Agent.QueueMode>:
  match value:
    case Some{SteeringMode{value}}: Some{value}
    case _: None{}

def selectedFollowUpMode(value: Maybe<&2,Setting>) -> Maybe<&2,Agent.QueueMode>:
  match value:
    case Some{FollowUpMode{value}}: Some{value}
    case _: None{}

def selectedPackages(value: Maybe<&2,Setting>) -> Maybe<&2,List<&2,PackageSource>>:
  match value:
    case Some{Packages{value}}: Some{value}
    case _: None{}

def selectedDefaultProjectTrust(value: Maybe<&2,Setting>) -> Maybe<&2,DefaultProjectTrust>:
  match value:
    case Some{DefaultProjectTrust{value}}: Some{value}
    case _: None{}

def selectedDoubleEscapeAction(value: Maybe<&2,Setting>) -> Maybe<&2,DoubleEscapeAction>:
  match value:
    case Some{DoubleEscapeAction{value}}: Some{value}
    case _: None{}

def selectedTreeFilterMode(value: Maybe<&2,Setting>) -> Maybe<&2,TreeFilterMode>:
  match value:
    case Some{TreeFilterMode{value}}: Some{value}
    case _: None{}

def selectedOutputPad(value: Maybe<&2,Setting>) -> Maybe<&2,OutputPadding>:
  match value:
    case Some{OutputPad{value}}: Some{value}
    case _: None{}

def selectedTuiMode(value: Maybe<&2,Setting>) -> Maybe<&2,TuiMode>:
  match value:
    case Some{TuiMode{value}}: Some{value}
    case _: None{}

def selectedFullscreenExitOutput(value: Maybe<&2,Setting>) -> Maybe<&2,FullscreenExitOutput>:
  match value:
    case Some{FullscreenExitOutput{value}}: Some{value}
    case _: None{}

def selectedFullscreenScrollbar(value: Maybe<&2,Setting>) -> Maybe<&2,ScrollViewScrollbar>:
  match value:
    case Some{FullscreenScrollbar{value}}: Some{value}
    case _: None{}

def selectedCompaction(value: Maybe<&2,Setting>) -> Maybe<&2,CompactionSettings>:
  match value:
    case Some{Compaction{value}}: Some{value}
    case _: None{}

def selectedBranchSummary(value: Maybe<&2,Setting>) -> Maybe<&2,BranchSummarySettings>:
  match value:
    case Some{BranchSummary{value}}: Some{value}
    case _: None{}

def selectedRetry(value: Maybe<&2,Setting>) -> Maybe<&2,RetrySettings>:
  match value:
    case Some{Retry{value}}: Some{value}
    case _: None{}

def selectedTerminal(value: Maybe<&2,Setting>) -> Maybe<&2,TerminalSettings>:
  match value:
    case Some{Terminal{value}}: Some{value}
    case _: None{}

def selectedImages(value: Maybe<&2,Setting>) -> Maybe<&2,ImageSettings>:
  match value:
    case Some{Images{value}}: Some{value}
    case _: None{}

def selectedThinkingBudgets(value: Maybe<&2,Setting>) -> Maybe<&2,ThinkingBudgetsSettings>:
  match value:
    case Some{ThinkingBudgets{value}}: Some{value}
    case _: None{}

def selectedMarkdown(value: Maybe<&2,Setting>) -> Maybe<&2,MarkdownSettings>:
  match value:
    case Some{Markdown{value}}: Some{value}
    case _: None{}

def selectedWarnings(value: Maybe<&2,Setting>) -> Maybe<&2,WarningSettings>:
  match value:
    case Some{Warnings{value}}: Some{value}
    case _: None{}

def getLastChangelogVersion(state: SettingsManager) -> Maybe<&2,String>: selectedLastChangelogVersion(get(effective(state),"lastChangelogVersion"))

def getDefaultProvider(state: SettingsManager) -> Maybe<&2,String>: selectedDefaultProvider(get(effective(state),"defaultProvider"))

def getDefaultModel(state: SettingsManager) -> Maybe<&2,String>: selectedDefaultModel(get(effective(state),"defaultModel"))

def getThemeSetting(state: SettingsManager) -> Maybe<&2,String>: selectedTheme(get(effective(state),"theme"))

def getExternalEditorSetting(state: SettingsManager) -> Maybe<&2,String>: selectedExternalEditor(get(effective(state),"externalEditor"))

def getShellPathSetting(state: SettingsManager) -> Maybe<&2,String>: selectedShellPath(get(effective(state),"shellPath"))

def getShellCommandPrefix(state: SettingsManager) -> Maybe<&2,String>: selectedShellCommandPrefix(get(effective(state),"shellCommandPrefix"))

def getTrackingId(state: SettingsManager) -> Maybe<&2,String>: selectedTrackingId(get(effective(state),"trackingId"))

def getSessionDirSetting(state: SettingsManager) -> Maybe<&2,String>: selectedSessionDir(get(effective(state),"sessionDir"))

def getHttpProxy(state: SettingsManager) -> Maybe<&2,String>: selectedHttpProxy(get(effective(state),"httpProxy"))

def getHideThinkingBlock(state: SettingsManager) -> Bool: Maybe.default(&2,Bool,selectedHideThinkingBlock(get(effective(state),"hideThinkingBlock")),False{})

def getShowCacheMissNotices(state: SettingsManager) -> Bool: Maybe.default(&2,Bool,selectedShowCacheMissNotices(get(effective(state),"showCacheMissNotices")),False{})

def getQuietStartup(state: SettingsManager) -> Bool: Maybe.default(&2,Bool,selectedQuietStartup(get(effective(state),"quietStartup")),False{})

def getCollapseChangelog(state: SettingsManager) -> Bool: Maybe.default(&2,Bool,selectedCollapseChangelog(get(effective(state),"collapseChangelog")),False{})

def getEnableInstallTelemetry(state: SettingsManager) -> Bool: Maybe.default(&2,Bool,selectedEnableInstallTelemetry(get(effective(state),"enableInstallTelemetry")),True{})

def getEnableAnalytics(state: SettingsManager) -> Bool: Maybe.default(&2,Bool,selectedEnableAnalytics(get(effective(state),"enableAnalytics")),False{})

def getEnableSkillCommands(state: SettingsManager) -> Bool: Maybe.default(&2,Bool,selectedEnableSkillCommands(get(effective(state),"enableSkillCommands")),True{})

def getFullscreenCopyOnSelect(state: SettingsManager) -> Bool: Maybe.default(&2,Bool,selectedFullscreenCopyOnSelect(get(effective(state),"fullscreenCopyOnSelect")),True{})

def getEditorPaddingX(state: SettingsManager) -> W.U64: Maybe.default(&2,W.U64,selectedEditorPaddingX(get(effective(state),"editorPaddingX")),W.U64{0,0})

def getAutocompleteMaxVisible(state: SettingsManager) -> W.U64: Maybe.default(&2,W.U64,selectedAutocompleteMaxVisible(get(effective(state),"autocompleteMaxVisible")),W.U64{0,5})

def getHttpIdleTimeoutMs(state: SettingsManager) -> W.U64: Maybe.default(&2,W.U64,selectedHttpIdleTimeoutMs(get(effective(state),"httpIdleTimeoutMs")),W.U64{0,300000})

def getWebSocketConnectTimeoutMs(state: SettingsManager) -> Maybe<&2,W.U64>: selectedWebsocketConnectTimeoutMs(get(effective(state),"websocketConnectTimeoutMs"))

def getNpmCommand(state: SettingsManager) -> Maybe<&2,List<&2,String>>: selectedNpmCommand(get(effective(state),"npmCommand"))

def getExtensionPaths(state: SettingsManager) -> List<&2,String>: Maybe.default(&2,List<&2,String>,selectedExtensions(get(effective(state),"extensions")),Nil{})

def getSkillPaths(state: SettingsManager) -> List<&2,String>: Maybe.default(&2,List<&2,String>,selectedSkills(get(effective(state),"skills")),Nil{})

def getPromptTemplatePaths(state: SettingsManager) -> List<&2,String>: Maybe.default(&2,List<&2,String>,selectedPrompts(get(effective(state),"prompts")),Nil{})

def getThemePaths(state: SettingsManager) -> List<&2,String>: Maybe.default(&2,List<&2,String>,selectedThemes(get(effective(state),"themes")),Nil{})

def getEnabledModels(state: SettingsManager) -> Maybe<&2,List<&2,String>>: selectedEnabledModels(get(effective(state),"enabledModels"))

def getDefaultTools(state: SettingsManager) -> Maybe<&2,List<&2,String>>: selectedDefaultTools(get(effective(state),"defaultTools"))

def getDefaultThinkingLevel(state: SettingsManager) -> Maybe<&2,Ai.ModelThinkingLevel>: selectedDefaultThinkingLevel(get(effective(state),"defaultThinkingLevel"))

def getAllModelThinkingLevels(state: SettingsManager) -> R.Record<Ai.ModelThinkingLevel>: Maybe.default(&2,R.Record<Ai.ModelThinkingLevel>,selectedModelThinkingLevels(get(effective(state),"modelThinkingLevels")),R.new(Ai.ModelThinkingLevel))

def getTransport(state: SettingsManager) -> Ai.Transport: Maybe.default(&2,Ai.Transport,selectedTransport(get(effective(state),"transport")),Ai.AutoTransport{})

def getSteeringMode(state: SettingsManager) -> Agent.QueueMode: Maybe.default(&2,Agent.QueueMode,selectedSteeringMode(get(effective(state),"steeringMode")),Agent.OneAtATime{})

def getFollowUpMode(state: SettingsManager) -> Agent.QueueMode: Maybe.default(&2,Agent.QueueMode,selectedFollowUpMode(get(effective(state),"followUpMode")),Agent.OneAtATime{})

def getPackages(state: SettingsManager) -> List<&2,PackageSource>: Maybe.default(&2,List<&2,PackageSource>,selectedPackages(get(effective(state),"packages")),Nil{})

def getDefaultProjectTrust(state: SettingsManager) -> DefaultProjectTrust: Maybe.default(&2,DefaultProjectTrust,selectedDefaultProjectTrust(get(getGlobalSettings(state),"defaultProjectTrust")),Ask{})

def getDoubleEscapeAction(state: SettingsManager) -> DoubleEscapeAction: Maybe.default(&2,DoubleEscapeAction,selectedDoubleEscapeAction(get(effective(state),"doubleEscapeAction")),Tree{})

def getTreeFilterMode(state: SettingsManager) -> TreeFilterMode: Maybe.default(&2,TreeFilterMode,selectedTreeFilterMode(get(effective(state),"treeFilterMode")),DefaultFilter{})

def getOutputPad(state: SettingsManager) -> OutputPadding: Maybe.default(&2,OutputPadding,selectedOutputPad(get(effective(state),"outputPad")),OnePadding{})

def getTuiMode(state: SettingsManager) -> TuiMode: Maybe.default(&2,TuiMode,selectedTuiMode(get(effective(state),"tuiMode")),Regular{})

def getFullscreenExitOutput(state: SettingsManager) -> FullscreenExitOutput: Maybe.default(&2,FullscreenExitOutput,selectedFullscreenExitOutput(get(effective(state),"fullscreenExitOutput")),Transcript{})

def getFullscreenScrollbar(state: SettingsManager) -> ScrollViewScrollbar: Maybe.default(&2,ScrollViewScrollbar,selectedFullscreenScrollbar(get(effective(state),"fullscreenScrollbar")),ScrollAuto{})

def getTerminalSettings(state: SettingsManager) -> Maybe<&2,TerminalSettings>: selectedTerminal(get(effective(state),"terminal"))

def getThinkingBudgets(state: SettingsManager) -> Maybe<&2,ThinkingBudgetsSettings>: selectedThinkingBudgets(get(effective(state),"thinkingBudgets"))

def setLastChangelogVersion(value: String,state: SettingsManager) -> Outcome(SettingsManager): set(LastChangelogVersion{value},state)

def setDefaultProvider(value: String,state: SettingsManager) -> Outcome(SettingsManager): set(DefaultProvider{value},state)

def setDefaultModel(value: String,state: SettingsManager) -> Outcome(SettingsManager): set(DefaultModel{value},state)

def setTheme(value: String,state: SettingsManager) -> Outcome(SettingsManager): set(Theme{value},state)

def setShellPath(value: Maybe<&2,String>,state: SettingsManager) -> Outcome(SettingsManager):
  match value:
    case None{}: unset("shellPath",state)
    case Some{value}: set(ShellPath{value},state)

def setShellCommandPrefix(value: Maybe<&2,String>,state: SettingsManager) -> Outcome(SettingsManager):
  match value:
    case None{}: unset("shellCommandPrefix",state)
    case Some{value}: set(ShellCommandPrefix{value},state)

def setHideThinkingBlock(value: Bool,state: SettingsManager) -> Outcome(SettingsManager): set(HideThinkingBlock{value},state)

def setShowCacheMissNotices(value: Bool,state: SettingsManager) -> Outcome(SettingsManager): set(ShowCacheMissNotices{value},state)

def setQuietStartup(value: Bool,state: SettingsManager) -> Outcome(SettingsManager): set(QuietStartup{value},state)

def setCollapseChangelog(value: Bool,state: SettingsManager) -> Outcome(SettingsManager): set(CollapseChangelog{value},state)

def setEnableInstallTelemetry(value: Bool,state: SettingsManager) -> Outcome(SettingsManager): set(EnableInstallTelemetry{value},state)

def setEnableSkillCommands(value: Bool,state: SettingsManager) -> Outcome(SettingsManager): set(EnableSkillCommands{value},state)

def setShowHardwareCursor(value: Bool,state: SettingsManager) -> Outcome(SettingsManager): set(ShowHardwareCursor{value},state)

def setFullscreenCopyOnSelect(value: Bool,state: SettingsManager) -> Outcome(SettingsManager): set(FullscreenCopyOnSelect{value},state)

def setEditorPaddingX(value: W.U64,state: SettingsManager) -> Outcome(SettingsManager): set(EditorPaddingX{countMinimum(value,W.U64{0,3})},state)

def setAutocompleteMaxVisible(value: W.U64,state: SettingsManager) -> Outcome(SettingsManager): set(AutocompleteMaxVisible{countMaximum(W.U64{0,3},countMinimum(value,W.U64{0,20}))},state)

def setHttpIdleTimeoutMs(value: W.U64,state: SettingsManager) -> Outcome(SettingsManager): set(HttpIdleTimeoutMs{value},state)

def setNpmCommand(value: Maybe<&2,List<&2,String>>,state: SettingsManager) -> Outcome(SettingsManager):
  match value:
    case None{}: unset("npmCommand",state)
    case Some{value}: set(NpmCommand{value},state)

def setExtensionPaths(value: List<&2,String>,state: SettingsManager) -> Outcome(SettingsManager): set(Extensions{value},state)

def setSkillPaths(value: List<&2,String>,state: SettingsManager) -> Outcome(SettingsManager): set(Skills{value},state)

def setPromptTemplatePaths(value: List<&2,String>,state: SettingsManager) -> Outcome(SettingsManager): set(Prompts{value},state)

def setThemePaths(value: List<&2,String>,state: SettingsManager) -> Outcome(SettingsManager): set(Themes{value},state)

def setEnabledModels(value: Maybe<&2,List<&2,String>>,state: SettingsManager) -> Outcome(SettingsManager):
  match value:
    case None{}: unset("enabledModels",state)
    case Some{value}: set(EnabledModels{value},state)

def setDefaultThinkingLevel(value: Ai.ModelThinkingLevel,state: SettingsManager) -> Outcome(SettingsManager): set(DefaultThinkingLevel{value},state)

def setTransport(value: Ai.Transport,state: SettingsManager) -> Outcome(SettingsManager): set(Transport{value},state)

def setSteeringMode(value: Agent.QueueMode,state: SettingsManager) -> Outcome(SettingsManager): set(SteeringMode{value},state)

def setFollowUpMode(value: Agent.QueueMode,state: SettingsManager) -> Outcome(SettingsManager): set(FollowUpMode{value},state)

def setPackages(value: List<&2,PackageSource>,state: SettingsManager) -> Outcome(SettingsManager): set(Packages{value},state)

def setDefaultProjectTrust(value: DefaultProjectTrust,state: SettingsManager) -> Outcome(SettingsManager): set(DefaultProjectTrust{value},state)

def setDoubleEscapeAction(value: DoubleEscapeAction,state: SettingsManager) -> Outcome(SettingsManager): set(DoubleEscapeAction{value},state)

def setTreeFilterMode(value: TreeFilterMode,state: SettingsManager) -> Outcome(SettingsManager): set(TreeFilterMode{value},state)

def setOutputPad(value: OutputPadding,state: SettingsManager) -> Outcome(SettingsManager): set(OutputPad{value},state)

def setTuiMode(value: TuiMode,state: SettingsManager) -> Outcome(SettingsManager): set(TuiMode{value},state)

def setFullscreenExitOutput(value: FullscreenExitOutput,state: SettingsManager) -> Outcome(SettingsManager): set(FullscreenExitOutput{value},state)

def setFullscreenScrollbar(value: ScrollViewScrollbar,state: SettingsManager) -> Outcome(SettingsManager): set(FullscreenScrollbar{value},state)

def setProjectPackages(value: List<&2,PackageSource>,state: SettingsManager) -> Outcome(SettingsManager): setProject(Packages{value},state)

def setProjectExtensionPaths(value: List<&2,String>,state: SettingsManager) -> Outcome(SettingsManager): setProject(Extensions{value},state)

def setProjectSkillPaths(value: List<&2,String>,state: SettingsManager) -> Outcome(SettingsManager): setProject(Skills{value},state)

def setProjectPromptTemplatePaths(value: List<&2,String>,state: SettingsManager) -> Outcome(SettingsManager): setProject(Prompts{value},state)

def setProjectThemePaths(value: List<&2,String>,state: SettingsManager) -> Outcome(SettingsManager): setProject(Themes{value},state)

def compactionOptions(state: SettingsManager) -> CompactionSettings: Maybe.default(&2,CompactionSettings,selectedCompaction(get(effective(state),"compaction")),CompactionSettings{None{},None{},None{},None{}})

def branchSummaryOptions(state: SettingsManager) -> BranchSummarySettings: Maybe.default(&2,BranchSummarySettings,selectedBranchSummary(get(effective(state),"branchSummary")),BranchSummarySettings{None{},None{}})

def retryOptions(state: SettingsManager) -> RetrySettings: Maybe.default(&2,RetrySettings,selectedRetry(get(effective(state),"retry")),RetrySettings{None{},None{},None{},None{},None{}})

def terminalOptions(state: SettingsManager) -> TerminalSettings: Maybe.default(&2,TerminalSettings,selectedTerminal(get(effective(state),"terminal")),TerminalSettings{None{},None{},None{},None{},None{},None{},None{}})

def imagesOptions(state: SettingsManager) -> ImageSettings: Maybe.default(&2,ImageSettings,selectedImages(get(effective(state),"images")),ImageSettings{None{},None{}})

def thinkingBudgetsOptions(state: SettingsManager) -> ThinkingBudgetsSettings: Maybe.default(&2,ThinkingBudgetsSettings,selectedThinkingBudgets(get(effective(state),"thinkingBudgets")),ThinkingBudgetsSettings{None{},None{},None{},None{}})

def markdownOptions(state: SettingsManager) -> MarkdownSettings: Maybe.default(&2,MarkdownSettings,selectedMarkdown(get(effective(state),"markdown")),MarkdownSettings{None{},None{}})

def warningsOptions(state: SettingsManager) -> WarningSettings: Maybe.default(&2,WarningSettings,selectedWarnings(get(effective(state),"warnings")),WarningSettings{None{}})

def setCompactionEnabledGroup(value: Bool,previous: CompactionSettings) -> CompactionSettings:
  match previous:
    case CompactionSettings{_,reserveTokens,keepRecentTokens,modelOverrides}: CompactionSettings{Some{value},reserveTokens,keepRecentTokens,modelOverrides}

def setCompactionEnabled(value: Bool,+state: SettingsManager) -> Outcome(SettingsManager): setNested(Compaction{setCompactionEnabledGroup(value,Maybe.default(&2,CompactionSettings,selectedCompaction(get(getGlobalSettings(state),"compaction")),CompactionSettings{None{},None{},None{},None{}}))},"compaction","enabled",state)

def setRetryEnabledGroup(value: Bool,previous: RetrySettings) -> RetrySettings:
  match previous:
    case RetrySettings{_,maxRetries,baseDelayMs,maxAgentDelayMs,provider}: RetrySettings{Some{value},maxRetries,baseDelayMs,maxAgentDelayMs,provider}

def setRetryEnabled(value: Bool,+state: SettingsManager) -> Outcome(SettingsManager): setNested(Retry{setRetryEnabledGroup(value,Maybe.default(&2,RetrySettings,selectedRetry(get(getGlobalSettings(state),"retry")),RetrySettings{None{},None{},None{},None{},None{}}))},"retry","enabled",state)

def setShowImagesGroup(value: Bool,previous: TerminalSettings) -> TerminalSettings:
  match previous:
    case TerminalSettings{_,imageWidthCells,clearOnShrink,showTerminalProgress,hyperlinks,images,trueColor}: TerminalSettings{Some{value},imageWidthCells,clearOnShrink,showTerminalProgress,hyperlinks,images,trueColor}

def setShowImages(value: Bool,+state: SettingsManager) -> Outcome(SettingsManager): setNested(Terminal{setShowImagesGroup(value,Maybe.default(&2,TerminalSettings,selectedTerminal(get(getGlobalSettings(state),"terminal")),TerminalSettings{None{},None{},None{},None{},None{},None{},None{}}))},"terminal","showImages",state)

def setImageWidthCellsGroup(value: W.U64,previous: TerminalSettings) -> TerminalSettings:
  match previous:
    case TerminalSettings{showImages,_,clearOnShrink,showTerminalProgress,hyperlinks,images,trueColor}: TerminalSettings{showImages,Some{countMaximum(W.U64{0,1},value)},clearOnShrink,showTerminalProgress,hyperlinks,images,trueColor}

def setImageWidthCells(value: W.U64,+state: SettingsManager) -> Outcome(SettingsManager): setNested(Terminal{setImageWidthCellsGroup(value,Maybe.default(&2,TerminalSettings,selectedTerminal(get(getGlobalSettings(state),"terminal")),TerminalSettings{None{},None{},None{},None{},None{},None{},None{}}))},"terminal","imageWidthCells",state)

def setClearOnShrinkGroup(value: Bool,previous: TerminalSettings) -> TerminalSettings:
  match previous:
    case TerminalSettings{showImages,imageWidthCells,_,showTerminalProgress,hyperlinks,images,trueColor}: TerminalSettings{showImages,imageWidthCells,Some{value},showTerminalProgress,hyperlinks,images,trueColor}

def setClearOnShrink(value: Bool,+state: SettingsManager) -> Outcome(SettingsManager): setNested(Terminal{setClearOnShrinkGroup(value,Maybe.default(&2,TerminalSettings,selectedTerminal(get(getGlobalSettings(state),"terminal")),TerminalSettings{None{},None{},None{},None{},None{},None{},None{}}))},"terminal","clearOnShrink",state)

def setShowTerminalProgressGroup(value: Bool,previous: TerminalSettings) -> TerminalSettings:
  match previous:
    case TerminalSettings{showImages,imageWidthCells,clearOnShrink,_,hyperlinks,images,trueColor}: TerminalSettings{showImages,imageWidthCells,clearOnShrink,Some{value},hyperlinks,images,trueColor}

def setShowTerminalProgress(value: Bool,+state: SettingsManager) -> Outcome(SettingsManager): setNested(Terminal{setShowTerminalProgressGroup(value,Maybe.default(&2,TerminalSettings,selectedTerminal(get(getGlobalSettings(state),"terminal")),TerminalSettings{None{},None{},None{},None{},None{},None{},None{}}))},"terminal","showTerminalProgress",state)

def setImageAutoResizeGroup(value: Bool,previous: ImageSettings) -> ImageSettings:
  match previous:
    case ImageSettings{_,blockImages}: ImageSettings{Some{value},blockImages}

def setImageAutoResize(value: Bool,+state: SettingsManager) -> Outcome(SettingsManager): setNested(Images{setImageAutoResizeGroup(value,Maybe.default(&2,ImageSettings,selectedImages(get(getGlobalSettings(state),"images")),ImageSettings{None{},None{}}))},"images","autoResize",state)

def setBlockImagesGroup(value: Bool,previous: ImageSettings) -> ImageSettings:
  match previous:
    case ImageSettings{autoResize,_}: ImageSettings{autoResize,Some{value}}

def setBlockImages(value: Bool,+state: SettingsManager) -> Outcome(SettingsManager): setNested(Images{setBlockImagesGroup(value,Maybe.default(&2,ImageSettings,selectedImages(get(getGlobalSettings(state),"images")),ImageSettings{None{},None{}}))},"images","blockImages",state)

def setMermaidRenderingModeGroup(value: MermaidRenderingMode,previous: MarkdownSettings) -> MarkdownSettings:
  match previous:
    case MarkdownSettings{codeBlockIndent,_}: MarkdownSettings{codeBlockIndent,Some{value}}

def setMermaidRenderingMode(value: MermaidRenderingMode,+state: SettingsManager) -> Outcome(SettingsManager): setNested(Markdown{setMermaidRenderingModeGroup(value,Maybe.default(&2,MarkdownSettings,selectedMarkdown(get(getGlobalSettings(state),"markdown")),MarkdownSettings{None{},None{}}))},"markdown","mermaid",state)

def slash(value: String) -> Bool:
  match value:
    case SNil{}: False{}
    case SCon{'/',_}: True{}
    case SCon{_,rest}: slash(rest)
def themeName(value: Maybe<&2,String>) -> Maybe<&2,String>:
  match value:
    case None{}: None{}
    case Some{+value}: Bool.pick(Maybe<&2,String>,slash(value),None{},Some{value})
def getTheme(state: SettingsManager) -> Maybe<&2,String>: themeName(getThemeSetting(state))
type ModelIdentity is Data:
  ModelIdentity{provider: String,id: String}
type ResolvedCompactionSettings is Data:
  ResolvedCompactionSettings{enabled: Bool,reserveTokens: W.U64,keepRecentTokens: W.U64}
def modelKey(value: ModelIdentity) -> String:
  match value:
    case ModelIdentity{provider,id}: provider ++ "/" ++ id
def modelOverride(model: Maybe<&2,ModelIdentity>,values: Maybe<&2,R.Record<CompactionModelOverride>>) -> CompactionModelOverride:
  match model values:
    case Some{model} Some{values}: Maybe.default(&2,CompactionModelOverride,R.get(CompactionModelOverride,values,modelKey(model)),CompactionModelOverride{None{},None{}})
    case _ _: CompactionModelOverride{None{},None{}}
def resolveTokens(enabled: Maybe<&2,Bool>,reserve: Maybe<&2,W.U64>,recent: Maybe<&2,W.U64>,override: CompactionModelOverride) -> ResolvedCompactionSettings:
  match override:
    case CompactionModelOverride{modelReserve,modelRecent}: ResolvedCompactionSettings{Maybe.default(&2,Bool,enabled,True{}),Maybe.default(&2,W.U64,prefer(W.U64,reserve,modelReserve),W.U64{0,16384}),Maybe.default(&2,W.U64,prefer(W.U64,recent,modelRecent),W.U64{0,20000})}
def resolvedCompaction(value: CompactionSettings,model: Maybe<&2,ModelIdentity>) -> ResolvedCompactionSettings:
  match value:
    case CompactionSettings{enabled,reserve,recent,overrides}: resolveTokens(enabled,reserve,recent,modelOverride(model,overrides))
def compactionEnabled(value: CompactionSettings) -> Bool:
  match value:
    case CompactionSettings{enabled,_,_,_}: Maybe.default(&2,Bool,enabled,True{})
def getCompactionEnabled(state: SettingsManager) -> Bool: compactionEnabled(compactionOptions(state))
def getCompactionSettings(state: SettingsManager,model: Maybe<&2,ModelIdentity>) -> ResolvedCompactionSettings: resolvedCompaction(compactionOptions(state),model)
def reserveTokens(value: ResolvedCompactionSettings) -> W.U64:
  match value:
    case ResolvedCompactionSettings{_,value,_}: value
def recentTokens(value: ResolvedCompactionSettings) -> W.U64:
  match value:
    case ResolvedCompactionSettings{_,_,value}: value
def getCompactionReserveTokens(state: SettingsManager,model: Maybe<&2,ModelIdentity>) -> W.U64: reserveTokens(getCompactionSettings(state,model))
def getCompactionKeepRecentTokens(state: SettingsManager,model: Maybe<&2,ModelIdentity>) -> W.U64: recentTokens(getCompactionSettings(state,model))
type ResolvedBranchSummarySettings is Data:
  ResolvedBranchSummarySettings{reserveTokens: W.U64,skipPrompt: Bool}
def resolvedBranch(value: BranchSummarySettings) -> ResolvedBranchSummarySettings:
  match value:
    case BranchSummarySettings{reserve,skip}: ResolvedBranchSummarySettings{Maybe.default(&2,W.U64,reserve,W.U64{0,16384}),Maybe.default(&2,Bool,skip,False{})}
def getBranchSummarySettings(state: SettingsManager) -> ResolvedBranchSummarySettings: resolvedBranch(branchSummaryOptions(state))
def branchSkip(value: ResolvedBranchSummarySettings) -> Bool:
  match value:
    case ResolvedBranchSummarySettings{_,skip}: skip
def getBranchSummarySkipPrompt(state: SettingsManager) -> Bool: branchSkip(getBranchSummarySettings(state))
type ResolvedRetrySettings is Data:
  ResolvedRetrySettings{enabled: Bool,maxRetries: W.U64,baseDelayMs: W.U64,maxAgentDelayMs: W.U64}
def resolvedRetry(value: RetrySettings) -> ResolvedRetrySettings:
  match value:
    case RetrySettings{enabled,retries,delay,cap,_}: ResolvedRetrySettings{Maybe.default(&2,Bool,enabled,True{}),Maybe.default(&2,W.U64,retries,W.U64{0,3}),Maybe.default(&2,W.U64,delay,W.U64{0,2000}),Maybe.default(&2,W.U64,cap,W.U64{0,60000})}
def getRetrySettings(state: SettingsManager) -> ResolvedRetrySettings: resolvedRetry(retryOptions(state))
def retryEnabled(value: ResolvedRetrySettings) -> Bool:
  match value:
    case ResolvedRetrySettings{enabled,_,_,_}: enabled
def getRetryEnabled(state: SettingsManager) -> Bool: retryEnabled(getRetrySettings(state))
type ResolvedProviderRetrySettings is Data:
  ResolvedProviderRetrySettings{timeoutMs: Maybe<&2,W.U64>,maxRetries: Maybe<&2,W.U64>,maxRetryDelayMs: W.U64}
def resolvedProvider(value: ProviderRetrySettings) -> ResolvedProviderRetrySettings:
  match value:
    case ProviderRetrySettings{timeout,retries,delay}: ResolvedProviderRetrySettings{timeout,retries,Maybe.default(&2,W.U64,delay,W.U64{0,60000})}
def providerRetry(value: RetrySettings) -> ResolvedProviderRetrySettings:
  match value:
    case RetrySettings{_,_,_,_,provider}: resolvedProvider(Maybe.default(&2,ProviderRetrySettings,provider,ProviderRetrySettings{None{},None{},None{}}))
def getProviderRetrySettings(state: SettingsManager) -> ResolvedProviderRetrySettings: providerRetry(retryOptions(state))
def terminalShowImages(value: TerminalSettings) -> Bool:
  match value:
    case TerminalSettings{value,_,_,_,_,_,_}: Maybe.default(&2,Bool,value,True{})
def getShowImages(state: SettingsManager) -> Bool: terminalShowImages(terminalOptions(state))
def terminalImageWidth(value: TerminalSettings) -> W.U64:
  match value:
    case TerminalSettings{_,value,_,_,_,_,_}: countMaximum(W.U64{0,1},Maybe.default(&2,W.U64,value,W.U64{0,60}))
def getImageWidthCells(state: SettingsManager) -> W.U64: terminalImageWidth(terminalOptions(state))
def terminalProgress(value: TerminalSettings) -> Bool:
  match value:
    case TerminalSettings{_,_,_,value,_,_,_}: Maybe.default(&2,Bool,value,False{})
def getShowTerminalProgress(state: SettingsManager) -> Bool: terminalProgress(terminalOptions(state))
def imageResize(value: ImageSettings) -> Bool:
  match value:
    case ImageSettings{value,_}: Maybe.default(&2,Bool,value,True{})
def getImageAutoResize(state: SettingsManager) -> Bool: imageResize(imagesOptions(state))
def imageBlock(value: ImageSettings) -> Bool:
  match value:
    case ImageSettings{_,value}: Maybe.default(&2,Bool,value,False{})
def getBlockImages(state: SettingsManager) -> Bool: imageBlock(imagesOptions(state))
def codeIndent(value: MarkdownSettings) -> String:
  match value:
    case MarkdownSettings{value,_}: Maybe.default(&2,String,value,"  ")
def getCodeBlockIndent(state: SettingsManager) -> String: codeIndent(markdownOptions(state))
def mermaidMode(value: MarkdownSettings) -> MermaidRenderingMode:
  match value:
    case MarkdownSettings{_,value}: Maybe.default(&2,MermaidRenderingMode,value,MermaidStreaming{})
def getMermaidRenderingMode(state: SettingsManager) -> MermaidRenderingMode: mermaidMode(markdownOptions(state))
def getWarnings(state: SettingsManager) -> WarningSettings: warningsOptions(state)
def setWarnings(value: WarningSettings,state: SettingsManager) -> Outcome(SettingsManager): set(Warnings{value},state)
def getModelThinkingLevel(provider: String,id: String,state: SettingsManager) -> Maybe<&2,Ai.ModelThinkingLevel>:
  R.get(Ai.ModelThinkingLevel,getAllModelThinkingLevels(state),provider ++ "/" ++ id)
def setModelThinkingLevel(provider: String,id: String,level: Ai.ModelThinkingLevel,+state: SettingsManager) -> Outcome(SettingsManager):
  values = Maybe.default(&2,R.Record<Ai.ModelThinkingLevel>,selectedModelThinkingLevels(get(getGlobalSettings(state),"modelThinkingLevels")),R.new(Ai.ModelThinkingLevel))
  set(ModelThinkingLevels{R.set(Ai.ModelThinkingLevel,values,provider ++ "/" ++ id,level)},state)
def removedThinking(values: R.Record<Ai.ModelThinkingLevel>,state: SettingsManager) -> Outcome(SettingsManager):
  match values:
    case R.Record{Nil{}}: unset("modelThinkingLevels",state)
    case other: set(ModelThinkingLevels{other},state)
def removeThinking(values: Maybe<&2,R.Record<Ai.ModelThinkingLevel>>,key: String,state: SettingsManager) -> Outcome(SettingsManager):
  match values:
    case None{}: Done{state}
    case Some{values}: removedThinking(R.remove(Ai.ModelThinkingLevel,values,key),state)
def removeModelThinkingLevel(provider: String,id: String,+state: SettingsManager) -> Outcome(SettingsManager):
  removeThinking(selectedModelThinkingLevels(get(getGlobalSettings(state),"modelThinkingLevels")),provider ++ "/" ++ id,state)
type ImageProtocol is Data:
  KittyProtocol{}
  Iterm2Protocol{}
type TerminalCapabilities is Data:
  TerminalCapabilities{images: Maybe<&2,Maybe<&2,ImageProtocol>>,trueColor: Maybe<&2,Bool>,hyperlinks: Maybe<&2,Bool>}
def capabilityBoolean(value: Maybe<&2,AutomaticBoolean>) -> Maybe<&2,Bool>:
  match value:
    case Some{Enabled{}}: Some{True{}}
    case Some{Disabled{}}: Some{False{}}
    case _: None{}
def capabilityImages(value: Maybe<&2,TerminalImages>) -> Maybe<&2,Maybe<&2,ImageProtocol>>:
  match value:
    case Some{Kitty{}}: Some{Some{KittyProtocol{}}}
    case Some{Iterm2{}}: Some{Some{Iterm2Protocol{}}}
    case Some{NoImages{}}: Some{None{}}
    case _: None{}
def capabilities(value: TerminalSettings) -> TerminalCapabilities:
  match value:
    case TerminalSettings{_,_,_,_,links,images,color}: TerminalCapabilities{capabilityImages(images),capabilityBoolean(color),capabilityBoolean(links)}
def getTerminalCapabilityOverrides(state: SettingsManager) -> TerminalCapabilities: capabilities(terminalOptions(state))

# Runtime preferences enter explicitly, keeping getters deterministic and useful
# in embedded agents without process-global environment mutation.
type Environment is Data:
  Environment{paths: Paths.Environment,visual: Maybe<&2,String>,editor: Maybe<&2,String>,windows: Bool,clearOnShrink: Bool,hardwareCursor: Bool}
def nonemptyText(value: Maybe<&2,String>) -> Maybe<&2,String>:
  match value:
    case Some{""}: None{}
    case other: other
def configuredEditor(value: Maybe<&2,String>,environment: String) -> String:
  match value:
    case None{}: environment
    case Some{+value}: Bool.pick(String,String.is_empty(Text.trim(value)),environment,value)
def getExternalEditorCommand(environment: Environment,state: SettingsManager) -> String:
  match environment:
    case Environment{_,visual,editor,windows,_,_}: configuredEditor(getExternalEditorSetting(state),Maybe.default(&2,String,Maybe.or(&2,String,nonemptyText(visual),nonemptyText(editor)),Bool.pick(String,windows,"notepad","nano")))
def normalizedPath(value: Maybe<&2,String>,environment: Paths.Environment) -> Result<&2,&2,Paths.Error,Maybe<&2,String>>:
  match value:
    case None{}: Done{None{}}
    case Some{""}: Done{Some{""}}
    case Some{value}: Result.map(&2,&2,Paths.Error,String,Maybe<&2,String>,value => Some{value},Paths.normalizePath(environment,value,Paths.defaults()))
def getSessionDir(environment: Paths.Environment,state: SettingsManager) -> Result<&2,&2,Paths.Error,Maybe<&2,String>>: normalizedPath(getSessionDirSetting(state),environment)
def getShellPath(environment: Paths.Environment,state: SettingsManager) -> Result<&2,&2,Paths.Error,Maybe<&2,String>>: normalizedPath(getShellPathSetting(state),environment)
def resolvedClearOnShrink(value: TerminalSettings,fallback: Bool) -> Bool:
  match value:
    case TerminalSettings{_,_,value,_,_,_,_}: Maybe.default(&2,Bool,value,fallback)
def getClearOnShrink(environment: Environment,state: SettingsManager) -> Bool:
  match environment:
    case Environment{_,_,_,_,fallback,_}: resolvedClearOnShrink(terminalOptions(state),fallback)
def getShowHardwareCursor(environment: Environment,state: SettingsManager) -> Bool:
  match environment:
    case Environment{_,_,_,_,_,fallback}: Maybe.default(&2,Bool,selectedShowHardwareCursor(get(effective(state),"showHardwareCursor")),fallback)

# Multi-field settings changes become one persistence snapshot.
type SettingsEdits is Data:
  SettingsEdits{settings: Settings,fields: List<&2,DirtyField>}
def editing(values: List<&2,Setting>,current: Settings,dirty: List<&2,DirtyField>) -> SettingsEdits:
  match values:
    case Nil{}: SettingsEdits{current,dirty}
    case +value <> rest: editing(rest,put(value,current),DirtyField{name(value),None{}} <> dirty)
def edited(values: SettingsEdits,previous: ScopedSettings,+state: SettingsManager) -> Outcome(SettingsManager):
  match values previous:
    case SettingsEdits{next,fields} ScopedSettings{_,loadError,oldFields}:
      do Result<&2,&2,Error,SettingsManager>:
        valid : Settings <- decode(toValue(next))
        return updated(Global{},ScopedSettings{valid,loadError,List.append(&2,DirtyField,fields,oldFields)},state)
def atomic(values: List<&2,Setting>,+state: SettingsManager) -> Outcome(SettingsManager):
  edited(editing(values,getGlobalSettings(state),Nil{}),selectedScope(Global{},state),state)
def setDefaultModelAndProvider(provider: String,model: String,state: SettingsManager) -> Outcome(SettingsManager):
  atomic(DefaultProvider{provider} <> DefaultModel{model} <> Nil{},state)
def trackingMissing(value: Maybe<&2,String>) -> Bool:
  match value:
    case None{}: True{}
    case Some{""}: True{}
    case _: False{}
def uuid4(bytes: List<&2,U32>) -> Maybe<&2,String>:
  match bytes:
    case a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> k <> l <> m <> n <> o <> p <> Nil{}:
      Some{Uuid.formatted(a <> b <> c <> d <> e <> f <> U32.or(64,U32.and(g,15)) <> h <> U32.or(128,U32.and(i,63)) <> j <> k <> l <> m <> n <> o <> p <> Nil{})}
    case _: None{}
def analyticsIdentity(id: Maybe<&2,String>,state: SettingsManager) -> Outcome(SettingsManager):
  match id:
    case None{}: Fail{StorageFailure{"Entropy source returned too few bytes"}}
    case Some{id}: atomic(EnableAnalytics{True{}} <> TrackingId{id} <> Nil{},state)
def analyticsEntropy(value: Result<&1,&1,U32 & String,List<&2,U32>>,state: SettingsManager) -> Outcome(SettingsManager):
  match value:
    case Fail{(_,message)}: Fail{StorageFailure{"Analytics identity entropy: " ++ message}}
    case Done{bytes}: analyticsIdentity(uuid4(bytes),state)
def setEnableAnalytics(+enabled: Bool,+state: SettingsManager) -> IO(Outcome(SettingsManager)):
  Bool.pick(Unit -> IO(Outcome(SettingsManager)),enabled && trackingMissing(selectedTrackingId(get(getGlobalSettings(state),"trackingId"))),_ =>
    do IO<Outcome(SettingsManager)>:
      bytes : Result<&1,&1,U32 & String,List<&2,U32>> <- Entropy.bytes(16)
      return analyticsEntropy(bytes,state),_ => IO.pure(Outcome(SettingsManager),set(EnableAnalytics{enabled},state)))(Unit{})

# File storage uses Pi's mkdir/mtime lease protocol. An explicit write intent
# lets reads remain side-effect free when directories are absent, while first
# writes acquire ownership before reading or evaluating the transaction.
type FileSettingsStorage is Data:
  FileSettingsStorage{global: String,project: String}
def fileStorage(cwd: String,agentDir: String) -> FileSettingsStorage:
  FileSettingsStorage{Path.join(agentDir,"settings.json"),Path.join(Path.join(cwd,".pi"),"settings.json")}
def filePath(scope: SettingsScope,storage: FileSettingsStorage) -> String:
  match scope storage:
    case Global{} FileSettingsStorage{path,_}: path
    case Project{} FileSettingsStorage{_,path}: path
def fileDecoded(value: Result<&2,&2,Utf8.Error,String>) -> Outcome(Maybe<&2,String>):
  match value:
    case Fail{cause}: Fail{InvalidEncoding{cause}}
    case Done{content}: Done{Some{content}}
def fileContent(value: Result<&2,&2,FS.Error,List<&2,U32>>) -> Outcome(Maybe<&2,String>):
  match value:
    case Fail{FS.System{2,_}}: Done{None{}}
    case Fail{cause}: Fail{FileFailure{cause}}
    case Done{bytes}: fileDecoded(Utf8.decodeWith(Utf8.Preserve{},bytes))
def fileRead(path: String) -> IO(Outcome(Maybe<&2,String>)):
  do IO<Outcome(Maybe<&2,String>)>:
    result : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
    return fileContent(result)
def fileWritten(result: Result<&2,&2,FS.Error,Unit>,settings: Settings) -> Outcome(Settings):
  match result:
    case Fail{cause}: Fail{FileFailure{cause}}
    case Done{_}: Done{settings}
def fileUpdate(path: String,writable: Bool,result: Outcome(StorageUpdate)) -> IO(Outcome(Settings)):
  match writable result:
    case _ Fail{cause}: IO.pure(Outcome(Settings),Fail{cause})
    case _ Done{StorageUpdate{settings,None{}}}: IO.pure(Outcome(Settings),Done{settings})
    case False{} Done{StorageUpdate{_,Some{_}}}: IO.pure(Outcome(Settings),Fail{StorageFailure{"Read-only transaction returned a write"}})
    case True{} Done{StorageUpdate{settings,Some{content}}}:
      do IO<Outcome(Settings)>:
        result : Result<&2,&2,FS.Error,Unit> <- FS.writeFile(path,content)
        return fileWritten(result,settings)
def fileTransaction(path: String,writable: Bool,transaction: Maybe<&2,String> -> Outcome(StorageUpdate),current: Outcome(Maybe<&2,String>)) -> IO(Outcome(Settings)):
  match current:
    case Fail{cause}: IO.pure(Outcome(Settings),Fail{cause})
    case Done{content}: fileUpdate(path,writable,transaction(content))
def leaseChecked(result: Result<&2,&2,Lock.Error,Unit>,previous: Outcome(Settings)) -> Outcome(Settings):
  match result previous:
    case Done{_} previous: previous
    case Fail{cause} Done{_}: Fail{LockFailure{cause}}
    case Fail{cause} Fail{previous}: Fail{CleanupFailure{previous,LockFailure{cause}}}
def leaseTransaction(checked: Result<&2,&2,Lock.Error,Unit>,+path: String,writable: Bool,transaction: Maybe<&2,String> -> Outcome(StorageUpdate)) -> IO(Outcome(Settings)):
  match checked:
    case Fail{cause}: IO.pure(Outcome(Settings),Fail{LockFailure{cause}})
    case Done{_}:
      do IO<Outcome(Settings)>:
        current : Outcome(Maybe<&2,String>) <- fileRead(path)
        fileTransaction(path,writable,transaction,current)
def leased(pair: Lock.Owner & Lock.Handle,path: String,writable: Bool,transaction: Maybe<&2,String> -> Outcome(StorageUpdate)) -> IO(Outcome(Settings)):
  match pair:
    case (owner,+handle):
      do IO<Outcome(Settings)>:
        before : Result<&2,&2,Lock.Error,Unit> <- Lock.check(handle)
        result : Outcome(Settings) <- leaseTransaction(before,path,writable,transaction)
        after : Result<&2,&2,Lock.Error,Unit> <- Lock.check(handle)
        released : Result<&2,&2,Lock.Error,Unit> <- Lock.release(owner)
        return leaseChecked(released,leaseChecked(after,result))
def acquired(result: Result<&2,&1,Lock.Error,Lock.Owner>,path: String,writable: Bool,transaction: Maybe<&2,String> -> Outcome(StorageUpdate)) -> IO(Outcome(Settings)):
  match result:
    case Fail{cause}: IO.pure(Outcome(Settings),Fail{LockFailure{cause}})
    case Done{owner}: leased(Lock.borrow(owner),path,writable,transaction)
def fileLocked(+path: String,writable: Bool,transaction: Maybe<&2,String> -> Outcome(StorageUpdate)) -> IO(Outcome(Settings)):
  do IO<Outcome(Settings)>:
    result : Result<&2,&1,Lock.Error,Lock.Owner> <- Lock.acquire(path,Lock.Options{10000,5000,10n,20,False{}},None{})
    acquired(result,path,writable,transaction)
def filePrepared(result: Result<&2,&2,FS.Error,Unit>,path: String,transaction: Maybe<&2,String> -> Outcome(StorageUpdate)) -> IO(Outcome(Settings)):
  match result:
    case Fail{cause}: IO.pure(Outcome(Settings),Fail{FileFailure{cause}})
    case Done{_}: fileLocked(path,True{},transaction)
def filePresent(result: Result<&2,&2,FS.Error,FS.FileKind>,path: String,transaction: Maybe<&2,String> -> Outcome(StorageUpdate)) -> IO(Outcome(Settings)):
  match result:
    case Fail{FS.System{2,_}}: fileUpdate(path,False{},transaction(None{}))
    case Fail{cause}: IO.pure(Outcome(Settings),Fail{FileFailure{cause}})
    case Done{_}: fileLocked(path,False{},transaction)
def fileAccess(writable: Bool,+path: String,transaction: Maybe<&2,String> -> Outcome(StorageUpdate)) -> IO(Outcome(Settings)):
  match writable:
    case True{}:
      do IO<Outcome(Settings)>:
        result : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(Path.join(path,".."))
        filePrepared(result,path,transaction)
    case False{}:
      do IO<Outcome(Settings)>:
        result : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(path)
        filePresent(result,path,transaction)
def fileWithLock(storage: FileSettingsStorage,scope: SettingsScope,writable: Bool,transaction: Maybe<&2,String> -> Outcome(StorageUpdate)) -> IO(FileSettingsStorage & Outcome(Settings)):
  +storage = storage
  do IO<FileSettingsStorage & Outcome(Settings)>:
    result : Outcome(Settings) <- fileAccess(writable,filePath(scope,storage),transaction)
    return (storage,result)
def create(cwd: String,agentDir: String,options: SettingsManagerCreateOptions) -> IO(FileSettingsStorage & SettingsManager):
  +storage = fileStorage(cwd,agentDir)
  fromStorageWithPaths(~FileSettingsStorage,~fileWithLock,storage,options,SettingsPaths{Some{filePath(Global{},storage)},Some{filePath(Project{},storage)}})

# upstream settingsManager.reload() for a manager loaded from files; in-memory
# managers are unchanged.
def reloadedFiles(value: FileSettingsStorage & SettingsManager) -> SettingsManager:
  match value:
    case (_,manager): manager
def reloadFiles(+state: SettingsManager) -> IO(SettingsManager):
  match state:
    case SettingsManager{_,_,_,_,_,_,SettingsPaths{Some{+global},Some{+project}}}:
      do IO<SettingsManager>:
        reloaded : FileSettingsStorage & SettingsManager <- reload(~FileSettingsStorage,~fileWithLock,FileSettingsStorage{global,project},state)
        return reloadedFiles(reloaded)
    case _: IO.pure(SettingsManager,state)

# Persist a manager loaded from file storage, while in-memory managers retain
# their transaction state for their caller's storage implementation.
def flushedFiles(value: FileSettingsStorage & SettingsManager) -> SettingsManager:
  match value:
    case (_,manager): manager
def flushFiles(+state: SettingsManager) -> IO(SettingsManager):
  match state:
    case SettingsManager{_,_,_,_,_,_,SettingsPaths{Some{+global},Some{+project}}}:
      do IO<SettingsManager>:
        written : FileSettingsStorage & SettingsManager <- flush(~FileSettingsStorage,~fileWithLock,FileSettingsStorage{global,project},state)
        return flushedFiles(written)
    case _: IO.pure(SettingsManager,state)
