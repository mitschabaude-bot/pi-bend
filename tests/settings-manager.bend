import Base
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties
import ../packages/ai/src/types.bend as Ai
import ../packages/agent/src/types.bend as Agent
import ../packages/coding-agent/src/core/settings-manager.bend as S
import ../packages/coding-agent/src/core/diagnostics.bend as D
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/u64.bend as W
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson

def stringify(value: V.Value) -> String: Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(value)),"null")
def object(fields: List<&2,R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def get(value: V.Value,key: String) -> V.Value:
  match value:
    case V.ObjectValue{fields}: Maybe.default(&2,V.Value,R.get(V.Value,fields,key),V.Null{})
    case _: V.Null{}
def text(value: V.Value) -> String:
  match value:
    case V.Text{value}: value
    case _: ""
def boolean(value: V.Value) -> Bool:
  match value:
    case V.Boolean{value}: value
    case _: True{}
def enabled(value: V.Value) -> Bool:
  match value:
    case V.Boolean{True{}}: True{}
    case _: False{}
def array(value: V.Value) -> List<&2,V.Value>:
  match value:
    case V.ArrayValue{values}: values
    case _: Nil{}
def optional(value: V.Value) -> Maybe<&2,String>:
  match value:
    case V.Null{}: None{}
    case V.Text{raw}: Some{raw}
    case other: Some{stringify(other)}
def valueOf(value: Maybe<&2,String>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{value}: V.Text{value}
def stored(value: S.InMemorySettingsStorage) -> V.Value:
  match value:
    case S.InMemorySettingsStorage{global,project}: object(R.Property{"global",valueOf(global)} <> R.Property{"project",valueOf(project)} <> Nil{})
def scopeName(value: S.SettingsScope) -> String:
  match value:
    case S.Global{}: "global"
    case S.Project{}: "project"
def error(value: S.SettingsError) -> V.Value:
  match value:
    case S.SettingsError{scope,path,_}: object(R.Property{"scope",V.Text{scopeName(scope)}} <> R.Property{"path",valueOf(path)} <> Nil{})
def errors(values: List<&2,S.SettingsError>) -> V.Value:
  V.ArrayValue{S.encodeValues(~S.SettingsError,~error,values,Nil{})}
type Fixture is Data:
  Fixture{storage: S.InMemorySettingsStorage,manager: S.SettingsManager,results: List<&2,V.Value>}
def updated(value: S.Outcome(S.SettingsManager),fixture: Fixture) -> Fixture:
  match value fixture:
    case Done{next} Fixture{storage,_,results}: Fixture{storage,next,results}
    case Fail{_} Fixture{storage,manager,results}: Fixture{storage,manager,object(R.Property{"error",V.Boolean{True{}}} <> Nil{}) <> results}
def runtime(value: S.InMemorySettingsStorage & S.SettingsManager,results: List<&2,V.Value>) -> Fixture:
  match value:
    case (storage,manager): Fixture{storage,manager,results}
def plain(value: V.Value) -> S.Outcome(S.Settings): S.decode(S.migrate(value))
def applied(value: S.Outcome(S.Settings),+fixture: Fixture) -> Fixture:
  match value fixture:
    case Fail{_} _: updated(Fail{S.StorageFailure{"invalid input"}},fixture)
    case Done{settings} Fixture{_,manager,_}: updated(S.applyOverrides(settings,manager),fixture)
def namedSet(value: S.Setting,state: S.SettingsManager) -> S.Outcome(S.SettingsManager):
  match value:
    case S.LastChangelogVersion{value}: S.setLastChangelogVersion(value,state)
    case S.DefaultProvider{value}: S.setDefaultProvider(value,state)
    case S.DefaultModel{value}: S.setDefaultModel(value,state)
    case S.Theme{value}: S.setTheme(value,state)
    case S.ShellPath{value}: S.setShellPath(Some{value},state)
    case S.ShellCommandPrefix{value}: S.setShellCommandPrefix(Some{value},state)
    case S.HideThinkingBlock{value}: S.setHideThinkingBlock(value,state)
    case S.ShowCacheMissNotices{value}: S.setShowCacheMissNotices(value,state)
    case S.QuietStartup{value}: S.setQuietStartup(value,state)
    case S.CollapseChangelog{value}: S.setCollapseChangelog(value,state)
    case S.EnableInstallTelemetry{value}: S.setEnableInstallTelemetry(value,state)
    case S.EnableSkillCommands{value}: S.setEnableSkillCommands(value,state)
    case S.ShowHardwareCursor{value}: S.setShowHardwareCursor(value,state)
    case S.FullscreenCopyOnSelect{value}: S.setFullscreenCopyOnSelect(value,state)
    case S.EditorPaddingX{value}: S.setEditorPaddingX(value,state)
    case S.AutocompleteMaxVisible{value}: S.setAutocompleteMaxVisible(value,state)
    case S.HttpIdleTimeoutMs{value}: S.setHttpIdleTimeoutMs(value,state)
    case S.NpmCommand{value}: S.setNpmCommand(Some{value},state)
    case S.Extensions{value}: S.setExtensionPaths(value,state)
    case S.Skills{value}: S.setSkillPaths(value,state)
    case S.Prompts{value}: S.setPromptTemplatePaths(value,state)
    case S.Themes{value}: S.setThemePaths(value,state)
    case S.EnabledModels{value}: S.setEnabledModels(Some{value},state)
    case S.DefaultThinkingLevel{value}: S.setDefaultThinkingLevel(value,state)
    case S.Transport{value}: S.setTransport(value,state)
    case S.SteeringMode{value}: S.setSteeringMode(value,state)
    case S.FollowUpMode{value}: S.setFollowUpMode(value,state)
    case S.Packages{value}: S.setPackages(value,state)
    case S.DefaultProjectTrust{value}: S.setDefaultProjectTrust(value,state)
    case S.DoubleEscapeAction{value}: S.setDoubleEscapeAction(value,state)
    case S.TreeFilterMode{value}: S.setTreeFilterMode(value,state)
    case S.OutputPad{value}: S.setOutputPad(value,state)
    case S.TuiMode{value}: S.setTuiMode(value,state)
    case S.FullscreenExitOutput{value}: S.setFullscreenExitOutput(value,state)
    case S.FullscreenScrollbar{value}: S.setFullscreenScrollbar(value,state)
    case other: S.set(other,state)
def setValue(value: Result<&2,&2,J.Error,Maybe<&2,S.Setting>>,project: Bool,+fixture: Fixture) -> Fixture:
  match value fixture:
    case Done{Some{+value}} Fixture{_,+manager,_}: updated(Bool.pick(S.Outcome(S.SettingsManager),project,S.setProject(value,manager),namedSet(value,manager)),fixture)
    case _ _: updated(Fail{S.StorageFailure{"invalid setter input"}},fixture)
def actionInput(+value: V.Value,fixture: Fixture) -> Fixture:
  setValue(S.knownField(text(get(value,"key")),get(value,"value")),enabled(get(value,"project")),fixture)
def external(scope: String,value: Maybe<&2,String>,fixture: Fixture) -> Fixture:
  match scope fixture:
    case "global" Fixture{S.InMemorySettingsStorage{_,project},manager,results}: Fixture{S.InMemorySettingsStorage{value,project},manager,results}
    case _ Fixture{S.InMemorySettingsStorage{global,_},manager,results}: Fixture{S.InMemorySettingsStorage{global,value},manager,results}
def model(value: V.Value) -> Maybe<&2,S.ModelIdentity>:
  match value:
    case V.Null{}: None{}
    case +value: Some{S.ModelIdentity{text(get(value,"provider")),text(get(value,"id"))}}
def compaction(value: S.ResolvedCompactionSettings) -> V.Value:
  match value:
    case S.ResolvedCompactionSettings{enabled,reserve,recent}: object(R.Property{"enabled",V.Boolean{enabled}} <> R.Property{"reserveTokens",S.numberValue(reserve)} <> R.Property{"keepRecentTokens",S.numberValue(recent)} <> Nil{})
def maybe(~A: Data,~encode: A -> V.Value,value: Maybe<&2,A>) -> V.Value:
  match value:
    case None{}: object(R.Property{"undefined",V.Boolean{True{}}} <> Nil{})
    case Some{value}: encode(value)

def showResolvedBranchSummarySettings(value: S.ResolvedBranchSummarySettings) -> V.Value:
  match value:
    case S.ResolvedBranchSummarySettings{reserveTokens,skipPrompt}: object(R.Property{"reserveTokens",S.numberValue(reserveTokens)} <> R.Property{"skipPrompt",V.Boolean{skipPrompt}} <> Nil{})

def showResolvedRetrySettings(value: S.ResolvedRetrySettings) -> V.Value:
  match value:
    case S.ResolvedRetrySettings{enabled,maxRetries,baseDelayMs,maxAgentDelayMs}: object(R.Property{"enabled",V.Boolean{enabled}} <> R.Property{"maxRetries",S.numberValue(maxRetries)} <> R.Property{"baseDelayMs",S.numberValue(baseDelayMs)} <> R.Property{"maxAgentDelayMs",S.numberValue(maxAgentDelayMs)} <> Nil{})

def mermaidSet(value: Result<&2,&2,J.Error,S.MermaidRenderingMode>,state: S.SettingsManager) -> S.Outcome(S.SettingsManager):
  match value:
    case Fail{cause}: Fail{S.InvalidSetting{cause}}
    case Done{value}: S.setMermaidRenderingMode(value,state)

def nested(method: String,+value: V.Value,state: S.SettingsManager) -> S.Outcome(S.SettingsManager):
  match method:
    case "setCompactionEnabled": S.setCompactionEnabled(enabled(value),state)
    case "setRetryEnabled": S.setRetryEnabled(enabled(value),state)
    case "setShowImages": S.setShowImages(enabled(value),state)
    case "setShowTerminalProgress": S.setShowTerminalProgress(enabled(value),state)
    case "setImageAutoResize": S.setImageAutoResize(enabled(value),state)
    case "setBlockImages": S.setBlockImages(enabled(value),state)
    case "setClearOnShrink": S.setClearOnShrink(enabled(value),state)
    case "setMermaidRenderingMode": mermaidSet(S.decodeMermaidRenderingMode(value),state)
    case _: Fail{S.StorageFailure{"Unknown nested setter"}}

def nestedAction(+input: V.Value,+fixture: Fixture) -> Fixture:
  match fixture:
    case Fixture{_,manager,_}: updated(nested(text(get(input,"method")),get(input,"value"),manager),fixture)

def pathEnvironment() -> Paths.Environment:
  Paths.Environment{"/work","/home/test",URL.Context{IDNA.Context{Mapping.table(),Normalization.tables(),Properties.table()},IDNA.Options{IDNA.LabelOptions{False{},False{},True{},IDNA.Nontransitional{}},True{},False{}}}}
def environment(+value: V.Value) -> S.Environment:
  S.Environment{pathEnvironment(),optional(get(value,"visual")),optional(get(value,"editor")),enabled(get(value,"windows")),enabled(get(value,"clear")),enabled(get(value,"cursor"))}
def pathResult(value: Result<&2,&2,Paths.Error,Maybe<&2,String>>) -> V.Value:
  match value:
    case Fail{_}: V.Text{"path-error"}
    case Done{value}: maybe(~String,~(text => V.Text{text}),value)
def protocol(value: Maybe<&2,S.ImageProtocol>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{S.KittyProtocol{}}: V.Text{"kitty"}
    case Some{S.Iterm2Protocol{}}: V.Text{"iterm2"}
def showCapabilities(value: S.TerminalCapabilities) -> V.Value:
  match value:
    case S.TerminalCapabilities{images,color,links}: object(List.concat(&2,R.Property<V.Value>,S.property(Maybe<&2,S.ImageProtocol>,"images",images,protocol) <> S.property(Bool,"trueColor",color,value => V.Boolean{value}) <> S.property(Bool,"hyperlinks",links,value => V.Boolean{value}) <> Nil{}))
def showProvider(value: S.ResolvedProviderRetrySettings) -> V.Value:
  match value:
    case S.ResolvedProviderRetrySettings{timeout,retries,delay}: object(List.concat(&2,R.Property<V.Value>,S.property(W.U64,"timeoutMs",timeout,S.numberValue) <> S.property(W.U64,"maxRetries",retries,S.numberValue) <> (R.Property{"maxRetryDelayMs",S.numberValue(delay)} <> Nil{}) <> Nil{}))

def query(method: String,+state: S.SettingsManager,args: V.Value) -> V.Value:
  match method:
    case "getLastChangelogVersion": maybe(~String,~(value => V.Text{value}),S.getLastChangelogVersion(state))
    case "getDefaultProvider": maybe(~String,~(value => V.Text{value}),S.getDefaultProvider(state))
    case "getDefaultModel": maybe(~String,~(value => V.Text{value}),S.getDefaultModel(state))
    case "getThemeSetting": maybe(~String,~(value => V.Text{value}),S.getThemeSetting(state))
    case "getExternalEditorSetting": maybe(~String,~(value => V.Text{value}),S.getExternalEditorSetting(state))
    case "getShellPathSetting": maybe(~String,~(value => V.Text{value}),S.getShellPathSetting(state))
    case "getShellCommandPrefix": maybe(~String,~(value => V.Text{value}),S.getShellCommandPrefix(state))
    case "getTrackingId": maybe(~String,~(value => V.Text{value}),S.getTrackingId(state))
    case "getSessionDirSetting": maybe(~String,~(value => V.Text{value}),S.getSessionDirSetting(state))
    case "getHttpProxy": maybe(~String,~(value => V.Text{value}),S.getHttpProxy(state))
    case "getHideThinkingBlock": V.Boolean{S.getHideThinkingBlock(state)}
    case "getShowCacheMissNotices": V.Boolean{S.getShowCacheMissNotices(state)}
    case "getQuietStartup": V.Boolean{S.getQuietStartup(state)}
    case "getCollapseChangelog": V.Boolean{S.getCollapseChangelog(state)}
    case "getEnableInstallTelemetry": V.Boolean{S.getEnableInstallTelemetry(state)}
    case "getEnableAnalytics": V.Boolean{S.getEnableAnalytics(state)}
    case "getEnableSkillCommands": V.Boolean{S.getEnableSkillCommands(state)}
    case "getFullscreenCopyOnSelect": V.Boolean{S.getFullscreenCopyOnSelect(state)}
    case "getEditorPaddingX": S.numberValue(S.getEditorPaddingX(state))
    case "getAutocompleteMaxVisible": S.numberValue(S.getAutocompleteMaxVisible(state))
    case "getHttpIdleTimeoutMs": S.numberValue(S.getHttpIdleTimeoutMs(state))
    case "getWebSocketConnectTimeoutMs": maybe(~W.U64,~(S.numberValue),S.getWebSocketConnectTimeoutMs(state))
    case "getNpmCommand": maybe(~List<&2,String>,~(S.encodeStrings),S.getNpmCommand(state))
    case "getExtensionPaths": S.encodeStrings(S.getExtensionPaths(state))
    case "getSkillPaths": S.encodeStrings(S.getSkillPaths(state))
    case "getPromptTemplatePaths": S.encodeStrings(S.getPromptTemplatePaths(state))
    case "getThemePaths": S.encodeStrings(S.getThemePaths(state))
    case "getEnabledModels": maybe(~List<&2,String>,~(S.encodeStrings),S.getEnabledModels(state))
    case "getDefaultTools": maybe(~List<&2,String>,~(S.encodeStrings),S.getDefaultTools(state))
    case "getDefaultThinkingLevel": maybe(~Ai.ModelThinkingLevel,~(S.encodeThinking),S.getDefaultThinkingLevel(state))
    case "getAllModelThinkingLevels": S.encodeMap(~Ai.ModelThinkingLevel,~S.encodeThinking,S.getAllModelThinkingLevels(state))
    case "getTransport": S.encodeTransport(S.getTransport(state))
    case "getSteeringMode": S.encodeQueue(S.getSteeringMode(state))
    case "getFollowUpMode": S.encodeQueue(S.getFollowUpMode(state))
    case "getPackages": V.ArrayValue{S.encodeValues(~S.PackageSource,~S.encodePackageSource,S.getPackages(state),Nil{})}
    case "getDefaultProjectTrust": S.encodeDefaultProjectTrust(S.getDefaultProjectTrust(state))
    case "getDoubleEscapeAction": S.encodeDoubleEscapeAction(S.getDoubleEscapeAction(state))
    case "getTreeFilterMode": S.encodeTreeFilterMode(S.getTreeFilterMode(state))
    case "getOutputPad": S.encodeOutputPadding(S.getOutputPad(state))
    case "getTuiMode": S.encodeTuiMode(S.getTuiMode(state))
    case "getFullscreenExitOutput": S.encodeFullscreenExitOutput(S.getFullscreenExitOutput(state))
    case "getFullscreenScrollbar": S.encodeScrollViewScrollbar(S.getFullscreenScrollbar(state))
    case "getTerminalSettings": maybe(~S.TerminalSettings,~(S.encodeTerminalSettings),S.getTerminalSettings(state))
    case "getThinkingBudgets": maybe(~S.ThinkingBudgetsSettings,~(S.encodeThinkingBudgetsSettings),S.getThinkingBudgets(state))
    case "getCompactionEnabled": V.Boolean{S.getCompactionEnabled(state)}
    case "getBranchSummarySkipPrompt": V.Boolean{S.getBranchSummarySkipPrompt(state)}
    case "getRetryEnabled": V.Boolean{S.getRetryEnabled(state)}
    case "getShowImages": V.Boolean{S.getShowImages(state)}
    case "getShowTerminalProgress": V.Boolean{S.getShowTerminalProgress(state)}
    case "getImageAutoResize": V.Boolean{S.getImageAutoResize(state)}
    case "getBlockImages": V.Boolean{S.getBlockImages(state)}
    case "getImageWidthCells": S.numberValue(S.getImageWidthCells(state))
    case "getCodeBlockIndent": V.Text{S.getCodeBlockIndent(state)}
    case "getMermaidRenderingMode": S.encodeMermaidRenderingMode(S.getMermaidRenderingMode(state))
    case "getBranchSummarySettings": showResolvedBranchSummarySettings(S.getBranchSummarySettings(state))
    case "getRetrySettings": showResolvedRetrySettings(S.getRetrySettings(state))
    case "getProviderRetrySettings": showProvider(S.getProviderRetrySettings(state))
    case "getTerminalCapabilityOverrides": showCapabilities(S.getTerminalCapabilityOverrides(state))
    case "getExternalEditorCommand": V.Text{S.getExternalEditorCommand(environment(args),state)}
    case "getShowHardwareCursor": V.Boolean{S.getShowHardwareCursor(environment(args),state)}
    case "getClearOnShrink": V.Boolean{S.getClearOnShrink(environment(args),state)}
    case "getShellPath": pathResult(S.getShellPath(pathEnvironment(),state))
    case "getSessionDir": pathResult(S.getSessionDir(pathEnvironment(),state))
    case "getTheme": maybe(~String,~(value => V.Text{value}),S.getTheme(state))
    case "getGlobalSettings": S.toValue(S.getGlobalSettings(state))
    case "getProjectSettings": S.toValue(S.getProjectSettings(state))
    case "getCompactionSettings": compaction(S.getCompactionSettings(state,model(args)))
    case "getCompactionReserveTokens": S.numberValue(S.getCompactionReserveTokens(state,model(args)))
    case "getCompactionKeepRecentTokens": S.numberValue(S.getCompactionKeepRecentTokens(state,model(args)))
    case "isProjectTrusted": V.Boolean{S.isProjectTrusted(state)}
    case _: V.Text{"UNIMPLEMENTED QUERY"}

def queried(method: String,args: V.Value,fixture: Fixture) -> Fixture:
  match fixture:
    case Fixture{storage,+manager,results}: Fixture{storage,manager,query(method,manager,args) <> results}
def drained(value: S.SettingsManager & List<&2,S.SettingsError>,storage: S.InMemorySettingsStorage,results: List<&2,V.Value>) -> Fixture:
  match value:
    case (manager,issues): Fixture{storage,manager,errors(issues) <> results}
def action(method: String,+input: V.Value,+fixture: Fixture) -> IO(Fixture):
  match method fixture:
    case "set" _: IO.pure(Fixture,actionInput(input,fixture))
    case "nested" _: IO.pure(Fixture,nestedAction(input,fixture))
    case "model" Fixture{_,manager,_}: IO.pure(Fixture,updated(S.setDefaultModelAndProvider(text(get(input,"provider")),text(get(input,"model")),manager),fixture))
    case "analytics" Fixture{_,manager,_}:
      do IO<Fixture>:
        next : S.Outcome(S.SettingsManager) <- S.setEnableAnalytics(enabled(get(input,"value")),manager)
        return updated(next,fixture)
    case "external" _: IO.pure(Fixture,external(text(get(input,"scope")),optional(get(input,"value")),fixture))
    case "override" _: IO.pure(Fixture,applied(plain(get(input,"value")),fixture))
    case "flush" Fixture{storage,manager,results}:
      do IO<Fixture>:
        next : S.InMemorySettingsStorage & S.SettingsManager <- S.flush(~S.InMemorySettingsStorage,~S.memoryWithLock,storage,manager)
        return runtime(next,results)
    case "reload" Fixture{storage,manager,results}:
      do IO<Fixture>:
        next : S.InMemorySettingsStorage & S.SettingsManager <- S.reload(~S.InMemorySettingsStorage,~S.memoryWithLock,storage,manager)
        return runtime(next,results)
    case "trust" Fixture{storage,manager,results}:
      do IO<Fixture>:
        next : S.InMemorySettingsStorage & S.SettingsManager <- S.setProjectTrusted(~S.InMemorySettingsStorage,~S.memoryWithLock,storage,boolean(get(input,"value")),manager)
        return runtime(next,results)
    case "errors" Fixture{storage,manager,results}: IO.pure(Fixture,drained(S.drainErrors(manager),storage,results))
    case _ _: IO.pure(Fixture,queried(method,get(input,"value"),fixture))
def finish(value: Fixture) -> V.Value:
  match value:
    case Fixture{storage,+manager,results}: object(R.Property{"stored",stored(storage)} <> R.Property{"global",S.toValue(S.getGlobalSettings(manager))} <> R.Property{"project",S.toValue(S.getProjectSettings(manager))} <> R.Property{"results",V.ArrayValue{List.reverse(&2,V.Value,results)}} <> Nil{})
def operations(values: List<&2,V.Value>,fixture: Fixture) -> IO(Unit):
  match values:
    case Nil{}: IO.print(stringify(finish(fixture)))
    case +value <> rest:
      do IO<Unit>:
        next : Fixture <- action(text(get(value,"op")),value,fixture)
        operations(rest,next)
def program(+value: V.Value) -> IO(Unit):
  do IO<Unit>:
    loaded : S.InMemorySettingsStorage & S.SettingsManager <- S.fromStorage(~S.InMemorySettingsStorage,~S.memoryWithLock,S.InMemorySettingsStorage{optional(get(value,"global")),optional(get(value,"project"))},S.SettingsManagerCreateOptions{boolean(get(value,"trusted"))})
    operations(array(get(value,"operations")),runtime(loaded,Nil{}))
def parsed(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit,1,"Invalid fixture JSON")
    case Done{value}: program(value)
def run(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        parsed(J.parse(value))
        run(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    run(values)
