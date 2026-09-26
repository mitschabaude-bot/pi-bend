import Base
import ../types.bend as T
import ../utils/event-stream.bend as Events
import ../utils/headers.bend as ProviderHeaders
import ../utils/provider-retry.bend as Retry
import ../utils/json.bend as JsonWire
import ../utils/transcript.bend as Transcript
import ../utils/schema-json.bend as Convert
import ./google-generative-ai.bend as Google
import ./google-generative-ai-stream.bend as Fold
import ./openai-client.bend as Client
import ./openai-sse.bend as Sse
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-message.bend as H
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-response.bend as Metadata
import ../../../runtime/src/http-response.bend as Progress
import ../../../runtime/src/http-response.bend as Source
import ../../../runtime/src/http-response.bend as Scope
import ../../../runtime/src/random.bend as Seed
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/sse.bend as Body
import ../../../runtime/src/url.bend as URL

# The request lifecycle of upstream `stream` (google-generative-ai.ts) over
# the @google/genai 2.21.0 client: the custom-fetch and API-key checks,
# buildParams, onPayload (a replacement is used as is), the SDK request with
# retryGoogleRequest, the SDK's stream framing and error handling, the chunk
# loop and the catch block.
def J() -> Data: T.JsonValue

def Signal(-Reason: Data) -> Data: Abort.AbortSignal<Reason>

def EventStream(-G: Data) -> Data: Events.AssistantMessageEventStream(V.Value, G)

def Options(-Reason: Data, -Telemetry: Data, -E: Data) -> Data: Google.GoogleOptions<Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>

# The URL tables, pi's User-Agent and the process fetch the SDK uses.
type Setup<-Reason: Data> is Data:
  Setup{url: URL.Context, agent: String, fetch: Fetch.Fetch(Reason), toolCallCounter: Ref.Ref<Nat>}

def sdkLabel() -> String: "google-genai-sdk/2.21.0"

