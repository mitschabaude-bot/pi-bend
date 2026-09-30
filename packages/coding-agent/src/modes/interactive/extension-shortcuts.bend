import Base
import ../../core/extensions/runner.bend as Runner
import ../../core/extensions/types.bend as T
import ../../core/extensions/context.bend as Ctx
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/ref.bend as R
import ../../../../runtime/src/record.bend as Record
import ../../../../tui/src/keys.bend as Keys
import ../../../../tui/src/keybindings.bend as Bindings
import ./transcript.bend as Transcript
import ./components/header.bend as Header
import ../../core/diagnostics.bend as Diagnostics
import ../../core/skills.bend as Skills

# Resolve on binding/reload; input only checks cached physical keys. Context
# actions read the live session through the runner's existing bindings.
type Shortcut is Data: Shortcut{key: Keys.KeyId,handler: T.ShortcutHandler(),context: Ctx.ExtensionContext}
type State is Data: State{active: Bool,shortcuts: List<&2,Shortcut>}
type Host is Data: Host{state: R.Ref<State>,input: C.Callback<String,Bool>,bindings: Bindings.KeybindingsManager,header: Maybe<&2,Header.Handle>}
type Owner is Type: Owner{host: Host}
type Input is Data: Input{state: R.Ref<State>,keyboard: Keys.Context,transcript: Transcript.Handle,redraw: R.Ref<Maybe<&2,C.Callback<Unit,Unit>>>}
type Task is Data: Task{shortcut: Shortcut,state: R.Ref<State>,transcript: Transcript.Handle,redraw: R.Ref<Maybe<&2,C.Callback<Unit,Unit>>>}
def compiledKey(key: Maybe<&2,Keys.KeyId>,shortcut: T.ExtensionShortcut,context: Ctx.ExtensionContext,rest: List<&2,Shortcut>) -> List<&2,Shortcut>:
  match key shortcut:
    case Some{key} T.ExtensionShortcut{_,_,_,handler}: Shortcut{key,handler,context} <> rest
    case None{} _: rest
def compile(values: List<&2,Record.Property<T.ExtensionShortcut>>,+context: Ctx.ExtensionContext) -> List<&2,Shortcut>:
  match values:
    case Nil{}: Nil{}
    case Record.Property{key,shortcut} <> rest: compiledKey(Keys.parseKeyId(key),shortcut,context,compile(rest,context))
def sourceIn(extensions: List<&2,T.Extension>,+path: String) -> Maybe<&2,Skills.SourceInfo>:
  match extensions:
    case Nil{}: None{}
    case T.Extension{_,+found,_,_,source,_,_,_,_,_,_} <> rest:
      Bool.pick(Unit -> Maybe<&2,Skills.SourceInfo>,String.eq(found,path),_ => Some{source},_ => sourceIn(rest,path))(Unit{})
def issueSource(extensions: List<&2,T.Extension>,path: Maybe<&2,String>) -> Maybe<&2,Skills.SourceInfo>:
  match path: case None{}: None{} case Some{path}: sourceIn(extensions,path)
def issues(diagnostics: List<&2,Diagnostics.ResourceDiagnostic>,+extensions: List<&2,T.Extension>) -> List<&2,Header.ExtensionIssue>:
  match diagnostics:
    case Nil{}: Nil{}
    case Diagnostics.ResourceDiagnostic{kind,message,+path,collision} <> rest:
      Header.ExtensionIssue{Diagnostics.ResourceDiagnostic{kind,message,path,collision},issueSource(extensions,path)} <> issues(rest,extensions)
def publish(header: Maybe<&2,Header.Handle>,issues: List<&2,Header.ExtensionIssue>) -> IO(Unit):
  match header:
    case None{}: IO.pure(Unit,Unit{})
    case Some{header}: Header.setExtensionIssues(header,issues)
def bind(host: Host,runner: Maybe<&2,Runner.ExtensionRunner>) -> IO(Unit):
  match host runner:
    case Host{state,_,_,header} None{}:
      do IO<Unit>:
        R.write(State,state,State{True{},Nil{}})
        publish(header,Nil{})
    case Host{state,_,bindings,header} Some{+runner}:
      do IO<Unit>:
        shortcuts : Record.Record<T.ExtensionShortcut> <- Runner.getShortcuts(runner,Bindings.getResolvedBindings(bindings))
        R.write(State,state,State{True{},compile(Record.entries(T.ExtensionShortcut,shortcuts),Runner.createContext(runner))})
        diagnostics : List<&2,Diagnostics.ResourceDiagnostic> <- Runner.getShortcutDiagnostics(runner)
        extensions : List<&2,T.Extension> <- Runner.extensions(runner)
        publish(header,issues(diagnostics,extensions))
