import Base
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/deferred.bend as Deferred
import ../../../../runtime/src/filesystem.bend as Filesystem
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/posix-path.bend as Path
import ../../../../runtime/src/record.bend as Record
import ../../../../runtime/src/ref.bend as Ref
import ../../../../runtime/src/schema-value.bend as Schema
import ../../../../runtime/src/word-segmenter.bend as Words
import ../../../../tui/src/component.bend as Component
import ../../../../tui/src/components/editor.bend as Editor
import ../../../../tui/src/components/editor-component.bend as Live
import ../../../../tui/src/components/select-list.bend as Select
import ../../../../tui/src/keybindings.bend as Keybindings
import ../../../../tui/src/keys.bend as Keys
import ../../../../tui/src/tui-base.bend as Tui
import ../../../../tui/src/tui-main-screen.bend as Screen
import ../../../../tui/src/tui-process.bend as Process
import ../../../../tui/src/terminal.bend as Terminal
import ../../../../tui/src/utils.bend as Utils
import ../../core/agent-runtime.bend as Runtime
import ../../core/agent-session.bend as Session
import ./components/footer.bend as Footer
import ./theme/color.bend as Color
import ./theme/markdown-theme.bend as MarkdownTheme
import ./theme/theme.bend as Theme
import ./interactive-mode.bend as Interactive
import ./session-controller.bend as Controller
import ./transcript.bend as Transcript
import ./viewport.bend as View

type Error is Data:
  WordData{cause: Words.LoadError}
  ThemeData{cause: Theme.LoadError}
  Layout{cause: Tui.Error}
  TerminalStart{cause: Terminal.Error}

def wordError(error: Words.LoadError) -> String:
  match error:
    case Words.ReadFailed{path,cause}: "Cannot load word data " ++ path ++ ": " ++ Filesystem.errorMessage(cause)
    case Words.InvalidAsset{path}: "Invalid word data: " ++ path
def themeError(error: Theme.LoadError) -> String:
  match error:
    case Theme.Read{cause}: "Cannot load theme: " ++ Filesystem.errorMessage(cause)
    case Theme.Decode{_}: "Invalid theme encoding"
    case Theme.Invalid{_}: "Invalid theme"
    case Theme.NotFound{name}: "Theme not found: " ++ name
def errorMessage(error: Error) -> String:
  match error:
    case WordData{cause}: wordError(cause)
    case ThemeData{cause}: themeError(cause)
    case Layout{_}: "Cannot mount interactive layout"
    case TerminalStart{Terminal.System{operation,_,message}}: "Terminal " ++ operation ++ ": " ++ message
    case TerminalStart{_}: "Cannot start terminal"

def converted(result: Result<&2,&2,F.Error,Nat>) -> Nat:
  match result:
    case Done{number}: number
    case Fail{_}: 0n
def count(value: F64) -> Nat: converted(F.convert(value))
def thinking(level: Ai.ModelThinkingLevel) -> String:
  match level:
    case Ai.Off{}: "off"
    case Ai.Thinking{Ai.Minimal{}}: "minimal"
    case Ai.Thinking{Ai.Low{}}: "low"
    case Ai.Thinking{Ai.Medium{}}: "medium"
    case Ai.Thinking{Ai.High{}}: "high"
    case Ai.Thinking{Ai.XHigh{}}: "xhigh"
    case Ai.Thinking{Ai.Max{}}: "max"
def model(value: Ai.Model<Ai.JsonValue>) -> Footer.Model:
  match value:
    case Ai.Model{id,_,_,provider,_,reasoning,_,_,_,_,_,window,_,_,_,_}:
      Footer.Model{id,provider,reasoning,count(window)}
def usage(value: Ai.Usage) -> Footer.Usage:
  match value:
    case Ai.Usage{input,output,read,write,_,_,_,Ai.UsageCost{_,_,_,_,cost}}:
      Footer.Usage{count(input),count(output),count(read),count(write),cost}
def usageTokens(value: Ai.Usage) -> F64:
  match value: case Ai.Usage{input,_,read,write,_,_,_,_}: F.add(input,F.add(read,write))
