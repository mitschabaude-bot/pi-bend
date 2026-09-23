import Base
import ../../../../runtime/src/fifo.bend as Fifo
import ../../../../runtime/src/ref.bend as Ref
import ../../../../runtime/src/callback.bend as Callback
import ../../../../ai/src/types.bend as Ai
import ../../core/agent-session.bend as Session

# The editor only enqueues submissions. A separate worker may await prompt,
# so session events can request TUI work without re-entering the editor lock.
type Submission is Data:
  Submission{text: String,images: List<&2,Ai.ImageContent>,behavior: Maybe<&2,Session.StreamingBehavior>}
type SubmitError is Data: Closed{} Full{}
type PromptFailure is Data: PromptFailure{message: String}
type QueueState is Data:
  QueueState{pending: Fifo.Queue<Submission>,size: Nat,limit: Nat,closed: Bool,processing: Bool,lastError: Maybe<&2,PromptFailure>}
type Decision is Data: Rejected{error: SubmitError} Accepted{wake: Bool}
type Handle is Data: Handle{state: Ref.Ref<QueueState>,wake: Chan(Unit)}
type Controller is Type:
  Controller{handle: Handle,worker: Chan(Unit),prompt: Callback.Callback<Submission,Result<&2,&2,String,Unit>>,session: Maybe<&2,Session.AgentSession>,listener: Maybe<&2,Session.Listener()>}

def submitState(state: QueueState, +request: Submission) -> QueueState & Decision:
  match state:
    case QueueState{pending,size,limit,True{},processing,previousError}:
      (QueueState{pending,size,limit,True{},processing,previousError},Rejected{Closed{}})
    case QueueState{+pending,+size,+limit,False{},+processing,+previousError}:
      Bool.pick(Unit -> QueueState & Decision,Nat.is_ge(size,limit),
        _ => (QueueState{pending,size,limit,False{},processing,previousError},Rejected{Full{}}),
        _ => (QueueState{Fifo.enqueue(Submission,pending,request),Succ{size},limit,False{},processing,previousError},Accepted{Nat.is_eq(size,0n) && Bool.not(processing)}))(Unit{})
def sent(wake: Chan(Unit), decision: Decision) -> IO(Result<&2,&2,SubmitError,Unit>):
  match decision:
    case Rejected{error}: IO.pure(Result<&2,&2,SubmitError,Unit>,Fail{error})
    case Accepted{False{}}: IO.pure(Result<&2,&2,SubmitError,Unit>,Done{Unit{}})
    case Accepted{True{}}:
      do IO<Result<&2,&2,SubmitError,Unit>>:
        delivered : Bool <- Chan.send(Unit,wake,Unit{})
        return Bool.pick(Result<&2,&2,SubmitError,Unit>,delivered,Done{Unit{}},Fail{Closed{}})
def submit(handle: Handle,request: Submission) -> IO(Result<&2,&2,SubmitError,Unit>):
  match handle:
    case Handle{state,wake}:
      do IO<Result<&2,&2,SubmitError,Unit>>:
        decision : Decision <- Ref.modify(QueueState,Decision,state,current => submitState(current,request))
        sent(wake,decision)
def submitText(handle: Handle,text: String) -> IO(Result<&2,&2,SubmitError,Unit>):
  submit(handle,Submission{text,Nil{},None{}})

def dequeued(result: Fifo.Queue<Submission> & Maybe<&2,Submission>,size: Nat,limit: Nat,previousError: Maybe<&2,PromptFailure>) -> QueueState & Maybe<&2,Submission>:
  match result:
    case (next,None{}): (QueueState{next,0n,limit,False{},False{},previousError},None{})
    case (next,Some{request}): (QueueState{next,size - 1n,limit,False{},True{},previousError},Some{request})
def taken(state: QueueState) -> QueueState & Maybe<&2,Submission>:
  match state:
    case QueueState{pending,size,limit,True{},_,previousError}: (QueueState{pending,size,limit,True{},False{},previousError},None{})
    case QueueState{pending,size,limit,False{},_,previousError}:
      dequeued(Fifo.dequeue(Submission,pending),size,limit,previousError)
def failureOf(result: Result<&2,&2,String,Unit>) -> Maybe<&2,PromptFailure>:
  match result:
    case Done{_}: None{}
    case Fail{message}: Some{PromptFailure{message}}
def finished(state: QueueState,result: Result<&2,&2,String,Unit>) -> QueueState & Unit:
  match state:
    case QueueState{pending,size,limit,closed,_,_}: (QueueState{pending,size,limit,closed,False{},failureOf(result)},Unit{})
def take(handle: Handle) -> IO(Maybe<&2,Submission>):
  match handle: case Handle{state,_}: Ref.modify(QueueState,Maybe<&2,Submission>,state,taken)
def complete(handle: Handle,result: Result<&2,&2,String,Unit>) -> IO(Unit):
  match handle: case Handle{state,_}: Ref.modify(QueueState,Unit,state,current => finished(current,result))
