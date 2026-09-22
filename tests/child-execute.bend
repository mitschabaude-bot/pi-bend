import Base
import ../packages/coding-agent/src/utils/child-process.bend as Child
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/base64.bend as B64

def encoded(result: Result<&2,&2,B64.Error,String>) -> String:
  match result:
    case Done{value}: value
    case Fail{_}: "invalid"

def output(mode: String, bytes: List<&2,U32>) -> IO(Result<&2,&2,String,Unit>):
  +choice = mode
  do IO<Result<&2,&2,String,Unit>>:
    IO.print("data " ++ encoded(B64.encode(bytes)))
    Bool.pick(IO(Unit),String.eq(choice,"both"),IO.sleep(80),IO.pure(Unit,Unit{}))
    return Bool.pick(Result<&2,&2,String,Unit>,String.eq(choice,"fail"),Fail{"consumer failed"},Done{Unit{}})

def describe(errors: List<&2,Child.Error>) -> String:
  match errors:
    case Nil{}: ""
    case Child.Error{operation,code,message} <> rest: operation ++ ":" ++ U32.show(code) ++ ":" ++ message ++ ";" ++ describe(rest)

def result(value: Result<&2,&2,Child.ExecutionError,U32>) -> String:
  match value:
    case Done{code}: "exit:" ++ U32.show(code)
    case Fail{Child.InvalidTimeout{}}: "invalid-timeout"
    case Fail{Child.ExecutionAborted{}}: "aborted"
    case Fail{Child.ExecutionTimedOut{}}: "timeout"
    case Fail{Child.ExecutionFailed{errors}}: "failed:" ++ describe(errors)

def timeout(text: String) -> Maybe<&2,F64>:
  match text:
    case "none": None{}
    case "nan": Some{F64{2146959360,0}}
    case "inf": Some{F64{2146435072,0}}
    case "-inf": Some{F64{4293918720,0}}
    case text: F64.read(text)

def milliseconds(value: Result<&2,&2,Child.ExecutionError,Maybe<&2,U32>>) -> String:
  match value:
    case Fail{_}: "invalid"
    case Done{None{}}: "none"
    case Done{Some{word}}: U32.show(word)

def abortAfter(controller: A.AbortController<Unit>, milliseconds: U32) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(milliseconds)
    won : Bool <- A.abort(Unit,controller,None{})
    return Unit{}

def scheduled(mode: String, controller: A.AbortController<Unit>, milliseconds: U32) -> IO(Maybe<&2,Chan(Unit)>):
  match mode:
    case "preabort":
      do IO<Maybe<&2,Chan(Unit)>>:
        won : Bool <- A.abort(Unit,controller,None{})
        return None{}
    case "abort":
      do IO<Maybe<&2,Chan(Unit)>>:
        task : Chan(Unit) <- IO.fork(Unit,abortAfter(controller,milliseconds))
        return Some{task}
    case "stdin-abort":
      do IO<Maybe<&2,Chan(Unit)>>:
        task : Chan(Unit) <- IO.fork(Unit,abortAfter(controller,milliseconds))
        return Some{task}
    case "both":
      do IO<Maybe<&2,Chan(Unit)>>:
        task : Chan(Unit) <- IO.fork(Unit,abortAfter(controller,milliseconds))
        return Some{task}
    case _: IO.pure(Maybe<&2,Chan(Unit)>,None{})

def joinAbort(task: Maybe<&2,Chan(Unit)>) -> IO(Unit):
  match task:
    case None{}: IO.pure(Unit,Unit{})
    case Some{channel}: IO.join(Unit,channel)

def invoke(stdin: Bool, shell: String, command: String, cwd: String, env: List<String>, signal: Maybe<&2,A.AbortSignal<Unit>>, timeout: Maybe<&2,F64>, callback: C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>) -> IO(Result<&2,&2,Child.ExecutionError,U32>):
  match stdin:
    case True{}: Child.executeStdin(shell,[],command,cwd,env,signal,timeout,callback)
    case False{}: Child.execute(shell,["-c"],command,cwd,env,signal,timeout,callback)

def stdinMode(+mode: String) -> Bool: String.eq(mode,"stdin") || String.eq(mode,"stdin-abort")

def repeat(count: Nat,+mode: String,+seconds: String,+delay: U32,+shell: String,+cwd: String,+command: String) -> IO(Unit):
  match count:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      do IO<Unit>:
        +controller : A.AbortController<Unit> <- A.new(Unit)
        task : Maybe<&2,Chan(Unit)> <- scheduled(mode,controller,delay)
        +callback : C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>> <- C.create(~String,~List<&2,U32>,~Result<&2,&2,String,Unit>,~output,mode)
        env : List<String> <- IO.environment()
        completed : Result<&2,&2,Child.ExecutionError,U32> <- invoke(stdinMode(mode),shell,command,cwd,env,Bool.pick(Maybe<&2,A.AbortSignal<Unit>>,String.eq(mode,"no-signal"),None{},Some{A.signal(Unit,controller)}),timeout(seconds),callback)
        IO.print("result " ++ result(completed))
        joinAbort(task)
        C.dispose(List<&2,U32>,Result<&2,&2,String,Unit>,callback)
        A.dispose(Unit,controller)
        repeat(rest,mode,seconds,delay,shell,cwd,command)

def run(args: List<String>) -> IO(Unit):
  match args:
    case "quantize" <> seconds <> Nil{}: IO.print(milliseconds(Child.optionalTimeout(timeout(seconds))))
    case mode <> seconds <> delay <> shell <> cwd <> command <> count <> Nil{}: repeat(Maybe.default(&2,Nat,Nat.read(count),0n),mode,seconds,Maybe.default(&2,U32,U32.read(delay),0),shell,cwd,command)
    case _: IO.die(Unit,1,"usage: MODE TIMEOUT ABORT_MS SHELL CWD COMMAND COUNT")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
