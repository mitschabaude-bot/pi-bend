import Base
import ./tools/bash.bend as Bash
import ./tools/output-accumulator.bend as Output
import ./tools/truncate.bend as Truncate
import ../utils/ansi.bend as Ansi
import ../utils/shell.bend as Shell
import ../../../runtime/src/child-process.bend as Child
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/serial-resource.bend as Serial
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/deferred.bend as Deferred
import ../../../runtime/src/abort.bend as Abort

type BashExecutorOptions is Data:
  BashExecutorOptions{onChunk: Maybe<&2,C.Callback<String,Unit>>, signal: Maybe<&2,Abort.AbortSignal<Unit>>}
type BashResult is Data:
  BashResult{output: String, exitCode: Maybe<&2,U32>, cancelled: Bool, truncated: Bool, fullOutputPath: Maybe<&2,String>}
type Error is Data:
  Execution{cause: Bash.OperationError}
  OutputFailure{cause: Output.Error}
  ExecutionAndOutput{execution: Bash.OperationError, output: Output.Error}

def errorMessage(cause: Error) -> String:
  match cause:
    case Execution{failure}: Bash.operationMessage(failure)
    case OutputFailure{failure}: Bash.outputMessage(failure)
    case ExecutionAndOutput{failure,output}: Bash.operationMessage(failure) ++ "; output: " ++ Bash.outputMessage(output)

type State is Data:
  State{decoder: Utf8.Decoder, ansi: Ansi.Scanner, raw: Nat, accepting: Bool, failure: Maybe<&2,Output.Error>, chunks: List<&2,String>, wake: Maybe<&2,Deferred.Deferred<Unit>>}
type Run is Type: Run{accumulator: Output.OutputAccumulator, state: State}
type Consumer is Type:
  Consumer{gate: Serial.Owner<Maybe<&1,Run>>, callback: C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>>}
type ExecutorOwner is Type: ExecutorOwner{consumers: Ref.Ref<List<&1,Consumer>>}
type ExecutorHandle is Data: ExecutorHandle{consumers: Ref.Ref<List<&1,Consumer>>}
type Publication is Data: Publication{chunks: List<&2,String>, wake: Maybe<&2,Deferred.Deferred<Unit>>}

def defaults() -> BashExecutorOptions: BashExecutorOptions{None{},None{}}
def createExecutor() -> IO(ExecutorOwner):
  do IO<ExecutorOwner>:
    registry : Ref.Ref<List<&1,Consumer>> <- Ref.new(List<&1,Consumer>,Nil{})
    return ExecutorOwner{registry}

def borrowExecutor(owner: ExecutorOwner) -> ExecutorOwner & ExecutorHandle:
  match owner:
    case ExecutorOwner{+registry}: (ExecutorOwner{registry},ExecutorHandle{registry})

def ansiFeed(value: String, scanner: Ansi.Scanner) -> Ansi.Scanner:
  match value:
    case SNil{}: scanner
    case SCon{character,rest}: ansiFeed(rest,Ansi.advance(character,scanner))

def removeCR(value: String, reversed: String) -> String:
  match value:
    case SNil{}: String.reverse(reversed)
    case SCon{Chr{13},rest}: removeCR(rest,reversed)
    case SCon{character,rest}: removeCR(rest,SCon{character,reversed})

def sanitized(value: String) -> String: removeCR(Shell.sanitizeBinaryOutput(value),"")

def notify(wake: Maybe<&2,Deferred.Deferred<Unit>>) -> IO(Unit):
  match wake:
    case None{}: IO.pure(Unit,Unit{})
    case Some{signal}:
      do IO<Unit>:
        settled : Bool <- Deferred.resolve(Unit,signal,Unit{})
        return Unit{}

def remember(previous: Maybe<&2,Output.Error>, result: Result<&2,&2,Output.Error,Unit>) -> Maybe<&2,Output.Error>:
  match previous result:
    case Some{cause} _: Some{cause}
    case None{} Fail{cause}: Some{cause}
    case None{} Done{Unit{}}: None{}

def appended(state: State, +text: String, outcome: Output.Outcome<Unit>) -> IO(Run):
  match state outcome:
    case State{decoder,ansi,raw,accepting,failure,+chunks,+wake} Output.Outcome{accumulator,result}:
      do IO<Run>:
        notify(wake)
        return Run{accumulator,State{decoder,ansi,raw,accepting,remember(failure,result),Bool.pick(List<&2,String>,Maybe.is_some(&2,Deferred.Deferred<Unit>,wake),text <> chunks,chunks),wake}}

