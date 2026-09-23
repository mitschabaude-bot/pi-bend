import Base

def unit(result: Result<&1,&1,U32 & String,Unit>) -> String:
  match result:
    case Done{_}: "ok"
    case Fail{(code,_)}: "error:" ++ U32.show(code)

def status(result: Result<&1,&1,U32 & String,ProcessStatus>) -> String:
  match result:
    case Fail{(code,_)}: "error:" ++ U32.show(code)
    case Done{ProcessExited{code}}: "exit:" ++ U32.show(code)
    case Done{ProcessSignalled{signal}}: "signal:" ++ U32.show(signal)

def boolean(result: Result<&1,&1,U32 & String,Bool>) -> String:
  match result:
    case Fail{(code,_)}: "error:" ++ U32.show(code)
    case Done{value}: Bool.show(value)

def written(result: Result<&1,&1,U32 & String,U32>) -> String:
  match result:
    case Fail{(code,_)}: "error:" ++ U32.show(code)
    case Done{count}: "count:" ++ U32.show(count)

def repeatedByte(count: Nat) -> List<&2,U32>:
  match count:
    case 0n: []
    case 1n+rest: 65 <> repeatedByte(rest)

def inputBytes(mode: String) -> List<&2,U32>:
  match mode:
    case "large-input": repeatedByte(65536n)
    case "cancel-write": repeatedByte(65536n)
    case "oversize-input": repeatedByte(65537n)
    case "invalid-byte": [256]
    case _: [65,0,255,10]

def numbers(bytes: List<&2,U32>) -> List<&2,String>:
  match bytes:
    case Nil{}: Nil{}
    case head <> rest: U32.show(head) <> numbers(rest)

def showBytes(result: Result<&1,&1,U32 & String,List<&2,U32>>) -> String:
  match result:
    case Fail{(code,_)}: "error:" ++ U32.show(code)
    case Done{bytes}: "bytes:" ++ String.join(numbers(bytes),",")

def drainResult(next: Pipe -> String -> IO(Pipe & String), acc: String, pair: Pipe & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Pipe & String):
  match pair:
    case (owner,Fail{(code,_)}): IO.pure(Pipe & String,(owner,acc ++ "error:" ++ U32.show(code)))
    case (owner,Done{Nil{}}): IO.pure(Pipe & String,(owner,acc))
    case (owner,Done{bytes}): next(owner,acc ++ String.join(numbers(bytes),",") ++ ";")

law drain:
  Nat -> Pipe -> String -> IO(Pipe & String)
def drain(fuel,owner,acc):
  match fuel:
    case 0n: IO.pure(Pipe & String,(owner,"exhausted"))
    case 1n+rest:
      IO.bind(Pipe & Result<&1,&1,U32 & String,List<&2,U32>>,Pipe & String,Pipe.read(owner,65536),drainResult(p => s => drain(rest,p,s),acc))

def cancelLater(+control: PipeCancel) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(20)
    cancelled : Bool <- Pipe.cancel(control)
    again : Bool <- Pipe.cancel(control)
    IO.print("cancel:" ++ Bool.show(cancelled) ++ ":" ++ Bool.show(again))

def killLater(control: ProcessControl) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(30)
    result : Result<&1,&1,U32 & String,Bool> <- Process.signal(control,9)
    IO.print("kill:" ++ boolean(result))

def reused(+old: ProcessControl,+oldInput: PipeCancel,+oldOutput: PipeCancel,+oldError: PipeCancel,result: Result<&1,&1,U32 & String,Process & ProcessControl & (Pipe & PipeCancel) & (Pipe & PipeCancel) & (Pipe & PipeCancel)>) -> IO(Unit):
  match result:
    case Fail{(code,_)}: IO.print("reuse-error:" ++ U32.show(code))
    case Done{(process,(_,((input,_),((output,_),(error,_)))))}:
      do IO<Unit>:
        stale : Result<&1,&1,U32 & String,Bool> <- Process.signal(old,9)
        inputStale : Bool <- Pipe.cancel(oldInput)
        outputStale : Bool <- Pipe.cancel(oldOutput)
        errorStale : Bool <- Pipe.cancel(oldError)
        IO.print("reuse:" ++ boolean(stale) ++ ":" ++ Bool.show(inputStale) ++ ":" ++ Bool.show(outputStale) ++ ":" ++ Bool.show(errorStale))
        first : Result<&1,&1,U32 & String,Unit> <- Pipe.close_checked(input)
        second : Result<&1,&1,U32 & String,Unit> <- Pipe.close_checked(output)
        third : Result<&1,&1,U32 & String,Unit> <- Pipe.close_checked(error)
        closed : Result<&1,&1,U32 & String,Unit> <- Process.close_checked(process)
        IO.print("reuse-close:" ++ unit(first) ++ ":" ++ unit(second) ++ ":" ++ unit(third) ++ ":" ++ unit(closed))

