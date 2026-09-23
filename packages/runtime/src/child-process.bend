import Base
import ./callback.bend as Callback
import ./abort.bend as Abort
import ./deferred.bend as Deferred
import ./utf8.bend as Utf8
import ./filesystem.bend as FS
import ./string.bend as Strings

# The process owner stays unreaped until the caller has retired its timeout
# and abort observers. Pipe readers and idle timers finish before this returns.
type Error is Data:
  Error{operation: String, code: U32, message: String}

type Report is Data:
  Report{status: Maybe<&2,ProcessStatus>, errors: List<&2,Error>}

# Stdout always reaches the output consumer. Stderr joins it, is drained
# unread, or reaches a separate consumer.
type OutputSelection is Data:
  Merged{}
  Stdout{}
  Separate{onError: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>}

type Route is Data:
  Primary{}
  Secondary{}
  Dropped{}

type ProcessEvent is Data:
  Output{route: Route, bytes: List<&2,U32>}
  PipeEnded{errors: List<&2,Error>}
  Exited{status: Maybe<&2,ProcessStatus>, errors: List<&2,Error>}
  TimerEnded{generation: Nat, elapsed: Bool}

type State is Data:
  State{pipes: U32, exited: Bool, status: Maybe<&2,ProcessStatus>, errors: List<&2,Error>, stopping: Bool, generation: Nat, timer: Maybe<&2,TimerCancel>, timers: Nat}

type Context is Data:
  Context{events: Chan(ProcessEvent), process: ProcessControl, stdout: PipeCancel, stderr: PipeCancel, onData: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>, onError: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>}

# libuv's names for the errors a spawn reports, as Node's messages show them.
def errnoName(code: U32) -> String:
  match code:
    case 1: "EPERM"
    case 2: "ENOENT"
    case 7: "E2BIG"
    case 8: "ENOEXEC"
    case 12: "ENOMEM"
    case 13: "EACCES"
    case 20: "ENOTDIR"
    case 36: "ENAMETOOLONG"
    case 40: "ELOOP"
    case code: "Unknown system error -" ++ U32.show(code)

def errors(operation: String, result: Result<&1,&1,U32 & String,Unit>) -> List<&2,Error>:
  match result:
    case Done{_}: Nil{}
    case Fail{(code,message)}: Error{operation,code,message} <> Nil{}

def closePipe(events: Chan(ProcessEvent), pipe: Pipe, failed: List<&2,Error>) -> IO(Unit):
  do IO<Unit>:
    closed : Result<&1,&1,U32 & String,Unit> <- Pipe.close_checked(pipe)
    sent : Bool <- Chan.send(ProcessEvent,events,PipeEnded{List.append(&2,Error,failed,errors("pipe close",closed))})
    return Unit{}

def readResult(route: Route,next: Pipe -> IO(Unit), +events: Chan(ProcessEvent), result: Pipe & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Unit):
  match result:
    case (pipe,Fail{(code,message)}): closePipe(events,pipe,Error{"pipe read",code,message} <> Nil{})
    case (pipe,Done{Nil{}}): closePipe(events,pipe,Nil{})
    case (pipe,Done{bytes}):
      do IO<Unit>:
        sent : Bool <- Chan.send(ProcessEvent,events,Output{route,bytes})
        next(pipe)

# External input determines the number of reads, so no structural fuel bound
# is appropriate. Each step awaits a read or a bounded-channel send.
@unsafe def readPipe(+route: Route,+events: Chan(ProcessEvent), pipe: Pipe) -> IO(Unit):
  do IO<Unit>:
    result : Pipe & Result<&1,&1,U32 & String,List<&2,U32>> <- Pipe.read(pipe,65536)
    readResult(route,next => readPipe(route,events,next),events,result)

def processResult(+events: Chan(ProcessEvent), owners: Chan(Process), result: Process & Result<&1,&1,U32 & String,ProcessStatus>) -> IO(Unit):
  match result:
    case (owner,Done{status}):
      do IO<Unit>:
        saved : Bool <- Chan.send(Process,owners,owner)
        sent : Bool <- Chan.send(ProcessEvent,events,Exited{Some{status},Nil{}})
        return Unit{}
    case (owner,Fail{(code,message)}):
      do IO<Unit>:
        saved : Bool <- Chan.send(Process,owners,owner)
        sent : Bool <- Chan.send(ProcessEvent,events,Exited{None{},Error{"process wait",code,message} <> Nil{}})
        return Unit{}

def watchProcess(events: Chan(ProcessEvent), owners: Chan(Process), owner: Process) -> IO(Unit):
  do IO<Unit>:
    result : Process & Result<&1,&1,U32 & String,ProcessStatus> <- Process.wait(owner)
    processResult(events,owners,result)

