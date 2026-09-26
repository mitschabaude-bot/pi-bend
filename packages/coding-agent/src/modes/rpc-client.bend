import Base
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/utf8.bend as Utf8
import ../../../ai/src/types.bend as Ai
import ../../../agent/src/types.bend as AgentTypes
import ../core/agent-session.bend as Session
import ../core/bash-executor.bend as Bash
import ../core/compaction/compaction.bend as Compaction
import ../core/session-stats.bend as Stats
import ./json-event.bend as Events
import ./jsonl.bend as Jsonl
import ./rpc-types.bend as Types

# pi v0.87.1 modes/rpc/rpc-client.ts: programmatic access to an agent running
# as a child `--mode rpc` process, with a typed method per RPC command.
#
# The transport is the injectable `send` capability of an RpcClient: create()
# supplies one that writes to the child's stdin and waits for the correlated
# response, and withSend() substitutes another (upstream tests replace the
# private `send`). Methods decode each response's data with its command's
# typed decoder; data that does not decode is a failure naming the command.
# Failures are Result values carrying upstream's error messages.
#
# Adaptations: cliPath names the agent executable itself (the native CLI)
# rather than a script run by `node`. Events reach listeners as their JSON
# values, the representation of JsonAgentSessionEvent in ./json-event.bend.
# Listeners run on the task that reads the child's stdout, one event at a
# time; they must not wait for a response or unsubscribe themselves.

# Options and results
# -------------------

type RpcClientOptions is Data:
  RpcClientOptions{cliPath: Maybe<&2,String>,cwd: Maybe<&2,String>,env: List<&2,R.Property<String>>,provider: Maybe<&2,String>,model: Maybe<&2,String>,args: List<&2,String>}

def defaultOptions() -> RpcClientOptions: RpcClientOptions{None{},None{},Nil{},None{},None{},Nil{}}

type ModelInfo is Data:
  ModelInfo{provider: String,id: String,contextWindow: F64,reasoning: Bool}
type ModelReference is Data:
  ModelReference{provider: String,id: String}
type ModelCycle is Data:
  ModelCycle{model: ModelReference,thinkingLevel: Ai.ModelThinkingLevel,isScoped: Bool}
type ThinkingLevelCycle is Data:
  ThinkingLevelCycle{level: Ai.ModelThinkingLevel}
type Cancellable is Data:
  Cancellable{cancelled: Bool}
type ForkResult is Data:
  ForkResult{text: Maybe<&2,String>,cancelled: Bool}
type ExportResult is Data:
  ExportResult{path: String}
type ForkMessage is Data:
  ForkMessage{entryId: String,text: String}
type SessionEntries is Data:
  SessionEntries{entries: List<&2,Session.Entry()>,leafId: Maybe<&2,String>}
type SessionTree is Data:
  SessionTree{tree: List<&2,Types.TreeNode()>,leafId: Maybe<&2,String>}

def JsonAgentSessionEvent() -> Data: V.Value
def RpcEventListener() -> Data: Callback.Callback<JsonAgentSessionEvent(),Unit>
def Reply() -> Data: Result<&2,&2,String,Types.RpcResponse>
def Sender() -> Data: Callback.Callback<Types.RpcCommand,Reply()>

# Connection state
# ----------------
# Requests holds the child and its pending requests together, so the exit of
# the child and the admission of a request are ordered: a request is either
# refused or pending when the child's exit rejects all pending requests.
type Running is Data:
  Running{generation: Nat,control: ProcessControl,stdout: PipeCancel,stderr: PipeCancel,exit: Chan(Process),reader: Chan(Unit),errors: Chan(Unit)}
type Pending is Data:
  Pending{id: String,reply: Chan(Reply()),timer: TimerCancel}
type Requests is Data:
  Requests{process: Maybe<&2,Running>,generation: Nat,exited: Maybe<&2,ProcessStatus>,exitError: Maybe<&2,String>,writable: Bool,reading: Bool,requestId: Nat,pending: List<&2,Pending>}
type Subscription is Data:
  Subscription{key: Nat,listener: RpcEventListener()}
type Listeners is Data:
  Listeners{next: Nat,entries: List<&2,Subscription>}
type Unsubscribe is Data:
  Unsubscribe{key: Nat}
type Connection is Data:
  Connection{options: RpcClientOptions,requests: Ref.Ref<Requests>,stderr: Ref.Ref<String>,listeners: Ref.Ref<Listeners>,delivery: Ref.Ref<Unit>,input: Ref.Ref<Maybe<&1,Pipe>>}
type RpcClient is Data:
  RpcClient{connection: Connection,send: Sender(),own: Sender()}

def connectionOf(client: RpcClient) -> Connection:
  match client:
    case RpcClient{connection,_,_}: connection
def requestsOf(connection: Connection) -> Ref.Ref<Requests>:
  match connection:
    case Connection{_,requests,_,_,_,_}: requests
def stderrOf(connection: Connection) -> Ref.Ref<String>:
  match connection:
    case Connection{_,_,stderr,_,_,_}: stderr

# upstream getStderr: the child's stderr collected so far.
def getStderr(client: RpcClient) -> IO(String):
  Ref.read(String,stderrOf(connectionOf(client)))
def signalNamed(+signal: Nat) -> String:
  match signal:
    case 1n: "SIGHUP"
    case 2n: "SIGINT"
    case 3n: "SIGQUIT"
    case 6n: "SIGABRT"
    case 9n: "SIGKILL"
    case 11n: "SIGSEGV"
    case 13n: "SIGPIPE"
    case 14n: "SIGALRM"
    case 15n: "SIGTERM"
    case other: "signal " ++ Nat.show(other)

# Pending requests
# ----------------

def signalName(signal: U32) -> String: signalNamed(U32.to_nat(signal))

# upstream createProcessExitError
def processExitError(status: ProcessStatus,+stderr: String) -> String:
  match status:
    case ProcessExited{code}: "Agent process exited (code=" ++ U32.show(code) ++ " signal=null). Stderr: " ++ stderr
    case ProcessSignalled{signal}: "Agent process exited (code=null signal=" ++ signalName(signal) ++ "). Stderr: " ++ stderr

type Admission is Data:
  Admitted{id: String}
  Refused{error: String}

def failed(state: Requests,+error: String) -> Requests & Admission:
  match state:
    case Requests{process,generation,exited,_,writable,reading,requestId,pending}: (Requests{process,generation,exited,Some{error},writable,reading,requestId,pending},Refused{error})
def registeredPending(state: Requests,+id: String,reply: Chan(Reply()),timer: TimerCancel) -> Requests & Admission:
  match state:
    case Requests{process,generation,exited,exitError,writable,reading,count,pending}: (Requests{process,generation,exited,exitError,writable,reading,count + 1n,List.append(&2,Pending,pending,[Pending{id,reply,timer}])},Admitted{id})
def admitRunning(+state: Requests,reply: Chan(Reply()),timer: TimerCancel,+stderr: String) -> Requests & Admission:
  match state:
    case Requests{_,_,_,Some{error},_,_,_,_}: (state,Refused{error})
    case Requests{_,_,Some{status},None{},_,_,_,_}: failed(state,processExitError(status,stderr))
    case Requests{_,_,None{},None{},False{},_,_,_}: failed(state,"Agent process stdin is not writable. Stderr: " ++ stderr)
    case Requests{_,_,None{},None{},True{},_,count,_}: registeredPending(state,"req_" ++ Nat.show(count + 1n),reply,timer)
# upstream send's preconditions, then a fresh request id and pending entry.
def admit(+state: Requests,reply: Chan(Reply()),timer: TimerCancel,stderr: String) -> Requests & Admission:
  match state:
    case Requests{None{},_,_,_,_,_,_,_}: (state,Refused{"Client not started"})
    case Requests{Some{_},_,_,_,_,_,_,_}: admitRunning(state,reply,timer,stderr)

def kept(head: Pending,pair: List<&2,Pending> & Maybe<&2,Pending>) -> List<&2,Pending> & Maybe<&2,Pending>:
  match pair:
    case (rest,found): (head <> rest,found)
def pendingId(pending: Pending) -> String:
  match pending:
    case Pending{id,_,_}: id
