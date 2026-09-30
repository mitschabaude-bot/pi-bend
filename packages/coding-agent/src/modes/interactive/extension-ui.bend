import Base
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/ref.bend as Ref
import ../../../../tui/src/components/editor.bend as Editor
import ../../../../tui/src/components/select-list.bend as Select
import ../../../../tui/src/components/editor-component.bend as Live
import ../../../../tui/src/terminal.bend as Terminal
import ../../core/extensions/context.bend as Ctx
import ../../core/extensions/runner.bend as Runner
import ../../core/agent-session.bend as Session
import ./components/extension-dialog.bend as Dialog
import ./components/extension-selector.bend as Selector
import ./components/extension-input.bend as Input
import ./components/extension-editor.bend as Multi
import ./components/extension-widgets.bend as Widgets
import ./components/footer.bend as Footer
import ./theme/markdown-theme.bend as MarkdownTheme
import ./theme/theme.bend as Theme
import ./transcript.bend as Transcript
import ./interactive-mode.bend as Interactive
import ./extension-shortcuts.bend as Shortcuts

# Interactive extension callbacks share the live editor and prompt slot.
# The owner unbinds these callbacks before disposing them.
type Env is Data:
  Env{dialog: Dialog.Host,editor: Ref.Ref<Maybe<&2,Live.Handle>>,footer: Ref.Ref<Footer.State>,transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,terminal: Ref.Ref<Maybe<&2,Terminal.Handle>>,theme: Ref.Ref<Theme.Theme>,editorTheme: Editor.EditorTheme}
type BaseEnv is Data:
  BaseEnv{dialog: Dialog.Host,editor: Ref.Ref<Maybe<&2,Live.Handle>>,footer: Ref.Ref<Footer.State>,transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,terminal: Ref.Ref<Maybe<&2,Terminal.Handle>>,theme: Ref.Ref<Theme.Theme>,widgets: Widgets.Host,working: Ctx.WorkingControls,shortcuts: Shortcuts.Host}
type Rebinding is Data:
  Rebinding{previous: Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,ui: Ctx.ExtensionUIContext,runner: Ref.Ref<Maybe<&2,Runner.ExtensionRunner>>,widgets: Widgets.Host,shortcuts: Shortcuts.Host}
type Owner is Type:
  Owner{ui: Ctx.ExtensionUIContext,border: Callback.Callback<String,String>,accent: Callback.Callback<String,String>,muted: Callback.Callback<String,String>,runner: Ref.Ref<Maybe<&2,Runner.ExtensionRunner>>,widgets: Widgets.Host,previous: Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,shortcuts: Shortcuts.Host}

def select(env: Env,request: Ctx.SelectRequest) -> IO(Maybe<&2,String>):
  match env request:
    case Env{dialog,_,_,_,_,_,_,_} Ctx.SelectRequest{title,options,Ctx.DialogOptions{signal,timeout}}: Dialog.selectWith(dialog,Selector.create(title,options,None{}),signal,timeout)
def yes(value: Maybe<&2,String>) -> Bool:
  match value: case Some{"Yes"}: True{} case _: False{}
def confirm(env: Env,request: Ctx.ConfirmRequest) -> IO(Bool):
  match env request:
    case Env{dialog,_,_,_,_,_,_,_} Ctx.ConfirmRequest{title,message,Ctx.DialogOptions{signal,timeout}}:
      do IO<Bool>:
        answer : Maybe<&2,String> <- Dialog.selectWith(dialog,Selector.create(title ++ "\n" ++ message,["Yes","No"],None{}),signal,timeout)
        return yes(answer)
def input(env: Env,request: Ctx.InputRequest) -> IO(Maybe<&2,String>):
  match env request:
    case Env{dialog,_,_,_,_,_,_,_} Ctx.InputRequest{title,_,Ctx.DialogOptions{signal,timeout}}: Dialog.inputWith(dialog,Input.create(title,"",None{}),signal,timeout)
def displayNotice(transcript: Transcript.Handle,message: String,kind: Ctx.NotifyType) -> IO(Unit):
  match kind:
    case Ctx.InfoNotice{}: Transcript.status(transcript,message)
    case Ctx.WarningNotice{}: Transcript.showWarning(transcript,message)
    case Ctx.ErrorNotice{}: Transcript.showError(transcript,message)