def timerResult(events: Chan(ProcessEvent), generation: Nat, result: Timer & Bool) -> IO(Unit):
  match result:
    case (owner,elapsed):
      do IO<Unit>:
        Timer.close(owner)
        sent : Bool <- Chan.send(ProcessEvent,events,TimerEnded{generation,elapsed})
        return Unit{}

def watchTimer(events: Chan(ProcessEvent), generation: Nat, owner: Timer) -> IO(Unit):
  do IO<Unit>:
    result : Timer & Bool <- Timer.wait(owner)
    timerResult(events,generation,result)

def cancelTimer(timer: Maybe<&2,TimerCancel>) -> IO(Unit):
  match timer:
    case None{}: IO.pure(Unit,Unit{})
    case Some{handle}:
      do IO<Unit>:
        cancelled : Bool <- Timer.cancel(handle)
        return Unit{}

def armed(events: Chan(ProcessEvent), state: State, pair: Timer & TimerCancel) -> IO(State):
  match state pair:
    case State{pipes,exited,status,failed,stopping,+generation,_,timers} Tuple{owner,handle}:
      do IO<State>:
        IO.spawn(Unit,watchTimer(events,generation,owner))
        return State{pipes,exited,status,failed,stopping,generation,Some{handle},timers+1n}

def arm(events: Chan(ProcessEvent), state: State) -> IO(State):
  match state:
    case State{pipes,exited,status,failed,stopping,generation,timer,timers}:
      do IO<State>:
        cancelTimer(timer)
        pair : Timer & TimerCancel <- Timer.new(100)
        armed(events,State{pipes,exited,status,failed,stopping,generation+1n,None{},timers},pair)

def stop(context: Context, state: State) -> IO(State):
  match context state:
    case Context{_,_,out,err,_,_} State{pipes,exited,status,failed,_,generation,timer,timers}:
      do IO<State>:
        cancelTimer(timer)
        cancelledOut : Bool <- Pipe.cancel(out)
        cancelledErr : Bool <- Pipe.cancel(err)
        return State{pipes,exited,status,failed,True{},generation,None{},timers}

def signalled(state: State, result: Result<&1,&1,U32 & String,Bool>) -> State:
  match state result:
    case State{pipes,exited,status,failed,stopping,generation,timer,timers} Fail{(code,message)}:
      State{pipes,exited,status,Error{"process signal",code,message} <> failed,stopping,generation,timer,timers}
    case state Done{_}: state

def fail(+context: Context, state: State) -> IO(State):
  match context:
    case Context{_,control,_,_,_,_}:
      do IO<State>:
        signalledResult : Result<&1,&1,U32 & String,Bool> <- Process.signal(control,9)
        stop(context,signalled(state,signalledResult))

# ECANCELED from our deliberate pipe cancellation is not an output failure.
# The primitive currently supports Linux; every other read/close error remains.
def retainErrors(stopping: Bool, failed: List<&2,Error>) -> List<&2,Error>:
  match stopping failed:
    case _ Nil{}: Nil{}
    case True{} Error{"pipe read",125,_} <> rest: retainErrors(True{},rest)
    case stopping error <> rest: error <> retainErrors(stopping,rest)

def outputResult(+context: Context, state: State, result: Result<&2,&2,String,Unit>) -> IO(State):
  match context state result:
    case _ State{pipes,exited,status,failed,stopping,generation,timer,timers} Fail{message}:
      fail(context,State{pipes,exited,status,Error{"output",0,message} <> failed,stopping,generation,timer,timers})
    case Context{events,_,_,_,_,_} State{pipes,True{},status,failed,False{},generation,timer,timers} Done{_}:
      arm(events,State{pipes,True{},status,failed,False{},generation,timer,timers})
    case _ state Done{_}: IO.pure(State,state)

def consumer(context: Context, route: Route) -> Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>:
  match context route:
    case Context{_,_,_,_,_,onError} Secondary{}: onError
    case Context{_,_,_,_,onData,_} _: onData

def deliver(+context: Context, state: State, route: Route, bytes: List<&2,U32>) -> IO(State):
  match state route:
    case State{pipes,exited,status,failed,True{},generation,timer,timers} _: IO.pure(State,State{pipes,exited,status,failed,True{},generation,timer,timers})
    case state Dropped{}: outputResult(context,state,Done{Unit{}})
    case state route:
      do IO<State>:
        result : Result<&2,&2,String,Unit> <- Callback.call(List<&2,U32>,Result<&2,&2,String,Unit>,consumer(context,route),bytes)
        outputResult(context,state,result)

