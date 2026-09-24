import Base
import ../../../../../agent/src/types.bend as Agent
import ../../../../../ai/src/types.bend as Ai
import ../../../../../runtime/src/json.bend as Json
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../runtime/src/word-segmenter.bend as Segmenter
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/tui.bend as Tui
import ../../../../../tui/src/keybindings.bend as Keybindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/word-navigation.bend as Word
import ../../../../../tui/src/components/settings-list.bend as ListUI
import ../../../core/agent-session.bend as Session
import ../../../core/settings-manager.bend as Settings
import ../theme/theme.bend as Theme
import ../transcript.bend as Transcript

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
def rows(+settings: Settings.SettingsManager) -> List<&2,ListUI.SettingItem>:
  boolean("autocompact","Auto-compact","Automatically compact context when it gets too large",Settings.getCompactionEnabled(settings)) <>
  item("steering-mode","Steering mode","Enter while streaming queues steering messages. 'one-at-a-time': deliver one, wait for response. 'all': deliver all at once.",queue(Settings.getSteeringMode(settings)),choices("one-at-a-time","all")) <>
  item("follow-up-mode","Follow-up mode","Queues follow-up messages until agent stops. 'one-at-a-time': deliver one, wait for response. 'all': deliver all at once.",queue(Settings.getFollowUpMode(settings)),choices("one-at-a-time","all")) <>
  item("transport","Transport","Preferred transport for providers that support multiple transports",transport(Settings.getTransport(settings)),"sse" <> "websocket" <> "websocket-cached" <> "auto" <> Nil{}) <>
  boolean("hide-thinking","Hide thinking","Hide thinking blocks in assistant responses",Settings.getHideThinkingBlock(settings)) <>
  item("mermaid-rendering","Mermaid diagrams","Render Mermaid code blocks as Unicode diagrams",mermaid(Settings.getMermaidRenderingMode(settings)),"off" <> "final" <> "streaming" <> Nil{}) <>
  boolean("cache-miss-notices","Cache miss notices","Show transcript notices for cache costs and provider recovery diagnostics",Settings.getShowCacheMissNotices(settings)) <>
  boolean("collapse-changelog","Collapse changelog","Show condensed changelog after updates",Settings.getCollapseChangelog(settings)) <>
  boolean("quiet-startup","Quiet startup","Disable verbose printing at startup",Settings.getQuietStartup(settings)) <>
  boolean("install-telemetry","Install telemetry","Send an anonymous version/update ping after changelog-detected updates",Settings.getEnableInstallTelemetry(settings)) <>
  item("default-project-trust","Default project trust","Fallback behavior when no extension or saved trust decision decides project trust",trust(Settings.getDefaultProjectTrust(settings)),"Ask" <> "Always trust" <> "Never trust" <> Nil{}) <>
  item("double-escape-action","Double-escape action","Action when pressing Escape twice with empty editor",escape(Settings.getDoubleEscapeAction(settings)),"tree" <> "fork" <> "none" <> Nil{}) <>
  item("tree-filter-mode","Tree filter mode","Default filter when opening /tree",treeFilter(Settings.getTreeFilterMode(settings)),"default" <> "no-tools" <> "user-only" <> "labeled-only" <> "all" <> Nil{}) <>
  boolean("show-images","Show images","Show images in tool output",Settings.getShowImages(settings)) <>
  boolean("auto-resize-images","Auto-resize images","Resize large images to fit the terminal",Settings.getImageAutoResize(settings)) <>
  boolean("block-images","Block images","Do not send image content to providers",Settings.getBlockImages(settings)) <>
  boolean("skill-commands","Skill commands","Expose skills as slash commands",Settings.getEnableSkillCommands(settings)) <>
  boolean("terminal-progress","Terminal progress","Show terminal progress while the agent is working",Settings.getShowTerminalProgress(settings)) <>
  Nil{}