def withoutPending(pending: List<&2,Pending>,+id: String) -> List<&2,Pending> & Maybe<&2,Pending>:
  match pending:
    case Nil{}: (Nil{},None{})
    case +head <> +rest: Bool.pick(List<&2,Pending> & Maybe<&2,Pending>,String.eq(pendingId(head),id),(rest,Some{head}),kept(head,withoutPending(rest,id)))
def withPending(state: Requests,pair: List<&2,Pending> & Maybe<&2,Pending>) -> Requests & Maybe<&2,Pending>:
  match state pair:
    case Requests{process,generation,exited,exitError,writable,reading,count,_} Tuple{rest,found}: (Requests{process,generation,exited,exitError,writable,reading,count,rest},found)
def pendingOf(state: Requests) -> List<&2,Pending>:
  match state:
    case Requests{_,_,_,_,_,_,_,pending}: pending
def takeOne(+state: Requests,id: String) -> Requests & Maybe<&2,Pending>:
  withPending(state,withoutPending(pendingOf(state),id))
def takeAll(state: Requests) -> Requests & List<&2,Pending>:
  match state:
    case Requests{process,generation,exited,exitError,writable,reading,count,pending}: (Requests{process,generation,exited,exitError,writable,reading,count,Nil{}},pending)

def settle(pending: Pending,result: Reply()) -> IO(Unit):
  match pending:
    case Pending{_,reply,timer}:
      do IO<Unit>:
        cancelled : Bool <- Timer.cancel(timer)
        sent : Bool <- Chan.send(Reply(),reply,result)
        return Unit{}
def settleAll(pending: List<&2,Pending>,+error: String) -> IO(Unit):
  match pending:
    case Nil{}: IO.pure(Unit,Unit{})
    case head <> rest:
      do IO<Unit>:
        settle(head,Fail{error})
        settleAll(rest,error)
# upstream rejectPendingRequests
def rejectPendingRequests(connection: Connection,error: String) -> IO(Unit):
  do IO<Unit>:
    pending : List<&2,Pending> <- Ref.modify(Requests,List<&2,Pending>,requestsOf(connection),takeAll)
    settleAll(pending,error)

# A request that is still pending after 30 seconds fails with a timeout.
def settleFound(found: Maybe<&2,Pending>,error: String) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit,Unit{})
    case Some{pending}: settle(pending,Fail{error})
def expire(+connection: Connection,id: String,command: String) -> IO(Unit):
  do IO<Unit>:
    found : Maybe<&2,Pending> <- Ref.modify(Requests,Maybe<&2,Pending>,requestsOf(connection),state => takeOne(state,id))
    stderr : String <- Ref.read(String,stderrOf(connection))
    settleFound(found,"Timeout waiting for response to " ++ command ++ ". Stderr: " ++ stderr)
def timedOut(connection: Connection,id: String,command: String,result: Timer & Bool) -> IO(Unit):
  match result:
    case (owner,True{}):
      do IO<Unit>:
        Timer.close(owner)
        expire(connection,id,command)
    case (owner,False{}): Timer.close(owner)
def watchTimeout(connection: Connection,id: String,command: String,owner: Timer) -> IO(Unit):
  do IO<Unit>:
    result : Timer & Bool <- Timer.wait(owner)
    timedOut(connection,id,command,result)

# Stdin
# -----

def writeResult(next: Pipe -> List<&2,U32> -> IO(Pipe & Result<&2,&2,String,Unit>),bytes: List<&2,U32>,result: Pipe & Result<&1,&1,U32 & String,U32>) -> IO(Pipe & Result<&2,&2,String,Unit>):
  match result:
    case (pipe,Fail{(_,message)}): IO.pure(Pipe & Result<&2,&2,String,Unit>,(pipe,Fail{message}))
    case (pipe,Done{0}): IO.pure(Pipe & Result<&2,&2,String,Unit>,(pipe,Fail{"write made no progress"}))
    case (pipe,Done{count}): next(pipe,List.drop(&2,U32,bytes,U32.to_nat(count)))
# Each successful write consumes at least one byte, so the byte count bounds
# the number of writes even when the OS accepts partial writes.
def writeAll(fuel: Nat,pipe: Pipe,+bytes: List<&2,U32>) -> IO(Pipe & Result<&2,&2,String,Unit>):
  match fuel bytes:
    case _ Nil{}: IO.pure(Pipe & Result<&2,&2,String,Unit>,(pipe,Done{Unit{}}))
    case 0n _: IO.pure(Pipe & Result<&2,&2,String,Unit>,(pipe,Fail{"write progress exhausted"}))
    case 1n+rest +bytes:
      do IO<Pipe & Result<&2,&2,String,Unit>>:
        result : Pipe & Result<&1,&1,U32 & String,U32> <- Pipe.write(pipe,List.take(&2,U32,bytes,65536n))
        writeResult(next => remaining => writeAll(rest,next,remaining),bytes,result)
def written(result: Pipe & Result<&2,&2,String,Unit>) -> Maybe<&1,Pipe> & Result<&2,&2,String,Unit>:
  match result:
    case (pipe,outcome): (Some{pipe},outcome)
def writeTo(input: Maybe<&1,Pipe>,+bytes: List<&2,U32>) -> IO(Maybe<&1,Pipe> & Result<&2,&2,String,Unit>):
  match input:
    case None{}: IO.pure(Maybe<&1,Pipe> & Result<&2,&2,String,Unit>,(None{},Fail{"stdin is closed"}))
    case Some{pipe}: IO.bind(Pipe & Result<&2,&2,String,Unit>,Maybe<&1,Pipe> & Result<&2,&2,String,Unit>,writeAll(List.length(&2,U32,bytes),pipe,bytes),result => IO.pure(Maybe<&1,Pipe> & Result<&2,&2,String,Unit>,written(result)))
def writeLine(connection: Connection,line: String) -> IO(Result<&2,&2,String,Unit>):
  match connection:
    case Connection{_,_,_,_,_,input}: Ref.update(Maybe<&1,Pipe>,Result<&2,&2,String,Unit>,input,current => writeTo(current,Utf8.encode(line)))

def stdinClosed(state: Requests,error: String) -> Requests & (String & List<&2,Pending>):
  match state:
    case Requests{process,generation,exited,exitError,_,reading,count,pending}:
      +chosen = Maybe.default(&2,String,exitError,error)
      (Requests{process,generation,exited,Some{chosen},False{},reading,count,Nil{}},(chosen,pending))
def rejectTaken(taken: String & List<&2,Pending>) -> IO(Unit):
  match taken:
    case (error,pending): settleAll(pending,error)
# upstream's stdin "error" listener: the exit error if known, otherwise the
# stdin error, fails every pending request.
def stdinFailed(+connection: Connection,message: String) -> IO(Unit):
  do IO<Unit>:
    stderr : String <- Ref.read(String,stderrOf(connection))
    taken : String & List<&2,Pending> <- Ref.modify(Requests,String & List<&2,Pending>,requestsOf(connection),state => stdinClosed(state,"Agent process stdin error: " ++ message ++ ". Stderr: " ++ stderr))
    rejectTaken(taken)
def afterWrite(connection: Connection,result: Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit,Unit{})
    case Fail{message}: stdinFailed(connection,message)

# The process transport
# ---------------------

def receivedReply(value: Maybe<&1,Reply()>) -> Reply():
  match value:
    case Some{reply}: reply
    case None{}: Fail{"Response channel closed"}
def awaitReply(+reply: Chan(Reply())) -> IO(Reply()):
  do IO<Reply()>:
    value : Maybe<&1,Reply()> <- Chan.recv(Reply(),reply)
    Chan.close(Reply(),reply)
    return receivedReply(value)
def dispatched(+connection: Connection,+command: Types.RpcCommand,+reply: Chan(Reply()),owner: Timer,admission: Admission) -> IO(Reply()):
  match admission:
    case Refused{error}:
      do IO<Reply()>:
        Timer.close(owner)
        Chan.close(Reply(),reply)
        return Fail{error}
    case Admitted{+id}:
      do IO<Reply()>:
        IO.spawn(Unit,watchTimeout(connection,id,Types.commandType(command),owner))
        result : Result<&2,&2,String,Unit> <- writeLine(connection,Jsonl.serializeJsonLine(Types.commandValue(command,Some{id})))
        afterWrite(connection,result)
        awaitReply(reply)
