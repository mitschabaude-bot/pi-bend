import Base
import ../packages/tui/src/terminal.bend as T
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/json.bend as J

def closeTimer(value: Timer & Bool) -> IO(Unit):
  match value:
    case (timer,_): Timer.close(timer)
def waitTimer(value: Timer & TimerCancel) -> IO(Unit):
  match value:
    case (timer,_):
      do IO<Unit>:
        result : Timer & Bool <- Timer.wait(timer)
        closeTimer(result)
def sleep(ms: U32) -> IO(Unit):
  do IO<Unit>:
    pair : Timer & TimerCancel <- Timer.new(ms)
    waitTimer(pair)
def onInput(environment: Unit,text: String) -> IO(Unit): IO.print_err("input:" ++ J.quote(text))
def onResize(environment: Unit,value: Unit) -> IO(Unit): IO.print_err("resize")
def status(result: Result<&2,&2,T.Error,Unit>) -> String:
  match result:
    case Done{Unit{}}: "ok"
    case Fail{_}: "error"
def size(value: T.Dimensions) -> String:
  match value:
    case T.Dimensions{columns,rows}: U32.show(columns) ++ ":" ++ U32.show(rows)
def repeat(count: Nat,text: String) -> String:
  match count:
    case Zero{}: text
    case Succ{rest}: repeat(rest,"0123456789abcdef" ++ text)
def collision(result: Result<&1,&1,U32 & String,TerminalLease & (Pipe & PipeCancel) & (Pipe & PipeCancel) & (Pipe & PipeCancel)>) -> IO(Unit):
  match result:
    case Fail{(16,_)}: IO.print_err("busy")
    case _: IO.die(Unit,1,"concurrent terminal acquire was not rejected")
def commands(+handle: T.Handle,mode: String) -> IO(Unit):
  match mode:
    case "cycle": IO.pure(Unit,Unit{})
    case "collision":
      do IO<Unit>:
        result : Result<&1,&1,U32 & String,TerminalLease & (Pipe & PipeCancel) & (Pipe & PipeCancel) & (Pipe & PipeCancel)> <- Terminal.acquire(0,1)
        collision(result)
    case "progress":
      do IO<Unit>:
        T.setProgress(handle,True{})
        sleep(1200)
        T.setProgress(handle,False{})
        sleep(40)
    case "progress-immediate":
      do IO<Unit>:
        T.setProgress(handle,True{})
        result : Result<&2,&2,T.Error,Unit> <- T.write(handle,"between")
        T.setProgress(handle,False{})
    case "drain":
      do IO<Unit>:
        sleep(80)
        IO.print_err("draining")
        +begin : Nat <- IO.now()
        result : Result<&2,&2,T.Error,Unit> <- T.drainInput(handle,600,80)
        end : Nat <- IO.now()
        IO.print_err("drained:" ++ status(result) ++ ":" ++ Nat.show(end - begin))
        sleep(200)
    case "cancel":
      do IO<Unit>:
        worker : Chan(Result<&2,&2,T.Error,Unit>) <- IO.fork(Result<&2,&2,T.Error,Unit>,T.write(handle,repeat(65536n,"")))
        sleep(60)
        T.cancel(handle)
        T.cancel(handle)
        result : Result<&2,&2,T.Error,Unit> <- IO.join(Result<&2,&2,T.Error,Unit>,worker)
        IO.print_err("cancelled:" ++ status(result))
    case "write":
      do IO<Unit>:
        result : Result<&2,&2,T.Error,Unit> <- T.write(handle,"logged Ω")
        IO.print_err("write:" ++ status(result))
        hidden : Result<&2,&2,T.Error,Unit> <- T.hideCursor(handle)
        return Unit{}
    case "slow-output":
      do IO<Unit>:
        result : Result<&2,&2,T.Error,Unit> <- T.write(handle,"BLOCKING_REGULAR_WRITE")
        IO.print_err("slow-write:" ++ status(result))
    case "slow-cancel":
      do IO<Unit>:
        worker : Chan(Result<&2,&2,T.Error,Unit>) <- IO.fork(Result<&2,&2,T.Error,Unit>,T.write(handle,"BLOCKING_REGULAR_WRITE"))
        sleep(60)
        T.cancel(handle)
        result : Result<&2,&2,T.Error,Unit> <- IO.join(Result<&2,&2,T.Error,Unit>,worker)
        IO.print_err("slow-cancel:" ++ status(result))
    case "controls":
      do IO<Unit>:
        a : Result<&2,&2,T.Error,Unit> <- T.hideCursor(handle)
        b : Result<&2,&2,T.Error,Unit> <- T.showCursor(handle)
        c : Result<&2,&2,T.Error,Unit> <- T.moveBy(handle,True{},2)
        d : Result<&2,&2,T.Error,Unit> <- T.moveBy(handle,False{},3)
        e : Result<&2,&2,T.Error,Unit> <- T.clearLine(handle)
        f : Result<&2,&2,T.Error,Unit> <- T.clearFromCursor(handle)
        g : Result<&2,&2,T.Error,Unit> <- T.clearScreen(handle)
        h : Result<&2,&2,T.Error,Unit> <- T.setTitle(handle,"test")
        IO.print_err(status(a) ++ status(b) ++ status(c) ++ status(d) ++ status(e) ++ status(f) ++ status(g) ++ status(h))
    case _:
      do IO<Unit>:
        sleep(550)
        kitty : Bool <- T.kittyProtocolActive(handle)
        IO.print_err(Bool.pick(String,kitty,"kitty:true","kitty:false"))
        measured : T.Dimensions <- T.getDimensions(handle)
        IO.print_err("size:" ++ size(measured))
def running(mode: String,pair: T.ProcessTerminal & T.Handle) -> IO(Unit):
  match pair:
    case (owner,handle):
      do IO<Unit>:
        IO.print_err("ready")
        commands(handle,mode)
        result : Result<&2,&2,T.Error,Unit> <- T.stop(owner)
        IO.print_err("stopped:" ++ status(result))
def started(mode: String,result: Result<&2,&1,T.Error,T.ProcessTerminal>) -> IO(Unit):
  match result:
    case Done{owner}: running(mode,T.borrow(owner))
    case Fail{_}: IO.die(Unit,1,"start:error")
def run(mode: String) -> IO(Unit):
  do IO<Unit>:
    +input : C.Callback<String,Unit> <- C.create(~Unit,~String,~Unit,~onInput,Unit{})
    +resize : C.Callback<Unit,Unit> <- C.create(~Unit,~Unit,~Unit,~onResize,Unit{})
    result : Result<&2,&1,T.Error,T.ProcessTerminal> <- T.startProcess(input,resize)
    started(mode,result)
    C.dispose(String,Unit,input)
    C.dispose(Unit,Unit,resize)
def runCycles(left: Nat) -> IO(Unit):
  match left:
    case Zero{}: IO.pure(Unit,Unit{})
    case Succ{rest}:
      do IO<Unit>:
        run("cycle")
        runCycles(rest)
def cycles() -> IO(Unit):
  do IO<Unit>:
    run("cycle")
    IO.print_err("fds-start")
    sleep(150)
    runCycles(100n)
    IO.print_err("fds-end")
    sleep(150)
def arguments(values: List<String>) -> IO(Unit):
  match values:
    case "restore-retry" <> _:
      do IO<Unit>:
        run("cycle")
        run("hold")
    case "cycles" <> _: cycles()
    case mode <> _: run(mode)
    case _: run("hold")
def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
