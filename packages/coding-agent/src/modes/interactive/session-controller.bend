import Base
import ../../../../runtime/src/fifo.bend as Fifo
import ../../../../runtime/src/ref.bend as Ref
import ../../../../runtime/src/callback.bend as Callback
import ../../../../ai/src/types.bend as Ai
import ../../core/agent-session.bend as Session
import ./commands.bend as Commands

# The editor only enqueues submissions. A separate worker may await prompt,
# so session events can request TUI work without re-entering the editor lock.
type Submission is Data:
  Submission{text: String,images: List<&2,Ai.ImageContent>,behavior: Maybe<&2,Session.StreamingBehavior>}
type Control is Data:
  Interrupt{draft: String}
  Dequeue{draft: String}
type ControlResult is Data:
  ControlResult{text: String,count: Nat}
type Selection is Data: Navigate{id: String} Fork{id: String}
type SelectionResult is Data: Navigated{navigation: Session.Navigation} Forked{fork: Session.Fork} SelectionFailed{message: String}
type Job is Data:
  PromptJob{request: Submission}
  CommandJob{command: Commands.Command}
  ControlJob{control: Control}
  SelectJob{selection: Selection}
type SubmitError is Data: Closed{} Full{}
type PromptFailure is Data: PromptFailure{message: String}
type QueueState is Data:
  QueueState{pending: Fifo.Queue<Job>,size: Nat,limit: Nat,closed: Bool,processing: Bool,lastError: Maybe<&2,PromptFailure>}
type Decision is Data: Rejected{error: SubmitError} Accepted{wake: Bool}
type Handle is Data: Handle{state: Ref.Ref<QueueState>,wake: Chan(Unit)}
type PromptRun is Data: PromptRun{running: Ref.Ref<Bool>,task: Ref.Ref<Maybe<&2,Chan(Unit)>>}
type Controller is Type:
  Controller{handle: Handle,worker: Chan(Unit),run: PromptRun,prompt: Callback.Callback<Submission,Result<&2,&2,String,Unit>>,session: Maybe<&2,Session.AgentSession>,listener: Maybe<&2,Session.Listener()>,failure: Maybe<&2,Callback.Callback<PromptFailure,Unit>>,commandResult: Maybe<&2,Callback.Callback<Commands.Action,Unit>>,controlResult: Maybe<&2,Callback.Callback<ControlResult,Unit>>,selectionResult: Maybe<&2,Callback.Callback<SelectionResult,Unit>>}

def submitState(state: QueueState, +request: Job) -> QueueState & Decision:
  match state:
    case QueueState{pending,size,limit,True{},processing,previousError}:
      (QueueState{pending,size,limit,True{},processing,previousError},Rejected{Closed{}})
    case QueueState{+pending,+size,+limit,False{},+processing,+previousError}:
      Bool.pick(Unit -> QueueState & Decision,Nat.is_ge(size,limit),
        _ => (QueueState{pending,size,limit,False{},processing,previousError},Rejected{Full{}}),
        _ => (QueueState{Fifo.enqueue(Job,pending,request),Succ{size},limit,False{},processing,previousError},Accepted{Nat.is_eq(size,0n) && Bool.not(processing)}))(Unit{})
def sent(wake: Chan(Unit), decision: Decision) -> IO(Result<&2,&2,SubmitError,Unit>):
  match decision:
    case Rejected{error}: IO.pure(Result<&2,&2,SubmitError,Unit>,Fail{error})
    case Accepted{False{}}: IO.pure(Result<&2,&2,SubmitError,Unit>,Done{Unit{}})
    case Accepted{True{}}:
      do IO<Result<&2,&2,SubmitError,Unit>>:
        delivered : Bool <- Chan.send(Unit,wake,Unit{})
        return Bool.pick(Result<&2,&2,SubmitError,Unit>,delivered,Done{Unit{}},Fail{Closed{}})
def enqueue(handle: Handle,request: Job) -> IO(Result<&2,&2,SubmitError,Unit>):
  match handle:
    case Handle{state,wake}:
      do IO<Result<&2,&2,SubmitError,Unit>>:
        decision : Decision <- Ref.modify(QueueState,Decision,state,current => submitState(current,request))
        sent(wake,decision)