def spilling(raw: Nat, outcome: Output.Outcome<Unit>) -> IO(Output.Outcome<Unit>):
  match outcome:
    case Output.Outcome{accumulator,Done{Unit{}}}:
      Bool.pick(Output.OutputAccumulator -> IO(Output.Outcome<Unit>),Nat.is_gt(raw,Truncate.DEFAULT_MAX_BYTES()),Output.ensureTempFile,
        accumulator => IO.pure(Output.Outcome<Unit>,Output.Outcome{accumulator,Done{Unit{}}}))(accumulator)
    case outcome: IO.pure(Output.Outcome<Unit>,outcome)

def rawCount(state: State) -> Nat:
  match state:
    case State{_,_,raw,_,_,_,_}: raw

def appendText(+state: State, +text: String, accumulator: Output.OutputAccumulator) -> IO(Run):
  do IO<Run>:
    added : Output.Outcome<Unit> <- Output.append(Utf8.encode(text),accumulator)
    persisted : Output.Outcome<Unit> <- spilling(rawCount(state),added)
    appended(state,text,persisted)

def emitted(state: State, scanner: Ansi.Scanner) -> State & String:
  match state scanner:
    case State{decoder,_,raw,accepting,failure,chunks,wake} Ansi.Scanner{mode,pending,reversed}:
      (State{decoder,Ansi.Scanner{mode,pending,""},raw,accepting,failure,chunks,wake},sanitized(String.reverse(reversed)))

def decodedState(state: State, decoded: Utf8.Decoded) -> State & String:
  match state decoded:
    case State{_,+ansi,raw,accepting,failure,chunks,wake} Utf8.Decoded{decoder,text}:
      emitted(State{decoder,ansi,raw,accepting,failure,chunks,wake},ansiFeed(text,ansi))

def decodedBytes(bytes: List<&2,U32>, size: Nat, state: State) -> State & String:
  match state:
    case State{+decoder,ansi,raw,accepting,failure,chunks,wake}:
      decodedState(State{decoder,ansi,raw + size,accepting,failure,chunks,wake},Utf8.decode(decoder,bytes))

def appendDecoded(accumulator: Output.OutputAccumulator, pair: State & String) -> IO(Run):
  match pair:
    case (state,text): appendText(state,text,accumulator)

def failedState(state: State, cause: Output.Error) -> State:
  match state:
    case State{decoder,ansi,raw,accepting,failure,chunks,wake}: State{decoder,ansi,raw,accepting,remember(failure,Fail{cause}),chunks,wake}

def accepted(bytes: List<&2,U32>, run: Run, valid: Result<&2,&2,Output.Error,Nat>) -> IO(Run):
  match run valid:
    case Run{accumulator,state} Fail{cause}: IO.pure(Run,Run{accumulator,failedState(state,cause)})
    case Run{accumulator,state} Done{size}: appendDecoded(accumulator,decodedBytes(bytes,size,state))

def callbackResult(failure: Maybe<&2,Output.Error>) -> Result<&2,&2,String,Unit>:
  match failure:
    case None{}: Done{Unit{}}
    case Some{cause}: Fail{Bash.outputMessage(cause)}

def retained(run: Run) -> Maybe<&1,Run> & Result<&2,&2,String,Unit>:
  match run:
    case Run{accumulator,State{decoder,ansi,raw,accepting,+failure,chunks,wake}}:
      (Some{Run{accumulator,State{decoder,ansi,raw,accepting,failure,chunks,wake}}},callbackResult(failure))

def appendLocked(+bytes: List<&2,U32>, value: Maybe<&1,Run>) -> IO(Maybe<&1,Run> & Result<&2,&2,String,Unit>):
  match value:
    case None{}: IO.pure(Maybe<&1,Run> & Result<&2,&2,String,Unit>,(None{},Done{Unit{}}))
    case Some{Run{accumulator,State{decoder,ansi,raw,False{},failure,chunks,wake}}}:
      IO.pure(Maybe<&1,Run> & Result<&2,&2,String,Unit>,(Some{Run{accumulator,State{decoder,ansi,raw,False{},failure,chunks,wake}}},Done{Unit{}}))
    case Some{run}:
      do IO<Maybe<&1,Run> & Result<&2,&2,String,Unit>>:
        next : Run <- accepted(bytes,run,Output.usedRaw(bytes,0n))
        return retained(next)

