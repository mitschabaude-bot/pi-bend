import Base
import ./types.bend as T
import ./agent-state.bend as State
import ./agent-run.bend as Run
import ./agent-hooks.bend as Hooks
import ./stream-fn.bend as Provider
import ../../ai/src/types.bend as Ai
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/record.bend as Record

def Converter(-A: Data, -G: Data, -D: Data, -M: Data, -E: Data) -> Data: C.Callback<T.AgentMessageArray(Schema.Value, A, G, D, M), Result<&2, &2, E, List<&2, Ai.Message<Schema.Value, A, G, D>>>>
def Turn(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data) -> Data: T.ShouldStopAfterTurnContext<Schema.Value, A, G, D, M, V, Run.Signal(), E>
def Update(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data) -> Data: T.AgentLoopTurnUpdate<Schema.Value, A, G, D, M, V, Run.Signal(), E, J>
def TurnHooks(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data) -> Data: Hooks.Hooks<Turn(A, G, D, M, V, E), Update(A, G, D, M, V, E, J), E>
# streamFn is optional only for the source's legacy default-provider fallback.
type AgentOptions<-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data> is Data:
  AgentOptions{initialState: Maybe<&2, State.AgentInitialState<Schema.Value, A, G, D, M, V, Run.Signal(), E, J>>, convertToLlm: Maybe<&2, Converter(A, G, D, M, E)>, transformContext: Maybe<&2, C.Callback<T.TransformContextInput<T.AgentMessageArray(Schema.Value, A, G, D, M), Run.Signal()>, Result<&2, &2, E, T.AgentMessageArray(Schema.Value, A, G, D, M)>>>, streamFn: Maybe<&2, T.StreamFn(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)>, getApiKey: Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>, onPayload: Maybe<&2, Ai.PayloadCallback(J, Ai.Model<J>, E)>, onResponse: Maybe<&2, Ai.ResponseCallback(Ai.Model<J>, E)>, beforeToolCall: Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<Schema.Value, A, G, D, M, V, Run.Signal(), E>, Run.Signal()>, Result<&2, &2, E, T.BeforeToolCallUpdate<V, T.AgentContext<Schema.Value, A, G, D, M, V, Run.Signal(), E>>>>>, afterToolCall: Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<Schema.Value, A, G, D, M, V, Run.Signal(), E>, Run.Signal()>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>, shouldStopAfterTurn: Maybe<&2, Hooks.StopHook(Turn(A, G, D, M, V, E), E)>, prepareNextTurn: Maybe<&2, Hooks.LegacyHook(Update(A, G, D, M, V, E, J), E)>, prepareNextTurnWithContext: Maybe<&2, Hooks.ContextHook(Turn(A, G, D, M, V, E), Update(A, G, D, M, V, E, J), E)>, steeringMode: Maybe<&2, T.QueueMode>, followUpMode: Maybe<&2, T.QueueMode>, sessionId: Maybe<&2, String>, thinkingBudgets: Maybe<&2, Ai.ThinkingBudgets>, transport: Maybe<&2, Ai.Transport>, maxRetryDelayMs: Maybe<&2, F.F64>, toolExecution: Maybe<&2, T.ToolExecutionMode>}
def defaults(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data) -> AgentOptions<A, G, D, M, V, E, J, Telemetry, Fetch>:
  AgentOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}
type Resolved<-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Resolved{initialState: State.AgentInitialState<Schema.Value, A, G, D, M, V, Run.Signal(), E, J>, config: Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), streamFn: T.StreamFn(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E), hooks: TurnHooks(A, G, D, M, V, E, J), steeringMode: T.QueueMode, followUpMode: T.QueueMode, ownedConverter: Maybe<&2, Converter(A, G, D, M, E)>}
type Converted<-A: Data, -G: Data, -D: Data, -M: Data, -E: Data> is Data:
  Converted{callback: Converter(A, G, D, M, E), owned: Maybe<&2, Converter(A, G, D, M, E)>}
def convert(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, unused: Unit, messages: List<&2, Run.Message(A, G, D, M)>) -> IO(Result<&2, &2, E, List<&2, Ai.Message<Schema.Value, A, G, D>>>):
  IO.pure(Result<&2, &2, E, List<&2, Ai.Message<Schema.Value, A, G, D>>>, Done{State.defaultConvertToLlm(Schema.Value, A, G, D, M, V, Run.Signal(), E, J, messages)})
def converter(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, supplied: Maybe<&2, Converter(A, G, D, M, E)>) -> IO(Converted<A, G, D, M, E>):
  match supplied:
    case Some{callback}: IO.pure(Converted<A, G, D, M, E>, Converted{callback, None{}})
    case None{}:
      do IO<Converted<A, G, D, M, E>>:
        +callback : Converter(A, G, D, M, E) <- C.create(~Unit, ~List<&2, Run.Message(A, G, D, M)>, ~Result<&2, &2, E, List<&2, Ai.Message<Schema.Value, A, G, D>>>, ~(convert(A, G, D, M, V, E, J)), Unit{})
        return Converted{callback, Some{callback}}
def providerSelection(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, callback: Maybe<&2, T.StreamFn(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)>, fallback: Provider.Registry(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)) -> Provider.Selection<Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E>:
  match callback:
    case Some{value}: Provider.Explicit{value}
    case None{}: Provider.Fallback{fallback}
