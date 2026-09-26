import Base
import ./types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/api/openai-responses.bend as Responses
import ../../ai/src/api/azure-openai-responses.bend as Azure
import ../../ai/src/api/openai-codex-responses.bend as Codex
import ../../ai/src/utils/event-stream.bend as Stream
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/callback.bend as C

# Provider integration belongs here: pi-ai does not depend on the agent.
# Options remains the caller's complete configuration snapshot; project selects
# its provider fields without changing the configuration seen by injected streams.
def Input(-Options: Data, -Diagnostics: Data, -Details: Data) -> Data:
  T.StreamInput<Diagnostics, Details, Options>

def Output(-Diagnostics: Data, -Error: Data) -> Type:
  Result<&2, &1, Error, T.StreamLease<Diagnostics, Error>>

# A failed provider already delivered its terminal error message through the
# stream. Preserve that failure; only a cleanup failure after success is new.
def released(~Diagnostics: Data, ~Error: Data, ~failure: Responses.Error<Unit, Error> -> Error, result: Responses.RunResult<Unit, Diagnostics, Error>) -> Result<&2, &2, Error, Unit>:
  match result:
    case Responses.RunResult{Responses.Failed{_, _, _}, _}: Done{Unit{}}
    case Responses.RunResult{_, None{}}: Done{Unit{}}
    case Responses.RunResult{_, Some{cause}}: Fail{failure(cause)}

def release(~Diagnostics: Data, ~Error: Data, ~failure: Responses.Error<Unit, Error> -> Error, owner: Responses.Run<Unit, Diagnostics, Error>) -> IO(Result<&2, &2, Error, Unit>):
  do IO<Result<&2, &2, Error, Unit>>:
    result : Responses.RunResult<Unit, Diagnostics, Error> <- Responses.dispose(Unit, Diagnostics, Error, owner)
    return released(~Diagnostics, ~Error, ~failure, result)

def lease(~Diagnostics: Data, ~Error: Data, ~failure: Responses.Error<Unit, Error> -> Error, pair: Responses.Run<Unit, Diagnostics, Error> & Stream.AssistantMessageEventStream(V.Value, Diagnostics)) -> Output(Diagnostics, Error):
  match pair:
    case (owner, events): Done{T.StreamLease{events, release(~Diagnostics, ~Error, ~failure, owner)}}

# A streamSimple that failed before a stream existed (upstream throws) is the
# provider call's failure; no stream is leased.
def leased(~Diagnostics: Data, ~Error: Data, ~failure: Responses.Error<Unit, Error> -> Error, started: Responses.SimpleRun(Unit, Diagnostics, Error)) -> Output(Diagnostics, Error):
  match started:
    case Fail{cause}: Fail{failure(Responses.PreparationFailure{cause})}
    case Done{owner}: lease(~Diagnostics, ~Error, ~failure, Responses.borrow(Unit, Diagnostics, Error, owner))

def apiOf(model: Ai.Model<Ai.JsonValue>) -> Ai.ModelApi:
  match model:
    case Ai.Model{_, _, api, _, _, _, _, _, _, _, _, _, _, _, _, _}: api

# The Responses APIs share one request preparation; Azure prepares its own
# requests and Codex runs its own SSE request lifecycle. The OpenAI Responses
# provider rejects any other API.
def streamSimple(~Telemetry: Data, ~Diagnostics: Data, ~Details: Data, ~Error: Data, ~render: Error -> String, config: Responses.Config, api: Ai.ModelApi, model: Ai.Model<Ai.JsonValue>, context: Ai.TranscriptContext<V.Value, V.Value, Diagnostics, Details>, options: Maybe<&2, Responses.SimpleStreamOptions(Unit, Telemetry, Error)>) -> IO(Responses.SimpleRun(Unit, Diagnostics, Error)):
  match api:
    case Ai.AzureOpenAIResponsesApi{}: Azure.streamSimple(~Unit, ~Telemetry, ~Diagnostics, ~Details, ~Error, ~render, config, model, context, options)
    case Ai.OpenAICodexResponsesApi{}: Codex.streamSimple(~Unit, ~Telemetry, ~Diagnostics, ~Details, ~Error, ~render, config, model, context, options)
    case _: Responses.streamSimple(~Unit, ~Telemetry, ~Diagnostics, ~Details, ~Error, ~render, config, model, context, options)

def openResponses(~Options: Data, ~Telemetry: Data, ~Diagnostics: Data, ~Details: Data, ~Error: Data, ~project: Options -> Responses.SimpleStreamOptions(Unit, Telemetry, Error), ~render: Error -> String, ~failure: Responses.Error<Unit, Error> -> Error, config: Responses.Config, input: Input(Options, Diagnostics, Details)) -> IO(Output(Diagnostics, Error)):
  match input:
    case T.StreamInput{+model, context, options}:
      do IO<Output(Diagnostics, Error)>:
        started : Responses.SimpleRun(Unit, Diagnostics, Error) <- streamSimple(~Telemetry, ~Diagnostics, ~Details, ~Error, ~render, config, apiOf(model), model, context, Maybe.map(&2, Options, Responses.SimpleStreamOptions(Unit, Telemetry, Error), project, options))
        return leased(~Diagnostics, ~Error, ~failure, started)

# Each call owns one run. The affine release captures that owner directly and
# the loop executes it after its final read; no reaper or shared owner slot is
# needed. Dispose the returned callback after all calls have finished. TLS
# authorizers and other callbacks in config remain borrowed for that lifetime.
def responses(~Options: Data, ~Telemetry: Data, ~Diagnostics: Data, ~Details: Data, ~Error: Data, ~project: Options -> Responses.SimpleStreamOptions(Unit, Telemetry, Error), ~render: Error -> String, ~failure: Responses.Error<Unit, Error> -> Error, config: Responses.Config) -> IO(T.StreamFn(Diagnostics, Details, Options, Error)):
  C.create(~Responses.Config, ~Input(Options, Diagnostics, Details), ~Output(Diagnostics, Error), ~(openResponses(~Options, ~Telemetry, ~Diagnostics, ~Details, ~Error, ~project, ~render, ~failure)), config)
