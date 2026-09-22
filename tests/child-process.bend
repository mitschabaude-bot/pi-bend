import Base
import ../packages/coding-agent/src/utils/child-process.bend as Child
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/base64.bend as B64

def encoded(result: Result<&2,&2,B64.Error,String>) -> String:
  match result:
    case Done{value}: value
    case Fail{_}: "invalid"

def output(mode: String, bytes: List<&2,U32>) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    IO.print("data " ++ encoded(B64.encode(bytes)))
    return Bool.pick(Result<&2,&2,String,Unit>,String.eq(mode,"fail"),Fail{"consumer failed"},Done{Unit{}})

def status(value: Maybe<&2,ProcessStatus>) -> String:
  match value:
    case None{}: "none"
    case Some{ProcessExited{code}}: "exit:" ++ U32.show(code)
    case Some{ProcessSignalled{signal}}: "signal:" ++ U32.show(signal)

def printErrors(values: List<&2,Child.Error>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case Child.Error{operation,code,message} <> rest:
      do IO<Unit>:
        IO.print("error " ++ operation ++ ":" ++ U32.show(code) ++ ":" ++ message)
        printErrors(rest)

def closed(result: Result<&1,&1,U32 & String,Unit>) -> String:
  match result:
    case Done{_}: "ok"
    case Fail{(code,_)}: U32.show(code)

def finished(result: Process & Child.Report) -> IO(Unit):
  match result:
    case (owner,Child.Report{state,failed}):
      do IO<Unit>:
        IO.print("status " ++ status(state))
        printErrors(failed)
        result : Result<&1,&1,U32 & String,Unit> <- Process.close_checked(owner)
        IO.print("close " ++ closed(result))

def spawned(mode: String, result: Result<&1,&1,U32 & String,Process & ProcessControl & (Pipe & PipeCancel) & (Pipe & PipeCancel) & (Pipe & PipeCancel)>) -> IO(Unit):
  match result:
    case Fail{(code,message)}: IO.print("spawn " ++ U32.show(code) ++ ":" ++ message)
    case Done{(owner,(control,((input,_),(out,err))))}:
      do IO<Unit>:
        inputClosed : Result<&1,&1,U32 & String,Unit> <- Pipe.close_checked(input)
        IO.print("stdin " ++ closed(inputClosed))
        +callback : C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>> <- C.create(~String,~List<&2,U32>,~Result<&2,&2,String,Unit>,~output,mode)
        result : Process & Child.Report <- Child.waitForChildProcess(owner,control,out,err,callback)
        C.dispose(List<&2,U32>,Result<&2,&2,String,Unit>,callback)
        finished(result)

def repeat(count: Nat, +mode: String, +command: String) -> IO(Unit):
  match count:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      do IO<Unit>:
        env : List<String> <- IO.environment()
        result : Result<&1,&1,U32 & String,Process & ProcessControl & (Pipe & PipeCancel) & (Pipe & PipeCancel) & (Pipe & PipeCancel)> <- Process.spawn("/bin/sh",["-c",command],"/tmp",env)
        spawned(mode,result)
        repeat(rest,mode,command)

def run(args: List<String>) -> IO(Unit):
  match args:
    case mode <> command <> Nil{}: repeat(1n,mode,command)
    case mode <> command <> count <> Nil{}: repeat(Maybe.default(&2,Nat,Nat.read(count),0n),mode,command)
    case _: IO.print("usage: mode command [count]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
