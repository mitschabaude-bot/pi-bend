import Base
import ../../../../agent/src/types.bend as Agent
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/deferred.bend as Deferred
import ../../../../runtime/src/ref.bend as Ref
import ../../../../runtime/src/text.bend as Text
import ../../../../tui/src/tui-process.bend as Process
import ../../core/agent-runtime.bend as Runtime
import ../../core/agent-session.bend as Session
import ./session-controller.bend as Controller
import ./transcript.bend as Transcript

# Model work runs in SessionController's worker. These callbacks only publish
# immutable event snapshots and ask the TUI process for another frame.
type Events is Data:
  Events{transcript: Transcript.Handle,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
type SubmissionFailure is Data:
  QueueFailure{cause: Controller.SubmitError}
  PromptFailure{message: String}
type SubmissionInput is Data:
  SubmissionInput{queue: Controller.Handle,stop: Deferred.Deferred<Unit>,failure: Ref.Ref<Maybe<&2,SubmissionFailure>>}
type Startup is Data:
  Startup{redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>,queue: Controller.Handle,initial: List<&2,Controller.Submission>,failure: Ref.Ref<Maybe<&2,SubmissionFailure>>}

def failureText(failure: SubmissionFailure) -> String:
  match failure:
    case QueueFailure{Controller.Full{}}: "Submission queue is full"
    case QueueFailure{Controller.Closed{}}: "Session is closed"
    case PromptFailure{message}: message
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
        changed : Bool <- Transcript.accept(Unit,Runtime.Details(),Runtime.Custom(),transcript,event)
        Bool.pick(Unit -> IO(Unit),changed,_ => requestRender(redraw),_ => IO.pure(Unit,Unit{}))(Unit{})
def onSessionEvent(events: Events,event: Session.AgentSessionEvent) -> IO(Unit):
  match event:
    case Session.AgentEvent{value}: observed(events,value)
    case _: IO.pure(Unit,Unit{})
def submitted(input: SubmissionInput,text: String) -> IO(Unit):
  match input:
    case SubmissionInput{queue,stop,failure}:
      +clean = Text.trim(text)
      Bool.pick(Unit -> IO(Unit),String.eq(clean,"/exit"),_ => do IO<Unit>:
        settled : Bool <- Deferred.resolve(Unit,stop,Unit{})
        return Unit{},_ => Bool.pick(Unit -> IO(Unit),String.is_empty(clean),_ => IO.pure(Unit,Unit{}),_ => do IO<Unit>:
        result : Result<&2,&2,Controller.SubmitError,Unit> <- Controller.submitText(queue,clean)
        submittedResult(failure,result))(Unit{}))(Unit{})
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