def admitted(+connection: Connection,command: Types.RpcCommand,+reply: Chan(Reply()),pair: Timer & TimerCancel) -> IO(Reply()):
  match pair:
    case (owner,+handle):
      do IO<Reply()>:
        stderr : String <- Ref.read(String,stderrOf(connection))
        admission : Admission <- Ref.modify(Requests,Admission,requestsOf(connection),state => admit(state,reply,handle,stderr))
        dispatched(connection,command,reply,owner,admission)
# upstream send: write the command with a fresh id, then wait for the response
# with that id, the process's exit, a stdin failure, or 30 seconds.
def processSend(connection: Connection,command: Types.RpcCommand) -> IO(Reply()):
  do IO<Reply()>:
    +reply : Chan(Reply()) <- Chan.new(Reply(),1)
    pair : Timer & TimerCancel <- Timer.new(30000)
    admitted(connection,command,reply,pair)

# Stdout: responses and events
# ----------------------------

def isReading(state: Requests) -> Bool:
  match state:
    case Requests{_,_,_,_,_,reading,_,_}: reading
def textValue(value: Maybe<&2,V.Value>) -> Maybe<&2,String>:
  match value:
    case Some{V.Text{text}}: Some{text}
    case _: None{}
def textField(fields: R.Record<V.Value>,key: String) -> Maybe<&2,String>: textValue(R.get(V.Value,fields,key))
# upstream: `data.type === "response" && data.id` (a non-empty id).
def responseKey(kind: Maybe<&2,String>,+id: Maybe<&2,String>) -> Maybe<&2,String>:
  match kind id:
    case Some{"response"} Some{""}: None{}
    case Some{"response"} Some{id}: Some{id}
    case _ _: None{}
def responseId(value: V.Value) -> Maybe<&2,String>:
  match value:
    case V.ObjectValue{+fields}: responseKey(textField(fields,"type"),textField(fields,"id"))
    case _: None{}

def callListeners(entries: List<&2,Subscription>,+event: V.Value) -> IO(Unit):
  match entries:
    case Nil{}: IO.pure(Unit,Unit{})
    case Subscription{_,listener} <> rest:
      do IO<Unit>:
        Callback.call(V.Value,Unit,listener,event)
        callListeners(rest,event)
def entriesOf(value: Listeners) -> List<&2,Subscription>:
  match value:
    case Listeners{_,entries}: entries
def deliverTo(listeners: Ref.Ref<Listeners>,event: V.Value,held: Unit) -> IO(Unit & Unit):
  do IO<Unit & Unit>:
    current : Listeners <- Ref.read(Listeners,listeners)
    callListeners(entriesOf(current),event)
    return (held,Unit{})
# Events are delivered while holding the delivery lock, so unsubscribe can
# wait until no delivery still uses a removed listener.
def deliver(connection: Connection,event: V.Value) -> IO(Unit):
  match connection:
    case Connection{_,_,_,listeners,delivery,_}: Ref.update(Unit,Unit,delivery,held => deliverTo(listeners,event,held))

def decodedResponse(result: Types.Decoded(Types.RpcResponse)) -> Reply():
  match result:
    case Done{response}: Done{response}
    case Fail{error}: Fail{"Invalid RPC response: " ++ Decode.describe(error)}
def resolved(connection: Connection,+value: V.Value,found: Maybe<&2,Pending>) -> IO(Unit):
  match found:
    case None{}: deliver(connection,value)
    case Some{pending}: settle(pending,decodedResponse(Types.decodeResponse(value)))
def dispatchValue(+connection: Connection,+value: V.Value,id: Maybe<&2,String>) -> IO(Unit):
  match id:
    case None{}: deliver(connection,value)
    case Some{+key}:
      do IO<Unit>:
        found : Maybe<&2,Pending> <- Ref.modify(Requests,Maybe<&2,Pending>,requestsOf(connection),state => takeOne(state,key))
        resolved(connection,value,found)
def parsedLine(connection: Connection,parsed: Result<&2,&2,Decode.ParseError,V.Value>) -> IO(Unit):
  match parsed:
    case Fail{_}: IO.pure(Unit,Unit{})
    case Done{+value}: dispatchValue(connection,value,responseId(value))

# upstream attachJsonlLineReader with StringDecoder: replacement-mode UTF-8
# across chunk boundaries, keeping a leading BOM, and a final unterminated
# record at end of stream.
type LineReader is Data:
  LineReader{decoder: Utf8.Decoder,buffer: String}
def lineReader() -> LineReader: LineReader{Utf8.Decoder{Utf8.Ready{},True{}},""}
def decodedText(decoded: Utf8.Decoded) -> String:
  match decoded:
    case Utf8.Decoded{_,text}: text
def closeQuietly(pipe: Pipe) -> IO(Unit):
  do IO<Unit>:
    closed : Result<&1,&1,U32 & String,Unit> <- Pipe.close_checked(pipe)
    return Unit{}

# Stderr: collected for error messages and forwarded to this process's stderr.
# It is opened for appending, so a shared output file is not truncated.
def forward(output: Maybe<&1,File>,bytes: List<&2,U32>) -> IO(Maybe<&1,File>):
  match output:
    case None{}: IO.pure(Maybe<&1,File>,None{})
    case Some{file}:
      do IO<Maybe<&1,File>>:
        pair : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,bytes)
        return Some{Pair.fst(File,Result<&1,&1,U32 & String,Unit>,pair)}
def closeOutput(output: Maybe<&1,File>) -> IO(Unit):
  match output:
    case None{}: IO.pure(Unit,Unit{})
    case Some{file}: File.close(file)
def collected(connection: Connection,decoded: Utf8.Decoded) -> IO(Utf8.Decoder):
  match decoded:
    case Utf8.Decoded{decoder,text}:
      do IO<Utf8.Decoder>:
        Ref.modify(String,Unit,stderrOf(connection),stderr => (stderr ++ text,Unit{}))
        return decoder
def stderrRead(+connection: Connection,next: Pipe -> Utf8.Decoder -> Maybe<&1,File> -> IO(Unit),decoder: Utf8.Decoder,output: Maybe<&1,File>,result: Pipe & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Unit):
  match result:
    case (pipe,Done{Nil{}}):
      do IO<Unit>:
        finished : Utf8.Decoder <- collected(connection,Utf8.finish(decoder))
        closeOutput(output)
        closeQuietly(pipe)
    case (pipe,Fail{_}):
      do IO<Unit>:
        closeOutput(output)
        closeQuietly(pipe)
    case (pipe,Done{+bytes}):
      do IO<Unit>:
        advanced : Utf8.Decoder <- collected(connection,Utf8.decode(decoder,bytes))
        forwarded : Maybe<&1,File> <- forward(output,bytes)
        next(pipe,advanced,forwarded)
@unsafe def readStderr(+connection: Connection,pipe: Pipe,decoder: Utf8.Decoder,output: Maybe<&1,File>) -> IO(Unit):
  do IO<Unit>:
    result : Pipe & Result<&1,&1,U32 & String,List<&2,U32>> <- Pipe.read(pipe,65536)
    stderrRead(connection,next => advanced => forwarded => readStderr(connection,next,advanced,forwarded),decoder,output,result)
def openedOutput(result: Result<&1,&1,U32 & String,File>) -> Maybe<&1,File>:
  match result:
    case Done{file}: Some{file}
    case Fail{_}: None{}
def collectStderr(connection: Connection,pipe: Pipe) -> IO(Unit):
  do IO<Unit>:
    opened : Result<&1,&1,U32 & String,File> <- File.open("/dev/stderr","a")
    readStderr(connection,pipe,Utf8.Decoder{Utf8.Ready{},True{}},openedOutput(opened))

# Exit
# ----

def exitedNow(state: Requests,error: String,status: Maybe<&2,ProcessStatus>) -> Requests & List<&2,Pending>:
  match state:
    case Requests{process,current,exited,_,writable,reading,count,pending}: (Requests{process,current,Maybe.or(&2,ProcessStatus,status,exited),Some{error},writable,reading,count,Nil{}},pending)
def generationOf(state: Requests) -> Nat:
  match state:
    case Requests{_,generation,_,_,_,_,_,_}: generation
# Only the current child's exit counts; a stopped predecessor's does not.
def markExited(+state: Requests,generation: Nat,error: String,status: Maybe<&2,ProcessStatus>) -> Requests & List<&2,Pending>:
  Bool.pick(Requests & List<&2,Pending>,Nat.is_eq(generationOf(state),generation),exitedNow(state,error,status),(state,Nil{}))
