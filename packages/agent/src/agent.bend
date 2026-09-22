import Base
import ./types.bend as T
import ./agent-loop.bend as Loop
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/ref.bend as R
import ../../runtime/src/abort.bend as Abort
import ./stream-fn.bend as Provider
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/date.bend as Date
import ../../ai/src/utils/tool-declaration.bend as Declaration
import ../../runtime/src/record.bend as Record
import ../../ai/src/utils/transcript.bend as Transcript
import ../../runtime/src/string.bend as Set
import ../../runtime/src/deferred.bend as D
import ../../runtime/src/big-nat.bend as N
import ../../ai/src/utils/model-api.bend as Api
import ../../runtime/src/fifo.bend as Fifo
import ../../runtime/src/fetch.bend as Fetch

# Pure state transitions from agent.ts. The Agent owner provides synchronization
# and waits for listeners before applying finishRunState; agent_end alone is not idle.
type AgentInitialState<-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data> is Data:
  AgentInitialState{systemPromptState: Maybe<&2, String>, model: Maybe<&2, Ai.Model<Ai.JsonValue>>, thinkingLevel: Maybe<&2, T.ThinkingLevel()>, tools: Maybe<&2, List<&2, T.AgentTool<Details, Error>>>, messages: Maybe<&2, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>>}

def defaultModel(-Value: Data) -> Ai.Model<Value>:
  +zero = F.fromU32(0)
  Ai.Model{"unknown", "unknown", Ai.CustomModelApi{"unknown"}, "unknown", "", False{}, None{}, Nil{}, Ai.ModelCost{zero, zero, zero, zero, None{}}, zero, zero, None{}, None{}, None{}}

def defaultConvertToLlm(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, messages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>) -> List<&2, Ai.Message<Schema.Value, Schema.Value, DiagnosticDetails, Details>>:
  match messages:
    case Nil{}: Nil{}
    case T.LlmMessage{value} <> rest: value <> defaultConvertToLlm(DiagnosticDetails, Details, Custom, Error, rest)
    case T.CustomMessage{_} <> rest: defaultConvertToLlm(DiagnosticDetails, Details, Custom, Error, rest)

def declarations(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, tools: List<&2, T.AgentTool<Details, Error>>) -> List<&2, Ai.Tool<Schema.Value>>:
  match tools:
    case Nil{}: Nil{}
    case tool <> rest: T.toTool(Details, Error, tool) <> declarations(DiagnosticDetails, Details, Custom, Error, rest)

def prependInitial(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, initial: Maybe<&2, Ai.SystemMessage<Schema.Value>>, messages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>) -> List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>:
  match initial:
    case None{}: messages
    case Some{value}: T.LlmMessage{Ai.System{value}} <> messages

def initialMessages(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, initialPrompt: Maybe<&2, String>, tools: List<&2, Ai.Tool<Schema.Value>>, messages: List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>) -> List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>:
  match messages:
    case T.LlmMessage{Ai.System{value}} <> rest: T.LlmMessage{Ai.System{value}} <> rest
    case other: prependInitial(DiagnosticDetails, Details, Custom, Error, Transcript.createInitialSystemMessage(Schema.Value, initialPrompt, Some{tools}), other)

def createState(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, initial: AgentInitialState<DiagnosticDetails, Details, Custom, Error>) -> T.AgentState<DiagnosticDetails, Details, Custom, Error>:
  match initial:
    case AgentInitialState{initialPrompt, model, thinking, tools, messages}:
      +selectedTools = Maybe.default(&2, List<&2, T.AgentTool<Details, Error>>, tools, Nil{})
      T.AgentState{Maybe.default(&2, Ai.Model<Ai.JsonValue>, model, defaultModel(Ai.JsonValue)), Maybe.default(&2, T.ThinkingLevel(), thinking, Ai.Off{}), selectedTools, initialMessages(DiagnosticDetails, Details, Custom, Error, initialPrompt, declarations(DiagnosticDetails, Details, Custom, Error, selectedTools), Maybe.default(&2, List<&2, T.AgentMessage<DiagnosticDetails, Details, Custom>>, messages, Nil{})), False{}, None{}, Set.empty(), None{}}

def systemPromptState(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, agentState: T.AgentState<DiagnosticDetails, Details, Custom, Error>) -> String:
  match agentState:
    case T.AgentState{_, _, _, messages, _, _, _, _}: Transcript.getCurrentSystemPrompt(Schema.Value, Schema.Value, DiagnosticDetails, Details, defaultConvertToLlm(DiagnosticDetails, Details, Custom, Error, messages))

def beginRun(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, agentState: T.AgentState<DiagnosticDetails, Details, Custom, Error>) -> T.AgentState<DiagnosticDetails, Details, Custom, Error>:
  match agentState:
    case T.AgentState{model, thinking, tools, messages, _, _, pending, _}: T.AgentState{model, thinking, tools, messages, True{}, None{}, pending, None{}}

def finishRunState(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, agentState: T.AgentState<DiagnosticDetails, Details, Custom, Error>) -> T.AgentState<DiagnosticDetails, Details, Custom, Error>:
  match agentState:
    case T.AgentState{model, thinking, tools, messages, _, _, _, error}: T.AgentState{model, thinking, tools, messages, False{}, None{}, Set.empty(), error}

def nonemptyError(previous: Maybe<&2, String>, incoming: Maybe<&2, String>) -> Maybe<&2, String>:
  match incoming:
    case None{}: previous
    case Some{+text}: Bool.pick(Maybe<&2, String>, String.is_empty(text), previous, Some{text})

def turnError(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, previous: Maybe<&2, String>, message: T.AgentMessage<DiagnosticDetails, Details, Custom>) -> Maybe<&2, String>:
  match message:
    case T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, error, _, _, _}}}: nonemptyError(previous, error)
    case _: previous