def submit(handle: Handle,request: Submission) -> IO(Result<&2,&2,SubmitError,Unit>):
  enqueue(handle,PromptJob{request})
def submitCommand(handle: Handle,command: Commands.Command) -> IO(Result<&2,&2,SubmitError,Unit>):
  enqueue(handle,CommandJob{command})
def submitControl(handle: Handle,control: Control) -> IO(Result<&2,&2,SubmitError,Unit>):
  enqueue(handle,ControlJob{control})
def submitSelection(handle: Handle,selection: Selection) -> IO(Result<&2,&2,SubmitError,Unit>):
  enqueue(handle,SelectJob{selection})
def submitText(handle: Handle,text: String) -> IO(Result<&2,&2,SubmitError,Unit>):
  submit(handle,Submission{text,Nil{},None{}})

def dequeued(result: Fifo.Queue<Job> & Maybe<&2,Job>,size: Nat,limit: Nat,previousError: Maybe<&2,PromptFailure>) -> QueueState & Maybe<&2,Job>:
  match result:
    case (next,None{}): (QueueState{next,0n,limit,False{},False{},previousError},None{})
    case (next,Some{request}): (QueueState{next,size - 1n,limit,False{},True{},previousError},Some{request})
def taken(state: QueueState) -> QueueState & Maybe<&2,Job>:
  match state:
    case QueueState{pending,size,limit,True{},_,previousError}: (QueueState{pending,size,limit,True{},False{},previousError},None{})
    case QueueState{pending,size,limit,False{},_,previousError}:
      dequeued(Fifo.dequeue(Job,pending),size,limit,previousError)
def failureOf(result: Result<&2,&2,String,Unit>) -> Maybe<&2,PromptFailure>:
  match result:
    case Done{_}: None{}
    case Fail{message}: Some{PromptFailure{message}}
def notifyFailure(observer: Maybe<&2,Callback.Callback<PromptFailure,Unit>>,failure: Maybe<&2,PromptFailure>) -> IO(Unit):
  match observer failure:
    case Some{callback} Some{value}: Callback.call(PromptFailure,Unit,callback,value)
    case _ _: IO.pure(Unit,Unit{})
def finished(state: QueueState,result: Result<&2,&2,String,Unit>) -> QueueState & Unit:
  match state:
    case QueueState{pending,size,limit,closed,_,_}: (QueueState{pending,size,limit,closed,False{},failureOf(result)},Unit{})
def take(handle: Handle) -> IO(Maybe<&2,Job>):
  match handle: case Handle{state,_}: Ref.modify(QueueState,Maybe<&2,Job>,state,taken)
def complete(handle: Handle,result: Result<&2,&2,String,Unit>) -> IO(Unit):
  match handle: case Handle{state,_}: Ref.modify(QueueState,Unit,state,current => finished(current,result))
def waitWake(handle: Handle) -> IO(Maybe<&1,Unit>):
  match handle: case Handle{_,wake}: Chan.recv(Unit,wake)
type Phase is Type:
  Check{}
  Taken{request: Maybe<&2,Job>}
  Woken{signal: Maybe<&1,Unit>}
def notifyCommand(observer: Maybe<&2,Callback.Callback<Commands.Action,Unit>>,action: Commands.Action) -> IO(Unit):
  match observer:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: Callback.call(Commands.Action,Unit,callback,action)
def joinedTask(current: Maybe<&2,Chan(Unit)>) -> IO(Unit):
  match current:
    case None{}: IO.pure(Unit,Unit{})
    case Some{+channel}:
      do IO<Unit>:
        finished : Maybe<&1,Unit> <- Chan.recv(Unit,channel)
        Chan.close(Unit,channel)
def joinTaskRef(task: Ref.Ref<Maybe<&2,Chan(Unit)>>) -> IO(Unit):
  do IO<Unit>:
    current : Maybe<&2,Chan(Unit)> <- Ref.swap(Maybe<&2,Chan(Unit)>,task,None{})
    joinedTask(current)
