import Base
import ../types.bend as T
import ../utils/event-stream.bend as Events
import ../utils/headers.bend as ProviderHeaders
import ../utils/provider-retry.bend as Retry
import ../utils/json.bend as JsonWire
import ../utils/transcript.bend as Transcript
import ./anthropic-messages.bend as Messages
import ./anthropic-messages-stream.bend as Fold
import ./github-copilot-headers.bend as Copilot
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
import ../../../runtime/src/random.bend as Seed
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/sse.bend as Body
import ../../../runtime/src/url.bend as URL

# The request lifecycle of upstream `stream` (anthropic-messages.ts): the
# transcript resolved for the model, the client (injected, or created with
# auth, Copilot and session headers), buildParams, onPayload (a replacement
# keeps streaming on), the retried request, onResponse, `start`, the event
# loop over the body and the catch block. The Anthropic SDK request goes
# through the shared Stainless client port (openai-client.bend).
def J() -> Data: T.JsonValue

def Signal(-Reason: Data) -> Data: Abort.AbortSignal<Reason>

def EventStream(-G: Data) -> Data: Events.AssistantMessageEventStream(V.Value, G)

# upstream `options.client`: an injected client receives the final params and
# returns the raw response (status, headers and body chunks). Its failures
# are messages; they are not provider errors, so they are not retried.
type ClientResponse is Data:
  ClientResponse{status: F64, headers: R.Record<String>, body: Body.Source<String>}

def AnthropicClient() -> Data: C.Callback<J(), Result<&2, &2, String, ClientResponse>>

def Options(-Reason: Data, -Telemetry: Data, -E: Data) -> Data: Messages.AnthropicOptions<Signal(Reason), Telemetry, Fetch.Fetch(Reason), E, AnthropicClient()>

# Runtime facilities of a created client: the URL tables, the SDK defaults,
# pi's User-Agent and the default fetch.
type Setup<-Reason: Data> is Data:
  Setup{url: URL.Context, defaults: Client.Defaults, agent: String, fetch: Fetch.Fetch(Reason)}

# The SDK identity replaced by pi's User-Agent in the client headers.
def sdkUserAgent() -> String: "Anthropic/JS 0.124.0"

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

# The catch block: the stop reason follows the abort signal.
def fail(~Reason: Data, ~G: Data, +events: EventStream(G), state: Fold.State<G>, +parent: Signal(Reason), message: String) -> IO(Unit):
  do IO<Unit>:
    aborted : Bool <- Abort.aborted(Reason, parent)
    finalStep(G, events, Fold.failed(G, state, message, aborted))

# Error messages
# --------------
# The Anthropic SDK's validateHeaders message.
def missingAuthentication() -> String:
  "Could not resolve authentication method. Expected either apiKey or authToken to be set. Or for one of the \"X-Api-Key\" or \"Authorization\" headers to be explicitly omitted"

def describeHeader(error: Client.HeaderError) -> String:
  match error:
    case Client.MissingAuthentication{}: missingAuthentication()
    case other: Client.describeHeader(other)

def describeRequest(error: Client.RequestError) -> String:
  match error:
    case Client.HeaderRejected{cause}: describeHeader(cause)
    case other: Client.describeRequest(other)

# upstream's catch keeps the SDK error's own message.
def describeAttempt(-Reason: Data, error: Client.AttemptError<Reason>) -> String:
  match error:
    case Client.TransportFailure{cause}: Client.describeTransport(Reason, cause)
    case Client.HTTPFailure{cause}: Client.apiMessage(cause)
    case Client.DiagnosticFailure{Client.DiagnosticReadFailure{_, _}}: "Could not read the error response diagnostic."
    case Client.DiagnosticFailure{Client.DiagnosticEncodingFailure{_, _}}: "Could not encode the error response diagnostic."

def describeRetry(-Reason: Data, error: Retry.RetryFailure<Client.AttemptError<Reason>>) -> String:
  match error:
    case Retry.RequestFailed{Retry.Other{cause}}: describeAttempt(Reason, cause)
    case Retry.RequestFailed{Retry.Provider{Retry.ProviderError{cause, _, _, _, _, _}}}: describeAttempt(Reason, cause)
    case Retry.RequestAborted{}: "Request aborted"
    case Retry.SleepRejected{_}: "Retry delay is outside the native timer range"
    case Retry.DelayRejected{cause, message}: Client.describeDelay(Retry.delayError(cause, message))

def describeRetryOptions(cause: Retry.OptionsError) -> String:
  match cause:
    case Retry.InvalidRetryCount{_}: "maxRetries must be a non-negative integer within the native natural-number range"
    case Retry.InvalidDelayLimit{_}: "maxRetryDelayMs must be finite and non-negative"

# Body reads: a cancelled read is the aborted request; a failing body stream
# surfaces as undici's "terminated".
def describeRead(-Reason: Data, error: Sse.ReadError<Sse.TransportError(Reason)>) -> String:
  match error:
    case Sse.Aborted{}: "Request was aborted"
    case Sse.Failure{_}: "terminated"

