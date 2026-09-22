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

# ---- from agent-stateLocal.bend ----
# Pure stateLocal transitions from agent.ts. The Agent owner provides synchronization
# and waits for listeners before applying finishRunState; agent_end alone is not idle.
type AgentInitialState<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data> is Data:
  AgentInitialState{systemPromptState: Maybe<&2, String>, model: Maybe<&2, Ai.Model<Value>>, thinkingLevel: Maybe<&2, T.ThinkingLevel()>, tools: Maybe<&2, List<&2, T.AgentTool<Parameters, Validated, Details, Arguments, Signal, Error>>>, messages: Maybe<&2, List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>>}

def defaultModel(-Value: Data) -> Ai.Model<Value>:
  +zero = F.fromU32(0)
  Ai.Model{"unknown", "unknown", Ai.CustomModelApi{"unknown"}, "unknown", "", False{}, None{}, Nil{}, Ai.ModelCost{zero, zero, zero, zero, None{}}, zero, zero, None{}, None{}, None{}}

def defaultConvertToLlm(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, messages: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>) -> List<&2, Ai.Message<Parameters, Arguments, DiagnosticDetails, Details>>:
  match messages:
    case Nil{}: Nil{}
    case T.LlmMessage{value} <> rest: value <> defaultConvertToLlm(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, rest)
    case T.CustomMessage{_} <> rest: defaultConvertToLlm(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, rest)

def declarations(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, tools: List<&2, T.AgentTool<Parameters, Validated, Details, Arguments, Signal, Error>>) -> List<&2, Ai.Tool<Parameters>>:
  match tools:
    case Nil{}: Nil{}
    case tool <> rest: T.toTool(Parameters, Validated, Details, Arguments, Signal, Error, tool) <> declarations(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, rest)

def prependInitial(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, initial: Maybe<&2, Ai.SystemMessage<Parameters>>, messages: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>) -> List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>:
  match initial:
    case None{}: messages
    case Some{value}: T.LlmMessage{Ai.System{value}} <> messages

def initialMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, promptLocal: Maybe<&2, String>, tools: List<&2, Ai.Tool<Parameters>>, messages: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>) -> List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>:
  match messages:
    case T.LlmMessage{Ai.System{value}} <> rest: T.LlmMessage{Ai.System{value}} <> rest
    case other: prependInitial(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Transcript.createInitialSystemMessage(Parameters, promptLocal, Some{tools}), other)

def createState(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, initial: AgentInitialState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>) -> T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>:
  match initial:
    case AgentInitialState{promptLocal, model, thinking, tools, messages}:
      +selectedTools = Maybe.default(&2, List<&2, T.AgentTool<Parameters, Validated, Details, Arguments, Signal, Error>>, tools, Nil{})
      T.AgentState{Maybe.default(&2, Ai.Model<Value>, model, defaultModel(Value)), Maybe.default(&2, T.ThinkingLevel(), thinking, Ai.Off{}), selectedTools, initialMessages(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, promptLocal, declarations(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, selectedTools), Maybe.default(&2, List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>, messages, Nil{})), False{}, None{}, Set.empty(), None{}}

def systemPromptState(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, stateLocal: T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>) -> String:
  match stateLocal:
    case T.AgentState{_, _, _, messages, _, _, _, _}: Transcript.getCurrentSystemPrompt(Parameters, Arguments, DiagnosticDetails, Details, defaultConvertToLlm(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, messages))

def beginRun(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, stateLocal: T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>) -> T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>:
  match stateLocal:
    case T.AgentState{model, thinking, tools, messages, _, _, pending, _}: T.AgentState{model, thinking, tools, messages, True{}, None{}, pending, None{}}

def finishRunState(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, stateLocal: T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>) -> T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>:
  match stateLocal:
    case T.AgentState{model, thinking, tools, messages, _, _, _, error}: T.AgentState{model, thinking, tools, messages, False{}, None{}, Set.empty(), error}

def nonemptyError(previous: Maybe<&2, String>, incoming: Maybe<&2, String>) -> Maybe<&2, String>:
  match incoming:
    case None{}: previous
    case Some{+text}: Bool.pick(Maybe<&2, String>, String.is_empty(text), previous, Some{text})

def turnError(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, previous: Maybe<&2, String>, message: T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>) -> Maybe<&2, String>:
  match message:
    case T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, error, _, _, _}}}: nonemptyError(previous, error)
    case _: previous