def joined(run: PromptRun) -> IO(Unit):
  match run: case PromptRun{_,task}: joinTaskRef(task)
def runPromptTask(+handle: Handle,+prompt: Callback.Callback<Submission,Result<&2,&2,String,Unit>>,observer: Maybe<&2,Callback.Callback<PromptFailure,Unit>>,running: Ref.Ref<Bool>,request: Submission) -> IO(Unit):
  do IO<Unit>:
    +result : Result<&2,&2,String,Unit> <- Callback.call(Submission,Result<&2,&2,String,Unit>,prompt,request)
    complete(handle,result)
    Ref.write(Bool,running,False{})
    notifyFailure(observer,failureOf(result))
def isRunning(run: PromptRun) -> IO(Bool):
  match run: case PromptRun{running,_}: Ref.read(Bool,running)
def launched(handle: Handle,prompt: Callback.Callback<Submission,Result<&2,&2,String,Unit>>,observer: Maybe<&2,Callback.Callback<PromptFailure,Unit>>,run: PromptRun,request: Submission) -> IO(Result<&2,&2,String,Unit>):
  match run:
    case PromptRun{+running,+task}:
      do IO<Result<&2,&2,String,Unit>>:
        joinTaskRef(task)
        Ref.write(Bool,running,True{})
        child : Chan(Unit) <- IO.fork(Unit,runPromptTask(handle,prompt,observer,running,request))
        Ref.write(Maybe<&2,Chan(Unit)>,task,Some{child})
        return Done{Unit{}}
def queuedWith(session: Session.AgentSession,text: String,images: List<&2,Ai.ImageContent>,behavior: Maybe<&2,Session.StreamingBehavior>) -> IO(Unit):
  match behavior:
    case Some{Session.FollowUp{}}: Session.followUp(session,text,images)
    case _: Session.steer(session,text,images)
def queuedPrompt(session: Session.AgentSession,request: Submission) -> IO(Result<&2,&2,String,Unit>):
  match request:
    case Submission{text,images,behavior}:
      do IO<Result<&2,&2,String,Unit>>:
        queuedWith(session,text,images,behavior)
        return Done{Unit{}}
def dispatchActive(handle: Handle,prompt: Callback.Callback<Submission,Result<&2,&2,String,Unit>>,session: Session.AgentSession,observer: Maybe<&2,Callback.Callback<PromptFailure,Unit>>,run: PromptRun,request: Submission,active: Bool) -> IO(Result<&2,&2,String,Unit>):
  match active:
    case True{}: queuedPrompt(session,request)
    case False{}: launched(handle,prompt,observer,run,request)
def dispatchPrompt(handle: Handle,prompt: Callback.Callback<Submission,Result<&2,&2,String,Unit>>,session: Maybe<&2,Session.AgentSession>,observer: Maybe<&2,Callback.Callback<PromptFailure,Unit>>,+run: PromptRun,request: Submission) -> IO(Result<&2,&2,String,Unit>):
  match session:
    case None{}:
      do IO<Result<&2,&2,String,Unit>>:
        +result : Result<&2,&2,String,Unit> <- Callback.call(Submission,Result<&2,&2,String,Unit>,prompt,request)
        notifyFailure(observer,failureOf(result))
        return result
    case Some{+value}:
      do IO<Result<&2,&2,String,Unit>>:
        active : Bool <- isRunning(run)
        dispatchActive(handle,prompt,value,observer,run,request,active)
def performCommand(session: Maybe<&2,Session.AgentSession>,observer: Maybe<&2,Callback.Callback<Commands.Action,Unit>>,command: Commands.Command) -> IO(Result<&2,&2,String,Unit>):
  match session:
    case None{}: IO.pure(Result<&2,&2,String,Unit>,Fail{"Command requires an active session"})
    case Some{value}:
      do IO<Result<&2,&2,String,Unit>>:
        action : Commands.Action <- Commands.execute(value,command)
        notifyCommand(observer,action)
        return Done{Unit{}}