def finish(-A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -E: Data, -J: Data, -Telemetry: Data, -Fetch: Data, initial: Maybe<&2, State.AgentInitialState<Schema.Value, A, G, D, M, V, Run.Signal(), E, J>>, converted: Converted<A, G, D, M, E>, stream: T.StreamFn(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E), hooks: TurnHooks(A, G, D, M, V, E, J), steering: Maybe<&2, T.QueueMode>, follow: Maybe<&2, T.QueueMode>, transformContext: Maybe<&2, C.Callback<T.TransformContextInput<T.AgentMessageArray(Schema.Value, A, G, D, M), Run.Signal()>, Result<&2, &2, E, T.AgentMessageArray(Schema.Value, A, G, D, M)>>>, getApiKey: Maybe<&2, C.Callback<String, Result<&2, &2, E, Maybe<&2, String>>>>, onPayload: Maybe<&2, Ai.PayloadCallback(J, Ai.Model<J>, E)>, onResponse: Maybe<&2, Ai.ResponseCallback(Ai.Model<J>, E)>, beforeToolCall: Maybe<&2, C.Callback<T.ToolHookInput<T.BeforeToolCallContext<Schema.Value, A, G, D, M, V, Run.Signal(), E>, Run.Signal()>, Result<&2, &2, E, T.BeforeToolCallUpdate<V, T.AgentContext<Schema.Value, A, G, D, M, V, Run.Signal(), E>>>>>, afterToolCall: Maybe<&2, C.Callback<T.ToolHookInput<T.AfterToolCallContext<Schema.Value, A, G, D, M, V, Run.Signal(), E>, Run.Signal()>, Result<&2, &2, E, Maybe<&2, T.AfterToolCallResult<D>>>>>, sessionId: Maybe<&2, String>, thinkingBudgets: Maybe<&2, Ai.ThinkingBudgets>, transport: Maybe<&2, Ai.Transport>, maxRetryDelayMs: Maybe<&2, F.F64>, toolExecution: Maybe<&2, T.ToolExecutionMode>) -> IO(Result<&2, &2, Provider.MissingDefault, Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>>):
  match converted:
    case Converted{callback, owned}: IO.pure(Result<&2, &2, Provider.MissingDefault, Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>>, Done{Resolved{Maybe.default(&2, State.AgentInitialState<Schema.Value, A, G, D, M, V, Run.Signal(), E, J>, initial, State.AgentInitialState{None{}, None{}, None{}, None{}, None{}}), T.AgentLoopConfig{None{}, None{}, None{}, None{}, None{}, onPayload, onResponse, None{}, None{}, None{}, maxRetryDelayMs, None{}, None{}, None{}, Some{Maybe.default(&2, Ai.Transport, transport, Ai.AutoTransport{})}, None{}, sessionId, None{}, None{}, None{}, None{}, None{}, thinkingBudgets, State.defaultModel(J), callback, transformContext, getApiKey, None{}, None{}, None{}, None{}, Some{Maybe.default(&2, T.ToolExecutionMode, toolExecution, T.Parallel{})}, beforeToolCall, afterToolCall}, stream, hooks, Maybe.default(&2, T.QueueMode, steering, T.OneAtATime{}), Maybe.default(&2, T.QueueMode, follow, T.OneAtATime{}), owned}})
def resolved(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, options: AgentOptions<A, G, D, M, V, E, J, Telemetry, Fetch>, provider: Result<&2, &2, Provider.MissingDefault, T.StreamFn(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)>) -> IO(Result<&2, &2, Provider.MissingDefault, Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>>):
  match options provider:
    case _ Fail{error}: IO.pure(Result<&2, &2, Provider.MissingDefault, Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>>, Fail{error})
    case AgentOptions{initialState, convertToLlm, transformContext, streamFn, getApiKey, onPayload, onResponse, beforeToolCall, afterToolCall, shouldStopAfterTurn, prepareNextTurn, prepareNextTurnWithContext, steeringMode, followUpMode, sessionId, thinkingBudgets, transport, maxRetryDelayMs, toolExecution} Done{stream}:
      do IO<Result<&2, &2, Provider.MissingDefault, Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>>>:
        converted : Converted<A, G, D, M, E> <- converter(~A, ~G, ~D, ~M, ~V, ~E, ~J, convertToLlm)
        finish(A, G, D, M, V, E, J, Telemetry, Fetch, initialState, converted, stream, Hooks.Hooks{shouldStopAfterTurn, prepareNextTurn, prepareNextTurnWithContext}, steeringMode, followUpMode, transformContext, getApiKey, onPayload, onResponse, beforeToolCall, afterToolCall, sessionId, thinkingBudgets, transport, maxRetryDelayMs, toolExecution)
# Resolve fallback at construction, preserving the selected callback for runs.
def resolve(~A: Data, ~G: Data, ~D: Data, ~M: Data, ~V: Data, ~E: Data, ~J: Data, ~Telemetry: Data, ~Fetch: Data, +options: AgentOptions<A, G, D, M, V, E, J, Telemetry, Fetch>, fallback: Provider.Registry(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)) -> IO(Result<&2, &2, Provider.MissingDefault, Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>>):
  match options:
    case AgentOptions{_, _, _, streamFn, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      do IO<Result<&2, &2, Provider.MissingDefault, Resolved<A, G, D, M, V, E, J, Telemetry, Fetch>>>:
        provider : Result<&2, &2, Provider.MissingDefault, T.StreamFn(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E)> <- Provider.resolve(Schema.Value, A, G, D, J, Run.Config(A, G, D, M, V, E, J, Telemetry, Fetch), E, providerSelection(A, G, D, M, V, E, J, Telemetry, Fetch, streamFn, fallback))
        resolved(~A, ~G, ~D, ~M, ~V, ~E, ~J, ~Telemetry, ~Fetch, options, provider)