# Publishing
# ----------
def publish(-G: Data, +events: EventStream(G), values: List<&2, T.AssistantMessageEvent<V.Value, G>>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case event <> rest:
      do IO<Unit>:
        Events.push(T.AssistantMessageEvent<V.Value, G>, T.AssistantMessage<V.Value, G>, events, event)
        publish(G, events, rest)

def finalStep(-G: Data, +events: EventStream(G), step: Fold.Step<G>) -> IO(Unit):
  match step:
    case Fold.Step{state, values, _}:
      do IO<Unit>:
        publish(G, events, values)
        Events.end(T.AssistantMessageEvent<V.Value, G>, T.AssistantMessage<V.Value, G>, events, Some{Fold.stateMessage(G, state)})

def fail(~Reason: Data, ~G: Data, +events: EventStream(G), state: Fold.State<G>, +parent: Signal(Reason), message: String) -> IO(Unit):
  do IO<Unit>:
    aborted : Bool <- Abort.aborted(Reason, parent)
    finalStep(G, events, Fold.failed(G, state, message, aborted))

# Requests
# --------
def modelPath(+model: String) -> Result<&2, &2, String, String>:
  Bool.pick(Result<&2, &2, String, String>, String.contains(model, "..") || String.contains(model, "?") || String.contains(model, "&"), Fail{"invalid model parameter"}, Done{Bool.pick(String, String.starts_with(model, "models/") || String.starts_with(model, "tunedModels/"), model, "models/" ++ model)})

def modelOf(value: Maybe<&2, String>) -> Result<&2, &2, String, String>:
  match value:
    case Some{SCon{c, cs}}: modelPath(SCon{c, cs})
    case _: Fail{"model is required and must be a string"}

# tModel: the params' model string names the resource.
def paramsModel(params: J()) -> Result<&2, &2, String, String>: modelOf(Google.payloadModel(params))

def trimmedReversed(reversed: String, base: String) -> String:
  match reversed:
    case SCon{'/', rest}: String.reverse(rest)
    case _: base

def trimmedBase(+base: String) -> String: trimmedReversed(String.reverse(base), base)

# `${baseUrl}/${path}:streamGenerateContent?alt=sse` with the empty apiVersion
# pi configures.
def address(+base: String, path: String) -> String: trimmedBase(base) ++ "/" ++ path ++ ":streamGenerateContent?alt=sse"

def presentHeaders(fields: List<&2, R.Property<String>>) -> T.ProviderHeaders(): ProviderHeaders.fromRecord(R.Record{fields})

def assembled(result: Result<&2, &2, H.HeaderSyntaxError, Client.HeaderState>) -> Result<&2, &2, String, H.Headers>:
  match result:
    case Fail{_}: Fail{"Invalid header value"}
    case Done{state}: Done{Client.wireHeaders(state)}

# The SDK's headers: httpOptions.headers (the client's), its identity and JSON
# content type, then the API key.
def requestHeaders(client: R.Record<String>, key: String) -> Result<&2, &2, String, H.Headers>:
  assembled(Client.build(Some{ProviderHeaders.fromRecord(client)} <> Some{presentHeaders(R.Property{"x-goog-api-client", sdkLabel()} <> R.Property{"Content-Type", "application/json"} <> Nil{})} <> Some{presentHeaders(R.Property{"x-goog-api-key", key} <> Nil{})} <> Nil{}))

# No request timeout is configured, so the attempt runs until the body ends
# or the signal aborts; the native scope needs a bound, the longest it has.
def unbounded() -> F64: F.fromU32(4294967295)

def buildRequest(url: Result<&2, &2, URL.Error, URL.URL>, headers: Result<&2, &2, String, H.Headers>, body: Maybe<&2, String>) -> Result<&2, &2, String, Client.Request>:
  match url headers body:
    case Fail{_} _ _: Fail{"Invalid URL"}
    case _ Fail{message} _: Fail{message}
    case _ _ None{}: Fail{"Could not encode request payload as JSON"}
    case Done{location} Done{fields} Some{text}: Done{Client.Request{location, "post", fields, text, unbounded()}}

def prepared(context: URL.Context, +base: String, client: R.Record<String>, key: String, +params: J(), path: Result<&2, &2, String, String>) -> Result<&2, &2, String, Client.Request>:
  match path:
    case Fail{message}: Fail{message}
    case Done{name}: buildRequest(URL.parse(context, address(base, name)), requestHeaders(client, key), JsonWire.stringify(Google.requestBody(params)))

def prepareRequest(context: URL.Context, base: String, client: R.Record<String>, key: String, +params: J()) -> Result<&2, &2, String, Client.Request>:
  prepared(context, base, client, key, params, paramsModel(params))

def jsonType(value: Result<&2, &2, H.HeaderSyntaxError, Maybe<&2, String>>) -> Bool:
  match value:
    case Done{Some{text}}: String.contains(text, "application/json")
    case _: False{}

# Errors
# ------
def contentType(metadata: Metadata.Metadata) -> Bool: jsonType(H.get(Metadata.headers(metadata), "content-type"))

def jsonText(value: J()) -> String: Maybe.default(&2, String, JsonWire.stringify(value), "")

# throwErrorIfNotOK: a JSON body is the error; any other body becomes
# {error: {message, code, status}}; the ApiError message is its JSON.
def bodyError(+metadata: Metadata.Metadata, diagnostic: Client.Diagnostic, json: Bool) -> String:
  match json diagnostic:
    case True{} Client.JSONDiagnostic{value}: jsonText(value)
    case _ Client.TextDiagnostic{text}: jsonText(T.JsonObject{R.Record{R.Property{"error", T.JsonObject{R.Record{R.Property{"message", T.JsonString{text}} <> R.Property{"code", T.JsonNumber{F.fromU32(Metadata.metadataStatus(metadata))}} <> R.Property{"status", T.JsonString{Metadata.statusText(metadata)}} <> Nil{}}}} <> Nil{}}})
    case False{} Client.JSONDiagnostic{value}: jsonText(T.JsonObject{R.Record{R.Property{"error", T.JsonObject{R.Record{R.Property{"message", T.JsonString{jsonText(value)}} <> R.Property{"code", T.JsonNumber{F.fromU32(Metadata.metadataStatus(metadata))}} <> R.Property{"status", T.JsonString{Metadata.statusText(metadata)}} <> Nil{}}}} <> Nil{}}})

def apiError(error: Client.APIError) -> String:
  match error:
    case Client.APIError{+metadata, diagnostic, _}: bodyError(metadata, diagnostic, contentType(metadata))

def describeAttempt(-Reason: Data, error: Client.AttemptError<Reason>) -> String:
  match error:
    case Client.HTTPFailure{cause}: apiError(cause)
    case Client.TransportFailure{Client.FetchFailure{Scope.Aborted{_}}}: "This operation was aborted"
    case Client.TransportFailure{_}: "fetch failed"
    case Client.DiagnosticFailure{_}: "fetch failed"

def describeRetry(-Reason: Data, error: Retry.RetryFailure<Client.AttemptError<Reason>>) -> String:
  match error:
    case Retry.RequestFailed{failure}: describeAttempt(Reason, Retry.original(Client.AttemptError<Reason>, failure))
    case Retry.RequestAborted{}: "Request aborted"
    case Retry.SleepRejected{_}: "Retry delay is outside the native timer range"
    case Retry.DelayRejected{cause, message}: Client.describeDelay(Retry.delayError(cause, message))

def describeRetryOptions(cause: Retry.OptionsError) -> String:
  match cause:
    case Retry.InvalidRetryCount{_}: "maxRetries must be a non-negative integer within the native natural-number range"
    case Retry.InvalidDelayLimit{_}: "maxRetryDelayMs must be finite and non-negative"

def describeRead(-Reason: Data, error: Sse.ReadError<Sse.TransportError(Reason)>) -> String:
  match error:
    case Sse.Aborted{}: "This operation was aborted"
    case Sse.Failure{_}: "terminated"

# retryGoogleRequest: the SDK's ApiError has a status but no headers, so only
# the status decides a retry and no server delay applies; other failures
# (fetch errors) are not provider errors and are not retried.
def googleFailure(-Reason: Data, failure: Retry.RequestFailure<Client.AttemptError<Reason>>) -> Retry.RequestFailure<Client.AttemptError<Reason>>:
  match failure:
    case Retry.Provider{Retry.ProviderError{Client.HTTPFailure{cause}, message, status, _, _, _}}: Retry.Provider{Retry.ProviderError{Client.HTTPFailure{cause}, message, status, None{}, None{}, None{}}}
    case Retry.Provider{Retry.ProviderError{original, _, _, _, _, _}}: Retry.Other{original}
    case other: other

def googleOutcome(-Reason: Data, outcome: Client.Outcome(Reason)) -> Client.Outcome(Reason):
  match outcome:
    case Fail{failure}: Fail{googleFailure(Reason, failure)}
    case Done{response}: Done{response}

type AttemptEnvironment<-Reason: Data> is Data:
  AttemptEnvironment{request: Client.Request, parent: Signal(Reason), fetch: Fetch.Fetch(Reason)}

def attemptBody(~Reason: Data, environment: AttemptEnvironment<Reason>, unused: Unit) -> IO(Client.Outcome(Reason)):
  match environment:
    case AttemptEnvironment{request, parent, fetch}:
      do IO<Client.Outcome(Reason)>:
        outcome : Client.Outcome(Reason) <- Client.attemptWith(~Reason, raw => Client.decodeWhole(raw), request, parent, fetch, 65536n)
        return googleOutcome(Reason, outcome)

# upstream retryGoogleRequest: retryProviderRequest around one SDK request.
type GoogleRetryError<-E: Data> is Data:
  RetryFailed{cause: Retry.RetryFailure<E>}
  EntropyFailed{cause: Seed.SeedError}

def retriedWith(-E: Data, -A: Type, result: Result<&2, &1, Retry.RetryFailure<E>, A>) -> Result<&2, &1, GoogleRetryError<E>, A>:
  match result:
    case Fail{cause}: Fail{RetryFailed{cause}}
    case Done{value}: Done{value}

def retryWithEffects(~Reason: Data, ~E: Data, ~A: Type, request: C.Callback<Unit, Result<&2, &1, Retry.RequestFailure<E>, A>>, retry: Retry.ProviderRetryOptions<Reason>, date: C.Callback<String, F64>, pair: Retry.Runtime<Reason> & Retry.Effects<Reason>) -> IO(Result<&2, &1, GoogleRetryError<E>, A>):
  match pair:
    case (owner, effects):
      do IO<Result<&2, &1, GoogleRetryError<E>, A>>:
        result : Result<&2, &1, Retry.RetryFailure<E>, A> <- Retry.retryProviderRequestOwned(Reason, E, A, request, effects, retry)
        Retry.dispose(Reason, owner)
        C.dispose(String, F64, date)
        return retriedWith(E, A, result)

def retrySeeded(~Reason: Data, ~E: Data, ~A: Type, request: C.Callback<Unit, Result<&2, &1, Retry.RequestFailure<E>, A>>, retry: Retry.ProviderRetryOptions<Reason>, date: C.Callback<String, F64>, seeded: Result<&2, &1, Seed.SeedError, Retry.Runtime<Reason>>) -> IO(Result<&2, &1, GoogleRetryError<E>, A>):
  match seeded:
    case Fail{cause}:
      do IO<Result<&2, &1, GoogleRetryError<E>, A>>:
        C.dispose(String, F64, date)
        return Fail{EntropyFailed{cause}}
    case Done{runtime}: retryWithEffects(~Reason, ~E, ~A, request, retry, date, Retry.borrow(Reason, runtime))

# The request's failures are already normalized: errors with a status are
# provider errors without headers, others are not retried.
def retryGoogleRequest(~Reason: Data, ~E: Data, ~A: Type, request: C.Callback<Unit, Result<&2, &1, Retry.RequestFailure<E>, A>>, retry: Retry.ProviderRetryOptions<Reason>) -> IO(Result<&2, &1, GoogleRetryError<E>, A>):
  do IO<Result<&2, &1, GoogleRetryError<E>, A>>:
    +date : C.Callback<String, F64> <- Retry.dateParser()
    seeded : Result<&2, &1, Seed.SeedError, Retry.Runtime<Reason>> <- Retry.new(~Reason, date)
    retrySeeded(~Reason, ~E, ~A, request, retry, date, seeded)

def Acquired(-Reason: Data) -> Type: Result<&2, &1, String, Response.Response<Client.State(Reason)>>

def acquiredWith(-Reason: Data, result: Result<&2, &1, GoogleRetryError<Client.AttemptError<Reason>>, Response.Response<Client.State(Reason)>>) -> Acquired(Reason):
  match result:
    case Fail{RetryFailed{cause}}: Fail{describeRetry(Reason, cause)}
    case Fail{EntropyFailed{cause}}: Fail{Client.describeEntropy(cause)}
    case Done{response}: Done{response}

def acquire(~Reason: Data, fetch: Fetch.Fetch(Reason), request: Client.Request, parent: Signal(Reason), retry: Retry.ProviderRetryOptions<Reason>) -> IO(Acquired(Reason)):
  do IO<Acquired(Reason)>:
    +attempt : C.Callback<Unit, Client.Outcome(Reason)> <- C.create(~AttemptEnvironment<Reason>, ~Unit, ~(Client.Outcome(Reason)), ~(attemptBody(~Reason)), AttemptEnvironment{request, parent, fetch})
    result : Result<&2, &1, GoogleRetryError<Client.AttemptError<Reason>>, Response.Response<Client.State(Reason)>> <- retryGoogleRequest(~Reason, ~(Client.AttemptError<Reason>), ~(Response.Response<Client.State(Reason)>), attempt, retry)
    C.dispose(Unit, Client.Outcome(Reason), attempt)
    return acquiredWith(Reason, result)

# The body loop
# -------------
type Drive<-E: Data, -G: Data> is Data:
  Read{framer: Fold.Framer, state: Fold.State<G>}
  Received{framer: Fold.Framer, state: Fold.State<G>, result: Result<&2, &2, E, Maybe<&2, Body.Chunk>>}
  Publish{next: Drive<E, G>, values: List<&2, T.AssistantMessageEvent<V.Value, G>>}
  Thrown{state: Fold.State<G>, message: String}
  Ended{step: Fold.Step<G>}

def stepped(-E: Data, -G: Data, framer: Fold.Framer, step: Fold.Step<G>) -> Drive<E, G>:
  match step:
    case Fold.Step{state, values, None{}}: Publish{Read{framer, state}, values}
    case Fold.Step{state, values, Some{message}}: Publish{Thrown{state, message}, values}

def framed(-E: Data, -G: Data, state: Fold.State<G>, value: Fold.Framed, +now: F64) -> Drive<E, G>:
  match value:
    case Fold.Framed{framer, _, Some{message}}: Thrown{state, message}
    case Fold.Framed{framer, events, None{}}: stepped(E, G, framer, Fold.dataEvents(G, events, now, Fold.Step{state, Nil{}, None{}}))

def frameChunk(framer: Fold.Framer, chunk: Body.Chunk) -> Fold.Framed:
  match chunk:
    case Body.Bytes{bytes}: Fold.frameBytes(framer, bytes)
    case Body.Text{text}: Fold.frameText(framer, text)
    case Body.EmptyChunk{}: Fold.Framed{framer, Nil{}, None{}}

def finished(-E: Data, -G: Data, step: Fold.Step<G>) -> Drive<E, G>:
  match step:
    case Fold.Step{state, values, Some{message}}: Publish{Thrown{state, message}, values}
    case Fold.Step{state, values, None{}}: Ended{Fold.Step{state, values, None{}}}

def endingWith(-E: Data, -G: Data, incomplete: Maybe<&2, String>, state: Fold.State<G>, aborted: Bool) -> Drive<E, G>:
  match incomplete:
    case Some{message}: Thrown{state, message}
    case None{}: finished(E, G, Fold.finish(G, state, aborted))

def ending(-E: Data, -G: Data, framer: Fold.Framer, state: Fold.State<G>, aborted: Bool) -> Drive<E, G>:
  endingWith(E, G, Fold.finishFramer(framer), state, aborted)

def framedCount(-E: Data, -G: Data, drive: Drive<E, G>, fallback: Nat) -> Nat:
  match drive:
    case Publish{Read{_, state}, _}: Fold.toolCallsOf(G, state)
    case Publish{Thrown{state, _}, _}: Fold.toolCallsOf(G, state)
    case Thrown{state, _}: Fold.toolCallsOf(G, state)
    case _: fallback

def countedFrame(-E: Data, -G: Data, state: Fold.State<G>, value: Fold.Framed, +now: F64, +calls: Nat) -> Nat & Drive<E, G>:
  +next = framed(E, G, Fold.withToolCalls(G, state, calls), value, now)
  (framedCount(E, G, next, calls), next)

# With a shared counter the chunk step reads and advances it atomically, so
# ids continue the process-wide sequence (upstream's module toolCallCounter);
# without one the stream keeps its own count.
def counted(-E: Data, -G: Data, counter: Maybe<&2, Ref.Ref<Nat>>, state: Fold.State<G>, value: Fold.Framed, +now: F64) -> IO(Drive<E, G>):
  match counter:
    case None{}: IO.pure(Drive<E, G>, framed(E, G, state, value, now))
    case Some{shared}: Ref.modify(Nat, Drive<E, G>, shared, calls => countedFrame(E, G, state, value, now, calls))

# The SDK reader: no abort check between reads (the fetch signal cancels a
# pending read); each chunk's events are published as they are decoded.
@unsafe def drive(~Reason: Data, ~E: Data, ~G: Data, ~describe: E -> String, +events: EventStream(G), +source: Body.Source<E>, +parent: Signal(Reason), +counter: Maybe<&2, Ref.Ref<Nat>>, current: Drive<E, G>) -> IO(Drive<E, G>):
  match current:
    case Read{framer, state}:
      do IO<Drive<E, G>>:
        result : Result<&2, &2, E, Maybe<&2, Body.Chunk>> <- Body.read(E, source)
        drive(~Reason, ~E, ~G, ~describe, events, source, parent, counter, Received{framer, state, result})
    case Received{_, state, Fail{cause}}: IO.pure(Drive<E, G>, Thrown{state, describe(cause)})
    case Received{framer, state, Done{None{}}}:
      do IO<Drive<E, G>>:
        aborted : Bool <- Abort.aborted(Reason, parent)
        drive(~Reason, ~E, ~G, ~describe, events, source, parent, counter, ending(E, G, framer, state, aborted))
    case Received{framer, state, Done{Some{chunk}}}:
      do IO<Drive<E, G>>:
        now : F64 <- Date.now()
        next : Drive<E, G> <- counted(E, G, counter, state, frameChunk(framer, chunk), now)
        drive(~Reason, ~E, ~G, ~describe, events, source, parent, counter, next)
    case Publish{next, values}:
      do IO<Drive<E, G>>:
        publish(G, events, values)
        drive(~Reason, ~E, ~G, ~describe, events, source, parent, counter, next)
    case other: IO.pure(Drive<E, G>, other)

def settled(~Reason: Data, ~E: Data, ~G: Data, +events: EventStream(G), +parent: Signal(Reason), drive: Drive<E, G>) -> IO(Unit):
  match drive:
    case Ended{step}: finalStep(G, events, step)
    case Thrown{state, message}: fail(~Reason, ~G, events, state, parent, message)
    case _: IO.pure(Unit, Unit{})

def streamBody(~Reason: Data, ~E: Data, ~G: Data, ~describe: E -> String, +events: EventStream(G), source: Body.Source<E>, +parent: Signal(Reason), +state: Fold.State<G>, counter: Maybe<&2, Ref.Ref<Nat>>) -> IO(Unit):
  do IO<Unit>:
    publish(G, events, T.Start{Fold.stateMessage(G, state)} <> Nil{})
    result : Drive<E, G> <- drive(~Reason, ~E, ~G, ~describe, events, source, parent, counter, Read{Fold.createFramer(), state})
    settled(~Reason, ~E, ~G, events, parent, result)

def borrowedBody(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Signal(Reason), +state: Fold.State<G>, counter: Maybe<&2, Ref.Ref<Nat>>, pair: Sse.Body(Reason) & Body.Source<Sse.ReadError<Sse.TransportError(Reason)>>) -> IO(Unit):
  match pair:
    case (owner, source):
      do IO<Unit>:
        streamBody(~Reason, ~(Sse.ReadError<Sse.TransportError(Reason)>), ~G, ~(describeRead(Reason)), events, source, parent, state, counter)
        closed : Result<&2, &2, Sse.ReadError<Sse.TransportError(Reason)>, Unit> <- Source.dispose(Client.State(Reason), Sse.ReadError<Sse.TransportError(Reason)>, owner)
        return Unit{}

def httpBody(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Signal(Reason), +state: Fold.State<G>, counter: Maybe<&2, Ref.Ref<Nat>>, response: Response.Response<Client.State(Reason)>) -> IO(Unit):
  match response:
    case Response.Response{_, body}:
      do IO<Unit>:
        owner : Sse.Body(Reason) <- Source.create(~(Client.ReadError(Reason)), ~(Client.State(Reason)), ~(Sse.ReadError<Sse.TransportError(Reason)>), ~(Sse.classify(Reason)), ~(Client.read(Reason)), ~(Client.close(Reason)), body)
        borrowedBody(~Reason, ~G, events, parent, state, counter, Source.borrow(Client.State(Reason), Sse.ReadError<Sse.TransportError(Reason)>, owner))

# Entry
# -----
def acquiredResponse(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Signal(Reason), +state: Fold.State<G>, counter: Maybe<&2, Ref.Ref<Nat>>, result: Acquired(Reason)) -> IO(Unit):
  match result:
    case Fail{message}: fail(~Reason, ~G, events, state, parent, message)
    case Done{response}: httpBody(~Reason, ~G, events, parent, state, counter, response)

def sendRequestCounted(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Signal(Reason), +state: Fold.State<G>, fetch: Fetch.Fetch(Reason), request: Result<&2, &2, String, Client.Request>, retry: Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>, counter: Maybe<&2, Ref.Ref<Nat>>) -> IO(Unit):
  match request retry:
    case Fail{message} _: fail(~Reason, ~G, events, state, parent, message)
    case _ Fail{cause}: fail(~Reason, ~G, events, state, parent, describeRetryOptions(cause))
    case Done{value} Done{options}:
      do IO<Unit>:
        result : Acquired(Reason) <- acquire(~Reason, fetch, value, parent, options)
        acquiredResponse(~Reason, ~G, events, parent, state, counter, result)

# The request and body loop with the stream's own tool-call count.
def sendRequest(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Signal(Reason), +state: Fold.State<G>, fetch: Fetch.Fetch(Reason), request: Result<&2, &2, String, Client.Request>, retry: Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>) -> IO(Unit):
  sendRequestCounted(~Reason, ~G, events, parent, state, fetch, request, retry, None{})

type Plan<-Reason: Data> is Data:
  Plan{key: String, client: R.Record<String>, base: String, retries: Maybe<&2, F64>, delay: Maybe<&2, F64>}

def send(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +state: Fold.State<G>, plan: Plan<Reason>, +params: J()) -> IO(Unit):
  match setup plan:
    case Setup{url, _, fetch, counter} Plan{key, client, base, retries, delay}:
      sendRequestCounted(~Reason, ~G, events, parent, state, fetch, prepareRequest(url, base, client, key, params), Retry.resolve(Reason, retries, delay, Some{parent}), Some{counter})

def payloaded(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +state: Fold.State<G>, plan: Plan<Reason>, original: J(), result: Result<&2, &2, E, Maybe<&2, J()>>) -> IO(Unit):
  match result:
    case Fail{cause}: fail(~Reason, ~G, events, state, parent, render(cause))
    case Done{replacement}: send(~Reason, ~G, events, parent, setup, state, plan, Maybe.default(&2, J(), replacement, original))

def withPayload(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +state: Fold.State<G>, +model: T.Model<J()>, plan: Plan<Reason>, +params: J(), hook: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>) -> IO(Unit):
  match hook:
    case None{}: send(~Reason, ~G, events, parent, setup, state, plan, params)
    case Some{callback}:
      do IO<Unit>:
        result : Result<&2, &2, E, Maybe<&2, J()>> <- C.call(T.PayloadInput<J(), T.Model<J()>>, Result<&2, &2, E, Maybe<&2, J()>>, callback, T.PayloadInput{params, model})
        payloaded(~Reason, ~E, ~G, ~render, events, parent, setup, state, plan, params, result)

# buildParams rejects an already aborted signal.
def built(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +state: Fold.State<G>, +model: T.Model<J()>, plan: Plan<Reason>, hook: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>, params: Result<&2, &2, String, J()>, aborted: Bool) -> IO(Unit):
  match params aborted:
    case Fail{message} _: fail(~Reason, ~G, events, state, parent, message)
    case Done{_} True{}: fail(~Reason, ~G, events, state, parent, "Request aborted")
    case Done{+payload} False{}: withPayload(~Reason, ~E, ~G, ~render, events, parent, setup, state, model, plan, payload, hook)

def optionsBase(-Reason: Data, -Telemetry: Data, -E: Data, options: Options(Reason, Telemetry, E)) -> T.StreamOptions<J(), Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>:
  match options:
    case Google.GoogleOptions{base, _, _}: base

def modelBaseUrl(model: T.Model<J()>) -> String:
  match model:
    case T.Model{_, _, _, _, base, _, _, _, _, _, _, _, _, _, _, _}: base

def planFor(-Reason: Data, -Telemetry: Data, -E: Data, +setup: Setup<Reason>, +model: T.Model<J()>, key: String, base: T.StreamOptions<J(), Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>) -> Plan<Reason>:
  match base setup:
    case T.StreamOptions{_, _, _, _, _, _, _, headers, _, retries, delay, _, _, _, _, _, _, _, _} Setup{_, agent, _, _}: Plan{key, Google.clientHeaders(agent, model, headers), modelBaseUrl(model), retries, delay}

def payloadHook(-Reason: Data, -Telemetry: Data, -E: Data, base: T.StreamOptions<J(), Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>) -> Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>:
  match base:
    case T.StreamOptions{_, _, _, _, _, hook, _, _, _, _, _, _, _, _, _, _, _, _, _}: hook

def keyed(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Options(Reason, Telemetry, E), +state: Fold.State<G>, key: String) -> IO(Unit):
  +base = optionsBase(Reason, Telemetry, E, options)
  do IO<Unit>:
    params : Result<&2, &2, String, J()> <- Google.buildParams(~G, ~D, ~(Signal(Reason)), ~Telemetry, ~(Fetch.Fetch(Reason)), ~E, model, context, options)
    aborted : Bool <- Abort.aborted(Reason, parent)
    built(~Reason, ~E, ~G, ~render, events, parent, setup, state, model, planFor(Reason, Telemetry, E, setup, model, key, base), payloadHook(Reason, Telemetry, E, base), params, aborted)

# upstream accepts `options.fetch` only when it is globalThis.fetch, the
# SDK's own fetch; here that is the setup's process fetch handle.
def ambientFetch(-Reason: Data, +setup: Setup<Reason>, fetch: Maybe<&2, Fetch.Fetch(Reason)>) -> Bool:
  match fetch setup:
    case None{} _: True{}
    case Some{selected} Setup{_, _, ambient, _}: C.same(Fetch.Input<Reason>, Fetch.Result_(Reason), selected, ambient)

def checkedKey(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Options(Reason, Telemetry, E), +state: Fold.State<G>, ambient: Bool, key: Maybe<&2, String>) -> IO(Unit):
  match ambient key:
    case False{} _: fail(~Reason, ~G, events, state, parent, "Custom fetch is not supported by the Google Generative AI adapter")
    case True{} Some{SCon{c, cs}}: keyed(~Reason, ~Telemetry, ~E, ~G, ~D, ~render, events, parent, setup, model, context, options, state, SCon{c, cs})
    case True{} _: fail(~Reason, ~G, events, state, parent, "No API key for provider: " ++ T.modelProvider(model))

def baseChecks(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Options(Reason, Telemetry, E), +state: Fold.State<G>, base: T.StreamOptions<J(), Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>) -> IO(Unit):
  match base:
    case T.StreamOptions{_, _, key, fetch, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: checkedKey(~Reason, ~Telemetry, ~E, ~G, ~D, ~render, events, parent, setup, model, context, options, state, ambientFetch(Reason, setup, fetch), key)

# upstream `stream`: the producer's work up to `stream.end()` over the
# collapsed transcript. `parent` is the request's abort signal. A custom
# fetch option is rejected as upstream does; the SDK's own fetch is `setup`'s.
def stream(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Options(Reason, Telemetry, E), timestamp: F64) -> IO(Unit):
  baseChecks(~Reason, ~Telemetry, ~E, ~G, ~D, ~render, events, parent, setup, model, Transcript.collapseSystemMessages(V.Value, V.Value, G, D, context), options, Fold.create(G, model, timestamp), optionsBase(Reason, Telemetry, E, options))