def processEvent(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, -PartialResult: Data, -ExecutionResult: Data, agentState: T.AgentState<DiagnosticDetails, Details, Custom, Error>, event: T.AgentEvent<DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult>) -> T.AgentState<DiagnosticDetails, Details, Custom, Error>:
  match agentState event:
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.MessageStart{message}: T.AgentState{model, thinking, tools, messages, streaming, Some{message}, pending, error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.MessageUpdate{message, _}: T.AgentState{model, thinking, tools, messages, streaming, Some{message}, pending, error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.MessageEnd{message}: T.AgentState{model, thinking, tools, List.append(&2, T.AgentMessage<DiagnosticDetails, Details, Custom>, messages, message <> Nil{}), streaming, None{}, pending, error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.ToolExecutionStart{id, _, _}: T.AgentState{model, thinking, tools, messages, streaming, partial, Set.insert(pending, id), error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.ToolExecutionEnd{id, _, _, _}: T.AgentState{model, thinking, tools, messages, streaming, partial, Set.remove(pending, id), error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.TurnEnd{message, _}: T.AgentState{model, thinking, tools, messages, streaming, partial, pending, turnError(DiagnosticDetails, Details, Custom, Error, error, message)}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.AgentEnd{_}: T.AgentState{model, thinking, tools, messages, streaming, None{}, pending, error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} _: T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error}

# Replays the transcript baseline, retaining model/thinking and executable tools.
# The synchronized owner rejects reset during a run and clears both queues.
def stateReset(-DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, agentState: T.AgentState<DiagnosticDetails, Details, Custom, Error>) -> T.AgentState<DiagnosticDetails, Details, Custom, Error>:
  match agentState:
    case T.AgentState{model, thinking, tools, messages, _, _, _, _}:
      baseline = Transcript.getCurrentSystemMessage(Schema.Value, Schema.Value, DiagnosticDetails, Details, defaultConvertToLlm(DiagnosticDetails, Details, Custom, Error, messages))
      T.AgentState{model, thinking, tools, prependInitial(DiagnosticDetails, Details, Custom, Error, baseline, Nil{}), False{}, None{}, Set.empty(), None{}}

# User-editable state is an explicit value transition. Runtime fields remain
# owned by the run lifecycle, including when an update occurs during delivery.
type StateChange<-G: Data, -D: Data, -M: Data, -E: Data> is Data:
  SetModel{model: Ai.Model<Ai.JsonValue>}
  SetThinkingLevel{level: T.ThinkingLevel()}
  SetTools{tools: List<&2, T.AgentTool<D, E>>}
  ReplaceMessages{messages: List<&2, T.AgentMessage<G, D, M>>}
  AppendMessage{message: T.AgentMessage<G, D, M>}
def applyChange(-G: Data, -D: Data, -M: Data, -E: Data, agentState: T.AgentState<G, D, M, E>, change: StateChange<G, D, M, E>) -> T.AgentState<G, D, M, E>:
  match agentState change:
    case T.AgentState{_, thinking, tools, messages, streaming, current, pending, error} SetModel{model}: T.AgentState{model, thinking, tools, messages, streaming, current, pending, error}
    case T.AgentState{model, _, tools, messages, streaming, current, pending, error} SetThinkingLevel{thinking}: T.AgentState{model, thinking, tools, messages, streaming, current, pending, error}
    case T.AgentState{model, thinking, _, messages, streaming, current, pending, error} SetTools{tools}: T.AgentState{model, thinking, tools, messages, streaming, current, pending, error}
    case T.AgentState{model, thinking, tools, _, streaming, current, pending, error} ReplaceMessages{messages}: T.AgentState{model, thinking, tools, messages, streaming, current, pending, error}
    case T.AgentState{model, thinking, tools, messages, streaming, current, pending, error} AppendMessage{message}: T.AgentState{model, thinking, tools, List.append(&2, T.AgentMessage<G, D, M>, messages, message <> Nil{}), streaming, current, pending, error}


# Immutable counterpart of agent.ts PendingMessageQueue. The Agent owner
# commits these transitions atomically with its other runtime state.
type PendingMessageQueue<-Message: Data> is Data:
  PendingMessageQueue{mode: T.QueueMode, messages: Fifo.Queue<Message>}

def newPending(-M: Data, mode: T.QueueMode) -> PendingMessageQueue<M>:
  PendingMessageQueue{mode, Fifo.new(M)}
def getModePending(-M: Data, queue: PendingMessageQueue<M>) -> T.QueueMode:
  match queue:
    case PendingMessageQueue{value, _}: value
def setModePending(-M: Data, queue: PendingMessageQueue<M>, mode: T.QueueMode) -> PendingMessageQueue<M>:
  match queue:
    case PendingMessageQueue{_, messages}: PendingMessageQueue{mode, messages}
def enqueuePending(-M: Data, queue: PendingMessageQueue<M>, message: M) -> PendingMessageQueue<M>:
  match queue:
    case PendingMessageQueue{mode, messages}: PendingMessageQueue{mode, Fifo.enqueue(M, messages, message)}
def hasItems(-M: Data, queue: PendingMessageQueue<M>) -> Bool:
  match queue:
    case PendingMessageQueue{_, Fifo.Queue{Nil{}, Nil{}}}: False{}
    case _: True{}
def values(-M: Data, queue: PendingMessageQueue<M>) -> List<&2, M>:
  match queue:
    case PendingMessageQueue{_, messages}: Fifo.drain(M, messages)
def clearPending(-M: Data, queue: PendingMessageQueue<M>) -> PendingMessageQueue<M>:
  match queue:
    case PendingMessageQueue{mode, _}: newPending(M, mode)
def drainedOne(-M: Data, popped: Fifo.Queue<M> & Maybe<&2, M>) -> PendingMessageQueue<M> & List<&2, M>:
  match popped:
    case Tuple{remaining, None{}}: (PendingMessageQueue{T.OneAtATime{}, remaining}, Nil{})
    case Tuple{remaining, Some{value}}: (PendingMessageQueue{T.OneAtATime{}, remaining}, value <> Nil{})
def drainPending(-M: Data, queue: PendingMessageQueue<M>) -> PendingMessageQueue<M> & List<&2, M>:
  match queue:
    case PendingMessageQueue{T.All{}, messages}: (newPending(M, T.All{}), Fifo.drain(M, messages))
    case PendingMessageQueue{T.OneAtATime{}, messages}: drainedOne(M, Fifo.dequeue(M, messages))


type Queues<-M: Data> is Data:
  Queues{steering: PendingMessageQueue<M>, followUp: PendingMessageQueue<M>}
type QueueKind is Data:
  QueuesSteering{}
  FollowUp{}

def newQueues(-M: Data, steering: T.QueueMode, followUps: T.QueueMode) -> Queues<M>:
  Queues{newPending(M, steering), newPending(M, followUps)}
def defaultQueues(-M: Data) -> Queues<M>: newQueues(M, T.OneAtATime{}, T.OneAtATime{})
def enqueueQueues(-M: Data, queues: Queues<M>, kind: QueueKind, message: M) -> Queues<M>:
  match queues kind:
    case Queues{steering, followUps} QueuesSteering{}: Queues{enqueuePending(M, steering, message), followUps}
    case Queues{steering, followUps} FollowUp{}: Queues{steering, enqueuePending(M, followUps, message)}
def setModeQueues(-M: Data, queues: Queues<M>, kind: QueueKind, mode: T.QueueMode) -> Queues<M>:
  match queues kind:
    case Queues{steering, followUps} QueuesSteering{}: Queues{setModePending(M, steering, mode), followUps}
    case Queues{steering, followUps} FollowUp{}: Queues{steering, setModePending(M, followUps, mode)}
def clearQueues(-M: Data, queues: Queues<M>, kind: QueueKind) -> Queues<M>:
  match queues kind:
    case Queues{steering, followUps} QueuesSteering{}: Queues{clearPending(M, steering), followUps}
    case Queues{steering, followUps} FollowUp{}: Queues{steering, clearPending(M, followUps)}
def clearAll(-M: Data, queues: Queues<M>) -> Queues<M>:
  match queues:
    case Queues{steering, followUps}: Queues{clearPending(M, steering), clearPending(M, followUps)}
def queuesHaveMessages(-M: Data, queues: Queues<M>) -> Bool:
  match queues:
    case Queues{steering, followUps}: hasItems(M, steering) || hasItems(M, followUps)
def drainedQueues(-M: Data, kind: QueueKind, other: PendingMessageQueue<M>, result: PendingMessageQueue<M> & List<&2, M>) -> Queues<M> & List<&2, M>:
  match kind result:
    case QueuesSteering{} Tuple{remaining, messages}: (Queues{remaining, other}, messages)
    case FollowUp{} Tuple{remaining, messages}: (Queues{other, remaining}, messages)
def drainQueues(-M: Data, queues: Queues<M>, kind: QueueKind) -> Queues<M> & List<&2, M>:
  match queues kind:
    case Queues{steering, followUps} QueuesSteering{}: drainedQueues(M, QueuesSteering{}, followUps, drainPending(M, steering))
    case Queues{steering, followUps} FollowUp{}: drainedQueues(M, FollowUp{}, steering, drainPending(M, followUps))

def getModeQueues(-M: Data, queues: Queues<M>, kind: QueueKind) -> T.QueueMode:
  match queues kind:
    case Queues{steering, _} QueuesSteering{}: getModePending(M, steering)
    case Queues{_, followUps} FollowUp{}: getModePending(M, followUps)


# A pure decision consumed by the Agent owner when it claims the next run.
# Planning and queue changes must be committed together with that run claim.
type ContinueError is Data:
  ContinueBusy{}
  NoMessages{}
  AssistantTail{}
def errorMessage(error: ContinueError) -> String:
  match error:
    case ContinueBusy{}: "Agent is already processing. Wait for completion before continuing."
    case NoMessages{}: "No messages to continue from"
    case AssistantTail{}: "Cannot continue from message role: assistant"

type Plan<-M: Data> is Data:
  Prompt{messages: List<&2, M>, skipInitialSteeringPoll: Bool}
  Continue{}
type Tail is Data:
  Empty{}
  Assistant{}
  Other{}

def isSystem(-G: Data, -D: Data, -C: Data, message: T.AgentMessage<G, D, C>) -> Bool:
  match message:
    case T.LlmMessage{Ai.System{_}}: True{}
    case _: False{}
def finalTail(-G: Data, -D: Data, -C: Data, nonSystem: Bool, message: T.AgentMessage<G, D, C>) -> Tail:
  match message:
    case T.LlmMessage{Ai.Assistant{_}}: Assistant{}
    case _: Bool.pick(Tail, nonSystem, Other{}, Empty{})
def tail(-G: Data, -D: Data, -C: Data, messages: List<&2, T.AgentMessage<G, D, C>>, nonSystem: Bool) -> Tail:
  match messages:
    case Nil{}: Empty{}
    case +last <> Nil{}: finalTail(G, D, C, nonSystem || Bool.not(isSystem(G, D, C, last)), last)
    case message <> rest: tail(G, D, C, rest, nonSystem || Bool.not(isSystem(G, D, C, message)))

def followUpPlan(-M: Data, drained: Queues<M> & List<&2, M>) -> Queues<M> & Result<&2, &2, ContinueError, Plan<M>>:
  match drained:
    case Tuple{queues, Nil{}}: (queues, Fail{AssistantTail{}})
    case Tuple{queues, head <> rest}: (queues, Done{Prompt{head <> rest, False{}}})
def steeringPlan(-M: Data, drained: Queues<M> & List<&2, M>) -> Queues<M> & Result<&2, &2, ContinueError, Plan<M>>:
  match drained:
    case Tuple{queues, Nil{}}: followUpPlan(M, drainQueues(M, queues, FollowUp{}))
    case Tuple{queues, head <> rest}: (queues, Done{Prompt{head <> rest, True{}}})
def planTail(-M: Data, queues: Queues<M>, last: Tail) -> Queues<M> & Result<&2, &2, ContinueError, Plan<M>>:
  match last:
    case Empty{}: (queues, Fail{NoMessages{}})
    case Assistant{}: steeringPlan(M, drainQueues(M, queues, QueuesSteering{}))
    case Other{}: (queues, Done{Continue{}})
def continuationPlan(-G: Data, -D: Data, -C: Data, active: Bool, messages: List<&2, T.AgentMessage<G, D, C>>, queues: Queues<T.AgentMessage<G, D, C>>) -> Queues<T.AgentMessage<G, D, C>> & Result<&2, &2, ContinueError, Plan<T.AgentMessage<G, D, C>>>:
  match active:
    case True{}: (queues, Fail{ContinueBusy{}})
    case False{}: planTail(T.AgentMessage<G, D, C>, queues, tail(G, D, C, messages, False{}))


# The owner stores Agent state and queues together in State. Claiming a run and
# its pure preparation therefore share one transaction, with no effectful callback under
# the lock. ActiveRun handles are borrowed until the owner's final disposal.
type ActiveRun is Data:
  ActiveRun{completion: D.Deferred<Unit>, controller: Abort.AbortController<Unit>}
type Cell<-State: Data> is Data:
  Cell{value: State, active: Maybe<&2, ActiveRun>, retired: List<&2, ActiveRun>}
type Lifecycle<-State: Data> is Data:
  Lifecycle{cell: R.Ref<Cell<State>>}
type Prepared<-State: Data, -Value: Data> is Data:
  Prepared{state: State, value: Value}
type ClaimError<-Error: Data> is Data:
  LifeBusy{}
  Rejected{error: Error}
type Claimed<-Value: Data> is Data:
  Claimed{run: ActiveRun, value: Value}

def newLifecycle(-State: Data, value: State) -> IO(Lifecycle<State>):
  do IO<Lifecycle<State>>:
    cell : R.Ref<Cell<State>> <- R.new(Cell<State>, Cell{value, None{}, Nil{}})
    return Lifecycle{cell}
def createRun() -> IO(ActiveRun):
  do IO<ActiveRun>:
    completion : D.Deferred<Unit> <- D.new(Unit)
    controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    return ActiveRun{completion, controller}
def disposeRun(run: ActiveRun) -> IO(Unit):
  match run:
    case ActiveRun{completion, controller}:
      do IO<Unit>:
        D.dispose(Unit, completion)
        Abort.dispose(Unit, controller)
def same(left: ActiveRun, right: ActiveRun) -> Bool:
  match left right:
    case ActiveRun{D.Deferred{a}, _} ActiveRun{D.Deferred{b}, _}: R.same(D.State<Unit>, a, b)
def activeRunSignal(run: ActiveRun) -> Abort.AbortSignal<Unit>:
  match run:
    case ActiveRun{_, controller}: Abort.signal(Unit, controller)
def prepared(-State: Data, -Error: Data, -Value: Data, original: State, retired: List<&2, ActiveRun>, +run: ActiveRun, result: Result<&2, &2, Error, Prepared<State, Value>>) -> Cell<State> & Result<&2, &2, ClaimError<Error>, Claimed<Value>>:
  match result:
    case Fail{error}: (Cell{original, None{}, retired}, Fail{Rejected{error}})
    case Done{Prepared{next, value}}: (Cell{next, Some{run}, retired}, Done{Claimed{run, value}})
def claimState(-State: Data, -Error: Data, -Value: Data, cell: Cell<State>, run: ActiveRun, prepare: State -> Result<&2, &2, Error, Prepared<State, Value>>) -> Cell<State> & Result<&2, &2, ClaimError<Error>, Claimed<Value>>:
  match cell:
    case Cell{value, Some{active}, retired}: (Cell{value, Some{active}, retired}, Fail{LifeBusy{}})
    case Cell{+value, None{}, retired}: prepared(State, Error, Value, value, retired, run, prepare(value))
def claimedActiveRun(-Error: Data, -Value: Data, candidate: ActiveRun, result: Result<&2, &2, ClaimError<Error>, Claimed<Value>>) -> IO(Result<&2, &2, ClaimError<Error>, Claimed<Value>>):
  match result:
    case Done{value}: IO.pure(Result<&2, &2, ClaimError<Error>, Claimed<Value>>, Done{value})
    case Fail{error}:
      do IO<Result<&2, &2, ClaimError<Error>, Claimed<Value>>>:
        disposeRun(candidate)
        return Fail{error}
def claimLifecycle(-State: Data, -Error: Data, -Value: Data, owner: Lifecycle<State>, prepare: State -> Result<&2, &2, Error, Prepared<State, Value>>) -> IO(Result<&2, &2, ClaimError<Error>, Claimed<Value>>):
  match owner:
    case Lifecycle{cell}:
      do IO<Result<&2, &2, ClaimError<Error>, Claimed<Value>>>:
        +candidate : ActiveRun <- createRun()
        result : Result<&2, &2, ClaimError<Error>, Claimed<Value>> <- R.modify(Cell<State>, Result<&2, &2, ClaimError<Error>, Claimed<Value>>, cell, current => claimState(State, Error, Value, current, candidate, prepare))
        claimedActiveRun(Error, Value, candidate, result)
def modified(-State: Data, -Value: Type, active: Maybe<&2, ActiveRun>, retired: List<&2, ActiveRun>, result: State & Value) -> Cell<State> & Value:
  match result:
    case Tuple{next, value}: (Cell{next, active, retired}, value)
def modifyState(-State: Data, -Value: Type, cell: Cell<State>, transform: State -> Maybe<&2, ActiveRun> -> State & Value) -> Cell<State> & Value:
  match cell:
    case Cell{agentState, +active, retired}: modified(State, Value, active, retired, transform(agentState, active))
# Event reductions, queue updates and reset share the run-claim transaction.
def modify(-State: Data, -Value: Type, owner: Lifecycle<State>, transform: State -> Maybe<&2, ActiveRun> -> State & Value) -> IO(Value):
  match owner:
    case Lifecycle{cell}: R.modify(Cell<State>, Value, cell, current => modifyState(State, Value, current, transform))

def readValue(-State: Data, cell: Cell<State>) -> State:
  match cell:
    case Cell{value, _, _}: value
def readLifecycle(-State: Data, owner: Lifecycle<State>) -> IO(State):
  match owner:
    case Lifecycle{cell}:
      do IO<State>:
        current : Cell<State> <- R.read(Cell<State>, cell)
        return readValue(State, current)
def activeValue(-State: Data, cell: Cell<State>) -> Maybe<&2, ActiveRun>:
  match cell:
    case Cell{_, active, _}: active
def activeRun(-State: Data, owner: Lifecycle<State>) -> IO(Maybe<&2, ActiveRun>):
  match owner:
    case Lifecycle{cell}:
      do IO<Maybe<&2, ActiveRun>>:
        current : Cell<State> <- R.read(Cell<State>, cell)
        return activeValue(State, current)
def waitRun(active: Maybe<&2, ActiveRun>) -> IO(Unit):
  match active:
    case None{}: IO.pure(Unit, Unit{})
    case Some{ActiveRun{completion, _}}: D.result(Unit, completion)
def waitForIdleLifecycle(-State: Data, owner: Lifecycle<State>) -> IO(Unit):
  do IO<Unit>:
    active : Maybe<&2, ActiveRun> <- activeRun(State, owner)
    waitRun(active)
def abortRun(active: Maybe<&2, ActiveRun>) -> IO(Unit):
  match active:
    case None{}: IO.pure(Unit, Unit{})
    case Some{ActiveRun{_, controller}}:
      do IO<Unit>:
        won : Bool <- Abort.abort(Unit, controller, None{})
        return Unit{}
def abortLifecycle(-State: Data, owner: Lifecycle<State>) -> IO(Unit):
  do IO<Unit>:
    active : Maybe<&2, ActiveRun> <- activeRun(State, owner)
    abortRun(active)

# Called only after the executor and all awaited listeners have settled.
# A stale finishing handle cannot clear a newer run or reapply the reduction.
def finishMatched(-State: Data, value: State, +active: ActiveRun, retired: List<&2, ActiveRun>, reduce: State -> State, matches: Bool) -> Cell<State> & Bool:
  match matches:
    case True{}: (Cell{reduce(value), None{}, active <> retired}, True{})
    case False{}: (Cell{value, Some{active}, retired}, False{})
def finishState(-State: Data, cell: Cell<State>, run: ActiveRun, reduce: State -> State) -> Cell<State> & Bool:
  match cell:
    case Cell{value, None{}, retired}: (Cell{value, None{}, retired}, False{})
    case Cell{value, Some{+active}, retired}: finishMatched(State, value, active, retired, reduce, same(active, run))
def settle(run: ActiveRun, won: Bool) -> IO(Bool):
  match run won:
    case ActiveRun{completion, _} True{}:
      do IO<Bool>:
        settled : Bool <- D.resolve(Unit, completion, Unit{})
        return True{}
    case _ False{}: IO.pure(Bool, False{})
def finishOwnedRun(-State: Data, owner: Lifecycle<State>, +run: ActiveRun, reduce: State -> State) -> IO(Bool):
  match owner:
    case Lifecycle{cell}:
      do IO<Bool>:
        won : Bool <- R.modify(Cell<State>, Bool, cell, current => finishState(State, current, run, reduce))
        settle(run, won)

type RunError<-Error: Data> is Data:
  LifeClaimFailed{error: ClaimError<Error>}
  CallbackFailed{error: Error}
def recoverResult(-Error: Data, run: ActiveRun, result: Result<&2, &2, Error, Unit>, recover: ActiveRun -> Error -> IO(Result<&2, &2, Error, Unit>)) -> IO(Result<&2, &2, Error, Unit>):
  match result:
    case Done{value}: IO.pure(Result<&2, &2, Error, Unit>, Done{value})
    case Fail{error}: recover(run, error)
def runResult(-Error: Data, result: Result<&2, &2, Error, Unit>) -> Result<&2, &2, RunError<Error>, Unit>:
  match result:
    case Done{value}: Done{value}
    case Fail{error}: Fail{CallbackFailed{error}}
def executeClaim(-State: Data, -Error: Data, -Value: Data, owner: Lifecycle<State>, claimResult: Result<&2, &2, ClaimError<Error>, Claimed<Value>>, execute: Claimed<Value> -> IO(Result<&2, &2, Error, Unit>), recover: ActiveRun -> Error -> IO(Result<&2, &2, Error, Unit>), reduce: State -> State) -> IO(Result<&2, &2, RunError<Error>, Unit>):
  match claimResult:
    case Fail{error}: IO.pure(Result<&2, &2, RunError<Error>, Unit>, Fail{LifeClaimFailed{error}})
    case Done{Claimed{+run, value}}:
      do IO<Result<&2, &2, RunError<Error>, Unit>>:
        result : Result<&2, &2, Error, Unit> <- execute(Claimed{run, value})
        recovered : Result<&2, &2, Error, Unit> <- recoverResult(Error, run, result, recover)
        finished : Bool <- finishOwnedRun(State, owner, run, reduce)
        return runResult(Error, recovered)
# Like Agent.runWithLifecycle: recovery handles executor failure, and final
# state/idle settlement happens even when recovery itself returns an error.
def runWithLifecycle(-State: Data, -Error: Data, -Value: Data, +owner: Lifecycle<State>, prepare: State -> Result<&2, &2, Error, Prepared<State, Value>>, execute: Claimed<Value> -> IO(Result<&2, &2, Error, Unit>), recover: ActiveRun -> Error -> IO(Result<&2, &2, Error, Unit>), reduce: State -> State) -> IO(Result<&2, &2, RunError<Error>, Unit>):
  do IO<Result<&2, &2, RunError<Error>, Unit>>:
    result : Result<&2, &2, ClaimError<Error>, Claimed<Value>> <- claimLifecycle(State, Error, Value, owner, prepare)
    executeClaim(State, Error, Value, owner, result, execute, recover, reduce)

def disposeActiveRuns(runs: List<&2, ActiveRun>) -> IO(Unit):
  match runs:
    case Nil{}: IO.pure(Unit, Unit{})
    case run <> rest:
      do IO<Unit>:
        disposeRun(run)
        disposeActiveRuns(rest)
def disposed(-State: Data, cell: Cell<State>) -> IO(State):
  match cell:
    case Cell{value, None{}, retired}:
      do IO<State>:
        disposeActiveRuns(retired)
        return value
    case Cell{_, Some{_}, _}: IO.die(State, 1, "Agent lifecycle disposed during an active run")
# Retire owner/run/signal aliases and drain waiters before final disposal.
# Completed signals remain inspectable throughout the owner's lifetime.
def disposeLifecycle(-State: Data, owner: Lifecycle<State>) -> IO(State):
  match owner:
    case Lifecycle{cell}:
      do IO<State>:
        previous : Cell<State> <- R.dispose(Cell<State>, cell)
        disposed(State, previous)


# P/A/G/D/C are schema/arguments/diagnostics/details/custom message values;
# V/S/E/J are validated arguments/tool signal/tool error/model metadata.
# One synchronized owner couples transcript, queues and active-run status.
type OwnedState<-G: Data, -D: Data, -C: Data, -E: Data> is Data:
  OwnedState{state: T.AgentState<G, D, C, E>, queues: Queues<T.AgentMessage<G, D, C>>}
type OwnedRuntime<-G: Data, -D: Data, -C: Data, -E: Data> is Data:
  OwnedRuntime{lifecycle: Lifecycle<OwnedState<G, D, C, E>>}

def newRuntime(-G: Data, -D: Data, -C: Data, -E: Data, initial: AgentInitialState<G, D, C, E>, steeringMode: T.QueueMode, followUpMode: T.QueueMode) -> IO(OwnedRuntime<G, D, C, E>):
  do IO<OwnedRuntime<G, D, C, E>>:
    lifecycle : Lifecycle<OwnedState<G, D, C, E>> <- newLifecycle(OwnedState<G, D, C, E>, OwnedState{createState(G, D, C, E, initial), newQueues(T.AgentMessage<G, D, C>, steeringMode, followUpMode)})
    return OwnedRuntime{lifecycle}
def snapshotRuntime(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>) -> IO(OwnedState<G, D, C, E>):
  match runtime:
    case OwnedRuntime{lifecycle}: readLifecycle(OwnedState<G, D, C, E>, lifecycle)
def stateValue(-G: Data, -D: Data, -C: Data, -E: Data, owned: OwnedState<G, D, C, E>) -> T.AgentState<G, D, C, E>:
  match owned:
    case OwnedState{agentState, _}: agentState
def readRuntime(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>) -> IO(T.AgentState<G, D, C, E>):
  do IO<T.AgentState<G, D, C, E>>:
    owned : OwnedState<G, D, C, E> <- snapshotRuntime(G, D, C, E, runtime)
    return stateValue(G, D, C, E, owned)
def history(-G: Data, -D: Data, -C: Data, -E: Data, agentState: T.AgentState<G, D, C, E>) -> List<&2, T.AgentMessage<G, D, C>>:
  match agentState:
    case T.AgentState{_, _, _, messages, _, _, _, _}: messages

def enqueueState(-G: Data, -D: Data, -C: Data, -E: Data, owned: OwnedState<G, D, C, E>, kind: QueueKind, message: T.AgentMessage<G, D, C>) -> OwnedState<G, D, C, E> & Unit:
  match owned:
    case OwnedState{agentState, queues}: (OwnedState{agentState, enqueueQueues(T.AgentMessage<G, D, C>, queues, kind, message)}, Unit{})
def enqueueRuntime(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>, kind: QueueKind, message: T.AgentMessage<G, D, C>) -> IO(Unit):
  match runtime:
    case OwnedRuntime{lifecycle}: modify(OwnedState<G, D, C, E>, Unit, lifecycle, owned => active => enqueueState(G, D, C, E, owned, kind, message))
def steerRuntime(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>, message: T.AgentMessage<G, D, C>) -> IO(Unit): enqueueRuntime(G, D, C, E, runtime, QueuesSteering{}, message)
def followUpRuntime(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>, message: T.AgentMessage<G, D, C>) -> IO(Unit): enqueueRuntime(G, D, C, E, runtime, FollowUp{}, message)
def updatedQueues(-G: Data, -D: Data, -C: Data, -E: Data, owned: OwnedState<G, D, C, E>, update: Queues<T.AgentMessage<G, D, C>> -> Queues<T.AgentMessage<G, D, C>>) -> OwnedState<G, D, C, E> & Unit:
  match owned:
    case OwnedState{agentState, queues}: (OwnedState{agentState, update(queues)}, Unit{})
def updateQueues(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>, update: Queues<T.AgentMessage<G, D, C>> -> Queues<T.AgentMessage<G, D, C>>) -> IO(Unit):
  match runtime:
    case OwnedRuntime{lifecycle}: modify(OwnedState<G, D, C, E>, Unit, lifecycle, owned => active => updatedQueues(G, D, C, E, owned, update))
def clearQueue(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>, kind: QueueKind) -> IO(Unit): updateQueues(G, D, C, E, runtime, queues => clearQueues(T.AgentMessage<G, D, C>, queues, kind))
def clearAllRuntimeQueues(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>) -> IO(Unit): updateQueues(G, D, C, E, runtime, queues => clearAll(T.AgentMessage<G, D, C>, queues))
def setQueueMode(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>, kind: QueueKind, mode: T.QueueMode) -> IO(Unit): updateQueues(G, D, C, E, runtime, queues => setModeQueues(T.AgentMessage<G, D, C>, queues, kind, mode))
def drainedRuntime(-G: Data, -D: Data, -C: Data, -E: Data, agentState: T.AgentState<G, D, C, E>, result: Queues<T.AgentMessage<G, D, C>> & List<&2, T.AgentMessage<G, D, C>>) -> OwnedState<G, D, C, E> & List<&2, T.AgentMessage<G, D, C>>:
  match result:
    case Tuple{queues, messages}: (OwnedState{agentState, queues}, messages)
def drainState(-G: Data, -D: Data, -C: Data, -E: Data, owned: OwnedState<G, D, C, E>, kind: QueueKind) -> OwnedState<G, D, C, E> & List<&2, T.AgentMessage<G, D, C>>:
  match owned:
    case OwnedState{agentState, queues}: drainedRuntime(G, D, C, E, agentState, drainQueues(T.AgentMessage<G, D, C>, queues, kind))
def drainRuntime(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>, kind: QueueKind) -> IO(List<&2, T.AgentMessage<G, D, C>>):
  match runtime:
    case OwnedRuntime{lifecycle}: modify(OwnedState<G, D, C, E>, List<&2, T.AgentMessage<G, D, C>>, lifecycle, owned => active => drainState(G, D, C, E, owned, kind))

def resetState(-G: Data, -D: Data, -C: Data, -E: Data, owned: OwnedState<G, D, C, E>, active: Maybe<&2, ActiveRun>) -> OwnedState<G, D, C, E> & Result<&2, &2, String, Unit>:
  match owned active:
    case OwnedState{agentState, queues} None{}: (OwnedState{stateReset(G, D, C, E, agentState), clearAll(T.AgentMessage<G, D, C>, queues)}, Done{Unit{}})
    case OwnedState{agentState, queues} Some{_}: (OwnedState{agentState, queues}, Fail{"Agent is already processing. Wait for completion before resetting."})
def resetRuntime(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>) -> IO(Result<&2, &2, String, Unit>):
  match runtime:
    case OwnedRuntime{lifecycle}: modify(OwnedState<G, D, C, E>, Result<&2, &2, String, Unit>, lifecycle, owned => active => resetState(G, D, C, E, owned, active))

def preparePrompt(-G: Data, -D: Data, -C: Data, -E: Data, owned: OwnedState<G, D, C, E>, messages: List<&2, T.AgentMessage<G, D, C>>) -> Result<&2, &2, String, Prepared<OwnedState<G, D, C, E>, Plan<T.AgentMessage<G, D, C>>>>:
  match owned:
    case OwnedState{agentState, queues}: Done{Prepared{OwnedState{beginRun(G, D, C, E, agentState), queues}, Prompt{messages, False{}}}}
def planned(-G: Data, -D: Data, -C: Data, -E: Data, agentState: T.AgentState<G, D, C, E>, result: Queues<T.AgentMessage<G, D, C>> & Result<&2, &2, ContinueError, Plan<T.AgentMessage<G, D, C>>>) -> Result<&2, &2, String, Prepared<OwnedState<G, D, C, E>, Plan<T.AgentMessage<G, D, C>>>>:
  match result:
    case Tuple{_, Fail{error}}: Fail{errorMessage(error)}
    case Tuple{queues, Done{plan}}: Done{Prepared{OwnedState{beginRun(G, D, C, E, agentState), queues}, plan}}
def prepareContinue(-G: Data, -D: Data, -C: Data, -E: Data, owned: OwnedState<G, D, C, E>) -> Result<&2, &2, String, Prepared<OwnedState<G, D, C, E>, Plan<T.AgentMessage<G, D, C>>>>:
  match owned:
    case OwnedState{+agentState, queues}: planned(G, D, C, E, agentState, continuationPlan(G, D, C, False{}, history(G, D, C, E, agentState), queues))
def beginPrompt(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>, messages: List<&2, T.AgentMessage<G, D, C>>) -> IO(Result<&2, &2, ClaimError<String>, Claimed<Plan<T.AgentMessage<G, D, C>>>>):
  match runtime:
    case OwnedRuntime{lifecycle}: claimLifecycle(OwnedState<G, D, C, E>, String, Plan<T.AgentMessage<G, D, C>>, lifecycle, owned => preparePrompt(G, D, C, E, owned, messages))
def beginContinue(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>) -> IO(Result<&2, &2, ClaimError<String>, Claimed<Plan<T.AgentMessage<G, D, C>>>>):
  match runtime:
    case OwnedRuntime{lifecycle}: claimLifecycle(OwnedState<G, D, C, E>, String, Plan<T.AgentMessage<G, D, C>>, lifecycle, owned => prepareContinue(G, D, C, E, owned))
def ended(-G: Data, -D: Data, -C: Data, -E: Data, owned: OwnedState<G, D, C, E>) -> OwnedState<G, D, C, E>:
  match owned:
    case OwnedState{agentState, queues}: OwnedState{finishRunState(G, D, C, E, agentState), queues}
def finishRuntimeRun(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>, run: ActiveRun) -> IO(Bool):
  match runtime:
    case OwnedRuntime{lifecycle}: finishOwnedRun(OwnedState<G, D, C, E>, lifecycle, run, owned => ended(G, D, C, E, owned))

def listenerRun(active: Maybe<&2, ActiveRun>) -> Result<&2, &2, String, ActiveRun>:
  match active:
    case None{}: Fail{"Agent listener invoked outside active run"}
    case Some{run}: Done{run}
def eventState(-G: Data, -D: Data, -C: Data, -E: Data, -Partial: Data, -Execution: Data, owned: OwnedState<G, D, C, E>, active: Maybe<&2, ActiveRun>, event: T.AgentEvent<G, D, C, Partial, Execution>) -> OwnedState<G, D, C, E> & Result<&2, &2, String, ActiveRun>:
  match owned:
    case OwnedState{agentState, queues}: (OwnedState{processEvent(G, D, C, E, Partial, Execution, agentState, event), queues}, listenerRun(active))
# Reduction happens before listener dispatch, including the source's error for
# an event outside a run. The returned handle carries the active signal.
def recordEvent(-G: Data, -D: Data, -C: Data, -E: Data, -Partial: Data, -Execution: Data, runtime: OwnedRuntime<G, D, C, E>, event: T.AgentEvent<G, D, C, Partial, Execution>) -> IO(Result<&2, &2, String, ActiveRun>):
  match runtime:
    case OwnedRuntime{lifecycle}: modify(OwnedState<G, D, C, E>, Result<&2, &2, String, ActiveRun>, lifecycle, owned => active => eventState(G, D, C, E, Partial, Execution, owned, active, event))
def abortRuntime(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>) -> IO(Unit):
  match runtime:
    case OwnedRuntime{lifecycle}: abortLifecycle(OwnedState<G, D, C, E>, lifecycle)
def waitForIdleRuntime(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>) -> IO(Unit):
  match runtime:
    case OwnedRuntime{lifecycle}: waitForIdleLifecycle(OwnedState<G, D, C, E>, lifecycle)
def disposeRuntime(-G: Data, -D: Data, -C: Data, -E: Data, runtime: OwnedRuntime<G, D, C, E>) -> IO(OwnedState<G, D, C, E>):
  match runtime:
    case OwnedRuntime{lifecycle}: disposeLifecycle(OwnedState<G, D, C, E>, lifecycle)

def changedState(-G: Data, -D: Data, -M: Data, -E: Data, owned: OwnedState<G, D, M, E>, change: StateChange<G, D, M, E>) -> OwnedState<G, D, M, E> & Unit:
  match owned:
    case OwnedState{agentState, queues}: (OwnedState{applyChange(G, D, M, E, agentState, change), queues}, Unit{})
def updateStateRuntime(-G: Data, -D: Data, -M: Data, -E: Data, runtime: OwnedRuntime<G, D, M, E>, change: StateChange<G, D, M, E>) -> IO(Unit):
  match runtime:
    case OwnedRuntime{lifecycle}: modify(OwnedState<G, D, M, E>, Unit, lifecycle, owned => active => changedState(G, D, M, E, owned, change))


# Ordered subscriptions with explicit registration positions. User callbacks
# run outside the lock. Each dispatch observes removals/additions before it
# selects the next listener, preserving the source's awaited live dispatch.
type Input<-Event: Data> is Data:
  Input{event: Event, signal: Abort.AbortSignal<Unit>}
def Handler(-Event: Data, -Error: Data) -> Data:
  C.Callback<Input<Event>, Loop.Emission<Error>>
type Entry<-Event: Data, -Error: Data> is Data:
  Entry{position: N.BigNat, callback: Handler(Event, Error)}
type State<-Event: Data, -Error: Data> is Data:
  State{next: N.BigNat, entries: List<&2, Entry<Event, Error>>}
type Listeners<-Event: Data, -Error: Data> is Data:
  Listeners{state: R.Ref<State<Event, Error>>}
type Subscription<-Event: Data, -Error: Data> is Data:
  Subscription{listeners: Listeners<Event, Error>, callback: Handler(Event, Error)}

def newListeners(-Event: Data, -Error: Data) -> IO(Listeners<Event, Error>):
  do IO<Listeners<Event, Error>>:
    agentState : R.Ref<State<Event, Error>> <- R.new(State<Event, Error>, State{N.zero(), Nil{}})
    return Listeners{agentState}
def contains(-Event: Data, -Error: Data, entries: List<&2, Entry<Event, Error>>, +callback: Handler(Event, Error)) -> Bool:
  match entries:
    case Nil{}: False{}
    case Entry{_, other} <> rest: C.same(Input<Event>, Loop.Emission<Error>, callback, other) || contains(Event, Error, rest, callback)
def added(-Event: Data, -Error: Data, +next: N.BigNat, entries: List<&2, Entry<Event, Error>>, callback: Handler(Event, Error), exists: Bool) -> State<Event, Error>:
  match exists:
    case True{}: State{next, entries}
    case False{}: State{N.add(next, N.one()), List.append(&2, Entry<Event, Error>, entries, Entry{next, callback} <> Nil{})}
def addState(-Event: Data, -Error: Data, agentState: State<Event, Error>, +callback: Handler(Event, Error)) -> State<Event, Error> & Unit:
  match agentState:
    case State{next, +entries}: (added(Event, Error, next, entries, callback, contains(Event, Error, entries, callback)), Unit{})
def subscribeListeners(-Event: Data, -Error: Data, +listeners: Listeners<Event, Error>, +callback: Handler(Event, Error)) -> IO(Subscription<Event, Error>):
  match listeners:
    case Listeners{+agentState}:
      do IO<Subscription<Event, Error>>:
        R.modify(State<Event, Error>, Unit, agentState, current => addState(Event, Error, current, callback))
        return Subscription{Listeners{agentState}, callback}
def remove(-Event: Data, -Error: Data, entries: List<&2, Entry<Event, Error>>, +callback: Handler(Event, Error)) -> List<&2, Entry<Event, Error>>:
  match entries:
    case Nil{}: Nil{}
    case Entry{position, +other} <> +rest:
      Bool.pick(List<&2, Entry<Event, Error>>, C.same(Input<Event>, Loop.Emission<Error>, callback, other), rest, Entry{position, other} <> remove(Event, Error, rest, callback))
def removeState(-Event: Data, -Error: Data, agentState: State<Event, Error>, callback: Handler(Event, Error)) -> State<Event, Error> & Unit:
  match agentState:
    case State{next, entries}: (State{next, remove(Event, Error, entries, callback)}, Unit{})
def unsubscribe(-Event: Data, -Error: Data, subscription: Subscription<Event, Error>) -> IO(Unit):
  match subscription:
    case Subscription{Listeners{agentState}, callback}: R.modify(State<Event, Error>, Unit, agentState, current => removeState(Event, Error, current, callback))
def less(order: Cmp) -> Bool:
  match order:
    case LT{}: True{}
    case _: False{}
def eligible(position: N.BigNat, cursor: Maybe<&2, N.BigNat>) -> Bool:
  match cursor:
    case None{}: True{}
    case Some{previous}: less(N.compare(previous, position))
def nextEntry(-Event: Data, -Error: Data, entries: List<&2, Entry<Event, Error>>, +cursor: Maybe<&2, N.BigNat>) -> Maybe<&2, Entry<Event, Error>>:
  match entries:
    case Nil{}: None{}
    case Entry{+position, callback} <> rest:
      Bool.pick(Maybe<&2, Entry<Event, Error>>, eligible(position, cursor), Some{Entry{position, callback}}, nextEntry(Event, Error, rest, cursor))
def selectedListeners(-Event: Data, -Error: Data, agentState: State<Event, Error>, cursor: Maybe<&2, N.BigNat>) -> Maybe<&2, Entry<Event, Error>>:
  match agentState:
    case State{_, entries}: nextEntry(Event, Error, entries, cursor)
# Phase/result arguments avoid mutual recursion: each callback settles before
# the next selection. Failure immediately stops this event's delivery.
@unsafe def dispatch(-Event: Data, -Error: Data, +listeners: Listeners<Event, Error>, +input: Input<Event>, cursor: Maybe<&2, N.BigNat>, result: Result<&2, &2, Error, Unit>, next: Maybe<&2, Entry<Event, Error>>, select: Bool) -> IO(Result<&2, &2, Error, Unit>):
  match listeners result next select:
    case Listeners{_} Fail{error} _ _: IO.pure(Result<&2, &2, Error, Unit>, Fail{error})
    case Listeners{+agentState} Done{_} _ True{}:
      do IO<Result<&2, &2, Error, Unit>>:
        current : State<Event, Error> <- R.read(State<Event, Error>, agentState)
        dispatch(Event, Error, Listeners{agentState}, input, None{}, Done{Unit{}}, selectedListeners(Event, Error, current, cursor), False{})
    case Listeners{agentState} Done{_} Some{Entry{position, callback}} False{}:
      do IO<Result<&2, &2, Error, Unit>>:
        delivery : Loop.Emission<Error> <- C.call(Input<Event>, Loop.Emission<Error>, callback, input)
        outcome : Result<&2, &2, Error, Unit> <- Loop.wait(Error, delivery)
        dispatch(Event, Error, Listeners{agentState}, input, Some{position}, outcome, None{}, True{})
    case Listeners{_} Done{_} None{} False{}: IO.pure(Result<&2, &2, Error, Unit>, Done{Unit{}})
# The first callback starts inline, before returning ownership of pending
# delivery. Subsequent callbacks remain live-selected after each completion.
def resume(-Event: Data, -Error: Data, listeners: Listeners<Event, Error>, input: Input<Event>, position: N.BigNat, delivery: Loop.Emission<Error>) -> IO(Result<&2, &2, Error, Unit>):
  do IO<Result<&2, &2, Error, Unit>>:
    outcome : Result<&2, &2, Error, Unit> <- Loop.wait(Error, delivery)
    dispatch(Event, Error, listeners, input, Some{position}, outcome, None{}, True{})
def startSelected(-Event: Data, -Error: Data, listeners: Listeners<Event, Error>, +input: Input<Event>, selectedListeners: Maybe<&2, Entry<Event, Error>>) -> IO(Loop.Emission<Error>):
  match selectedListeners:
    case None{}: IO.pure(Loop.Emission<Error>, Loop.EmissionReady{Done{Unit{}}})
    case Some{Entry{position, callback}}:
      do IO<Loop.Emission<Error>>:
        delivery : Loop.Emission<Error> <- C.call(Input<Event>, Loop.Emission<Error>, callback, input)
        Loop.startEmission(Error, resume(Event, Error, listeners, input, position, delivery))
def start(-Event: Data, -Error: Data, listeners: Listeners<Event, Error>, event: Event, abortSignal: Abort.AbortSignal<Unit>) -> IO(Loop.Emission<Error>):
  match listeners:
    case Listeners{+agentState}:
      do IO<Loop.Emission<Error>>:
        current : State<Event, Error> <- R.read(State<Event, Error>, agentState)
        startSelected(Event, Error, Listeners{agentState}, Input{event, abortSignal}, selectedListeners(Event, Error, current, None{}))
def emitListeners(-Event: Data, -Error: Data, listeners: Listeners<Event, Error>, event: Event, abortSignal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, Error, Unit>):
  do IO<Result<&2, &2, Error, Unit>>:
    delivery : Loop.Emission<Error> <- start(Event, Error, listeners, event, abortSignal)
    Loop.wait(Error, delivery)
# Callbacks are borrowed. Drain in-flight dispatches before disposing the
# registry, then retire callback handles according to their own ownership.
def disposeListeners(-Event: Data, -Error: Data, listeners: Listeners<Event, Error>) -> IO(Unit):
  match listeners:
    case Listeners{agentState}:
      do IO<Unit>:
        previous : State<Event, Error> <- R.dispose(State<Event, Error>, agentState)
        return Unit{}


type DeliveryError<-Failure: Data> is Data:
  OutsideRun{message: String}
  ListenerFailed{error: Failure}
def delivered(-Failure: Data, result: Result<&2, &2, Failure, Unit>) -> Result<&2, &2, DeliveryError<Failure>, Unit>:
  match result:
    case Done{value}: Done{value}
    case Fail{error}: Fail{ListenerFailed{error}}
def completedEvents(-Failure: Data, delivery: Loop.Emission<Failure>) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
    result : Result<&2, &2, Failure, Unit> <- Loop.wait(Failure, delivery)
    return delivered(Failure, result)
def startDispatch(-G: Data, -D: Data, -C: Data, -Partial: Data, -Execution: Data, -Failure: Data, listeners: Listeners<T.AgentEvent<G, D, C, Partial, Execution>, Failure>, event: T.AgentEvent<G, D, C, Partial, Execution>, active: Result<&2, &2, String, ActiveRun>) -> IO(Loop.Emission<DeliveryError<Failure>>):
  match active:
    case Fail{message}: IO.pure(Loop.Emission<DeliveryError<Failure>>, Loop.EmissionReady{Fail{OutsideRun{message}}})
    case Done{run}:
      do IO<Loop.Emission<DeliveryError<Failure>>>:
        delivery : Loop.Emission<Failure> <- start(T.AgentEvent<G, D, C, Partial, Execution>, Failure, listeners, event, activeRunSignal(run))
        Loop.startEmission(DeliveryError<Failure>, completedEvents(Failure, delivery))
# State reduction and the first listener's immediate effects happen before
# returning. The caller owns and must await the remaining delivery.
def startEvents(-G: Data, -D: Data, -C: Data, -E: Data, -Partial: Data, -Execution: Data, -Failure: Data, runtime: OwnedRuntime<G, D, C, E>, listeners: Listeners<T.AgentEvent<G, D, C, Partial, Execution>, Failure>, +event: T.AgentEvent<G, D, C, Partial, Execution>) -> IO(Loop.Emission<DeliveryError<Failure>>):
  do IO<Loop.Emission<DeliveryError<Failure>>>:
    active : Result<&2, &2, String, ActiveRun> <- recordEvent(G, D, C, E, Partial, Execution, runtime, event)
    startDispatch(G, D, C, Partial, Execution, Failure, listeners, event, active)

# Awaited delivery is the same start operation followed by its completion.
def processEvents(-G: Data, -D: Data, -C: Data, -E: Data, -Partial: Data, -Execution: Data, -Failure: Data, runtime: OwnedRuntime<G, D, C, E>, listeners: Listeners<T.AgentEvent<G, D, C, Partial, Execution>, Failure>, +event: T.AgentEvent<G, D, C, Partial, Execution>) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
    delivery : Loop.Emission<DeliveryError<Failure>> <- startEvents(G, D, C, E, Partial, Execution, Failure, runtime, listeners, event)
    Loop.wait(DeliveryError<Failure>, delivery)


def emptyUsage() -> Ai.Usage:
  +zero = F.fromU32(0)
  Ai.Usage{zero, zero, zero, zero, None{}, None{}, zero, Ai.UsageCost{zero, zero, zero, zero, zero}}
def failureMessage(-G: Data, model: Ai.Model<Ai.JsonValue>, aborted: Bool, error: String, timestamp: F.F64) -> Ai.AssistantMessage<Schema.Value, G>:
  match model:
    case Ai.Model{id, _, api, provider, _, _, _, _, _, _, _, _, _, _}:
      Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{"", None{}}} <> Nil{}, Api.name(api), provider, id, None{}, None{}, None{}, None{}, emptyUsage(), Bool.pick(Ai.StopReason, aborted, Ai.Aborted{}, Ai.Error{}), None{}, Some{error}, None{}, None{}, timestamp}
def fromState(-G: Data, -D: Data, -C: Data, -E: Data, agentState: T.AgentState<G, D, C, E>, aborted: Bool, error: String, timestamp: F.F64) -> T.AgentMessage<G, D, C>:
  match agentState:
    case T.AgentState{model, _, _, _, _, _, _, _}: T.LlmMessage{Ai.Assistant{failureMessage(G, model, aborted, error, timestamp)}}
def events(-G: Data, -D: Data, -C: Data, -Partial: Data, -Execution: Data, +message: T.AgentMessage<G, D, C>) -> List<&2, T.AgentEvent<G, D, C, Partial, Execution>>:
  T.MessageStart{message} <> T.MessageEnd{message} <> T.TurnEnd{message, Nil{}} <> T.AgentEnd{message <> Nil{}} <> Nil{}
def deliver(-G: Data, -D: Data, -C: Data, -E: Data, -Partial: Data, -Execution: Data, -Failure: Data, +runtime: OwnedRuntime<G, D, C, E>, +listeners: Listeners<T.AgentEvent<G, D, C, Partial, Execution>, Failure>, messages: List<&2, T.AgentEvent<G, D, C, Partial, Execution>>, result: Result<&2, &2, DeliveryError<Failure>, Unit>) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  match messages result:
    case _ Fail{error}: IO.pure(Result<&2, &2, DeliveryError<Failure>, Unit>, Fail{error})
    case Nil{} Done{_}: IO.pure(Result<&2, &2, DeliveryError<Failure>, Unit>, Done{Unit{}})
    case event <> rest Done{_}:
      do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
        outcome : Result<&2, &2, DeliveryError<Failure>, Unit> <- processEvents(G, D, C, E, Partial, Execution, Failure, runtime, listeners, event)
        deliver(G, D, C, E, Partial, Execution, Failure, runtime, listeners, rest, outcome)
# Explicit timestamp supports deterministic tests; production uses Date.now.
def handleRunFailureAt(-G: Data, -D: Data, -C: Data, -E: Data, -Partial: Data, -Execution: Data, -Failure: Data, +runtime: OwnedRuntime<G, D, C, E>, listeners: Listeners<T.AgentEvent<G, D, C, Partial, Execution>, Failure>, error: String, aborted: Bool, timestamp: F.F64) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
    agentState : T.AgentState<G, D, C, E> <- readRuntime(G, D, C, E, runtime)
    deliver(G, D, C, E, Partial, Execution, Failure, runtime, listeners, events(G, D, C, Partial, Execution, fromState(G, D, C, E, agentState, aborted, error, timestamp)), Done{Unit{}})
def handleRunFailure(-G: Data, -D: Data, -C: Data, -E: Data, -Partial: Data, -Execution: Data, -Failure: Data, +runtime: OwnedRuntime<G, D, C, E>, listeners: Listeners<T.AgentEvent<G, D, C, Partial, Execution>, Failure>, error: String, aborted: Bool) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
    agentState : T.AgentState<G, D, C, E> <- readRuntime(G, D, C, E, runtime)
    timestamp : F.F64 <- Date.now()
    deliver(G, D, C, E, Partial, Execution, Failure, runtime, listeners, events(G, D, C, Partial, Execution, fromState(G, D, C, E, agentState, aborted, error, timestamp)), Done{Unit{}})
def recover(-G: Data, -D: Data, -C: Data, -E: Data, -Partial: Data, -Execution: Data, -Failure: Data, runtime: OwnedRuntime<G, D, C, E>, listeners: Listeners<T.AgentEvent<G, D, C, Partial, Execution>, Failure>, run: ActiveRun, result: Result<&2, &2, Failure, Unit>, renderError: Failure -> String) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  match result:
    case Done{_}: IO.pure(Result<&2, &2, DeliveryError<Failure>, Unit>, Done{Unit{}})
    case Fail{error}:
      do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
        aborted : Bool <- Abort.aborted(Unit, activeRunSignal(run))
        handleRunFailure(G, D, C, E, Partial, Execution, Failure, runtime, listeners, renderError(error), aborted)
# The prepared run is already claimed. Recovery is awaited as part of that
# run; even a recovery-listener failure reaches the final state/idle cleanup.
def runClaimedFailure(-G: Data, -D: Data, -C: Data, -E: Data, -Partial: Data, -Execution: Data, -Failure: Data, -Value: Data, +runtime: OwnedRuntime<G, D, C, E>, listeners: Listeners<T.AgentEvent<G, D, C, Partial, Execution>, Failure>, claimed: Claimed<Value>, execute: Claimed<Value> -> IO(Result<&2, &2, Failure, Unit>), renderError: Failure -> String) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  match claimed:
    case Claimed{+run, value}:
      do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
        result : Result<&2, &2, Failure, Unit> <- execute(Claimed{run, value})
        outcome : Result<&2, &2, DeliveryError<Failure>, Unit> <- recover(G, D, C, E, Partial, Execution, Failure, runtime, listeners, run, result, renderError)
        finished : Bool <- finishRuntimeRun(G, D, C, E, runtime, run)
        return outcome


def HooksSignal() -> Data: Abort.AbortSignal<Unit>
def PrepareResult(-Update: Data, -Error: Data) -> Data: Result<&2, &2, Error, Maybe<&2, Update>>
def StopHook(-Turn: Data, -Error: Data) -> Data: C.Callback<T.ToolHookInput<Turn>, Result<&2, &2, Error, Bool>>
def LegacyHook(-Update: Data, -Error: Data) -> Data: C.Callback<Maybe<&2, HooksSignal()>, PrepareResult(Update, Error)>
def ContextHook(-Turn: Data, -Update: Data, -Error: Data) -> Data: C.Callback<T.ToolHookInput<Turn>, PrepareResult(Update, Error)>

# These handles are borrowed from the Agent's mutable options. Preparation
# rereads both forms on every invocation; stop hooks are captured per run.
type Hooks<-Turn: Data, -Update: Data, -Error: Data> is Data:
  Hooks{shouldStopAfterTurn: Maybe<&2, StopHook(Turn, Error)>, prepareNextTurn: Maybe<&2, LegacyHook(Update, Error)>, prepareNextTurnWithContext: Maybe<&2, ContextHook(Turn, Update, Error)>}
type Adapters<-Turn: Data, -Update: Data, -Error: Data> is Data:
  Adapters{shouldStopAfterTurn: Maybe<&2, C.Callback<Turn, Result<&2, &2, Error, Bool>>>, prepareNextTurn: Maybe<&2, C.Callback<Turn, PrepareResult(Update, Error)>>}
type StopCapture<-State: Data, -Turn: Data, -Error: Data> is Data:
  StopCapture{lifecycle: Lifecycle<State>, hook: StopHook(Turn, Error)}
type PrepareCapture<-State: Data, -Turn: Data, -Update: Data, -Error: Data> is Data:
  PrepareCapture{lifecycle: Lifecycle<State>, hooks: R.Ref<Hooks<Turn, Update, Error>>}

def signalHooks(-State: Data, lifecycle: Lifecycle<State>) -> IO(Maybe<&2, HooksSignal()>):
  do IO<Maybe<&2, HooksSignal()>>:
    active : Maybe<&2, ActiveRun> <- activeRun(State, lifecycle)
    return Maybe.map(&2, ActiveRun, HooksSignal(), run => activeRunSignal(run), active)
def stopBody(-State: Data, -Turn: Data, -Error: Data, capture: StopCapture<State, Turn, Error>, turnContext: Turn) -> IO(Result<&2, &2, Error, Bool>):
  match capture:
    case StopCapture{lifecycle, hook}:
      do IO<Result<&2, &2, Error, Bool>>:
        active : Maybe<&2, HooksSignal()> <- signalHooks(State, lifecycle)
        C.call(T.ToolHookInput<Turn>, Result<&2, &2, Error, Bool>, hook, T.ToolHookInput{turnContext, active})
def prepareSelected(-State: Data, -Turn: Data, -Update: Data, -Error: Data, lifecycle: Lifecycle<State>, hooks: Hooks<Turn, Update, Error>, turnContext: Turn) -> IO(PrepareResult(Update, Error)):
  match hooks:
    case Hooks{_, _, Some{hook}}:
      do IO<PrepareResult(Update, Error)>:
        active : Maybe<&2, HooksSignal()> <- signalHooks(State, lifecycle)
        C.call(T.ToolHookInput<Turn>, PrepareResult(Update, Error), hook, T.ToolHookInput{turnContext, active})
    case Hooks{_, Some{hook}, None{}}:
      do IO<PrepareResult(Update, Error)>:
        active : Maybe<&2, HooksSignal()> <- signalHooks(State, lifecycle)
        C.call(Maybe<&2, HooksSignal()>, PrepareResult(Update, Error), hook, active)
    case Hooks{_, None{}, None{}}: IO.pure(PrepareResult(Update, Error), Done{None{}})
def prepareBody(-State: Data, -Turn: Data, -Update: Data, -Error: Data, capture: PrepareCapture<State, Turn, Update, Error>, turnContext: Turn) -> IO(PrepareResult(Update, Error)):
  match capture:
    case PrepareCapture{lifecycle, hooks}:
      do IO<PrepareResult(Update, Error)>:
        selected : Hooks<Turn, Update, Error> <- R.read(Hooks<Turn, Update, Error>, hooks)
        prepareSelected(State, Turn, Update, Error, lifecycle, selected, turnContext)
def createStop(~State: Data, ~Turn: Data, ~Error: Data, lifecycle: Lifecycle<State>, hook: Maybe<&2, StopHook(Turn, Error)>) -> IO(Maybe<&2, C.Callback<Turn, Result<&2, &2, Error, Bool>>>):
  match hook:
    case None{}: IO.pure(Maybe<&2, C.Callback<Turn, Result<&2, &2, Error, Bool>>>, None{})
    case Some{callback}:
      do IO<Maybe<&2, C.Callback<Turn, Result<&2, &2, Error, Bool>>>>:
        adapted : C.Callback<Turn, Result<&2, &2, Error, Bool>> <- C.create(~StopCapture<State, Turn, Error>, ~Turn, ~Result<&2, &2, Error, Bool>, ~(stopBody(State, Turn, Error)), StopCapture{lifecycle, callback})
        return Some{adapted}
def hasPreparation(-Turn: Data, -Update: Data, -Error: Data, hooks: Hooks<Turn, Update, Error>) -> Bool:
  match hooks:
    case Hooks{_, None{}, None{}}: False{}
    case _: True{}
def createPrepare(~State: Data, ~Turn: Data, ~Update: Data, ~Error: Data, lifecycle: Lifecycle<State>, hooks: R.Ref<Hooks<Turn, Update, Error>>, enabled: Bool) -> IO(Maybe<&2, C.Callback<Turn, PrepareResult(Update, Error)>>):
  match enabled:
    case False{}: IO.pure(Maybe<&2, C.Callback<Turn, PrepareResult(Update, Error)>>, None{})
    case True{}:
      do IO<Maybe<&2, C.Callback<Turn, PrepareResult(Update, Error)>>>:
        adapted : C.Callback<Turn, PrepareResult(Update, Error)> <- C.create(~PrepareCapture<State, Turn, Update, Error>, ~Turn, ~PrepareResult(Update, Error), ~(prepareBody(State, Turn, Update, Error)), PrepareCapture{lifecycle, hooks})
        return Some{adapted}
def stopValue(-Turn: Data, -Update: Data, -Error: Data, hooks: Hooks<Turn, Update, Error>) -> Maybe<&2, StopHook(Turn, Error)>:
  match hooks:
    case Hooks{stop, _, _}: stop
def createHooks(~State: Data, ~Turn: Data, ~Update: Data, ~Error: Data, +lifecycle: Lifecycle<State>, +hooks: R.Ref<Hooks<Turn, Update, Error>>) -> IO(Adapters<Turn, Update, Error>):
  do IO<Adapters<Turn, Update, Error>>:
    +current : Hooks<Turn, Update, Error> <- R.read(Hooks<Turn, Update, Error>, hooks)
    stop : Maybe<&2, C.Callback<Turn, Result<&2, &2, Error, Bool>>> <- createStop(~State, ~Turn, ~Error, lifecycle, stopValue(Turn, Update, Error, current))
    prepare : Maybe<&2, C.Callback<Turn, PrepareResult(Update, Error)>> <- createPrepare(~State, ~Turn, ~Update, ~Error, lifecycle, hooks, hasPreparation(Turn, Update, Error, current))
    return Adapters{stop, prepare}
def disposeCallback(-Input: Data, -Output: Data, callback: Maybe<&2, C.Callback<Input, Output>>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}: C.dispose(Input, Output, value)
# Drain in-flight calls before disposing adapters. Original hooks, option
# storage and lifecycle remain caller-owned, including replaced callbacks.
def disposeHooks(-Turn: Data, -Update: Data, -Error: Data, adapters: Adapters<Turn, Update, Error>) -> IO(Unit):
  match adapters:
    case Adapters{stop, prepare}:
      do IO<Unit>:
        disposeCallback(Turn, Result<&2, &2, Error, Bool>, stop)
        disposeCallback(Turn, PrepareResult(Update, Error), prepare)


# Queue readers belong to one run. Other configuration callbacks are borrowed.
# Drain loop work before disposing these readers; the Agent owner outlives them.
type BindingSteering<-G: Data, -D: Data, -M: Data, -E: Data> is Data:
  BindingSteering{runtime: OwnedRuntime<G, D, M, E>, skip: R.Ref<Bool>}
type BindingPollers<-G: Data, -D: Data, -M: Data, -E: Data> is Data:
  BindingPollers{steering: C.Callback<Unit, Result<&2, &2, E, List<&2, T.AgentMessage<G, D, M>>>>, followUp: C.Callback<Unit, Result<&2, &2, E, List<&2, T.AgentMessage<G, D, M>>>>, skip: R.Ref<Bool>}
def queue(-G: Data, -D: Data, -M: Data, -E: Data, runtime: OwnedRuntime<G, D, M, E>, kind: QueueKind) -> IO(Result<&2, &2, E, List<&2, T.AgentMessage<G, D, M>>>):
  do IO<Result<&2, &2, E, List<&2, T.AgentMessage<G, D, M>>>>:
    messages : List<&2, T.AgentMessage<G, D, M>> <- drainRuntime(G, D, M, E, runtime, kind)
    return Done{messages}
def steeringReady(-G: Data, -D: Data, -M: Data, -E: Data, runtime: OwnedRuntime<G, D, M, E>, skip: Bool) -> IO(Result<&2, &2, E, List<&2, T.AgentMessage<G, D, M>>>):
  match skip:
    case True{}: IO.pure(Result<&2, &2, E, List<&2, T.AgentMessage<G, D, M>>>, Done{Nil{}})
    case False{}: queue(G, D, M, E, runtime, QueuesSteering{})
def steeringBody(-G: Data, -D: Data, -M: Data, -E: Data, capture: BindingSteering<G, D, M, E>, unused: Unit) -> IO(Result<&2, &2, E, List<&2, T.AgentMessage<G, D, M>>>):
  match capture:
    case BindingSteering{runtime, skip}:
      do IO<Result<&2, &2, E, List<&2, T.AgentMessage<G, D, M>>>>:
        previous : Bool <- R.swap(Bool, skip, False{})
        steeringReady(G, D, M, E, runtime, previous)
def followUpBody(-G: Data, -D: Data, -M: Data, -E: Data, runtime: OwnedRuntime<G, D, M, E>, unused: Unit) -> IO(Result<&2, &2, E, List<&2, T.AgentMessage<G, D, M>>>): queue(G, D, M, E, runtime, FollowUp{})
def newBinding(~G: Data, ~D: Data, ~M: Data, ~E: Data, +runtime: OwnedRuntime<G, D, M, E>, skipInitialSteeringPoll: Bool) -> IO(BindingPollers<G, D, M, E>):
  do IO<BindingPollers<G, D, M, E>>:
    +skip : R.Ref<Bool> <- R.new(Bool, skipInitialSteeringPoll)
    steering : C.Callback<Unit, Result<&2, &2, E, List<&2, T.AgentMessage<G, D, M>>>> <- C.create(~BindingSteering<G, D, M, E>, ~Unit, ~Result<&2, &2, E, List<&2, T.AgentMessage<G, D, M>>>, ~(steeringBody(G, D, M, E)), BindingSteering{runtime, skip})
    followUps : C.Callback<Unit, Result<&2, &2, E, List<&2, T.AgentMessage<G, D, M>>>> <- C.create(~OwnedRuntime<G, D, M, E>, ~Unit, ~Result<&2, &2, E, List<&2, T.AgentMessage<G, D, M>>>, ~(followUpBody(G, D, M, E)), runtime)
    return BindingPollers{steering, followUps, skip}
def thinkingReasoning(thinking: T.ThinkingLevel()) -> Maybe<&2, Ai.ThinkingLevel>:
  match thinking:
    case Ai.Off{}: None{}
    case Ai.Thinking{level}: Some{level}
def context(-G: Data, -D: Data, -M: Data, -E: Data, agentState: T.AgentState<G, D, M, E>) -> T.AgentContext<G, D, M, E>:
  match agentState:
    case T.AgentState{_, _, tools, messages, _, _, _, _}: T.AgentContext{messages, Some{tools}}
# Keep the configured options/hooks while taking model/thinking and transcript
# from one immutable Agent snapshot. The public options adapter builds the base.
def bind(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agentState: T.AgentState<G, D, M, E>, base: T.AgentLoopConfig<G, D, M, E, Telemetry>, readers: BindingPollers<G, D, M, E>) -> T.AgentLoopConfig<G, D, M, E, Telemetry>:
  match agentState base readers:
    case T.AgentState{currentModel, thinking, _, _, _, _, _, _} T.AgentLoopConfig{options, _, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall} BindingPollers{steering, followUps, _}:
      T.AgentLoopConfig{Ai.withReasoning(Ai.JsonValue, Abort.AbortSignal<Unit>, Telemetry, Fetch.Fetch(Unit), E, options, thinkingReasoning(thinking)), currentModel, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, Some{steering}, Some{followUps}, toolExecution, beforeToolCall, afterToolCall}
type Snapshot<-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data> is Data:
  Snapshot{context: T.AgentContext<G, D, M, E>, config: T.AgentLoopConfig<G, D, M, E, Telemetry>}
def snapshotBinding(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, runtime: OwnedRuntime<G, D, M, E>, base: T.AgentLoopConfig<G, D, M, E, Telemetry>, readers: BindingPollers<G, D, M, E>) -> IO(Snapshot<G, D, M, E, Telemetry>):
  do IO<Snapshot<G, D, M, E, Telemetry>>:
    +agentState : T.AgentState<G, D, M, E> <- readRuntime(G, D, M, E, runtime)
    return Snapshot{context(G, D, M, E, agentState), bind(G, D, M, E, Telemetry, agentState, base, readers)}
def disposeBinding(-G: Data, -D: Data, -M: Data, -E: Data, readers: BindingPollers<G, D, M, E>) -> IO(Unit):
  match readers:
    case BindingPollers{steering, followUps, skip}:
      do IO<Unit>:
        C.dispose(Unit, Result<&2, &2, E, List<&2, T.AgentMessage<G, D, M>>>, steering)
        C.dispose(Unit, Result<&2, &2, E, List<&2, T.AgentMessage<G, D, M>>>, followUps)
        ignored : Bool <- R.dispose(Bool, skip)
        return Unit{}

# The run owns these wrappers; public hooks and option storage stay borrowed.
def applyHooks(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, base: T.AgentLoopConfig<G, D, M, E, Telemetry>, adapters: Adapters<T.ShouldStopAfterTurnContext<G, D, M, E>, T.AgentLoopTurnUpdate<G, D, M, E>, E>) -> T.AgentLoopConfig<G, D, M, E, Telemetry>:
  match base adapters:
    case T.AgentLoopConfig{options, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall} Adapters{stop, prepare}: T.AgentLoopConfig{options, model, convertToLlm, transformContext, getApiKey, stop, prepare, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}


def RunSignal() -> Data: Abort.AbortSignal<Unit>
def RunMessage(-G: Data, -D: Data, -M: Data) -> Data: T.AgentMessage<G, D, M>
def RunEvent(-G: Data, -D: Data, -M: Data) -> Data: T.AgentEvent<G, D, M, T.AgentToolResult<D>, T.AgentToolResult<D>>
def RunRuntime(-G: Data, -D: Data, -M: Data, -E: Data) -> Data: OwnedRuntime<G, D, M, E>
def Registry(-G: Data, -D: Data, -M: Data, -E: Data) -> Data: Listeners<RunEvent(G, D, M), E>
def Config(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data) -> Data: T.AgentLoopConfig<G, D, M, E, Telemetry>
def RunPollers(-G: Data, -D: Data, -M: Data, -E: Data) -> Data: BindingPollers<G, D, M, E>
def Outcome(-G: Data, -D: Data, -M: Data, -E: Data) -> Data: Result<&2, &2, E, List<&2, RunMessage(G, D, M)>>
type Options<-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data> is Data:
  Options{config: Config(G, D, M, E, Telemetry), provider: Provider.Selection<G, D, Config(G, D, M, E, Telemetry), E>, validate: C.Callback<Loop.ToolValidationInput, Result<&2, &2, E, Schema.Value>>, emptyDetails: D}
# A completed run can still own tool-held callback aliases or sibling work.
# Retain these resources until aliases retire; dispose drains batches first.
type Resources<-G: Data, -D: Data, -M: Data, -E: Data> is Data:
  Resources{pollers: RunPollers(G, D, M, E), emit: C.Callback<RunEvent(G, D, M), Loop.Emission<E>>, sink: C.Callback<RunEvent(G, D, M), Result<&2, &2, E, Unit>>, isAborted: C.Callback<Maybe<&2, RunSignal()>, Bool>, updates: Loop.Owners(D, E), batches: Loop.Batches(G, D, M, E)}
type Completed<-G: Data, -D: Data, -M: Data, -E: Data> is Data:
  Completed{outcome: Result<&2, &2, DeliveryError<E>, Unit>, resources: Resources<G, D, M, E>}
type Capture<-G: Data, -D: Data, -M: Data, -E: Data> is Data:
  Capture{runtime: RunRuntime(G, D, M, E), listeners: Registry(G, D, M, E)}

def missing(-E: Data, fromString: String -> E, error: Provider.MissingDefault) -> E: fromString(Provider.errorMessage(error))
def invalidEntry(-E: Data, fromString: String -> E, error: Loop.ContinueError) -> E: fromString(Loop.errorMessage(error))
def mapped(-E: Data, fromString: String -> E, outcome: Result<&2, &2, DeliveryError<E>, Unit>) -> Result<&2, &2, E, Unit>:
  match outcome:
    case Done{value}: Done{value}
    case Fail{ListenerFailed{error}}: Fail{error}
    case Fail{OutsideRun{message}}: Fail{fromString(message)}
def finishEmission(-E: Data, fromString: String -> E, delivery: Loop.Emission<DeliveryError<E>>) -> IO(Result<&2, &2, E, Unit>):
  do IO<Result<&2, &2, E, Unit>>:
    outcome : Result<&2, &2, DeliveryError<E>, Unit> <- Loop.wait(DeliveryError<E>, delivery)
    return mapped(E, fromString, outcome)
def emitBody(-G: Data, -D: Data, -M: Data, -E: Data, fromString: String -> E, capture: Capture<G, D, M, E>, event: RunEvent(G, D, M)) -> IO(Loop.Emission<E>):
  match capture:
    case Capture{runtime, listeners}:
      do IO<Loop.Emission<E>>:
        delivery : Loop.Emission<DeliveryError<E>> <- startEvents(G, D, M, E, T.AgentToolResult<D>, T.AgentToolResult<D>, E, runtime, listeners, event)
        Loop.startEmission(E, finishEmission(E, fromString, delivery))
def isAborted(unused: Unit, abortSignal: Maybe<&2, RunSignal()>) -> IO(Bool):
  match abortSignal:
    case None{}: IO.pure(Bool, False{})
    case Some{value}: Abort.aborted(Unit, value)
def skipInitial(-G: Data, -D: Data, -M: Data, plan: Plan<RunMessage(G, D, M)>) -> Bool:
  match plan:
    case Prompt{_, skip}: skip
    case Continue{}: False{}
def allocate(~G: Data, ~D: Data, ~M: Data, ~E: Data, ~fromString: String -> E, +runtime: RunRuntime(G, D, M, E), listeners: Registry(G, D, M, E), skip: Bool) -> IO(Resources<G, D, M, E>):
  do IO<Resources<G, D, M, E>>:
    pollers : RunPollers(G, D, M, E) <- newBinding(~G, ~D, ~M, ~E, runtime, skip)
    +emit : C.Callback<RunEvent(G, D, M), Loop.Emission<E>> <- C.create(~Capture<G, D, M, E>, ~RunEvent(G, D, M), ~Loop.Emission<E>, ~(emitBody(G, D, M, E, fromString)), Capture{runtime, listeners})
    sink : C.Callback<RunEvent(G, D, M), Result<&2, &2, E, Unit>> <- Loop.createAwaitedEventSink(~G, ~D, ~M, ~T.AgentToolResult<D>, ~T.AgentToolResult<D>, ~E, emit)
    cancelled : C.Callback<Maybe<&2, RunSignal()>, Bool> <- C.create(~Unit, ~Maybe<&2, RunSignal()>, ~Bool, ~isAborted, Unit{})
    updates : Loop.Owners(D, E) <- Loop.newOwners(D, E)
    batches : Loop.Batches(G, D, M, E) <- Loop.newBatches(G, D, M, E)
    return Resources{pollers, emit, sink, cancelled, updates, batches}
def executePlan(~G: Data, ~D: Data, ~M: Data, ~E: Data, ~Telemetry: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, plan: Plan<RunMessage(G, D, M)>, snapshot: Snapshot<G, D, M, E, Telemetry>, capture: Loop.EntryCapture<G, D, M, E, Telemetry>) -> IO(Outcome(G, D, M, E)):
  match plan snapshot:
    case Prompt{messages, _} Snapshot{turnContext, config}: Loop.runAgentLoop(~G, ~D, ~M, ~E, ~Telemetry, ~renderError, ~declarationError, ~(missing(E, fromString)), messages, turnContext, config, capture)
    case Continue{} Snapshot{turnContext, config}: Loop.runAgentLoopContinue(~G, ~D, ~M, ~E, ~Telemetry, ~renderError, ~declarationError, ~(missing(E, fromString)), ~(invalidEntry(E, fromString)), turnContext, config, capture)
def execute(~G: Data, ~D: Data, ~M: Data, ~E: Data, ~Telemetry: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, runtime: RunRuntime(G, D, M, E), options: Options<G, D, M, E, Telemetry>, resources: Resources<G, D, M, E>, claimed: Claimed<Plan<RunMessage(G, D, M)>>) -> IO(Outcome(G, D, M, E)):
  match options resources claimed:
    case Options{base, provider, validate, emptyDetails} Resources{pollers, emit, sink, cancelled, updates, batches} Claimed{run, plan}:
      do IO<Outcome(G, D, M, E)>:
        snapshot : Snapshot<G, D, M, E, Telemetry> <- snapshotBinding(G, D, M, E, Telemetry, runtime, base, pollers)
        executePlan(~G, ~D, ~M, ~E, ~Telemetry, ~renderError, ~fromString, ~declarationError, plan, snapshot, Loop.EntryCapture{Loop.Services{Some{activeRunSignal(run)}, validate, cancelled, emit, sink, updates, batches, emptyDetails}, provider})
def finishedLoop(-G: Data, -D: Data, -M: Data, -E: Data, outcome: Outcome(G, D, M, E)) -> Result<&2, &2, E, Unit>:
  match outcome:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{error}
# Run claims and queue planning happen atomically in agent-runtime. This bridge
# executes that plan through the real loop, recovers, then always marks idle.
# The caller retains Completed.resources until explicit disposal is safe.
def runClaimedRun(~G: Data, ~D: Data, ~M: Data, ~E: Data, ~Telemetry: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, +runtime: RunRuntime(G, D, M, E), +listeners: Registry(G, D, M, E), options: Options<G, D, M, E, Telemetry>, claimed: Claimed<Plan<RunMessage(G, D, M)>>) -> IO(Completed<G, D, M, E>):
  match claimed:
    case Claimed{+run, +plan}:
      do IO<Completed<G, D, M, E>>:
        +resources : Resources<G, D, M, E> <- allocate(~G, ~D, ~M, ~E, ~fromString, runtime, listeners, skipInitial(G, D, M, plan))
        result : Outcome(G, D, M, E) <- execute(~G, ~D, ~M, ~E, ~Telemetry, ~renderError, ~fromString, ~declarationError, runtime, options, resources, Claimed{run, plan})
        outcome : Result<&2, &2, DeliveryError<E>, Unit> <- recover(G, D, M, E, T.AgentToolResult<D>, T.AgentToolResult<D>, E, runtime, listeners, run, finishedLoop(G, D, M, E, result), renderError)
        finished : Bool <- finishRuntimeRun(G, D, M, E, runtime, run)
        return Completed{outcome, resources}
def runDispose(-G: Data, -D: Data, -M: Data, -E: Data, resources: Resources<G, D, M, E>) -> IO(Unit):
  match resources:
    case Resources{pollers, emit, sink, cancelled, updates, batches}:
      do IO<Unit>:
        Loop.disposeBatches(G, D, M, E, batches)
        Loop.disposeOwners(D, E, updates)
        C.dispose(RunEvent(G, D, M), Result<&2, &2, E, Unit>, sink)
        C.dispose(RunEvent(G, D, M), Loop.Emission<E>, emit)
        C.dispose(Maybe<&2, RunSignal()>, Bool, cancelled)
        disposeBinding(G, D, M, E, pollers)


def Converter(-G: Data, -D: Data, -M: Data, -E: Data) -> Data: C.Callback<T.AgentMessageArray(G, D, M), Result<&2, &2, E, List<&2, Ai.Message<Schema.Value, Schema.Value, G, D>>>>
def Turn(-G: Data, -D: Data, -M: Data, -E: Data) -> Data: T.ShouldStopAfterTurnContext<G, D, M, E>
def Update(-G: Data, -D: Data, -M: Data, -E: Data) -> Data: T.AgentLoopTurnUpdate<G, D, M, E>
def TurnHooks(-G: Data, -D: Data, -M: Data, -E: Data) -> Data: Hooks<Turn(G, D, M, E), Update(G, D, M, E), E>
# streamFn is optional only for the source's legacy default-provider fallback.
type AgentOptions<-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data> is Data:
  AgentOptions{initialState: Maybe<&2, AgentInitialState<G, D, M, E>>, convertToLlm: Maybe<&2, Converter(G, D, M, E)>, transformContext: Maybe<&2, C.Callback<T.TransformContextInput<T.AgentMessageArray(G, D, M)>, Result<&2, &2, E, T.AgentMessageArray(G, D, M)>>>, streamFn: Maybe<&2, T.StreamFn(G, D, Config(G, D, M, E, Telemetry), E)>, getApiKey: Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>, onPayload: Maybe<&2, Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, E)>, onResponse: Maybe<&2, Ai.ResponseCallback(Ai.Model<Ai.JsonValue>, E)>, beforeToolCall: Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<G, D, M, E>>, Result<&2, &2, E, T.BeforeToolCallUpdate<T.AgentContext<G, D, M, E>>>>>, afterToolCall: Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<G, D, M, E>>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>, shouldStopAfterTurn: Maybe<&2, StopHook(Turn(G, D, M, E), E)>, prepareNextTurn: Maybe<&2, LegacyHook(Update(G, D, M, E), E)>, prepareNextTurnWithContext: Maybe<&2, ContextHook(Turn(G, D, M, E), Update(G, D, M, E), E)>, steeringMode: Maybe<&2, T.QueueMode>, followUpMode: Maybe<&2, T.QueueMode>, sessionId: Maybe<&2, String>, thinkingBudgets: Maybe<&2, Ai.ThinkingBudgets>, transport: Maybe<&2, Ai.Transport>, maxRetryDelayMs: Maybe<&2, F.F64>, toolExecution: Maybe<&2, T.ToolExecutionMode>}
def defaultAgentOptions(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data) -> AgentOptions<G, D, M, E, Telemetry>:
  AgentOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}