def onData(gate: Serial.Handle<Maybe<&1,Run>>, bytes: List<&2,U32>) -> IO(Result<&2,&2,String,Unit>):
  Serial.run(Maybe<&1,Run>,Result<&2,&2,String,Unit>,gate,value => appendLocked(bytes,value))

def disposeWake(wake: Maybe<&2,Deferred.Deferred<Unit>>) -> IO(Unit):
  match wake:
    case None{}: IO.pure(Unit,Unit{})
    case Some{signal}: Deferred.dispose(Unit,signal)

def newWake(enabled: Bool) -> IO(Maybe<&2,Deferred.Deferred<Unit>>):
  match enabled:
    case False{}: IO.pure(Maybe<&2,Deferred.Deferred<Unit>>,None{})
    case True{}:
      do IO<Maybe<&2,Deferred.Deferred<Unit>>>:
        signal : Deferred.Deferred<Unit> <- Deferred.new(Unit)
        return Some{signal}

# Swap a complete batch under the gate; callbacks run outside it. Producers
# never wait for publisher capacity, including reentrant onData calls.
def takePublication(value: Maybe<&1,Run>) -> IO(Maybe<&1,Run> & Publication):
  match value:
    case None{}: IO.pure(Maybe<&1,Run> & Publication,(None{},Publication{Nil{},None{}}))
    case Some{Run{accumulator,State{decoder,ansi,raw,+accepting,failure,chunks,old}}}:
      do IO<Maybe<&1,Run> & Publication>:
        disposeWake(old)
        +wake : Maybe<&2,Deferred.Deferred<Unit>> <- newWake(accepting)
        return (Some{Run{accumulator,State{decoder,ansi,raw,accepting,failure,Nil{},wake}}},Publication{List.reverse(&2,String,chunks),wake})

def publishChunks(+callback: C.Callback<String,Unit>, chunks: List<&2,String>) -> IO(Unit):
  match chunks:
    case Nil{}: IO.pure(Unit,Unit{})
    case text <> rest:
      do IO<Unit>:
        C.call(String,Unit,callback,text)
        publishChunks(callback,rest)

# One externally driven publisher owns ordered onChunk calls. The queue is
# drained before invocation return; termination follows acceptance closure.
@unsafe def publisher(+gate: Serial.Handle<Maybe<&1,Run>>, +callback: C.Callback<String,Unit>, batch: Publication) -> IO(Unit):
  match batch:
    case Publication{chunks,None{}}: publishChunks(callback,chunks)
    case Publication{chunks,Some{signal}}:
      do IO<Unit>:
        publishChunks(callback,chunks)
        settled : Unit <- Deferred.result(Unit,signal)
        next : Publication <- Serial.run(Maybe<&1,Run>,Publication,gate,takePublication)
        publisher(gate,callback,next)

def startPublisher(gate: Serial.Handle<Maybe<&1,Run>>, callback: Maybe<&2,C.Callback<String,Unit>>, wake: Maybe<&2,Deferred.Deferred<Unit>>) -> IO(Maybe<&2,Chan(Unit)>):
  match callback:
    case None{}: IO.pure(Maybe<&2,Chan(Unit)>,None{})
    case Some{callback}:
      do IO<Maybe<&2,Chan(Unit)>>:
        task : Chan(Unit) <- IO.fork(Unit,publisher(gate,callback,Publication{Nil{},wake}))
        return Some{task}

def finalText(ansi: Ansi.Scanner, decoded: Utf8.Decoded) -> String:
  match decoded:
    case Utf8.Decoded{_,text}: sanitized(Ansi.finish(ansiFeed(text,ansi)))

def finishedRun(run: Run) -> IO(Maybe<&1,Run> & Unit):
  match run:
    case Run{accumulator,State{decoder,ansi,raw,_,failure,chunks,+wake}}:
      do IO<Maybe<&1,Run> & Unit>:
        notify(wake)
        return (Some{Run{accumulator,State{decoder,ansi,raw,False{},failure,chunks,wake}}},Unit{})