def processEvent(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -PartialResult: Data, -ExecutionResult: Data, stateLocal: T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>, event: T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, PartialResult, ExecutionResult>) -> T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>:
  match stateLocal event:
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.MessageStart{message}: T.AgentState{model, thinking, tools, messages, streaming, Some{message}, pending, error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.MessageUpdate{message, _}: T.AgentState{model, thinking, tools, messages, streaming, Some{message}, pending, error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.MessageEnd{message}: T.AgentState{model, thinking, tools, List.append(&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>, messages, message <> Nil{}), streaming, None{}, pending, error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.ToolExecutionStart{id, _, _}: T.AgentState{model, thinking, tools, messages, streaming, partial, Set.insert(pending, id), error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.ToolExecutionEnd{id, _, _, _}: T.AgentState{model, thinking, tools, messages, streaming, partial, Set.remove(pending, id), error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.TurnEnd{message, _}: T.AgentState{model, thinking, tools, messages, streaming, partial, pending, turnError(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, error, message)}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} T.AgentEnd{_}: T.AgentState{model, thinking, tools, messages, streaming, None{}, pending, error}
    case T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error} _: T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error}

# Replays the transcript baseline, retaining model/thinking and executable tools.
# The synchronized owner rejects reset during a run and clears both queues.
def stateReset(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, stateLocal: T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>) -> T.AgentState<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value>:
  match stateLocal:
    case T.AgentState{model, thinking, tools, messages, _, _, _, _}:
      baseline = Transcript.getCurrentSystemMessage(Parameters, Arguments, DiagnosticDetails, Details, defaultConvertToLlm(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, messages))
      T.AgentState{model, thinking, tools, prependInitial(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, baseline, Nil{}), False{}, None{}, Set.empty(), None{}}

# User-editable stateLocal is an explicit value transition. Runtime fields remain
# owned by the run lifecycle, including when an update occurs during delivery.
type StateChange<-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data> is Data:
  SetModel{model: Ai.Model<J>}
  SetThinkingLevel{level: T.ThinkingLevel()}
  SetTools{tools: List<&2, T.AgentTool<P, V, D, A, S, E>>}
  ReplaceMessages{messages: List<&2, T.AgentMessage<P, A, G, D, M>>}
  AppendMessage{message: T.AgentMessage<P, A, G, D, M>}
def applyChange(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, stateLocal: T.AgentState<P, A, G, D, M, V, S, E, J>, change: StateChange<P, A, G, D, M, V, S, E, J>) -> T.AgentState<P, A, G, D, M, V, S, E, J>:
  match stateLocal change:
    case T.AgentState{_, thinking, tools, messages, streaming, current, pending, error} SetModel{model}: T.AgentState{model, thinking, tools, messages, streaming, current, pending, error}
    case T.AgentState{model, _, tools, messages, streaming, current, pending, error} SetThinkingLevel{thinking}: T.AgentState{model, thinking, tools, messages, streaming, current, pending, error}
    case T.AgentState{model, thinking, _, messages, streaming, current, pending, error} SetTools{tools}: T.AgentState{model, thinking, tools, messages, streaming, current, pending, error}
    case T.AgentState{model, thinking, tools, _, streaming, current, pending, error} ReplaceMessages{messages}: T.AgentState{model, thinking, tools, messages, streaming, current, pending, error}
    case T.AgentState{model, thinking, tools, messages, streaming, current, pending, error} AppendMessage{message}: T.AgentState{model, thinking, tools, List.append(&2, T.AgentMessage<P, A, G, D, M>, messages, message <> Nil{}), streaming, current, pending, error}


# Immutable counterpart of agent.ts PendingMessageQueue. The Agent owner
# commits these transitions atomically with its other runtime stateLocal.
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
  Queues{steering: PendingMessageQueue<M>, followUpLocal: PendingMessageQueue<M>}
type QueueKind is Data:
  QueuesSteering{}
  FollowUp{}

def newQueues(-M: Data, steering: T.QueueMode, followUpLocal: T.QueueMode) -> Queues<M>:
  Queues{newPending(M, steering), newPending(M, followUpLocal)}
def defaultQueues(-M: Data) -> Queues<M>: newQueues(M, T.OneAtATime{}, T.OneAtATime{})
def enqueueQueues(-M: Data, queues: Queues<M>, kind: QueueKind, message: M) -> Queues<M>:
  match queues kind:
    case Queues{steering, followUpLocal} QueuesSteering{}: Queues{enqueuePending(M, steering, message), followUpLocal}
    case Queues{steering, followUpLocal} FollowUp{}: Queues{steering, enqueuePending(M, followUpLocal, message)}
def setModeQueues(-M: Data, queues: Queues<M>, kind: QueueKind, mode: T.QueueMode) -> Queues<M>:
  match queues kind:
    case Queues{steering, followUpLocal} QueuesSteering{}: Queues{setModePending(M, steering, mode), followUpLocal}
    case Queues{steering, followUpLocal} FollowUp{}: Queues{steering, setModePending(M, followUpLocal, mode)}
def clearQueues(-M: Data, queues: Queues<M>, kind: QueueKind) -> Queues<M>:
  match queues kind:
    case Queues{steering, followUpLocal} QueuesSteering{}: Queues{clearPending(M, steering), followUpLocal}
    case Queues{steering, followUpLocal} FollowUp{}: Queues{steering, clearPending(M, followUpLocal)}
def clearAll(-M: Data, queues: Queues<M>) -> Queues<M>:
  match queues:
    case Queues{steering, followUpLocal}: Queues{clearPending(M, steering), clearPending(M, followUpLocal)}
def queuesHaveMessages(-M: Data, queues: Queues<M>) -> Bool:
  match queues:
    case Queues{steering, followUpLocal}: hasItems(M, steering) || hasItems(M, followUpLocal)
def drainedQueues(-M: Data, kind: QueueKind, other: PendingMessageQueue<M>, result: PendingMessageQueue<M> & List<&2, M>) -> Queues<M> & List<&2, M>:
  match kind result:
    case QueuesSteering{} Tuple{remaining, messages}: (Queues{remaining, other}, messages)
    case FollowUp{} Tuple{remaining, messages}: (Queues{other, remaining}, messages)
def drainQueues(-M: Data, queues: Queues<M>, kind: QueueKind) -> Queues<M> & List<&2, M>:
  match queues kind:
    case Queues{steering, followUpLocal} QueuesSteering{}: drainedQueues(M, QueuesSteering{}, followUpLocal, drainPending(M, steering))
    case Queues{steering, followUpLocal} FollowUp{}: drainedQueues(M, FollowUp{}, steering, drainPending(M, followUpLocal))

def getModeQueues(-M: Data, queues: Queues<M>, kind: QueueKind) -> T.QueueMode:
  match queues kind:
    case Queues{steering, _} QueuesSteering{}: getModePending(M, steering)
    case Queues{_, followUpLocal} FollowUp{}: getModePending(M, followUpLocal)


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

def isSystem(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, message: T.AgentMessage<P, A, G, D, C>) -> Bool:
  match message:
    case T.LlmMessage{Ai.System{_}}: True{}
    case _: False{}
def finalTail(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, nonSystem: Bool, message: T.AgentMessage<P, A, G, D, C>) -> Tail:
  match message:
    case T.LlmMessage{Ai.Assistant{_}}: Assistant{}
    case _: Bool.pick(Tail, nonSystem, Other{}, Empty{})
def tail(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, messages: List<&2, T.AgentMessage<P, A, G, D, C>>, nonSystem: Bool) -> Tail:
  match messages:
    case Nil{}: Empty{}
    case +last <> Nil{}: finalTail(P, A, G, D, C, nonSystem || Bool.not(isSystem(P, A, G, D, C, last)), last)
    case message <> rest: tail(P, A, G, D, C, rest, nonSystem || Bool.not(isSystem(P, A, G, D, C, message)))

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
def planContinue(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, active: Bool, messages: List<&2, T.AgentMessage<P, A, G, D, C>>, queues: Queues<T.AgentMessage<P, A, G, D, C>>) -> Queues<T.AgentMessage<P, A, G, D, C>> & Result<&2, &2, ContinueError, Plan<T.AgentMessage<P, A, G, D, C>>>:
  match active:
    case True{}: (queues, Fail{ContinueBusy{}})
    case False{}: planTail(T.AgentMessage<P, A, G, D, C>, queues, tail(P, A, G, D, C, messages, False{}))


# The owner stores Agent stateLocal and queues together in State. Claiming a run and
# its pure preparation therefore share one transaction, with no effectful callback under
# the lock. ActiveRun handles are borrowed until the owner's final disposal.
type ActiveRun is Data:
  ActiveRun{completion: D.Deferred<Unit>, controller: Abort.AbortController<Unit>}
type Cell<-State: Data> is Data:
  Cell{value: State, active: Maybe<&2, ActiveRun>, retired: List<&2, ActiveRun>}
type Lifecycle<-State: Data> is Data:
  Lifecycle{cell: R.Ref<Cell<State>>}
type Prepared<-State: Data, -Value: Data> is Data:
  Prepared{stateLocal: State, value: Value}
type ClaimError<-Error: Data> is Data:
  LifeBusy{}
  Rejected{error: Error}
type Claimed<-Value: Data> is Data:
  Claimed{run: ActiveRun, value: Value}

def newLife(-State: Data, value: State) -> IO(Lifecycle<State>):
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
def signalLife(run: ActiveRun) -> Abort.AbortSignal<Unit>:
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
def claimedLife(-Error: Data, -Value: Data, candidate: ActiveRun, result: Result<&2, &2, ClaimError<Error>, Claimed<Value>>) -> IO(Result<&2, &2, ClaimError<Error>, Claimed<Value>>):
  match result:
    case Done{value}: IO.pure(Result<&2, &2, ClaimError<Error>, Claimed<Value>>, Done{value})
    case Fail{error}:
      do IO<Result<&2, &2, ClaimError<Error>, Claimed<Value>>>:
        disposeRun(candidate)
        return Fail{error}
def claimLife(-State: Data, -Error: Data, -Value: Data, owner: Lifecycle<State>, prepare: State -> Result<&2, &2, Error, Prepared<State, Value>>) -> IO(Result<&2, &2, ClaimError<Error>, Claimed<Value>>):
  match owner:
    case Lifecycle{cell}:
      do IO<Result<&2, &2, ClaimError<Error>, Claimed<Value>>>:
        +candidate : ActiveRun <- createRun()
        result : Result<&2, &2, ClaimError<Error>, Claimed<Value>> <- R.modify(Cell<State>, Result<&2, &2, ClaimError<Error>, Claimed<Value>>, cell, current => claimState(State, Error, Value, current, candidate, prepare))
        claimedLife(Error, Value, candidate, result)
def modified(-State: Data, -Value: Type, active: Maybe<&2, ActiveRun>, retired: List<&2, ActiveRun>, result: State & Value) -> Cell<State> & Value:
  match result:
    case Tuple{next, value}: (Cell{next, active, retired}, value)
def modifyState(-State: Data, -Value: Type, cell: Cell<State>, transform: State -> Maybe<&2, ActiveRun> -> State & Value) -> Cell<State> & Value:
  match cell:
    case Cell{stateLocal, +active, retired}: modified(State, Value, active, retired, transform(stateLocal, active))
# Event reductions, queue updates and reset share the run-claim transaction.
def modify(-State: Data, -Value: Type, owner: Lifecycle<State>, transform: State -> Maybe<&2, ActiveRun> -> State & Value) -> IO(Value):
  match owner:
    case Lifecycle{cell}: R.modify(Cell<State>, Value, cell, current => modifyState(State, Value, current, transform))

def readValue(-State: Data, cell: Cell<State>) -> State:
  match cell:
    case Cell{value, _, _}: value
def readLife(-State: Data, owner: Lifecycle<State>) -> IO(State):
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
def waitForIdleLife(-State: Data, owner: Lifecycle<State>) -> IO(Unit):
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
def abortLife(-State: Data, owner: Lifecycle<State>) -> IO(Unit):
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
def finishLife(-State: Data, owner: Lifecycle<State>, +run: ActiveRun, reduce: State -> State) -> IO(Bool):
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
        finished : Bool <- finishLife(State, owner, run, reduce)
        return runResult(Error, recovered)
# Like Agent.runWithLifecycle: recovery handles executor failure, and final
# stateLocal/idle settlement happens even when recovery itself returns an error.
def runWithLifecycle(-State: Data, -Error: Data, -Value: Data, +owner: Lifecycle<State>, prepare: State -> Result<&2, &2, Error, Prepared<State, Value>>, execute: Claimed<Value> -> IO(Result<&2, &2, Error, Unit>), recover: ActiveRun -> Error -> IO(Result<&2, &2, Error, Unit>), reduce: State -> State) -> IO(Result<&2, &2, RunError<Error>, Unit>):
  do IO<Result<&2, &2, RunError<Error>, Unit>>:
    result : Result<&2, &2, ClaimError<Error>, Claimed<Value>> <- claimLife(State, Error, Value, owner, prepare)
    executeClaim(State, Error, Value, owner, result, execute, recover, reduce)

def disposeRunsLife(runs: List<&2, ActiveRun>) -> IO(Unit):
  match runs:
    case Nil{}: IO.pure(Unit, Unit{})
    case run <> rest:
      do IO<Unit>:
        disposeRun(run)
        disposeRunsLife(rest)
def disposed(-State: Data, cell: Cell<State>) -> IO(State):
  match cell:
    case Cell{value, None{}, retired}:
      do IO<State>:
        disposeRunsLife(retired)
        return value
    case Cell{_, Some{_}, _}: IO.die(State, 1, "Agent lifecycle disposed during an active run")
# Retire owner/run/signal aliases and drain waiters before final disposal.
# Completed signals remain inspectable throughout the owner's lifetime.
def disposeLife(-State: Data, owner: Lifecycle<State>) -> IO(State):
  match owner:
    case Lifecycle{cell}:
      do IO<State>:
        previous : Cell<State> <- R.dispose(Cell<State>, cell)
        disposed(State, previous)


# P/A/G/D/C are schema/arguments/diagnostics/details/custom message values;
# V/S/E/J are validated arguments/tool signalLocal/tool error/model metadata.
# One synchronized owner couples transcript, queues and active-run status.
type OwnedState<-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data> is Data:
  OwnedState{stateLocal: T.AgentState<P, A, G, D, C, V, S, E, J>, queues: Queues<T.AgentMessage<P, A, G, D, C>>}
type OwnedRuntime<-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data> is Data:
  OwnedRuntime{lifecycle: Lifecycle<OwnedState<P, A, G, D, C, V, S, E, J>>}

def newRuntime(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, initial: AgentInitialState<P, A, G, D, C, V, S, E, J>, steeringMode: T.QueueMode, followUpMode: T.QueueMode) -> IO(OwnedRuntime<P, A, G, D, C, V, S, E, J>):
  do IO<OwnedRuntime<P, A, G, D, C, V, S, E, J>>:
    lifecycle : Lifecycle<OwnedState<P, A, G, D, C, V, S, E, J>> <- newLife(OwnedState<P, A, G, D, C, V, S, E, J>, OwnedState{createState(P, A, G, D, C, V, S, E, J, initial), newQueues(T.AgentMessage<P, A, G, D, C>, steeringMode, followUpMode)})
    return OwnedRuntime{lifecycle}
def snapshotRuntime(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>) -> IO(OwnedState<P, A, G, D, C, V, S, E, J>):
  match runtime:
    case OwnedRuntime{lifecycle}: readLife(OwnedState<P, A, G, D, C, V, S, E, J>, lifecycle)
def stateValue(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>) -> T.AgentState<P, A, G, D, C, V, S, E, J>:
  match owned:
    case OwnedState{stateLocal, _}: stateLocal
def readRuntime(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>) -> IO(T.AgentState<P, A, G, D, C, V, S, E, J>):
  do IO<T.AgentState<P, A, G, D, C, V, S, E, J>>:
    owned : OwnedState<P, A, G, D, C, V, S, E, J> <- snapshotRuntime(P, A, G, D, C, V, S, E, J, runtime)
    return stateValue(P, A, G, D, C, V, S, E, J, owned)
def history(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, stateLocal: T.AgentState<P, A, G, D, C, V, S, E, J>) -> List<&2, T.AgentMessage<P, A, G, D, C>>:
  match stateLocal:
    case T.AgentState{_, _, _, messages, _, _, _, _}: messages

def enqueueState(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>, kind: QueueKind, message: T.AgentMessage<P, A, G, D, C>) -> OwnedState<P, A, G, D, C, V, S, E, J> & Unit:
  match owned:
    case OwnedState{stateLocal, queues}: (OwnedState{stateLocal, enqueueQueues(T.AgentMessage<P, A, G, D, C>, queues, kind, message)}, Unit{})
def enqueueRuntime(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, kind: QueueKind, message: T.AgentMessage<P, A, G, D, C>) -> IO(Unit):
  match runtime:
    case OwnedRuntime{lifecycle}: modify(OwnedState<P, A, G, D, C, V, S, E, J>, Unit, lifecycle, owned => active => enqueueState(P, A, G, D, C, V, S, E, J, owned, kind, message))
def steerRuntime(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, message: T.AgentMessage<P, A, G, D, C>) -> IO(Unit): enqueueRuntime(P, A, G, D, C, V, S, E, J, runtime, QueuesSteering{}, message)
def followUpRuntime(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, message: T.AgentMessage<P, A, G, D, C>) -> IO(Unit): enqueueRuntime(P, A, G, D, C, V, S, E, J, runtime, FollowUp{}, message)
def updatedQueues(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>, update: Queues<T.AgentMessage<P, A, G, D, C>> -> Queues<T.AgentMessage<P, A, G, D, C>>) -> OwnedState<P, A, G, D, C, V, S, E, J> & Unit:
  match owned:
    case OwnedState{stateLocal, queues}: (OwnedState{stateLocal, update(queues)}, Unit{})
def updateQueues(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, update: Queues<T.AgentMessage<P, A, G, D, C>> -> Queues<T.AgentMessage<P, A, G, D, C>>) -> IO(Unit):
  match runtime:
    case OwnedRuntime{lifecycle}: modify(OwnedState<P, A, G, D, C, V, S, E, J>, Unit, lifecycle, owned => active => updatedQueues(P, A, G, D, C, V, S, E, J, owned, update))
def clearQueue(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, kind: QueueKind) -> IO(Unit): updateQueues(P, A, G, D, C, V, S, E, J, runtime, queues => clearQueues(T.AgentMessage<P, A, G, D, C>, queues, kind))
def clearAllRuntimeQueues(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>) -> IO(Unit): updateQueues(P, A, G, D, C, V, S, E, J, runtime, queues => clearAll(T.AgentMessage<P, A, G, D, C>, queues))
def setQueueMode(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, kind: QueueKind, mode: T.QueueMode) -> IO(Unit): updateQueues(P, A, G, D, C, V, S, E, J, runtime, queues => setModeQueues(T.AgentMessage<P, A, G, D, C>, queues, kind, mode))
def drainedRuntime(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, stateLocal: T.AgentState<P, A, G, D, C, V, S, E, J>, result: Queues<T.AgentMessage<P, A, G, D, C>> & List<&2, T.AgentMessage<P, A, G, D, C>>) -> OwnedState<P, A, G, D, C, V, S, E, J> & List<&2, T.AgentMessage<P, A, G, D, C>>:
  match result:
    case Tuple{queues, messages}: (OwnedState{stateLocal, queues}, messages)
def drainState(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>, kind: QueueKind) -> OwnedState<P, A, G, D, C, V, S, E, J> & List<&2, T.AgentMessage<P, A, G, D, C>>:
  match owned:
    case OwnedState{stateLocal, queues}: drainedRuntime(P, A, G, D, C, V, S, E, J, stateLocal, drainQueues(T.AgentMessage<P, A, G, D, C>, queues, kind))
def drainRuntime(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, kind: QueueKind) -> IO(List<&2, T.AgentMessage<P, A, G, D, C>>):
  match runtime:
    case OwnedRuntime{lifecycle}: modify(OwnedState<P, A, G, D, C, V, S, E, J>, List<&2, T.AgentMessage<P, A, G, D, C>>, lifecycle, owned => active => drainState(P, A, G, D, C, V, S, E, J, owned, kind))

def resetState(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>, active: Maybe<&2, ActiveRun>) -> OwnedState<P, A, G, D, C, V, S, E, J> & Result<&2, &2, String, Unit>:
  match owned active:
    case OwnedState{stateLocal, queues} None{}: (OwnedState{stateReset(P, A, G, D, C, V, S, E, J, stateLocal), clearAll(T.AgentMessage<P, A, G, D, C>, queues)}, Done{Unit{}})
    case OwnedState{stateLocal, queues} Some{_}: (OwnedState{stateLocal, queues}, Fail{"Agent is already processing. Wait for completion before resetting."})
def resetRuntime(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>) -> IO(Result<&2, &2, String, Unit>):
  match runtime:
    case OwnedRuntime{lifecycle}: modify(OwnedState<P, A, G, D, C, V, S, E, J>, Result<&2, &2, String, Unit>, lifecycle, owned => active => resetState(P, A, G, D, C, V, S, E, J, owned, active))

def preparePrompt(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>, messages: List<&2, T.AgentMessage<P, A, G, D, C>>) -> Result<&2, &2, String, Prepared<OwnedState<P, A, G, D, C, V, S, E, J>, Plan<T.AgentMessage<P, A, G, D, C>>>>:
  match owned:
    case OwnedState{stateLocal, queues}: Done{Prepared{OwnedState{beginRun(P, A, G, D, C, V, S, E, J, stateLocal), queues}, Prompt{messages, False{}}}}
def planned(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, stateLocal: T.AgentState<P, A, G, D, C, V, S, E, J>, result: Queues<T.AgentMessage<P, A, G, D, C>> & Result<&2, &2, ContinueError, Plan<T.AgentMessage<P, A, G, D, C>>>) -> Result<&2, &2, String, Prepared<OwnedState<P, A, G, D, C, V, S, E, J>, Plan<T.AgentMessage<P, A, G, D, C>>>>:
  match result:
    case Tuple{_, Fail{error}}: Fail{errorMessage(error)}
    case Tuple{queues, Done{plan}}: Done{Prepared{OwnedState{beginRun(P, A, G, D, C, V, S, E, J, stateLocal), queues}, plan}}
def prepareContinue(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>) -> Result<&2, &2, String, Prepared<OwnedState<P, A, G, D, C, V, S, E, J>, Plan<T.AgentMessage<P, A, G, D, C>>>>:
  match owned:
    case OwnedState{+stateLocal, queues}: planned(P, A, G, D, C, V, S, E, J, stateLocal, planContinue(P, A, G, D, C, False{}, history(P, A, G, D, C, V, S, E, J, stateLocal), queues))
def beginPrompt(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, messages: List<&2, T.AgentMessage<P, A, G, D, C>>) -> IO(Result<&2, &2, ClaimError<String>, Claimed<Plan<T.AgentMessage<P, A, G, D, C>>>>):
  match runtime:
    case OwnedRuntime{lifecycle}: claimLife(OwnedState<P, A, G, D, C, V, S, E, J>, String, Plan<T.AgentMessage<P, A, G, D, C>>, lifecycle, owned => preparePrompt(P, A, G, D, C, V, S, E, J, owned, messages))
def beginContinue(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>) -> IO(Result<&2, &2, ClaimError<String>, Claimed<Plan<T.AgentMessage<P, A, G, D, C>>>>):
  match runtime:
    case OwnedRuntime{lifecycle}: claimLife(OwnedState<P, A, G, D, C, V, S, E, J>, String, Plan<T.AgentMessage<P, A, G, D, C>>, lifecycle, owned => prepareContinue(P, A, G, D, C, V, S, E, J, owned))
def ended(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>) -> OwnedState<P, A, G, D, C, V, S, E, J>:
  match owned:
    case OwnedState{stateLocal, queues}: OwnedState{finishRunState(P, A, G, D, C, V, S, E, J, stateLocal), queues}
def finishRunRuntime(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, run: ActiveRun) -> IO(Bool):
  match runtime:
    case OwnedRuntime{lifecycle}: finishLife(OwnedState<P, A, G, D, C, V, S, E, J>, lifecycle, run, owned => ended(P, A, G, D, C, V, S, E, J, owned))

def listenerRun(active: Maybe<&2, ActiveRun>) -> Result<&2, &2, String, ActiveRun>:
  match active:
    case None{}: Fail{"Agent listener invoked outside active run"}
    case Some{run}: Done{run}
def eventState(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>, active: Maybe<&2, ActiveRun>, event: T.AgentEvent<P, A, G, D, C, Partial, Execution>) -> OwnedState<P, A, G, D, C, V, S, E, J> & Result<&2, &2, String, ActiveRun>:
  match owned:
    case OwnedState{stateLocal, queues}: (OwnedState{processEvent(P, A, G, D, C, V, S, E, J, Partial, Execution, stateLocal, event), queues}, listenerRun(active))
# Reduction happens before listener dispatch, including the source's error for
# an event outside a run. The returned handle carries the active signalLocal.
def recordEvent(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, event: T.AgentEvent<P, A, G, D, C, Partial, Execution>) -> IO(Result<&2, &2, String, ActiveRun>):
  match runtime:
    case OwnedRuntime{lifecycle}: modify(OwnedState<P, A, G, D, C, V, S, E, J>, Result<&2, &2, String, ActiveRun>, lifecycle, owned => active => eventState(P, A, G, D, C, V, S, E, J, Partial, Execution, owned, active, event))
def abortRuntime(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>) -> IO(Unit):
  match runtime:
    case OwnedRuntime{lifecycle}: abortLife(OwnedState<P, A, G, D, C, V, S, E, J>, lifecycle)
def waitForIdleRuntime(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>) -> IO(Unit):
  match runtime:
    case OwnedRuntime{lifecycle}: waitForIdleLife(OwnedState<P, A, G, D, C, V, S, E, J>, lifecycle)
def disposeRuntime(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>) -> IO(OwnedState<P, A, G, D, C, V, S, E, J>):
  match runtime:
    case OwnedRuntime{lifecycle}: disposeLife(OwnedState<P, A, G, D, C, V, S, E, J>, lifecycle)

def changedState(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, M, V, S, E, J>, change: StateChange<P, A, G, D, M, V, S, E, J>) -> OwnedState<P, A, G, D, M, V, S, E, J> & Unit:
  match owned:
    case OwnedState{stateLocal, queues}: (OwnedState{applyChange(P, A, G, D, M, V, S, E, J, stateLocal, change), queues}, Unit{})
def updateStateRuntime(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, M, V, S, E, J>, change: StateChange<P, A, G, D, M, V, S, E, J>) -> IO(Unit):
  match runtime:
    case OwnedRuntime{lifecycle}: modify(OwnedState<P, A, G, D, M, V, S, E, J>, Unit, lifecycle, owned => active => changedState(P, A, G, D, M, V, S, E, J, owned, change))


# Ordered subscriptions with explicit registration positions. User callbacks
# run outside the lock. Each dispatch observes removals/additions before it
# selects the next listener, preserving the source's awaited live dispatch.
type Input<-Event: Data, -Signal: Data> is Data:
  Input{event: Event, signalLocal: Signal}
def Handler(-Event: Data, -Signal: Data, -Error: Data) -> Data:
  C.Callback<Input<Event, Signal>, Loop.Emission<Error>>
type Entry<-Event: Data, -Signal: Data, -Error: Data> is Data:
  Entry{position: N.BigNat, callback: Handler(Event, Signal, Error)}
type State<-Event: Data, -Signal: Data, -Error: Data> is Data:
  State{next: N.BigNat, entries: List<&2, Entry<Event, Signal, Error>>}
type Listeners<-Event: Data, -Signal: Data, -Error: Data> is Data:
  Listeners{stateLocal: R.Ref<State<Event, Signal, Error>>}
type Subscription<-Event: Data, -Signal: Data, -Error: Data> is Data:
  Subscription{listeners: Listeners<Event, Signal, Error>, callback: Handler(Event, Signal, Error)}

def newListeners(-Event: Data, -Signal: Data, -Error: Data) -> IO(Listeners<Event, Signal, Error>):
  do IO<Listeners<Event, Signal, Error>>:
    stateLocal : R.Ref<State<Event, Signal, Error>> <- R.new(State<Event, Signal, Error>, State{N.zero(), Nil{}})
    return Listeners{stateLocal}
def contains(-Event: Data, -Signal: Data, -Error: Data, entries: List<&2, Entry<Event, Signal, Error>>, +callback: Handler(Event, Signal, Error)) -> Bool:
  match entries:
    case Nil{}: False{}
    case Entry{_, other} <> rest: C.same(Input<Event, Signal>, Loop.Emission<Error>, callback, other) || contains(Event, Signal, Error, rest, callback)
def added(-Event: Data, -Signal: Data, -Error: Data, +next: N.BigNat, entries: List<&2, Entry<Event, Signal, Error>>, callback: Handler(Event, Signal, Error), exists: Bool) -> State<Event, Signal, Error>:
  match exists:
    case True{}: State{next, entries}
    case False{}: State{N.add(next, N.one()), List.append(&2, Entry<Event, Signal, Error>, entries, Entry{next, callback} <> Nil{})}
def addState(-Event: Data, -Signal: Data, -Error: Data, stateLocal: State<Event, Signal, Error>, +callback: Handler(Event, Signal, Error)) -> State<Event, Signal, Error> & Unit:
  match stateLocal:
    case State{next, +entries}: (added(Event, Signal, Error, next, entries, callback, contains(Event, Signal, Error, entries, callback)), Unit{})
def subscribeListeners(-Event: Data, -Signal: Data, -Error: Data, +listeners: Listeners<Event, Signal, Error>, +callback: Handler(Event, Signal, Error)) -> IO(Subscription<Event, Signal, Error>):
  match listeners:
    case Listeners{+stateLocal}:
      do IO<Subscription<Event, Signal, Error>>:
        R.modify(State<Event, Signal, Error>, Unit, stateLocal, current => addState(Event, Signal, Error, current, callback))
        return Subscription{Listeners{stateLocal}, callback}
def remove(-Event: Data, -Signal: Data, -Error: Data, entries: List<&2, Entry<Event, Signal, Error>>, +callback: Handler(Event, Signal, Error)) -> List<&2, Entry<Event, Signal, Error>>:
  match entries:
    case Nil{}: Nil{}
    case Entry{position, +other} <> +rest:
      Bool.pick(List<&2, Entry<Event, Signal, Error>>, C.same(Input<Event, Signal>, Loop.Emission<Error>, callback, other), rest, Entry{position, other} <> remove(Event, Signal, Error, rest, callback))
def removeState(-Event: Data, -Signal: Data, -Error: Data, stateLocal: State<Event, Signal, Error>, callback: Handler(Event, Signal, Error)) -> State<Event, Signal, Error> & Unit:
  match stateLocal:
    case State{next, entries}: (State{next, remove(Event, Signal, Error, entries, callback)}, Unit{})
def unsubscribe(-Event: Data, -Signal: Data, -Error: Data, subscription: Subscription<Event, Signal, Error>) -> IO(Unit):
  match subscription:
    case Subscription{Listeners{stateLocal}, callback}: R.modify(State<Event, Signal, Error>, Unit, stateLocal, current => removeState(Event, Signal, Error, current, callback))
def less(order: Cmp) -> Bool:
  match order:
    case LT{}: True{}
    case _: False{}
def eligible(position: N.BigNat, cursor: Maybe<&2, N.BigNat>) -> Bool:
  match cursor:
    case None{}: True{}
    case Some{previous}: less(N.compare(previous, position))
def nextEntry(-Event: Data, -Signal: Data, -Error: Data, entries: List<&2, Entry<Event, Signal, Error>>, +cursor: Maybe<&2, N.BigNat>) -> Maybe<&2, Entry<Event, Signal, Error>>:
  match entries:
    case Nil{}: None{}
    case Entry{+position, callback} <> rest:
      Bool.pick(Maybe<&2, Entry<Event, Signal, Error>>, eligible(position, cursor), Some{Entry{position, callback}}, nextEntry(Event, Signal, Error, rest, cursor))
def selectedListeners(-Event: Data, -Signal: Data, -Error: Data, stateLocal: State<Event, Signal, Error>, cursor: Maybe<&2, N.BigNat>) -> Maybe<&2, Entry<Event, Signal, Error>>:
  match stateLocal:
    case State{_, entries}: nextEntry(Event, Signal, Error, entries, cursor)
# Phase/result arguments avoid mutual recursion: each callback settles before
# the next selection. Failure immediately stops this event's delivery.
@unsafe def dispatch(-Event: Data, -Signal: Data, -Error: Data, +listeners: Listeners<Event, Signal, Error>, +input: Input<Event, Signal>, cursor: Maybe<&2, N.BigNat>, result: Result<&2, &2, Error, Unit>, next: Maybe<&2, Entry<Event, Signal, Error>>, select: Bool) -> IO(Result<&2, &2, Error, Unit>):
  match listeners result next select:
    case Listeners{_} Fail{error} _ _: IO.pure(Result<&2, &2, Error, Unit>, Fail{error})
    case Listeners{+stateLocal} Done{_} _ True{}:
      do IO<Result<&2, &2, Error, Unit>>:
        current : State<Event, Signal, Error> <- R.read(State<Event, Signal, Error>, stateLocal)
        dispatch(Event, Signal, Error, Listeners{stateLocal}, input, None{}, Done{Unit{}}, selectedListeners(Event, Signal, Error, current, cursor), False{})
    case Listeners{stateLocal} Done{_} Some{Entry{position, callback}} False{}:
      do IO<Result<&2, &2, Error, Unit>>:
        delivery : Loop.Emission<Error> <- C.call(Input<Event, Signal>, Loop.Emission<Error>, callback, input)
        outcome : Result<&2, &2, Error, Unit> <- Loop.wait(Error, delivery)
        dispatch(Event, Signal, Error, Listeners{stateLocal}, input, Some{position}, outcome, None{}, True{})
    case Listeners{_} Done{_} None{} False{}: IO.pure(Result<&2, &2, Error, Unit>, Done{Unit{}})
# The first callback starts inline, before returning ownership of pending
# delivery. Subsequent callbacks remain live-selected after each completion.
def resume(-Event: Data, -Signal: Data, -Error: Data, listeners: Listeners<Event, Signal, Error>, input: Input<Event, Signal>, position: N.BigNat, delivery: Loop.Emission<Error>) -> IO(Result<&2, &2, Error, Unit>):
  do IO<Result<&2, &2, Error, Unit>>:
    outcome : Result<&2, &2, Error, Unit> <- Loop.wait(Error, delivery)
    dispatch(Event, Signal, Error, listeners, input, Some{position}, outcome, None{}, True{})
def startSelected(-Event: Data, -Signal: Data, -Error: Data, listeners: Listeners<Event, Signal, Error>, +input: Input<Event, Signal>, selectedListeners: Maybe<&2, Entry<Event, Signal, Error>>) -> IO(Loop.Emission<Error>):
  match selectedListeners:
    case None{}: IO.pure(Loop.Emission<Error>, Loop.EmissionReady{Done{Unit{}}})
    case Some{Entry{position, callback}}:
      do IO<Loop.Emission<Error>>:
        delivery : Loop.Emission<Error> <- C.call(Input<Event, Signal>, Loop.Emission<Error>, callback, input)
        Loop.startEmission(Error, resume(Event, Signal, Error, listeners, input, position, delivery))
def start(-Event: Data, -Signal: Data, -Error: Data, listeners: Listeners<Event, Signal, Error>, event: Event, signalLocal: Signal) -> IO(Loop.Emission<Error>):
  match listeners:
    case Listeners{+stateLocal}:
      do IO<Loop.Emission<Error>>:
        current : State<Event, Signal, Error> <- R.read(State<Event, Signal, Error>, stateLocal)
        startSelected(Event, Signal, Error, Listeners{stateLocal}, Input{event, signalLocal}, selectedListeners(Event, Signal, Error, current, None{}))
def emitListeners(-Event: Data, -Signal: Data, -Error: Data, listeners: Listeners<Event, Signal, Error>, event: Event, signalLocal: Signal) -> IO(Result<&2, &2, Error, Unit>):
  do IO<Result<&2, &2, Error, Unit>>:
    delivery : Loop.Emission<Error> <- start(Event, Signal, Error, listeners, event, signalLocal)
    Loop.wait(Error, delivery)
# Callbacks are borrowed. Drain in-flight dispatches before disposing the
# registry, then retire callback handles according to their own ownership.
def disposeListeners(-Event: Data, -Signal: Data, -Error: Data, listeners: Listeners<Event, Signal, Error>) -> IO(Unit):
  match listeners:
    case Listeners{stateLocal}:
      do IO<Unit>:
        previous : State<Event, Signal, Error> <- R.dispose(State<Event, Signal, Error>, stateLocal)
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
def startDispatch(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -Partial: Data, -Execution: Data, -Failure: Data, listeners: Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, event: T.AgentEvent<P, A, G, D, C, Partial, Execution>, active: Result<&2, &2, String, ActiveRun>) -> IO(Loop.Emission<DeliveryError<Failure>>):
  match active:
    case Fail{message}: IO.pure(Loop.Emission<DeliveryError<Failure>>, Loop.EmissionReady{Fail{OutsideRun{message}}})
    case Done{run}:
      do IO<Loop.Emission<DeliveryError<Failure>>>:
        delivery : Loop.Emission<Failure> <- start(T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure, listeners, event, signalLife(run))
        Loop.startEmission(DeliveryError<Failure>, completedEvents(Failure, delivery))
# State reduction and the first listener's immediate effects happen before
# returning. The caller owns and must await the remaining delivery.
def startEvents(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, -Failure: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, listeners: Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, +event: T.AgentEvent<P, A, G, D, C, Partial, Execution>) -> IO(Loop.Emission<DeliveryError<Failure>>):
  do IO<Loop.Emission<DeliveryError<Failure>>>:
    active : Result<&2, &2, String, ActiveRun> <- recordEvent(P, A, G, D, C, V, S, E, J, Partial, Execution, runtime, event)
    startDispatch(P, A, G, D, C, Partial, Execution, Failure, listeners, event, active)

# Awaited delivery is the same start operation followed by its completion.
def processEvents(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, -Failure: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, listeners: Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, +event: T.AgentEvent<P, A, G, D, C, Partial, Execution>) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
    delivery : Loop.Emission<DeliveryError<Failure>> <- startEvents(P, A, G, D, C, V, S, E, J, Partial, Execution, Failure, runtime, listeners, event)
    Loop.wait(DeliveryError<Failure>, delivery)


def emptyUsage() -> Ai.Usage:
  +zero = F.fromU32(0)
  Ai.Usage{zero, zero, zero, zero, None{}, None{}, zero, Ai.UsageCost{zero, zero, zero, zero, zero}}
def messageFailure(-A: Data, -G: Data, -J: Data, model: Ai.Model<J>, aborted: Bool, error: String, timestamp: F.F64) -> Ai.AssistantMessage<A, G>:
  match model:
    case Ai.Model{id, _, api, provider, _, _, _, _, _, _, _, _, _, _}:
      Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{"", None{}}} <> Nil{}, Api.name(api), provider, id, None{}, None{}, None{}, None{}, emptyUsage(), Bool.pick(Ai.StopReason, aborted, Ai.Aborted{}, Ai.Error{}), None{}, Some{error}, None{}, None{}, timestamp}