type Resolved<-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data> is Data:
  Resolved{initialState: AgentInitialState<G, D, M, E>, config: Config(G, D, M, E, Telemetry), streamFn: T.StreamFn(G, D, Config(G, D, M, E, Telemetry), E), hooks: TurnHooks(G, D, M, E), steeringMode: T.QueueMode, followUpMode: T.QueueMode, ownedConverter: Maybe<&2, Converter(G, D, M, E)>}
type Converted<-G: Data, -D: Data, -M: Data, -E: Data> is Data:
  Converted{callback: Converter(G, D, M, E), owned: Maybe<&2, Converter(G, D, M, E)>}
def convert(-G: Data, -D: Data, -M: Data, -E: Data, unused: Unit, messages: List<&2, RunMessage(G, D, M)>) -> IO(Result<&2, &2, E, List<&2, Ai.Message<Schema.Value, Schema.Value, G, D>>>):
  IO.pure(Result<&2, &2, E, List<&2, Ai.Message<Schema.Value, Schema.Value, G, D>>>, Done{defaultConvertToLlm(G, D, M, E, messages)})
def suppliedConverter(~G: Data, ~D: Data, ~M: Data, ~E: Data, supplied: Maybe<&2, Converter(G, D, M, E)>) -> IO(Converted<G, D, M, E>):
  match supplied:
    case Some{callback}: IO.pure(Converted<G, D, M, E>, Converted{callback, None{}})
    case None{}:
      do IO<Converted<G, D, M, E>>:
        +callback : Converter(G, D, M, E) <- C.create(~Unit, ~List<&2, RunMessage(G, D, M)>, ~Result<&2, &2, E, List<&2, Ai.Message<Schema.Value, Schema.Value, G, D>>>, ~(convert(G, D, M, E)), Unit{})
        return Converted{callback, Some{callback}}
