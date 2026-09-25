import Base
import ../types.bend as T
import ../utils/event-stream.bend as Events
import ../utils/headers.bend as ProviderHeaders
import ../utils/provider-retry.bend as Retry
import ../utils/schema-json.bend as Convert
import ./openai-client.bend as Client
import ./openai-sse.bend as Sse
import ./openai-completions-stream.bend as Fold
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-response.bend as Metadata
import ../../../runtime/src/http-response.bend as Progress
import ../../../runtime/src/random.bend as Seed
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/url.bend as URL

# The request lifecycle of upstream `stream` (openai-completions.ts) over the
# OpenAI SDK port: `client.chat.completions.create` with SDK retries disabled
# inside retryProviderRequest, onPayload/onResponse, the SDK's SSE message
# stream, the chunk fold (openai-completions-stream.bend) and the catch
# block's error message.

def Signal(-Reason: Data) -> Data: Abort.AbortSignal<Reason>
def EventStream(-G: Data) -> Data: Events.AssistantMessageEventStream(V.Value, G)
def J() -> Data: T.JsonValue

# Client
# ------

def nonempty(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: None{}

# upstream getClientApiKey: header-owned auth (Authorization or
# cf-aig-authorization) sends the placeholder key "unused".
def headerKey(+provider: String, +headers: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, String, String>:
  Bool.pick(Result<&2, &2, String, String>, ProviderHeaders.hasHeader(headers, "authorization") || ProviderHeaders.hasHeader(headers, "cf-aig-authorization"), Done{"unused"}, Fail{"No API key for provider: " ++ provider})

def getClientApiKey(provider: String, apiKey: Maybe<&2, String>, headers: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, String, String>:
  match apiKey:
    case Some{SCon{c, cs}}: Done{SCon{c, cs}}
    case _: headerKey(provider, headers)

# createClient's default headers: pi's User-Agent, the model's headers, then
# the session-affinity and option headers (Request.clientHeaders).
def defaultHeaders(agent: String, modelHeaders: Maybe<&2, R.Record<String>>, requestHeaders: Maybe<&2, T.ProviderHeaders()>) -> T.ProviderHeaders():
  ProviderHeaders.overlay(ProviderHeaders.overlayStrings(ProviderHeaders.fromRecord(R.Record{R.Property{"User-Agent", agent} <> Nil{}}), modelHeaders), requestHeaders)

# Failures
# --------

type Failure<-Reason: Data, -E: Data> is Data:
  Unauthorized{message: String}
  PreparationFailure{message: String}
  HookFailure{cause: E}
  RequestRejected{cause: Client.RequestError}
  InvalidRetryOptions{cause: Retry.OptionsError}
  EntropyFailure{cause: Seed.SeedError}
  RequestFailure{cause: Retry.RetryFailure<Client.AttemptError<Reason>>}
  StreamFailure{cause: Sse.Error<Sse.TransportError(Reason)>}
  DisposalFailure{cause: Sse.CloseError<Reason>}

def describeRetryOptions(cause: Retry.OptionsError) -> String:
  match cause:
    case Retry.InvalidRetryCount{_}: "maxRetries must be a non-negative integer within the native natural-number range"
    case Retry.InvalidDelayLimit{_}: "maxRetryDelayMs must be finite and non-negative"

# The OpenAI SDK error's parsed `error` object, if any.
def attemptErrorObject(-Reason: Data, error: Client.AttemptError<Reason>) -> Maybe<&2, J()>:
  match error:
    case Client.HTTPFailure{Client.APIError{_, Client.JSONDiagnostic{value}, _}}: Some{value}
    case _: None{}

def retryErrorObject(-Reason: Data, error: Retry.RetryFailure<Client.AttemptError<Reason>>) -> Maybe<&2, J()>:
  match error:
    case Retry.RequestFailed{Retry.Other{cause}}: attemptErrorObject(Reason, cause)
    case Retry.RequestFailed{Retry.Provider{Retry.ProviderError{cause, _, _, _, _, _}}}: attemptErrorObject(Reason, cause)
    case _: None{}

def streamErrorObject(-Reason: Data, error: Sse.Error<Sse.TransportError(Reason)>) -> Maybe<&2, J()>:
  match error:
    case Sse.DispatchFailure{Sse.ApiErrorPayload{value}}: Some{Convert.toJson(value)}
    case _: None{}

def jsonField(value: Maybe<&2, J()>, name: String) -> Maybe<&2, J()>:
  match value:
    case Some{T.JsonObject{fields}}: R.get(J(), fields, name)
    case _: None{}

def rawText(value: Maybe<&2, J()>) -> Maybe<&2, String>:
  match value:
    case Some{T.JsonString{SCon{c, cs}}}: Some{SCon{c, cs}}
    case _: None{}

# OpenRouter puts the upstream provider's text in error.metadata.raw.
def withRaw(+message: String, raw: Maybe<&2, String>) -> String:
  match raw:
    case Some{+text}: Bool.pick(String, String.contains(message, text), message, message ++ "\n" ++ text)
    case None{}: message

def withMetadata(+message: String, error: Maybe<&2, J()>) -> String:
  withRaw(message, rawText(jsonField(jsonField(error, "metadata"), "raw")))

# The catch block's errorMessage: formatProviderError(normalizeProviderError(
# error)) with no prefix, plus OpenRouter's raw metadata.
def describe(~Reason: Data, ~E: Data, ~render: E -> String, failure: Failure<Reason, E>) -> String:
  match failure:
    case Unauthorized{message}: message
    case PreparationFailure{message}: message
    case HookFailure{cause}: render(cause)
    case RequestRejected{cause}: Client.describeRequest(cause)
    case InvalidRetryOptions{cause}: describeRetryOptions(cause)
    case EntropyFailure{cause}: Client.describeEntropy(cause)
    case RequestFailure{+cause}: withMetadata(Client.describeRetry(Reason, cause, None{}), retryErrorObject(Reason, cause))
    case StreamFailure{+cause}: withMetadata(Sse.describeStreaming(Reason, cause), streamErrorObject(Reason, cause))
    case DisposalFailure{_}: "Could not close the response body"

# Publishing
# ----------

def publish(-G: Data, +events: EventStream(G), values: List<&2, T.AssistantMessageEvent<V.Value, G>>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case event <> rest:
      do IO<Unit>:
        Events.push(T.AssistantMessageEvent<V.Value, G>, T.AssistantMessage<V.Value, G>, events, event)
        publish(G, events, rest)

def lastMessage(-G: Data, state: Fold.State<G>) -> T.AssistantMessage<V.Value, G>: Fold.stateMessage(G, state)

def settleFailed(-G: Data, +events: EventStream(G), step: Fold.Step<G>) -> IO(Unit):
  match step:
    case Fold.Step{state, values, _}:
      do IO<Unit>:
        publish(G, events, values)
        Events.end(T.AssistantMessageEvent<V.Value, G>, T.AssistantMessage<V.Value, G>, events, Some{lastMessage(G, state)})

# Publish a step's events; a thrown error ends the run through the catch block.
def settleStep(-G: Data, +events: EventStream(G), step: Fold.Step<G>, aborted: Bool) -> IO(Unit):
  match step:
    case Fold.Step{state, values, None{}}:
      do IO<Unit>:
        publish(G, events, values)
        Events.end(T.AssistantMessageEvent<V.Value, G>, T.AssistantMessage<V.Value, G>, events, Some{lastMessage(G, state)})
    case Fold.Step{state, values, Some{message}}:
      do IO<Unit>:
        publish(G, events, values)
        settleFailed(G, events, Fold.failedWith(G, state, message, aborted))

def failWith(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), state: Fold.State<G>, parent: Signal(Reason), failure: Failure<Reason, E>) -> IO(Unit):
  do IO<Unit>:
    aborted : Bool <- Abort.aborted(Reason, parent)
    settleFailed(G, events, Fold.failedWith(G, state, describe(~Reason, ~E, ~render, failure), aborted))

# Streaming
# ---------

def TransportError(-Reason: Data) -> Data: Sse.TransportError(Reason)

type Run<-Reason: Data, -G: Data> is Type:
  Run{body: Sse.Body(Reason), cursor: Sse.Cursor<TransportError(Reason)>, state: Fold.State<G>}

def messageData(message: Sse.Message) -> V.Value:
  match message:
    case Sse.JsonMessage{data}: data
    case Sse.EventMessage{_, data}: data

type Pulled<-Reason: Data, -G: Data> is Type:
  Pulled{run: Run<Reason, G>, result: Result<&2, &2, Sse.Error<TransportError(Reason)>, Maybe<&2, Sse.Message>>}

def pulled(-Reason: Data, -G: Data, body: Sse.Body(Reason), state: Fold.State<G>, next: Sse.Next<TransportError(Reason)>) -> Pulled<Reason, G>:
  match next:
    case Sse.Next{cursor, result}: Pulled{Run{body, cursor, state}, result}

def pull(~Reason: Data, ~G: Data, run: Run<Reason, G>) -> IO(Pulled<Reason, G>):
  match run:
    case Run{body, cursor, state}:
      do IO<Pulled<Reason, G>>:
        next : Sse.Next<TransportError(Reason)> <- Sse.next(TransportError(Reason), cursor)
        return pulled(Reason, G, body, state, next)

# The stream loop's outcome: the fold's final step, or a transport failure.
type Ended<-Reason: Data, -G: Data> is Type:
  Ended{run: Run<Reason, G>, step: Fold.Step<G>, failure: Maybe<&2, Sse.Error<TransportError(Reason)>>}

def withState(-Reason: Data, -G: Data, run: Run<Reason, G>, state: Fold.State<G>) -> Run<Reason, G>:
  match run:
    case Run{body, cursor, _}: Run{body, cursor, state}

def runState(-Reason: Data, -G: Data, run: Run<Reason, G>) -> Run<Reason, G> & Fold.State<G>:
  match run:
    case Run{body, cursor, +state}: (Run{body, cursor, state}, state)

def failedPull(-Reason: Data, -G: Data, pair: Run<Reason, G> & Fold.State<G>, cause: Sse.Error<TransportError(Reason)>) -> Ended<Reason, G>:
  match pair:
    case (kept, state): Ended{kept, Fold.unchanged(G, state), Some{cause}}

def finished(~Reason: Data, ~G: Data, +settings: Fold.Settings, +parent: Signal(Reason), pair: Run<Reason, G> & Fold.State<G>) -> IO(Ended<Reason, G>):
  match pair:
    case (kept, state):
      do IO<Ended<Reason, G>>:
        aborted : Bool <- Abort.aborted(Reason, parent)
        return Ended{kept, Fold.finish(G, state, settings, aborted), None{}}

def chunked(-Reason: Data, -G: Data, +settings: Fold.Settings, pair: Run<Reason, G> & Fold.State<G>, message: Sse.Message) -> Run<Reason, G> & Fold.Step<G>:
  match pair:
    case (kept, state): (kept, Fold.chunk(G, state, messageData(message), settings))

type Drive<-Reason: Data, -G: Data> is Type:
  Pulling{pulled: Pulled<Reason, G>}
  Stepping{pair: Run<Reason, G> & Fold.Step<G>}

@unsafe def loop(~Reason: Data, ~G: Data, +events: EventStream(G), +settings: Fold.Settings, +parent: Signal(Reason), current: Drive<Reason, G>) -> IO(Ended<Reason, G>):
  match current:
    case Pulling{Pulled{run, Fail{cause}}}: IO.pure(Ended<Reason, G>, failedPull(Reason, G, runState(Reason, G, run), cause))
    case Pulling{Pulled{run, Done{None{}}}}: finished(~Reason, ~G, settings, parent, runState(Reason, G, run))
    case Pulling{Pulled{run, Done{Some{message}}}}: loop(~Reason, ~G, events, settings, parent, Stepping{chunked(Reason, G, settings, runState(Reason, G, run), message)})
    case Stepping{(run, Fold.Step{state, values, None{}})}:
      do IO<Ended<Reason, G>>:
        publish(G, events, values)
        next : Pulled<Reason, G> <- pull(~Reason, ~G, withState(Reason, G, run, state))
        loop(~Reason, ~G, events, settings, parent, Pulling{next})
    case Stepping{(run, thrown)}: IO.pure(Ended<Reason, G>, Ended{run, thrown, None{}})

def disposed(-Reason: Data, -G: Data, run: Run<Reason, G>) -> IO(Result<&2, &2, Sse.CloseError<Reason>, Unit>):
  match run:
    case Run{body, cursor, _}: Sse.dispose(Reason, body, cursor)

# A transport failure is reported through the catch block, after the events
# the fold already published.
def ended(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), value: Ended<Reason, G>) -> IO(Unit):
  match value:
    case Ended{run, step, None{}}:
      do IO<Unit>:
        closed : Result<&2, &2, Sse.CloseError<Reason>, Unit> <- disposed(Reason, G, run)
        aborted : Bool <- Abort.aborted(Reason, parent)
        settleStep(G, events, step, aborted)
    case Ended{run, Fold.Step{state, _, _}, Some{cause}}:
      do IO<Unit>:
        closed : Result<&2, &2, Sse.CloseError<Reason>, Unit> <- disposed(Reason, G, run)
        failWith(~Reason, ~E, ~G, ~render, events, state, parent, StreamFailure{cause})

def streamed(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +settings: Fold.Settings, +parent: Signal(Reason), state: Fold.State<G>, pair: Sse.Body(Reason) & Sse.Cursor<TransportError(Reason)>) -> IO(Unit):
  match pair:
    case (body, cursor):
      do IO<Unit>:
        first : Pulled<Reason, G> <- pull(~Reason, ~G, Run{body, cursor, state})
        result : Ended<Reason, G> <- loop(~Reason, ~G, events, settings, parent, Pulling{first})
        ended(~Reason, ~E, ~G, ~render, events, parent, result)

# onResponse sees the status and headers before any body is read; `start`
# follows it.
def providerResponse(+metadata: Metadata.Metadata) -> T.ProviderResponse:
  T.ProviderResponse{F.fromU32(Metadata.metadataStatus(metadata)), ProviderHeaders.headersToRecord(Metadata.headers(metadata))}

def started(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +settings: Fold.Settings, +parent: Signal(Reason), +state: Fold.State<G>, hooks: Sse.Hooks<TransportError(Reason)>, response: Response.Response<Client.State(Reason)>) -> IO(Unit):
  match response:
    case Response.Response{_, body}:
      do IO<Unit>:
        publish(G, events, T.Start{lastMessage(G, state)} <> Nil{})
        pair : Sse.Body(Reason) & Sse.Cursor<TransportError(Reason)> <- Sse.fromBody(~Reason, body, hooks, False{})
        streamed(~Reason, ~E, ~G, ~render, events, settings, parent, state, pair)

def hooked(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +settings: Fold.Settings, +parent: Signal(Reason), +state: Fold.State<G>, hooks: Sse.Hooks<TransportError(Reason)>, response: Response.Response<Client.State(Reason)>, result: Result<&2, &2, E, Unit>) -> IO(Unit):
  match result:
    case Fail{cause}:
      do IO<Unit>:
        released : Result<&2, &2, Progress.ResponseProgressError<Client.ReadError(Reason)>, Unit> <- Client.release(Reason, response)
        failWith(~Reason, ~E, ~G, ~render, events, state, parent, HookFailure{cause})
    case Done{_}: started(~Reason, ~E, ~G, ~render, events, settings, parent, state, hooks, response)

def responded(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +settings: Fold.Settings, +parent: Signal(Reason), +state: Fold.State<G>, hooks: Sse.Hooks<TransportError(Reason)>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, response: Response.Response<Client.State(Reason)>) -> IO(Unit):
  match hook response:
    case None{} value: hooked(~Reason, ~E, ~G, ~render, events, settings, parent, state, hooks, value, Done{Unit{}})
    case Some{callback} Response.Response{+metadata, body}:
      do IO<Unit>:
        result : Result<&2, &2, E, Unit> <- C.call(T.ResponseInput<T.Model<J()>>, Result<&2, &2, E, Unit>, callback, T.ResponseInput{providerResponse(metadata), Fold.settingsModel(settings)})
        hooked(~Reason, ~E, ~G, ~render, events, settings, parent, state, hooks, Response.Response{metadata, body}, result)

# Acquisition
# -----------

type AttemptEnvironment<-Reason: Data> is Data:
  AttemptEnvironment{request: Client.Request, parent: Signal(Reason), fetch: Fetch.Fetch(Reason), diagnosticLimit: Nat}

def attemptBody(~Reason: Data, environment: AttemptEnvironment<Reason>, unused: Unit) -> IO(Client.Outcome(Reason)):
  match environment:
    case AttemptEnvironment{request, parent, fetch, limit}: Client.attempt(~Reason, request, parent, fetch, limit)

def Acquired(-Reason: Data, -E: Data) -> Type: Result<&2, &1, Failure<Reason, E>, Response.Response<Client.State(Reason)>>

def retried(-Reason: Data, -E: Data, result: Result<&2, &1, Retry.RetryFailure<Client.AttemptError<Reason>>, Response.Response<Client.State(Reason)>>) -> Acquired(Reason, E):
  match result:
    case Fail{cause}: Fail{RequestFailure{cause}}
    case Done{response}: Done{response}

def attemptWithEffects(~Reason: Data, ~E: Data, environment: AttemptEnvironment<Reason>, retry: Retry.ProviderRetryOptions<Reason>, date: C.Callback<String, F64>, pair: Retry.Runtime<Reason> & Retry.Effects<Reason>) -> IO(Acquired(Reason, E)):
  match pair:
    case (owner, effects):
      do IO<Acquired(Reason, E)>:
        +request : C.Callback<Unit, Client.Outcome(Reason)> <- C.create(~AttemptEnvironment<Reason>, ~Unit, ~(Client.Outcome(Reason)), ~(attemptBody(~Reason)), environment)
        result : Result<&2, &1, Retry.RetryFailure<Client.AttemptError<Reason>>, Response.Response<Client.State(Reason)>> <- Retry.retryProviderRequestOwned(Reason, Client.AttemptError<Reason>, Response.Response<Client.State(Reason)>, request, effects, retry)
        C.dispose(Unit, Client.Outcome(Reason), request)
        Retry.dispose(Reason, owner)
        C.dispose(String, F64, date)
        return retried(Reason, E, result)

def attempted(~Reason: Data, ~E: Data, environment: AttemptEnvironment<Reason>, retry: Retry.ProviderRetryOptions<Reason>, date: C.Callback<String, F64>, seeded: Result<&2, &1, Seed.SeedError, Retry.Runtime<Reason>>) -> IO(Acquired(Reason, E)):
  match seeded:
    case Fail{cause}:
      do IO<Acquired(Reason, E)>:
        C.dispose(String, F64, date)
        return Fail{EntropyFailure{cause}}
    case Done{runtime}: attemptWithEffects(~Reason, ~E, environment, retry, date, Retry.borrow(Reason, runtime))

# retryProviderRequest around `create(params, { maxRetries: 0 })`.
def acquire(~Reason: Data, ~E: Data, fetch: Fetch.Fetch(Reason), request: Client.Request, parent: Signal(Reason), retry: Retry.ProviderRetryOptions<Reason>) -> IO(Acquired(Reason, E)):
  do IO<Acquired(Reason, E)>:
    +date : C.Callback<String, F64> <- Retry.dateParser()
    seeded : Result<&2, &1, Seed.SeedError, Retry.Runtime<Reason>> <- Retry.new(~Reason, date)
    attempted(~Reason, ~E, AttemptEnvironment{request, parent, fetch, 65536n}, retry, date, seeded)

# Entry
# -----

# What `stream` prepares before the request: the client key, the default
# headers, the request timeout, retry limits and the built params (or the
# message of the error building them threw).
type Prepared<-E: Data> is Data:
  Prepared{apiKey: Result<&2, &2, String, String>, headers: T.ProviderHeaders(), timeout: Maybe<&2, F64>, maxRetries: Maybe<&2, F64>, maxRetryDelayMs: Maybe<&2, F64>, params: Result<&2, &2, String, J()>, onPayload: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>}

type Context<-Reason: Data> is Data:
  Context{url: URL.Context, defaults: Client.Defaults, fetch: Fetch.Fetch(Reason)}

def acquired(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +settings: Fold.Settings, +parent: Signal(Reason), +state: Fold.State<G>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, result: Acquired(Reason, E)) -> IO(Unit):
  match result:
    case Fail{cause}: failWith(~Reason, ~E, ~G, ~render, events, state, parent, cause)
    case Done{response}:
      do IO<Unit>:
        +hooks : Sse.Hooks<TransportError(Reason)> <- Sse.defaultHooks(~(TransportError(Reason)))
        responded(~Reason, ~E, ~G, ~render, events, settings, parent, state, hooks, hook, response)
        Sse.disposeHooks(TransportError(Reason), hooks)

def requested(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +settings: Fold.Settings, +parent: Signal(Reason), +state: Fold.State<G>, fetch: Fetch.Fetch(Reason), hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, request: Result<&2, &2, Client.RequestError, Client.Request>, retry: Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>) -> IO(Unit):
  match request retry:
    case Fail{cause} _: failWith(~Reason, ~E, ~G, ~render, events, state, parent, RequestRejected{cause})
    case _ Fail{cause}: failWith(~Reason, ~E, ~G, ~render, events, state, parent, InvalidRetryOptions{cause})
    case Done{value} Done{options}:
      do IO<Unit>:
        result : Acquired(Reason, E) <- acquire(~Reason, ~E, fetch, value, parent, options)
        acquired(~Reason, ~E, ~G, ~render, events, settings, parent, state, hook, result)

def modelBaseUrl(model: T.Model<J()>) -> String:
  match model:
    case T.Model{_, _, _, _, baseUrl, _, _, _, _, _, _, _, _, _, _, _}: baseUrl

# `nextParams !== undefined` replaces the params.
def configured(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +settings: Fold.Settings, +parent: Signal(Reason), +state: Fold.State<G>, setup: Context<Reason>, apiKey: String, plan: Prepared<E>, payload: J()) -> IO(Unit):
  match setup plan:
    case Context{url, defaults, fetch} Prepared{_, headers, timeout, retries, delay, _, _, hook}:
      requested(~Reason, ~E, ~G, ~render, events, settings, parent, state, fetch, hook, Client.prepareChatRequest(url, defaults, apiKey, headers, modelBaseUrl(Fold.settingsModel(settings)), timeout, payload), Retry.resolve(Reason, retries, delay, Some{parent}))

# `nextParams !== undefined` replaces the params.
def payloaded(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +settings: Fold.Settings, +parent: Signal(Reason), +state: Fold.State<G>, setup: Context<Reason>, apiKey: String, plan: Prepared<E>, +original: J(), result: Result<&2, &2, E, Maybe<&2, J()>>) -> IO(Unit):
  match result:
    case Fail{cause}: failWith(~Reason, ~E, ~G, ~render, events, state, parent, HookFailure{cause})
    case Done{replacement}: configured(~Reason, ~E, ~G, ~render, events, settings, parent, state, setup, apiKey, plan, Maybe.default(&2, J(), replacement, original))

def withPayload(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +settings: Fold.Settings, +parent: Signal(Reason), +state: Fold.State<G>, setup: Context<Reason>, apiKey: String, +plan: Prepared<E>, +params: J(), hook: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>) -> IO(Unit):
  match hook:
    case None{}: payloaded(~Reason, ~E, ~G, ~render, events, settings, parent, state, setup, apiKey, plan, params, Done{None{}})
    case Some{callback}:
      do IO<Unit>:
        result : Result<&2, &2, E, Maybe<&2, J()>> <- C.call(T.PayloadInput<J(), T.Model<J()>>, Result<&2, &2, E, Maybe<&2, J()>>, callback, T.PayloadInput{params, Fold.settingsModel(settings)})
        payloaded(~Reason, ~E, ~G, ~render, events, settings, parent, state, setup, apiKey, plan, params, result)

def paramsReady(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +settings: Fold.Settings, +parent: Signal(Reason), setup: Context<Reason>, +state: Fold.State<G>, +key: String, headers: T.ProviderHeaders(), timeout: Maybe<&2, F64>, retries: Maybe<&2, F64>, delay: Maybe<&2, F64>, params: Result<&2, &2, String, J()>, +hook: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>, response: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>) -> IO(Unit):
  match params:
    case Fail{message}: failWith(~Reason, ~E, ~G, ~render, events, state, parent, PreparationFailure{message})
    case Done{+payload}: withPayload(~Reason, ~E, ~G, ~render, events, settings, parent, state, setup, key, Prepared{Done{key}, headers, timeout, retries, delay, Done{payload}, hook, response}, payload, hook)

# The key check comes first, as getClientApiKey throws before anything else.
def runFrom(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +settings: Fold.Settings, +parent: Signal(Reason), setup: Context<Reason>, +state: Fold.State<G>, plan: Prepared<E>) -> IO(Unit):
  match plan:
    case Prepared{Fail{message}, _, _, _, _, _, _, _}: failWith(~Reason, ~E, ~G, ~render, events, state, parent, Unauthorized{message})
    case Prepared{Done{key}, headers, timeout, retries, delay, params, hook, response}: paramsReady(~Reason, ~E, ~G, ~render, events, settings, parent, setup, state, key, headers, timeout, retries, delay, params, hook, response)

def stream(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +settings: Fold.Settings, +parent: Signal(Reason), setup: Context<Reason>, timestamp: F64, plan: Prepared<E>) -> IO(Unit):
  runFrom(~Reason, ~E, ~G, ~render, events, settings, parent, setup, Fold.create(G, Fold.settingsModel(settings), timestamp), plan)