def percent(tokens: F64,chosen: Maybe<&2,Footer.Model>) -> Maybe<&2,F64>:
  match chosen:
    case Some{Footer.Model{_,_,_,+window}}:
      Bool.pick(Maybe<&2,F64>,Nat.is_eq(window,0n),None{},Some{F.multiply(F.divide(tokens,F.fromNat(window)),F.fromNat(100n))})
    case None{}: None{}
def latestModel(previous: Maybe<&2,Footer.Model>,+message: Ai.AssistantMessage<Schema.Value,Unit>) -> Maybe<&2,Footer.Model>:
  match previous:
    case Some{Footer.Model{_,_,reasoning,window}}: Some{Footer.Model{Ai.assistantModel(Schema.Value,Unit,message),Ai.assistantProvider(Schema.Value,Unit,message),reasoning,window}}
    case None{}: previous
def withAssistant(state: Footer.State,+message: Ai.AssistantMessage<Schema.Value,Unit>) -> Footer.State:
  match state:
    case Footer.State{cwd,home,branch,name,chosen,thinkingLevel,totals,_,_,window,providers,subscription,auto,experimental,statuses}:
      +raw = Ai.assistantUsage(Schema.Value,Unit,message)
      +latest = usage(raw)
      +nextModel = latestModel(chosen,message)
      Footer.State{cwd,home,branch,name,nextModel,thinkingLevel,Footer.addUsage(totals,latest),Some{latest},percent(usageTokens(raw),nextModel),window,providers,subscription,auto,experimental,statuses}
def seedFooter(messages: List<&2,Session.Message()>,state: Footer.State) -> Footer.State:
  match messages:
    case Nil{}: state
    case Agent.LlmMessage{Ai.Assistant{message}} <> rest: seedFooter(rest,withAssistant(state,message))
    case _ <> rest: seedFooter(rest,state)
def initialFooter(+agentState: Session.AgentState(),messages: List<&2,Session.Message()>,cwd: String,home: Maybe<&2,String>) -> Footer.State:
  +chosen = model(Session.stateModel(agentState))
  seedFooter(messages,Footer.State{cwd,home,None{},None{},Some{chosen},thinking(Session.stateThinking(agentState)),Footer.emptyUsage(),None{},None{},None{},1n,False{},False{},False{},Nil{}})
def withStatus(state: Footer.State,statuses: List<&2,Footer.Status>) -> Footer.State:
  match state:
    case Footer.State{cwd,home,branch,name,chosen,thinkingLevel,totals,latest,context,window,providers,subscription,auto,experimental,_}:
      Footer.State{cwd,home,branch,name,chosen,thinkingLevel,totals,latest,context,window,providers,subscription,auto,experimental,statuses}
def withThinking(state: Footer.State,level: Ai.ModelThinkingLevel) -> Footer.State:
  match state:
    case Footer.State{cwd,home,branch,name,chosen,_,totals,latest,context,window,providers,subscription,auto,experimental,statuses}:
      Footer.State{cwd,home,branch,name,chosen,thinking(level),totals,latest,context,window,providers,subscription,auto,experimental,statuses}
def withName(state: Footer.State,name: Maybe<&2,String>) -> Footer.State:
  match state:
    case Footer.State{cwd,home,branch,_,chosen,thinkingLevel,totals,latest,context,window,providers,subscription,auto,experimental,statuses}:
      Footer.State{cwd,home,branch,name,chosen,thinkingLevel,totals,latest,context,window,providers,subscription,auto,experimental,statuses}
def footerEvent(state: Footer.State,event: Session.AgentSessionEvent) -> Footer.State & Bool:
  match event:
    case Session.AgentEvent{Agent.MessageEnd{Agent.LlmMessage{Ai.Assistant{message}}}}: (withAssistant(state,message),True{})
    case Session.AgentEvent{Agent.AgentStart{}}: (withStatus(state,Footer.Status{"agent","Working"} <> Nil{}),True{})
    case Session.AgentSettled{}: (withStatus(state,Nil{}),True{})
    case Session.AutoRetryStart{attempt,_,_,_}: (withStatus(state,Footer.Status{"retry","Retry " ++ Nat.show(attempt)} <> Nil{}),True{})
    case Session.AutoRetryEnd{_,_,_}: (withStatus(state,Nil{}),True{})
    case Session.CompactionStart{_}: (withStatus(state,Footer.Status{"compact","Compacting"} <> Nil{}),True{})
    case Session.CompactionEnd{_,_,_,_,_}: (withStatus(state,Nil{}),True{})
    case Session.ThinkingLevelChanged{level}: (withThinking(state,level),True{})
    case Session.SessionInfoChanged{name}: (withName(state,name),True{})
    case _: (state,False{})