def ended(connection: Connection,generation: Nat,+error: String,status: Maybe<&2,ProcessStatus>) -> IO(Unit):
  do IO<Unit>:
    pending : List<&2,Pending> <- Ref.modify(Requests,List<&2,Pending>,requestsOf(connection),state => markExited(state,generation,error,status))
    settleAll(pending,error)
# upstream's "exit" and "error" listeners of the current child.
def childExited(+connection: Connection,+generation: Nat,result: Process & Result<&1,&1,U32 & String,ProcessStatus>) -> IO(Process):
  match result:
    case (owner,Done{+status}):
      do IO<Process>:
        stderr : String <- Ref.read(String,stderrOf(connection))
        ended(connection,generation,processExitError(status,stderr),Some{status})
        return owner
    case (owner,Fail{(_,message)}):
      do IO<Process>:
        stderr : String <- Ref.read(String,stderrOf(connection))
        ended(connection,generation,"Agent process error: " ++ message ++ ". Stderr: " ++ stderr,None{})
        return owner
def watchExit(connection: Connection,generation: Nat,owner: Process) -> IO(Process):
  do IO<Process>:
    result : Process & Result<&1,&1,U32 & String,ProcessStatus> <- Process.wait(owner)
    childExited(connection,generation,result)

# Lifecycle
# ---------

def argv(values: List<&2,String>) -> List<String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: value <> argv(rest)
def argsOf(options: RpcClientOptions) -> List<&2,String>:
  match options:
    case RpcClientOptions{_,_,_,provider,model,args}:
      List.concat(&2,String,["--mode" <> "rpc" <> Nil{},Maybe.default(&2,List<&2,String>,Maybe.map(&2,String,List<&2,String>,name => "--provider" <> name <> Nil{},provider),Nil{}),Maybe.default(&2,List<&2,String>,Maybe.map(&2,String,List<&2,String>,name => "--model" <> name <> Nil{},model),Nil{}),args])
def cliPathOf(options: RpcClientOptions) -> String:
  match options:
    case RpcClientOptions{path,_,_,_,_,_}: Maybe.default(&2,String,path,"dist/cli.js")
def cwdOf(options: RpcClientOptions) -> String:
  match options:
    case RpcClientOptions{_,cwd,_,_,_,_}: Maybe.default(&2,String,cwd,".")
def firstPart(parts: List<&2,String>) -> String:
  match parts:
    case key <> _: key
    case Nil{}: ""
def keyOf(entry: String) -> String: firstPart(String.split(entry,'='))
def overrides(+key: String,values: List<&2,R.Property<String>>) -> Bool:
  match values:
    case Nil{}: False{}
    case R.Property{name,_} <> rest: String.eq(name,key) || overrides(key,rest)
def keepEntry(entry: String,replaced: Bool,rest: List<String>) -> List<String>:
  match replaced:
    case True{}: rest
    case False{}: entry <> rest
def inherited(entries: List<String>,+values: List<&2,R.Property<String>>) -> List<String>:
  match entries:
    case Nil{}: Nil{}
    case +entry <> rest: keepEntry(entry,overrides(keyOf(entry),values),inherited(rest,values))
def assignments(overrides: List<&2,R.Property<String>>) -> List<String>:
  match overrides:
    case Nil{}: Nil{}
    case R.Property{key,value} <> rest: (key ++ "=" ++ value) <> assignments(rest)
# upstream `{ ...process.env, ...options.env }`
def environmentOf(environment: List<String>,options: RpcClientOptions) -> List<String>:
  match options:
    case RpcClientOptions{_,_,+values,_,_,_}: List.append(&1,String,inherited(environment,values),assignments(values))

def isStarted(state: Requests) -> Bool:
  match state:
    case Requests{None{},_,_,_,_,_,_,_}: False{}
    case Requests{Some{_},_,_,_,_,_,_,_}: True{}
def begin(state: Requests) -> Requests & Nat:
  match state:
    case Requests{process,+generation,_,_,_,_,count,pending}: (Requests{process,generation + 1n,None{},None{},True{},True{},count,pending},generation + 1n)
def withRunning(state: Requests,process: Running) -> Requests & Unit:
  match state:
    case Requests{_,generation,exited,exitError,writable,reading,count,pending}: (Requests{Some{process},generation,exited,exitError,writable,reading,count,pending},Unit{})
def spawnFailed(state: Requests,error: String) -> Requests & Unit:
  match state:
    case Requests{process,generation,exited,_,writable,reading,count,pending}: (Requests{process,generation,exited,Some{error},writable,reading,count,pending},Unit{})
# upstream start's check after its 100 ms: an exited child fails the start.
def startChecked(state: Requests,stderr: String) -> Result<&2,&2,String,Unit>:
  match state:
    case Requests{_,_,None{},_,_,_,_,_}: Done{Unit{}}
    case Requests{_,_,Some{status},exitError,_,_,_,_}: Fail{Maybe.default(&2,String,exitError,processExitError(status,stderr))}
def closeInput(input: Maybe<&1,Pipe>) -> IO(Unit):
  match input:
    case None{}: IO.pure(Unit,Unit{})
    case Some{pipe}: closeQuietly(pipe)
def storeInput(connection: Connection,pipe: Pipe) -> IO(Unit):
  match connection:
    case Connection{_,_,_,_,_,input}:
      do IO<Unit>:
        previous : Maybe<&1,Pipe> <- Ref.swap(Maybe<&1,Pipe>,input,Some{pipe})
        closeInput(previous)

def detach(state: Requests) -> Requests & Maybe<&2,Running>:
  match state:
    case Requests{+process,generation,exited,exitError,writable,_,count,pending}: (Requests{process,generation,exited,exitError,writable,False{},count,pending},process)
def retire(state: Requests) -> Requests & (String & List<&2,Pending>):
  match state:
    case Requests{_,generation,exited,+exitError,_,reading,count,pending}: (Requests{None{},generation,exited,exitError,False{},reading,count,Nil{}},(Maybe.default(&2,String,exitError,"Client stopped"),pending))
def killed(control: ProcessControl,result: Timer & Bool) -> IO(Unit):
  match result:
    case (owner,elapsed):
      do IO<Unit>:
        Timer.close(owner)
        Bool.pick(Unit -> IO(Unit),elapsed,_ => IO.bind(Result<&1,&1,U32 & String,Bool>,Unit,Process.signal(control,9),sent => IO.pure(Unit,Unit{})),_ => IO.pure(Unit,Unit{}))(Unit{})
def killAfter(control: ProcessControl,owner: Timer) -> IO(Unit):
  do IO<Unit>:
    result : Timer & Bool <- Timer.wait(owner)
    killed(control,result)
# SIGKILL unless cancelled within the timer's delay.
def armKill(control: ProcessControl,pair: Timer & TimerCancel) -> IO(TimerCancel):
  match pair:
    case (owner,handle):
      do IO<TimerCancel>:
        IO.spawn(Unit,killAfter(control,owner))
        return handle
def stopRunning(+connection: Connection,process: Running) -> IO(Unit):
  match connection process:
    case Connection{_,_,_,_,_,input} Running{_,+control,stdout,stderr,exit,reader,errors}:
      do IO<Unit>:
        stopped : Bool <- Pipe.cancel(stdout)
        terminated : Result<&1,&1,U32 & String,Bool> <- Process.signal(control,15)
        pair : Timer & TimerCancel <- Timer.new(1000)
        handle : TimerCancel <- armKill(control,pair)
        owner : Process <- IO.join(Process,exit)
        cancelled : Bool <- Timer.cancel(handle)
        closed : Result<&1,&1,U32 & String,Unit> <- Process.close_checked(owner)
        IO.join(Unit,reader)
        drained : Bool <- Pipe.cancel(stderr)
        IO.join(Unit,errors)
        remaining : Maybe<&1,Pipe> <- Ref.swap(Maybe<&1,Pipe>,input,None{})
        closeInput(remaining)
        left : String & List<&2,Pending> <- Ref.modify(Requests,String & List<&2,Pending>,requestsOf(connection),retire)
        rejectTaken(left)