# Request
# -------
def addressReversed(base: String, reversed: String) -> String:
  match reversed:
    case SCon{'/', _}: base ++ "v1/messages?beta=true"
    case _: base ++ "/v1/messages?beta=true"

# The SDK joins its fixed `/v1/messages?beta=true` path to the base URL.
def address(+base: String) -> String: addressReversed(base, String.reverse(base))

def presentHeaders(fields: List<&2, R.Property<String>>) -> T.ProviderHeaders(): ProviderHeaders.fromRecord(R.Record{fields})

# The SDK's defaults after its Stainless fields: browser access (pi allows
# it) and the API version.
def anthropicDefaults() -> T.ProviderHeaders():
  presentHeaders(R.Property{"anthropic-dangerous-direct-browser-access", "true"} <> R.Property{"anthropic-version", "2023-06-01"} <> Nil{})

# apiKeyAuth then bearerAuth.
def authLayer(auth: Messages.ClientAuth) -> T.ProviderHeaders():
  match auth:
    case Messages.ApiKeyAuth{Some{key}}: presentHeaders(R.Property{"X-Api-Key", key} <> Nil{})
    case Messages.BearerAuth{Some{token}}: presentHeaders(R.Property{"Authorization", "Bearer " ++ token} <> Nil{})
    case _: R.new(T.Nullable<String>)

# A present header or an explicitly removed one satisfies validateHeaders.
def allows(value: Maybe<&2, T.Nullable<String>>) -> Bool:
  match value:
    case Some{T.NullValue{}}: True{}
    case Some{T.PresentValue{SCon{_, _}}}: True{}
    case _: False{}

def authenticated(+state: Client.HeaderState) -> Bool:
  allows(Client.lookup(state, "x-api-key")) || allows(Client.lookup(state, "authorization"))

def validated(result: Result<&2, &2, H.HeaderSyntaxError, Client.HeaderState>) -> Result<&2, &2, Client.HeaderError, H.Headers>:
  match result:
    case Fail{cause}: Fail{Client.HeaderFailure{cause}}
    case Done{+state}: Bool.pick(Result<&2, &2, Client.HeaderError, H.Headers>, authenticated(state), Done{Client.wireHeaders(state)}, Fail{Client.MissingAuthentication{}})

def betaHeaders(beta: Maybe<&2, String>) -> T.ProviderHeaders():
  match beta:
    case None{}: R.new(T.Nullable<String>)
    case Some{value}: presentHeaders(R.Property{"anthropic-beta", value} <> Nil{})

# The SDK's layers: defaults (with the retry count and timeout), auth, the
# client's default headers, JSON body headers, then the betas header.
def layeredHeaders(defaults: Client.Defaults, auth: Messages.ClientAuth, client: T.ProviderHeaders(), beta: Maybe<&2, String>, timeout: Result<&2, &2, Client.HeaderError, Maybe<&2, String>>) -> Result<&2, &2, Client.HeaderError, H.Headers>:
  match timeout:
    case Fail{cause}: Fail{cause}
    case Done{value}: validated(Client.build(Some{Client.defaultHeaders(defaults, 0n, value)} <> Some{anthropicDefaults()} <> Some{authLayer(auth)} <> Some{client} <> Some{Client.bodyHeaders()} <> Some{betaHeaders(beta)} <> Nil{}))

def betaText(value: J()) -> String:
  match value:
    case T.JsonString{text}: text
    case other: Maybe.default(&2, String, JsonWire.stringify(other), "")