type Observation is Data:
  Observation{transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,footer: Ref.Ref<Footer.State>}
def observeCopied(input: Observation,+event: Session.AgentSessionEvent) -> IO(Unit):
  match input:
    case Observation{transcript,+redraw,footer}:
      do IO<Unit>:
        changed : Bool <- Ref.modify(Footer.State,Bool,footer,state => footerEvent(state,event))
        Interactive.onSessionEvent(Interactive.Events{transcript,redraw},event)
        Bool.pick(Unit -> IO(Unit),changed,_ => Interactive.requestRender(redraw),_ => IO.pure(Unit,Unit{}))(Unit{})
def observed(input: Observation,event: Session.AgentSessionEvent) -> IO(Unit):
  observeCopied(input,event)
type WorkerFailure is Data:
  WorkerFailure{failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
def promptFailed(input: WorkerFailure,value: Controller.PromptFailure) -> IO(Unit):
  match input value:
    case WorkerFailure{failure,redraw} Controller.PromptFailure{message}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Interactive.SubmissionFailure>,failure,Some{Interactive.PromptFailure{message}})
        Interactive.requestRender(redraw)

type FooterPaint is Data: FooterPaint{state: Ref.Ref<Footer.State>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,theme: Theme.Theme}
type FooterOwner is Data: FooterOwner{state: Ref.Ref<Footer.State>,failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>}

def appendedFailure(lines: List<&2,String>,plain: String,painted: Result<&2,&2,Theme.Error,String>) -> List<&2,String>:
  match painted:
    case Done{colored}: List.append(&2,String,lines,colored <> Nil{})
    case Fail{_}: List.append(&2,String,lines,plain <> Nil{})
def withFailure(lines: List<&2,String>,failure: Maybe<&2,Interactive.SubmissionFailure>,theme: Theme.Theme,width: Nat) -> List<&2,String>:
  match failure:
    case None{}: lines
    case Some{value}:
      +plain = Utils.truncateToWidth("Error: " ++ Interactive.failureText(value),width,"...",False{})
      appendedFailure(lines,plain,Theme.foreground(theme,"error",plain))
def footerLinesCopied(paint: FooterPaint,+width: Nat) -> IO(List<&2,String>):
  match paint:
    case FooterPaint{state,failure,+theme}:
      do IO<List<&2,String>>:
        current : Footer.State <- Ref.read(Footer.State,state)
        failed : Maybe<&2,Interactive.SubmissionFailure> <- Ref.read(Maybe<&2,Interactive.SubmissionFailure>,failure)
        lines : List<&2,String> <- Footer.render(current,theme,width)
        return withFailure(lines,failed,theme,width)
def footerLines(paint: FooterPaint,width: Nat) -> IO(List<&2,String>):
  footerLinesCopied(paint,width)
def ignore(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def footer(initial: Footer.State,theme: Theme.Theme) -> IO(FooterOwner):
  do IO<FooterOwner>:
    +state : Ref.Ref<Footer.State> <- Ref.new(Footer.State,initial)
    +failure : Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>> <- Ref.new(Maybe<&2,Interactive.SubmissionFailure>,None{})
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~FooterPaint,~Nat,~List<&2,String>,~footerLines,FooterPaint{state,failure,theme})
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    return FooterOwner{state,failure,Component.Component{Component.ComponentId{3n},render,None{},None{},invalidate,None{},False{}},render,invalidate}
def footerState(owner: FooterOwner) -> Ref.Ref<Footer.State>:
  match owner: case FooterOwner{state,_,_,_,_}: state