# upstream stop: detach the stdout reader, SIGTERM the child, SIGKILL it if it
# has not exited within a second, then forget it. Requests still pending fail
# with the exit error rather than waiting for their timeouts.
def stopFound(connection: Connection,process: Maybe<&2,Running>) -> IO(Unit):
  match process:
    case None{}: IO.pure(Unit,Unit{})
    case Some{value}: stopRunning(connection,value)
def stop(client: RpcClient) -> IO(Unit):
  do IO<Unit>:
    +connection : Connection = connectionOf(client)
    process : Maybe<&2,Running> <- Ref.modify(Requests,Maybe<&2,Running>,requestsOf(connection),detach)
    stopFound(connection,process)
# upstream handleLine: a response to a pending request resolves it; anything
# else that parses is an event; lines that are not JSON are ignored. Nothing
# is handled after stop() detached the reader.
def handleLine(+connection: Connection,line: String) -> IO(Unit):
  do IO<Unit>:
    state : Requests <- Ref.read(Requests,requestsOf(connection))
    Bool.pick(Unit -> IO(Unit),isReading(state),_ => parsedLine(connection,Decode.parse(line)),_ => IO.pure(Unit,Unit{}))(Unit{})
def handleLines(+connection: Connection,lines: List<&2,String>) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit,Unit{})
    case line <> rest:
      do IO<Unit>:
        handleLine(connection,line)
        handleLines(connection,rest)
def framed(connection: Connection,decoder: Utf8.Decoder,frame: Jsonl.Frame) -> IO(LineReader):
  match frame:
    case Jsonl.Frame{records,pending}:
      do IO<LineReader>:
        handleLines(connection,records)
        return LineReader{decoder,pending}
def decodedChunk(connection: Connection,buffer: String,decoded: Utf8.Decoded) -> IO(LineReader):
  match decoded:
    case Utf8.Decoded{decoder,text}: framed(connection,decoder,Jsonl.frame(buffer,text))
def feedLines(connection: Connection,reader: LineReader,bytes: List<&2,U32>) -> IO(LineReader):
  match reader:
    case LineReader{decoder,buffer}: decodedChunk(connection,buffer,Utf8.decode(decoder,bytes))
def finalRecord(connection: Connection,+record: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),String.is_empty(record),_ => IO.pure(Unit,Unit{}),_ => handleLine(connection,Jsonl.withoutCR(record)))(Unit{})
def endLines(connection: Connection,reader: LineReader) -> IO(Unit):
  match reader:
    case LineReader{decoder,buffer}: finalRecord(connection,buffer ++ decodedText(Utf8.finish(decoder)))
def stdoutRead(+connection: Connection,next: Pipe -> LineReader -> IO(Unit),reader: LineReader,result: Pipe & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Unit):
  match result:
    case (pipe,Fail{_}): closeQuietly(pipe)
    case (pipe,Done{Nil{}}):
      do IO<Unit>:
        endLines(connection,reader)
        closeQuietly(pipe)
    case (pipe,Done{bytes}):
      do IO<Unit>:
        advanced : LineReader <- feedLines(connection,reader,bytes)
        next(pipe,advanced)
# External input determines the number of reads; each step awaits one read.
@unsafe def readStdout(+connection: Connection,pipe: Pipe,reader: LineReader) -> IO(Unit):
  do IO<Unit>:
    result : Pipe & Result<&1,&1,U32 & String,List<&2,U32>> <- Pipe.read(pipe,65536)
    stdoutRead(connection,next => advanced => readStdout(connection,next,advanced),reader,result)
def launched(+connection: Connection,result: Result<&1,&1,U32 & String,Process & ProcessControl & (Pipe & PipeCancel) & (Pipe & PipeCancel) & (Pipe & PipeCancel)>) -> IO(Result<&2,&2,String,Unit>):
  match result:
    case Fail{(_,message)}:
      do IO<Result<&2,&2,String,Unit>>:
        stderr : String <- Ref.read(String,stderrOf(connection))
        +error : String = "Agent process error: " ++ message ++ ". Stderr: " ++ stderr
        Ref.modify(Requests,Unit,requestsOf(connection),state => spawnFailed(state,error))
        return Fail{error}
    case Done{(owner,(control,((input,_),((output,outputCancel),(errors,errorsCancel)))))}:
      do IO<Result<&2,&2,String,Unit>>:
        +generation : Nat <- Ref.modify(Requests,Nat,requestsOf(connection),begin)
        storeInput(connection,input)
        exit : Chan(Process) <- IO.fork(Process,watchExit(connection,generation,owner))
        reader : Chan(Unit) <- IO.fork(Unit,readStdout(connection,output,lineReader()))
        collector : Chan(Unit) <- IO.fork(Unit,collectStderr(connection,errors))
        Ref.modify(Requests,Unit,requestsOf(connection),state => withRunning(state,Running{generation,control,outputCancel,errorsCancel,exit,reader,collector}))
        IO.sleep(100)
        state : Requests <- Ref.read(Requests,requestsOf(connection))
        stderr : String <- Ref.read(String,stderrOf(connection))
        return startChecked(state,stderr)
def launch(+connection: Connection) -> IO(Result<&2,&2,String,Unit>):
  match connection:
    case Connection{+options,_,_,_,_,_}:
      do IO<Result<&2,&2,String,Unit>>:
        inherited : List<String> <- IO.environment()
        spawned : Result<&1,&1,U32 & String,Process & ProcessControl & (Pipe & PipeCancel) & (Pipe & PipeCancel) & (Pipe & PipeCancel)> <- Process.spawn(cliPathOf(options),argv(argsOf(options)),cwdOf(options),environmentOf(inherited,options))
        launched(connection,spawned)
# upstream start: spawn `<cliPath> --mode rpc [--provider p] [--model m]
# [...args]` with stdio pipes, then give it 100 ms to fail.
def start(client: RpcClient) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    +connection : Connection = connectionOf(client)
    state : Requests <- Ref.read(Requests,requestsOf(connection))
    Bool.pick(Unit -> IO(Result<&2,&2,String,Unit>),isStarted(state),_ => IO.pure(Result<&2,&2,String,Unit>,Fail{"Client already started"}),_ => launch(connection))(Unit{})

def create(options: RpcClientOptions) -> IO(RpcClient):
  do IO<RpcClient>:
    requests : Ref.Ref<Requests> <- Ref.new(Requests,Requests{None{},0n,None{},None{},False{},False{},0n,Nil{}})
    stderr : Ref.Ref<String> <- Ref.new(String,"")
    listeners : Ref.Ref<Listeners> <- Ref.new(Listeners,Listeners{0n,Nil{}})
    delivery : Ref.Ref<Unit> <- Ref.new(Unit,Unit{})
    input : Ref.Ref<Maybe<&1,Pipe>> <- Ref.new(Maybe<&1,Pipe>,None{})
    +connection : Connection = Connection{options,requests,stderr,listeners,delivery,input}
    +own : Sender() <- Callback.create(~Connection,~Types.RpcCommand,~Reply(),~processSend,connection)
    return RpcClient{connection,own,own}

# The client with another transport in place of its process (upstream tests
# assign the private `send`).
def withSend(client: RpcClient,sender: Sender()) -> RpcClient:
  match client:
    case RpcClient{connection,_,own}: RpcClient{connection,sender,own}

# Releases a stopped client's state; the caller owns any substituted send.
def dispose(client: RpcClient) -> IO(Unit):
  match client:
    case RpcClient{Connection{_,requests,stderr,listeners,delivery,input},_,own}:
      do IO<Unit>:
        Callback.dispose(Types.RpcCommand,Reply(),own)
        state : Requests <- Ref.dispose(Requests,requests)
        text : String <- Ref.dispose(String,stderr)
        registered : Listeners <- Ref.dispose(Listeners,listeners)
        held : Unit <- Ref.dispose(Unit,delivery)
        remaining : Maybe<&1,Pipe> <- Ref.dispose(Maybe<&1,Pipe>,input)
        closeInput(remaining)

# Events
# ------

def subscribed(value: Listeners,listener: RpcEventListener()) -> Listeners & Unsubscribe:
  match value:
    case Listeners{+next,entries}: (Listeners{next + 1n,List.append(&2,Subscription,entries,[Subscription{next,listener}])},Unsubscribe{next})
def subscriptionKey(entry: Subscription) -> Nat:
  match entry:
    case Subscription{key,_}: key