def fromState(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, stateLocal: T.AgentState<P, A, G, D, C, V, S, E, J>, aborted: Bool, error: String, timestamp: F.F64) -> T.AgentMessage<P, A, G, D, C>:
  match stateLocal:
    case T.AgentState{model, _, _, _, _, _, _, _}: T.LlmMessage{Ai.Assistant{messageFailure(A, G, J, model, aborted, error, timestamp)}}
def events(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -Partial: Data, -Execution: Data, +messageFailure: T.AgentMessage<P, A, G, D, C>) -> List<&2, T.AgentEvent<P, A, G, D, C, Partial, Execution>>:
  T.MessageStart{messageFailure} <> T.MessageEnd{messageFailure} <> T.TurnEnd{messageFailure, Nil{}} <> T.AgentEnd{messageFailure <> Nil{}} <> Nil{}
def deliver(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, -Failure: Data, +runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, +listeners: Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, messages: List<&2, T.AgentEvent<P, A, G, D, C, Partial, Execution>>, result: Result<&2, &2, DeliveryError<Failure>, Unit>) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  match messages result:
    case _ Fail{error}: IO.pure(Result<&2, &2, DeliveryError<Failure>, Unit>, Fail{error})
    case Nil{} Done{_}: IO.pure(Result<&2, &2, DeliveryError<Failure>, Unit>, Done{Unit{}})
    case event <> rest Done{_}:
      do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
        outcome : Result<&2, &2, DeliveryError<Failure>, Unit> <- processEvents(P, A, G, D, C, V, S, E, J, Partial, Execution, Failure, runtime, listeners, event)
        deliver(P, A, G, D, C, V, S, E, J, Partial, Execution, Failure, runtime, listeners, rest, outcome)