def footerFailure(owner: FooterOwner) -> Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>:
  match owner: case FooterOwner{_,failure,_,_,_}: failure
def footerComponent(owner: FooterOwner) -> Component.Component:
  match owner: case FooterOwner{_,_,component,_,_}: component
def disposeFooter(owner: FooterOwner) -> IO(Unit):
  match owner:
    case FooterOwner{state,failure,_,render,invalidate}:
      do IO<Unit>:
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(Unit,Unit,invalidate)
        old : Footer.State <- Ref.dispose(Footer.State,state)
        oldFailure : Maybe<&2,Interactive.SubmissionFailure> <- Ref.dispose(Maybe<&2,Interactive.SubmissionFailure>,failure)
        return Unit{}

def editorTheme(theme: Theme.Theme) -> IO(Callback.Callback<String,String> & Editor.EditorTheme):
  do IO<Callback.Callback<String,String> & Editor.EditorTheme>:
    +paint : Callback.Callback<String,String> <- MarkdownTheme.color(theme,"accent")
    return (paint,Editor.EditorTheme{paint,Select.SelectListTheme{paint,paint,paint,paint,paint}})
def clear(redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,_: Unit) -> IO(Unit):
  Ref.write(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw,None{})

def processResult(result: Result<&2,&2,Terminal.Error,Process.Active>) -> Result<&2,&2,Error,Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{cause}: Fail{TerminalStart{cause}}
def processMounted(mounted: View.View & View.Handle & Tui.ResultOf(Tui.TuiBase),document: Component.Component,editorComponent: Component.Component,+foot: FooterOwner,stopped: Deferred.Deferred<Unit>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>) -> IO(View.View & Result<&2,&2,Error,Unit>):
  match mounted:
    case (view,_,Fail{cause}): IO.pure(View.View & Result<&2,&2,Error,Unit>,(view,Fail{Layout{cause}}))
    case (view,_,Done{base}):
      do IO<View.View & Result<&2,&2,Error,Unit>>:
        +ready : Callback.Callback<Process.QueryReady,Unit> <- Callback.create(~Interactive.Startup,~Process.QueryReady,~Unit,~Interactive.onReady,Interactive.Startup{redraw,queue,initial,footerFailure(foot)})
        +stopping : Callback.Callback<Unit,Unit> <- Callback.create(~Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,~Unit,~Unit,~clear,redraw)
        +ids : List<&2,Component.ComponentId> <- IO.pure(List<&2,Component.ComponentId>,Component.ComponentId{1n} <> Component.ComponentId{2n} <> Component.ComponentId{3n} <> Nil{})
        +components : List<&2,Component.Component> <- IO.pure(List<&2,Component.Component>,document <> editorComponent <> footerComponent(foot) <> Nil{})
        outcome : Result<&2,&2,Terminal.Error,Process.Active> <- Process.runProcessWithLifecycle(Process.active(Process.Session{base,Screen.initial()},components,ids),stopped,False{},ready,stopping)
        Callback.dispose(Process.QueryReady,Unit,ready)
        Callback.dispose(Unit,Unit,stopping)
        return (view,processResult(outcome))

def processEditorBorrowed(borrowed: View.View & Component.Component & View.Handle,+editorComponent: Component.Component,+foot: FooterOwner,stopped: Deferred.Deferred<Unit>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>) -> IO(View.View & Result<&2,&2,Error,Unit>):
  match borrowed:
    case (view,document,_):
      do IO<View.View & Result<&2,&2,Error,Unit>>:
        mounted : View.View & View.Handle & Tui.ResultOf(Tui.TuiBase) <- View.mount(view,editorComponent,footerComponent(foot))
        processMounted(mounted,document,editorComponent,foot,stopped,redraw,queue,initial)
def processEditor(view: View.View,editorComponent: Component.Component,foot: FooterOwner,stopped: Deferred.Deferred<Unit>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>) -> IO(View.View & Result<&2,&2,Error,Unit>):
  processEditorBorrowed(View.borrow(view),editorComponent,foot,stopped,redraw,queue,initial)