def joinedTexts(queued: Session.QueuedMessages) -> List<&2,String>:
  match queued:
    case Session.QueuedMessages{steering,followUp}: List.append(&2,String,steering,followUp)
def restoredText(queued: List<&2,String>,+draft: String) -> String:
  String.join(List.append(&2,String,queued,Bool.pick(List<&2,String>,String.is_empty(draft),Nil{},draft <> Nil{})),"\n\n")
def notifyControl(observer: Maybe<&2,Callback.Callback<ControlResult,Unit>>,result: ControlResult) -> IO(Unit):
  match observer:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: Callback.call(ControlResult,Unit,callback,result)
def clearControl(+session: Session.AgentSession,observer: Maybe<&2,Callback.Callback<ControlResult,Unit>>,draft: String,abort: Bool) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    queuedMessages : Session.QueuedMessages <- Session.clearQueue(session)
    +texts : List<&2,String> <- IO.pure(List<&2,String>,joinedTexts(queuedMessages))
    notifyControl(observer,ControlResult{restoredText(texts,draft),List.length(&2,String,texts)})
    Bool.pick(Unit -> IO(Unit),abort,_ => Session.abort(session),_ => IO.pure(Unit,Unit{}))(Unit{})
    return Done{Unit{}}
def interruptControl(session: Session.AgentSession,observer: Maybe<&2,Callback.Callback<ControlResult,Unit>>,run: PromptRun,draft: String) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    active : Bool <- isRunning(run)
    Bool.pick(Unit -> IO(Result<&2,&2,String,Unit>),active,_ => clearControl(session,observer,draft,True{}),_ => IO.pure(Result<&2,&2,String,Unit>,Done{Unit{}}))(Unit{})
def performControl(session: Maybe<&2,Session.AgentSession>,observer: Maybe<&2,Callback.Callback<ControlResult,Unit>>,run: PromptRun,control: Control) -> IO(Result<&2,&2,String,Unit>):
  match session control:
    case None{} _: IO.pure(Result<&2,&2,String,Unit>,Fail{"Control requires an active session"})
    case Some{value} Interrupt{draft}: interruptControl(value,observer,run,draft)
    case Some{value} Dequeue{draft}: clearControl(value,observer,draft,False{})
def notifySelection(observer: Maybe<&2,Callback.Callback<SelectionResult,Unit>>,result: SelectionResult) -> IO(Unit):
  match observer:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: Callback.call(SelectionResult,Unit,callback,result)
def navigationResult(result: Result<&2,&2,String,Session.Navigation>) -> SelectionResult:
  match result:
    case Done{value}: Navigated{value}
    case Fail{message}: SelectionFailed{message}
def forkResult(result: Result<&2,&2,String,Session.Fork>) -> SelectionResult:
  match result:
    case Done{value}: Forked{value}
    case Fail{message}: SelectionFailed{message}
def performSelection(session: Maybe<&2,Session.AgentSession>,observer: Maybe<&2,Callback.Callback<SelectionResult,Unit>>,selection: Selection) -> IO(Result<&2,&2,String,Unit>):
  match session selection:
    case None{} _: IO.pure(Result<&2,&2,String,Unit>,Fail{"Selection requires an active session"})
    case Some{value} Navigate{id}:
      do IO<Result<&2,&2,String,Unit>>:
        outcome : Result<&2,&2,String,Session.Navigation> <- Session.navigateTree(value,id)
        notifySelection(observer,navigationResult(outcome))
        return Done{Unit{}}
    case Some{value} Fork{id}:
      do IO<Result<&2,&2,String,Unit>>:
        outcome : Result<&2,&2,String,Session.Fork> <- Session.forkAt(value,id)
        notifySelection(observer,forkResult(outcome))
        return Done{Unit{}}