def providerSelection(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, callback: Maybe<&2, T.StreamFn(G, D, Config(G, D, M, E, Telemetry), E)>, fallback: Provider.Registry(G, D, Config(G, D, M, E, Telemetry), E)) -> Provider.Selection<G, D, Config(G, D, M, E, Telemetry), E>:
  match callback:
    case Some{value}: Provider.Explicit{value}
    case None{}: Provider.Fallback{fallback}
def finishOptions(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, initial: Maybe<&2, AgentInitialState<G, D, M, E>>, converted: Converted<G, D, M, E>, stream: T.StreamFn(G, D, Config(G, D, M, E, Telemetry), E), hooks: TurnHooks(G, D, M, E), steering: Maybe<&2, T.QueueMode>, follow: Maybe<&2, T.QueueMode>, transformContext: Maybe<&2, C.Callback<T.TransformContextInput<T.AgentMessageArray(G, D, M)>, Result<&2, &2, E, T.AgentMessageArray(G, D, M)>>>, getApiKey: Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>, onPayload: Maybe<&2, Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, E)>, onResponse: Maybe<&2, Ai.ResponseCallback(Ai.Model<Ai.JsonValue>, E)>, beforeToolCall: Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<G, D, M, E>>, Result<&2, &2, E, T.BeforeToolCallUpdate<T.AgentContext<G, D, M, E>>>>>, afterToolCall: Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<G, D, M, E>>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>, sessionId: Maybe<&2, String>, thinkingBudgets: Maybe<&2, Ai.ThinkingBudgets>, transport: Maybe<&2, Ai.Transport>, maxRetryDelayMs: Maybe<&2, F.F64>, toolExecution: Maybe<&2, T.ToolExecutionMode>) -> IO(Result<&2, &2, Provider.MissingDefault, Resolved<G, D, M, E, Telemetry>>):
  match converted:
    case Converted{callback, owned}: IO.pure(Result<&2, &2, Provider.MissingDefault, Resolved<G, D, M, E, Telemetry>>, Done{Resolved{Maybe.default(&2, AgentInitialState<G, D, M, E>, initial, AgentInitialState{None{}, None{}, None{}, None{}, None{}}), T.AgentLoopConfig{Ai.SimpleStreamOptions{None{}, None{}, None{}, None{}, None{}, onPayload, onResponse, None{}, None{}, None{}, maxRetryDelayMs, None{}, None{}, None{}, Some{Maybe.default(&2, Ai.Transport, transport, Ai.AutoTransport{})}, None{}, sessionId, None{}, None{}, None{}, None{}, None{}, thinkingBudgets}, defaultModel(Ai.JsonValue), callback, transformContext, getApiKey, None{}, None{}, None{}, None{}, Some{Maybe.default(&2, T.ToolExecutionMode, toolExecution, T.Parallel{})}, beforeToolCall, afterToolCall}, stream, hooks, Maybe.default(&2, T.QueueMode, steering, T.OneAtATime{}), Maybe.default(&2, T.QueueMode, follow, T.OneAtATime{}), owned}})
