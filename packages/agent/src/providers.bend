import Base
import ./types.bend as T
import ../../ai/src/api/openai-responses.bend as Responses
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

def openResponses(~Options: Data, ~Telemetry: Data, ~Diagnostics: Data, ~Details: Data, ~Error: Data, ~project: Options -> Responses.SimpleStreamOptions(Unit, Telemetry, Error), ~render: Error -> String, ~failure: Responses.Error<Unit, Error> -> Error, config: Responses.Config, input: Input(Options, Diagnostics, Details)) -> IO(Output(Diagnostics, Error)):
  match input:
    case T.StreamInput{model, context, options}:
      do IO<Output(Diagnostics, Error)>:
        owner : Responses.Run<Unit, Diagnostics, Error> <- Responses.streamSimple(~Unit, ~Telemetry, ~Diagnostics, ~Details, ~Error, ~render, config, model, context, Maybe.map(&2, Options, Responses.SimpleStreamOptions(Unit, Telemetry, Error), project, options))
        return lease(~Diagnostics, ~Error, ~failure, Responses.borrow(Unit, Diagnostics, Error, owner))

# Each call owns one run. The affine release captures that owner directly and
# the loop executes it after its final read; no reaper or shared owner slot is
# needed. Dispose the returned callback after all calls have finished. TLS
# authorizers and other callbacks in config remain borrowed for that lifetime.
def responses(~Options: Data, ~Telemetry: Data, ~Diagnostics: Data, ~Details: Data, ~Error: Data, ~project: Options -> Responses.SimpleStreamOptions(Unit, Telemetry, Error), ~render: Error -> String, ~failure: Responses.Error<Unit, Error> -> Error, config: Responses.Config) -> IO(T.StreamFn(Diagnostics, Details, Options, Error)):
  C.create(~Responses.Config, ~Input(Options, Diagnostics, Details), ~Output(Diagnostics, Error), ~(openResponses(~Options, ~Telemetry, ~Diagnostics, ~Details, ~Error, ~project, ~render, ~failure)), config)