# An invalid choice fails at the boundary instead of silently changing state.
def change(id: String,value: String,settings: Settings.SettingsManager) -> Settings.Outcome(Settings.SettingsManager):
  match id value:
    case "autocompact" "true": Settings.setCompactionEnabled(True{},settings)
    case "autocompact" "false": Settings.setCompactionEnabled(False{},settings)
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
  ChangeContext{session: Ref.Ref<Session.AgentSession>,transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
type CancelContext is Data:
  CancelContext{modal: Ref.Ref<Modal>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
type Host is Data:
  Host{modal: Ref.Ref<Modal>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,session: Ref.Ref<Session.AgentSession>,words: Ref.Ref<Segmenter.Source>,bindings: Keybindings.KeybindingsManager,keyboard: Keys.Context,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,style: ListUI.SettingsListTheme,changed: Callback.Callback<ListUI.Change,Unit>,cancelled: Callback.Callback<Unit,Unit>,completed: Callback.Callback<ListUI.Completion,Unit>}
type Owner is Type:
  Owner{host: Host,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,input: Callback.Callback<String,Unit>,mouse: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>>,invalidate: Callback.Callback<Unit,Unit>,focus: Callback.Callback<Bool,Unit>,label: Callback.Callback<ListUI.ThemeText,String>,value: Callback.Callback<ListUI.ThemeText,String>,description: Callback.Callback<String,String>,hint: Callback.Callback<String,String>,changed: Callback.Callback<ListUI.Change,Unit>,cancelled: Callback.Callback<Unit,Unit>,completed: Callback.Callback<ListUI.Completion,Unit>}

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
      do IO<String>:
        current : Theme.Theme <- Ref.read(Theme.Theme,theme)
        return Result.default(&2,&2,Theme.Error,String,Theme.foreground(current,Bool.pick(String,active,selected,normal),value),value)
def plainPaint(context: Paint,text: String) -> IO(String):
  match context text:
    case Paint{theme,key,_} +value:
      do IO<String>:
        current : Theme.Theme <- Ref.read(Theme.Theme,theme)
        return Result.default(&2,&2,Theme.Error,String,Theme.foreground(current,key,value),value)
def noCompletion(_: Unit,_: ListUI.Completion) -> IO(Unit): IO.pure(Unit,Unit{})
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
    case _ _: Session.changeSettings(session,settings => change(id,value,settings))
def liveEffectDone(id: String,value: String,transcript: Transcript.Handle) -> IO(Unit):
  match id:
    case "hide-thinking": Transcript.setHideThinking(transcript,boolValue(value))
    case _: IO.pure(Unit,Unit{})
def liveEffect(id: String,value: String,transcript: Transcript.Handle,result: Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case Fail{message}: Transcript.showError(transcript,message)
    case Done{_}: liveEffectDone(id,value,transcript)
def changed(context: ChangeContext,selection: ListUI.Change) -> IO(Unit):
  match context selection:
    case ChangeContext{session,+transcript,redraw} ListUI.Change{+id,+newValue}:
      do IO<Unit>:
        current : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        result : Result<&2,&2,String,Unit> <- applied(id,newValue,current)
        liveEffect(id,newValue,transcript,result)
        request(redraw)
def cancelled(context: CancelContext,_: Unit) -> IO(Unit):
  match context:
    case CancelContext{modal,redraw}:
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        request(redraw)
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
    case Host{_,editor,_,_,_,_,_,_,_,_,_,_}: Component.render(editor,width)
def displayedOpen(host: Host,+width: Nat,list: ListUI.SettingsList) -> IO(List<&2,String>):
  match host:
    case Host{modal,_,theme,_,_,_,_,_,_,_,_,_}:
      do IO<List<&2,String>>:
        pair : ListUI.SettingsList & List<&2,String> <- ListUI.render(list,width)
        displayedPair(modal,theme,width,pair)
def displayed(host: Host,width: Nat,current: Modal) -> IO(List<&2,String>):
  match current:
    case Closed{}: displayedClosed(host,width)
    case Open{list}: displayedOpen(host,width,list)
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{+modal,editor,theme,session,words,bindings,keyboard,redraw,style,changed,cancelled,completed}:
      do IO<List<&2,String>>:
        current : Modal <- Ref.read(Modal,modal)
        displayed(Host{modal,editor,theme,session,words,bindings,keyboard,redraw,style,changed,cancelled,completed},width,current)
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
def inputOpen(host: Host,list: ListUI.SettingsList,data: String) -> IO(Unit):
  match host:
    case Host{modal,_,_,_,words,bindings,keyboard,redraw,_,_,_,_}:
      do IO<Unit>:
        source : Segmenter.Source <- Ref.read(Segmenter.Source,words)
        result : Word.ResultOf(ListUI.SettingsList) <- ListUI.handleInput(~Segmenter.Source,~Word.sourceSegments,~nonAtomic,source,list,bindings,keyboard,data)
        accepted(modal,result)
        request(redraw)
def receiveCurrent(current: Modal,host: Host,editor: Component.Component,data: String) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case Open{list}: inputOpen(host,list,data)
def receive(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{+modal,+editor,theme,session,words,bindings,keyboard,redraw,style,changed,cancelled,completed}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        receiveCurrent(current,Host{modal,editor,theme,session,words,bindings,keyboard,redraw,style,changed,cancelled,completed},editor,data)
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
def mouseCurrent(current: Modal,modal: Ref.Ref<Modal>,editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match current:
    case Closed{}: editorMouse(editor,event)
    case Open{list}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        pair : ListUI.SettingsList & Maybe<&2,Component.MouseResponse> <- ListUI.handleMouse(list,event)
        mousePair(modal,pair)
def mouse(host: Host,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match host:
    case Host{+modal,editor,_,_,_,_,_,_,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        current : Modal <- Ref.read(Modal,modal)
        mouseCurrent(current,modal,editor,event)
def invalidated(host: Host,_: Unit) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_,_,_,_,_,_,_}: Component.invalidate(editor)
def focused(host: Host,value: Bool) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_,_,_,_,_,_,_}: Component.setFocused(editor,value)
def createHost(+editor: Component.Component,+theme: Ref.Ref<Theme.Theme>,+session: Ref.Ref<Session.AgentSession>,transcript: Transcript.Handle,words: Segmenter.Source,bindings: Keybindings.KeybindingsManager,keyboard: Keys.Context,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Owner):
  do IO<Owner>:
    +modal : Ref.Ref<Modal> <- Ref.new(Modal,Closed{})
    source : Ref.Ref<Segmenter.Source> <- Ref.new(Segmenter.Source,words)
    +label : Callback.Callback<ListUI.ThemeText,String> <- Callback.create(~Paint,~ListUI.ThemeText,~String,~painted,Paint{theme,"text","accent"})
    +value : Callback.Callback<ListUI.ThemeText,String> <- Callback.create(~Paint,~ListUI.ThemeText,~String,~painted,Paint{theme,"muted","text"})
    +description : Callback.Callback<String,String> <- Callback.create(~Paint,~String,~String,~plainPaint,Paint{theme,"muted","muted"})
    +hint : Callback.Callback<String,String> <- Callback.create(~Paint,~String,~String,~plainPaint,Paint{theme,"dim","dim"})
    +changedCallback : Callback.Callback<ListUI.Change,Unit> <- Callback.create(~ChangeContext,~ListUI.Change,~Unit,~changed,ChangeContext{session,transcript,redraw})
    +cancelledCallback : Callback.Callback<Unit,Unit> <- Callback.create(~CancelContext,~Unit,~Unit,~cancelled,CancelContext{modal,redraw})
    +completed : Callback.Callback<ListUI.Completion,Unit> <- Callback.create(~Unit,~ListUI.Completion,~Unit,~noCompletion,Unit{})
    +style : ListUI.SettingsListTheme <- IO.pure(ListUI.SettingsListTheme,ListUI.SettingsListTheme{label,value,description,"› ",hint})
    +host : Host <- IO.pure(Host,Host{modal,editor,theme,session,source,bindings,keyboard,redraw,style,changedCallback,cancelledCallback,completed})
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Host,~Nat,~List<&2,String>,~draw,host)
    +input : Callback.Callback<String,Unit> <- Callback.create(~Host,~String,~Unit,~receive,host)
    +mouseCallback : Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>> <- Callback.create(~Host,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse>,~mouse,host)
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Host,~Unit,~Unit,~invalidated,host)
    +focus : Callback.Callback<Bool,Unit> <- Callback.create(~Host,~Bool,~Unit,~focused,host)
    +component : Component.Component <- IO.pure(Component.Component,Component.Component{Component.id(editor),render,Some{input},Some{mouseCallback},invalidate,Some{focus},False{}})
    return Owner{host,component,render,input,mouseCallback,invalidate,focus,label,value,description,hint,changedCallback,cancelledCallback,completed}
def borrowHost(owner: Owner) -> Owner & Host & Component.Component:
  match owner:
    case Owner{+host,+component,render,input,mouse,invalidate,focus,label,value,description,hint,changed,cancelled,completed}:
      (Owner{host,component,render,input,mouse,invalidate,focus,label,value,description,hint,changed,cancelled,completed},host,component)
def open(host: Host) -> IO(Unit):
  match host:
    case Host{modal,_,_,session,_,_,_,redraw,style,changed,cancelled,completed}:
      do IO<Unit>:
        current : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        settings : Settings.SettingsManager <- Session.getSettings(current)
        Ref.write(Modal,modal,Open{ListUI.new(rows(settings),10n,style,changed,cancelled,Some{ListUI.SettingsListOptions{True{}}},completed)})
        request(redraw)
def disposeHost(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Host{modal,_,_,_,words,_,_,_,_,_,_,_},_,render,input,mouse,invalidate,focus,label,value,description,hint,changed,cancelled,completed}:
      do IO<Unit>:
        oldModal : Modal <- Ref.dispose(Modal,modal)
        oldSource : Segmenter.Source <- Ref.dispose(Segmenter.Source,words)
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