def without(entries: List<&2,Subscription>,+key: Nat) -> List<&2,Subscription>:
  match entries:
    case Nil{}: Nil{}
    case Subscription{+index,listener} <> +rest: Bool.pick(List<&2,Subscription>,Nat.is_eq(index,key),without(rest,key),Subscription{index,listener} <> without(rest,key))
def removed(value: Listeners,+key: Nat) -> Listeners & Unit:
  match value:
    case Listeners{next,entries}: (Listeners{next,without(entries,key)},Unit{})
# upstream onEvent; the returned value unsubscribes the listener.
def listenersOf(client: RpcClient) -> Ref.Ref<Listeners>:
  match client:
    case RpcClient{Connection{_,_,_,listeners,_,_},_,_}: listeners
def deliveryOf(client: RpcClient) -> Ref.Ref<Unit>:
  match client:
    case RpcClient{Connection{_,_,_,_,delivery,_},_,_}: delivery
def onEvent(client: RpcClient,listener: RpcEventListener()) -> IO(Unsubscribe):
  Ref.modify(Listeners,Unsubscribe,listenersOf(client),value => subscribed(value,listener))
# After unsubscribe returns, no delivery still calls the listener.
def unsubscribe(+client: RpcClient,token: Unsubscribe) -> IO(Unit):
  match token:
    case Unsubscribe{key}:
      do IO<Unit>:
        Ref.modify(Listeners,Unit,listenersOf(client),value => removed(value,key))
        Ref.modify(Unit,Unit,deliveryOf(client),held => (held,Unit{}))

# Commands
# --------

def send(client: RpcClient,command: Types.RpcCommand) -> IO(Reply()):
  match client:
    case RpcClient{_,sender,_}: Callback.call(Types.RpcCommand,Reply(),sender,command)

# upstream getData: a failure response's error, or a success's data.
def getData(response: Types.RpcResponse) -> Result<&2,&2,String,Maybe<&2,V.Value>>:
  match response:
    case Types.RpcResponse{_,_,Types.RpcFailure{error}}: Fail{error}
    case Types.RpcResponse{_,_,Types.RpcSuccess{data}}: Done{data}

def decodedData(-A: Data,command: String,result: Types.Decoded(A)) -> Result<&2,&2,String,A>:
  match result:
    case Done{value}: Done{value}
    case Fail{error}: Fail{"Invalid " ++ command ++ " response: " ++ Decode.describe(error)}
def dataOf(-A: Data,command: String,decode: V.Value -> Types.Decoded(A),reply: Reply()) -> Result<&2,&2,String,A>:
  Result.bind(&2,&2,String,Types.RpcResponse,A,reply,response => Result.bind(&2,&2,String,Maybe<&2,V.Value>,A,getData(response),data => decodedData(A,command,decode(Maybe.default(&2,V.Value,data,V.Null{})))))
def query(-A: Data,client: RpcClient,+command: Types.RpcCommand,decode: V.Value -> Types.Decoded(A)) -> IO(Result<&2,&2,String,A>):
  IO.bind(Reply(),Result<&2,&2,String,A>,send(client,command),reply => IO.pure(Result<&2,&2,String,A>,dataOf(A,Types.commandType(command),decode,reply)))
# Upstream's void methods await the response without inspecting it, so a
# failure response does not fail them; transport failures do.
def sentReply(reply: Reply()) -> Result<&2,&2,String,Unit>:
  Result.map(&2,&2,String,Types.RpcResponse,Unit,response => Unit{},reply)
def perform(client: RpcClient,value: Types.RpcCommand) -> IO(Result<&2,&2,String,Unit>):
  IO.bind(Reply(),Result<&2,&2,String,Unit>,send(client,value),reply => IO.pure(Result<&2,&2,String,Unit>,sentReply(reply)))

def objectFields(-A: Data,read: R.Record<V.Value> -> Types.Decoded(A),value: V.Value) -> Types.Decoded(A):
  Result.bind(&2,&2,Decode.Error,R.Record<V.Value>,A,Decode.object(value),read)
def member(-A: Data,key: String,decode: V.Value -> Types.Decoded(A),value: V.Value) -> Types.Decoded(A):
  objectFields(A,fields => Decode.required(A,fields,key,decode),value)
def listOf(~A: Data,~decode: V.Value -> Types.Decoded(A),value: V.Value) -> Types.Decoded(List<&2,A>):
  Decode.list(~A,~decode,value)
def cancellable(value: V.Value) -> Types.Decoded(Cancellable):
  Result.map(&2,&2,Decode.Error,Bool,Cancellable,cancelled => Cancellable{cancelled},member(Bool,"cancelled",Types.decodeBoolean,value))
def nullable(-A: Data,decode: V.Value -> Types.Decoded(A),value: V.Value) -> Types.Decoded(Maybe<&2,A>):
  match value:
    case V.Null{}: Done{None{}}
    case other: Result.map(&2,&2,Decode.Error,A,Maybe<&2,A>,found => Some{found},decode(other))
def nullableText(value: V.Value) -> Types.Decoded(Maybe<&2,String>): nullable(String,Decode.string,value)

def modelReferenceFields(+fields: R.Record<V.Value>) -> Types.Decoded(ModelReference):
  do Result<&2,&2,Decode.Error,ModelReference>:
    provider : String <- Decode.required(String,fields,"provider",Decode.string)
    id : String <- Decode.required(String,fields,"id",Decode.string)
    return ModelReference{provider,id}
def modelReference(value: V.Value) -> Types.Decoded(ModelReference): objectFields(ModelReference,fields => modelReferenceFields(fields),value)
def modelInfoFields(+fields: R.Record<V.Value>) -> Types.Decoded(ModelInfo):
  do Result<&2,&2,Decode.Error,ModelInfo>:
    provider : String <- Decode.required(String,fields,"provider",Decode.string)
    id : String <- Decode.required(String,fields,"id",Decode.string)
    contextWindow : F64 <- Decode.required(F64,fields,"contextWindow",Decode.number)
    reasoning : Bool <- Decode.required(Bool,fields,"reasoning",Types.decodeBoolean)
    return ModelInfo{provider,id,contextWindow,reasoning}
def modelInfo(value: V.Value) -> Types.Decoded(ModelInfo): objectFields(ModelInfo,fields => modelInfoFields(fields),value)
def modelCycleFields(+fields: R.Record<V.Value>) -> Types.Decoded(ModelCycle):
  do Result<&2,&2,Decode.Error,ModelCycle>:
    model : ModelReference <- Decode.required(ModelReference,fields,"model",modelReference)
    level : Ai.ModelThinkingLevel <- Decode.required(Ai.ModelThinkingLevel,fields,"thinkingLevel",Types.decodeThinkingLevel)
    scoped : Bool <- Decode.required(Bool,fields,"isScoped",Types.decodeBoolean)
    return ModelCycle{model,level,scoped}
def modelCycle(value: V.Value) -> Types.Decoded(ModelCycle): objectFields(ModelCycle,fields => modelCycleFields(fields),value)
def levelCycle(value: V.Value) -> Types.Decoded(ThinkingLevelCycle):
  Result.map(&2,&2,Decode.Error,Ai.ModelThinkingLevel,ThinkingLevelCycle,level => ThinkingLevelCycle{level},member(Ai.ModelThinkingLevel,"level",Types.decodeThinkingLevel,value))
def forkFields(+fields: R.Record<V.Value>) -> Types.Decoded(ForkResult):
  do Result<&2,&2,Decode.Error,ForkResult>:
    text : Maybe<&2,String> <- Decode.optional(String,fields,"text",Decode.string)
    cancelled : Bool <- Decode.required(Bool,fields,"cancelled",Types.decodeBoolean)
    return ForkResult{text,cancelled}
def forkMessageFields(+fields: R.Record<V.Value>) -> Types.Decoded(ForkMessage):
  do Result<&2,&2,Decode.Error,ForkMessage>:
    entryId : String <- Decode.required(String,fields,"entryId",Decode.string)
    text : String <- Decode.required(String,fields,"text",Decode.string)
    return ForkMessage{entryId,text}
