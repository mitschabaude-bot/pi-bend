import Base
import ../packages/coding-agent/src/core/bash-executor.bend as Executor
import ../packages/coding-agent/src/core/tools/bash.bend as Bash
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/string.bend as Strings
import ../packages/runtime/test/utf8-runner.bend as Wire
import ./tool-truncate.bend as Text

type Context is Data:
  Context{mode: String, chunks: List<&2,List<&2,U32>>, exit: String, retained: Ref.Ref<Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>>>, seen: Ref.Ref<List<&2,String>>, ready: Chan(Unit), controller: Abort.AbortController<Unit>}

def appendAll(+callback: C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>, chunks: List<&2,List<&2,U32>>) -> IO(Unit):
  match chunks:
    case Nil{}: IO.pure(Unit,Unit{})
    case chunk <> rest:
      do IO<Unit>:
        result : Result<&2,&2,String,Unit> <- C.call(List<&2,U32>,Result<&2,&2,String,Unit>,callback,chunk)
        appendAll(callback,rest)

def code(exit: String) -> Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>:
  match exit:
    case "fail": Fail{Bash.Operation{"injected failure"}}
    case "none": Done{None{}}
    case value: Done{Some{Wire.decimal(value,0)}}

def completed(+mode: String, exit: String, controller: Abort.AbortController<Unit>, ready: Chan(Unit)) -> IO(Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>):
  do IO<Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>>:
    Bool.pick(Unit -> IO(Unit),String.eq(mode,"reentry"),_ => do IO<Unit>:
      signal : Maybe<&1,Unit> <- Chan.recv(Unit,ready)
      return Unit{},_ => IO.pure(Unit,Unit{}))(Unit{})
    cancelled : Bool <- Bool.pick(Unit -> IO(Bool),String.eq(mode,"cancel"),_ => Abort.abort(Unit,controller,None{}),_ => IO.pure(Bool,False{}))(Unit{})
    return code(exit)

def injected(context: Context, input: Bash.BashExecutionInput) -> IO(Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>):
  match context input:
    case Context{mode,chunks,exit,retained,_,ready,controller} Bash.BashExecutionInput{_,_,+callback,_,_,_}:
      do IO<Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>>:
        Ref.modify(Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>>,Unit,retained,_ => (Some{callback},Unit{}))
        appendAll(callback,chunks)
        completed(mode,exit,controller,ready)

def repeatChunk(n: Nat, +chunk: List<&2,U32>, reversed: List<&2,List<&2,U32>>) -> List<&2,List<&2,U32>>:
  match n:
    case 0n: reversed
    case 1n+n: repeatChunk(n,chunk,chunk <> reversed)

def late(retained: Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>>, count: Nat) -> IO(Unit):
  match retained:
    case None{}: IO.die(Unit,1,"missing retained callback")
    case Some{callback}: appendAll(callback,repeatChunk(count,Utf8.encode("R"),Nil{}))

def observed(context: Context, text: String) -> IO(Unit):
  match context:
    case Context{+mode,_,_,retained,seen,ready,_}:
      do IO<Unit>:
        first : Bool <- Ref.modify(List<&2,String>,Bool,seen,+previous => (text <> previous,List.is_empty(&2,String,previous)))
        Bool.pick(Unit -> IO(Unit),String.eq(mode,"reentry") && first,_ => do IO<Unit>:
          callback : Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>> <- Ref.read(Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>>,retained)
          late(callback,1000n)
          sent : Bool <- Chan.send(Unit,ready,Unit{})
          return Unit{},_ => IO.pure(Unit,Unit{}))(Unit{})

def result(value: Result<&2,&2,Executor.Error,Executor.BashResult>) -> String:
  match value:
    case Done{Executor.BashResult{text,exit,cancelled,truncated,path}}:
      String.join(["ok",Wire.showText(text),Maybe.default(&2,String,Maybe.map(&2,U32,String,U32.show,exit),"none"),Text.boolean(cancelled),Text.boolean(truncated),Maybe.default(&2,String,Maybe.map(&2,String,String,Wire.showText,path),"none")],"|")
    case Fail{Executor.Execution{cause}}: "exec|" ++ Wire.showText(Executor.errorMessage(Executor.Execution{cause}))
    case Fail{Executor.OutputFailure{cause}}: "output|" ++ Wire.showText(Executor.errorMessage(Executor.OutputFailure{cause}))
    case Fail{Executor.ExecutionAndOutput{cause,output}}: "both|" ++ Wire.showText(Bash.operationMessage(cause)) ++ "|" ++ Wire.showText(Bash.outputMessage(output))