def resolvedOptions(~G: Data, ~D: Data, ~M: Data, ~E: Data, ~Telemetry: Data, options: AgentOptions<G, D, M, E, Telemetry>, provider: Result<&2, &2, Provider.MissingDefault, T.StreamFn(G, D, Config(G, D, M, E, Telemetry), E)>) -> IO(Result<&2, &2, Provider.MissingDefault, Resolved<G, D, M, E, Telemetry>>):
  match options provider:
    case _ Fail{error}: IO.pure(Result<&2, &2, Provider.MissingDefault, Resolved<G, D, M, E, Telemetry>>, Fail{error})
    case AgentOptions{initialState, convertToLlm, transformContext, streamFn, getApiKey, onPayload, onResponse, beforeToolCall, afterToolCall, shouldStopAfterTurn, prepareNextTurn, prepareNextTurnWithContext, steeringMode, followUpMode, sessionId, thinkingBudgets, transport, maxRetryDelayMs, toolExecution} Done{stream}:
      do IO<Result<&2, &2, Provider.MissingDefault, Resolved<G, D, M, E, Telemetry>>>:
        converted : Converted<G, D, M, E> <- suppliedConverter(~G, ~D, ~M, ~E, convertToLlm)
        finishOptions(G, D, M, E, Telemetry, initialState, converted, stream, Hooks{shouldStopAfterTurn, prepareNextTurn, prepareNextTurnWithContext}, steeringMode, followUpMode, transformContext, getApiKey, onPayload, onResponse, beforeToolCall, afterToolCall, sessionId, thinkingBudgets, transport, maxRetryDelayMs, toolExecution)