def forkMessage(value: V.Value) -> Types.Decoded(ForkMessage): objectFields(ForkMessage,fields => forkMessageFields(fields),value)
def entriesFields(+fields: R.Record<V.Value>) -> Types.Decoded(SessionEntries):
  do Result<&2,&2,Decode.Error,SessionEntries>:
    entries : List<&2,Session.Entry()> <- Decode.required(List<&2,Session.Entry()>,fields,"entries",value => listOf(~Session.Entry(),~Types.decodeEntry,value))
    leafId : Maybe<&2,String> <- Decode.required(Maybe<&2,String>,fields,"leafId",nullableText)
    return SessionEntries{entries,leafId}
def treeFields(+fields: R.Record<V.Value>) -> Types.Decoded(SessionTree):
  do Result<&2,&2,Decode.Error,SessionTree>:
    tree : List<&2,Types.TreeNode()> <- Decode.required(List<&2,Types.TreeNode()>,fields,"tree",Types.decodeTree)
    leafId : Maybe<&2,String> <- Decode.required(Maybe<&2,String>,fields,"leafId",nullableText)
    return SessionTree{tree,leafId}
def lastText(value: V.Value) -> Types.Decoded(Maybe<&2,String>):
  objectFields(Maybe<&2,String>,fields => Decode.optional(String,fields,"text",Decode.string),value)

def Images() -> Data: Maybe<&2,List<&2,Ai.ImageContent>>

# upstream prompt: returns once the command is sent; events follow.
def prompt(client: RpcClient,message: String,images: Images()) -> IO(Result<&2,&2,String,Unit>):
  perform(client,Types.RpcPrompt{message,images,None{}})
def steer(client: RpcClient,message: String,images: Images()) -> IO(Result<&2,&2,String,Unit>):
  perform(client,Types.RpcSteer{message,images})
def followUp(client: RpcClient,message: String,images: Images()) -> IO(Result<&2,&2,String,Unit>):
  perform(client,Types.RpcFollowUp{message,images})
def abort(client: RpcClient) -> IO(Result<&2,&2,String,Unit>): perform(client,Types.RpcAbort{})
def clearQueue(client: RpcClient) -> IO(Result<&2,&2,String,Session.QueuedMessages>):
  query(Session.QueuedMessages,client,Types.RpcClearQueue{},Types.decodeClearedQueue)
def newSession(client: RpcClient,parentSession: Maybe<&2,String>) -> IO(Result<&2,&2,String,Cancellable>):
  query(Cancellable,client,Types.RpcNewSession{parentSession},cancellable)
def getState(client: RpcClient) -> IO(Result<&2,&2,String,Types.RpcSessionState>):
  query(Types.RpcSessionState,client,Types.RpcGetState{},Types.decodeSessionState)
def setModel(client: RpcClient,provider: String,modelId: String) -> IO(Result<&2,&2,String,ModelReference>):
  query(ModelReference,client,Types.RpcSetModel{provider,modelId},modelReference)
def cycleModel(client: RpcClient) -> IO(Result<&2,&2,String,Maybe<&2,ModelCycle>>):
  query(Maybe<&2,ModelCycle>,client,Types.RpcCycleModel{},value => nullable(ModelCycle,modelCycle,value))
def getAvailableModels(client: RpcClient) -> IO(Result<&2,&2,String,List<&2,ModelInfo>>):
  query(List<&2,ModelInfo>,client,Types.RpcGetAvailableModels{},value => member(List<&2,ModelInfo>,"models",models => listOf(~ModelInfo,~modelInfo,models),value))
def setThinkingLevel(client: RpcClient,level: Ai.ModelThinkingLevel) -> IO(Result<&2,&2,String,Unit>):
  perform(client,Types.RpcSetThinkingLevel{level})
def cycleThinkingLevel(client: RpcClient) -> IO(Result<&2,&2,String,Maybe<&2,ThinkingLevelCycle>>):
  query(Maybe<&2,ThinkingLevelCycle>,client,Types.RpcCycleThinkingLevel{},value => nullable(ThinkingLevelCycle,levelCycle,value))
def getAvailableThinkingLevels(client: RpcClient) -> IO(Result<&2,&2,String,List<&2,Ai.ModelThinkingLevel>>):
  query(List<&2,Ai.ModelThinkingLevel>,client,Types.RpcGetAvailableThinkingLevels{},value => member(List<&2,Ai.ModelThinkingLevel>,"levels",levels => listOf(~Ai.ModelThinkingLevel,~Types.decodeThinkingLevel,levels),value))
def setSteeringMode(client: RpcClient,mode: AgentTypes.QueueMode) -> IO(Result<&2,&2,String,Unit>):
  perform(client,Types.RpcSetSteeringMode{mode})
def setFollowUpMode(client: RpcClient,mode: AgentTypes.QueueMode) -> IO(Result<&2,&2,String,Unit>):
  perform(client,Types.RpcSetFollowUpMode{mode})
def compact(client: RpcClient,customInstructions: Maybe<&2,String>) -> IO(Result<&2,&2,String,Compaction.CompactionResult>):
  query(Compaction.CompactionResult,client,Types.RpcCompact{customInstructions},Events.decodeCompactionResult)
def setAutoCompaction(client: RpcClient,enabled: Bool) -> IO(Result<&2,&2,String,Unit>):
  perform(client,Types.RpcSetAutoCompaction{enabled})
def setAutoRetry(client: RpcClient,enabled: Bool) -> IO(Result<&2,&2,String,Unit>):
  perform(client,Types.RpcSetAutoRetry{enabled})
def abortRetry(client: RpcClient) -> IO(Result<&2,&2,String,Unit>): perform(client,Types.RpcAbortRetry{})
def bash(client: RpcClient,value: String) -> IO(Result<&2,&2,String,Bash.BashResult>):
  query(Bash.BashResult,client,Types.RpcBash{value,None{}},Types.decodeBashResult)
def abortBash(client: RpcClient) -> IO(Result<&2,&2,String,Unit>): perform(client,Types.RpcAbortBash{})
def getSessionStats(client: RpcClient) -> IO(Result<&2,&2,String,Stats.Stats>):
  query(Stats.Stats,client,Types.RpcGetSessionStats{},Stats.decode)
def exportHtml(client: RpcClient,outputPath: Maybe<&2,String>) -> IO(Result<&2,&2,String,ExportResult>):
  query(ExportResult,client,Types.RpcExportHtml{outputPath},value => Result.map(&2,&2,Decode.Error,String,ExportResult,path => ExportResult{path},member(String,"path",Decode.string,value)))
def switchSession(client: RpcClient,sessionPath: String) -> IO(Result<&2,&2,String,Cancellable>):
  query(Cancellable,client,Types.RpcSwitchSession{sessionPath},cancellable)
def fork(client: RpcClient,entryId: String) -> IO(Result<&2,&2,String,ForkResult>):
  query(ForkResult,client,Types.RpcFork{entryId},value => objectFields(ForkResult,fields => forkFields(fields),value))
def clone(client: RpcClient) -> IO(Result<&2,&2,String,Cancellable>):
  query(Cancellable,client,Types.RpcClone{},cancellable)
def getForkMessages(client: RpcClient) -> IO(Result<&2,&2,String,List<&2,ForkMessage>>):
  query(List<&2,ForkMessage>,client,Types.RpcGetForkMessages{},value => member(List<&2,ForkMessage>,"messages",messages => listOf(~ForkMessage,~forkMessage,messages),value))
def getEntries(client: RpcClient,since: Maybe<&2,String>) -> IO(Result<&2,&2,String,SessionEntries>):
  query(SessionEntries,client,Types.RpcGetEntries{since},value => objectFields(SessionEntries,fields => entriesFields(fields),value))
def getTree(client: RpcClient) -> IO(Result<&2,&2,String,SessionTree>):
  query(SessionTree,client,Types.RpcGetTree{},value => objectFields(SessionTree,fields => treeFields(fields),value))
def getLastAssistantText(client: RpcClient) -> IO(Result<&2,&2,String,Maybe<&2,String>>):
  query(Maybe<&2,String>,client,Types.RpcGetLastAssistantText{},lastText)
def setSessionName(client: RpcClient,name: String) -> IO(Result<&2,&2,String,Unit>):
  perform(client,Types.RpcSetSessionName{name})
def getMessages(client: RpcClient) -> IO(Result<&2,&2,String,List<&2,Session.Message()>>):
  query(List<&2,Session.Message()>,client,Types.RpcGetMessages{},value => member(List<&2,Session.Message()>,"messages",messages => listOf(~Session.Message(),~Events.decodeMessage,messages),value))