# Explicit timestamp supports deterministic tests; production uses Date.now.
def handleRunFailureAt(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, -Failure: Data, +runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, listeners: Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, error: String, aborted: Bool, timestamp: F.F64) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
    stateLocal : T.AgentState<P, A, G, D, C, V, S, E, J> <- readRuntime(P, A, G, D, C, V, S, E, J, runtime)
    deliver(P, A, G, D, C, V, S, E, J, Partial, Execution, Failure, runtime, listeners, events(P, A, G, D, C, Partial, Execution, fromState(P, A, G, D, C, V, S, E, J, stateLocal, aborted, error, timestamp)), Done{Unit{}})
def handleRunFailure(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, -Failure: Data, +runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, listeners: Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, error: String, aborted: Bool) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
    stateLocal : T.AgentState<P, A, G, D, C, V, S, E, J> <- readRuntime(P, A, G, D, C, V, S, E, J, runtime)
    timestamp : F.F64 <- Date.now()
    deliver(P, A, G, D, C, V, S, E, J, Partial, Execution, Failure, runtime, listeners, events(P, A, G, D, C, Partial, Execution, fromState(P, A, G, D, C, V, S, E, J, stateLocal, aborted, error, timestamp)), Done{Unit{}})
def recover(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, -Failure: Data, runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, listeners: Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, run: ActiveRun, result: Result<&2, &2, Failure, Unit>, renderError: Failure -> String) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  match result:
    case Done{_}: IO.pure(Result<&2, &2, DeliveryError<Failure>, Unit>, Done{Unit{}})
    case Fail{error}:
      do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
        aborted : Bool <- Abort.aborted(Unit, signalLife(run))
        handleRunFailure(P, A, G, D, C, V, S, E, J, Partial, Execution, Failure, runtime, listeners, renderError(error), aborted)
# The prepared run is already claimed. Recovery is awaited as part of that
# run; even a recovery-listener failure reaches the final stateLocal/idle cleanup.
def runClaimedFailure(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, -Failure: Data, -Value: Data, +runtime: OwnedRuntime<P, A, G, D, C, V, S, E, J>, listeners: Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, claimed: Claimed<Value>, execute: Claimed<Value> -> IO(Result<&2, &2, Failure, Unit>), renderError: Failure -> String) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  match claimed:
    case Claimed{+run, value}:
      do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
        result : Result<&2, &2, Failure, Unit> <- execute(Claimed{run, value})
        outcome : Result<&2, &2, DeliveryError<Failure>, Unit> <- recover(P, A, G, D, C, V, S, E, J, Partial, Execution, Failure, runtime, listeners, run, result, renderError)
        finished : Bool <- finishRunRuntime(P, A, G, D, C, V, S, E, J, runtime, run)
        return outcome


def HooksSignal() -> Data: Abort.AbortSignal<Unit>
def PrepareResult(-Update: Data, -Error: Data) -> Data: Result<&2, &2, Error, Maybe<&2, Update>>
def StopHook(-Turn: Data, -Error: Data) -> Data: C.Callback<T.ToolHookInput<Turn, HooksSignal()>, Result<&2, &2, Error, Bool>>
def LegacyHook(-Update: Data, -Error: Data) -> Data: C.Callback<Maybe<&2, HooksSignal()>, PrepareResult(Update, Error)>
def ContextHook(-Turn: Data, -Update: Data, -Error: Data) -> Data: C.Callback<T.ToolHookInput<Turn, HooksSignal()>, PrepareResult(Update, Error)>

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
    return Maybe.map(&2, ActiveRun, HooksSignal(), run => signalLife(run), active)
def stopBody(-State: Data, -Turn: Data, -Error: Data, capture: StopCapture<State, Turn, Error>, contextLocal: Turn) -> IO(Result<&2, &2, Error, Bool>):
  match capture:
    case StopCapture{lifecycle, hook}:
      do IO<Result<&2, &2, Error, Bool>>:
        active : Maybe<&2, HooksSignal()> <- signalHooks(State, lifecycle)
        C.call(T.ToolHookInput<Turn, HooksSignal()>, Result<&2, &2, Error, Bool>, hook, T.ToolHookInput{contextLocal, active})
def prepareSelected(-State: Data, -Turn: Data, -Update: Data, -Error: Data, lifecycle: Lifecycle<State>, hooks: Hooks<Turn, Update, Error>, contextLocal: Turn) -> IO(PrepareResult(Update, Error)):
  match hooks:
    case Hooks{_, _, Some{hook}}:
      do IO<PrepareResult(Update, Error)>:
        active : Maybe<&2, HooksSignal()> <- signalHooks(State, lifecycle)
        C.call(T.ToolHookInput<Turn, HooksSignal()>, PrepareResult(Update, Error), hook, T.ToolHookInput{contextLocal, active})
    case Hooks{_, Some{hook}, None{}}:
      do IO<PrepareResult(Update, Error)>:
        active : Maybe<&2, HooksSignal()> <- signalHooks(State, lifecycle)
        C.call(Maybe<&2, HooksSignal()>, PrepareResult(Update, Error), hook, active)
    case Hooks{_, None{}, None{}}: IO.pure(PrepareResult(Update, Error), Done{None{}})
def prepareBody(-State: Data, -Turn: Data, -Update: Data, -Error: Data, capture: PrepareCapture<State, Turn, Update, Error>, contextLocal: Turn) -> IO(PrepareResult(Update, Error)):
  match capture:
    case PrepareCapture{lifecycle, hooks}:
      do IO<PrepareResult(Update, Error)>:
        selected : Hooks<Turn, Update, Error> <- R.read(Hooks<Turn, Update, Error>, hooks)
        prepareSelected(State, Turn, Update, Error, lifecycle, selected, contextLocal)
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
type BindingSteering<-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data> is Data:
  BindingSteering{runtime: OwnedRuntime<P, A, G, D, M, V, S, E, J>, skip: R.Ref<Bool>}
type BindingPollers<-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data> is Data:
  BindingPollers{steering: C.Callback<Unit, Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>>, followUpLocal: C.Callback<Unit, Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>>, skip: R.Ref<Bool>}
def queue(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, M, V, S, E, J>, kind: QueueKind) -> IO(Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>):
  do IO<Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>>:
    messages : List<&2, T.AgentMessage<P, A, G, D, M>> <- drainRuntime(P, A, G, D, M, V, S, E, J, runtime, kind)
    return Done{messages}
def steeringReady(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, M, V, S, E, J>, skip: Bool) -> IO(Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>):
  match skip:
    case True{}: IO.pure(Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>, Done{Nil{}})
    case False{}: queue(P, A, G, D, M, V, S, E, J, runtime, QueuesSteering{})
def steeringBody(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, capture: BindingSteering<P, A, G, D, M, V, S, E, J>, unused: Unit) -> IO(Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>):
  match capture:
    case BindingSteering{runtime, skip}:
      do IO<Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>>:
        previous : Bool <- R.swap(Bool, skip, False{})
        steeringReady(P, A, G, D, M, V, S, E, J, runtime, previous)
def followUpBody(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: OwnedRuntime<P, A, G, D, M, V, S, E, J>, unused: Unit) -> IO(Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>): queue(P, A, G, D, M, V, S, E, J, runtime, FollowUp{})
def newBinding(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~S: Data, ~E: Data, ~J: Data, +runtime: OwnedRuntime<P, A, G, D, M, V, S, E, J>, skipInitialSteeringPoll: Bool) -> IO(BindingPollers<P, A, G, D, M, V, S, E, J>):
  do IO<BindingPollers<P, A, G, D, M, V, S, E, J>>:
    +skip : R.Ref<Bool> <- R.new(Bool, skipInitialSteeringPoll)
    steering : C.Callback<Unit, Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>> <- C.create(~BindingSteering<P, A, G, D, M, V, S, E, J>, ~Unit, ~Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>, ~(steeringBody(P, A, G, D, M, V, S, E, J)), BindingSteering{runtime, skip})
    followUpLocal : C.Callback<Unit, Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>> <- C.create(~OwnedRuntime<P, A, G, D, M, V, S, E, J>, ~Unit, ~Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>, ~(followUpBody(P, A, G, D, M, V, S, E, J)), runtime)
    return BindingPollers{steering, followUpLocal, skip}
def thinkingReasoning(thinking: T.ThinkingLevel()) -> Maybe<&2, Ai.ThinkingLevel>:
  match thinking:
    case Ai.Off{}: None{}
    case Ai.Thinking{level}: Some{level}
def context(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, stateLocal: T.AgentState<P, A, G, D, M, V, S, E, J>) -> T.AgentContext<P, A, G, D, M, V, S, E>:
  match stateLocal:
    case T.AgentState{_, _, tools, messages, _, _, _, _}: T.AgentContext{messages, Some{tools}}
# Keep the configured options/hooks while taking model/thinking and transcript
# from one immutable Agent snapshot. The public options adapter builds the base.
def bind(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, stateLocal: T.AgentState<P, A, G, D, M, V, S, E, J>, base: T.AgentLoopConfig<P, A, G, D, M, V, S, E, J, Telemetry, Fetch>, readers: BindingPollers<P, A, G, D, M, V, S, E, J>) -> T.AgentLoopConfig<P, A, G, D, M, V, S, E, J, Telemetry, Fetch>:
  match stateLocal base readers:
    case T.AgentState{currentModel, thinking, _, _, _, _, _, _} T.AgentLoopConfig{signalLocal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall} BindingPollers{steering, followUpLocal, _}:
      T.AgentLoopConfig{signalLocal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, thinkingReasoning(thinking), deferred, thinkingBudgets, currentModel, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, Some{steering}, Some{followUpLocal}, toolExecution, beforeToolCall, afterToolCall}
type Snapshot<-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Snapshot{contextLocal: T.AgentContext<P, A, G, D, M, V, S, E>, config: T.AgentLoopConfig<P, A, G, D, M, V, S, E, J, Telemetry, Fetch>}
def snapshotBinding(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, runtime: OwnedRuntime<P, A, G, D, M, V, S, E, J>, base: T.AgentLoopConfig<P, A, G, D, M, V, S, E, J, Telemetry, Fetch>, readers: BindingPollers<P, A, G, D, M, V, S, E, J>) -> IO(Snapshot<P, A, G, D, M, V, S, E, J, Telemetry, Fetch>):
  do IO<Snapshot<P, A, G, D, M, V, S, E, J, Telemetry, Fetch>>:
    +stateLocal : T.AgentState<P, A, G, D, M, V, S, E, J> <- readRuntime(P, A, G, D, M, V, S, E, J, runtime)
    return Snapshot{context(P, A, G, D, M, V, S, E, J, stateLocal), bind(P, A, G, D, M, V, S, E, J, Telemetry, Fetch, stateLocal, base, readers)}
def disposeBinding(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, readers: BindingPollers<P, A, G, D, M, V, S, E, J>) -> IO(Unit):
  match readers:
    case BindingPollers{steering, followUpLocal, skip}:
      do IO<Unit>:
        C.dispose(Unit, Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>, steering)
        C.dispose(Unit, Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>, followUpLocal)
        ignored : Bool <- R.dispose(Bool, skip)
        return Unit{}

