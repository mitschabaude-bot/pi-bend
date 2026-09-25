import Base
import ../../../../../agent/src/types.bend as Agent
import ../../../../../ai/src/types.bend as Ai
import ../../../../../runtime/src/json.bend as Json
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../runtime/src/word-segmenter.bend as Segmenter
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/components/editor-component.bend as Live
import ../../../../../tui/src/tui.bend as Tui
import ../../../../../tui/src/keybindings.bend as Keybindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/word-navigation.bend as Word
import ../../../../../tui/src/components/settings-list.bend as ListUI
import ../../../core/agent-session.bend as Session
import ../../../core/settings-manager.bend as Settings
import ../../../../../runtime/src/u64.bend as W
import ../theme/theme.bend as Theme
import ../theme/theme-controller.bend as ThemeController
import ../transcript.bend as Transcript
import ./theme-selector.bend as ThemePicker

# The rows are real settings, in the same order and with the same choices as
# pi's selector. A choice is decoded before it touches the persisted manager.
def item(id: String,label: String,description: String,current: String,values: List<&2,String>) -> ListUI.SettingItem:
  ListUI.SettingItem{id,label,Some{description},current,Some{values},None{}}
def choices(first: String,second: String) -> List<&2,String>: first <> second <> Nil{}
def enabled(value: Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"
def boolean(id: String,label: String,description: String,value: Bool) -> ListUI.SettingItem:
  item(id,label,description,enabled(value),choices("true","false"))
def themeRow(current: String,submenu: Callback.Callback<ListUI.SubmenuRequest,Component.Component>) -> ListUI.SettingItem:
  ListUI.SettingItem{"theme","Theme",Some{"Color theme for the interface"},current,None{},Some{submenu}}
def queue(value: Agent.QueueMode) -> String:
  match value:
    case Agent.All{}: "all"
    case Agent.OneAtATime{}: "one-at-a-time"
def transport(value: Ai.Transport) -> String:
  match value:
    case Ai.Sse{}: "sse"
    case Ai.WebSocket{}: "websocket"
    case Ai.WebSocketCached{}: "websocket-cached"
    case Ai.AutoTransport{}: "auto"
def trust(value: Settings.DefaultProjectTrust) -> String:
  match value:
    case Settings.Ask{}: "Ask"
    case Settings.Always{}: "Always trust"
    case Settings.Never{}: "Never trust"
def escape(value: Settings.DoubleEscapeAction) -> String:
  match value:
    case Settings.Tree{}: "tree"
    case Settings.Fork{}: "fork"
    case Settings.NoDoubleEscape{}: "none"
def treeFilter(value: Settings.TreeFilterMode) -> String:
  match value:
    case Settings.DefaultFilter{}: "default"
    case Settings.NoTools{}: "no-tools"
    case Settings.UserOnly{}: "user-only"
    case Settings.LabeledOnly{}: "labeled-only"
    case Settings.AllEntries{}: "all"
def mermaid(value: Settings.MermaidRenderingMode) -> String:
  match value:
    case Settings.MermaidOff{}: "off"
    case Settings.MermaidFinal{}: "final"
    case Settings.MermaidStreaming{}: "streaming"
def outputPadding(value: Settings.OutputPadding) -> String:
  match value:
    case Settings.NoPadding{}: "0"
    case Settings.OnePadding{}: "1"
def smallNumber(value: W.U64) -> String:
  match value:
    case W.U64{_,low}: U32.show(low)
def modeNames(modes: List<&2,Settings.CacheWarmingMode>) -> List<&2,String>:
  match modes:
    case Nil{}: Nil{}
    case mode <> rest: Settings.cacheWarmingModeName(mode) <> modeNames(rest)
def rows(+settings: Settings.SettingsManager,currentTheme: String,submenu: Callback.Callback<ListUI.SubmenuRequest,Component.Component>) -> List<&2,ListUI.SettingItem>:
  boolean("autocompact","Auto-compact","Automatically compact context when it gets too large",Settings.getCompactionEnabled(settings)) <>
  boolean("auto-resize-images","Auto-resize images","Resize large images to 2000x2000 max for better model compatibility",Settings.getImageAutoResize(settings)) <>
  boolean("block-images","Block images","Prevent images from being sent to LLM providers",Settings.getBlockImages(settings)) <>
  boolean("skill-commands","Skill commands","Register skills as /skill:name commands",Settings.getEnableSkillCommands(settings)) <>
  boolean("show-hardware-cursor","Show hardware cursor","Show the terminal cursor while still positioning it for IME support",Maybe.default(&2,Bool,Settings.selectedShowHardwareCursor(Settings.get(Settings.effective(settings),"showHardwareCursor")),False{})) <>
  item("editor-padding","Editor padding","Horizontal padding for input editor (0-3)",smallNumber(Settings.getEditorPaddingX(settings)),"0" <> "1" <> "2" <> "3" <> Nil{}) <>
  item("output-padding","Output padding","Horizontal padding for user messages, assistant messages, and thinking",outputPadding(Settings.getOutputPad(settings)),choices("0","1")) <>
  item("autocomplete-max-visible","Autocomplete max items","Max visible items in autocomplete dropdown (3-20)",smallNumber(Settings.getAutocompleteMaxVisible(settings)),"3" <> "5" <> "7" <> "10" <> "15" <> "20" <> Nil{}) <>
  boolean("clear-on-shrink","Clear on shrink","Clear empty rows when content shrinks (may cause flicker)",Settings.resolvedClearOnShrink(Settings.terminalOptions(settings),False{})) <>
  boolean("terminal-progress","Terminal progress","Show OSC 9;4 progress indicators in the terminal tab bar",Settings.getShowTerminalProgress(settings)) <>
  item("steering-mode","Steering mode","Enter while streaming queues steering messages. 'one-at-a-time': deliver one, wait for response. 'all': deliver all at once.",queue(Settings.getSteeringMode(settings)),choices("one-at-a-time","all")) <>
  item("follow-up-mode","Follow-up mode","Queues follow-up messages until agent stops. 'one-at-a-time': deliver one, wait for response. 'all': deliver all at once.",queue(Settings.getFollowUpMode(settings)),choices("one-at-a-time","all")) <>
  item("transport","Transport","Preferred transport for providers that support multiple transports",transport(Settings.getTransport(settings)),"sse" <> "websocket" <> "websocket-cached" <> "auto" <> Nil{}) <>
  item("cache-warming-mode","Cache warming","off; streaming while the agent runs; idle also between runs while continuation stays profitable",Settings.cacheWarmingModeName(Settings.getCacheWarmingMode(settings)),modeNames(Settings.CACHE_WARMING_MODES())) <>
  boolean("hide-thinking","Hide thinking","Hide thinking blocks in assistant responses",Settings.getHideThinkingBlock(settings)) <>
  item("mermaid-rendering","Mermaid diagrams","Render Mermaid code blocks as Unicode diagrams",mermaid(Settings.getMermaidRenderingMode(settings)),"off" <> "final" <> "streaming" <> Nil{}) <>
  boolean("cache-miss-notices","Cache miss notices","Show transcript notices for cache costs and provider recovery diagnostics",Settings.getShowCacheMissNotices(settings)) <>
  boolean("collapse-changelog","Collapse changelog","Show condensed changelog after updates",Settings.getCollapseChangelog(settings)) <>
  boolean("quiet-startup","Quiet startup","Disable verbose printing at startup",Settings.getQuietStartup(settings)) <>
  boolean("install-telemetry","Install telemetry","Send an anonymous version/update ping after changelog-detected updates",Settings.getEnableInstallTelemetry(settings)) <>
  item("default-project-trust","Default project trust","Fallback behavior when no extension or saved trust decision decides project trust",trust(Settings.getDefaultProjectTrust(settings)),"Ask" <> "Always trust" <> "Never trust" <> Nil{}) <>
  item("double-escape-action","Double-escape action","Action when pressing Escape twice with empty editor",escape(Settings.getDoubleEscapeAction(settings)),"tree" <> "fork" <> "none" <> Nil{}) <>
  item("tree-filter-mode","Tree filter mode","Default filter when opening /tree",treeFilter(Settings.getTreeFilterMode(settings)),"default" <> "no-tools" <> "user-only" <> "labeled-only" <> "all" <> Nil{}) <>
  themeRow(currentTheme,submenu) <>
  Nil{}

# An invalid choice fails at the boundary instead of silently changing state.
def change(id: String,value: String,settings: Settings.SettingsManager) -> Settings.Outcome(Settings.SettingsManager):
  match id value:
    case "autocompact" "true": Settings.setCompactionEnabled(True{},settings)
    case "autocompact" "false": Settings.setCompactionEnabled(False{},settings)
    case "show-hardware-cursor" "true": Settings.setShowHardwareCursor(True{},settings)
    case "show-hardware-cursor" "false": Settings.setShowHardwareCursor(False{},settings)
    case "editor-padding" "0": Settings.setEditorPaddingX(W.U64{0,0},settings)
    case "editor-padding" "1": Settings.setEditorPaddingX(W.U64{0,1},settings)
    case "editor-padding" "2": Settings.setEditorPaddingX(W.U64{0,2},settings)
    case "editor-padding" "3": Settings.setEditorPaddingX(W.U64{0,3},settings)
    case "output-padding" "0": Settings.setOutputPad(Settings.NoPadding{},settings)
    case "output-padding" "1": Settings.setOutputPad(Settings.OnePadding{},settings)
    case "autocomplete-max-visible" "3": Settings.setAutocompleteMaxVisible(W.U64{0,3},settings)
    case "autocomplete-max-visible" "5": Settings.setAutocompleteMaxVisible(W.U64{0,5},settings)
    case "autocomplete-max-visible" "7": Settings.setAutocompleteMaxVisible(W.U64{0,7},settings)
    case "autocomplete-max-visible" "10": Settings.setAutocompleteMaxVisible(W.U64{0,10},settings)
    case "autocomplete-max-visible" "15": Settings.setAutocompleteMaxVisible(W.U64{0,15},settings)
    case "autocomplete-max-visible" "20": Settings.setAutocompleteMaxVisible(W.U64{0,20},settings)
    case "clear-on-shrink" "true": Settings.setClearOnShrink(True{},settings)
    case "clear-on-shrink" "false": Settings.setClearOnShrink(False{},settings)
    case "steering-mode" "all": Settings.setSteeringMode(Agent.All{},settings)
    case "steering-mode" "one-at-a-time": Settings.setSteeringMode(Agent.OneAtATime{},settings)
    case "follow-up-mode" "all": Settings.setFollowUpMode(Agent.All{},settings)
    case "follow-up-mode" "one-at-a-time": Settings.setFollowUpMode(Agent.OneAtATime{},settings)
    case "transport" "sse": Settings.setTransport(Ai.Sse{},settings)
    case "transport" "websocket": Settings.setTransport(Ai.WebSocket{},settings)
    case "transport" "websocket-cached": Settings.setTransport(Ai.WebSocketCached{},settings)
    case "transport" "auto": Settings.setTransport(Ai.AutoTransport{},settings)
    case "hide-thinking" "true": Settings.setHideThinkingBlock(True{},settings)
    case "hide-thinking" "false": Settings.setHideThinkingBlock(False{},settings)
    case "mermaid-rendering" "off": Settings.setMermaidRenderingMode(Settings.MermaidOff{},settings)
    case "mermaid-rendering" "final": Settings.setMermaidRenderingMode(Settings.MermaidFinal{},settings)
    case "mermaid-rendering" "streaming": Settings.setMermaidRenderingMode(Settings.MermaidStreaming{},settings)
    case "cache-miss-notices" "true": Settings.setShowCacheMissNotices(True{},settings)
    case "cache-miss-notices" "false": Settings.setShowCacheMissNotices(False{},settings)
    case "collapse-changelog" "true": Settings.setCollapseChangelog(True{},settings)
    case "collapse-changelog" "false": Settings.setCollapseChangelog(False{},settings)
    case "quiet-startup" "true": Settings.setQuietStartup(True{},settings)
    case "quiet-startup" "false": Settings.setQuietStartup(False{},settings)
    case "install-telemetry" "true": Settings.setEnableInstallTelemetry(True{},settings)
    case "install-telemetry" "false": Settings.setEnableInstallTelemetry(False{},settings)
    case "default-project-trust" "Ask": Settings.setDefaultProjectTrust(Settings.Ask{},settings)
    case "default-project-trust" "Always trust": Settings.setDefaultProjectTrust(Settings.Always{},settings)
    case "default-project-trust" "Never trust": Settings.setDefaultProjectTrust(Settings.Never{},settings)
    case "double-escape-action" "tree": Settings.setDoubleEscapeAction(Settings.Tree{},settings)
    case "double-escape-action" "fork": Settings.setDoubleEscapeAction(Settings.Fork{},settings)
    case "double-escape-action" "none": Settings.setDoubleEscapeAction(Settings.NoDoubleEscape{},settings)
    case "tree-filter-mode" "default": Settings.setTreeFilterMode(Settings.DefaultFilter{},settings)
    case "tree-filter-mode" "no-tools": Settings.setTreeFilterMode(Settings.NoTools{},settings)
    case "tree-filter-mode" "user-only": Settings.setTreeFilterMode(Settings.UserOnly{},settings)
    case "tree-filter-mode" "labeled-only": Settings.setTreeFilterMode(Settings.LabeledOnly{},settings)
    case "tree-filter-mode" "all": Settings.setTreeFilterMode(Settings.AllEntries{},settings)
    case "show-images" "true": Settings.setShowImages(True{},settings)
    case "show-images" "false": Settings.setShowImages(False{},settings)
    case "theme" _: Settings.setTheme(value,settings)
    case "auto-resize-images" "true": Settings.setImageAutoResize(True{},settings)
    case "auto-resize-images" "false": Settings.setImageAutoResize(False{},settings)
    case "block-images" "true": Settings.setBlockImages(True{},settings)
    case "block-images" "false": Settings.setBlockImages(False{},settings)
    case "skill-commands" "true": Settings.setEnableSkillCommands(True{},settings)
    case "skill-commands" "false": Settings.setEnableSkillCommands(False{},settings)
    case "terminal-progress" "true": Settings.setShowTerminalProgress(True{},settings)
    case "terminal-progress" "false": Settings.setShowTerminalProgress(False{},settings)
    case _ _: Fail{Settings.InvalidSetting{Json.InvalidValue{Nil{},"known setting choice"}}}

type Modal is Data: Closed{} Open{list: ListUI.SettingsList}
type Paint is Data: Paint{theme: Ref.Ref<Theme.Theme>,ordinary: String,selected: String}
type ChangeContext is Data:
  ChangeContext{session: Ref.Ref<Session.AgentSession>,transcript: Transcript.Handle,editor: Ref.Ref<Maybe<&2,Live.Handle>>,controller: Ref.Ref<Maybe<&2,ThemeController.Handle>>}
type CancelContext is Data:
  CancelContext{modal: Ref.Ref<Modal>}
type CompletionContext is Data:
  CompletionContext{pending: Ref.Ref<Maybe<&2,ListUI.Completion>>}
type Host is Data:
  Host{modal: Ref.Ref<Modal>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,session: Ref.Ref<Session.AgentSession>,words: Ref.Ref<Segmenter.Source>,bindings: Keybindings.KeybindingsManager,keyboard: Keys.Context,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,style: ListUI.SettingsListTheme,changed: Callback.Callback<ListUI.Change,Unit>,cancelled: Callback.Callback<Unit,Unit>,completed: Callback.Callback<ListUI.Completion,Unit>,controller: Ref.Ref<Maybe<&2,ThemeController.Handle>>,themeSubmenu: Callback.Callback<ListUI.SubmenuRequest,Component.Component>,pending: Ref.Ref<Maybe<&2,ListUI.Completion>>}
type Owner is Type:
  Owner{host: Host,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,input: Callback.Callback<String,Unit>,mouse: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>>,invalidate: Callback.Callback<Unit,Unit>,focus: Callback.Callback<Bool,Unit>,label: Callback.Callback<ListUI.ThemeText,String>,value: Callback.Callback<ListUI.ThemeText,String>,description: Callback.Callback<String,String>,hint: Callback.Callback<String,String>,changed: Callback.Callback<ListUI.Change,Unit>,cancelled: Callback.Callback<Unit,Unit>,completed: Callback.Callback<ListUI.Completion,Unit>,themeOwner: ThemePicker.Owner}

def requested(callback: Maybe<&2,Callback.Callback<Unit,Unit>>) -> IO(Unit):
  match callback:
    case Some{ready}: Callback.call(Unit,Unit,ready,Unit{})
    case None{}: IO.pure(Unit,Unit{})
def request(redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Unit):
  do IO<Unit>:
    callback : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.read(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw)
    requested(callback)
def painted(context: Paint,text: ListUI.ThemeText) -> IO(String):
  match context text:
    case Paint{theme,normal,selected} ListUI.ThemeText{+value,active}:
      +key = Bool.pick(String,active,selected,normal)
      do IO<String>:
        current : Theme.Theme <- Ref.read(Theme.Theme,theme)
        return Bool.pick(String,String.is_empty(key),value,Result.default(&2,&2,Theme.Error,String,Theme.foreground(current,key,value),value))
def plainPaint(context: Paint,text: String) -> IO(String):
  match context text:
    case Paint{theme,key,_} +value:
      do IO<String>:
        current : Theme.Theme <- Ref.read(Theme.Theme,theme)
        return Result.default(&2,&2,Theme.Error,String,Theme.foreground(current,key,value),value)
def completedSubmenu(context: CompletionContext,completion: ListUI.Completion) -> IO(Unit):
  match context:
    case CompletionContext{pending}: Ref.write(Maybe<&2,ListUI.Completion>,pending,Some{completion})
def boolValue(value: String) -> Bool: String.eq(value,"true")
def applied(id: String,value: String,session: Session.AgentSession) -> IO(Result<&2,&2,String,Unit>):
  match id value:
    case "autocompact" "true": Session.setAutoCompactionEnabled(session,True{})
    case "autocompact" "false": Session.setAutoCompactionEnabled(session,False{})
    case "steering-mode" "all": Session.setSteeringMode(session,Agent.All{})
    case "steering-mode" "one-at-a-time": Session.setSteeringMode(session,Agent.OneAtATime{})
    case "follow-up-mode" "all": Session.setFollowUpMode(session,Agent.All{})
    case "follow-up-mode" "one-at-a-time": Session.setFollowUpMode(session,Agent.OneAtATime{})
    case "transport" "sse": Session.setTransport(session,Ai.Sse{})
    case "transport" "websocket": Session.setTransport(session,Ai.WebSocket{})
    case "transport" "websocket-cached": Session.setTransport(session,Ai.WebSocketCached{})
    case "transport" "auto": Session.setTransport(session,Ai.AutoTransport{})
    case "cache-warming-mode" "off": Session.setCacheWarmingMode(session,Settings.CacheWarmingOff{})
    case "cache-warming-mode" "streaming": Session.setCacheWarmingMode(session,Settings.CacheWarmingStreaming{})
    case "cache-warming-mode" "idle": Session.setCacheWarmingMode(session,Settings.CacheWarmingIdle{})
    case _ _: Session.changeSettings(session,settings => change(id,value,settings))
def editorChoice(current: Maybe<&2,Live.Handle>,id: String,value: String) -> IO(Unit):
  match current id value:
    case Some{handle} "editor-padding" "0": Live.setPaddingX(handle,0n)
    case Some{handle} "editor-padding" "1": Live.setPaddingX(handle,1n)
    case Some{handle} "editor-padding" "2": Live.setPaddingX(handle,2n)
    case Some{handle} "editor-padding" "3": Live.setPaddingX(handle,3n)
    case Some{handle} "autocomplete-max-visible" "3": Live.setAutocompleteMaxVisible(handle,3n)
    case Some{handle} "autocomplete-max-visible" "5": Live.setAutocompleteMaxVisible(handle,5n)
    case Some{handle} "autocomplete-max-visible" "7": Live.setAutocompleteMaxVisible(handle,7n)
    case Some{handle} "autocomplete-max-visible" "10": Live.setAutocompleteMaxVisible(handle,10n)
    case Some{handle} "autocomplete-max-visible" "15": Live.setAutocompleteMaxVisible(handle,15n)
    case Some{handle} "autocomplete-max-visible" "20": Live.setAutocompleteMaxVisible(handle,20n)
    case _ _ _: IO.pure(Unit,Unit{})
def editorEffect(id: String,value: String,editor: Ref.Ref<Maybe<&2,Live.Handle>>) -> IO(Unit):
  do IO<Unit>:
    current : Maybe<&2,Live.Handle> <- Ref.read(Maybe<&2,Live.Handle>,editor)
    editorChoice(current,id,value)
def transcriptEffect(id: String,value: String,transcript: Transcript.Handle) -> IO(Unit):
  match id value:
    case "hide-thinking" _: Transcript.setHideThinking(transcript,boolValue(value))
    case "output-padding" "0": Transcript.setOutputPad(transcript,0n)
    case "output-padding" "1": Transcript.setOutputPad(transcript,1n)
    case _ _: IO.pure(Unit,Unit{})
def liveEffectDone(+id: String,+value: String,transcript: Transcript.Handle,editor: Ref.Ref<Maybe<&2,Live.Handle>>) -> IO(Unit):
  do IO<Unit>:
    transcriptEffect(id,value,transcript)
    editorEffect(id,value,editor)
def liveEffect(id: String,value: String,transcript: Transcript.Handle,editor: Ref.Ref<Maybe<&2,Live.Handle>>,result: Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case Fail{message}: Transcript.showError(transcript,message)
    case Done{_}: liveEffectDone(id,value,transcript,editor)
def themeResult(result: Result<&2,&2,Theme.LoadError,ThemeController.Selection>,transcript: Transcript.Handle) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit,Unit{})
    case Fail{_}: Transcript.showError(transcript,"Cannot apply theme")
def themeChanged(current: Maybe<&2,ThemeController.Handle>,value: String,transcript: Transcript.Handle) -> IO(Unit):
  match current:
    case None{}: IO.pure(Unit,Unit{})
    case Some{handle}:
      do IO<Unit>:
        result : Result<&2,&2,Theme.LoadError,ThemeController.Selection> <- ThemeController.setThemeSetting(handle,Some{value})
        themeResult(result,transcript)
def themeEffect(id: String,value: String,controller: Ref.Ref<Maybe<&2,ThemeController.Handle>>,transcript: Transcript.Handle) -> IO(Unit):
  match id:
    case "theme":
      do IO<Unit>:
        current : Maybe<&2,ThemeController.Handle> <- Ref.read(Maybe<&2,ThemeController.Handle>,controller)
        themeChanged(current,value,transcript)
    case _: IO.pure(Unit,Unit{})
def themeAfter(result: Result<&2,&2,String,Unit>,id: String,value: String,controller: Ref.Ref<Maybe<&2,ThemeController.Handle>>,transcript: Transcript.Handle) -> IO(Unit):
  match result:
    case Fail{_}: IO.pure(Unit,Unit{})
    case Done{_}: themeEffect(id,value,controller,transcript)
def changeSetting(context: ChangeContext,selection: ListUI.Change) -> IO(Unit):
  match context selection:
    case ChangeContext{session,+transcript,editor,controller} ListUI.Change{+id,+newValue}:
      do IO<Unit>:
        current : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        +result : Result<&2,&2,String,Unit> <- applied(id,newValue,current)
        liveEffect(id,newValue,transcript,editor,result)
        themeAfter(result,id,newValue,controller,transcript)
def cancelPanel(context: CancelContext,_: Unit) -> IO(Unit):
  match context:
    case CancelContext{modal}: Ref.write(Modal,modal,Closed{})
def border(width: Nat) -> String:
  match width:
    case Zero{}: ""
    case Succ{rest}: "─" ++ border(rest)
def borderPainted(theme: Theme.Theme,width: Nat) -> String:
  +line = border(width)
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,"border",line),line)
def displayedPair(modal: Ref.Ref<Modal>,theme: Ref.Ref<Theme.Theme>,width: Nat,pair: ListUI.SettingsList & List<&2,String>) -> IO(List<&2,String>):
  match pair:
    case (next,lines):
      do IO<List<&2,String>>:
        Ref.write(Modal,modal,Open{next})
        currentTheme : Theme.Theme <- Ref.read(Theme.Theme,theme)
        +rule : String <- IO.pure(String,borderPainted(currentTheme,width))
        return rule <> List.append(&2,String,lines,rule <> Nil{})