def notice(env: Env,notification: Ctx.Notification) -> IO(Unit):
  match env notification:
    case Env{_,_,_,transcript,redraw,_,_,_} Ctx.Notification{message,kind}:
      do IO<Unit>:
        displayNotice(transcript,message,kind)
        Interactive.requestRender(redraw)
def without(statuses: List<&2,Footer.Status>,+key: String) -> List<&2,Footer.Status>:
  match statuses:
    case Nil{}: Nil{}
    case Footer.Status{+found,text} <> +rest:
      Bool.pick(Unit -> List<&2,Footer.Status>,String.eq(found,key),_ => without(rest,key),_ => Footer.Status{found,text} <> without(rest,key))(Unit{})
def updatedList(key: String,text: Maybe<&2,String>,rest: List<&2,Footer.Status>) -> List<&2,Footer.Status>:
  match text:
    case None{}: rest
    case Some{value}: Footer.Status{key,value} <> rest
def changedStatus(state: Footer.State,update: Ctx.StatusUpdate) -> Footer.State & Unit:
  match state update:
    case Footer.State{cwd,home,branch,name,model,thinking,totals,latest,percent,window,providers,subscription,auto,experimental,statuses} Ctx.StatusUpdate{+key,text}:
      +rest = without(statuses,key)
      (Footer.State{cwd,home,branch,name,model,thinking,totals,latest,percent,window,providers,subscription,auto,experimental,updatedList(key,text,rest)},Unit{})
def status(env: Env,update: Ctx.StatusUpdate) -> IO(Unit):
  match env:
    case Env{_,_,footer,_,redraw,_,_,_}:
      do IO<Unit>:
        Ref.modify(Footer.State,Unit,footer,state => changedStatus(state,update))
        Interactive.requestRender(redraw)
def unsupported(env: Env,feature: String) -> IO(Unit):
  match env:
    case Env{_,_,_,transcript,redraw,_,_,_}:
      do IO<Unit>:
        Transcript.showWarning(transcript,"Extension UI " ++ feature ++ " is not available yet")
        Interactive.requestRender(redraw)
def custom(env: Env,_: Ctx.CustomFactory()) -> IO(Unit): unsupported(env,"custom components")
def editRequest(env: Env,request: Ctx.EditorRequest) -> IO(Maybe<&2,String>):
  match env request:
    case Env{dialog,_,_,_,_,_,_,editorTheme} Ctx.EditorRequest{title,prefill}:
      do IO<Maybe<&2,String>>:
        state : Multi.State <- Multi.create(title,Maybe.default(&2,String,prefill,""),None{},editorTheme,None{})
        Dialog.editor(dialog,state)
def titled(result: Result<&2,&2,Terminal.Error,Unit>) -> IO(Unit): IO.pure(Unit,Unit{})
def setTitleWith(active: Maybe<&2,Terminal.Handle>,value: String) -> IO(Unit):
  match active:
    case None{}: IO.pure(Unit,Unit{})
    case Some{handle}:
      do IO<Unit>:
        result : Result<&2,&2,Terminal.Error,Unit> <- Terminal.setTitle(handle,value)
        titled(result)
def title(env: Env,value: String) -> IO(Unit):
  match env:
    case Env{_,_,_,_,_,terminal,_,_}:
      do IO<Unit>:
        active : Maybe<&2,Terminal.Handle> <- Ref.read(Maybe<&2,Terminal.Handle>,terminal)
        setTitleWith(active,value)
def applyEditor(found: Maybe<&2,Live.Handle>,operation: Live.Handle -> IO(Unit)) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit,Unit{})
    case Some{handle}: operation(handle)
def withEditor(env: Env,operation: Live.Handle -> IO(Unit)) -> IO(Unit):
  match env:
    case Env{_,editor,_,_,_,_,_,_}:
      do IO<Unit>:
        found : Maybe<&2,Live.Handle> <- Ref.read(Maybe<&2,Live.Handle>,editor)
        applyEditor(found,operation)
def setEditorText(env: Env,value: String) -> IO(Unit): withEditor(env,handle => Live.setText(handle,value))
def pasteToEditor(env: Env,value: String) -> IO(Unit): withEditor(env,handle => Live.insertTextAtCursor(handle,value))
def readEditor(found: Maybe<&2,Live.Handle>) -> IO(String):
  match found:
    case None{}: IO.pure(String,"")
    case Some{handle}: Live.expandedText(handle)