# The run owns these wrappers; public hooks and option storage stay borrowed.
def applyHooks(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, base: T.AgentLoopConfig<P, A, G, D, M, V, S, E, J, Telemetry, Fetch>, adapters: Adapters<T.ShouldStopAfterTurnContext<P, A, G, D, M, V, S, E>, T.AgentLoopTurnUpdate<P, A, G, D, M, V, S, E, J>, E>) -> T.AgentLoopConfig<P, A, G, D, M, V, S, E, J, Telemetry, Fetch>:
  match base adapters:
    case T.AgentLoopConfig{signalLocal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall} Adapters{stop, prepare}: T.AgentLoopConfig{signalLocal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, stop, prepare, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}


def RunSignal() -> Data: Abort.AbortSignal<Unit>
def RunMessage(-A: Data, -G: Data, -D: Data, -M: Data) -> Data: T.AgentMessage<Schema.Value, A, G, D, M>
def RunEvent(-A: Data, -G: Data, -D: Data, -M: Data) -> Data: T.AgentEvent<Schema.Value, A, G, D, M, T.AgentToolResult<D>, T.AgentToolResult<D>>
def RunRuntime(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data) -> Data: OwnedRuntime<Schema.Value, A, G, D, M, V, RunSignal(), E, J>
def Registry(-A: Data, -G: Data, -D: Data, -M: Data, -E: Data) -> Data: Listeners<RunEvent(A, G, D, M), RunSignal(), E>
def Config(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data) -> Data: T.AgentLoopConfig<Schema.Value, A, G, D, M, V, RunSignal(), E, J, Telemetry, Fetch>
def RunPollers(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data) -> Data: BindingPollers<Schema.Value, A, G, D, M, V, RunSignal(), E, J>
def Outcome(-A: Data, -G: Data, -D: Data, -M: Data, -E: Data) -> Data: Result<&2, &2, E, List<&2, RunMessage(A, G, D, M)>>
type Options<-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Options{config: Config(A, G, D, M, V, E, J, Telemetry, Fetch), provider: Provider.Selection<Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E>, validate: C.Callback<Loop.ToolValidationInput<Schema.Value, A, V>, Result<&2, &2, E, V>>, emptyDetails: D}
# A completed run can still own tool-held callback aliases or sibling work.
# Retain these resources until aliases retire; dispose drains batches first.
type Resources<-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data> is Data:
  Resources{pollers: RunPollers(A, G, D, M, V, E, J), emit: C.Callback<RunEvent(A, G, D, M), Loop.Emission<E>>, sink: C.Callback<RunEvent(A, G, D, M), Result<&2, &2, E, Unit>>, isAborted: C.Callback<Maybe<&2, RunSignal()>, Bool>, updates: Loop.Owners(D, E), batches: Loop.Batches(A, G, D, M, V, RunSignal(), E)}
type Completed<-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data> is Data:
  Completed{outcome: Result<&2, &2, DeliveryError<E>, Unit>, resources: Resources<A, G, D, M, V, E, J>}
type Capture<-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data> is Data:
  Capture{runtime: RunRuntime(A, G, D, M, V, E, J), listeners: Registry(A, G, D, M, E)}

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
def emitBody(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, fromString: String -> E, capture: Capture<A, G, D, M, V, E, J>, event: RunEvent(A, G, D, M)) -> IO(Loop.Emission<E>):
  match capture:
    case Capture{runtime, listeners}:
      do IO<Loop.Emission<E>>:
        delivery : Loop.Emission<DeliveryError<E>> <- startEvents(Schema.Value, A, G, D, M, V, RunSignal(), E, J, T.AgentToolResult<D>, T.AgentToolResult<D>, E, runtime, listeners, event)
        Loop.startEmission(E, finishEmission(E, fromString, delivery))
def isAborted(unused: Unit, signalLocal: Maybe<&2, RunSignal()>) -> IO(Bool):
  match signalLocal:
    case None{}: IO.pure(Bool, False{})
    case Some{value}: Abort.aborted(Unit, value)
def skipInitial(-A: Data, -G: Data, -D: Data, -M: Data, plan: Plan<RunMessage(A, G, D, M)>) -> Bool:
  match plan:
    case Prompt{_, skip}: skip
    case Continue{}: False{}
def allocate(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~fromString: String -> E, +runtime: RunRuntime(A, G, D, M, V, E, J), listeners: Registry(A, G, D, M, E), skip: Bool) -> IO(Resources<A, G, D, M, V, E, J>):
  do IO<Resources<A, G, D, M, V, E, J>>:
    pollers : RunPollers(A, G, D, M, V, E, J) <- newBinding(~Schema.Value, ~A, ~G, ~D, ~M, ~V, ~RunSignal(), ~E, ~J, runtime, skip)
    +emit : C.Callback<RunEvent(A, G, D, M), Loop.Emission<E>> <- C.create(~Capture<A, G, D, M, V, E, J>, ~RunEvent(A, G, D, M), ~Loop.Emission<E>, ~(emitBody(A, G, D, M, V, E, J, fromString)), Capture{runtime, listeners})
    sink : C.Callback<RunEvent(A, G, D, M), Result<&2, &2, E, Unit>> <- Loop.createAwaitedEventSink(~Schema.Value, ~A, ~G, ~D, ~M, ~T.AgentToolResult<D>, ~T.AgentToolResult<D>, ~E, emit)
    cancelled : C.Callback<Maybe<&2, RunSignal()>, Bool> <- C.create(~Unit, ~Maybe<&2, RunSignal()>, ~Bool, ~isAborted, Unit{})
    updates : Loop.Owners(D, E) <- Loop.newOwners(D, E)
    batches : Loop.Batches(A, G, D, M, V, RunSignal(), E) <- Loop.newBatches(A, G, D, M, V, RunSignal(), E)
    return Resources{pollers, emit, sink, cancelled, updates, batches}
def executePlan(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, plan: Plan<RunMessage(A, G, D, M)>, snapshot: Snapshot<Schema.Value, A, G, D, M, V, RunSignal(), E, J, Telemetry, Fetch>, capture: Loop.EntryCapture<A, G, D, M, V, RunSignal(), E, J, Telemetry, Fetch>) -> IO(Outcome(A, G, D, M, E)):
  match plan snapshot:
    case Prompt{messages, _} Snapshot{contextLocal, config}: Loop.runAgentLoop(~A, ~G, ~D, ~M, ~V, ~RunSignal(), ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~(missing(E, fromString)), messages, contextLocal, config, capture)
    case Continue{} Snapshot{contextLocal, config}: Loop.runAgentLoopContinue(~A, ~G, ~D, ~M, ~V, ~RunSignal(), ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~(missing(E, fromString)), ~(invalidEntry(E, fromString)), contextLocal, config, capture)
def execute(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, runtime: RunRuntime(A, G, D, M, V, E, J), options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>, resources: Resources<A, G, D, M, V, E, J>, claimed: Claimed<Plan<RunMessage(A, G, D, M)>>) -> IO(Outcome(A, G, D, M, E)):
  match options resources claimed:
    case Options{base, provider, validate, emptyDetails} Resources{pollers, emit, sink, cancelled, updates, batches} Claimed{run, plan}:
      do IO<Outcome(A, G, D, M, E)>:
        snapshot : Snapshot<Schema.Value, A, G, D, M, V, RunSignal(), E, J, Telemetry, Fetch> <- snapshotBinding(Schema.Value, A, G, D, M, V, RunSignal(), E, J, Telemetry, Fetch, runtime, base, pollers)
        executePlan(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~fromString, ~declarationError, plan, snapshot, Loop.EntryCapture{Loop.Services{Some{signalLife(run)}, validate, cancelled, emit, sink, updates, batches, emptyDetails}, provider})
def finishedLoop(-A: Data, -G: Data, -D: Data, -M: Data, -E: Data, outcome: Outcome(A, G, D, M, E)) -> Result<&2, &2, E, Unit>:
  match outcome:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{error}
# Run claims and queue planning happen atomically in agent-runtime. This bridge
# executes that plan through the real loop, recovers, then always marks idle.
# The caller retains Completed.resources until explicit disposal is safe.
def runClaimedRun(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, +runtime: RunRuntime(A, G, D, M, V, E, J), +listeners: Registry(A, G, D, M, E), options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>, claimed: Claimed<Plan<RunMessage(A, G, D, M)>>) -> IO(Completed<A, G, D, M, V, E, J>):
  match claimed:
    case Claimed{+run, +plan}:
      do IO<Completed<A, G, D, M, V, E, J>>:
        +resources : Resources<A, G, D, M, V, E, J> <- allocate(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~fromString, runtime, listeners, skipInitial(A, G, D, M, plan))
        result : Outcome(A, G, D, M, E) <- execute(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~fromString, ~declarationError, runtime, options, resources, Claimed{run, plan})
        outcome : Result<&2, &2, DeliveryError<E>, Unit> <- recover(Schema.Value, A, G, D, M, V, RunSignal(), E, J, T.AgentToolResult<D>, T.AgentToolResult<D>, E, runtime, listeners, run, finishedLoop(A, G, D, M, E, result), renderError)
        finished : Bool <- finishRunRuntime(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime, run)
        return Completed{outcome, resources}
def runDispose(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, resources: Resources<A, G, D, M, V, E, J>) -> IO(Unit):
  match resources:
    case Resources{pollers, emit, sink, cancelled, updates, batches}:
      do IO<Unit>:
        Loop.disposeBatches(A, G, D, M, V, RunSignal(), E, batches)
        Loop.disposeOwners(D, E, updates)
        C.dispose(RunEvent(A, G, D, M), Result<&2, &2, E, Unit>, sink)
        C.dispose(RunEvent(A, G, D, M), Loop.Emission<E>, emit)
        C.dispose(Maybe<&2, RunSignal()>, Bool, cancelled)
        disposeBinding(Schema.Value, A, G, D, M, V, RunSignal(), E, J, pollers)


def Converter(-A: Data, -G: Data, -D: Data, -M: Data, -E: Data) -> Data: C.Callback<T.AgentMessageArray(Schema.Value, A, G, D, M), Result<&2, &2, E, List<&2, Ai.Message<Schema.Value, A, G, D>>>>
def Turn(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data) -> Data: T.ShouldStopAfterTurnContext<Schema.Value, A, G, D, M, V, RunSignal(), E>
def Update(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data) -> Data: T.AgentLoopTurnUpdate<Schema.Value, A, G, D, M, V, RunSignal(), E, J>
def TurnHooks(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data) -> Data: Hooks<Turn(A, G, D, M, V, E), Update(A, G, D, M, V, E, J), E>
# streamFn is optional only for the source's legacy default-provider fallback.
type AgentOptions<-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data> is Data:
  AgentOptions{initialState: Maybe<&2, AgentInitialState<Schema.Value, A, G, D, M, V, RunSignal(), E, J>>, convertToLlm: Maybe<&2, Converter(A, G, D, M, E)>, transformContext: Maybe<&2, C.Callback<T.TransformContextInput<T.AgentMessageArray(Schema.Value, A, G, D, M), RunSignal()>, Result<&2, &2, E, T.AgentMessageArray(Schema.Value, A, G, D, M)>>>, streamFn: Maybe<&2, T.StreamFn(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)>, getApiKey: Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>, onPayload: Maybe<&2, Ai.PayloadCallback(J, Ai.Model<J>, E)>, onResponse: Maybe<&2, Ai.ResponseCallback(Ai.Model<J>, E)>, beforeToolCall: Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, T.BeforeToolCallUpdate<V, T.AgentContext<Schema.Value, A, G, D, M, V, RunSignal(), E>>>>>, afterToolCall: Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>, shouldStopAfterTurn: Maybe<&2, StopHook(Turn(A, G, D, M, V, E), E)>, prepareNextTurn: Maybe<&2, LegacyHook(Update(A, G, D, M, V, E, J), E)>, prepareNextTurnWithContext: Maybe<&2, ContextHook(Turn(A, G, D, M, V, E), Update(A, G, D, M, V, E, J), E)>, steeringMode: Maybe<&2, T.QueueMode>, followUpMode: Maybe<&2, T.QueueMode>, sessionId: Maybe<&2, String>, thinkingBudgets: Maybe<&2, Ai.ThinkingBudgets>, transport: Maybe<&2, Ai.Transport>, maxRetryDelayMs: Maybe<&2, F.F64>, toolExecution: Maybe<&2, T.ToolExecutionMode>}
def defaultAgentOptions(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data) -> AgentOptions<A, G, D, M, V, E, J, Telemetry, Fetch>:
  AgentOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}
type Resolved<-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Resolved{initialState: AgentInitialState<Schema.Value, A, G, D, M, V, RunSignal(), E, J>, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch), streamFn: T.StreamFn(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E), hooks: TurnHooks(A, G, D, M, V, E, J), steeringMode: T.QueueMode, followUpMode: T.QueueMode, ownedConverter: Maybe<&2, Converter(A, G, D, M, E)>}
type Converted<-A: Data, -G: Data, -D: Data, -M: Data, -E: Data> is Data:
  Converted{callback: Converter(A, G, D, M, E), owned: Maybe<&2, Converter(A, G, D, M, E)>}
def convert(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, unused: Unit, messages: List<&2, RunMessage(A, G, D, M)>) -> IO(Result<&2, &2, E, List<&2, Ai.Message<Schema.Value, A, G, D>>>):
  IO.pure(Result<&2, &2, E, List<&2, Ai.Message<Schema.Value, A, G, D>>>, Done{defaultConvertToLlm(Schema.Value, A, G, D, M, V, RunSignal(), E, J, messages)})
def converterOptions(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, supplied: Maybe<&2, Converter(A, G, D, M, E)>) -> IO(Converted<A, G, D, M, E>):
  match supplied:
    case Some{callback}: IO.pure(Converted<A, G, D, M, E>, Converted{callback, None{}})
    case None{}:
      do IO<Converted<A, G, D, M, E>>:
        +callback : Converter(A, G, D, M, E) <- C.create(~Unit, ~List<&2, RunMessage(A, G, D, M)>, ~Result<&2, &2, E, List<&2, Ai.Message<Schema.Value, A, G, D>>>, ~(convert(A, G, D, M, V, E, J)), Unit{})
        return Converted{callback, Some{callback}}