def retired(+control: ProcessControl, +inputCancel: PipeCancel, +outputCancel: PipeCancel, +errorCancel: PipeCancel, output: Pipe, error: Pipe, pair: Process & Result<&1,&1,U32 & String,ProcessStatus>) -> IO(Unit):
  match pair:
    case (process,ended):
      do IO<Unit>:
        IO.print("again:" ++ status(ended))
        outputClosed : Result<&1,&1,U32 & String,Unit> <- Pipe.close_checked(output)
        errorClosed : Result<&1,&1,U32 & String,Unit> <- Pipe.close_checked(error)
        closed : Result<&1,&1,U32 & String,Unit> <- Process.close_checked(process)
        IO.print("close:" ++ unit(outputClosed) ++ ":" ++ unit(errorClosed) ++ ":" ++ unit(closed))
        stale : Result<&1,&1,U32 & String,Bool> <- Process.signal(control,9)
        staleInput : Bool <- Pipe.cancel(inputCancel)
        staleOutput : Bool <- Pipe.cancel(outputCancel)
        staleError : Bool <- Pipe.cancel(errorCancel)
        IO.print("stale:" ++ boolean(stale) ++ ":" ++ Bool.show(staleInput) ++ ":" ++ Bool.show(staleOutput) ++ ":" ++ Bool.show(staleError))
        fresh : Result<&1,&1,U32 & String,Process & ProcessControl & (Pipe & PipeCancel) & (Pipe & PipeCancel) & (Pipe & PipeCancel)> <- Process.spawn("/bin/true",[],"/",[])
        reused(control,inputCancel,outputCancel,errorCancel,fresh)

def waited(control: ProcessControl,inputCancel: PipeCancel,outputCancel: PipeCancel,errorCancel: PipeCancel,output: Pipe,error: Pipe,pair: Process & Result<&1,&1,U32 & String,ProcessStatus>) -> IO(Unit):
  match pair:
    case (process,ended):
      do IO<Unit>:
        IO.print(status(ended))
        again : Process & Result<&1,&1,U32 & String,ProcessStatus> <- Process.wait(process)
        retired(control,inputCancel,outputCancel,errorCancel,output,error,again)

def stderrDrained(process: Process,control: ProcessControl,inputCancel: PipeCancel,outputCancel: PipeCancel,errorCancel: PipeCancel,output: Pipe,pair: Pipe & String) -> IO(Unit):
  match pair:
    case (error,text):
      do IO<Unit>:
        IO.print("stderr:" ++ text)
        ended : Process & Result<&1,&1,U32 & String,ProcessStatus> <- Process.wait(process)
        waited(control,inputCancel,outputCancel,errorCancel,output,error,ended)

def stdoutDrained(process: Process,control: ProcessControl,inputCancel: PipeCancel,outputCancel: PipeCancel,errorCancel: PipeCancel,errorTask: Chan(Pipe & String),pair: Pipe & String) -> IO(Unit):
  match pair:
    case (output,text):
      do IO<Unit>:
        IO.print("stdout:" ++ text)
        stderr : Pipe & String <- IO.join(Pipe & String,errorTask)
        stderrDrained(process,control,inputCancel,outputCancel,errorCancel,output,stderr)

def leaderExited(control: ProcessControl,inputCancel: PipeCancel,outputCancel: PipeCancel,errorCancel: PipeCancel,outputTask: Chan(Pipe & String),errorTask: Chan(Pipe & String),pair: Process & Result<&1,&1,U32 & String,ProcessStatus>) -> IO(Unit):
  match pair:
    case (process,ended):
      do IO<Unit>:
        IO.print("leader:" ++ status(ended))
        stdout : Pipe & String <- IO.join(Pipe & String,outputTask)
        stdoutDrained(process,control,inputCancel,outputCancel,errorCancel,errorTask,stdout)

def finishInput(+mode: String,process: Process,+control: ProcessControl,inputCancel: PipeCancel,+outputCancel: PipeCancel,errorCancel: PipeCancel,output: Pipe,error: Pipe,pair: Pipe & Result<&1,&1,U32 & String,U32>) -> IO(Unit):
  match pair:
    case (input,result):
      do IO<Unit>:
        IO.print("write:" ++ written(result))
        inputClosed : Result<&1,&1,U32 & String,Unit> <- Pipe.close_checked(input)
        IO.print("input-close:" ++ unit(inputClosed))
        Bool.pick(IO(Unit),String.eq(mode,"cancel"),IO.spawn(Unit,cancelLater(outputCancel)),IO.pure(Unit,Unit{}))
        Bool.pick(IO(Unit),String.eq(mode,"kill"),IO.spawn(Unit,killLater(control)),IO.pure(Unit,Unit{}))
        outputTask : Chan(Pipe & String) <- IO.fork(Pipe & String,drain(32n,output,""))
        errorTask : Chan(Pipe & String) <- IO.fork(Pipe & String,drain(32n,error,""))
        ended : Process & Result<&1,&1,U32 & String,ProcessStatus> <- Process.wait(process)
        leaderExited(control,inputCancel,outputCancel,errorCancel,outputTask,errorTask,ended)