def perform(handle: Handle,+prompt: Callback.Callback<Submission,Result<&2,&2,String,Unit>>,session: Maybe<&2,Session.AgentSession>,observer: Maybe<&2,Callback.Callback<PromptFailure,Unit>>,commandResult: Maybe<&2,Callback.Callback<Commands.Action,Unit>>,controlResult: Maybe<&2,Callback.Callback<ControlResult,Unit>>,selectionResult: Maybe<&2,Callback.Callback<SelectionResult,Unit>>,run: PromptRun,job: Job) -> IO(Result<&2,&2,String,Unit>):
  match job:
    case PromptJob{request}: dispatchPrompt(handle,prompt,session,observer,run,request)
    case CommandJob{command}: performCommand(session,commandResult,command)
    case ControlJob{control}: performControl(session,controlResult,run,control)
    case SelectJob{selection}: performSelection(session,selectionResult,selection)
@unsafe def worker(+handle: Handle,+prompt: Callback.Callback<Submission,Result<&2,&2,String,Unit>>,+session: Maybe<&2,Session.AgentSession>,+observer: Maybe<&2,Callback.Callback<PromptFailure,Unit>>,+commandResult: Maybe<&2,Callback.Callback<Commands.Action,Unit>>,+controlResult: Maybe<&2,Callback.Callback<ControlResult,Unit>>,+selectionResult: Maybe<&2,Callback.Callback<SelectionResult,Unit>>,+run: PromptRun,phase: Phase) -> IO(Unit):
  match phase:
    case Check{}:
      do IO<Unit>:
        next : Maybe<&2,Job> <- take(handle)
        worker(handle,prompt,session,observer,commandResult,controlResult,selectionResult,run,Taken{next})
    case Taken{Some{request}}:
      do IO<Unit>:
        result : Result<&2,&2,String,Unit> <- perform(handle,prompt,session,observer,commandResult,controlResult,selectionResult,run,request)
        complete(handle,result)
        worker(handle,prompt,session,observer,commandResult,controlResult,selectionResult,run,Check{})
    case Taken{None{}}:
      do IO<Unit>:
        signal : Maybe<&1,Unit> <- waitWake(handle)
        worker(handle,prompt,session,observer,commandResult,controlResult,selectionResult,run,Woken{signal})
    case Woken{None{}}: IO.pure(Unit,Unit{})
    case Woken{Some{_}}: worker(handle,prompt,session,observer,commandResult,controlResult,selectionResult,run,Check{})
def started(+prompt: Callback.Callback<Submission,Result<&2,&2,String,Unit>>,+session: Maybe<&2,Session.AgentSession>,listener: Maybe<&2,Session.Listener()>,limit: Nat,+failure: Maybe<&2,Callback.Callback<PromptFailure,Unit>>,+commandResult: Maybe<&2,Callback.Callback<Commands.Action,Unit>>,+controlResult: Maybe<&2,Callback.Callback<ControlResult,Unit>>,+selectionResult: Maybe<&2,Callback.Callback<SelectionResult,Unit>>) -> IO(Controller & Handle):
  do IO<Controller & Handle>:
    +state : Ref.Ref<QueueState> <- Ref.new(QueueState,QueueState{Fifo.new(Job),0n,Nat.max(1n,limit),False{},False{},None{}})
    +wake : Chan(Unit) <- Chan.new(Unit,1)
    +handle : Handle <- IO.pure(Handle,Handle{state,wake})
    +running : Ref.Ref<Bool> <- Ref.new(Bool,False{})
    +promptTask : Ref.Ref<Maybe<&2,Chan(Unit)>> <- Ref.new(Maybe<&2,Chan(Unit)>,None{})
    +run : PromptRun <- IO.pure(PromptRun,PromptRun{running,promptTask})
    +task : Chan(Unit) <- IO.fork(Unit,worker(handle,prompt,session,failure,commandResult,controlResult,selectionResult,run,Check{}))
    return (Controller{handle,task,run,prompt,session,listener,failure,commandResult,controlResult,selectionResult},handle)
def callPrompt(session: Session.AgentSession,request: Submission) -> IO(Result<&2,&2,String,Unit>):
  match request:
    case Submission{text,images,behavior}: Session.prompt(session,text,images,behavior)