def displayedClosed(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{_,editor,_,_,_,_,_,_,_,_,_,_,_,_,_}: Component.render(editor,width)
def displayedOpen(host: Host,+width: Nat,list: ListUI.SettingsList) -> IO(List<&2,String>):
  match host:
    case Host{modal,_,theme,_,_,_,_,_,_,_,_,_,_,_,_}:
      do IO<List<&2,String>>:
        pair : ListUI.SettingsList & List<&2,String> <- ListUI.render(list,width)
        displayedPair(modal,theme,width,pair)
def displayed(host: Host,width: Nat,current: Modal) -> IO(List<&2,String>):
  match current:
    case Closed{}: displayedClosed(host,width)
    case Open{list}: displayedOpen(host,width,list)
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{+modal,editor,theme,session,words,bindings,keyboard,redraw,style,changed,cancelled,completed,controller,themeSubmenu,pending}:
      do IO<List<&2,String>>:
        current : Modal <- Ref.read(Modal,modal)
        displayed(Host{modal,editor,theme,session,words,bindings,keyboard,redraw,style,changed,cancelled,completed,controller,themeSubmenu,pending},width,current)
def nonAtomic(_: Segmenter.Source,_: String) -> Bool: False{}
def keepOpen(current: Modal,modal: Ref.Ref<Modal>,next: ListUI.SettingsList) -> IO(Unit):
  match current:
    case Closed{}: IO.pure(Unit,Unit{})
    case Open{_}: Ref.write(Modal,modal,Open{next})
def accepted(+modal: Ref.Ref<Modal>,result: Word.ResultOf(ListUI.SettingsList)) -> IO(Unit):
  match result:
    case Done{next}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        keepOpen(current,modal,next)
    case Fail{_}: IO.pure(Unit,Unit{})
def completedInput(result: Word.ResultOf(ListUI.SettingsList),completion: Maybe<&2,ListUI.Completion>) -> IO(Word.ResultOf(ListUI.SettingsList)):
  match result completion:
    case Done{list} Some{choice}:
      do IO<Word.ResultOf(ListUI.SettingsList)>:
        next : ListUI.SettingsList <- ListUI.completeSubmenu(list,choice)
        return Done{next}
    case _ _: IO.pure(Word.ResultOf(ListUI.SettingsList),result)
def applyCompletion(result: Word.ResultOf(ListUI.SettingsList),+pending: Ref.Ref<Maybe<&2,ListUI.Completion>>) -> IO(Word.ResultOf(ListUI.SettingsList)):
  do IO<Word.ResultOf(ListUI.SettingsList)>:
    completion : Maybe<&2,ListUI.Completion> <- Ref.read(Maybe<&2,ListUI.Completion>,pending)
    Ref.write(Maybe<&2,ListUI.Completion>,pending,None{})
    completedInput(result,completion)
def inputOpen(host: Host,list: ListUI.SettingsList,data: String) -> IO(Unit):
  match host:
    case Host{modal,_,_,_,words,bindings,keyboard,_,_,_,_,_,_,_,pending}:
      do IO<Unit>:
        source : Segmenter.Source <- Ref.read(Segmenter.Source,words)
        result : Word.ResultOf(ListUI.SettingsList) <- ListUI.handleInput(~Segmenter.Source,~Word.sourceSegments,~nonAtomic,source,list,bindings,keyboard,data)
        completed : Word.ResultOf(ListUI.SettingsList) <- applyCompletion(result,pending)
        accepted(modal,completed)
def receiveCurrent(current: Modal,host: Host,editor: Component.Component,data: String) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case Open{list}: inputOpen(host,list,data)
def receive(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{+modal,+editor,theme,session,words,bindings,keyboard,redraw,style,changed,cancelled,completed,controller,themeSubmenu,pending}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        receiveCurrent(current,Host{modal,editor,theme,session,words,bindings,keyboard,redraw,style,changed,cancelled,completed,controller,themeSubmenu,pending},editor,data)
def editorMouse(editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match editor:
    case Component.Component{_,_,_,Some{callback},_,_,_}: Callback.call(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,callback,event)
    case _: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def mousePair(modal: Ref.Ref<Modal>,pair: ListUI.SettingsList & Maybe<&2,Component.MouseResponse>) -> IO(Maybe<&2,Component.MouseResponse>):
  match pair:
    case (next,result):
      do IO<Maybe<&2,Component.MouseResponse>>:
        Ref.write(Modal,modal,Open{next})
        return result
def listMouseEvent(event: Tui.TuiMouseEvent) -> Tui.TuiMouseEvent:
  match event:
    case Tui.TuiMouseEvent{kind,button,x,y,screenX,screenY,width,height,shift,alt,ctrl,wheel,clicks}:
      Tui.TuiMouseEvent{kind,button,x,Component.subtract(y,Tui.Forward{1n}),screenX,screenY,width,height,shift,alt,ctrl,wheel,clicks}
def mouseCurrent(current: Modal,modal: Ref.Ref<Modal>,editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match current:
    case Closed{}: editorMouse(editor,event)
    case Open{list}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        pair : ListUI.SettingsList & Maybe<&2,Component.MouseResponse> <- ListUI.handleMouse(list,listMouseEvent(event))
        mousePair(modal,pair)
def mouseEvent(host: Host,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match host:
    case Host{+modal,editor,_,_,_,_,_,_,_,_,_,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        current : Modal <- Ref.read(Modal,modal)
        result : Maybe<&2,Component.MouseResponse> <- mouseCurrent(current,modal,editor,event)
        return result
def invalidated(host: Host,_: Unit) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_,_,_,_,_,_,_,_,_,_}: Component.invalidate(editor)
def focused(host: Host,value: Bool) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_,_,_,_,_,_,_,_,_,_}: Component.setFocused(editor,value)
def createHost(+editor: Component.Component,+theme: Ref.Ref<Theme.Theme>,+session: Ref.Ref<Session.AgentSession>,+transcript: Transcript.Handle,editorHandle: Ref.Ref<Maybe<&2,Live.Handle>>,words: Segmenter.Source,+bindings: Keybindings.KeybindingsManager,+keyboard: Keys.Context,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Owner):
  do IO<Owner>:
    +modal : Ref.Ref<Modal> <- Ref.new(Modal,Closed{})
    +pending : Ref.Ref<Maybe<&2,ListUI.Completion>> <- Ref.new(Maybe<&2,ListUI.Completion>,None{})
    +themeController : Ref.Ref<Maybe<&2,ThemeController.Handle>> <- Ref.new(Maybe<&2,ThemeController.Handle>,None{})
    +themeOwner : ThemePicker.Owner <- ThemePicker.createHost(editor,theme,themeController,transcript,bindings,keyboard)
    +themeSubmenu : Callback.Callback<ListUI.SubmenuRequest,Component.Component> <- IO.pure(Callback.Callback<ListUI.SubmenuRequest,Component.Component>,ThemePicker.factoryOf(themeOwner))
    source : Ref.Ref<Segmenter.Source> <- Ref.new(Segmenter.Source,words)
    +label : Callback.Callback<ListUI.ThemeText,String> <- Callback.create(~Paint,~ListUI.ThemeText,~String,~painted,Paint{theme,"","accent"})
    +value : Callback.Callback<ListUI.ThemeText,String> <- Callback.create(~Paint,~ListUI.ThemeText,~String,~painted,Paint{theme,"muted","accent"})
    +description : Callback.Callback<String,String> <- Callback.create(~Paint,~String,~String,~plainPaint,Paint{theme,"dim","dim"})
    +hint : Callback.Callback<String,String> <- Callback.create(~Paint,~String,~String,~plainPaint,Paint{theme,"dim","dim"})
    +changedCallback : Callback.Callback<ListUI.Change,Unit> <- Callback.create(~ChangeContext,~ListUI.Change,~Unit,~changeSetting,ChangeContext{session,transcript,editorHandle,themeController})
    +cancelledCallback : Callback.Callback<Unit,Unit> <- Callback.create(~CancelContext,~Unit,~Unit,~cancelPanel,CancelContext{modal})
    +completed : Callback.Callback<ListUI.Completion,Unit> <- Callback.create(~CompletionContext,~ListUI.Completion,~Unit,~completedSubmenu,CompletionContext{pending})
    currentTheme : Theme.Theme <- Ref.read(Theme.Theme,theme)
    cursor : String <- IO.pure(String,Result.default(&2,&2,Theme.Error,String,Theme.foreground(currentTheme,"accent","→ "),"→ "))
    +style : ListUI.SettingsListTheme <- IO.pure(ListUI.SettingsListTheme,ListUI.SettingsListTheme{label,value,description,cursor,hint})
    +host : Host <- IO.pure(Host,Host{modal,editor,theme,session,source,bindings,keyboard,redraw,style,changedCallback,cancelledCallback,completed,themeController,themeSubmenu,pending})
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Host,~Nat,~List<&2,String>,~draw,host)
    +input : Callback.Callback<String,Unit> <- Callback.create(~Host,~String,~Unit,~receive,host)
    +mouseCallback : Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>> <- Callback.create(~Host,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse>,~mouseEvent,host)
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Host,~Unit,~Unit,~invalidated,host)
    +focus : Callback.Callback<Bool,Unit> <- Callback.create(~Host,~Bool,~Unit,~focused,host)
    +component : Component.Component <- IO.pure(Component.Component,Component.Component{Component.id(editor),render,Some{input},Some{mouseCallback},invalidate,Some{focus},False{}})
    return Owner{host,component,render,input,mouseCallback,invalidate,focus,label,value,description,hint,changedCallback,cancelledCallback,completed,themeOwner}
def borrowHost(owner: Owner) -> Owner & Host & Component.Component:
  match owner:
    case Owner{+host,+component,render,input,mouse,invalidate,focus,label,value,description,hint,changed,cancelled,completed,themeOwner}:
      (Owner{host,component,render,input,mouse,invalidate,focus,label,value,description,hint,changed,cancelled,completed,themeOwner},host,component)
def open(host: Host) -> IO(Unit):
  match host:
    case Host{modal,_,_,session,_,_,_,redraw,style,changed,cancelled,completed,_,themeSubmenu,_}:
      do IO<Unit>:
        current : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        +settings : Settings.SettingsManager <- Session.getSettings(current)
        Ref.write(Modal,modal,Open{ListUI.new(rows(settings,Maybe.default(&2,String,Settings.getThemeSetting(settings),"dark"),themeSubmenu),10n,style,changed,cancelled,Some{ListUI.SettingsListOptions{True{}}},completed)})
        request(redraw)
def installController(host: Host,handle: ThemeController.Handle) -> IO(Unit):
  match host:
    case Host{_,_,_,_,_,_,_,_,_,_,_,_,controller,_,_}: Ref.write(Maybe<&2,ThemeController.Handle>,controller,Some{handle})
def disposeHost(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Host{modal,_,_,_,words,_,_,_,_,_,_,_,controller,_,pending},_,render,input,mouse,invalidate,focus,label,value,description,hint,changed,cancelled,completed,themeOwner}:
      do IO<Unit>:
        oldModal : Modal <- Ref.dispose(Modal,modal)
        oldSource : Segmenter.Source <- Ref.dispose(Segmenter.Source,words)
        oldController : Maybe<&2,ThemeController.Handle> <- Ref.dispose(Maybe<&2,ThemeController.Handle>,controller)
        oldPending : Maybe<&2,ListUI.Completion> <- Ref.dispose(Maybe<&2,ListUI.Completion>,pending)
        ThemePicker.disposeHost(themeOwner)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(String,Unit,input)
        Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,mouse)
        Callback.dispose(Unit,Unit,invalidate)
        Callback.dispose(Bool,Unit,focus)
        Callback.dispose(ListUI.ThemeText,String,label)
        Callback.dispose(ListUI.ThemeText,String,value)
        Callback.dispose(String,String,description)
        Callback.dispose(String,String,hint)
        Callback.dispose(ListUI.Change,Unit,changed)
        Callback.dispose(Unit,Unit,cancelled)
        Callback.dispose(ListUI.Completion,Unit,completed)
