import Base
import ./process-primitive.bend as P

def ended(pair: Process & Result<&1,&1,U32 & String,ProcessStatus>) -> IO(Unit):
  match pair:
    case (owner,result):
      do IO<Unit>:
        IO.print(P.status(result))
        closed : Result<&1,&1,U32 & String,Unit> <- Process.close_checked(owner)
        IO.print("process-close:" ++ P.unit(closed))

def errorDrained(owner: Process, output: Pipe, pair: Pipe & String) -> IO(Unit):
  match pair:
    case (error,text):
      do IO<Unit>:
        IO.print("stderr:" ++ text)
        a : Result<&1,&1,U32 & String,Unit> <- Pipe.close_checked(output)
        b : Result<&1,&1,U32 & String,Unit> <- Pipe.close_checked(error)
        IO.print("pipes-close:" ++ P.unit(a) ++ ":" ++ P.unit(b))
        result : Process & Result<&1,&1,U32 & String,ProcessStatus> <- Process.wait(owner)
        ended(result)

def outputDrained(owner: Process, task: Chan(Pipe & String), pair: Pipe & String) -> IO(Unit):
  match pair:
    case (output,text):
      do IO<Unit>:
        IO.print("stdout:" ++ text)
        other : Pipe & String <- IO.join(Pipe & String,task)
        errorDrained(owner,output,other)

def spawned(result: Result<&1,&1,U32 & String,Process & ProcessControl & (Pipe & PipeCancel) & (Pipe & PipeCancel)>) -> IO(Unit):
  match result:
    case Fail{(code,_)}: IO.print("spawn-error:" ++ U32.show(code))
    case Done{(owner,(_,((output,_),(error,_))))}:
      do IO<Unit>:
        task : Chan(Pipe & String) <- IO.fork(Pipe & String,P.drain(32n,error,""))
        bytes : Pipe & String <- P.drain(32n,output,"")
        outputDrained(owner,task,bytes)

def repeat(count: Nat,+path: String,+cwd: String,+command: String) -> IO(Unit):
  match count:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      do IO<Unit>:
        env : List<String> <- IO.environment()
        result : Result<&1,&1,U32 & String,Process & ProcessControl & (Pipe & PipeCancel) & (Pipe & PipeCancel)> <- Process.spawn_null_stdin(path,["-c",command],cwd,env)
        spawned(result)
        repeat(rest,path,cwd,command)

def run(args: List<String>) -> IO(Unit):
  match args:
    case path <> cwd <> command <> Nil{}: repeat(1n,path,cwd,command)
    case path <> cwd <> command <> count <> Nil{}: repeat(Maybe.default(&2,Nat,Nat.read(count),0n),path,cwd,command)
    case _: IO.die(Unit,1,"usage: SHELL CWD COMMAND [COUNT]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