def called(+context: Context, operations: Bash.BashOperations, options: Executor.BashExecutorOptions, pair: Executor.ExecutorOwner & Executor.ExecutorHandle) -> IO(Unit):
  match context pair:
    case Context{_,_,_,retained,seen,_,_} Tuple{owner,handle}:
      do IO<Unit>:
        value : Result<&2,&2,Executor.Error,Executor.BashResult> <- Executor.executeBashWithOperations(handle,"injected",".",operations,options)
        IO.print(result(value))
        callback : Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>> <- Ref.read(Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>>,retained)
        late(callback,1n)
        texts : List<&2,String> <- Ref.read(List<&2,String>,seen)
        IO.print("chunks|" ++ Wire.showText(String.join(List.reverse(&2,String,texts),"")))
        Executor.disposeExecutor(owner)

def rawBytes(parts: List<&2,String>, reversed: List<&2,U32>) -> List<&2,U32>:
  match parts:
    case Nil{}: List.reverse(&2,U32,reversed)
    case "" <> rest: rawBytes(rest,reversed)
    case value <> rest: rawBytes(rest,Wire.decimal(value,0) <> reversed)

def chunks(values: List<&2,String>) -> List<&2,List<&2,U32>>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: rawBytes(Strings.split(value,','),Nil{}) <> chunks(rest)

def runCase(+mode: String, exit: String, bytes: List<&2,List<&2,U32>>) -> IO(Unit):
  do IO<Unit>:
    +retained : Ref.Ref<Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>>> <- Ref.new(Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>>,None{})
    +seen : Ref.Ref<List<&2,String>> <- Ref.new(List<&2,String>,Nil{})
    +ready : Chan(Unit) <- Chan.new(Unit,1)
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    +context : Context = Context{mode,bytes,exit,retained,seen,ready,controller}
    +exec : C.Callback<Bash.BashExecutionInput,Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>> <- C.create(~Context,~Bash.BashExecutionInput,~Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>,~injected,context)
    +observer : C.Callback<String,Unit> <- C.create(~Context,~String,~Unit,~observed,context)
    owner : Executor.ExecutorOwner <- Executor.createExecutor()
    called(context,Bash.BashOperations{exec},Executor.BashExecutorOptions{Bool.pick(Maybe<&2,C.Callback<String,Unit>>,String.eq(mode,"silent"),None{},Some{observer}),Some{Abort.signal(Unit,controller)}},Executor.borrowExecutor(owner))
    C.dispose(Bash.BashExecutionInput,Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>,exec)
    C.dispose(String,Unit,observer)
    callback : Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>> <- Ref.dispose(Maybe<&2,C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>>,retained)
    texts : List<&2,String> <- Ref.dispose(List<&2,String>,seen)
    Chan.close(Unit,ready)
    Abort.dispose(Unit,controller)

def nativeBorrowed(command: String, +operations: Bash.BashOperations, pair: Executor.ExecutorOwner & Executor.ExecutorHandle) -> IO(Unit):
  match pair:
    case (owner,handle):
      do IO<Unit>:
        value : Result<&2,&2,Executor.Error,Executor.BashResult> <- Executor.executeBashWithOperations(handle,command,".",operations,Executor.defaults())
        IO.print(result(value))
        IO.print("chunks|")
        Executor.disposeExecutor(owner)
        Bash.disposeOperations(operations)

def native(command: String) -> IO(Unit):
  do IO<Unit>:
    operations : Bash.BashOperations <- Bash.createLocalBashOperations("",Some{"/bin/bash"})
    owner : Executor.ExecutorOwner <- Executor.createExecutor()
    nativeBorrowed(command,operations,Executor.borrowExecutor(owner))

def run(arguments: List<String>) -> IO(Unit):
  match arguments:
    case "native" <> command <> Nil{}: native(command)
    case mode <> exit <> "lines" <> Nil{}: runCase(mode,exit,repeatChunk(3000n,Utf8.encode("line\n"),Nil{}))
    case mode <> exit <> "ansi-large" <> Nil{}: runCase(mode,exit,repeatChunk(11000n,Utf8.encode("\u{1b}[31m"),Nil{}))
    case mode <> exit <> "large" <> Nil{}: runCase(mode,exit,repeatChunk(15000n,Utf8.encode("abcd\n"),Nil{}))
    case mode <> exit <> values <> Nil{}: runCase(mode,exit,chunks(Strings.split(values,';')))
    case _: IO.die(Unit,1,"usage: MODE EXIT BYTE_CHUNKS")

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    run(arguments)