def waitWake(handle: Handle) -> IO(Maybe<&1,Unit>):
  match handle: case Handle{_,wake}: Chan.recv(Unit,wake)
type Phase is Type:
  Check{}
  Taken{request: Maybe<&2,Submission>}
  Woken{signal: Maybe<&1,Unit>}
@unsafe def worker(+handle: Handle,+prompt: Callback.Callback<Submission,Result<&2,&2,String,Unit>>,phase: Phase) -> IO(Unit):
  match phase:
    case Check{}:
      do IO<Unit>:
        next : Maybe<&2,Submission> <- take(handle)
        worker(handle,prompt,Taken{next})
    case Taken{Some{request}}:
      do IO<Unit>:
        result : Result<&2,&2,String,Unit> <- Callback.call(Submission,Result<&2,&2,String,Unit>,prompt,request)
        complete(handle,result)
        worker(handle,prompt,Check{})
    case Taken{None{}}:
      do IO<Unit>:
        signal : Maybe<&1,Unit> <- waitWake(handle)
        worker(handle,prompt,Woken{signal})
    case Woken{None{}}: IO.pure(Unit,Unit{})
    case Woken{Some{_}}: worker(handle,prompt,Check{})
def started(+prompt: Callback.Callback<Submission,Result<&2,&2,String,Unit>>,session: Maybe<&2,Session.AgentSession>,listener: Maybe<&2,Session.Listener()>,limit: Nat) -> IO(Controller & Handle):
  do IO<Controller & Handle>:
    +state : Ref.Ref<QueueState> <- Ref.new(QueueState,QueueState{Fifo.new(Submission),0n,Nat.max(1n,limit),False{},False{},None{}})
    +wake : Chan(Unit) <- Chan.new(Unit,1)
    +handle : Handle <- IO.pure(Handle,Handle{state,wake})
    +task : Chan(Unit) <- IO.fork(Unit,worker(handle,prompt,Check{}))
    return (Controller{handle,task,prompt,session,listener},handle)
def callPrompt(session: Session.AgentSession,request: Submission) -> IO(Result<&2,&2,String,Unit>):
  match request:
    case Submission{text,images,behavior}: Session.prompt(session,text,images,behavior)
def start(+session: Session.AgentSession,+listener: Session.Listener(),limit: Nat) -> IO(Controller & Handle):
  do IO<Controller & Handle>:
    Session.subscribe(session,listener)
    +prompt : Callback.Callback<Submission,Result<&2,&2,String,Unit>> <- Callback.create(~Session.AgentSession,~Submission,~Result<&2,&2,String,Unit>,~callPrompt,session)
    started(prompt,Some{session},Some{listener},limit)
# Injectable prompt path for a lifecycle test and for embedders with a custom
# session driver. The controller owns this callback just as start owns its own.
def startWithPrompt(prompt: Callback.Callback<Submission,Result<&2,&2,String,Unit>>,limit: Nat) -> IO(Controller & Handle):
  started(prompt,None{},None{},limit)
def errorIn(current: QueueState) -> Maybe<&2,PromptFailure>:
  match current: case QueueState{_,_,_,_,_,error}: error
def lastError(handle: Handle) -> IO(Maybe<&2,PromptFailure>):
  match handle:
    case Handle{state,_}:
      do IO<Maybe<&2,PromptFailure>>:
        current : QueueState <- Ref.read(QueueState,state)
        return errorIn(current)
def closedState(state: QueueState) -> QueueState & Bool:
  match state:
    case QueueState{_,_,limit,_,+processing,previousError}:
      (QueueState{Fifo.new(Submission),0n,limit,True{},processing,previousError},processing)
def abortActive(session: Maybe<&2,Session.AgentSession>,active: Bool) -> IO(Unit):
  match session:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: Bool.pick(Unit -> IO(Unit),active,_ => Session.abort(value),_ => IO.pure(Unit,Unit{}))(Unit{})
def releaseListener(session: Maybe<&2,Session.AgentSession>,listener: Maybe<&2,Session.Listener()>) -> IO(Unit):
  match session listener:
    case Some{value} Some{+callback}:
      do IO<Unit>:
        Session.unsubscribe(value,callback)
        Callback.dispose(Session.AgentSessionEvent,Unit,callback)
    case _ _: IO.pure(Unit,Unit{})
def stop(owner: Controller) -> IO(Unit):
  match owner:
    case Controller{Handle{+state,wake},+task,prompt,+session,listener}:
      do IO<Unit>:
        active : Bool <- Ref.modify(QueueState,Bool,state,closedState)
        Chan.close(Unit,wake)
        abortActive(session,active)
        finishedTask : Maybe<&1,Unit> <- Chan.recv(Unit,task)
        Chan.close(Unit,task)
        releaseListener(session,listener)
        Callback.dispose(Submission,Result<&2,&2,String,Unit>,prompt)
        retired : QueueState <- Ref.dispose(QueueState,state)
        return Unit{}