def betaStrings(values: List<&2, J()>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: betaText(value) <> betaStrings(rest)

# `betas` leaves the body and becomes the anthropic-beta header
# (`betas.toString()`).
def betaOf(value: Maybe<&2, J()>) -> Maybe<&2, String>:
  match value:
    case Some{T.JsonArray{values}}: Some{String.join(betaStrings(values), ",")}
    case Some{T.JsonNull{}}: None{}
    case Some{other}: Some{betaText(other)}
    case None{}: None{}

def payloadBeta(payload: J()) -> Maybe<&2, String>:
  match payload:
    case T.JsonObject{fields}: betaOf(R.get(J(), fields, "betas"))
    case _: None{}

def payloadBody(payload: J()) -> J():
  match payload:
    case T.JsonObject{fields}: T.JsonObject{R.remove(J(), fields, "betas")}
    case other: other

def serializedRequest(url: URL.URL, headers: Result<&2, &2, Client.HeaderError, H.Headers>, timeout: F64, body: Result<&2, &2, Client.RequestError, String>) -> Result<&2, &2, Client.RequestError, Client.Request>:
  match body headers:
    case Fail{cause} _: Fail{cause}
    case _ Fail{cause}: Fail{Client.HeaderRejected{cause}}
    case Done{text} Done{fields}: Done{Client.Request{url, "post", fields, text, timeout}}

def timedRequest(defaults: Client.Defaults, auth: Messages.ClientAuth, client: T.ProviderHeaders(), url: URL.URL, +payload: J(), original: Maybe<&2, F64>, timeout: Result<&2, &2, Client.HeaderError, F64>) -> Result<&2, &2, Client.RequestError, Client.Request>:
  match timeout:
    case Fail{cause}: Fail{Client.HeaderRejected{cause}}
    case Done{value}: serializedRequest(url, layeredHeaders(defaults, auth, client, payloadBeta(payload), Client.timeoutHeader(original)), value, Client.serialize(payloadBody(payload)))

def addressedRequest(defaults: Client.Defaults, auth: Messages.ClientAuth, client: T.ProviderHeaders(), +timeout: Maybe<&2, F64>, payload: J(), url: Result<&2, &2, URL.Error, URL.URL>) -> Result<&2, &2, Client.RequestError, Client.Request>:
  match url:
    case Fail{cause}: Fail{Client.URLFailure{Client.InvalidURL{cause}}}
    case Done{value}: timedRequest(defaults, auth, client, value, payload, timeout, Client.validateTimeout(Client.effectiveTimeout(timeout)))

# The body loop
# -------------
def emittedEvents(-G: Data, step: Fold.Step<G>) -> List<&2, T.AssistantMessageEvent<V.Value, G>>:
  match step:
    case Fold.Step{_, values, _}: values

type Reading<-G: Data> is Data:
  Reading{decoder: Fold.SseDecoder, state: Fold.State<G>}

# The loop's states: before a read, after the abort check, after a read,
# events to publish before the next state, and the two endings.
type Drive<-E: Data, -G: Data> is Data:
  Pull{reading: Reading<G>}
  Checked{reading: Reading<G>, aborted: Bool}
  Received{reading: Reading<G>, result: Result<&2, &2, E, Maybe<&2, Body.Chunk>>}
  Publish{next: Drive<E, G>, values: List<&2, T.AssistantMessageEvent<V.Value, G>>}
  Thrown{state: Fold.State<G>, message: String}
  Ended{step: Fold.Step<G>}

def decodedStep(-E: Data, -G: Data, decoder: Fold.SseDecoder, step: Fold.Step<G>) -> Drive<E, G>:
  match step:
    case Fold.Step{state, values, None{}}: Publish{Pull{Reading{decoder, state}}, values}
    case Fold.Step{state, values, Some{message}}: Publish{Thrown{state, message}, values}

def decodedChunk(-E: Data, -G: Data, state: Fold.State<G>, decoded: Fold.Decoded) -> Drive<E, G>:
  match decoded:
    case Fold.Decoded{decoder, sse}: decodedStep(E, G, decoder, Fold.serverSentEvents(G, sse, Fold.Step{state, Nil{}, None{}}))

def finished(-E: Data, -G: Data, earlier: List<&2, T.AssistantMessageEvent<V.Value, G>>, step: Fold.Step<G>) -> Drive<E, G>:
  match step:
    case Fold.Step{state, values, Some{message}}: Publish{Thrown{state, message}, List.append(&2, T.AssistantMessageEvent<V.Value, G>, earlier, values)}
    case Fold.Step{state, values, None{}}: Publish{Ended{Fold.Step{state, values, None{}}}, earlier}

# The end of the body: remaining server-sent events, then the checks after
# the loop.
def endStep(-E: Data, -G: Data, step: Fold.Step<G>, aborted: Bool, timestamp: F64, details: List<&2, Fold.InputTransformation> -> G) -> Drive<E, G>:
  match step:
    case Fold.Step{state, values, Some{message}}: Publish{Thrown{state, message}, values}
    case Fold.Step{state, values, None{}}: finished(E, G, values, Fold.finish(G, state, aborted, timestamp, details))

def ending(-E: Data, -G: Data, reading: Reading<G>, aborted: Bool, timestamp: F64, details: List<&2, Fold.InputTransformation> -> G) -> Drive<E, G>:
  match reading:
    case Reading{decoder, state}: endStep(E, G, Fold.serverSentEvents(G, Fold.finishDecoder(decoder), Fold.Step{state, Nil{}, None{}}), aborted, timestamp, details)

def decodeChunk(decoder: Fold.SseDecoder, chunk: Body.Chunk) -> Fold.Decoded:
  match chunk:
    case Body.Bytes{bytes}: Fold.decodeBytes(decoder, bytes)
    case Body.Text{text}: Fold.decodeText(decoder, text)
    case Body.EmptyChunk{}: Fold.Decoded{decoder, Nil{}}

def chunkStep(-E: Data, -G: Data, reading: Reading<G>, chunk: Body.Chunk) -> Drive<E, G>:
  match reading:
    case Reading{decoder, state}: decodedChunk(E, G, state, decodeChunk(decoder, chunk))

def stateOf(-G: Data, reading: Reading<G>) -> Fold.State<G>:
  match reading:
    case Reading{_, state}: state

# upstream's `for await` over the body: an aborted signal throws before each
# read; each chunk's events are published as they are decoded.
@unsafe def drive(~Reason: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~describe: E -> String, +events: EventStream(G), +source: Body.Source<E>, +parent: Signal(Reason), current: Drive<E, G>) -> IO(Drive<E, G>):
  match current:
    case Pull{reading}:
      do IO<Drive<E, G>>:
        aborted : Bool <- Abort.aborted(Reason, parent)
        drive(~Reason, ~E, ~G, ~details, ~describe, events, source, parent, Checked{reading, aborted})
    case Checked{reading, True{}}: IO.pure(Drive<E, G>, Thrown{stateOf(G, reading), "Request was aborted"})
    case Checked{reading, False{}}:
      do IO<Drive<E, G>>:
        result : Result<&2, &2, E, Maybe<&2, Body.Chunk>> <- Body.read(E, source)
        drive(~Reason, ~E, ~G, ~details, ~describe, events, source, parent, Received{reading, result})
    case Received{reading, Fail{cause}}: IO.pure(Drive<E, G>, Thrown{stateOf(G, reading), describe(cause)})
    case Received{reading, Done{None{}}}:
      do IO<Drive<E, G>>:
        aborted : Bool <- Abort.aborted(Reason, parent)
        timestamp : F64 <- Date.now()
        drive(~Reason, ~E, ~G, ~details, ~describe, events, source, parent, ending(E, G, reading, aborted, timestamp, details))
    case Received{reading, Done{Some{chunk}}}: drive(~Reason, ~E, ~G, ~details, ~describe, events, source, parent, chunkStep(E, G, reading, chunk))
    case Publish{next, values}:
      do IO<Drive<E, G>>:
        publish(G, events, values)
        drive(~Reason, ~E, ~G, ~details, ~describe, events, source, parent, next)
    case other: IO.pure(Drive<E, G>, other)

def settled(~Reason: Data, ~E: Data, ~G: Data, +events: EventStream(G), +parent: Signal(Reason), drive: Drive<E, G>) -> IO(Unit):
  match drive:
    case Ended{step}: finalStep(G, events, step)
    case Thrown{state, message}: fail(~Reason, ~G, events, state, parent, message)
    case _: IO.pure(Unit, Unit{})

# `start`, the event loop and its ending over one response body source.
def streamBody(~Reason: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~describe: E -> String, +events: EventStream(G), source: Body.Source<E>, +parent: Signal(Reason), +state: Fold.State<G>) -> IO(Unit):
  do IO<Unit>:
    publish(G, events, T.Start{Fold.stateMessage(G, state)} <> Nil{})
    result : Drive<E, G> <- drive(~Reason, ~E, ~G, ~details, ~describe, events, source, parent, Pull{Reading{Fold.createDecoder(), state}})
    settled(~Reason, ~E, ~G, events, parent, result)

def renderedHook(~E: Data, ~render: E -> String, result: Result<&2, &2, E, Unit>) -> Result<&2, &2, String, Unit>:
  match result:
    case Fail{cause}: Fail{render(cause)}
    case Done{_}: Done{Unit{}}

# Responses
# ---------
def responseHook(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, response: T.ProviderResponse, model: T.Model<J()>) -> IO(Result<&2, &2, String, Unit>):
  match hook:
    case None{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case Some{callback}:
      do IO<Result<&2, &2, String, Unit>>:
        result : Result<&2, &2, E, Unit> <- C.call(T.ResponseInput<T.Model<J()>>, Result<&2, &2, E, Unit>, callback, T.ResponseInput{response, model})
        return renderedHook(~E, ~render, result)

def providerResponse(+metadata: Metadata.Metadata) -> T.ProviderResponse:
  T.ProviderResponse{F.fromU32(Metadata.metadataStatus(metadata)), ProviderHeaders.headersToRecord(Metadata.headers(metadata))}

def borrowedBody(~Reason: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, +events: EventStream(G), +parent: Signal(Reason), +state: Fold.State<G>, pair: Sse.Body(Reason) & Body.Source<Sse.ReadError<Sse.TransportError(Reason)>>) -> IO(Unit):
  match pair:
    case (owner, source):
      do IO<Unit>:
        streamBody(~Reason, ~(Sse.ReadError<Sse.TransportError(Reason)>), ~G, ~details, ~(describeRead(Reason)), events, source, parent, state)
        closed : Result<&2, &2, Sse.ReadError<Sse.TransportError(Reason)>, Unit> <- Source.dispose(Client.State(Reason), Sse.ReadError<Sse.TransportError(Reason)>, owner)
        return Unit{}

# An HTTP response body becomes a chunk source that owns its transport.
def httpBody(~Reason: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, +events: EventStream(G), +parent: Signal(Reason), +state: Fold.State<G>, body: Response.Body<Client.State(Reason)>) -> IO(Unit):
  do IO<Unit>:
    owner : Sse.Body(Reason) <- Source.create(~(Client.ReadError(Reason)), ~(Client.State(Reason)), ~(Sse.ReadError<Sse.TransportError(Reason)>), ~(Sse.classify(Reason)), ~(Client.read(Reason)), ~(Client.close(Reason)), body)
    borrowedBody(~Reason, ~G, ~details, events, parent, state, Source.borrow(Client.State(Reason), Sse.ReadError<Sse.TransportError(Reason)>, owner))

def httpHooked(~Reason: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, +events: EventStream(G), +parent: Signal(Reason), +state: Fold.State<G>, response: Response.Response<Client.State(Reason)>, hooked: Result<&2, &2, String, Unit>) -> IO(Unit):
  match hooked response:
    case Fail{message} value:
      do IO<Unit>:
        released : Result<&2, &2, Progress.ResponseProgressError<Client.ReadError(Reason)>, Unit> <- Client.release(Reason, value)
        fail(~Reason, ~G, events, state, parent, message)
    case Done{_} Response.Response{_, body}: httpBody(~Reason, ~G, ~details, events, parent, state, body)

def httpResponse(~Reason: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +state: Fold.State<G>, +model: T.Model<J()>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, response: Response.Response<Client.State(Reason)>) -> IO(Unit):
  match response:
    case Response.Response{+metadata, body}:
      do IO<Unit>:
        hooked : Result<&2, &2, String, Unit> <- responseHook(~Reason, ~E, ~G, ~render, hook, providerResponse(metadata), model)
        httpHooked(~Reason, ~G, ~details, events, parent, state, Response.Response{metadata, body}, hooked)

def injectedHooked(~Reason: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, +events: EventStream(G), +parent: Signal(Reason), +state: Fold.State<G>, +source: Body.Source<String>, hooked: Result<&2, &2, String, Unit>) -> IO(Unit):
  match hooked:
    case Fail{message}:
      do IO<Unit>:
        closed : Result<&2, &2, String, Unit> <- Body.closeSource(String, source)
        fail(~Reason, ~G, events, state, parent, message)
    case Done{_}:
      do IO<Unit>:
        streamBody(~Reason, ~String, ~G, ~details, ~(message => message), events, source, parent, state)
        closed : Result<&2, &2, String, Unit> <- Body.closeSource(String, source)
        return Unit{}

def injectedResponse(~Reason: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +state: Fold.State<G>, +model: T.Model<J()>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, response: ClientResponse) -> IO(Unit):
  match response:
    case ClientResponse{status, headers, source}:
      do IO<Unit>:
        hooked : Result<&2, &2, String, Unit> <- responseHook(~Reason, ~E, ~G, ~render, hook, T.ProviderResponse{status, headers}, model)
        injectedHooked(~Reason, ~G, ~details, events, parent, state, source, hooked)

# Acquisition
# -----------
type AttemptEnvironment<-Reason: Data> is Data:
  AttemptEnvironment{request: Client.Request, parent: Signal(Reason), fetch: Fetch.Fetch(Reason)}

def attemptBody(~Reason: Data, environment: AttemptEnvironment<Reason>, unused: Unit) -> IO(Client.Outcome(Reason)):
  match environment:
    case AttemptEnvironment{request, parent, fetch}: Client.attemptWith(~Reason, raw => Client.decodeWhole(raw), request, parent, fetch, 65536n)

def Acquired(-Reason: Data) -> Type: Result<&2, &1, String, Response.Response<Client.State(Reason)>>

def retried(-Reason: Data, result: Result<&2, &1, Retry.RetryFailure<Client.AttemptError<Reason>>, Response.Response<Client.State(Reason)>>) -> Acquired(Reason):
  match result:
    case Fail{cause}: Fail{describeRetry(Reason, cause)}
    case Done{response}: Done{response}

def attemptWithEffects(~Reason: Data, environment: AttemptEnvironment<Reason>, retry: Retry.ProviderRetryOptions<Reason>, date: C.Callback<String, F64>, pair: Retry.Runtime<Reason> & Retry.Effects<Reason>) -> IO(Acquired(Reason)):
  match pair:
    case (owner, effects):
      do IO<Acquired(Reason)>:
        +request : C.Callback<Unit, Client.Outcome(Reason)> <- C.create(~AttemptEnvironment<Reason>, ~Unit, ~(Client.Outcome(Reason)), ~(attemptBody(~Reason)), environment)
        result : Result<&2, &1, Retry.RetryFailure<Client.AttemptError<Reason>>, Response.Response<Client.State(Reason)>> <- Retry.retryProviderRequestOwned(Reason, Client.AttemptError<Reason>, Response.Response<Client.State(Reason)>, request, effects, retry)
        C.dispose(Unit, Client.Outcome(Reason), request)
        Retry.dispose(Reason, owner)
        C.dispose(String, F64, date)
        return retried(Reason, result)

def attempted(~Reason: Data, environment: AttemptEnvironment<Reason>, retry: Retry.ProviderRetryOptions<Reason>, date: C.Callback<String, F64>, seeded: Result<&2, &1, Seed.SeedError, Retry.Runtime<Reason>>) -> IO(Acquired(Reason)):
  match seeded:
    case Fail{cause}:
      do IO<Acquired(Reason)>:
        C.dispose(String, F64, date)
        return Fail{Client.describeEntropy(cause)}
    case Done{runtime}: attemptWithEffects(~Reason, environment, retry, date, Retry.borrow(Reason, runtime))

# retryProviderRequest around `create(params, { maxRetries: 0 }).asResponse()`.
def acquire(~Reason: Data, fetch: Fetch.Fetch(Reason), request: Client.Request, parent: Signal(Reason), retry: Retry.ProviderRetryOptions<Reason>) -> IO(Acquired(Reason)):
  do IO<Acquired(Reason)>:
    +date : C.Callback<String, F64> <- Retry.dateParser()
    seeded : Result<&2, &1, Seed.SeedError, Retry.Runtime<Reason>> <- Retry.new(~Reason, date)
    attempted(~Reason, AttemptEnvironment{request, parent, fetch}, retry, date, seeded)

def acquiredResponse(~Reason: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +state: Fold.State<G>, +model: T.Model<J()>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, result: Acquired(Reason)) -> IO(Unit):
  match result:
    case Fail{message}: fail(~Reason, ~G, events, state, parent, message)
    case Done{response}: httpResponse(~Reason, ~E, ~G, ~details, ~render, events, parent, state, model, hook, response)

def requested(~Reason: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +state: Fold.State<G>, +model: T.Model<J()>, fetch: Fetch.Fetch(Reason), hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, request: Result<&2, &2, Client.RequestError, Client.Request>, retry: Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>) -> IO(Unit):
  match request retry:
    case Fail{cause} _: fail(~Reason, ~G, events, state, parent, describeRequest(cause))
    case _ Fail{cause}: fail(~Reason, ~G, events, state, parent, describeRetryOptions(cause))
    case Done{value} Done{options}:
      do IO<Unit>:
        result : Acquired(Reason) <- acquire(~Reason, fetch, value, parent, options)
        acquiredResponse(~Reason, ~E, ~G, ~details, ~render, events, parent, state, model, hook, result)

def injected(~Reason: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +state: Fold.State<G>, +model: T.Model<J()>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, result: Result<&2, &2, String, ClientResponse>) -> IO(Unit):
  match result:
    case Fail{message}: fail(~Reason, ~G, events, state, parent, message)
    case Done{response}: injectedResponse(~Reason, ~E, ~G, ~details, ~render, events, parent, state, model, hook, response)

def modelBaseUrl(model: T.Model<J()>) -> String:
  match model:
    case T.Model{_, _, _, _, base, _, _, _, _, _, _, _, _, _, _, _}: base

def optionsBase(-Reason: Data, -Telemetry: Data, -E: Data, options: Options(Reason, Telemetry, E)) -> T.StreamOptions<J(), Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>:
  match options:
    case Messages.AnthropicOptions{base, _, _, _, _, _, _, _}: base

def optionsClient(-Reason: Data, -Telemetry: Data, -E: Data, options: Options(Reason, Telemetry, E)) -> Maybe<&2, AnthropicClient()>:
  match options:
    case Messages.AnthropicOptions{_, _, _, _, _, _, _, client}: client

def optionsEffort(-Reason: Data, -Telemetry: Data, -E: Data, options: Options(Reason, Telemetry, E)) -> Maybe<&2, String>:
  match options:
    case Messages.AnthropicOptions{_, _, _, effort, _, _, _, _}: effort

def payloadHook(-Reason: Data, -Telemetry: Data, -E: Data, base: T.StreamOptions<J(), Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>) -> Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>:
  match base:
    case T.StreamOptions{_, _, _, _, _, hook, _, _, _, _, _, _, _, _, _, _, _, _, _}: hook

def setupFetch(-Reason: Data, +setup: Setup<Reason>) -> Fetch.Fetch(Reason):
  match setup:
    case Setup{_, _, _, fetch}: fetch

def setupAgent(-Reason: Data, +setup: Setup<Reason>) -> String:
  match setup:
    case Setup{_, _, agent, _}: agent

def isNone(retention: T.CacheRetention) -> Bool:
  match retention:
    case T.CacheNone{}: True{}
    case _: False{}

def baseRetention(-Reason: Data, -Telemetry: Data, -E: Data, base: T.StreamOptions<J(), Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>) -> IO(T.CacheRetention):
  match base:
    case T.StreamOptions{_, _, _, _, env, _, _, _, _, _, _, _, _, _, _, retention, _, _, _}: Messages.resolveCacheRetention(retention, env)

def baseAuthorized(-Reason: Data, -Telemetry: Data, -E: Data, base: T.StreamOptions<J(), Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>) -> Bool:
  match base:
    case T.StreamOptions{_, _, key, _, _, _, _, headers, _, _, _, _, _, _, _, _, _, _, _}: Messages.hasRequestAuth(key, headers)

def requestAuthorized(-Reason: Data, -Telemetry: Data, -E: Data, options: Options(Reason, Telemetry, E)) -> Bool:
  baseAuthorized(Reason, Telemetry, E, optionsBase(Reason, Telemetry, E, options))

# `client.beta.messages.create(params)` as one SDK request.
def prepareRequest(context: URL.Context, defaults: Client.Defaults, created: Messages.CreatedClient, baseUrl: String, timeout: Maybe<&2, F64>, payload: J()) -> Result<&2, &2, Client.RequestError, Client.Request>:
  match created:
    case Messages.CreatedClient{auth, headers, _}: addressedRequest(defaults, auth, headers, timeout, payload, URL.parse(context, address(baseUrl)))

# Entry
# -----
# What the request needs after the payload is final.
type Plan<-Reason: Data, -E: Data> is Data:
  Plan{model: T.Model<J()>, created: Maybe<&2, Messages.CreatedClient>, client: Maybe<&2, AnthropicClient()>, fetch: Fetch.Fetch(Reason), timeout: Maybe<&2, F64>, retries: Maybe<&2, F64>, delay: Maybe<&2, F64>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>}

def planModel(-Reason: Data, -E: Data, plan: Plan<Reason, E>) -> T.Model<J()>:
  match plan:
    case Plan{model, _, _, _, _, _, _, _}: model

def send(~Reason: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +state: Fold.State<G>, plan: Plan<Reason, E>, payload: J()) -> IO(Unit):
  match plan setup:
    case Plan{+model, _, Some{client}, _, _, _, _, hook} _:
      do IO<Unit>:
        result : Result<&2, &2, String, ClientResponse> <- C.call(J(), Result<&2, &2, String, ClientResponse>, client, payload)
        injected(~Reason, ~E, ~G, ~details, ~render, events, parent, state, model, hook, result)
    case Plan{+model, Some{created}, None{}, fetch, +timeout, retries, delay, hook} Setup{url, defaults, _, _}:
      requested(~Reason, ~E, ~G, ~details, ~render, events, parent, state, model, fetch, hook, prepareRequest(url, defaults, created, modelBaseUrl(model), timeout, payload), Retry.resolve(Reason, retries, delay, Some{parent}))
    case _ _: fail(~Reason, ~G, events, state, parent, "Anthropic client unavailable")

def planFor(-Reason: Data, -Telemetry: Data, -E: Data, +model: T.Model<J()>, created: Maybe<&2, Messages.CreatedClient>, client: Maybe<&2, AnthropicClient()>, default: Fetch.Fetch(Reason), base: T.StreamOptions<J(), Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>) -> Plan<Reason, E>:
  match base:
    case T.StreamOptions{_, _, _, fetch, _, _, hook, _, timeout, retries, delay, _, _, _, _, _, _, _, _}: Plan{model, created, client, Maybe.default(&2, Fetch.Fetch(Reason), fetch, default), timeout, retries, delay, hook}

def createdOauth(created: Messages.CreatedClient) -> Bool:
  match created:
    case Messages.CreatedClient{_, _, oauth}: oauth

# A replacement payload keeps streaming on: `{ ...nextParams, stream: true }`.
def streaming(value: J()) -> J():
  match value:
    case T.JsonObject{fields}: T.JsonObject{R.set(J(), fields, "stream", T.JsonBoolean{True{}})}
    case _: T.JsonObject{R.Record{R.Property{"stream", T.JsonBoolean{True{}}} <> Nil{}}}

def replaced(original: J(), replacement: Maybe<&2, J()>) -> J():
  match replacement:
    case None{}: original
    case Some{value}: streaming(value)

def payloaded(~Reason: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +state: Fold.State<G>, plan: Plan<Reason, E>, original: J(), result: Result<&2, &2, E, Maybe<&2, J()>>) -> IO(Unit):
  match result:
    case Fail{cause}: fail(~Reason, ~G, events, state, parent, render(cause))
    case Done{replacement}: send(~Reason, ~E, ~G, ~details, ~render, events, parent, setup, state, plan, replaced(original, replacement))

def withPayload(~Reason: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +state: Fold.State<G>, +plan: Plan<Reason, E>, +params: J(), hook: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>) -> IO(Unit):
  match hook:
    case None{}: send(~Reason, ~E, ~G, ~details, ~render, events, parent, setup, state, plan, params)
    case Some{callback}:
      do IO<Unit>:
        result : Result<&2, &2, E, Maybe<&2, J()>> <- C.call(T.PayloadInput<J(), T.Model<J()>>, Result<&2, &2, E, Maybe<&2, J()>>, callback, T.PayloadInput{params, planModel(Reason, E, plan)})
        payloaded(~Reason, ~E, ~G, ~details, ~render, events, parent, setup, state, plan, params, result)

def built(~Reason: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +state: Fold.State<G>, +plan: Plan<Reason, E>, hook: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>, params: Result<&2, &2, String, J()>) -> IO(Unit):
  match params:
    case Fail{message}: fail(~Reason, ~G, events, state, parent, message)
    case Done{+payload}: withPayload(~Reason, ~E, ~G, ~details, ~render, events, parent, setup, state, plan, payload, hook)

# The client is known; build the params with its OAuth shaping.
def clientReady(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Options(Reason, Telemetry, E), timestamp: F64, created: Maybe<&2, Messages.CreatedClient>, +oauth: Bool) -> IO(Unit):
  +base = optionsBase(Reason, Telemetry, E, options)
  +level = Bool.pick(Maybe<&2, String>, Messages.supportsMidConvoEffort(model), Some{Maybe.default(&2, String, optionsEffort(Reason, Telemetry, E, options), "high")}, None{})
  +state = Fold.create(G, model, timestamp, level, oauth, Transcript.getCurrentTools(V.Value, V.Value, G, D, Messages.contextMessages(G, D, context)))
  do IO<Unit>:
    params : Result<&2, &2, String, J()> <- Messages.buildParams(~G, ~D, ~(Signal(Reason)), ~Telemetry, ~(Fetch.Fetch(Reason)), ~E, ~AnthropicClient(), model, context, oauth, options)
    built(~Reason, ~E, ~G, ~details, ~render, events, parent, setup, state, planFor(Reason, Telemetry, E, model, created, optionsClient(Reason, Telemetry, E, options), setupFetch(Reason, setup), base), payloadHook(Reason, Telemetry, E, base), params)

def withRetentionBase(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Options(Reason, Telemetry, E), timestamp: F64, retention: T.CacheRetention, base: T.StreamOptions<J(), Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>) -> IO(Unit):
  match base:
    case T.StreamOptions{_, _, key, _, _, _, _, headers, _, _, _, _, _, _, _, _, session, _, _}:
      +sessionId = Bool.pick(Maybe<&2, String>, isNone(retention), None{}, session)
      +created = Messages.createClient(model, setupAgent(Reason, setup), key, headers, Copilot.forProvider(V.Value, V.Value, G, D, T.modelProvider(model), Messages.contextMessages(G, D, context)), sessionId)
      clientReady(~Reason, ~Telemetry, ~E, ~G, ~details, ~D, ~render, events, parent, setup, model, context, options, timestamp, Some{created}, createdOauth(created))

# Without an injected client: assert auth, add Copilot's dynamic headers,
# resolve cache retention for the session id and create the client.
def withRetention(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Options(Reason, Telemetry, E), timestamp: F64, retention: T.CacheRetention) -> IO(Unit):
  withRetentionBase(~Reason, ~Telemetry, ~E, ~G, ~details, ~D, ~render, events, parent, setup, model, context, options, timestamp, retention, optionsBase(Reason, Telemetry, E, options))

def authorizedStream(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Options(Reason, Telemetry, E), timestamp: F64, authorized: Bool) -> IO(Unit):
  match authorized:
    case False{}: fail(~Reason, ~G, events, Fold.create(G, model, timestamp, None{}, False{}, Nil{}), parent, "No API key for provider: " ++ T.modelProvider(model))
    case True{}:
      do IO<Unit>:
        resolved : T.CacheRetention <- baseRetention(Reason, Telemetry, E, optionsBase(Reason, Telemetry, E, options))
        withRetention(~Reason, ~Telemetry, ~E, ~G, ~details, ~D, ~render, events, parent, setup, model, context, options, timestamp, resolved)

def clientResolved(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Options(Reason, Telemetry, E), timestamp: F64, client: Maybe<&2, AnthropicClient()>) -> IO(Unit):
  match client:
    case Some{_}: clientReady(~Reason, ~Telemetry, ~E, ~G, ~details, ~D, ~render, events, parent, setup, model, context, options, timestamp, None{}, False{})
    case None{}: authorizedStream(~Reason, ~Telemetry, ~E, ~G, ~details, ~D, ~render, events, parent, setup, model, context, options, timestamp, requestAuthorized(Reason, Telemetry, E, options))

# upstream `stream`: the producer's work up to `stream.end()`. `parent` is the
# request's abort signal; `details` encodes the input transformation
# diagnostic's details as the caller's diagnostic type.
def stream(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~details: List<&2, Fold.InputTransformation> -> G, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Options(Reason, Telemetry, E), timestamp: F64) -> IO(Unit):
  +normalized = Transcript.resolveTranscript(V.Value, V.Value, G, D, context, Some{Messages.compatMidSystem(Messages.getAnthropicCompat(model))})
  clientResolved(~Reason, ~Telemetry, ~E, ~G, ~details, ~D, ~render, events, parent, setup, model, normalized, options, timestamp, optionsClient(Reason, Telemetry, E, options))