def providerSelection(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, callback: Maybe<&2, T.StreamFn(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)>, fallback: Provider.Registry(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)) -> Provider.Selection<Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E>:
  match callback:
    case Some{value}: Provider.Explicit{value}
    case None{}: Provider.Fallback{fallback}
def finishOptions(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, initial: Maybe<&2, AgentInitialState<Schema.Value, A, G, D, M, V, RunSignal(), E, J>>, converted: Converted<A, G, D, M, E>, stream: T.StreamFn(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E), hooks: TurnHooks(A, G, D, M, V, E, J), steering: Maybe<&2, T.QueueMode>, follow: Maybe<&2, T.QueueMode>, transformContext: Maybe<&2, C.Callback<T.TransformContextInput<T.AgentMessageArray(Schema.Value, A, G, D, M), RunSignal()>, Result<&2, &2, E, T.AgentMessageArray(Schema.Value, A, G, D, M)>>>, getApiKey: Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>, onPayload: Maybe<&2, Ai.PayloadCallback(J, Ai.Model<J>, E)>, onResponse: Maybe<&2, Ai.ResponseCallback(Ai.Model<J>, E)>, beforeToolCall: Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, T.BeforeToolCallUpdate<V, T.AgentContext<Schema.Value, A, G, D, M, V, RunSignal(), E>>>>>, afterToolCall: Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>, sessionId: Maybe<&2, String>, thinkingBudgets: Maybe<&2, Ai.ThinkingBudgets>, transport: Maybe<&2, Ai.Transport>, maxRetryDelayMs: Maybe<&2, F.F64>, toolExecution: Maybe<&2, T.ToolExecutionMode>) -> IO(Result<&2, &2, Provider.MissingDefault, Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>>):
  match converted:
    case Converted{callback, owned}: IO.pure(Result<&2, &2, Provider.MissingDefault, Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>>, Done{Resolved{Maybe.default(&2, AgentInitialState<Schema.Value, A, G, D, M, V, RunSignal(), E, J>, initial, AgentInitialState{None{}, None{}, None{}, None{}, None{}}), T.AgentLoopConfig{None{}, None{}, None{}, None{}, None{}, onPayload, onResponse, None{}, None{}, None{}, maxRetryDelayMs, None{}, None{}, None{}, Some{Maybe.default(&2, Ai.Transport, transport, Ai.AutoTransport{})}, None{}, sessionId, None{}, None{}, None{}, None{}, None{}, thinkingBudgets, defaultModel(J), callback, transformContext, getApiKey, None{}, None{}, None{}, None{}, Some{Maybe.default(&2, T.ToolExecutionMode, toolExecution, T.Parallel{})}, beforeToolCall, afterToolCall}, stream, hooks, Maybe.default(&2, T.QueueMode, steering, T.OneAtATime{}), Maybe.default(&2, T.QueueMode, follow, T.OneAtATime{}), owned}})
def resolvedOptions(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, options: AgentOptions<A, G, D, M, V, E, J, Telemetry, Fetch>, provider: Result<&2, &2, Provider.MissingDefault, T.StreamFn(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)>) -> IO(Result<&2, &2, Provider.MissingDefault, Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>>):
  match options provider:
    case _ Fail{error}: IO.pure(Result<&2, &2, Provider.MissingDefault, Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>>, Fail{error})
    case AgentOptions{initialState, convertToLlm, transformContext, streamFn, getApiKey, onPayload, onResponse, beforeToolCall, afterToolCall, shouldStopAfterTurn, prepareNextTurn, prepareNextTurnWithContext, steeringMode, followUpMode, sessionId, thinkingBudgets, transport, maxRetryDelayMs, toolExecution} Done{stream}:
      do IO<Result<&2, &2, Provider.MissingDefault, Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>>>:
        converted : Converted<A, G, D, M, E> <- converterOptions(~A, ~G, ~D, ~M, ~V, ~E, ~J, convertToLlm)
        finishOptions(A, G, D, M, V, E, J, Telemetry, Fetch, initialState, converted, stream, Hooks{shouldStopAfterTurn, prepareNextTurn, prepareNextTurnWithContext}, steeringMode, followUpMode, transformContext, getApiKey, onPayload, onResponse, beforeToolCall, afterToolCall, sessionId, thinkingBudgets, transport, maxRetryDelayMs, toolExecution)