# Resolve fallback at construction, preserving the selected callback for runs.
def resolve(~G: Data, ~D: Data, ~M: Data, ~E: Data, ~Telemetry: Data, +options: AgentOptions<G, D, M, E, Telemetry>, fallback: Provider.Registry(G, D, Config(G, D, M, E, Telemetry), E)) -> IO(Result<&2, &2, Provider.MissingDefault, Resolved<G, D, M, E, Telemetry>>):
  match options:
    case AgentOptions{_, _, _, streamFn, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      do IO<Result<&2, &2, Provider.MissingDefault, Resolved<G, D, M, E, Telemetry>>>:
        provider : Result<&2, &2, Provider.MissingDefault, T.StreamFn(G, D, Config(G, D, M, E, Telemetry), E)> <- Provider.resolve(G, D, Config(G, D, M, E, Telemetry), E, providerSelection(G, D, M, E, Telemetry, streamFn, fallback))
        resolvedOptions(~G, ~D, ~M, ~E, ~Telemetry, options, provider)


# Immutable public request settings; each run captures its own value.
type Settings is Data:
  Settings{sessionId: Maybe<&2, String>, thinkingBudgets: Maybe<&2, Ai.ThinkingBudgets>, transport: Ai.Transport, maxRetryDelayMs: Maybe<&2, F.F64>, toolExecution: T.ToolExecutionMode}
type SettingsChange is Data:
  SetSessionId{value: Maybe<&2, String>}
  SetThinkingBudgets{value: Maybe<&2, Ai.ThinkingBudgets>}
  SetTransport{value: Ai.Transport}
  SetMaxRetryDelayMs{value: Maybe<&2, F.F64>}
  SetToolExecution{value: T.ToolExecutionMode}

def apply(settings: Settings, change: SettingsChange) -> Settings:
  match settings change:
    case Settings{_, thinkingBudgets, transport, maxRetryDelayMs, toolExecution} SetSessionId{value}: Settings{value, thinkingBudgets, transport, maxRetryDelayMs, toolExecution}
    case Settings{sessionId, _, transport, maxRetryDelayMs, toolExecution} SetThinkingBudgets{value}: Settings{sessionId, value, transport, maxRetryDelayMs, toolExecution}
    case Settings{sessionId, thinkingBudgets, _, maxRetryDelayMs, toolExecution} SetTransport{value}: Settings{sessionId, thinkingBudgets, value, maxRetryDelayMs, toolExecution}
    case Settings{sessionId, thinkingBudgets, transport, _, toolExecution} SetMaxRetryDelayMs{value}: Settings{sessionId, thinkingBudgets, transport, value, toolExecution}
    case Settings{sessionId, thinkingBudgets, transport, maxRetryDelayMs, _} SetToolExecution{value}: Settings{sessionId, thinkingBudgets, transport, maxRetryDelayMs, value}
def settingsSessionId(settings: Settings) -> Maybe<&2, String>:
  match settings:
    case Settings{value, _, _, _, _}: value
def getThinkingBudgetsSettings(settings: Settings) -> Maybe<&2, Ai.ThinkingBudgets>:
  match settings:
    case Settings{_, value, _, _, _}: value
def getTransportSettings(settings: Settings) -> Ai.Transport:
  match settings:
    case Settings{_, _, value, _, _}: value
def getMaxRetryDelayMsSettings(settings: Settings) -> Maybe<&2, F.F64>:
  match settings:
    case Settings{_, _, _, value, _}: value
def getToolExecutionSettings(settings: Settings) -> T.ToolExecutionMode:
  match settings:
    case Settings{_, _, _, _, value}: value


type AgentError<-E: Data> is Data:
  ClaimFailed{message: String}
  DeliveryFailed{error: DeliveryError<E>}
type Retired<-G: Data, -D: Data, -M: Data, -E: Data> is Data:
  Retired{resources: Resources<G, D, M, E>, hooks: Adapters<Turn(G, D, M, E), Update(G, D, M, E), E>}
# Caller-owned callbacks remain borrowed. Stop new operations and await their
# completion before disposal; retained tool/listener aliases must retire too.
type Agent<-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data> is Data:
  Agent{runtime: RunRuntime(G, D, M, E), listeners: Registry(G, D, M, E), options: R.Ref<Options<G, D, M, E, Telemetry>>, hooks: R.Ref<TurnHooks(G, D, M, E)>, retired: R.Ref<List<&2, Retired<G, D, M, E>>>, ownedConverter: Maybe<&2, Converter(G, D, M, E)>}
def constructed(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, resolved: Result<&2, &2, Provider.MissingDefault, Resolved<G, D, M, E, Telemetry>>, validate: C.Callback<Loop.ToolValidationInput, Result<&2, &2, E, Schema.Value>>, emptyDetails: D) -> IO(Result<&2, &2, Provider.MissingDefault, Agent<G, D, M, E, Telemetry>>):
  match resolved:
    case Fail{error}: IO.pure(Result<&2, &2, Provider.MissingDefault, Agent<G, D, M, E, Telemetry>>, Fail{error})
    case Done{Resolved{initial, config, stream, hooks, steering, follow, ownedConverter}}:
      do IO<Result<&2, &2, Provider.MissingDefault, Agent<G, D, M, E, Telemetry>>>:
        runtime : RunRuntime(G, D, M, E) <- newRuntime(G, D, M, E, initial, steering, follow)
        listeners : Registry(G, D, M, E) <- newListeners(RunEvent(G, D, M), E)
        options : R.Ref<Options<G, D, M, E, Telemetry>> <- R.new(Options<G, D, M, E, Telemetry>, Options{config, Provider.Explicit{stream}, validate, emptyDetails})
        liveHooks : R.Ref<TurnHooks(G, D, M, E)> <- R.new(TurnHooks(G, D, M, E), hooks)
        retired : R.Ref<List<&2, Retired<G, D, M, E>>> <- R.new(List<&2, Retired<G, D, M, E>>, Nil{})
        return Done{Agent{runtime, listeners, options, liveHooks, retired, ownedConverter}}
# Validation is an explicit typed dependency, never an implicit permissive check.
def new(~G: Data, ~D: Data, ~M: Data, ~E: Data, ~Telemetry: Data, options: AgentOptions<G, D, M, E, Telemetry>, fallback: Provider.Registry(G, D, Config(G, D, M, E, Telemetry), E), validate: C.Callback<Loop.ToolValidationInput, Result<&2, &2, E, Schema.Value>>, emptyDetails: D) -> IO(Result<&2, &2, Provider.MissingDefault, Agent<G, D, M, E, Telemetry>>):
  do IO<Result<&2, &2, Provider.MissingDefault, Agent<G, D, M, E, Telemetry>>>:
    resolved : Result<&2, &2, Provider.MissingDefault, Resolved<G, D, M, E, Telemetry>> <- resolve(~G, ~D, ~M, ~E, ~Telemetry, options, fallback)
    constructed(G, D, M, E, Telemetry, resolved, validate, emptyDetails)
def state(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(T.AgentState<G, D, M, E>):
  match agent:
    case Agent{runtime, _, _, _, _, _}: readRuntime(G, D, M, E, runtime)
def subscribe(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, listener: Handler(RunEvent(G, D, M), E)) -> IO(Subscription<RunEvent(G, D, M), E>):
  match agent:
    case Agent{_, listeners, _, _, _, _}: subscribeListeners(RunEvent(G, D, M), E, listeners, listener)
def runOptions(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>, hooks: Adapters<Turn(G, D, M, E), Update(G, D, M, E), E>) -> Options<G, D, M, E, Telemetry>:
  match options:
    case Options{config, stream, validate, emptyDetails}: Options{applyHooks(G, D, M, E, Telemetry, config, hooks), stream, validate, emptyDetails}
def settledAgent(-E: Data, outcome: Result<&2, &2, DeliveryError<E>, Unit>) -> Result<&2, &2, AgentError<E>, Unit>:
  match outcome:
    case Done{value}: Done{value}
    case Fail{error}: Fail{DeliveryFailed{error}}
def retire(-G: Data, -D: Data, -M: Data, -E: Data, retired: R.Ref<List<&2, Retired<G, D, M, E>>>, hooks: Adapters<Turn(G, D, M, E), Update(G, D, M, E), E>, completed: Completed<G, D, M, E>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match completed:
    case Completed{outcome, resources}:
      do IO<Result<&2, &2, AgentError<E>, Unit>>:
        R.modify(List<&2, Retired<G, D, M, E>>, Unit, retired, previous => (Retired{resources, hooks} <> previous, Unit{}))
        return settledAgent(E, outcome)
def runClaimed(~G: Data, ~D: Data, ~M: Data, ~E: Data, ~Telemetry: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, agent: Agent<G, D, M, E, Telemetry>, claimed: Claimed<Plan<RunMessage(G, D, M)>>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match agent:
    case Agent{OwnedRuntime{+lifecycle}, listeners, options, hooks, retired, _}:
      do IO<Result<&2, &2, AgentError<E>, Unit>>:
        +adapters : Adapters<Turn(G, D, M, E), Update(G, D, M, E), E> <- createHooks(~OwnedState<G, D, M, E>, ~Turn(G, D, M, E), ~Update(G, D, M, E), ~E, lifecycle, hooks)
        base : Options<G, D, M, E, Telemetry> <- R.read(Options<G, D, M, E, Telemetry>, options)
        completed : Completed<G, D, M, E> <- runClaimedRun(~G, ~D, ~M, ~E, ~Telemetry, ~renderError, ~fromString, ~declarationError, OwnedRuntime{lifecycle}, listeners, runOptions(G, D, M, E, Telemetry, base, adapters), claimed)
        retire(G, D, M, E, retired, adapters, completed)
def claimError(error: ClaimError<String>, continuation: Bool) -> String:
  match error:
    case Rejected{message}: message
    case LifeBusy{}: Bool.pick(String, continuation, "Agent is already processing. Wait for completion before continuing.", "Agent is already processing a prompt. Use steer() or followUp() to queue messages, or wait for completion.")
def startClaimed(~G: Data, ~D: Data, ~M: Data, ~E: Data, ~Telemetry: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, agent: Agent<G, D, M, E, Telemetry>, continuation: Bool, claim: Result<&2, &2, ClaimError<String>, Claimed<Plan<RunMessage(G, D, M)>>>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match claim:
    case Fail{error}: IO.pure(Result<&2, &2, AgentError<E>, Unit>, Fail{ClaimFailed{claimError(error, continuation)}})
    case Done{claimed}: runClaimed(~G, ~D, ~M, ~E, ~Telemetry, ~renderError, ~fromString, ~declarationError, agent, claimed)
def promptMessages(~G: Data, ~D: Data, ~M: Data, ~E: Data, ~Telemetry: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, +agent: Agent<G, D, M, E, Telemetry>, messages: List<&2, RunMessage(G, D, M)>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match agent:
    case Agent{runtime, _, _, _, _, _}:
      do IO<Result<&2, &2, AgentError<E>, Unit>>:
        claim : Result<&2, &2, ClaimError<String>, Claimed<Plan<RunMessage(G, D, M)>>> <- beginPrompt(G, D, M, E, runtime, messages)
        startClaimed(~G, ~D, ~M, ~E, ~Telemetry, ~renderError, ~fromString, ~declarationError, agent, False{}, claim)
def continueRun(~G: Data, ~D: Data, ~M: Data, ~E: Data, ~Telemetry: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, +agent: Agent<G, D, M, E, Telemetry>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match agent:
    case Agent{runtime, _, _, _, _, _}:
      do IO<Result<&2, &2, AgentError<E>, Unit>>:
        claim : Result<&2, &2, ClaimError<String>, Claimed<Plan<RunMessage(G, D, M)>>> <- beginContinue(G, D, M, E, runtime)
        startClaimed(~G, ~D, ~M, ~E, ~Telemetry, ~renderError, ~fromString, ~declarationError, agent, True{}, claim)
def steer(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, message: RunMessage(G, D, M)) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: steerRuntime(G, D, M, E, runtime, message)
def followUp(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, message: RunMessage(G, D, M)) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: followUpRuntime(G, D, M, E, runtime, message)
def abort(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: abortRuntime(G, D, M, E, runtime)
def waitForIdle(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: waitForIdleRuntime(G, D, M, E, runtime)
def clearAllQueues(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: clearAllRuntimeQueues(G, D, M, E, runtime)
def reset(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Result<&2, &2, String, Unit>):
  match agent:
    case Agent{runtime, _, _, _, _, _}: resetRuntime(G, D, M, E, runtime)
def clearSteeringQueue(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: clearQueue(G, D, M, E, runtime, QueuesSteering{})
def clearFollowUpQueue(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: clearQueue(G, D, M, E, runtime, FollowUp{})
def signal(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Maybe<&2, RunSignal()>):
  match agent:
    case Agent{OwnedRuntime{lifecycle}, _, _, _, _, _}: signalHooks(OwnedState<G, D, M, E>, lifecycle)
def setHooks(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: TurnHooks(G, D, M, E)) -> IO(Unit):
  match agent:
    case Agent{_, _, _, hooks, _, _}: R.write(TurnHooks(G, D, M, E), hooks, value)
def disposeRuns(-G: Data, -D: Data, -M: Data, -E: Data, runs: List<&2, Retired<G, D, M, E>>) -> IO(Unit):
  match runs:
    case Nil{}: IO.pure(Unit, Unit{})
    case Retired{resources, hooks} <> rest:
      do IO<Unit>:
        runDispose(G, D, M, E, resources)
        disposeHooks(Turn(G, D, M, E), Update(G, D, M, E), E, hooks)
        disposeRuns(G, D, M, E, rest)
# Join public calls and retire borrowed aliases before disposal. waitForIdle
# covers awaited listeners; surviving failed tool batches drain here.
def dispose(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Unit):
  match agent:
    case Agent{runtime, listeners, options, hooks, retired, converter}:
      do IO<Unit>:
        runs : List<&2, Retired<G, D, M, E>> <- R.dispose(List<&2, Retired<G, D, M, E>>, retired)
        disposeRuns(G, D, M, E, runs)
        disposeListeners(RunEvent(G, D, M), E, listeners)
        old : Options<G, D, M, E, Telemetry> <- R.dispose(Options<G, D, M, E, Telemetry>, options)
        old : TurnHooks(G, D, M, E) <- R.dispose(TurnHooks(G, D, M, E), hooks)
        disposeCallback(List<&2, RunMessage(G, D, M)>, Result<&2, &2, E, List<&2, Ai.Message<Schema.Value, Schema.Value, G, D>>>, converter)
        old : OwnedState<G, D, M, E> <- disposeRuntime(G, D, M, E, runtime)
        return Unit{}

# Native sum types represent the source's text/single-message/batch overloads.
type PromptInput<-G: Data, -D: Data, -M: Data> is Data:
  Text{text: String, images: List<&2, Ai.ImageContent>}
  Message{message: RunMessage(G, D, M)}
  Messages{messages: List<&2, RunMessage(G, D, M)>}
def imageBlocks(images: List<&2, Ai.ImageContent>) -> List<&2, Ai.TextImageContent>:
  match images:
    case Nil{}: Nil{}
    case image <> rest: Ai.TextImageImage{image} <> imageBlocks(rest)
def normalizePromptInputAt(-G: Data, -D: Data, -M: Data, input: PromptInput<G, D, M>, timestamp: F.F64) -> List<&2, RunMessage(G, D, M)>:
  match input:
    case Text{text, images}: T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{Ai.TextImageText{Ai.TextContent{text, None{}}} <> imageBlocks(images)}, timestamp}}} <> Nil{}
    case Message{message}: message <> Nil{}
    case Messages{messages}: messages
def normalizePromptInput(-G: Data, -D: Data, -M: Data, input: PromptInput<G, D, M>) -> IO(List<&2, RunMessage(G, D, M)>):
  match input:
    case Text{text, images}:
      do IO<List<&2, RunMessage(G, D, M)>>:
        timestamp : F.F64 <- Date.now()
        return normalizePromptInputAt(G, D, M, Text{text, images}, timestamp)
    case Message{message}: IO.pure(List<&2, RunMessage(G, D, M)>, message <> Nil{})
    case Messages{messages}: IO.pure(List<&2, RunMessage(G, D, M)>, messages)
def promptReady(~G: Data, ~D: Data, ~M: Data, ~E: Data, ~Telemetry: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, agent: Agent<G, D, M, E, Telemetry>, input: PromptInput<G, D, M>, active: Maybe<&2, RunSignal()>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match active:
    case Some{_}: IO.pure(Result<&2, &2, AgentError<E>, Unit>, Fail{ClaimFailed{claimError(LifeBusy{}, False{})}})
    case None{}:
      do IO<Result<&2, &2, AgentError<E>, Unit>>:
        messages : List<&2, RunMessage(G, D, M)> <- normalizePromptInput(G, D, M, input)
        promptMessages(~G, ~D, ~M, ~E, ~Telemetry, ~renderError, ~fromString, ~declarationError, agent, messages)
def prompt(~G: Data, ~D: Data, ~M: Data, ~E: Data, ~Telemetry: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, +agent: Agent<G, D, M, E, Telemetry>, input: PromptInput<G, D, M>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  do IO<Result<&2, &2, AgentError<E>, Unit>>:
    active : Maybe<&2, RunSignal()> <- signal(G, D, M, E, Telemetry, agent)
    promptReady(~G, ~D, ~M, ~E, ~Telemetry, ~renderError, ~fromString, ~declarationError, agent, input, active)

def updateState(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, change: StateChange<G, D, M, E>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: updateStateRuntime(G, D, M, E, runtime, change)
def setModel(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: Ai.Model<Ai.JsonValue>) -> IO(Unit):
  updateState(G, D, M, E, Telemetry, agent, SetModel{value})
def setThinkingLevel(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: T.ThinkingLevel()) -> IO(Unit):
  updateState(G, D, M, E, Telemetry, agent, SetThinkingLevel{value})
def setTools(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: List<&2, T.AgentTool<D, E>>) -> IO(Unit):
  updateState(G, D, M, E, Telemetry, agent, SetTools{value})
def replaceMessages(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: List<&2, RunMessage(G, D, M)>) -> IO(Unit):
  updateState(G, D, M, E, Telemetry, agent, ReplaceMessages{value})
def appendMessage(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: RunMessage(G, D, M)) -> IO(Unit):
  updateState(G, D, M, E, Telemetry, agent, AppendMessage{value})
def clearMessages(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Unit): replaceMessages(G, D, M, E, Telemetry, agent, Nil{})
def systemPrompt(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(String):
  do IO<String>:
    value : T.AgentState<G, D, M, E> <- state(G, D, M, E, Telemetry, agent)
    return systemPromptState(G, D, M, E, value)
def queueValues(-G: Data, -D: Data, -M: Data, -E: Data, owned: OwnedState<G, D, M, E>) -> Queues<RunMessage(G, D, M)>:
  match owned:
    case OwnedState{_, queues}: queues
def queueSnapshot(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Queues<RunMessage(G, D, M)>):
  match agent:
    case Agent{runtime, _, _, _, _, _}:
      do IO<Queues<RunMessage(G, D, M)>>:
        owned : OwnedState<G, D, M, E> <- snapshotRuntime(G, D, M, E, runtime)
        return queueValues(G, D, M, E, owned)
def hasQueuedMessages(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Bool):
  do IO<Bool>:
    queues : Queues<RunMessage(G, D, M)> <- queueSnapshot(G, D, M, E, Telemetry, agent)
    return queuesHaveMessages(RunMessage(G, D, M), queues)
def setSteeringMode(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, mode: T.QueueMode) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: setQueueMode(G, D, M, E, runtime, QueuesSteering{}, mode)
def getSteeringMode(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(T.QueueMode):
  do IO<T.QueueMode>:
    queues : Queues<RunMessage(G, D, M)> <- queueSnapshot(G, D, M, E, Telemetry, agent)
    return getModeQueues(RunMessage(G, D, M), queues, QueuesSteering{})
def setFollowUpMode(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, mode: T.QueueMode) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: setQueueMode(G, D, M, E, runtime, FollowUp{}, mode)
def getFollowUpMode(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(T.QueueMode):
  do IO<T.QueueMode>:
    queues : Queues<RunMessage(G, D, M)> <- queueSnapshot(G, D, M, E, Telemetry, agent)
    return getModeQueues(RunMessage(G, D, M), queues, FollowUp{})

def configSettings(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry)) -> Settings:
  match config:
    case T.AgentLoopConfig{Ai.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, maxRetryDelayMs, _, _, _, transport, _, sessionId, _, _, _, _, _, thinkingBudgets}, _, _, _, _, _, _, _, _, toolExecution, _, _}: Settings{sessionId, thinkingBudgets, Maybe.default(&2, Ai.Transport, transport, Ai.AutoTransport{}), maxRetryDelayMs, Maybe.default(&2, T.ToolExecutionMode, toolExecution, T.Parallel{})}
def settingsConfig(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry), settings: Settings) -> Config(G, D, M, E, Telemetry):
  match config settings:
    case T.AgentLoopConfig{Ai.SimpleStreamOptions{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, _, temperature, samplingParams, maxTokens, _, cacheRetention, _, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, _}, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, _, beforeToolCall, afterToolCall} Settings{sessionId, thinkingBudgets, transport, maxRetryDelayMs, toolExecution}: T.AgentLoopConfig{Ai.SimpleStreamOptions{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, Some{transport}, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets}, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, Some{toolExecution}, beforeToolCall, afterToolCall}
def changedSettings(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>, change: SettingsChange) -> Options<G, D, M, E, Telemetry> & Unit:
  match options:
    case Options{+config, provider, validate, emptyDetails}: (Options{settingsConfig(G, D, M, E, Telemetry, config, apply(configSettings(G, D, M, E, Telemetry, config), change)), provider, validate, emptyDetails}, Unit{})
def updateSettings(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, change: SettingsChange) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<G, D, M, E, Telemetry>, Unit, options, current => changedSettings(G, D, M, E, Telemetry, current, change))
def optionsSettings(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>) -> Settings:
  match options:
    case Options{config, _, _, _}: configSettings(G, D, M, E, Telemetry, config)
def getSettings(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Settings):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Settings>:
        current : Options<G, D, M, E, Telemetry> <- R.read(Options<G, D, M, E, Telemetry>, options)
        return optionsSettings(G, D, M, E, Telemetry, current)
def setSessionId(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: Maybe<&2, String>) -> IO(Unit):
  updateSettings(G, D, M, E, Telemetry, agent, SetSessionId{value})
def getSessionId(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    settings : Settings <- getSettings(G, D, M, E, Telemetry, agent)
    return settingsSessionId(settings)
def setThinkingBudgets(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: Maybe<&2, Ai.ThinkingBudgets>) -> IO(Unit):
  updateSettings(G, D, M, E, Telemetry, agent, SetThinkingBudgets{value})
def getThinkingBudgets(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Maybe<&2, Ai.ThinkingBudgets>):
  do IO<Maybe<&2, Ai.ThinkingBudgets>>:
    settings : Settings <- getSettings(G, D, M, E, Telemetry, agent)
    return getThinkingBudgetsSettings(settings)
def setTransport(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: Ai.Transport) -> IO(Unit):
  updateSettings(G, D, M, E, Telemetry, agent, SetTransport{value})
def getTransport(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Ai.Transport):
  do IO<Ai.Transport>:
    settings : Settings <- getSettings(G, D, M, E, Telemetry, agent)
    return getTransportSettings(settings)
def setMaxRetryDelayMs(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: Maybe<&2, F.F64>) -> IO(Unit):
  updateSettings(G, D, M, E, Telemetry, agent, SetMaxRetryDelayMs{value})
def getMaxRetryDelayMs(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Maybe<&2, F.F64>):
  do IO<Maybe<&2, F.F64>>:
    settings : Settings <- getSettings(G, D, M, E, Telemetry, agent)
    return getMaxRetryDelayMsSettings(settings)
def setToolExecution(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: T.ToolExecutionMode) -> IO(Unit):
  updateSettings(G, D, M, E, Telemetry, agent, SetToolExecution{value})
def getToolExecution(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(T.ToolExecutionMode):
  do IO<T.ToolExecutionMode>:
    settings : Settings <- getSettings(G, D, M, E, Telemetry, agent)
    return getToolExecutionSettings(settings)
def configSessionId(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry)) -> Maybe<&2, String>:
  settingsSessionId(configSettings(G, D, M, E, Telemetry, config))

# Replacement borrows the new callback. Keep old and new caller-owned handles
# alive through every run that captured them. The owned default converter stays
# alive until Agent disposal, even after replacement.
def changedStreamFunction(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>, value: T.StreamFn(G, D, Config(G, D, M, E, Telemetry), E)) -> Options<G, D, M, E, Telemetry> & Unit:
  match options:
    case Options{config, _, validate, emptyDetails}: (Options{config, Provider.Explicit{value}, validate, emptyDetails}, Unit{})
def setStreamFunction(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: T.StreamFn(G, D, Config(G, D, M, E, Telemetry), E)) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<G, D, M, E, Telemetry>, Unit, options, current => changedStreamFunction(G, D, M, E, Telemetry, current, value))
def optionsStreamFunction(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>) -> IO(T.StreamFn(G, D, Config(G, D, M, E, Telemetry), E)):
  match options:
    case Options{_, Provider.Explicit{value}, _, _}: IO.pure(T.StreamFn(G, D, Config(G, D, M, E, Telemetry), E), value)
    case _: IO.die(T.StreamFn(G, D, Config(G, D, M, E, Telemetry), E), 1, "Agent provider selection must be resolved at construction")
def getStreamFunction(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(T.StreamFn(G, D, Config(G, D, M, E, Telemetry), E)):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<T.StreamFn(G, D, Config(G, D, M, E, Telemetry), E)>:
        current : Options<G, D, M, E, Telemetry> <- R.read(Options<G, D, M, E, Telemetry>, options)
        optionsStreamFunction(G, D, M, E, Telemetry, current)
def configConvertToLlm(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry)) -> Converter(G, D, M, E):
  match config:
    case T.AgentLoopConfig{_, _, value, _, _, _, _, _, _, _, _, _}: value
def replaceConvertToLlm(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry), value: Converter(G, D, M, E)) -> Config(G, D, M, E, Telemetry):
  match config:
    case T.AgentLoopConfig{options, model, _, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{options, model, value, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}
def changedConvertToLlm(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>, value: Converter(G, D, M, E)) -> Options<G, D, M, E, Telemetry> & Unit:
  match options:
    case Options{config, provider, validate, emptyDetails}: (Options{replaceConvertToLlm(G, D, M, E, Telemetry, config, value), provider, validate, emptyDetails}, Unit{})
def setConvertToLlm(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: Converter(G, D, M, E)) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<G, D, M, E, Telemetry>, Unit, options, current => changedConvertToLlm(G, D, M, E, Telemetry, current, value))
def optionsConvertToLlm(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>) -> Converter(G, D, M, E):
  match options:
    case Options{config, _, _, _}: configConvertToLlm(G, D, M, E, Telemetry, config)
def getConvertToLlm(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Converter(G, D, M, E)):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Converter(G, D, M, E)>:
        current : Options<G, D, M, E, Telemetry> <- R.read(Options<G, D, M, E, Telemetry>, options)
        return optionsConvertToLlm(G, D, M, E, Telemetry, current)
def configTransformContext(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry)) -> Maybe<&2, C.Callback<T.TransformContextInput<List<&2, RunMessage(G, D, M)>>, Result<&2, &2, E, List<&2, RunMessage(G, D, M)>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, value, _, _, _, _, _, _, _, _}: value
def replaceTransformContext(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry), value: Maybe<&2, C.Callback<T.TransformContextInput<List<&2, RunMessage(G, D, M)>>, Result<&2, &2, E, List<&2, RunMessage(G, D, M)>>>>) -> Config(G, D, M, E, Telemetry):
  match config:
    case T.AgentLoopConfig{options, model, convertToLlm, _, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{options, model, convertToLlm, value, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}
def changedTransformContext(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>, value: Maybe<&2, C.Callback<T.TransformContextInput<List<&2, RunMessage(G, D, M)>>, Result<&2, &2, E, List<&2, RunMessage(G, D, M)>>>>) -> Options<G, D, M, E, Telemetry> & Unit:
  match options:
    case Options{config, provider, validate, emptyDetails}: (Options{replaceTransformContext(G, D, M, E, Telemetry, config, value), provider, validate, emptyDetails}, Unit{})
def setTransformContext(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: Maybe<&2, C.Callback<T.TransformContextInput<List<&2, RunMessage(G, D, M)>>, Result<&2, &2, E, List<&2, RunMessage(G, D, M)>>>>) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<G, D, M, E, Telemetry>, Unit, options, current => changedTransformContext(G, D, M, E, Telemetry, current, value))
def optionsTransformContext(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>) -> Maybe<&2, C.Callback<T.TransformContextInput<List<&2, RunMessage(G, D, M)>>, Result<&2, &2, E, List<&2, RunMessage(G, D, M)>>>>:
  match options:
    case Options{config, _, _, _}: configTransformContext(G, D, M, E, Telemetry, config)
def getTransformContext(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Maybe<&2, C.Callback<T.TransformContextInput<List<&2, RunMessage(G, D, M)>>, Result<&2, &2, E, List<&2, RunMessage(G, D, M)>>>>):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Maybe<&2, C.Callback<T.TransformContextInput<List<&2, RunMessage(G, D, M)>>, Result<&2, &2, E, List<&2, RunMessage(G, D, M)>>>>>:
        current : Options<G, D, M, E, Telemetry> <- R.read(Options<G, D, M, E, Telemetry>, options)
        return optionsTransformContext(G, D, M, E, Telemetry, current)

def configGetApiKey(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry)) -> Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, value, _, _, _, _, _, _, _}: value
def replaceGetApiKey(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry), value: Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>) -> Config(G, D, M, E, Telemetry):
  match config:
    case T.AgentLoopConfig{options, model, convertToLlm, transformContext, _, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{options, model, convertToLlm, transformContext, value, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}
def changedGetApiKey(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>, value: Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>) -> Options<G, D, M, E, Telemetry> & Unit:
  match options:
    case Options{config, provider, validate, emptyDetails}: (Options{replaceGetApiKey(G, D, M, E, Telemetry, config, value), provider, validate, emptyDetails}, Unit{})
def setGetApiKey(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<G, D, M, E, Telemetry>, Unit, options, current => changedGetApiKey(G, D, M, E, Telemetry, current, value))
def optionsGetApiKey(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>) -> Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>:
  match options:
    case Options{config, _, _, _}: configGetApiKey(G, D, M, E, Telemetry, config)
def getGetApiKey(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>>:
        current : Options<G, D, M, E, Telemetry> <- R.read(Options<G, D, M, E, Telemetry>, options)
        return optionsGetApiKey(G, D, M, E, Telemetry, current)

def configOnPayload(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry)) -> Maybe<&2, Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, E)>:
  match config:
    case T.AgentLoopConfig{options, _, _, _, _, _, _, _, _, _, _, _}: Ai.onPayloadOption(Ai.JsonValue, Abort.AbortSignal<Unit>, Telemetry, Fetch.Fetch(Unit), E, options)
def replaceOnPayload(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry), value: Maybe<&2, Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, E)>) -> Config(G, D, M, E, Telemetry):
  match config:
    case T.AgentLoopConfig{options, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{Ai.withOnPayload(Ai.JsonValue, Abort.AbortSignal<Unit>, Telemetry, Fetch.Fetch(Unit), E, options, value), model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}
def changedOnPayload(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>, value: Maybe<&2, Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, E)>) -> Options<G, D, M, E, Telemetry> & Unit:
  match options:
    case Options{config, provider, validate, emptyDetails}: (Options{replaceOnPayload(G, D, M, E, Telemetry, config, value), provider, validate, emptyDetails}, Unit{})
def setOnPayload(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: Maybe<&2, Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, E)>) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<G, D, M, E, Telemetry>, Unit, options, current => changedOnPayload(G, D, M, E, Telemetry, current, value))
def optionsOnPayload(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>) -> Maybe<&2, Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, E)>:
  match options:
    case Options{config, _, _, _}: configOnPayload(G, D, M, E, Telemetry, config)