def process(view: View.View,editor: Component.Component,foot: FooterOwner,stopped: Deferred.Deferred<Unit>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>) -> IO(View.View & Result<&2,&2,Error,Unit>):
  processEditor(view,editor,foot,stopped,redraw,queue,initial)
def finish(outcome: View.View & Result<&2,&2,Error,Unit>,controller: Controller.Controller,transcript: Transcript.Owner,live: Live.Owner,foot: FooterOwner,submitted: Callback.Callback<String,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,stopped: Deferred.Deferred<Unit>) -> IO(Result<&2,&2,Error,Unit>):
  match outcome:
    case (view,result):
      do IO<Result<&2,&2,Error,Unit>>:
        Controller.stop(controller)
        Transcript.dispose(transcript)
        View.dispose(view)
        Live.dispose(live)
        disposeFooter(foot)
        Callback.dispose(String,Unit,submitted)
        Callback.dispose(String,String,paint)
        MarkdownTheme.dispose(styles)
        oldRows : Nat <- Ref.dispose(Nat,rows)
        oldRedraw : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw)
        Deferred.dispose(Unit,stopped)
        return result

def runLive(borrowed: Live.Owner & Component.Component & Live.Handle,view: View.View,+foot: FooterOwner,controller: Controller.Controller,queue: Controller.Handle,transcript: Transcript.Owner,submitted: Callback.Callback<String,Unit>,paint: Callback.Callback<String,String>,styles: MarkdownTheme.Styles,rows: Ref.Ref<Nat>,+redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,+stopped: Deferred.Deferred<Unit>,initial: List<&2,Controller.Submission>) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (live,component,_):
      do IO<Result<&2,&2,Error,Unit>>:
        outcome : View.View & Result<&2,&2,Error,Unit> <- process(view,component,foot,stopped,redraw,queue,initial)
        finish(outcome,controller,transcript,live,foot,submitted,paint,styles,rows,redraw,stopped)
def startPaint(pair: Callback.Callback<String,String> & Editor.EditorTheme,controller: Controller.Controller,queue: Controller.Handle,+submitted: Callback.Callback<String,Unit>,view: View.View,transcript: Transcript.Owner,styles: MarkdownTheme.Styles,initial: List<&2,Controller.Submission>,foot: FooterOwner,words: Words.Context,stopped: Deferred.Deferred<Unit>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Result<&2,&2,Error,Unit>):
  match pair:
    case (paint,uiTheme):
      do IO<Result<&2,&2,Error,Unit>>:
        editor : Editor.Editor <- Editor.new(uiTheme,None{})
        +configured : Editor.Editor <- IO.pure(Editor.Editor,Editor.setCallbacks(editor,Editor.EditorCallbacks{None{},Some{submitted},None{}}))
        +rows : Ref.Ref<Nat> <- Ref.new(Nat,24n)
        live : Live.Owner <- Live.create(Component.ComponentId{2n},configured,words,Keybindings.create(Keybindings.TUI_KEYBINDINGS(),Record.new(List<&2,Keys.KeyId>)),Keys.defaults(),rows)
        runLive(Live.borrow(live),view,foot,controller,queue,transcript,submitted,paint,styles,rows,redraw,stopped,initial)
def startController(pair: Controller.Controller & Controller.Handle,view: View.View,transcript: Transcript.Owner,styles: MarkdownTheme.Styles,initial: List<&2,Controller.Submission>,+foot: FooterOwner,theme: Theme.Theme,words: Words.Context,+stopped: Deferred.Deferred<Unit>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Result<&2,&2,Error,Unit>):
  match pair:
    case (controller,+queue):
      do IO<Result<&2,&2,Error,Unit>>:
        submitted : Callback.Callback<String,Unit> <- Callback.create(~Interactive.SubmissionInput,~String,~Unit,~Interactive.submitted,Interactive.SubmissionInput{queue,stopped,footerFailure(foot)})
        paintPair : Callback.Callback<String,String> & Editor.EditorTheme <- editorTheme(theme)
        startPaint(paintPair,controller,queue,submitted,view,transcript,styles,initial,foot,words,stopped,redraw)