# Resolve fallback at construction, preserving the selected callback for runs.
def resolve(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, +options: AgentOptions<A, G, D, M, V, E, J, Telemetry, Fetch>, fallback: Provider.Registry(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)) -> IO(Result<&2, &2, Provider.MissingDefault, Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>>):
  match options:
    case AgentOptions{_, _, _, streamFn, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      do IO<Result<&2, &2, Provider.MissingDefault, Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>>>:
        provider : Result<&2, &2, Provider.MissingDefault, T.StreamFn(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)> <- Provider.resolve(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E, providerSelection(A, G, D, M, V, E, J, Telemetry, Fetch, streamFn, fallback))
        resolvedOptions(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, options, provider)


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
def getSessionIdSettings(settings: Settings) -> Maybe<&2, String>:
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
type Retired<-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data> is Data:
  Retired{resources: Resources<A, G, D, M, V, E, J>, hooks: Adapters<Turn(A, G, D, M, V, E), Update(A, G, D, M, V, E, J), E>}
# Caller-owned callbacks remain borrowed. Stop new operations and await their
# completion before disposal; retained tool/listener aliases must retire too.
type Agent<-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Agent{runtime: RunRuntime(A, G, D, M, V, E, J), listeners: Registry(A, G, D, M, E), options: R.Ref<Options<A, G, D, M, V, E, J, Telemetry, Fetch>>, hooks: R.Ref<TurnHooks(A, G, D, M, V, E, J)>, retired: R.Ref<List<&2, Retired<A, G, D, M, V, E, J>>>, ownedConverter: Maybe<&2, Converter(A, G, D, M, E)>}
def constructed(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, resolved: Result<&2, &2, Provider.MissingDefault, Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>>, validate: C.Callback<Loop.ToolValidationInput<Schema.Value, A, V>, Result<&2, &2, E, V>>, emptyDetails: D) -> IO(Result<&2, &2, Provider.MissingDefault, Agent<A, G, D, M, V, E, J, Telemetry, Fetch>>):
  match resolved:
    case Fail{error}: IO.pure(Result<&2, &2, Provider.MissingDefault, Agent<A, G, D, M, V, E, J, Telemetry, Fetch>>, Fail{error})
    case Done{Resolved{initial, config, stream, hooks, steering, follow, ownedConverter}}:
      do IO<Result<&2, &2, Provider.MissingDefault, Agent<A, G, D, M, V, E, J, Telemetry, Fetch>>>:
        runtime : RunRuntime(A, G, D, M, V, E, J) <- newRuntime(Schema.Value, A, G, D, M, V, RunSignal(), E, J, initial, steering, follow)
        listeners : Registry(A, G, D, M, E) <- newListeners(RunEvent(A, G, D, M), RunSignal(), E)
        options : R.Ref<Options<A, G, D, M, V, E, J, Telemetry, Fetch>> <- R.new(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, Options{config, Provider.Explicit{stream}, validate, emptyDetails})
        liveHooks : R.Ref<TurnHooks(A, G, D, M, V, E, J)> <- R.new(TurnHooks(A, G, D, M, V, E, J), hooks)
        retired : R.Ref<List<&2, Retired<A, G, D, M, V, E, J>>> <- R.new(List<&2, Retired<A, G, D, M, V, E, J>>, Nil{})
        return Done{Agent{runtime, listeners, options, liveHooks, retired, ownedConverter}}
# Validation is an explicit typed dependency, never an implicit permissive check.
def new(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, options: AgentOptions<A, G, D, M, V, E, J, Telemetry, Fetch>, fallback: Provider.Registry(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E), validate: C.Callback<Loop.ToolValidationInput<Schema.Value, A, V>, Result<&2, &2, E, V>>, emptyDetails: D) -> IO(Result<&2, &2, Provider.MissingDefault, Agent<A, G, D, M, V, E, J, Telemetry, Fetch>>):
  do IO<Result<&2, &2, Provider.MissingDefault, Agent<A, G, D, M, V, E, J, Telemetry, Fetch>>>:
    resolved : Result<&2, &2, Provider.MissingDefault, Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>> <- resolve(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, options, fallback)
    constructed(A, G, D, M, V, E, J, Telemetry, Fetch, resolved, validate, emptyDetails)
def state(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(T.AgentState<Schema.Value, A, G, D, M, V, RunSignal(), E, J>):
  match agent:
    case Agent{runtime, _, _, _, _, _}: readRuntime(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime)
def subscribe(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, listener: Handler(RunEvent(A, G, D, M), RunSignal(), E)) -> IO(Subscription<RunEvent(A, G, D, M), RunSignal(), E>):
  match agent:
    case Agent{_, listeners, _, _, _, _}: subscribeListeners(RunEvent(A, G, D, M), RunSignal(), E, listeners, listener)
def runOptions(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>, hooks: Adapters<Turn(A, G, D, M, V, E), Update(A, G, D, M, V, E, J), E>) -> Options<A, G, D, M, V, E, J, Telemetry, Fetch>:
  match options:
    case Options{config, stream, validate, emptyDetails}: Options{applyHooks(Schema.Value, A, G, D, M, V, RunSignal(), E, J, Telemetry, Fetch, config, hooks), stream, validate, emptyDetails}
def settledAgent(-E: Data, outcome: Result<&2, &2, DeliveryError<E>, Unit>) -> Result<&2, &2, AgentError<E>, Unit>:
  match outcome:
    case Done{value}: Done{value}
    case Fail{error}: Fail{DeliveryFailed{error}}
def retire(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, retired: R.Ref<List<&2, Retired<A, G, D, M, V, E, J>>>, hooks: Adapters<Turn(A, G, D, M, V, E), Update(A, G, D, M, V, E, J), E>, completed: Completed<A, G, D, M, V, E, J>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match completed:
    case Completed{outcome, resources}:
      do IO<Result<&2, &2, AgentError<E>, Unit>>:
        R.modify(List<&2, Retired<A, G, D, M, V, E, J>>, Unit, retired, previous => (Retired{resources, hooks} <> previous, Unit{}))
        return settledAgent(E, outcome)
def runClaimed(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, claimed: Claimed<Plan<RunMessage(A, G, D, M)>>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match agent:
    case Agent{OwnedRuntime{+lifecycle}, listeners, options, hooks, retired, _}:
      do IO<Result<&2, &2, AgentError<E>, Unit>>:
        +adapters : Adapters<Turn(A, G, D, M, V, E), Update(A, G, D, M, V, E, J), E> <- createHooks(~OwnedState<Schema.Value, A, G, D, M, V, RunSignal(), E, J>, ~Turn(A, G, D, M, V, E), ~Update(A, G, D, M, V, E, J), ~E, lifecycle, hooks)
        base : Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.read(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        completed : Completed<A, G, D, M, V, E, J> <- runClaimedRun(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~fromString, ~declarationError, OwnedRuntime{lifecycle}, listeners, runOptions(A, G, D, M, V, E, J, Telemetry, Fetch, base, adapters), claimed)
        retire(A, G, D, M, V, E, J, retired, adapters, completed)
def claimError(error: ClaimError<String>, continuation: Bool) -> String:
  match error:
    case Rejected{message}: message
    case LifeBusy{}: Bool.pick(String, continuation, "Agent is already processing. Wait for completion before continuing.", "Agent is already processing a prompt. Use steer() or followUp() to queue messages, or wait for completion.")
def startClaimed(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, continuation: Bool, claim: Result<&2, &2, ClaimError<String>, Claimed<Plan<RunMessage(A, G, D, M)>>>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match claim:
    case Fail{error}: IO.pure(Result<&2, &2, AgentError<E>, Unit>, Fail{ClaimFailed{claimError(error, continuation)}})
    case Done{claimed}: runClaimed(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~fromString, ~declarationError, agent, claimed)
def promptMessages(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, +agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, messages: List<&2, RunMessage(A, G, D, M)>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match agent:
    case Agent{runtime, _, _, _, _, _}:
      do IO<Result<&2, &2, AgentError<E>, Unit>>:
        claim : Result<&2, &2, ClaimError<String>, Claimed<Plan<RunMessage(A, G, D, M)>>> <- beginPrompt(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime, messages)
        startClaimed(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~fromString, ~declarationError, agent, False{}, claim)
def continueRun(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, +agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match agent:
    case Agent{runtime, _, _, _, _, _}:
      do IO<Result<&2, &2, AgentError<E>, Unit>>:
        claim : Result<&2, &2, ClaimError<String>, Claimed<Plan<RunMessage(A, G, D, M)>>> <- beginContinue(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime)
        startClaimed(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~fromString, ~declarationError, agent, True{}, claim)
def steer(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, message: RunMessage(A, G, D, M)) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: steerRuntime(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime, message)
def followUp(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, message: RunMessage(A, G, D, M)) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: followUpRuntime(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime, message)
def abort(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: abortRuntime(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime)
def waitForIdle(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: waitForIdleRuntime(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime)
def clearAllQueues(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: clearAllRuntimeQueues(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime)
def reset(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Result<&2, &2, String, Unit>):
  match agent:
    case Agent{runtime, _, _, _, _, _}: resetRuntime(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime)
def clearSteeringQueue(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: clearQueue(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime, QueuesSteering{})
def clearFollowUpQueue(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: clearQueue(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime, FollowUp{})
def signal(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, RunSignal()>):
  match agent:
    case Agent{OwnedRuntime{lifecycle}, _, _, _, _, _}: signalHooks(OwnedState<Schema.Value, A, G, D, M, V, RunSignal(), E, J>, lifecycle)
def setHooks(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: TurnHooks(A, G, D, M, V, E, J)) -> IO(Unit):
  match agent:
    case Agent{_, _, _, hooks, _, _}: R.write(TurnHooks(A, G, D, M, V, E, J), hooks, value)
def disposeRuns(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, runs: List<&2, Retired<A, G, D, M, V, E, J>>) -> IO(Unit):
  match runs:
    case Nil{}: IO.pure(Unit, Unit{})
    case Retired{resources, hooks} <> rest:
      do IO<Unit>:
        runDispose(A, G, D, M, V, E, J, resources)
        disposeHooks(Turn(A, G, D, M, V, E), Update(A, G, D, M, V, E, J), E, hooks)
        disposeRuns(A, G, D, M, V, E, J, rest)
# Join public calls and retire borrowed aliases before disposal. waitForIdle
# covers awaited listeners; surviving failed tool batches drain here.
def dispose(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Unit):
  match agent:
    case Agent{runtime, listeners, options, hooks, retired, converter}:
      do IO<Unit>:
        runs : List<&2, Retired<A, G, D, M, V, E, J>> <- R.dispose(List<&2, Retired<A, G, D, M, V, E, J>>, retired)
        disposeRuns(A, G, D, M, V, E, J, runs)
        disposeListeners(RunEvent(A, G, D, M), RunSignal(), E, listeners)
        old : Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.dispose(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        old : TurnHooks(A, G, D, M, V, E, J) <- R.dispose(TurnHooks(A, G, D, M, V, E, J), hooks)
        disposeCallback(List<&2, RunMessage(A, G, D, M)>, Result<&2, &2, E, List<&2, Ai.Message<Schema.Value, A, G, D>>>, converter)
        old : OwnedState<Schema.Value, A, G, D, M, V, RunSignal(), E, J> <- disposeRuntime(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime)
        return Unit{}

# Native sum types represent the source's text/single-message/batch overloads.
type PromptInput<-A: Data, -G: Data, -D: Data, -M: Data> is Data:
  Text{text: String, images: List<&2, Ai.ImageContent>}
  Message{message: RunMessage(A, G, D, M)}
  Messages{messages: List<&2, RunMessage(A, G, D, M)>}
def imageBlocks(images: List<&2, Ai.ImageContent>) -> List<&2, Ai.TextImageContent>:
  match images:
    case Nil{}: Nil{}
    case image <> rest: Ai.TextImageImage{image} <> imageBlocks(rest)
def normalizePromptInputAt(-A: Data, -G: Data, -D: Data, -M: Data, input: PromptInput<A, G, D, M>, timestamp: F.F64) -> List<&2, RunMessage(A, G, D, M)>:
  match input:
    case Text{text, images}: T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{Ai.TextImageText{Ai.TextContent{text, None{}}} <> imageBlocks(images)}, timestamp}}} <> Nil{}
    case Message{message}: message <> Nil{}
    case Messages{messages}: messages
def normalizePromptInput(-A: Data, -G: Data, -D: Data, -M: Data, input: PromptInput<A, G, D, M>) -> IO(List<&2, RunMessage(A, G, D, M)>):
  match input:
    case Text{text, images}:
      do IO<List<&2, RunMessage(A, G, D, M)>>:
        timestamp : F.F64 <- Date.now()
        return normalizePromptInputAt(A, G, D, M, Text{text, images}, timestamp)
    case Message{message}: IO.pure(List<&2, RunMessage(A, G, D, M)>, message <> Nil{})
    case Messages{messages}: IO.pure(List<&2, RunMessage(A, G, D, M)>, messages)
def promptReady(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, input: PromptInput<A, G, D, M>, active: Maybe<&2, RunSignal()>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  match active:
    case Some{_}: IO.pure(Result<&2, &2, AgentError<E>, Unit>, Fail{ClaimFailed{claimError(LifeBusy{}, False{})}})
    case None{}:
      do IO<Result<&2, &2, AgentError<E>, Unit>>:
        messages : List<&2, RunMessage(A, G, D, M)> <- normalizePromptInput(A, G, D, M, input)
        promptMessages(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~fromString, ~declarationError, agent, messages)
def prompt(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: E -> String, ~fromString: String -> E, ~declarationError: Declaration.DeclarationError -> E, +agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, input: PromptInput<A, G, D, M>) -> IO(Result<&2, &2, AgentError<E>, Unit>):
  do IO<Result<&2, &2, AgentError<E>, Unit>>:
    active : Maybe<&2, RunSignal()> <- signal(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    promptReady(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, ~renderError, ~fromString, ~declarationError, agent, input, active)

def updateState(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, change: StateChange<Schema.Value, A, G, D, M, V, RunSignal(), E, J>) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: updateStateRuntime(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime, change)
def setModel(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Ai.Model<J>) -> IO(Unit):
  updateState(A, G, D, M, V, E, J, Telemetry, Fetch, agent, SetModel{value})
def setThinkingLevel(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: T.ThinkingLevel()) -> IO(Unit):
  updateState(A, G, D, M, V, E, J, Telemetry, Fetch, agent, SetThinkingLevel{value})
def setTools(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: List<&2, T.AgentTool<Schema.Value, V, D, A, RunSignal(), E>>) -> IO(Unit):
  updateState(A, G, D, M, V, E, J, Telemetry, Fetch, agent, SetTools{value})
def replaceMessages(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: List<&2, RunMessage(A, G, D, M)>) -> IO(Unit):
  updateState(A, G, D, M, V, E, J, Telemetry, Fetch, agent, ReplaceMessages{value})
def appendMessage(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: RunMessage(A, G, D, M)) -> IO(Unit):
  updateState(A, G, D, M, V, E, J, Telemetry, Fetch, agent, AppendMessage{value})
def clearMessages(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Unit): replaceMessages(A, G, D, M, V, E, J, Telemetry, Fetch, agent, Nil{})
def systemPrompt(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(String):
  do IO<String>:
    value : T.AgentState<Schema.Value, A, G, D, M, V, RunSignal(), E, J> <- state(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return systemPromptState(Schema.Value, A, G, D, M, V, RunSignal(), E, J, value)
def queueValues(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, owned: OwnedState<Schema.Value, A, G, D, M, V, RunSignal(), E, J>) -> Queues<RunMessage(A, G, D, M)>:
  match owned:
    case OwnedState{_, queues}: queues
def queueSnapshot(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Queues<RunMessage(A, G, D, M)>):
  match agent:
    case Agent{runtime, _, _, _, _, _}:
      do IO<Queues<RunMessage(A, G, D, M)>>:
        owned : OwnedState<Schema.Value, A, G, D, M, V, RunSignal(), E, J> <- snapshotRuntime(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime)
        return queueValues(A, G, D, M, V, E, J, owned)
def hasQueuedMessages(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Bool):
  do IO<Bool>:
    queues : Queues<RunMessage(A, G, D, M)> <- queueSnapshot(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return queuesHaveMessages(RunMessage(A, G, D, M), queues)
def setSteeringMode(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, mode: T.QueueMode) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: setQueueMode(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime, QueuesSteering{}, mode)
def getSteeringMode(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(T.QueueMode):
  do IO<T.QueueMode>:
    queues : Queues<RunMessage(A, G, D, M)> <- queueSnapshot(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return getModeQueues(RunMessage(A, G, D, M), queues, QueuesSteering{})
def setFollowUpMode(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, mode: T.QueueMode) -> IO(Unit):
  match agent:
    case Agent{runtime, _, _, _, _, _}: setQueueMode(Schema.Value, A, G, D, M, V, RunSignal(), E, J, runtime, FollowUp{}, mode)
def getFollowUpMode(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(T.QueueMode):
  do IO<T.QueueMode>:
    queues : Queues<RunMessage(A, G, D, M)> <- queueSnapshot(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return getModeQueues(RunMessage(A, G, D, M), queues, FollowUp{})

def configSettings(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch)) -> Settings:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, maxRetryDelayMs, _, _, _, transport, _, sessionId, _, _, _, _, _, thinkingBudgets, _, _, _, _, _, _, _, _, toolExecution, _, _}: Settings{sessionId, thinkingBudgets, Maybe.default(&2, Ai.Transport, transport, Ai.AutoTransport{}), maxRetryDelayMs, Maybe.default(&2, T.ToolExecutionMode, toolExecution, T.Parallel{})}
def settingsConfig(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch), settings: Settings) -> Config(A, G, D, M, V, E, J, Telemetry, Fetch):
  match config settings:
    case T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, _, temperature, samplingParams, maxTokens, _, cacheRetention, _, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, _, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, _, beforeToolCall, afterToolCall} Settings{sessionId, thinkingBudgets, transport, maxRetryDelayMs, toolExecution}: T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, Some{transport}, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, Some{toolExecution}, beforeToolCall, afterToolCall}
def changedSettings(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>, change: SettingsChange) -> Options<A, G, D, M, V, E, J, Telemetry, Fetch> & Unit:
  match options:
    case Options{+config, provider, validate, emptyDetails}: (Options{settingsConfig(A, G, D, M, V, E, J, Telemetry, Fetch, config, apply(configSettings(A, G, D, M, V, E, J, Telemetry, Fetch, config), change)), provider, validate, emptyDetails}, Unit{})
def updateSettings(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, change: SettingsChange) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, Unit, options, current => changedSettings(A, G, D, M, V, E, J, Telemetry, Fetch, current, change))
def optionsSettings(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>) -> Settings:
  match options:
    case Options{config, _, _, _}: configSettings(A, G, D, M, V, E, J, Telemetry, Fetch, config)
def getSettings(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Settings):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Settings>:
        current : Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.read(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        return optionsSettings(A, G, D, M, V, E, J, Telemetry, Fetch, current)
def setSessionId(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, String>) -> IO(Unit):
  updateSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent, SetSessionId{value})
def getSessionId(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    settings : Settings <- getSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return getSessionIdSettings(settings)
def setThinkingBudgets(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, Ai.ThinkingBudgets>) -> IO(Unit):
  updateSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent, SetThinkingBudgets{value})
def getThinkingBudgets(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, Ai.ThinkingBudgets>):
  do IO<Maybe<&2, Ai.ThinkingBudgets>>:
    settings : Settings <- getSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return getThinkingBudgetsSettings(settings)
def setTransport(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Ai.Transport) -> IO(Unit):
  updateSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent, SetTransport{value})
def getTransport(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Ai.Transport):
  do IO<Ai.Transport>:
    settings : Settings <- getSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return getTransportSettings(settings)
def setMaxRetryDelayMs(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, F.F64>) -> IO(Unit):
  updateSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent, SetMaxRetryDelayMs{value})
def getMaxRetryDelayMs(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, F.F64>):
  do IO<Maybe<&2, F.F64>>:
    settings : Settings <- getSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return getMaxRetryDelayMsSettings(settings)
def setToolExecution(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: T.ToolExecutionMode) -> IO(Unit):
  updateSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent, SetToolExecution{value})
def getToolExecution(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(T.ToolExecutionMode):
  do IO<T.ToolExecutionMode>:
    settings : Settings <- getSettings(A, G, D, M, V, E, J, Telemetry, Fetch, agent)
    return getToolExecutionSettings(settings)
def configSessionId(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch)) -> Maybe<&2, String>:
  getSessionIdSettings(configSettings(A, G, D, M, V, E, J, Telemetry, Fetch, config))

# Replacement borrows the new callback. Keep old and new caller-owned handles
# alive through every run that captured them. The owned default converter stays
# alive until Agent disposal, even after replacement.
def changedStreamFunction(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>, value: T.StreamFn(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)) -> Options<A, G, D, M, V, E, J, Telemetry, Fetch> & Unit:
  match options:
    case Options{config, _, validate, emptyDetails}: (Options{config, Provider.Explicit{value}, validate, emptyDetails}, Unit{})
def setStreamFunction(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: T.StreamFn(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, Unit, options, current => changedStreamFunction(A, G, D, M, V, E, J, Telemetry, Fetch, current, value))
def optionsStreamFunction(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(T.StreamFn(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)):
  match options:
    case Options{_, Provider.Explicit{value}, _, _}: IO.pure(T.StreamFn(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E), value)
    case _: IO.die(T.StreamFn(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E), 1, "Agent provider selection must be resolved at construction")
def getStreamFunction(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(T.StreamFn(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<T.StreamFn(Schema.Value, A, G, D, J, Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)>:
        current : Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.read(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        optionsStreamFunction(A, G, D, M, V, E, J, Telemetry, Fetch, current)
def configConvertToLlm(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch)) -> Converter(A, G, D, M, E):
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _, _, _}: value
def replaceConvertToLlm(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch), value: Converter(A, G, D, M, E)) -> Config(A, G, D, M, V, E, J, Telemetry, Fetch):
  match config:
    case T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, _, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, value, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}
def changedConvertToLlm(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Converter(A, G, D, M, E)) -> Options<A, G, D, M, V, E, J, Telemetry, Fetch> & Unit:
  match options:
    case Options{config, provider, validate, emptyDetails}: (Options{replaceConvertToLlm(A, G, D, M, V, E, J, Telemetry, Fetch, config, value), provider, validate, emptyDetails}, Unit{})
def setConvertToLlm(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Converter(A, G, D, M, E)) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, Unit, options, current => changedConvertToLlm(A, G, D, M, V, E, J, Telemetry, Fetch, current, value))
def optionsConvertToLlm(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>) -> Converter(A, G, D, M, E):
  match options:
    case Options{config, _, _, _}: configConvertToLlm(A, G, D, M, V, E, J, Telemetry, Fetch, config)
def getConvertToLlm(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Converter(A, G, D, M, E)):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Converter(A, G, D, M, E)>:
        current : Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.read(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        return optionsConvertToLlm(A, G, D, M, V, E, J, Telemetry, Fetch, current)
def configTransformContext(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch)) -> Maybe<&2, C.Callback<T.TransformContextInput<List<&2, RunMessage(A, G, D, M)>, RunSignal()>, Result<&2, &2, E, List<&2, RunMessage(A, G, D, M)>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _, _}: value
def replaceTransformContext(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch), value: Maybe<&2, C.Callback<T.TransformContextInput<List<&2, RunMessage(A, G, D, M)>, RunSignal()>, Result<&2, &2, E, List<&2, RunMessage(A, G, D, M)>>>>) -> Config(A, G, D, M, V, E, J, Telemetry, Fetch):
  match config:
    case T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, _, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, value, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}
def changedTransformContext(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, C.Callback<T.TransformContextInput<List<&2, RunMessage(A, G, D, M)>, RunSignal()>, Result<&2, &2, E, List<&2, RunMessage(A, G, D, M)>>>>) -> Options<A, G, D, M, V, E, J, Telemetry, Fetch> & Unit:
  match options:
    case Options{config, provider, validate, emptyDetails}: (Options{replaceTransformContext(A, G, D, M, V, E, J, Telemetry, Fetch, config, value), provider, validate, emptyDetails}, Unit{})
def setTransformContext(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, C.Callback<T.TransformContextInput<List<&2, RunMessage(A, G, D, M)>, RunSignal()>, Result<&2, &2, E, List<&2, RunMessage(A, G, D, M)>>>>) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, Unit, options, current => changedTransformContext(A, G, D, M, V, E, J, Telemetry, Fetch, current, value))
def optionsTransformContext(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>) -> Maybe<&2, C.Callback<T.TransformContextInput<List<&2, RunMessage(A, G, D, M)>, RunSignal()>, Result<&2, &2, E, List<&2, RunMessage(A, G, D, M)>>>>:
  match options:
    case Options{config, _, _, _}: configTransformContext(A, G, D, M, V, E, J, Telemetry, Fetch, config)
def getTransformContext(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, C.Callback<T.TransformContextInput<List<&2, RunMessage(A, G, D, M)>, RunSignal()>, Result<&2, &2, E, List<&2, RunMessage(A, G, D, M)>>>>):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Maybe<&2, C.Callback<T.TransformContextInput<List<&2, RunMessage(A, G, D, M)>, RunSignal()>, Result<&2, &2, E, List<&2, RunMessage(A, G, D, M)>>>>>:
        current : Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.read(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        return optionsTransformContext(A, G, D, M, V, E, J, Telemetry, Fetch, current)

def configGetApiKey(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch)) -> Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _}: value
def replaceGetApiKey(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch), value: Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>) -> Config(A, G, D, M, V, E, J, Telemetry, Fetch):
  match config:
    case T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, _, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, value, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}
def changedGetApiKey(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>) -> Options<A, G, D, M, V, E, J, Telemetry, Fetch> & Unit:
  match options:
    case Options{config, provider, validate, emptyDetails}: (Options{replaceGetApiKey(A, G, D, M, V, E, J, Telemetry, Fetch, config, value), provider, validate, emptyDetails}, Unit{})
def setGetApiKey(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, Unit, options, current => changedGetApiKey(A, G, D, M, V, E, J, Telemetry, Fetch, current, value))
def optionsGetApiKey(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>) -> Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>:
  match options:
    case Options{config, _, _, _}: configGetApiKey(A, G, D, M, V, E, J, Telemetry, Fetch, config)
def getGetApiKey(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>>:
        current : Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.read(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        return optionsGetApiKey(A, G, D, M, V, E, J, Telemetry, Fetch, current)

def configOnPayload(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch)) -> Maybe<&2, Ai.PayloadCallback(J, Ai.Model<J>, E)>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, value, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
def replaceOnPayload(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch), value: Maybe<&2, Ai.PayloadCallback(J, Ai.Model<J>, E)>) -> Config(A, G, D, M, V, E, J, Telemetry, Fetch):
  match config:
    case T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, _, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, value, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}
def changedOnPayload(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, Ai.PayloadCallback(J, Ai.Model<J>, E)>) -> Options<A, G, D, M, V, E, J, Telemetry, Fetch> & Unit:
  match options:
    case Options{config, provider, validate, emptyDetails}: (Options{replaceOnPayload(A, G, D, M, V, E, J, Telemetry, Fetch, config, value), provider, validate, emptyDetails}, Unit{})
def setOnPayload(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, Ai.PayloadCallback(J, Ai.Model<J>, E)>) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, Unit, options, current => changedOnPayload(A, G, D, M, V, E, J, Telemetry, Fetch, current, value))
def optionsOnPayload(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>) -> Maybe<&2, Ai.PayloadCallback(J, Ai.Model<J>, E)>:
  match options:
    case Options{config, _, _, _}: configOnPayload(A, G, D, M, V, E, J, Telemetry, Fetch, config)
def getOnPayload(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, Ai.PayloadCallback(J, Ai.Model<J>, E)>):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Maybe<&2, Ai.PayloadCallback(J, Ai.Model<J>, E)>>:
        current : Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.read(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        return optionsOnPayload(A, G, D, M, V, E, J, Telemetry, Fetch, current)

def configOnResponse(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch)) -> Maybe<&2, Ai.ResponseCallback(Ai.Model<J>, E)>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, value, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
def replaceOnResponse(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch), value: Maybe<&2, Ai.ResponseCallback(Ai.Model<J>, E)>) -> Config(A, G, D, M, V, E, J, Telemetry, Fetch):
  match config:
    case T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, _, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}: T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, value, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall}