def finishText(+state: State, +text: String, accumulator: Output.OutputAccumulator) -> IO(Maybe<&1,Run> & Unit):
  Bool.pick(Output.OutputAccumulator -> IO(Maybe<&1,Run> & Unit),String.eq(text,""),
    accumulator => finishedRun(Run{accumulator,state}),
    accumulator => do IO<Maybe<&1,Run> & Unit>:
      run : Run <- appendText(state,text,accumulator)
      finishedRun(run))(accumulator)

def finishLocked(value: Maybe<&1,Run>) -> IO(Maybe<&1,Run> & Unit):
  match value:
    case None{}: IO.pure(Maybe<&1,Run> & Unit,(None{},Unit{}))
    case Some{Run{accumulator,State{decoder,ansi,raw,_,failure,chunks,wake}}}:
      finishText(State{Utf8.create(),Ansi.Scanner{Ansi.Plain{},"",""},raw,False{},failure,chunks,wake},finalText(ansi,Utf8.finish(decoder)),accumulator)

def joinPublisher(task: Maybe<&2,Chan(Unit)>) -> IO(Unit):
  match task:
    case None{}: IO.pure(Unit,Unit{})
    case Some{channel}: IO.join(Unit,channel)

def takeRun(value: Maybe<&1,Run>) -> IO(Maybe<&1,Run> & Maybe<&1,Run>):
  IO.pure(Maybe<&1,Run> & Maybe<&1,Run>,(None{},value))

def outputResult(previous: Maybe<&2,Output.Error>, snapshot: Result<&2,&2,Output.Error,Output.OutputSnapshot>, close: Output.Outcome<Unit>) -> Result<&2,&2,Output.Error,Output.OutputSnapshot>:
  match previous snapshot close:
    case _ _ Output.Outcome{_,Fail{cause}}: Fail{cause}
    case Some{cause} _ _: Fail{cause}
    case None{} result _: result

def closeSnapshot(failure: Maybe<&2,Output.Error>, outcome: Output.Outcome<Output.OutputSnapshot>) -> IO(Result<&2,&2,Output.Error,Output.OutputSnapshot>):
  match outcome:
    case Output.Outcome{accumulator,result}:
      do IO<Result<&2,&2,Output.Error,Output.OutputSnapshot>>:
        closed : Output.Outcome<Unit> <- Output.closeTempFile(accumulator)
        return outputResult(failure,result,closed)

def snapshotFinished(persist: Bool, failure: Maybe<&2,Output.Error>, outcome: Output.Outcome<Unit>) -> IO(Result<&2,&2,Output.Error,Output.OutputSnapshot>):
  match outcome:
    case Output.Outcome{accumulator,result}:
      do IO<Result<&2,&2,Output.Error,Output.OutputSnapshot>>:
        view : Output.Outcome<Output.OutputSnapshot> <- Output.snapshot(persist,accumulator)
        closeSnapshot(remember(failure,result),view)

def finishOutput(persist: Bool, value: Maybe<&1,Run>) -> IO(Result<&2,&2,Output.Error,Output.OutputSnapshot>):
  match value:
    case None{}: IO.die(Result<&2,&2,Output.Error,Output.OutputSnapshot>,1,"Bash executor: missing run")
    case Some{Run{accumulator,State{_,_,_,_,failure,_,wake}}}:
      do IO<Result<&2,&2,Output.Error,Output.OutputSnapshot>>:
        disposeWake(wake)
        outcome : Output.Outcome<Unit> <- Output.finish(accumulator)
        snapshotFinished(persist,failure,outcome)

def resultFromSnapshot(exitCode: Maybe<&2,U32>, cancelled: Bool, snapshot: Output.OutputSnapshot) -> BashResult:
  match snapshot:
    case Output.OutputSnapshot{text,Truncate.TruncationResult{_,truncated,_,_,_,_,_,_,_,_,_},path}:
      BashResult{text,exitCode,cancelled,truncated,path}