def getOnPayload(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Maybe<&2, Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, E)>):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Maybe<&2, Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, E)>>:
        current : Options<G, D, M, E, Telemetry> <- R.read(Options<G, D, M, E, Telemetry>, options)
        return optionsOnPayload(G, D, M, E, Telemetry, current)

def configOnResponse(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry)) -> Maybe<&2, Ai.ResponseCallback(Ai.Model<Ai.JsonValue>, E)>:
  match config:
    case T.AgentLoopConfig{options, _, _, _, _, _, _, _, _, _, _, _}: Ai.onResponseOption(Ai.JsonValue, Abort.AbortSignal<Unit>, Telemetry, Fetch.Fetch(Unit), E, options)
def replaceOnResponse(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry), value: Maybe<&2, Ai.ResponseCallback(Ai.Model<Ai.JsonValue>, E)>) -> Config(G, D, M, E, Telemetry):
  match config:
    case T.AgentLoopConfig{options, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{Ai.withOnResponse(Ai.JsonValue, Abort.AbortSignal<Unit>, Telemetry, Fetch.Fetch(Unit), E, options, value), model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}
def changedOnResponse(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>, value: Maybe<&2, Ai.ResponseCallback(Ai.Model<Ai.JsonValue>, E)>) -> Options<G, D, M, E, Telemetry> & Unit:
  match options:
    case Options{config, provider, validate, emptyDetails}: (Options{replaceOnResponse(G, D, M, E, Telemetry, config, value), provider, validate, emptyDetails}, Unit{})
def setOnResponse(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: Maybe<&2, Ai.ResponseCallback(Ai.Model<Ai.JsonValue>, E)>) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<G, D, M, E, Telemetry>, Unit, options, current => changedOnResponse(G, D, M, E, Telemetry, current, value))
def optionsOnResponse(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>) -> Maybe<&2, Ai.ResponseCallback(Ai.Model<Ai.JsonValue>, E)>:
  match options:
    case Options{config, _, _, _}: configOnResponse(G, D, M, E, Telemetry, config)
