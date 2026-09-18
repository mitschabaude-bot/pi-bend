import Base
import ./types.bend as T
import ./agent-runtime.bend as Runtime
import ./agent-lifecycle.bend as Life
import ./agent-listeners.bend as Listeners
import ./agent-events.bend as Events
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/model-api.bend as Api
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/f64.bend as F
import ../../runtime/src/date.bend as Date

def emptyUsage() -> Ai.Usage:
  +zero = F.fromU32(0)
  Ai.Usage{zero, zero, zero, zero, None{}, None{}, zero, Ai.UsageCost{zero, zero, zero, zero, zero}}
def message(-A: Data, -G: Data, -J: Data, model: Ai.Model<J>, aborted: Bool, error: String, timestamp: F.F64) -> Ai.AssistantMessage<A, G>:
  match model:
    case Ai.Model{id, _, api, provider, _, _, _, _, _, _, _, _, _, _}:
      Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{"", None{}}} <> Nil{}, Api.name(api), provider, id, None{}, None{}, None{}, None{}, emptyUsage(), Bool.pick(Ai.StopReason, aborted, Ai.Aborted{}, Ai.Error{}), None{}, Some{error}, None{}, None{}, timestamp}
def fromState(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, state: T.AgentState<P, A, G, D, C, V, S, E, J>, aborted: Bool, error: String, timestamp: F.F64) -> T.AgentMessage<P, A, G, D, C>:
  match state:
    case T.AgentState{model, _, _, _, _, _, _, _}: T.LlmMessage{Ai.Assistant{message(A, G, J, model, aborted, error, timestamp)}}
def events(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -Partial: Data, -Execution: Data, +message: T.AgentMessage<P, A, G, D, C>) -> List<&2, T.AgentEvent<P, A, G, D, C, Partial, Execution>>:
  T.MessageStart{message} <> T.MessageEnd{message} <> T.TurnEnd{message, Nil{}} <> T.AgentEnd{message <> Nil{}} <> Nil{}
def deliver(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, -Failure: Data, +runtime: Runtime.Runtime<P, A, G, D, C, V, S, E, J>, +listeners: Listeners.Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, messages: List<&2, T.AgentEvent<P, A, G, D, C, Partial, Execution>>, result: Result<&2, &2, Events.DeliveryError<Failure>, Unit>) -> IO(Result<&2, &2, Events.DeliveryError<Failure>, Unit>):
  match messages result:
    case _ Fail{error}: IO.pure(Result<&2, &2, Events.DeliveryError<Failure>, Unit>, Fail{error})
    case Nil{} Done{_}: IO.pure(Result<&2, &2, Events.DeliveryError<Failure>, Unit>, Done{Unit{}})
    case event <> rest Done{_}:
      do IO<Result<&2, &2, Events.DeliveryError<Failure>, Unit>>:
        outcome : Result<&2, &2, Events.DeliveryError<Failure>, Unit> <- Events.processEvents(P, A, G, D, C, V, S, E, J, Partial, Execution, Failure, runtime, listeners, event)
        deliver(P, A, G, D, C, V, S, E, J, Partial, Execution, Failure, runtime, listeners, rest, outcome)
# Explicit timestamp supports deterministic tests; production uses Date.now.
def handleRunFailureAt(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, -Failure: Data, +runtime: Runtime.Runtime<P, A, G, D, C, V, S, E, J>, listeners: Listeners.Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, error: String, aborted: Bool, timestamp: F.F64) -> IO(Result<&2, &2, Events.DeliveryError<Failure>, Unit>):
  do IO<Result<&2, &2, Events.DeliveryError<Failure>, Unit>>:
    state : T.AgentState<P, A, G, D, C, V, S, E, J> <- Runtime.read(P, A, G, D, C, V, S, E, J, runtime)
    deliver(P, A, G, D, C, V, S, E, J, Partial, Execution, Failure, runtime, listeners, events(P, A, G, D, C, Partial, Execution, fromState(P, A, G, D, C, V, S, E, J, state, aborted, error, timestamp)), Done{Unit{}})
def handleRunFailure(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, -Failure: Data, +runtime: Runtime.Runtime<P, A, G, D, C, V, S, E, J>, listeners: Listeners.Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, error: String, aborted: Bool) -> IO(Result<&2, &2, Events.DeliveryError<Failure>, Unit>):
  do IO<Result<&2, &2, Events.DeliveryError<Failure>, Unit>>:
    state : T.AgentState<P, A, G, D, C, V, S, E, J> <- Runtime.read(P, A, G, D, C, V, S, E, J, runtime)
    timestamp : F.F64 <- Date.now()
    deliver(P, A, G, D, C, V, S, E, J, Partial, Execution, Failure, runtime, listeners, events(P, A, G, D, C, Partial, Execution, fromState(P, A, G, D, C, V, S, E, J, state, aborted, error, timestamp)), Done{Unit{}})
def recover(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, -Failure: Data, runtime: Runtime.Runtime<P, A, G, D, C, V, S, E, J>, listeners: Listeners.Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, run: Life.ActiveRun, result: Result<&2, &2, Failure, Unit>, renderError: Failure -> String) -> IO(Result<&2, &2, Events.DeliveryError<Failure>, Unit>):
  match result:
    case Done{_}: IO.pure(Result<&2, &2, Events.DeliveryError<Failure>, Unit>, Done{Unit{}})
    case Fail{error}:
      do IO<Result<&2, &2, Events.DeliveryError<Failure>, Unit>>:
        aborted : Bool <- Abort.aborted(Unit, Life.signal(run))
        handleRunFailure(P, A, G, D, C, V, S, E, J, Partial, Execution, Failure, runtime, listeners, renderError(error), aborted)
# The prepared run is already claimed. Recovery is awaited as part of that
# run; even a recovery-listener failure reaches the final state/idle cleanup.
def runClaimed(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, -Failure: Data, -Value: Data, +runtime: Runtime.Runtime<P, A, G, D, C, V, S, E, J>, listeners: Listeners.Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, claimed: Life.Claimed<Value>, execute: Life.Claimed<Value> -> IO(Result<&2, &2, Failure, Unit>), renderError: Failure -> String) -> IO(Result<&2, &2, Events.DeliveryError<Failure>, Unit>):
  match claimed:
    case Life.Claimed{+run, value}:
      do IO<Result<&2, &2, Events.DeliveryError<Failure>, Unit>>:
        result : Result<&2, &2, Failure, Unit> <- execute(Life.Claimed{run, value})
        outcome : Result<&2, &2, Events.DeliveryError<Failure>, Unit> <- recover(P, A, G, D, C, V, S, E, J, Partial, Execution, Failure, runtime, listeners, run, result, renderError)
        finished : Bool <- Runtime.finishRun(P, A, G, D, C, V, S, E, J, runtime, run)
        return outcome
