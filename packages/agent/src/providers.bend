import Base
import ./types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/api/openai-responses.bend as Responses
import ../../ai/src/utils/event-stream.bend as Stream
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/callback.bend as C

# Provider integration belongs here: pi-ai does not depend on the agent.
# Options remains the caller's complete configuration snapshot; project selects
# its provider fields without changing the configuration seen by injected streams.
def Input(-Options: Data, -Diagnostics: Data, -Details: Data) -> Data:
  T.StreamInput<V.Value, V.Value, Diagnostics, Details, Ai.JsonValue, Options>

def Output(-Diagnostics: Data, -Error: Data) -> Type:
  Result<&2, &1, Error, T.StreamLease<V.Value, Diagnostics, Error>>

# A failed provider already delivered its terminal error message through the
# stream. Preserve that failure; only a cleanup failure after success is new.
def released(~Reason: Data, ~Diagnostics: Data, ~Error: Data, ~failure: Responses.Error<Reason, Error> -> Error, result: Responses.RunResult<Reason, Diagnostics, Error>) -> Result<&2, &2, Error, Unit>:
  match result:
    case Responses.RunResult{Responses.Failed{_, _, _}, _}: Done{Unit{}}
    case Responses.RunResult{_, None{}}: Done{Unit{}}
    case Responses.RunResult{_, Some{cause}}: Fail{failure(cause)}

def release(~Reason: Data, ~Diagnostics: Data, ~Error: Data, ~failure: Responses.Error<Reason, Error> -> Error, owner: Responses.Run<Reason, Diagnostics, Error>) -> IO(Result<&2, &2, Error, Unit>):
  do IO<Result<&2, &2, Error, Unit>>:
    result : Responses.RunResult<Reason, Diagnostics, Error> <- Responses.dispose(Reason, Diagnostics, Error, owner)
    return released(~Reason, ~Diagnostics, ~Error, ~failure, result)

def lease(~Reason: Data, ~Diagnostics: Data, ~Error: Data, ~failure: Responses.Error<Reason, Error> -> Error, pair: Responses.Run<Reason, Diagnostics, Error> & Stream.AssistantMessageEventStream(V.Value, Diagnostics)) -> Output(Diagnostics, Error):
  match pair:
    case (owner, events): Done{T.StreamLease{events, release(~Reason, ~Diagnostics, ~Error, ~failure, owner)}}

def openResponses(~Options: Data, ~Reason: Data, ~Telemetry: Data, ~Diagnostics: Data, ~Details: Data, ~Error: Data, ~project: Options -> Responses.SimpleStreamOptions(Reason, Telemetry, Error), ~render: Error -> String, ~failure: Responses.Error<Reason, Error> -> Error, config: Responses.Config, input: Input(Options, Diagnostics, Details)) -> IO(Output(Diagnostics, Error)):
  match input:
    case T.StreamInput{model, context, options}:
      do IO<Output(Diagnostics, Error)>:
        owner : Responses.Run<Reason, Diagnostics, Error> <- Responses.streamSimple(~Reason, ~Telemetry, ~Diagnostics, ~Details, ~Error, ~render, config, model, context, Maybe.map(&2, Options, Responses.SimpleStreamOptions(Reason, Telemetry, Error), project, options))
        return lease(~Reason, ~Diagnostics, ~Error, ~failure, Responses.borrow(Reason, Diagnostics, Error, owner))

# Each call owns one run. The affine release captures that owner directly and
# the loop executes it after its final read; no reaper or shared owner slot is
# needed. Dispose the returned callback after all calls have finished. TLS
# authorizers and other callbacks in config remain borrowed for that lifetime.
def responses(~Options: Data, ~Reason: Data, ~Telemetry: Data, ~Diagnostics: Data, ~Details: Data, ~Error: Data, ~project: Options -> Responses.SimpleStreamOptions(Reason, Telemetry, Error), ~render: Error -> String, ~failure: Responses.Error<Reason, Error> -> Error, config: Responses.Config) -> IO(T.StreamFn(V.Value, V.Value, Diagnostics, Details, Ai.JsonValue, Options, Error)):
  C.create(~Responses.Config, ~Input(Options, Diagnostics, Details), ~Output(Diagnostics, Error), ~(openResponses(~Options, ~Reason, ~Telemetry, ~Diagnostics, ~Details, ~Error, ~project, ~render, ~failure)), config)