def startTranscript(borrowed: Transcript.Owner & Transcript.Handle,view: View.View,styles: MarkdownTheme.Styles,+session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,+theme: Theme.Theme,words: Words.Context) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (transcript,+transcriptHandle):
      do IO<Result<&2,&2,Error,Unit>>:
        +existing : List<&2,Session.Message()> <- Session.messages(session)
        Transcript.seed(Unit,Runtime.Details(),Runtime.Custom(),transcriptHandle,existing)
        agentState : Session.AgentState() <- Session.state(session)
        +foot : FooterOwner <- footer(initialFooter(agentState,existing,cwd,home),theme)
        +redraw : Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Unit,Unit>>,None{})
        +stopped : Deferred.Deferred<Unit> <- Deferred.new(Unit)
        listener : Callback.Callback<Session.AgentSessionEvent,Unit> <- Callback.create(~Observation,~Session.AgentSessionEvent,~Unit,~observed,Observation{transcriptHandle,redraw,footerState(foot)})
        failureObserver : Callback.Callback<Controller.PromptFailure,Unit> <- Callback.create(~WorkerFailure,~Controller.PromptFailure,~Unit,~promptFailed,WorkerFailure{footerFailure(foot),redraw})
        controllerPair : Controller.Controller & Controller.Handle <- Controller.start(session,listener,32n,Some{failureObserver})
        startController(controllerPair,view,transcript,styles,initial,foot,theme,words,stopped,redraw)
def startStyles(styles: MarkdownTheme.Styles,view: View.View,viewHandle: View.Handle,session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,+theme: Theme.Theme,words: Words.Context) -> IO(Result<&2,&2,Error,Unit>):
  match styles:
    case MarkdownTheme.Styles{+markdown,callbacks}:
      do IO<Result<&2,&2,Error,Unit>>:
        transcript : Transcript.Owner <- Transcript.create(viewHandle,theme,markdown)
        startTranscript(Transcript.borrow(transcript),view,MarkdownTheme.Styles{markdown,callbacks},session,initial,cwd,home,theme,words)
def startView(borrowed: View.View & Component.Component & View.Handle,styles: MarkdownTheme.Styles,session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,theme: Theme.Theme,words: Words.Context) -> IO(Result<&2,&2,Error,Unit>):
  match borrowed:
    case (view,_,viewHandle):
      startStyles(styles,view,viewHandle,session,initial,cwd,home,theme,words)
def started(session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,+theme: Theme.Theme,words: Words.Context) -> IO(Result<&2,&2,Error,Unit>):
  do IO<Result<&2,&2,Error,Unit>>:
    styles : MarkdownTheme.Styles <- MarkdownTheme.create(theme)
    view : View.View <- View.create(Component.ComponentId{1n})
    startView(View.borrow(view),styles,session,initial,cwd,home,theme,words)
def themed(session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,words: Words.Context,loaded: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Result<&2,&2,Error,Unit>):
  match loaded:
    case Fail{cause}: IO.pure(Result<&2,&2,Error,Unit>,Fail{ThemeData{cause}})
    case Done{theme}: started(session,initial,cwd,home,theme,words)
def withWords(session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,agentDir: String,assetsRoot: String,loaded: Words.Loaded(Words.Context)) -> IO(Result<&2,&2,Error,Unit>):
  match loaded:
    case Fail{cause}: IO.pure(Result<&2,&2,Error,Unit>,Fail{WordData{cause}})
    case Done{words}:
      do IO<Result<&2,&2,Error,Unit>>:
        theme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadByName("dark",Path.join(assetsRoot,"packages/coding-agent/src/modes/interactive/theme"),Path.join(agentDir,"themes"),Color.TrueColor{})
        themed(session,initial,cwd,home,words,theme)
def run(session: Session.AgentSession,initial: List<&2,Controller.Submission>,cwd: String,home: Maybe<&2,String>,agentDir: String,+assetsRoot: String) -> IO(Result<&2,&2,Error,Unit>):
  do IO<Result<&2,&2,Error,Unit>>:
    words : Words.Loaded(Words.Context) <- Words.loadDefault(Path.join(assetsRoot,"packages/runtime/data"))
    withWords(session,initial,cwd,home,agentDir,assetsRoot,words)