def writeAgain(cancel: Bool,process: Process,control: ProcessControl,+inputCancel: PipeCancel,outputCancel: PipeCancel,errorCancel: PipeCancel,output: Pipe,error: Pipe,pair: Pipe & Result<&1,&1,U32 & String,U32>) -> IO(Unit):
  match pair:
    case (input,result):
      do IO<Unit>:
        IO.print("first-write:" ++ written(result))
        Bool.pick(IO(Unit),cancel,IO.spawn(Unit,cancelLater(inputCancel)),IO.pure(Unit,Unit{}))
        again : Pipe & Result<&1,&1,U32 & String,U32> <- Pipe.write(input,repeatedByte(65536n))
        finishInput("normal",process,control,inputCancel,outputCancel,errorCancel,output,error,again)

def inputWritten(mode: String,process: Process,control: ProcessControl,inputCancel: PipeCancel,outputCancel: PipeCancel,errorCancel: PipeCancel,output: Pipe,error: Pipe,pair: Pipe & Result<&1,&1,U32 & String,U32>) -> IO(Unit):
  match mode:
    case "cancel-write": writeAgain(True{},process,control,inputCancel,outputCancel,errorCancel,output,error,pair)
    case "partial-write": writeAgain(False{},process,control,inputCancel,outputCancel,errorCancel,output,error,pair)
    case mode: finishInput(mode,process,control,inputCancel,outputCancel,errorCancel,output,error,pair)

def execute(+mode: String,result: Result<&1,&1,U32 & String,Process & ProcessControl & (Pipe & PipeCancel) & (Pipe & PipeCancel) & (Pipe & PipeCancel)>) -> IO(Unit):
  match result:
    case Fail{(code,_)}: IO.print("spawn-error:" ++ U32.show(code))
    case Done{(process,(control,((input,inputCancel),((output,outputCancel),(error,errorCancel)))))}:
      do IO<Unit>:
        Bool.pick(IO(Unit),String.eq(mode,"broken-input"),IO.sleep(40),IO.pure(Unit,Unit{}))
        written : Pipe & Result<&1,&1,U32 & String,U32> <- Pipe.write(input,inputBytes(mode))
        inputWritten(mode,process,control,inputCancel,outputCancel,errorCancel,output,error,written)

def repeated(count: Nat,+path: String,+cwd: String,+command: String) -> IO(Unit):
  match count:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      do IO<Unit>:
        result : Result<&1,&1,U32 & String,Process & ProcessControl & (Pipe & PipeCancel) & (Pipe & PipeCancel) & (Pipe & PipeCancel)> <- Process.spawn(path,["-c",command],cwd,[])
        execute("normal",result)
        repeated(rest,path,cwd,command)

def launch(mode: String,path: String,cwd: String,command: String,inherited: List<String>) -> IO(Result<&1,&1,U32 & String,Process & ProcessControl & (Pipe & PipeCancel) & (Pipe & PipeCancel) & (Pipe & PipeCancel)>):
  match mode:
    case "nul-path": Process.spawn(path ++ SCon{Chr{0},""},["-c",command],cwd,[])
    case "nul-cwd": Process.spawn(path,["-c",command],cwd ++ SCon{Chr{0},""},[])
    case "nul-argv": Process.spawn(path,["-c",command ++ SCon{Chr{0},""}],cwd,[])
    case "nul-env": Process.spawn(path,["-c",command],cwd,["X=" ++ SCon{Chr{0},""}])
    case "invalid-env": Process.spawn(path,["-c",command],cwd,["NO_EQUALS"])
    case "empty-key": Process.spawn(path,["-c",command],cwd,["=value"])
    case "inherit": Process.spawn(path,["-c",command],cwd,inherited)
    case _: Process.spawn(path,["-c",command],cwd,["TEST_VALUE=hello spaces","PATH=/usr/bin:/bin"])

def runOnce(+mode: String,path: String,cwd: String,command: String) -> IO(Unit):
  do IO<Unit>:
    environment : List<String> <- IO.environment()
    result : Result<&1,&1,U32 & String,Process & ProcessControl & (Pipe & PipeCancel) & (Pipe & PipeCancel) & (Pipe & PipeCancel)> <- launch(mode,path,cwd,command,environment)
    execute(mode,result)

def run(args: List<String>) -> IO(Unit):
  match args:
    case "repeat" <> path <> cwd <> command <> Nil{}: repeated(128n,path,cwd,command)
    case mode <> path <> cwd <> command <> Nil{}: runOnce(mode,path,cwd,command)
    case _: IO.die(Unit,1,"usage: MODE SHELL CWD COMMAND")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