def changedOnResponse(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, Ai.ResponseCallback(Ai.Model<J>, E)>) -> Options<A, G, D, M, V, E, J, Telemetry, Fetch> & Unit:
  match options:
    case Options{config, provider, validate, emptyDetails}: (Options{replaceOnResponse(A, G, D, M, V, E, J, Telemetry, Fetch, config, value), provider, validate, emptyDetails}, Unit{})
def setOnResponse(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, Ai.ResponseCallback(Ai.Model<J>, E)>) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, Unit, options, current => changedOnResponse(A, G, D, M, V, E, J, Telemetry, Fetch, current, value))
def optionsOnResponse(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>) -> Maybe<&2, Ai.ResponseCallback(Ai.Model<J>, E)>:
  match options:
    case Options{config, _, _, _}: configOnResponse(A, G, D, M, V, E, J, Telemetry, Fetch, config)
def getOnResponse(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, Ai.ResponseCallback(Ai.Model<J>, E)>):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Maybe<&2, Ai.ResponseCallback(Ai.Model<J>, E)>>:
        current : Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.read(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        return optionsOnResponse(A, G, D, M, V, E, J, Telemetry, Fetch, current)

def configBeforeToolCall(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch)) -> Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, T.BeforeToolCallUpdate<V, T.AgentContext<Schema.Value, A, G, D, M, V, RunSignal(), E>>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _}: value
def replaceBeforeToolCall(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch), value: Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, T.BeforeToolCallUpdate<V, T.AgentContext<Schema.Value, A, G, D, M, V, RunSignal(), E>>>>>) -> Config(A, G, D, M, V, E, J, Telemetry, Fetch):
  match config:
    case T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, _, afterToolCall}: T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, value, afterToolCall}
def changedBeforeToolCall(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, T.BeforeToolCallUpdate<V, T.AgentContext<Schema.Value, A, G, D, M, V, RunSignal(), E>>>>>) -> Options<A, G, D, M, V, E, J, Telemetry, Fetch> & Unit:
  match options:
    case Options{config, provider, validate, emptyDetails}: (Options{replaceBeforeToolCall(A, G, D, M, V, E, J, Telemetry, Fetch, config, value), provider, validate, emptyDetails}, Unit{})
def setBeforeToolCall(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, T.BeforeToolCallUpdate<V, T.AgentContext<Schema.Value, A, G, D, M, V, RunSignal(), E>>>>>) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, Unit, options, current => changedBeforeToolCall(A, G, D, M, V, E, J, Telemetry, Fetch, current, value))
def optionsBeforeToolCall(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>) -> Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, T.BeforeToolCallUpdate<V, T.AgentContext<Schema.Value, A, G, D, M, V, RunSignal(), E>>>>>:
  match options:
    case Options{config, _, _, _}: configBeforeToolCall(A, G, D, M, V, E, J, Telemetry, Fetch, config)
def getBeforeToolCall(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, T.BeforeToolCallUpdate<V, T.AgentContext<Schema.Value, A, G, D, M, V, RunSignal(), E>>>>>):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, T.BeforeToolCallUpdate<V, T.AgentContext<Schema.Value, A, G, D, M, V, RunSignal(), E>>>>>>:
        current : Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.read(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        return optionsBeforeToolCall(A, G, D, M, V, E, J, Telemetry, Fetch, current)


def configAfterToolCall(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch)) -> Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value}: value
def replaceAfterToolCall(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, config: Config(A, G, D, M, V, E, J, Telemetry, Fetch), value: Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>) -> Config(A, G, D, M, V, E, J, Telemetry, Fetch):
  match config:
    case T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, _}: T.AgentLoopConfig{runSignal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, value}
def changedAfterToolCall(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>) -> Options<A, G, D, M, V, E, J, Telemetry, Fetch> & Unit:
  match options:
    case Options{config, provider, validate, emptyDetails}: (Options{replaceAfterToolCall(A, G, D, M, V, E, J, Telemetry, Fetch, config, value), provider, validate, emptyDetails}, Unit{})
def setAfterToolCall(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>) -> IO(Unit):
  match agent:
    case Agent{_, _, options, _, _, _}: R.modify(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, Unit, options, current => changedAfterToolCall(A, G, D, M, V, E, J, Telemetry, Fetch, current, value))
def optionsAfterToolCall(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, options: Options<A, G, D, M, V, E, J, Telemetry, Fetch>) -> Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>:
  match options:
    case Options{config, _, _, _}: configAfterToolCall(A, G, D, M, V, E, J, Telemetry, Fetch, config)
def getAfterToolCall(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>):
  match agent:
    case Agent{_, _, options, _, _, _}:
      do IO<Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<Schema.Value, A, G, D, M, V, RunSignal(), E>, RunSignal()>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>>:
        current : Options<A, G, D, M, V, E, J, Telemetry, Fetch> <- R.read(Options<A, G, D, M, V, E, J, Telemetry, Fetch>, options)
        return optionsAfterToolCall(A, G, D, M, V, E, J, Telemetry, Fetch, current)

def changedShouldStopAfterTurn(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, hooks: TurnHooks(A, G, D, M, V, E, J), value: Maybe<&2, StopHook(Turn(A, G, D, M, V, E), E)>) -> TurnHooks(A, G, D, M, V, E, J) & Unit:
  match hooks:
    case Hooks{_, legacy, contextLocal}: (Hooks{value, legacy, contextLocal}, Unit{})
def setShouldStopAfterTurn(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, StopHook(Turn(A, G, D, M, V, E), E)>) -> IO(Unit):
  match agent:
    case Agent{_, _, _, hooks, _, _}: R.modify(TurnHooks(A, G, D, M, V, E, J), Unit, hooks, current => changedShouldStopAfterTurn(A, G, D, M, V, E, J, Telemetry, Fetch, current, value))
def hooksShouldStopAfterTurn(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, hooks: TurnHooks(A, G, D, M, V, E, J)) -> Maybe<&2, StopHook(Turn(A, G, D, M, V, E), E)>:
  match hooks:
    case Hooks{value, _, _}: value
def getShouldStopAfterTurn(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, StopHook(Turn(A, G, D, M, V, E), E)>):
  match agent:
    case Agent{_, _, _, hooks, _, _}:
      do IO<Maybe<&2, StopHook(Turn(A, G, D, M, V, E), E)>>:
        current : TurnHooks(A, G, D, M, V, E, J) <- R.read(TurnHooks(A, G, D, M, V, E, J), hooks)
        return hooksShouldStopAfterTurn(A, G, D, M, V, E, J, Telemetry, Fetch, current)

def changedPrepareNextTurn(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, hooks: TurnHooks(A, G, D, M, V, E, J), value: Maybe<&2, LegacyHook(Update(A, G, D, M, V, E, J), E)>) -> TurnHooks(A, G, D, M, V, E, J) & Unit:
  match hooks:
    case Hooks{stop, _, contextLocal}: (Hooks{stop, value, contextLocal}, Unit{})
def setPrepareNextTurn(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, LegacyHook(Update(A, G, D, M, V, E, J), E)>) -> IO(Unit):
  match agent:
    case Agent{_, _, _, hooks, _, _}: R.modify(TurnHooks(A, G, D, M, V, E, J), Unit, hooks, current => changedPrepareNextTurn(A, G, D, M, V, E, J, Telemetry, Fetch, current, value))
def hooksPrepareNextTurn(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, hooks: TurnHooks(A, G, D, M, V, E, J)) -> Maybe<&2, LegacyHook(Update(A, G, D, M, V, E, J), E)>:
  match hooks:
    case Hooks{_, value, _}: value
def getPrepareNextTurn(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, LegacyHook(Update(A, G, D, M, V, E, J), E)>):
  match agent:
    case Agent{_, _, _, hooks, _, _}:
      do IO<Maybe<&2, LegacyHook(Update(A, G, D, M, V, E, J), E)>>:
        current : TurnHooks(A, G, D, M, V, E, J) <- R.read(TurnHooks(A, G, D, M, V, E, J), hooks)
        return hooksPrepareNextTurn(A, G, D, M, V, E, J, Telemetry, Fetch, current)

def changedPrepareNextTurnWithContext(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, hooks: TurnHooks(A, G, D, M, V, E, J), value: Maybe<&2, ContextHook(Turn(A, G, D, M, V, E), Update(A, G, D, M, V, E, J), E)>) -> TurnHooks(A, G, D, M, V, E, J) & Unit:
  match hooks:
    case Hooks{stop, legacy, _}: (Hooks{stop, legacy, value}, Unit{})
def setPrepareNextTurnWithContext(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>, value: Maybe<&2, ContextHook(Turn(A, G, D, M, V, E), Update(A, G, D, M, V, E, J), E)>) -> IO(Unit):
  match agent:
    case Agent{_, _, _, hooks, _, _}: R.modify(TurnHooks(A, G, D, M, V, E, J), Unit, hooks, current => changedPrepareNextTurnWithContext(A, G, D, M, V, E, J, Telemetry, Fetch, current, value))
def hooksPrepareNextTurnWithContext(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, hooks: TurnHooks(A, G, D, M, V, E, J)) -> Maybe<&2, ContextHook(Turn(A, G, D, M, V, E), Update(A, G, D, M, V, E, J), E)>:
  match hooks:
    case Hooks{_, _, value}: value
def getPrepareNextTurnWithContext(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, agent: Agent<A, G, D, M, V, E, J, Telemetry, Fetch>) -> IO(Maybe<&2, ContextHook(Turn(A, G, D, M, V, E), Update(A, G, D, M, V, E, J), E)>):
  match agent:
    case Agent{_, _, _, hooks, _, _}:
      do IO<Maybe<&2, ContextHook(Turn(A, G, D, M, V, E), Update(A, G, D, M, V, E, J), E)>>:
        current : TurnHooks(A, G, D, M, V, E, J) <- R.read(TurnHooks(A, G, D, M, V, E, J), hooks)
        return hooksPrepareNextTurnWithContext(A, G, D, M, V, E, J, Telemetry, Fetch, current)