def executionResult(cancelled: Bool, execution: Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>, output: Result<&2,&2,Output.Error,Output.OutputSnapshot>) -> Result<&2,&2,Error,BashResult>:
  match cancelled execution output:
    case True{} _ Done{view}: Done{resultFromSnapshot(None{},True{},view)}
    case True{} _ Fail{cause}: Fail{OutputFailure{cause}}
    case False{} Fail{cause} Fail{output}: Fail{ExecutionAndOutput{cause,output}}
    case False{} _ Fail{cause}: Fail{OutputFailure{cause}}
    case False{} Fail{cause} _: Fail{Execution{cause}}
    case False{} Done{code} Done{view}: Done{resultFromSnapshot(code,False{},view)}

def persistResult(cancelled: Bool, result: Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>) -> Bool:
  match result:
    case Done{_}: True{}
    case Fail{_}: cancelled

def executeOwned(registry: Ref.Ref<List<&1,Consumer>>, command: String, cwd: String, operations: Bash.BashOperations, options: BashExecutorOptions, wake: Maybe<&2,Deferred.Deferred<Unit>>, pair: Serial.Owner<Maybe<&1,Run>> & Serial.Handle<Maybe<&1,Run>>) -> IO(Result<&2,&2,Error,BashResult>):
  match operations options pair:
    case Bash.BashOperations{exec} BashExecutorOptions{observer,+signal} Tuple{owner,+handle}:
      do IO<Result<&2,&2,Error,BashResult>>:
        task : Maybe<&2,Chan(Unit)> <- startPublisher(handle,observer,wake)
        +callback : C.Callback<List<&2,U32>,Result<&2,&2,String,Unit>> <- C.create(~Serial.Handle<Maybe<&1,Run>>,~List<&2,U32>,~Result<&2,&2,String,Unit>,~onData,handle)
        +result : Result<&2,&2,Bash.OperationError,Maybe<&2,U32>> <- C.call(Bash.BashExecutionInput,Result<&2,&2,Bash.OperationError,Maybe<&2,U32>>,exec,Bash.BashExecutionInput{command,cwd,callback,signal,None{},None{}})
        Serial.run(Maybe<&1,Run>,Unit,handle,finishLocked)
        joinPublisher(task)
        run : Maybe<&1,Run> <- Serial.run(Maybe<&1,Run>,Maybe<&1,Run>,handle,takeRun)
        Ref.modify(List<&1,Consumer>,Unit,registry,previous => (Consumer{owner,callback} <> previous,Unit{}))
        +cancelled : Bool <- Child.parentAborted(signal)
        output : Result<&2,&2,Output.Error,Output.OutputSnapshot> <- finishOutput(persistResult(cancelled,result),run)
        return executionResult(cancelled,result,output)

def executeBashWithOperations(executor: ExecutorHandle, command: String, cwd: String, operations: Bash.BashOperations, +options: BashExecutorOptions) -> IO(Result<&2,&2,Error,BashResult>):
  match executor options:
    case ExecutorHandle{registry} BashExecutorOptions{observer,_}:
      do IO<Result<&2,&2,Error,BashResult>>:
        +wake : Maybe<&2,Deferred.Deferred<Unit>> <- newWake(Maybe.is_some(&2,C.Callback<String,Unit>,observer))
        accumulator : Output.OutputAccumulator = Output.createPreservingBom(Output.OutputAccumulatorOptions{None{},None{},Some{"pi-bash"}},False{})
        gate : Serial.Owner<Maybe<&1,Run>> <- Serial.create(Maybe<&1,Run>,Some{Run{accumulator,State{Utf8.create(),Ansi.Scanner{Ansi.Plain{},"",""},0n,True{},None{},Nil{},wake}}})
        executeOwned(registry,command,cwd,operations,options,wake,Serial.borrow(Maybe<&1,Run>,gate))

def disposeConsumers(consumers: List<&1,Consumer>) -> IO(Unit):
  match consumers:
    case Nil{}: IO.pure(Unit,Unit{})
    case Consumer{gate,callback} <> rest:
      do IO<Unit>:
        C.dispose(List<&2,U32>,Result<&2,&2,String,Unit>,callback)
        retired : Maybe<&1,Run> <- Serial.retire(Maybe<&1,Run>,gate)
        disposeConsumers(rest)

# Join invocations and retire external onData aliases before disposing.
def disposeExecutor(owner: ExecutorOwner) -> IO(Unit):
  match owner:
    case ExecutorOwner{registry}:
      do IO<Unit>:
        consumers : List<&1,Consumer> <- Ref.dispose(List<&1,Consumer>,registry)
        disposeConsumers(consumers)
