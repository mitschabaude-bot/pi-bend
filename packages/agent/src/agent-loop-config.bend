import Base
import ./types.bend as T
import ./agent-runtime.bend as Runtime
import ./agent-queues.bend as Q
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R

# Queue readers belong to one run. Other configuration callbacks are borrowed.
# Drain loop work before disposing these readers; the Agent owner outlives them.
type Steering<-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data> is Data:
  Steering{runtime: Runtime.Runtime<P, A, G, D, M, V, S, E, J>, skip: R.Ref<Bool>}
type Pollers<-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data> is Data:
  Pollers{steering: C.Callback<Unit, Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>>, followUp: C.Callback<Unit, Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>>, skip: R.Ref<Bool>}
def queue(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime.Runtime<P, A, G, D, M, V, S, E, J>, kind: Q.QueueKind) -> IO(Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>):
  do IO<Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>>:
    messages : List<&2, T.AgentMessage<P, A, G, D, M>> <- Runtime.drain(P, A, G, D, M, V, S, E, J, runtime, kind)
    return Done{messages}
def steeringReady(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime.Runtime<P, A, G, D, M, V, S, E, J>, skip: Bool) -> IO(Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>):
  match skip:
    case True{}: IO.pure(Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>, Done{Nil{}})
    case False{}: queue(P, A, G, D, M, V, S, E, J, runtime, Q.Steering{})
def steeringBody(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, capture: Steering<P, A, G, D, M, V, S, E, J>, unused: Unit) -> IO(Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>):
  match capture:
    case Steering{runtime, skip}:
      do IO<Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>>:
        previous : Bool <- R.swap(Bool, skip, False{})
        steeringReady(P, A, G, D, M, V, S, E, J, runtime, previous)
def followUpBody(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime.Runtime<P, A, G, D, M, V, S, E, J>, unused: Unit) -> IO(Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>): queue(P, A, G, D, M, V, S, E, J, runtime, Q.FollowUp{})
def new(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~S: Data, ~E: Data, ~J: Data, +runtime: Runtime.Runtime<P, A, G, D, M, V, S, E, J>, skipInitialSteeringPoll: Bool) -> IO(Pollers<P, A, G, D, M, V, S, E, J>):
  do IO<Pollers<P, A, G, D, M, V, S, E, J>>:
    +skip : R.Ref<Bool> <- R.new(Bool, skipInitialSteeringPoll)
    steering : C.Callback<Unit, Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>> <- C.create(~Steering<P, A, G, D, M, V, S, E, J>, ~Unit, ~Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>, ~(steeringBody(P, A, G, D, M, V, S, E, J)), Steering{runtime, skip})
    followUp : C.Callback<Unit, Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>> <- C.create(~Runtime.Runtime<P, A, G, D, M, V, S, E, J>, ~Unit, ~Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>, ~(followUpBody(P, A, G, D, M, V, S, E, J)), runtime)
    return Pollers{steering, followUp, skip}
def thinkingReasoning(thinking: T.ThinkingLevel()) -> Maybe<&2, Ai.ThinkingLevel>:
  match thinking:
    case Ai.Off{}: None{}
    case Ai.Thinking{level}: Some{level}
def context(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, state: T.AgentState<P, A, G, D, M, V, S, E, J>) -> T.AgentContext<P, A, G, D, M, V, S, E>:
  match state:
    case T.AgentState{_, _, tools, messages, _, _, _, _}: T.AgentContext{messages, Some{tools}}
# Keep the configured options/hooks while taking model/thinking and transcript
# from one immutable Agent snapshot. The public options adapter builds the base.
def bind(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, state: T.AgentState<P, A, G, D, M, V, S, E, J>, base: T.AgentLoopConfig<P, A, G, D, M, V, S, E, J, Telemetry, Fetch>, readers: Pollers<P, A, G, D, M, V, S, E, J>) -> T.AgentLoopConfig<P, A, G, D, M, V, S, E, J, Telemetry, Fetch>:
  match state base readers:
    case T.AgentState{currentModel, thinking, _, _, _, _, _, _} T.AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, thinkingBudgets, model, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, getSteeringMessages, getFollowUpMessages, toolExecution, beforeToolCall, afterToolCall} Pollers{steering, followUp, _}:
      T.AgentLoopConfig{signal, telemetryContext, apiKey, fetch, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, thinkingReasoning(thinking), deferred, thinkingBudgets, currentModel, convertToLlm, transformContext, getApiKey, shouldStopAfterTurn, prepareNextTurn, Some{steering}, Some{followUp}, toolExecution, beforeToolCall, afterToolCall}
type Snapshot<-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Snapshot{context: T.AgentContext<P, A, G, D, M, V, S, E>, config: T.AgentLoopConfig<P, A, G, D, M, V, S, E, J, Telemetry, Fetch>}
def snapshot(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, runtime: Runtime.Runtime<P, A, G, D, M, V, S, E, J>, base: T.AgentLoopConfig<P, A, G, D, M, V, S, E, J, Telemetry, Fetch>, readers: Pollers<P, A, G, D, M, V, S, E, J>) -> IO(Snapshot<P, A, G, D, M, V, S, E, J, Telemetry, Fetch>):
  do IO<Snapshot<P, A, G, D, M, V, S, E, J, Telemetry, Fetch>>:
    +state : T.AgentState<P, A, G, D, M, V, S, E, J> <- Runtime.read(P, A, G, D, M, V, S, E, J, runtime)
    return Snapshot{context(P, A, G, D, M, V, S, E, J, state), bind(P, A, G, D, M, V, S, E, J, Telemetry, Fetch, state, base, readers)}
def dispose(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, readers: Pollers<P, A, G, D, M, V, S, E, J>) -> IO(Unit):
  match readers:
    case Pollers{steering, followUp, skip}:
      do IO<Unit>:
        C.dispose(Unit, Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>, steering)
        C.dispose(Unit, Result<&2, &2, E, List<&2, T.AgentMessage<P, A, G, D, M>>>, followUp)
        ignored : Bool <- R.dispose(Bool, skip)
        return Unit{}