def pipeEnded(+context: Context, state: State, newErrors: List<&2,Error>) -> IO(State):
  match state newErrors:
    case State{0,True{},status,failed,stopping,generation,timer,timers} Nil{}:
      stop(context,State{0,True{},status,failed,stopping,generation,timer,timers})
    case state Nil{}: IO.pure(State,state)
    case State{pipes,exited,status,failed,stopping,generation,timer,timers} newErrors:
      fail(context,State{pipes,exited,status,List.append(&2,Error,List.reverse(&2,Error,newErrors),failed),stopping,generation,timer,timers})

def afterExit(context: Context, events: Chan(ProcessEvent), state: State) -> IO(State):
  match state:
    case State{0,exited,status,failed,stopping,generation,timer,timers}: stop(context,State{0,exited,status,failed,stopping,generation,timer,timers})
    case State{pipes,exited,status,failed,True{},generation,timer,timers}: stop(context,State{pipes,exited,status,failed,True{},generation,timer,timers})
    case state: arm(events,state)

def timerEnded(context: Context, state: State, elapsed: Bool) -> IO(State):
  match elapsed:
    case True{}: stop(context,state)
    case False{}: IO.pure(State,state)

def consume(+context: Context, state: State, event: ProcessEvent) -> IO(State):
  match context state event:
    case _ state Output{route,bytes}:
      deliver(context,state,route,bytes)
    case _ State{pipes,exited,status,failed,+stopping,generation,timer,timers} PipeEnded{newErrors}:
      pipeEnded(context,State{(pipes-1:U32),exited,status,failed,stopping,generation,timer,timers},retainErrors(stopping,newErrors))
    case Context{events,_,_,_,_,_} State{pipes,_,_,failed,stopping,generation,timer,timers} Exited{status,Nil{}}:
      afterExit(context,events,State{pipes,True{},status,failed,stopping,generation,timer,timers})
    case _ State{pipes,_,_,failed,stopping,generation,timer,timers} Exited{status,newErrors}:
      fail(context,State{pipes,True{},status,List.append(&2,Error,List.reverse(&2,Error,newErrors),failed),stopping,generation,timer,timers})
    case _ State{pipes,exited,status,failed,stopping,+generation,timer,timers} TimerEnded{ended,elapsed}:
      timerEnded(context,State{pipes,exited,status,failed,stopping,generation,timer,timers-1n},Nat.is_eq(ended,generation) && elapsed)

def received(value: Maybe<&1,ProcessEvent>) -> IO(ProcessEvent):
  match value:
    case Some{event}: IO.pure(ProcessEvent,event)
    case None{}: IO.die(ProcessEvent,1,"child-process event channel closed before its producers finished")

def receive(events: Chan(ProcessEvent)) -> IO(ProcessEvent):
  IO.bind(Maybe<&1,ProcessEvent>,ProcessEvent,Chan.recv(ProcessEvent,events),received)

# ProcessEvent sources have external lifetimes. Drain all terminal events, including
# cancelled timers, before closing the bounded channel; no worker outlives it.
@unsafe def drive(+context: Context, state: State) -> IO(Report):
  match context state:
    case Context{events,_,_,_,_,_} State{0,True{},status,failed,_,_,_,0n}:
      do IO<Report>:
        Chan.close(ProcessEvent,events)
        return Report{status,List.reverse(&2,Error,failed)}
    case Context{+events,_,_,_,_,_} state:
      do IO<Report>:
        event : ProcessEvent <- receive(events)
        next : State <- consume(context,state,event)
        drive(context,next)

def errorRoute(selection: OutputSelection) -> Route:
  match selection:
    case Merged{}: Primary{}
    case Stdout{}: Dropped{}
    case Separate{_}: Secondary{}

def errorConsumer(selection: OutputSelection, onData: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>) -> Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>:
  match selection:
    case Separate{onError}: onError
    case _: onData

def waitForSelectedChildProcess(+selection: OutputSelection,owner: Process, +control: ProcessControl, stdout: Pipe & PipeCancel, stderr: Pipe & PipeCancel, +onData: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>) -> IO(Process & Report):
  match stdout stderr:
    case Tuple{out,outCancel} Tuple{err,errCancel}:
      do IO<Process & Report>:
        +events : Chan(ProcessEvent) <- Chan.new(ProcessEvent,16)
        +owners : Chan(Process) <- Chan.new(Process,1)
        IO.spawn(Unit,readPipe(Primary{},events,out))
        IO.spawn(Unit,readPipe(errorRoute(selection),events,err))
        IO.spawn(Unit,watchProcess(events,owners,owner))
        report : Report <- drive(Context{events,control,outCancel,errCancel,onData,errorConsumer(selection,onData)},State{2,False{},None{},Nil{},False{},0n,None{},0n})
        process : Process <- IO.join(Process,owners)
        return (process,report)