def getCommands(client: RpcClient) -> IO(Result<&2,&2,String,List<&2,Types.RpcSlashCommand>>):
  query(List<&2,Types.RpcSlashCommand>,client,Types.RpcGetCommands{},value => member(List<&2,Types.RpcSlashCommand>,"commands",commands => listOf(~Types.RpcSlashCommand,~Types.decodeSlashCommand,commands),value))
# A collector gathers events until the first agent_settled, or fails when its
# timer fires first. Its listener is removed before its state is released.

type Outcome is Data:
  Settled{}
  Expired{}
type Gathering is Data:
  Gathering{keep: Bool,events: Ref.Ref<List<&2,V.Value>>,fired: Ref.Ref<Bool>,signal: Chan(Outcome)}
type Collector is Data:
  Collector{client: RpcClient,gathering: Gathering,listener: RpcEventListener(),token: Unsubscribe,timer: TimerCancel}

def isSettled(value: V.Value) -> Bool:
  match value:
    case V.ObjectValue{fields}: String.eq(Maybe.default(&2,String,textField(fields,"type"),""),"agent_settled")
    case _: False{}
def signalOnce(fired: Ref.Ref<Bool>,signal: Chan(Outcome)) -> IO(Unit):
  do IO<Unit>:
    previous : Bool <- Ref.swap(Bool,fired,True{})
    Bool.pick(Unit -> IO(Unit),previous,_ => IO.pure(Unit,Unit{}),_ => IO.bind(Bool,Unit,Chan.send(Outcome,signal,Settled{}),sentNow => IO.pure(Unit,Unit{})))(Unit{})
def gatherEvent(gathering: Gathering,+event: V.Value) -> IO(Unit):
  match gathering:
    case Gathering{keep,events,fired,signal}:
      do IO<Unit>:
        Bool.pick(Unit -> IO(Unit),keep,_ => Ref.modify(List<&2,V.Value>,Unit,events,current => (event <> current,Unit{})),_ => IO.pure(Unit,Unit{}))(Unit{})
        Bool.pick(Unit -> IO(Unit),isSettled(event),_ => signalOnce(fired,signal),_ => IO.pure(Unit,Unit{}))(Unit{})

# Helpers
# -------
def gather(gathering: Gathering,event: V.Value) -> IO(Unit): gatherEvent(gathering,event)
def expired(signal: Chan(Outcome),result: Timer & Bool) -> IO(Unit):
  match result:
    case (owner,elapsed):
      do IO<Unit>:
        Timer.close(owner)
        Bool.pick(Unit -> IO(Unit),elapsed,_ => IO.bind(Bool,Unit,Chan.send(Outcome,signal,Expired{}),sentNow => IO.pure(Unit,Unit{})),_ => IO.pure(Unit,Unit{}))(Unit{})
def expireAfter(signal: Chan(Outcome),owner: Timer) -> IO(Unit):
  do IO<Unit>:
    result : Timer & Bool <- Timer.wait(owner)
    expired(signal,result)
def armExpiry(signal: Chan(Outcome),pair: Timer & TimerCancel) -> IO(TimerCancel):
  match pair:
    case (owner,handle):
      do IO<TimerCancel>:
        IO.spawn(Unit,expireAfter(signal,owner))
        return handle
def collecting(+client: RpcClient,+gathering: Gathering,timeout: U32) -> IO(Collector):
  match gathering:
    case Gathering{_,_,_,+signal}:
      do IO<Collector>:
        +listener : RpcEventListener() <- Callback.create(~Gathering,~V.Value,~Unit,~gather,gathering)
        token : Unsubscribe <- onEvent(client,listener)
        pair : Timer & TimerCancel <- Timer.new(timeout)
        handle : TimerCancel <- armExpiry(signal,pair)
        return Collector{client,gathering,listener,token,handle}
def startCollecting(client: RpcClient,keep: Bool,timeout: U32) -> IO(Collector):
  do IO<Collector>:
    events : Ref.Ref<List<&2,V.Value>> <- Ref.new(List<&2,V.Value>,Nil{})
    fired : Ref.Ref<Bool> <- Ref.new(Bool,False{})
    signal : Chan(Outcome) <- Chan.new(Outcome,2)
    collecting(client,Gathering{keep,events,fired,signal},timeout)
# Removes the listener, then releases the collector: its events in order and
# how it ended, if it has.
def release(collector: Collector,outcome: Maybe<&1,Outcome>) -> IO(Maybe<&1,Outcome> & List<&2,V.Value>):
  match collector:
    case Collector{+client,Gathering{_,events,fired,signal},listener,token,timer}:
      do IO<Maybe<&1,Outcome> & List<&2,V.Value>>:
        unsubscribe(client,token)
        cancelled : Bool <- Timer.cancel(timer)
        Callback.dispose(V.Value,Unit,listener)
        Chan.close(Outcome,signal)
        flag : Bool <- Ref.dispose(Bool,fired)
        gathered : List<&2,V.Value> <- Ref.dispose(List<&2,V.Value>,events)
        return (outcome,List.reverse(&2,V.Value,gathered))
def signalOf(collector: Collector) -> Chan(Outcome):
  match collector:
    case Collector{_,Gathering{_,_,_,signal},_,_,_}: signal
def finishCollecting(+collector: Collector) -> IO(Maybe<&1,Outcome> & List<&2,V.Value>):
  do IO<Maybe<&1,Outcome> & List<&2,V.Value>>:
    outcome : Maybe<&1,Outcome> <- Chan.recv(Outcome,signalOf(collector))
    release(collector,outcome)
def gatheredEvents(client: RpcClient,message: String,result: Maybe<&1,Outcome> & List<&2,V.Value>) -> IO(Result<&2,&2,String,List<&2,V.Value>>):
  match result:
    case (Some{Settled{}},events): IO.pure(Result<&2,&2,String,List<&2,V.Value>>,Done{events})
    case (_,_):
      do IO<Result<&2,&2,String,List<&2,V.Value>>>:
        stderr : String <- getStderr(client)
        return Fail{message ++ stderr}

# upstream waitForIdle: resolves at the next agent_settled event.
def waitForIdle(+client: RpcClient,timeout: U32) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    collector : Collector <- startCollecting(client,False{},timeout)
    result : Maybe<&1,Outcome> & List<&2,V.Value> <- finishCollecting(collector)
    events : Result<&2,&2,String,List<&2,V.Value>> <- gatheredEvents(client,"Timeout waiting for agent to become idle. Stderr: ",result)
    return Result.map(&2,&2,String,List<&2,V.Value>,Unit,values => Unit{},events)
# upstream collectEvents: every event up to and including agent_settled.
def collectEvents(+client: RpcClient,timeout: U32) -> IO(Result<&2,&2,String,List<&2,V.Value>>):
  do IO<Result<&2,&2,String,List<&2,V.Value>>>:
    collector : Collector <- startCollecting(client,True{},timeout)
    result : Maybe<&1,Outcome> & List<&2,V.Value> <- finishCollecting(collector)
    gatheredEvents(client,"Timeout collecting events. Stderr: ",result)
def prompted(+client: RpcClient,+collector: Collector,sent: Result<&2,&2,String,Unit>) -> IO(Result<&2,&2,String,List<&2,V.Value>>):
  match sent:
    case Fail{error}:
      do IO<Result<&2,&2,String,List<&2,V.Value>>>:
        released : Maybe<&1,Outcome> & List<&2,V.Value> <- release(collector,None{})
        return Fail{error}
    case Done{_}:
      do IO<Result<&2,&2,String,List<&2,V.Value>>>:
        result : Maybe<&1,Outcome> & List<&2,V.Value> <- finishCollecting(collector)
        gatheredEvents(client,"Timeout collecting events. Stderr: ",result)
# upstream promptAndWait: collect from before the prompt is sent until idle.
def promptAndWait(+client: RpcClient,message: String,images: Images(),timeout: U32) -> IO(Result<&2,&2,String,List<&2,V.Value>>):
  do IO<Result<&2,&2,String,List<&2,V.Value>>>:
    collector : Collector <- startCollecting(client,True{},timeout)
    sent : Result<&2,&2,String,Unit> <- prompt(client,message,images)
    prompted(client,collector,sent)