def start(+session: Session.AgentSession,+listener: Session.Listener(),limit: Nat,failure: Maybe<&2,Callback.Callback<PromptFailure,Unit>>,commandResult: Maybe<&2,Callback.Callback<Commands.Action,Unit>>,controlResult: Maybe<&2,Callback.Callback<ControlResult,Unit>>,selectionResult: Maybe<&2,Callback.Callback<SelectionResult,Unit>>) -> IO(Controller & Handle):
  do IO<Controller & Handle>:
    Session.subscribe(session,listener)
    +prompt : Callback.Callback<Submission,Result<&2,&2,String,Unit>> <- Callback.create(~Session.AgentSession,~Submission,~Result<&2,&2,String,Unit>,~callPrompt,session)
    started(prompt,Some{session},Some{listener},limit,failure,commandResult,controlResult,selectionResult)
# Injectable prompt path for a lifecycle test and for embedders with a custom
# session driver. The controller owns this callback just as start owns its own.
def startWithPrompt(prompt: Callback.Callback<Submission,Result<&2,&2,String,Unit>>,limit: Nat,failure: Maybe<&2,Callback.Callback<PromptFailure,Unit>>) -> IO(Controller & Handle):
  started(prompt,None{},None{},limit,failure,None{},None{},None{})
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
      (QueueState{Fifo.new(Job),0n,limit,True{},processing,previousError},processing)
def releaseListener(session: Maybe<&2,Session.AgentSession>,listener: Maybe<&2,Session.Listener()>) -> IO(Unit):
  match session listener:
    case Some{value} Some{+callback}:
      do IO<Unit>:
        Session.unsubscribe(value,callback)
        Callback.dispose(Session.AgentSessionEvent,Unit,callback)
    case _ _: IO.pure(Unit,Unit{})
def disposeFailure(failure: Maybe<&2,Callback.Callback<PromptFailure,Unit>>) -> IO(Unit):
  match failure:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: Callback.dispose(PromptFailure,Unit,callback)
def disposeCommandResult(observer: Maybe<&2,Callback.Callback<Commands.Action,Unit>>) -> IO(Unit):
  match observer:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: Callback.dispose(Commands.Action,Unit,callback)
def disposeControlResult(observer: Maybe<&2,Callback.Callback<ControlResult,Unit>>) -> IO(Unit):
  match observer:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: Callback.dispose(ControlResult,Unit,callback)
def disposeSelectionResult(observer: Maybe<&2,Callback.Callback<SelectionResult,Unit>>) -> IO(Unit):
  match observer:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: Callback.dispose(SelectionResult,Unit,callback)
def abortSession(session: Maybe<&2,Session.AgentSession>,active: Bool) -> IO(Unit):
  match session:
    case Some{value}: Bool.pick(Unit -> IO(Unit),active,_ => Session.abort(value),_ => IO.pure(Unit,Unit{}))(Unit{})
    case None{}: IO.pure(Unit,Unit{})
def disposeRun(run: PromptRun) -> IO(Unit):
  match run:
    case PromptRun{running,promptTask}:
      do IO<Unit>:
        wasRunning : Bool <- Ref.dispose(Bool,running)
        retiredTask : Maybe<&2,Chan(Unit)> <- Ref.dispose(Maybe<&2,Chan(Unit)>,promptTask)
        return Unit{}
def stop(owner: Controller) -> IO(Unit):
  match owner:
    case Controller{Handle{+state,wake},+task,+run,prompt,+session,listener,failure,commandResult,controlResult,selectionResult}:
      do IO<Unit>:
        active : Bool <- Ref.modify(QueueState,Bool,state,closedState)
        Chan.close(Unit,wake)
        promptActive : Bool <- isRunning(run)
        abortSession(session,active || promptActive)
        finishedTask : Maybe<&1,Unit> <- Chan.recv(Unit,task)
        Chan.close(Unit,task)
        joined(run)
        disposeRun(run)
        releaseListener(session,listener)
        Callback.dispose(Submission,Result<&2,&2,String,Unit>,prompt)
        disposeFailure(failure)
        disposeCommandResult(commandResult)
        disposeControlResult(controlResult)
        disposeSelectionResult(selectionResult)
        retired : QueueState <- Ref.dispose(QueueState,state)
        return Unit{}