def editorText(env: Env,_: Unit) -> IO(String):
  match env:
    case Env{_,editor,_,_,_,_,_,_}:
      do IO<String>:
        found : Maybe<&2,Live.Handle> <- Ref.read(Maybe<&2,Live.Handle>,editor)
        readEditor(found)
def create(+base: BaseEnv) -> IO(Owner):
  match base:
    case BaseEnv{dialog,editor,footer,transcript,redraw,terminal,theme,+widgets,working,shortcuts}:
      do IO<Owner>:
        +border : Callback.Callback<String,String> <- MarkdownTheme.color(theme,"borderMuted")
        +accent : Callback.Callback<String,String> <- MarkdownTheme.color(theme,"accent")
        +muted : Callback.Callback<String,String> <- MarkdownTheme.color(theme,"muted")
        +bound : Env <- IO.pure(Env,Env{dialog,editor,footer,transcript,redraw,terminal,theme,Editor.EditorTheme{border,Select.SelectListTheme{accent,accent,muted,muted,muted}}})
        +select : Callback.Callback<Ctx.SelectRequest,Maybe<&2,String>> <- Callback.create(~Env,~Ctx.SelectRequest,~Maybe<&2,String>,~select,bound)
        +confirm : Callback.Callback<Ctx.ConfirmRequest,Bool> <- Callback.create(~Env,~Ctx.ConfirmRequest,~Bool,~confirm,bound)
        +input : Callback.Callback<Ctx.InputRequest,Maybe<&2,String>> <- Callback.create(~Env,~Ctx.InputRequest,~Maybe<&2,String>,~input,bound)
        +notify : Callback.Callback<Ctx.Notification,Unit> <- Callback.create(~Env,~Ctx.Notification,~Unit,~notice,bound)
        +status : Callback.Callback<Ctx.StatusUpdate,Unit> <- Callback.create(~Env,~Ctx.StatusUpdate,~Unit,~status,bound)
        +custom : Callback.Callback<Ctx.CustomFactory(),Unit> <- Callback.create(~Env,~Ctx.CustomFactory(),~Unit,~custom,bound)
        +editor : Callback.Callback<Ctx.EditorRequest,Maybe<&2,String>> <- Callback.create(~Env,~Ctx.EditorRequest,~Maybe<&2,String>,~editRequest,bound)
        +widget : Callback.Callback<Ctx.WidgetUpdate,Unit> <- Callback.create(~Widgets.Host,~Ctx.WidgetUpdate,~Unit,~Widgets.setWidget,widgets)
        +title : Callback.Callback<String,Unit> <- Callback.create(~Env,~String,~Unit,~title,bound)
        +setText : Callback.Callback<String,Unit> <- Callback.create(~Env,~String,~Unit,~setEditorText,bound)
        +paste : Callback.Callback<String,Unit> <- Callback.create(~Env,~String,~Unit,~pasteToEditor,bound)
        +getText : Callback.Callback<Unit,String> <- Callback.create(~Env,~Unit,~String,~editorText,bound)
        current : Ref.Ref<Maybe<&2,Runner.ExtensionRunner>> <- Ref.new(Maybe<&2,Runner.ExtensionRunner>,None{})
        return Owner{Ctx.ExtensionUIContext{select,confirm,input,notify,status,custom,editor,widget,title,setText,paste,getText,Some{working},Some{theme}},border,accent,muted,current,widgets,None{},shortcuts}
def bindRunner(ui: Ctx.ExtensionUIContext,runner: Maybe<&2,Runner.ExtensionRunner>) -> IO(Unit):
  match runner:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: Runner.setUIContext(value,Some{ui},Ctx.TuiMode{})
def unbind(runner: Maybe<&2,Runner.ExtensionRunner>) -> IO(Unit):
  match runner:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: Runner.setUIContext(value,None{},Ctx.PrintMode{})
def switchRunner(ui: Ctx.ExtensionUIContext,current: Ref.Ref<Maybe<&2,Runner.ExtensionRunner>>,+next: Maybe<&2,Runner.ExtensionRunner>) -> IO(Unit):
  do IO<Unit>:
    old : Maybe<&2,Runner.ExtensionRunner> <- Ref.swap(Maybe<&2,Runner.ExtensionRunner>,current,next)
    unbind(old)
    bindRunner(ui,next)