def waitForChildProcess(owner: Process,control: ProcessControl,stdout: Pipe & PipeCancel,stderr: Pipe & PipeCancel,onData: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>) -> IO(Process & Report):
  waitForSelectedChildProcess(Merged{},owner,control,stdout,stderr,onData)

# Execution owns the process and its cancellation observers. The caller owns
# the signals and output callbacks, all of which remain borrowed. Any signal
# interrupts the process.
type ExecutionError is Data:
  InvalidTimeout{}
  ExecutionAborted{}
  ExecutionTimedOut{}
  ExecutionFailed{errors: List<&2,Error>}

type ExecutionOptions is Data:
  ExecutionOptions{signals: List<&2,Abort.AbortSignal<Unit>>, milliseconds: Maybe<&2,U32>, onData: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>}

type Started is Type:
  Started{owner: Process, control: ProcessControl, input: Maybe<&1,Pipe & PipeCancel>, output: Pipe & PipeCancel, error: Pipe & PipeCancel}

type WatchResult is Data:
  WatchResult{triggered: Bool, errors: List<&2,Error>}

type Observer is Type:
  Observer{cancel: IO(Unit), task: Chan(WatchResult)}

type InputWriter is Type:
  InputWriter{cancel: PipeCancel, task: Chan(List<&2,Error>)}

def timeoutChecked(valid: Bool, milliseconds: F64) -> Result<&2,&2,ExecutionError,U32>:
  match valid:
    case False{}: Fail{InvalidTimeout{}}
    case True{}: Done{U32.max(1,F64.to_u32(F64.floor(milliseconds)))}

# Validate the original positive seconds and unrounded milliseconds, then use
# Node's floor/minimum-one millisecond timer quantization (including underflow).
def timeoutMilliseconds(+seconds: F64) -> Result<&2,&2,ExecutionError,U32>:
  +ms = F64.mul(seconds,U32.to_f64(1000))
  timeoutChecked(F64.is_lt(U32.to_f64(0),seconds) && F64.is_le(ms,U32.to_f64(2147483647)),ms)

def optionalTimeout(value: Maybe<&2,F64>) -> Result<&2,&2,ExecutionError,Maybe<&2,U32>>:
  match value:
    case None{}: Done{None{}}
    case Some{seconds}: Result.map(&2,&2,ExecutionError,U32,Maybe<&2,U32>,n => Some{n},timeoutMilliseconds(seconds))

def anyAborted(signals: List<&2,Abort.AbortSignal<Unit>>) -> IO(Bool):
  match signals:
    case Nil{}: IO.pure(Bool,False{})
    case signal <> rest:
      do IO<Bool>:
        aborted : Bool <- Abort.aborted(Unit,signal)
        Bool.pick(IO(Bool),aborted,IO.pure(Bool,True{}),anyAborted(rest))