def getOnResponse(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Maybe<&2, Ai.ResponseCallback(Ai.Model<Ai.JsonValue>, E)>):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Maybe<&2, Ai.ResponseCallback(Ai.Model<Ai.JsonValue>, E)>>:
        current : Options<G, D, M, E, Telemetry> <- R.read(Options<G, D, M, E, Telemetry>, options)
        return optionsOnResponse(G, D, M, E, Telemetry, current)

def configBeforeToolCall(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry)) -> Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<G, D, M, E>>, Result<&2, &2, E, T.BeforeToolCallUpdate<T.AgentContext<G, D, M, E>>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, value, _}: value
def replaceBeforeToolCall(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry), value: Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<G, D, M, E>>, Result<&2, &2, E, T.BeforeToolCallUpdate<T.AgentContext<G, D, M, E>>>>>) -> Config(G, D, M, E, Telemetry):
  match config:
    case T.AgentLoopConfig{options, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, _, afterToolCall}: T.AgentLoopConfig{options, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, value, afterToolCall}
def changedBeforeToolCall(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>, value: Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<G, D, M, E>>, Result<&2, &2, E, T.BeforeToolCallUpdate<T.AgentContext<G, D, M, E>>>>>) -> Options<G, D, M, E, Telemetry> & Unit:
  match options:
    case Options{config, provider, validate, emptyDetails}: (Options{replaceBeforeToolCall(G, D, M, E, Telemetry, config, value), provider, validate, emptyDetails}, Unit{})
def setBeforeToolCall(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<G, D, M, E>>, Result<&2, &2, E, T.BeforeToolCallUpdate<T.AgentContext<G, D, M, E>>>>>) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<G, D, M, E, Telemetry>, Unit, options, current => changedBeforeToolCall(G, D, M, E, Telemetry, current, value))
def optionsBeforeToolCall(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>) -> Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<G, D, M, E>>, Result<&2, &2, E, T.BeforeToolCallUpdate<T.AgentContext<G, D, M, E>>>>>:
  match options:
    case Options{config, _, _, _}: configBeforeToolCall(G, D, M, E, Telemetry, config)
def getBeforeToolCall(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<G, D, M, E>>, Result<&2, &2, E, T.BeforeToolCallUpdate<T.AgentContext<G, D, M, E>>>>>):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<G, D, M, E>>, Result<&2, &2, E, T.BeforeToolCallUpdate<T.AgentContext<G, D, M, E>>>>>>:
        current : Options<G, D, M, E, Telemetry> <- R.read(Options<G, D, M, E, Telemetry>, options)
        return optionsBeforeToolCall(G, D, M, E, Telemetry, current)


def configAfterToolCall(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry)) -> Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<G, D, M, E>>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, value}: value
def replaceAfterToolCall(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, config: Config(G, D, M, E, Telemetry), value: Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<G, D, M, E>>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>) -> Config(G, D, M, E, Telemetry):
  match config:
    case T.AgentLoopConfig{options, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, _}: T.AgentLoopConfig{options, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, value}
def changedAfterToolCall(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>, value: Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<G, D, M, E>>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>) -> Options<G, D, M, E, Telemetry> & Unit:
  match options:
    case Options{config, provider, validate, emptyDetails}: (Options{replaceAfterToolCall(G, D, M, E, Telemetry, config, value), provider, validate, emptyDetails}, Unit{})
def setAfterToolCall(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<G, D, M, E>>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<G, D, M, E, Telemetry>, Unit, options, current => changedAfterToolCall(G, D, M, E, Telemetry, current, value))
def optionsAfterToolCall(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, options: Options<G, D, M, E, Telemetry>) -> Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<G, D, M, E>>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>:
  match options:
    case Options{config, _, _, _}: configAfterToolCall(G, D, M, E, Telemetry, config)
def getAfterToolCall(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<G, D, M, E>>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<G, D, M, E>>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>>:
        current : Options<G, D, M, E, Telemetry> <- R.read(Options<G, D, M, E, Telemetry>, options)
        return optionsAfterToolCall(G, D, M, E, Telemetry, current)

def changedShouldStopAfterTurn(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, hooks: TurnHooks(G, D, M, E), value: Maybe<&2, StopHook(Turn(G, D, M, E), E)>) -> TurnHooks(G, D, M, E) & Unit:
  match hooks:
    case Hooks{_, legacy, turnContext}: (Hooks{value, legacy, turnContext}, Unit{})
def setShouldStopAfterTurn(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: Maybe<&2, StopHook(Turn(G, D, M, E), E)>) -> IO(Unit):
  match agent:
    case Agent{_, _, _, hooks, _, _}: R.modify(TurnHooks(G, D, M, E), Unit, hooks, current => changedShouldStopAfterTurn(G, D, M, E, Telemetry, current, value))
def hooksShouldStopAfterTurn(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, hooks: TurnHooks(G, D, M, E)) -> Maybe<&2, StopHook(Turn(G, D, M, E), E)>:
  match hooks:
    case Hooks{value, _, _}: value
def getShouldStopAfterTurn(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Maybe<&2, StopHook(Turn(G, D, M, E), E)>):
  match agent:
    case Agent{_, _, _, hooks, _, _}:
      do IO<Maybe<&2, StopHook(Turn(G, D, M, E), E)>>:
        current : TurnHooks(G, D, M, E) <- R.read(TurnHooks(G, D, M, E), hooks)
        return hooksShouldStopAfterTurn(G, D, M, E, Telemetry, current)

def changedPrepareNextTurn(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, hooks: TurnHooks(G, D, M, E), value: Maybe<&2, LegacyHook(Update(G, D, M, E), E)>) -> TurnHooks(G, D, M, E) & Unit:
  match hooks:
    case Hooks{stop, _, turnContext}: (Hooks{stop, value, turnContext}, Unit{})
def setPrepareNextTurn(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: Maybe<&2, LegacyHook(Update(G, D, M, E), E)>) -> IO(Unit):
  match agent:
    case Agent{_, _, _, hooks, _, _}: R.modify(TurnHooks(G, D, M, E), Unit, hooks, current => changedPrepareNextTurn(G, D, M, E, Telemetry, current, value))
def hooksPrepareNextTurn(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, hooks: TurnHooks(G, D, M, E)) -> Maybe<&2, LegacyHook(Update(G, D, M, E), E)>:
  match hooks:
    case Hooks{_, value, _}: value
def getPrepareNextTurn(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Maybe<&2, LegacyHook(Update(G, D, M, E), E)>):
  match agent:
    case Agent{_, _, _, hooks, _, _}:
      do IO<Maybe<&2, LegacyHook(Update(G, D, M, E), E)>>:
        current : TurnHooks(G, D, M, E) <- R.read(TurnHooks(G, D, M, E), hooks)
        return hooksPrepareNextTurn(G, D, M, E, Telemetry, current)

def changedPrepareNextTurnWithContext(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, hooks: TurnHooks(G, D, M, E), value: Maybe<&2, ContextHook(Turn(G, D, M, E), Update(G, D, M, E), E)>) -> TurnHooks(G, D, M, E) & Unit:
  match hooks:
    case Hooks{stop, legacy, _}: (Hooks{stop, legacy, value}, Unit{})
def setPrepareNextTurnWithContext(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>, value: Maybe<&2, ContextHook(Turn(G, D, M, E), Update(G, D, M, E), E)>) -> IO(Unit):
  match agent:
    case Agent{_, _, _, hooks, _, _}: R.modify(TurnHooks(G, D, M, E), Unit, hooks, current => changedPrepareNextTurnWithContext(G, D, M, E, Telemetry, current, value))
def hooksPrepareNextTurnWithContext(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, hooks: TurnHooks(G, D, M, E)) -> Maybe<&2, ContextHook(Turn(G, D, M, E), Update(G, D, M, E), E)>:
  match hooks:
    case Hooks{_, _, value}: value
def getPrepareNextTurnWithContext(-G: Data, -D: Data, -M: Data, -E: Data, -Telemetry: Data, agent: Agent<G, D, M, E, Telemetry>) -> IO(Maybe<&2, ContextHook(Turn(G, D, M, E), Update(G, D, M, E), E)>):
  match agent:
    case Agent{_, _, _, hooks, _, _}:
      do IO<Maybe<&2, ContextHook(Turn(G, D, M, E), Update(G, D, M, E), E)>>:
        current : TurnHooks(G, D, M, E) <- R.read(TurnHooks(G, D, M, E), hooks)
        return hooksPrepareNextTurnWithContext(G, D, M, E, Telemetry, current)