def callPrevious(previous: Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,session: Session.AgentSession) -> IO(Unit):
  match previous:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: Callback.call(Session.AgentSession,Unit,callback,session)
def sessionRebound(binding: Rebinding,+session: Session.AgentSession) -> IO(Unit):
  match binding:
    case Rebinding{previous,ui,current,widgets,shortcuts}:
      do IO<Unit>:
        callPrevious(previous,session)
        +next : Maybe<&2,Runner.ExtensionRunner> <- Session.extensionRunner(session)
        switchRunner(ui,current,next)
        Shortcuts.bind(shortcuts,next)
        Widgets.clear(widgets)
def rebound(binding: Rebinding,session: Session.AgentSession) -> IO(Unit):
  sessionRebound(binding,session)
def installHook(hook: Maybe<&2,Ref.Ref<Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>>>,ui: Ctx.ExtensionUIContext,current: Ref.Ref<Maybe<&2,Runner.ExtensionRunner>>,widgets: Widgets.Host,shortcuts: Shortcuts.Host) -> IO(Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>):
  match hook:
    case None{}: IO.pure(Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,None{})
    case Some{+reference}:
      do IO<Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>>:
        +previous : Maybe<&2,Callback.Callback<Session.AgentSession,Unit>> <- Ref.read(Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,reference)
        callback : Callback.Callback<Session.AgentSession,Unit> <- Callback.create(~Rebinding,~Session.AgentSession,~Unit,~rebound,Rebinding{previous,ui,current,widgets,shortcuts})
        Ref.write(Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>,reference,Some{callback})
        return previous
def bind(owner: Owner,+runner: Maybe<&2,Runner.ExtensionRunner>,hook: Maybe<&2,Ref.Ref<Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>>>) -> IO(Owner):
  match owner:
    case Owner{+ui,border,accent,muted,+current,+widgets,_,+shortcuts}:
      do IO<Owner>:
        switchRunner(ui,current,runner)
        Shortcuts.bind(shortcuts,runner)
        previous : Maybe<&2,Callback.Callback<Session.AgentSession,Unit>> <- installHook(hook,ui,current,widgets,shortcuts)
        return Owner{ui,border,accent,muted,current,widgets,previous,shortcuts}
def context(owner: Owner) -> Owner & Ctx.ExtensionUIContext:
  match owner:
    case Owner{+ui,border,accent,muted,current,widgets,previous,shortcuts}:
      (Owner{ui,border,accent,muted,current,widgets,previous,shortcuts},ui)
def disposePrevious(previous: Maybe<&2,Callback.Callback<Session.AgentSession,Unit>>) -> IO(Unit):
  match previous:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: Callback.dispose(Session.AgentSession,Unit,callback)
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Ctx.ExtensionUIContext{select,confirm,input,notify,status,custom,editor,widget,title,setText,paste,getText,_,_},border,accent,muted,runner,_,previous,shortcuts}:
      do IO<Unit>:
        Shortcuts.clear(shortcuts)
        current : Maybe<&2,Runner.ExtensionRunner> <- Ref.dispose(Maybe<&2,Runner.ExtensionRunner>,runner)
        unbind(current)
        disposePrevious(previous)
        Callback.dispose(Ctx.SelectRequest,Maybe<&2,String>,select)
        Callback.dispose(Ctx.ConfirmRequest,Bool,confirm)
        Callback.dispose(Ctx.InputRequest,Maybe<&2,String>,input)
        Callback.dispose(Ctx.Notification,Unit,notify)
        Callback.dispose(Ctx.StatusUpdate,Unit,status)
        Callback.dispose(Ctx.CustomFactory(),Unit,custom)
        Callback.dispose(Ctx.EditorRequest,Maybe<&2,String>,editor)
        Callback.dispose(Ctx.WidgetUpdate,Unit,widget)
        Callback.dispose(String,Unit,title)
        Callback.dispose(String,Unit,setText)
        Callback.dispose(String,Unit,paste)
        Callback.dispose(Unit,String,getText)
        Callback.dispose(String,String,border)
        Callback.dispose(String,String,accent)
        Callback.dispose(String,String,muted)