def signalList(signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> List<&2,Abort.AbortSignal<Unit>>:
  match signal:
    case None{}: Nil{}
    case Some{value}: [value]

def parentAborted(signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(Bool):
  anyAborted(signalList(signal))

def signalResult(triggered: Bool, result: Result<&1,&1,U32 & String,Bool>) -> WatchResult:
  match result:
    case Done{_}: WatchResult{triggered,Nil{}}
    case Fail{(code,message)}: WatchResult{triggered,Error{"process signal",code,message} <> Nil{}}

def interruptProcess(triggered: Bool, control: ProcessControl) -> IO(WatchResult):
  match triggered:
    case False{}: IO.pure(WatchResult,WatchResult{False{},Nil{}})
    case True{}:
      do IO<WatchResult>:
        result : Result<&1,&1,U32 & String,Bool> <- Process.signal(control,9)
        return signalResult(True{},result)

def watchAbort(control: ProcessControl, ticket: Deferred.Ticket<Maybe<&2,Abort.AbortReason<Unit>>>) -> IO(WatchResult):
  do IO<WatchResult>:
    reason : Maybe<&2,Abort.AbortReason<Unit>> <- Deferred.wait(Maybe<&2,Abort.AbortReason<Unit>>,ticket)
    interruptProcess(Bool.not(Maybe.is_none(&2,Abort.AbortReason<Unit>,reason)),control)

def cancelAbort(cancellation: Deferred.Cancellation<Abort.AbortReason<Unit>>) -> IO(Unit):
  do IO<Unit>:
    removed : Bool <- Deferred.cancel(Abort.AbortReason<Unit>,cancellation)
    return Unit{}

def abortObserver(control: ProcessControl, observation: Deferred.Observation<Abort.AbortReason<Unit>>) -> IO(Observer):
  match observation:
    case Deferred.Observation{ticket,cancellation}:
      do IO<Observer>:
        task : Chan(WatchResult) <- IO.fork(WatchResult,watchAbort(control,ticket))
        return Observer{cancelAbort(cancellation),task}

def observeAborts(signals: List<&2,Abort.AbortSignal<Unit>>, +control: ProcessControl) -> IO(List<&1,Observer>):
  match signals:
    case Nil{}: IO.pure(List<&1,Observer>,Nil{})
    case signal <> rest:
      do IO<List<&1,Observer>>:
        observation : Deferred.Observation<Abort.AbortReason<Unit>> <- Abort.observe(Unit,signal)
        observer : Observer <- abortObserver(control,observation)
        others : List<&1,Observer> <- observeAborts(rest,control)
        return observer <> others

def deadlineElapsed(control: ProcessControl, result: Timer & Bool) -> IO(WatchResult):
  match result:
    case (owner,elapsed):
      do IO<WatchResult>:
        Timer.close(owner)
        interruptProcess(elapsed,control)

def watchDeadline(control: ProcessControl, owner: Timer) -> IO(WatchResult):
  do IO<WatchResult>:
    result : Timer & Bool <- Timer.wait(owner)
    deadlineElapsed(control,result)

def deadlineObserver(control: ProcessControl, pair: Timer & TimerCancel) -> IO(Maybe<&1,Observer>):
  match pair:
    case (owner,handle):
      do IO<Maybe<&1,Observer>>:
        task : Chan(WatchResult) <- IO.fork(WatchResult,watchDeadline(control,owner))
        return Some{Observer{cancelTimer(Some{handle}),task}}

def observeDeadline(milliseconds: Maybe<&2,U32>, control: ProcessControl) -> IO(Maybe<&1,Observer>):
  match milliseconds:
    case None{}: IO.pure(Maybe<&1,Observer>,None{})
    case Some{value}:
      do IO<Maybe<&1,Observer>>:
        pair : Timer & TimerCancel <- Timer.new(value)
        deadlineObserver(control,pair)

# Cancel both registrations before joining either completion. A completion that
# already won is retained, and no observer can signal after owner retirement.
def cancelObserver(observer: Maybe<&1,Observer>) -> IO(Maybe<&2,Chan(WatchResult)>):
  match observer:
    case None{}: IO.pure(Maybe<&2,Chan(WatchResult)>,None{})
    case Some{Observer{cancel,task}}:
      do IO<Maybe<&2,Chan(WatchResult)>>:
        cancel
        return Some{task}

def joinObserver(task: Maybe<&2,Chan(WatchResult)>) -> IO(WatchResult):
  match task:
    case None{}: IO.pure(WatchResult,WatchResult{False{},Nil{}})
    case Some{value}: IO.join(WatchResult,value)

def cancelObservers(observers: List<&1,Observer>) -> IO(List<&2,Chan(WatchResult)>):
  match observers:
    case Nil{}: IO.pure(List<&2,Chan(WatchResult)>,Nil{})
    case Observer{cancel,task} <> rest:
      do IO<List<&2,Chan(WatchResult)>>:
        cancel
        others : List<&2,Chan(WatchResult)> <- cancelObservers(rest)
        return task <> others

def combined(first: WatchResult, second: WatchResult) -> WatchResult:
  match first second:
    case WatchResult{left,leftErrors} WatchResult{right,rightErrors}: WatchResult{left || right,List.append(&2,Error,leftErrors,rightErrors)}

def joinObservers(tasks: List<&2,Chan(WatchResult)>) -> IO(WatchResult):
  match tasks:
    case Nil{}: IO.pure(WatchResult,WatchResult{False{},Nil{}})
    case task <> rest:
      do IO<WatchResult>:
        first : WatchResult <- IO.join(WatchResult,task)
        others : WatchResult <- joinObservers(rest)
        return combined(first,others)

def inputClosed(pipe: Pipe, failed: List<&2,Error>) -> IO(List<&2,Error>):
  do IO<List<&2,Error>>:
    result : Result<&1,&1,U32 & String,Unit> <- Pipe.close_checked(pipe)
    return List.append(&2,Error,failed,errors("stdin close",result))

# A shell may exit before consuming its whole script. EPIPE matches upstream's
# ignored stdin error; our deliberate retirement also cancels a blocked writer.
def inputResult(next: Pipe -> List<&2,U32> -> IO(List<&2,Error>), bytes: List<&2,U32>, result: Pipe & Result<&1,&1,U32 & String,U32>) -> IO(List<&2,Error>):
  match result:
    case (pipe,Fail{(32,_)}): inputClosed(pipe,Nil{})
    case (pipe,Fail{(125,_)}): inputClosed(pipe,Nil{})
    case (pipe,Fail{(code,message)}): inputClosed(pipe,Error{"stdin write",code,message} <> Nil{})
    case (pipe,Done{0}): inputClosed(pipe,Error{"stdin write",0,"write made no progress"} <> Nil{})
    case (pipe,Done{count}): next(pipe,List.drop(&2,U32,bytes,U32.to_nat(count)))

# Each successful write removes at least one byte, so the initial byte length
# bounds the number of iterations even when the OS accepts partial writes.
def writeInput(fuel: Nat, pipe: Pipe, bytes: List<&2,U32>) -> IO(List<&2,Error>):
  match fuel bytes:
    case _ Nil{}: inputClosed(pipe,Nil{})
    case 0n _: inputClosed(pipe,[Error{"stdin write",0,"write progress exhausted"}])
    case 1n+rest +bytes:
      do IO<List<&2,Error>>:
        result : Pipe & Result<&1,&1,U32 & String,U32> <- Pipe.write(pipe,List.take(&2,U32,bytes,65536n))
        inputResult(next => pending => writeInput(rest,next,pending),bytes,result)

def startInput(input: Maybe<&1,Pipe & PipeCancel>, command: String) -> IO(Maybe<&1,InputWriter>):
  match input:
    case None{}: IO.pure(Maybe<&1,InputWriter>,None{})
    case Some{(pipe,cancel)}:
      do IO<Maybe<&1,InputWriter>>:
        +bytes : List<&2,U32> = Utf8.encode(command)
        task : Chan(List<&2,Error>) <- IO.fork(List<&2,Error>,writeInput(List.length(&2,U32,bytes),pipe,bytes))
        return Some{InputWriter{cancel,task}}

def finishInput(input: Maybe<&1,InputWriter>) -> IO(List<&2,Error>):
  match input:
    case None{}: IO.pure(List<&2,Error>,Nil{})
    case Some{InputWriter{cancel,task}}:
      do IO<List<&2,Error>>:
        stopped : Bool <- Pipe.cancel(cancel)
        IO.join(List<&2,Error>,task)

def executionResult(aborted: Bool, expired: Bool, failed: List<&2,Error>, status: Maybe<&2,ProcessStatus>) -> Result<&2,&2,ExecutionError,U32>:
  match aborted expired failed status:
    case True{} _ _ _: Fail{ExecutionAborted{}}
    case _ True{} _ _: Fail{ExecutionTimedOut{}}
    case _ _ error <> rest _: Fail{ExecutionFailed{error <> rest}}
    case _ _ Nil{} Some{ProcessExited{code}}: Done{code}
    case _ _ Nil{} Some{ProcessSignalled{signal}}: Done{(128 + signal : U32)}
    case _ _ Nil{} None{}: Fail{ExecutionFailed{[Error{"process status",0,"missing exit status"}]}}

def finishExecution(signals: List<&2,Abort.AbortSignal<Unit>>, input: Maybe<&1,InputWriter>, owner: Process, report: Report, parent: WatchResult, deadline: WatchResult) -> IO(Result<&2,&2,ExecutionError,U32>):
  match report parent deadline:
    case Report{status,failed} WatchResult{_,parentErrors} WatchResult{expired,timerErrors}:
      do IO<Result<&2,&2,ExecutionError,U32>>:
        inputErrors : List<&2,Error> <- finishInput(input)
        closed : Result<&1,&1,U32 & String,Unit> <- Process.close_checked(owner)
        aborted : Bool <- anyAborted(signals)
        allErrors : List<&2,Error> = List.concat(&2,Error,[failed,parentErrors,timerErrors,inputErrors,errors("process close",closed)])
        return executionResult(aborted,expired,allErrors,status)

def retireExecution(signals: List<&2,Abort.AbortSignal<Unit>>, input: Maybe<&1,InputWriter>, parents: List<&1,Observer>, deadline: Maybe<&1,Observer>, result: Process & Report) -> IO(Result<&2,&2,ExecutionError,U32>):
  match result:
    case (owner,report):
      do IO<Result<&2,&2,ExecutionError,U32>>:
        parentTasks : List<&2,Chan(WatchResult)> <- cancelObservers(parents)
        timerTask : Maybe<&2,Chan(WatchResult)> <- cancelObserver(deadline)
        parentResult : WatchResult <- joinObservers(parentTasks)
        timerResult : WatchResult <- joinObserver(timerTask)
        finishExecution(signals,input,owner,report,parentResult,timerResult)

def withInput(result: Result<&1,&1,U32 & String,Process & ProcessControl & (Pipe & PipeCancel) & (Pipe & PipeCancel) & (Pipe & PipeCancel)>) -> Result<&1,&1,U32 & String,Started>:
  match result:
    case Fail{error}: Fail{error}
    case Done{(owner,(control,(input,(output,error))))}: Done{Started{owner,control,Some{input},output,error}}

def withoutInput(result: Result<&1,&1,U32 & String,Process & ProcessControl & (Pipe & PipeCancel) & (Pipe & PipeCancel)>) -> Result<&1,&1,U32 & String,Started>:
  match result:
    case Fail{error}: Fail{error}
    case Done{(owner,(control,(output,error)))}: Done{Started{owner,control,None{},output,error}}

def spawnStarted(stdin: Bool, path: String, args: List<String>, cwd: String, env: List<String>) -> IO(Result<&1,&1,U32 & String,Started>):
  match stdin:
    case True{}:
      do IO<Result<&1,&1,U32 & String,Started>>:
        result : Result<&1,&1,U32 & String,Process & ProcessControl & (Pipe & PipeCancel) & (Pipe & PipeCancel) & (Pipe & PipeCancel)> <- Process.spawn(path,args,cwd,env)
        return withInput(result)
    case False{}:
      do IO<Result<&1,&1,U32 & String,Started>>:
        result : Result<&1,&1,U32 & String,Process & ProcessControl & (Pipe & PipeCancel) & (Pipe & PipeCancel)> <- Process.spawn_null_stdin(path,args,cwd,env)
        return withoutInput(result)

def executeStarted(selection: OutputSelection,options: ExecutionOptions, command: String, result: Result<&1,&1,U32 & String,Started>) -> IO(Result<&2,&2,ExecutionError,U32>):
  match options result:
    case ExecutionOptions{signals,_,_} Fail{(code,message)}:
      do IO<Result<&2,&2,ExecutionError,U32>>:
        aborted : Bool <- anyAborted(signals)
        return executionResult(aborted,False{},[Error{"spawn",code,message}],None{})
    case ExecutionOptions{+signals,milliseconds,onData} Done{Started{owner,+control,input,output,error}}:
      do IO<Result<&2,&2,ExecutionError,U32>>:
        parents : List<&1,Observer> <- observeAborts(signals,control)
        deadline : Maybe<&1,Observer> <- observeDeadline(milliseconds,control)
        writer : Maybe<&1,InputWriter> <- startInput(input,command)
        result : Process & Report <- waitForSelectedChildProcess(selection,owner,control,output,error,onData)
        retireExecution(signals,writer,parents,deadline,result)

def executeChecked(selection: OutputSelection,aborted: Bool, stdin: Bool, path: String, args: List<String>, +command: String, cwd: String, env: List<String>, options: ExecutionOptions) -> IO(Result<&2,&2,ExecutionError,U32>):
  match aborted:
    case True{}: IO.pure(Result<&2,&2,ExecutionError,U32>,Fail{ExecutionAborted{}})
    case False{}:
      do IO<Result<&2,&2,ExecutionError,U32>>:
        result : Result<&1,&1,U32 & String,Started> <- spawnStarted(stdin,path,args,cwd,env)
        executeStarted(selection,options,command,result)

def executeValidated(selection: OutputSelection,stdin: Bool, path: String, args: List<String>, command: String, cwd: String, env: List<String>, +signals: List<&2,Abort.AbortSignal<Unit>>, onData: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>, timeout: Result<&2,&2,ExecutionError,Maybe<&2,U32>>) -> IO(Result<&2,&2,ExecutionError,U32>):
  match timeout:
    case Fail{error}: IO.pure(Result<&2,&2,ExecutionError,U32>,Fail{error})
    case Done{milliseconds}:
      do IO<Result<&2,&2,ExecutionError,U32>>:
        aborted : Bool <- anyAborted(signals)
        executeChecked(selection,aborted,stdin,path,args,command,cwd,env,ExecutionOptions{signals,milliseconds,onData})

# Stderr is always drained and checked, but Stdout never calls the consumer for
# those bytes. Both streams still extend post-exit activity before retirement.
def executeSelected(selection: OutputSelection,shell: String,args: List<String>,command: String,cwd: String,env: List<String>,signal: Maybe<&2,Abort.AbortSignal<Unit>>,timeoutSeconds: Maybe<&2,F64>,onData: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>) -> IO(Result<&2,&2,ExecutionError,U32>):
  executeValidated(selection,False{},shell,List.append(&1,String,args,[command]),"",cwd,env,signalList(signal),onData,optionalTimeout(timeoutSeconds))

def execute(shell: String, args: List<String>, command: String, cwd: String, env: List<String>, signal: Maybe<&2,Abort.AbortSignal<Unit>>, timeoutSeconds: Maybe<&2,F64>, onData: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>) -> IO(Result<&2,&2,ExecutionError,U32>):
  executeSelected(Merged{},shell,args,command,cwd,env,signal,timeoutSeconds,onData)

def executeStdin(shell: String, args: List<String>, command: String, cwd: String, env: List<String>, signal: Maybe<&2,Abort.AbortSignal<Unit>>, timeoutSeconds: Maybe<&2,F64>, onData: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>) -> IO(Result<&2,&2,ExecutionError,U32>):
  executeValidated(Merged{},True{},shell,args,command,cwd,env,signalList(signal),onData,optionalTimeout(timeoutSeconds))

# X_OK alone also accepts directories and executable special files. stat's
# regular-file predicate follows symlinks without opening their content.
def executableFile(+path: String, accessible: Bool) -> IO(Bool):
  match accessible:
    case False{}: IO.pure(Bool,False{})
    case True{}:
      do IO<Bool>:
        regular : Result<&1,&1,U32 & String,Bool> <- File.is_file(path)
        return Result.default(&1,&1,U32 & String,Bool,regular,False{})

def executable(+path: String) -> IO(Bool):
  do IO<Bool>:
    accessible : Bool <- FS.accessible(path,1)
    executableFile(path,accessible)

# PATH is ordered, and an empty component denotes the current directory.
# Candidates remain paths, never strings interpolated into a shell command.
def findExecutableOnPath(+name: String, entries: List<&2,String>, previous: Maybe<&2,String>) -> IO(Maybe<&2,String>):
  match entries previous:
    case _ Some{path}: IO.pure(Maybe<&2,String>,Some{path})
    case Nil{} None{}: IO.pure(Maybe<&2,String>,None{})
    case +directory <> rest None{}:
      +path = FS.child(Bool.pick(String,Strings.equal(directory,""),".",directory),name)
      do IO<Maybe<&2,String>>:
        allowed : Bool <- executable(path)
        findExecutableOnPath(name,rest,Bool.pick(Maybe<&2,String>,allowed,Some{path},None{}))

# The child's PATH, or libuv's default search path when it has none. The
# environment is returned for the spawn itself.
def restored(entry: String, found: String & List<String>) -> String & List<String>:
  match found:
    case (path,others): (path,entry <> others)

def withSearchPath(env: List<String>, found: Maybe<&2,String>) -> String & List<String>:
  match env found:
    case env Some{path}: (path,env)
    case Nil{} None{}: ("/usr/bin:/bin",Nil{})
    case +entry <> rest None{}:
      restored(entry,withSearchPath(rest,Bool.pick(Maybe<&2,String>,String.starts_with(entry,"PATH="),Some{String.drop(entry,5n)},None{})))

def resolved(named: Bool, command: String, path: String) -> IO(Maybe<&2,String>):
  match named:
    case True{}: IO.pure(Maybe<&2,String>,Some{command})
    case False{}: findExecutableOnPath(command,Strings.split(path,':'),None{})

# A command naming a path is used as is; a bare name is searched on PATH.
def resolveCommand(+command: String, path: String) -> IO(Maybe<&2,String>):
  resolved(String.contains(command,"/"),command,path)

def spawnResolved(args: List<String>, cwd: String, env: List<String>, +signals: List<&2,Abort.AbortSignal<Unit>>, onStdout: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>, onStderr: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>, path: Maybe<&2,String>) -> IO(Result<&2,&2,ExecutionError,U32>):
  match path:
    case None{}: IO.pure(Result<&2,&2,ExecutionError,U32>,Fail{ExecutionFailed{[Error{"spawn",2,"No such file or directory"}]}})
    case Some{program}: executeValidated(Separate{onStderr},False{},program,args,"",cwd,env,signals,onStdout,Done{None{}})

def spawnSearched(command: String, args: List<String>, cwd: String, signals: List<&2,Abort.AbortSignal<Unit>>, onStdout: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>, onStderr: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>, searched: String & List<String>) -> IO(Result<&2,&2,ExecutionError,U32>):
  match searched:
    case (path,env):
      do IO<Result<&2,&2,ExecutionError,U32>>:
        program : Maybe<&2,String> <- resolveCommand(command,path)
        spawnResolved(args,cwd,env,signals,onStdout,onStderr,program)

# Node's spawn without a shell: stdin is closed, stdout and stderr reach their
# own consumers, and any of the signals interrupts the process.
def spawn(command: String, args: List<String>, cwd: String, env: List<String>, signals: List<&2,Abort.AbortSignal<Unit>>, onStdout: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>, onStderr: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>) -> IO(Result<&2,&2,ExecutionError,U32>):
  spawnSearched(command,args,cwd,signals,onStdout,onStderr,withSearchPath(env,None{}))
