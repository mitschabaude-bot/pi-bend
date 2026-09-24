import Base
import ../../../../agent/src/types.bend as Agent
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/deferred.bend as Deferred
import ../../../../runtime/src/ref.bend as Ref
import ../../../../runtime/src/text.bend as Text
import ../../../../tui/src/tui-process.bend as Process
import ../../core/agent-runtime.bend as Runtime
import ../../core/agent-session.bend as Session
import ../../core/model-runtime.bend as Models
import ./components/model-selector.bend as ModelPicker
import ./session-controller.bend as Controller
import ./commands.bend as Commands
import ./transcript.bend as Transcript

# Model work runs in SessionController's worker. These callbacks only publish
# immutable event snapshots and ask the TUI process for another frame.
type Events is Data:
  Events{transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
type SubmissionFailure is Data:
  QueueFailure{cause: Controller.SubmitError}
  PromptFailure{message: String}
  CommandFailure{message: String}
  CommandNotice{message: String}
type SubmissionInput is Data:
  SubmissionInput{queue: Controller.Handle,stop: Deferred.Deferred<Unit>,failure: Ref.Ref<Maybe<&2,SubmissionFailure>>}
type CommandSink is Data:
  CommandSink{failure: Ref.Ref<Maybe<&2,SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,picker: Ref.Ref<Maybe<&2,ModelPicker.Host>>,session: Ref.Ref<Session.AgentSession>,models: Ref.Ref<List<&2,Models.Model()>>}
type Startup is Data:
  Startup{redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>,failure: Ref.Ref<Maybe<&2,SubmissionFailure>>}

def failureText(failure: SubmissionFailure) -> String:
  match failure:
    case QueueFailure{Controller.Full{}}: "Submission queue is full"
    case QueueFailure{Controller.Closed{}}: "Session is closed"
    case PromptFailure{message}: message
    case CommandFailure{message}: message
    case CommandNotice{message}: message
def submittedResult(failure: Ref.Ref<Maybe<&2,SubmissionFailure>>,result: Result<&2,&2,Controller.SubmitError,Unit>) -> IO(Unit):
  match result:
    case Done{_}: Ref.write(Maybe<&2,SubmissionFailure>,failure,None{})
    case Fail{cause}: Ref.write(Maybe<&2,SubmissionFailure>,failure,Some{QueueFailure{cause}})

def renderRequested(callback: Maybe<&2,Callback.Callback<Unit,Unit>>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: Callback.call(Unit,Unit,value,Unit{})
def requestRender(redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>) -> IO(Unit):
  do IO<Unit>:
    callback : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.read(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw)
    renderRequested(callback)
def observed(events: Events,event: Session.SessionEvent()) -> IO(Unit):
  match events:
    case Events{transcript,redraw}:
      do IO<Unit>:
        changed : Bool <- Transcript.accept(Unit,Runtime.Custom(),transcript,event)
        Bool.pick(Unit -> IO(Unit),changed,_ => requestRender(redraw),_ => IO.pure(Unit,Unit{}))(Unit{})
def onSessionEvent(events: Events,event: Session.AgentSessionEvent) -> IO(Unit):
  match event:
    case Session.AgentEvent{value}: observed(events,value)
    case _: IO.pure(Unit,Unit{})
def commandStatus(failure: Ref.Ref<Maybe<&2,SubmissionFailure>>,status: SubmissionFailure) -> IO(Unit):
  Ref.write(Maybe<&2,SubmissionFailure>,failure,Some{status})
def pickerCurrent(session: Session.AgentSession) -> IO(Maybe<&2,Models.Model()>):
  do IO<Maybe<&2,Models.Model()>>:
    current : Session.AgentState() <- Session.state(session)
    return Session.stateModel(current)
def openPicker(host: Maybe<&2,ModelPicker.Host>,models: List<&2,Models.Model()>,current: Maybe<&2,Models.Model()>,query: Maybe<&2,String>) -> IO(Unit):
  match host:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: ModelPicker.open(value,ModelPicker.create(models,current,Maybe.default(&2,String,query,""),24n))
def openPickerResult(failure: Ref.Ref<Maybe<&2,SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,picker: Ref.Ref<Maybe<&2,ModelPicker.Host>>,session: Session.AgentSession,models: List<&2,Models.Model()>,search: Maybe<&2,String>) -> IO(Bool):
  match models:
    case Nil{}:
      do IO<Bool>:
        commandStatus(failure,CommandFailure{"No models available. Use /login to add a provider."})
        requestRender(redraw)
        return False{}
    case model <> rest:
      do IO<Bool>:
        +current : Maybe<&2,Models.Model()> <- pickerCurrent(session)
        target : Maybe<&2,ModelPicker.Host> <- Ref.read(Maybe<&2,ModelPicker.Host>,picker)
        openPicker(target,model <> rest,current,search)
        requestRender(redraw)
        return False{}
def commandResult(+sink: CommandSink,result: Commands.Action) -> IO(Bool):
  match sink result:
    case CommandSink{failure,redraw,_,_,_} Commands.Notice{message}:
      do IO<Bool>:
        commandStatus(failure,CommandNotice{message})
        requestRender(redraw)
        return False{}
    case CommandSink{failure,redraw,_,_,_} Commands.CommandError{message}:
      do IO<Bool>:
        commandStatus(failure,CommandFailure{message})
        requestRender(redraw)
        return False{}
    case CommandSink{failure,redraw,_,_,_} Commands.ModelSelected{model}:
      do IO<Bool>:
        commandStatus(failure,CommandNotice{"Model: " ++ Models.reference(model)})
        requestRender(redraw)
        return True{}
    case CommandSink{failure,redraw,picker,session,models} Commands.OpenModelPicker{search}:
      do IO<Bool>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        available : List<&2,Models.Model()> <- Ref.read(List<&2,Models.Model()>,models)
        openPickerResult(failure,redraw,picker,live,available,search)
    case _ _: IO.pure(Bool,False{})
def act(queue: Controller.Handle,stop: Deferred.Deferred<Unit>,failure: Ref.Ref<Maybe<&2,SubmissionFailure>>,command: Commands.Command) -> IO(Unit):
  match command:
    case Commands.Stop{}:
      do IO<Unit>:
        settled : Bool <- Deferred.resolve(Unit,stop,Unit{})
        return Unit{}
    case Commands.Send{message}:
      do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submitText(queue,message)
        submittedResult(failure,result)
    case other:
      do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submitCommand(queue,other)
        submittedResult(failure,result)
def submitOwned(input: SubmissionInput,+text: String) -> IO(Unit):
  match input:
    case SubmissionInput{queue,stop,failure}:
      Bool.pick(Unit -> IO(Unit),String.is_empty(Text.trim(text)),_ => IO.pure(Unit,Unit{}),_ => do IO<Unit>:
        act(queue,stop,failure,Commands.parse(text)))(Unit{})
def submitted(input: SubmissionInput,text: String) -> IO(Unit): submitOwned(input,text)
def queueInitial(+queue: Controller.Handle,+failure: Ref.Ref<Maybe<&2,SubmissionFailure>>,initial: List<&2,Controller.Submission>) -> IO(Unit):
  match initial:
    case Nil{}: IO.pure(Unit,Unit{})
    case item <> rest:
      do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submit(queue,item)
        submittedResult(failure,result)
        queueInitial(queue,failure,rest)
def onReady(startup: Startup,ready: Process.QueryReady) -> IO(Unit):
  match startup ready:
    case Startup{redraw,queue,initial,failure} Process.QueryReady{_,_,_,request}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw,Some{request})
        queueInitial(queue,failure,initial)