def matchesShortcut(shortcut: Shortcut,keyboard: Keys.Context,data: String) -> Bool:
  match shortcut: case Shortcut{key,_,_}: Keys.matchesKey(keyboard,data,key)
def matching(values: List<&2,Shortcut>,+keyboard: Keys.Context,+data: String) -> Maybe<&2,Shortcut>:
  match values:
    case Nil{}: None{}
    case +shortcut <> rest:
      Bool.pick(Unit -> Maybe<&2,Shortcut>,matchesShortcut(shortcut,keyboard,data),_ => Some{shortcut},_ => matching(rest,keyboard,data))(Unit{})
def activeState(+state: State) -> State & Bool:
  match state: case State{active,_}: (state,active)
def redrawWith(callback: Maybe<&2,C.Callback<Unit,Unit>>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: C.call(Unit,Unit,callback,Unit{})
def outcomeShown(transcript: Transcript.Handle,result: Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit,Unit{})
    case Fail{message}: Transcript.showError(transcript,"Shortcut handler error: " ++ message)
def completedWhileActive(transcript: Transcript.Handle,redraw: R.Ref<Maybe<&2,C.Callback<Unit,Unit>>>,result: Result<&2,&2,String,Unit>,active: Maybe<&1,Bool>) -> IO(Unit):
  match active:
    case Some{True{}}:
      do IO<Unit>:
        outcomeShown(transcript,result)
        callback : Maybe<&2,C.Callback<Unit,Unit>> <- R.read(Maybe<&2,C.Callback<Unit,Unit>>,redraw)
        redrawWith(callback)
    case _: IO.pure(Unit,Unit{})
def completed(state: R.Ref<State>,transcript: Transcript.Handle,redraw: R.Ref<Maybe<&2,C.Callback<Unit,Unit>>>,result: Result<&2,&2,String,Unit>) -> IO(Unit):
  # A spawned handler may finish after the input's render; repaint its updates.
  do IO<Unit>:
    active : Maybe<&1,Bool> <- R.tryModify(State,Bool,state,value => activeState(value))
    completedWhileActive(transcript,redraw,result,active)
def run(task: Task) -> IO(Unit):
  match task:
    case Task{Shortcut{_,handler,context},state,transcript,redraw}:
      do IO<Unit>:
        result : Result<&2,&2,String,Unit> <- C.call(Ctx.ExtensionContext,Result<&2,&2,String,Unit>,handler,context)
        completed(state,transcript,redraw,result)
def dispatch(state: R.Ref<State>,transcript: Transcript.Handle,redraw: R.Ref<Maybe<&2,C.Callback<Unit,Unit>>>,shortcut: Maybe<&2,Shortcut>) -> IO(Bool):
  match shortcut:
    case None{}: IO.pure(Bool,False{})
    case Some{shortcut}:
      do IO<Bool>:
        IO.spawn(Unit,run(Task{shortcut,state,transcript,redraw}))
        return True{}
def fromState(state: State,keyboard: Keys.Context,data: String) -> Maybe<&2,Shortcut>:
  match state:
    case State{True{},values}: matching(values,keyboard,data)
    case _: None{}
def input(env: Input,data: String) -> IO(Bool):
  match env:
    case Input{+state,keyboard,transcript,redraw}:
      do IO<Bool>:
        current : State <- R.read(State,state)
        dispatch(state,transcript,redraw,fromState(current,keyboard,data))
def create(+bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,transcript: Transcript.Handle,redraw: R.Ref<Maybe<&2,C.Callback<Unit,Unit>>>,header: Maybe<&2,Header.Handle>) -> IO(Owner):
  do IO<Owner>:
    +state : R.Ref<State> <- R.new(State,State{True{},Nil{}})
    callback : C.Callback<String,Bool> <- C.create(~Input,~String,~Bool,~input,Input{state,keyboard,transcript,redraw})
    return Owner{Host{state,callback,bindings,header}}
def borrow(owner: Owner) -> Owner & Host:
  match owner: case Owner{+host}: (Owner{host},host)
def inputCallback(host: Host) -> C.Callback<String,Bool>:
  match host: case Host{_,input,_,_}: input
def clear(host: Host) -> IO(Unit):
  match host: case Host{state,_,_,_}: R.write(State,state,State{False{},Nil{}})
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Host{state,input,_,_}}:
      do IO<Unit>:
        C.dispose(String,Bool,input)
        old : State <- R.dispose(State,state)
        return Unit{}
