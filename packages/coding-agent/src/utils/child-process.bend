import Base
import ../../../runtime/src/callback.bend as Callback

# The process owner stays unreaped until the caller has retired its timeout
# and abort observers. Pipe readers and idle timers finish before this returns.
type Error is Data:
  Error{operation: String, code: U32, message: String}

type Report is Data:
  Report{status: Maybe<&2,ProcessStatus>, errors: List<&2,Error>}

type ProcessEvent is Data:
  Output{bytes: List<&2,U32>}
  PipeEnded{errors: List<&2,Error>}
  Exited{status: Maybe<&2,ProcessStatus>, errors: List<&2,Error>}
  TimerEnded{generation: Nat, elapsed: Bool}

type State is Data:
  State{pipes: U32, exited: Bool, status: Maybe<&2,ProcessStatus>, errors: List<&2,Error>, stopping: Bool, generation: Nat, timer: Maybe<&2,TimerCancel>, timers: Nat}

type Context is Data:
  Context{events: Chan(ProcessEvent), process: ProcessControl, stdout: PipeCancel, stderr: PipeCancel, onData: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>}

def errors(operation: String, result: Result<&1,&1,U32 & String,Unit>) -> List<&2,Error>:
  match result:
    case Done{_}: Nil{}
    case Fail{(code,message)}: Error{operation,code,message} <> Nil{}

def closePipe(events: Chan(ProcessEvent), pipe: Pipe, failed: List<&2,Error>) -> IO(Unit):
  do IO<Unit>:
    closed : Result<&1,&1,U32 & String,Unit> <- Pipe.close_checked(pipe)
    sent : Bool <- Chan.send(ProcessEvent,events,PipeEnded{List.append(&2,Error,failed,errors("pipe close",closed))})
    return Unit{}

def readResult(next: Pipe -> IO(Unit), +events: Chan(ProcessEvent), result: Pipe & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Unit):
  match result:
    case (pipe,Fail{(code,message)}): closePipe(events,pipe,Error{"pipe read",code,message} <> Nil{})
    case (pipe,Done{Nil{}}): closePipe(events,pipe,Nil{})
    case (pipe,Done{bytes}):
      do IO<Unit>:
        sent : Bool <- Chan.send(ProcessEvent,events,Output{bytes})
        next(pipe)

# External input determines the number of reads, so no structural fuel bound
# is appropriate. Each step awaits a read or a bounded-channel send.
@unsafe def readPipe(+events: Chan(ProcessEvent), pipe: Pipe) -> IO(Unit):
  do IO<Unit>:
    result : Pipe & Result<&1,&1,U32 & String,List<&2,U32>> <- Pipe.read(pipe,65536)
    readResult(next => readPipe(events,next),events,result)

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
    case Context{_,_,out,err,_} State{pipes,exited,status,failed,_,generation,timer,timers}:
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
    case Context{_,control,_,_,_}:
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
    case Context{events,_,_,_,_} State{pipes,True{},status,failed,False{},generation,timer,timers} Done{_}:
      arm(events,State{pipes,True{},status,failed,False{},generation,timer,timers})
    case _ state Done{_}: IO.pure(State,state)

def deliver(+context: Context, state: State, bytes: List<&2,U32>) -> IO(State):
  match context state:
    case _ State{pipes,exited,status,failed,True{},generation,timer,timers}: IO.pure(State,State{pipes,exited,status,failed,True{},generation,timer,timers})
    case Context{_,_,_,_,onData} state:
      do IO<State>:
        result : Result<&2,&2,String,Unit> <- Callback.call(List<&2,U32>,Result<&2,&2,String,Unit>,onData,bytes)
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
    case _ state Output{bytes}:
      deliver(context,state,bytes)
    case _ State{pipes,exited,status,failed,+stopping,generation,timer,timers} PipeEnded{newErrors}:
      pipeEnded(context,State{(pipes-1:U32),exited,status,failed,stopping,generation,timer,timers},retainErrors(stopping,newErrors))
    case Context{events,_,_,_,_} State{pipes,_,_,failed,stopping,generation,timer,timers} Exited{status,Nil{}}:
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
    case Context{events,_,_,_,_} State{0,True{},status,failed,_,_,_,0n}:
      do IO<Report>:
        Chan.close(ProcessEvent,events)
        return Report{status,List.reverse(&2,Error,failed)}
    case Context{+events,_,_,_,_} state:
      do IO<Report>:
        event : ProcessEvent <- receive(events)
        next : State <- consume(context,state,event)
        drive(context,next)

def waitForChildProcess(owner: Process, +control: ProcessControl, stdout: Pipe & PipeCancel, stderr: Pipe & PipeCancel, onData: Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>) -> IO(Process & Report):
  match stdout stderr:
    case Tuple{out,outCancel} Tuple{err,errCancel}:
      do IO<Process & Report>:
        +events : Chan(ProcessEvent) <- Chan.new(ProcessEvent,16)
        +owners : Chan(Process) <- Chan.new(Process,1)
        IO.spawn(Unit,readPipe(events,out))
        IO.spawn(Unit,readPipe(events,err))
        IO.spawn(Unit,watchProcess(events,owners,owner))
        report : Report <- drive(Context{events,control,outCancel,errCancel,onData},State{2,False{},None{},Nil{},False{},0n,None{},0n})
        process : Process <- IO.join(Process,owners)
        return (process,report)
