import Base
import ../types.bend as T
import ../utils/headers.bend as ProviderHeaders
import ../utils/provider-retry.bend as Retry
import ../utils/sanitize-unicode.bend as Unicode
import ../utils/schema-json.bend as Convert
import ./openai-client.bend as Client
import ../images-models.bend as Images
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-response.bend as Metadata
import ../../../runtime/src/json.bend as Parse
import ../../../runtime/src/random.bend as Seed
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/url.bend as URL

# upstream api/openrouter-images.ts: image generation through OpenRouter's
# Chat Completions endpoint with the OpenAI SDK (openai-client.bend):
# `client.chat.completions.create(params, { maxRetries: 0 }).withResponse()`
# inside retryProviderRequest, onPayload/onResponse, and the text and
# data-URL images of the first choice. Failures never escape: they become an
# AssistantImages with stopReason "error" (or "aborted" under an aborted
# signal) and the formatted provider error.

def J() -> Data: T.JsonValue

def Model() -> Data: T.ImagesModel<J()>

def Options(-Reason: Data, -Telemetry: Data, -E: Data) -> Data: T.ImagesOptions<Abort.AbortSignal<Reason>, Telemetry, Fetch.Fetch(Reason), E>

# The response body limit: generated images arrive inline as base64.
def RESPONSE_LIMIT() -> Nat: 67108864n

# JSON helpers
# ------------

def str(value: String) -> J(): T.JsonString{value}

def obj(fields: List<&2, R.Property<J()>>) -> J(): T.JsonObject{R.Record{fields}}

def field(name: String, value: J()) -> R.Property<J()>: R.Property{name, value}

def member(value: Maybe<&2, J()>, name: String) -> Maybe<&2, J()>:
  match value:
    case Some{T.JsonObject{fields}}: R.get(J(), fields, name)
    case _: None{}

# Request
# -------

def contentPart(item: T.TextImageContent) -> J():
  match item:
    case T.TextImageText{T.TextContent{text, _}}: obj([field("type", str("text")), field("text", str(Unicode.sanitizeSurrogates(text)))])
    case T.TextImageImage{T.ImageContent{data, mimeType}}: obj([field("type", str("image_url")), field("image_url", obj([field("url", str("data:" ++ mimeType ++ ";base64," ++ data))]))])

def contentParts(items: List<&2, T.TextImageContent>) -> List<&2, J()>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: contentPart(item) <> contentParts(rest)

def outputsText(values: List<&2, T.ModelInput>) -> Bool:
  match values:
    case Nil{}: False{}
    case T.InputText{} <> _: True{}
    case _ <> rest: outputsText(rest)

def modalities(text: Bool) -> J():
  match text:
    case True{}: T.JsonArray{[str("image"), str("text")]}
    case False{}: T.JsonArray{[str("image")]}

# upstream buildParams.
def buildParams(model: Model(), context: T.ImagesContext) -> J():
  match model context:
    case T.ImagesModel{id, _, _, _, _, _, _, _, _, _, _, _, output} T.ImagesContext{input}:
      obj([field("model", str(id)), field("messages", T.JsonArray{[obj([field("role", str("user")), field("content", T.JsonArray{contentParts(input)})])]}), field("stream", T.JsonBoolean{False{}}), field("modalities", modalities(outputsText(output)))])

# createClient's defaultHeaders: providerHeadersToRecord({...model.headers,
# ...options.headers}); null values are dropped, not sent as removals.
def presentHeaders(value: Maybe<&2, R.Record<String>>) -> T.ProviderHeaders():
  match value:
    case Some{record}: ProviderHeaders.fromRecord(record)
    case None{}: R.new(T.Nullable<String>)

def modelHeaders(model: Model()) -> Maybe<&2, R.Record<String>>:
  match model:
    case T.ImagesModel{_, _, _, _, _, _, _, _, _, _, _, headers, _}: headers

def clientHeaders(modelHeaders: Maybe<&2, R.Record<String>>, optionHeaders: Maybe<&2, T.ProviderHeaders()>) -> T.ProviderHeaders():
  presentHeaders(ProviderHeaders.providerHeadersToRecord(Some{ProviderHeaders.overlay(ProviderHeaders.overlayStrings(R.new(T.Nullable<String>), modelHeaders), optionHeaders)}))

# Output
# ------

def zero() -> F64: F.fromU32(0)

def million() -> F64: F.fromU32(1000000)

def createOutput(model: Model(), timestamp: F64) -> T.AssistantImages:
  match model:
    case T.ImagesModel{id, _, api, provider, _, _, _, _, _, _, _, _, _}: T.AssistantImages{api, provider, id, Nil{}, None{}, None{}, T.ImagesStop{}, None{}, timestamp}

def responseIdOf(value: Maybe<&2, J()>) -> Maybe<&2, String>:
  match value:
    case Some{T.JsonString{id}}: Some{id}
    case _: None{}

def failedOutput(output: T.AssistantImages, aborted: Bool, message: String) -> T.AssistantImages:
  match output:
    case T.AssistantImages{api, provider, model, content, responseId, usage, _, _, timestamp}:
      T.AssistantImages{api, provider, model, content, responseId, usage, Bool.pick(T.ImagesStopReason, aborted, T.ImagesAborted{}, T.ImagesError{}), Some{message}, timestamp}

# `x || 0` for a token count.
def count(value: Maybe<&2, J()>) -> F64:
  match value:
    case Some{T.JsonNumber{+number}}: Bool.pick(F64, F.isNaN(number), zero(), number)
    case _: zero()

def positive(+value: F64) -> F64: Bool.pick(F64, F.isGreater(F.compare(value, zero())), value, zero())

def rate(price: F64, tokens: F64) -> F64: F.multiply(F.divide(price, million()), tokens)

def costOf(cost: T.ModelCost, input: F64, output: F64, cacheRead: F64, cacheWrite: F64) -> T.UsageCost:
  match cost:
    case T.ModelCost{inputPrice, outputPrice, readPrice, writePrice, _}:
      +a = rate(inputPrice, input)
      +b = rate(outputPrice, output)
      +c = rate(readPrice, cacheRead)
      +d = rate(writePrice, cacheWrite)
      T.UsageCost{a, b, c, d, F.add(F.add(F.add(a, b), c), d)}

def usageWith(cost: T.ModelCost, +prompt: F64, +cached: F64, +written: F64, +completion: F64) -> T.Usage:
  +read = Bool.pick(F64, F.isGreater(F.compare(written, zero())), positive(F.subtract(cached, written)), cached)
  +input = positive(F.subtract(F.subtract(prompt, read), written))
  T.Usage{input, completion, read, written, None{}, None{}, F.add(F.add(F.add(input, completion), read), written), costOf(cost, input, completion, read, written)}

# upstream parseUsage.
def parseUsage(model: Model(), +raw: Maybe<&2, J()>) -> T.Usage:
  match model:
    case T.ImagesModel{_, _, _, _, _, _, _, _, cost, _, _, _, _}:
      +details = member(raw, "prompt_tokens_details")
      usageWith(cost, count(member(raw, "prompt_tokens")), count(member(details, "cached_tokens")), count(member(details, "cache_write_tokens")), count(member(raw, "completion_tokens")))

def truthy(value: Maybe<&2, J()>) -> Bool:
  match value:
    case None{}: False{}
    case Some{T.JsonNull{}}: False{}
    case Some{T.JsonBoolean{flag}}: flag
    case Some{T.JsonString{SNil{}}}: False{}
    case Some{T.JsonNumber{+number}}: Bool.not(F.isNaN(number)) && Bool.not(F.isEqual(F.compare(number, zero())))
    case _: True{}

# `.` in the data-URL pattern excludes line terminators.
def lineTerminator(c: Char) -> Bool:
  +code = Char.to_u32(c)
  U32.is_eq(code, 10) || U32.is_eq(code, 13) || U32.is_eq(code, 8232) || U32.is_eq(code, 8233)

def singleLine(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{c, rest}: Bool.not(lineTerminator(c)) && singleLine(rest)

def base64Data(mime: String, rest: String) -> Maybe<&2, T.ImageContent>:
  match rest:
    case SCon{+c, +cs}: Bool.pick(Maybe<&2, T.ImageContent>, singleLine(SCon{c, cs}), Some{T.ImageContent{SCon{c, cs}, mime}}, None{})
    case SNil{}: None{}

def stripPrefix(+text: String, +prefix: String) -> Maybe<&2, String>:
  Bool.pick(Unit -> Maybe<&2, String>, String.starts_with(text, prefix), _ => Some{String.drop(text, String.length(prefix))}, _ => None{})(Unit{})

def encoded(mime: String, value: Maybe<&2, String>) -> Maybe<&2, T.ImageContent>:
  match value:
    case Some{data}: base64Data(mime, data)
    case None{}: None{}

def afterMime(mime: String, rest: String) -> Maybe<&2, T.ImageContent>: encoded(mime, stripPrefix(rest, ";base64,"))

def mimeAt(mime: String, rest: String) -> Maybe<&2, T.ImageContent>:
  match mime:
    case SNil{}: None{}
    case SCon{c, cs}: afterMime(SCon{c, cs}, rest)

# /^data:([^;]+);base64,(.+)$/ after the "data:" prefix: the media type runs
# to the first ";".
def mediaType(rest: String, +reversed: String) -> Maybe<&2, T.ImageContent>:
  match rest:
    case SNil{}: None{}
    case SCon{+c, +cs}:
      Bool.pick(Unit -> Maybe<&2, T.ImageContent>, Char.is_eq(c, ';'), _ => mimeAt(String.reverse(reversed), SCon{c, cs}), _ => mediaType(cs, SCon{c, reversed}))(Unit{})

def dataRest(value: Maybe<&2, String>) -> Maybe<&2, T.ImageContent>:
  match value:
    case Some{rest}: mediaType(rest, SNil{})
    case None{}: None{}

def dataImage(url: String) -> Maybe<&2, T.ImageContent>: dataRest(stripPrefix(url, "data:"))

def urlText(value: Maybe<&2, J()>) -> Maybe<&2, String>:
  match value:
    case Some{T.JsonString{url}}: Some{url}
    case _: None{}

# `typeof image.image_url === "string" ? image.image_url : image.image_url?.url`
def imageUrl(value: Maybe<&2, J()>) -> Maybe<&2, String>:
  match value:
    case Some{T.JsonString{url}}: Some{url}
    case Some{T.JsonObject{fields}}: urlText(R.get(J(), fields, "url"))
    case _: None{}

def urlImage(value: Maybe<&2, String>) -> Maybe<&2, T.ImageContent>:
  match value:
    case Some{url}: dataImage(url)
    case None{}: None{}

def generated(image: J()) -> Maybe<&2, T.ImageContent>: urlImage(imageUrl(member(Some{image}, "image_url")))

def prependImage(image: Maybe<&2, T.ImageContent>, rest: List<&2, T.TextImageContent>) -> List<&2, T.TextImageContent>:
  match image:
    case Some{value}: T.TextImageImage{value} <> rest
    case None{}: rest

def images(values: List<&2, J()>) -> List<&2, T.TextImageContent>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: prependImage(generated(value), images(rest))

def imageList(value: Maybe<&2, J()>) -> List<&2, T.TextImageContent>:
  match value:
    case Some{T.JsonArray{items}}: images(items)
    case _: Nil{}

def textOutput(value: Maybe<&2, J()>) -> List<&2, T.TextImageContent>:
  match value:
    case Some{T.JsonString{SCon{c, cs}}}: [T.TextImageText{T.TextContent{SCon{c, cs}, None{}}}]
    case _: Nil{}

def choiceOutput(+message: Maybe<&2, J()>) -> List<&2, T.TextImageContent>:
  List.append(&2, T.TextImageContent, textOutput(member(message, "content")), imageList(member(message, "images")))

def firstChoice(choices: Maybe<&2, J()>) -> Result<&2, &2, String, List<&2, T.TextImageContent>>:
  match choices:
    case Some{T.JsonArray{Nil{}}}: Done{Nil{}}
    case Some{T.JsonArray{choice <> _}}: Done{choiceOutput(member(Some{choice}, "message"))}
    case _: Fail{"Cannot read properties of undefined (reading '0')"}

def usageOf(model: Model(), +raw: Maybe<&2, J()>) -> Maybe<&2, T.Usage>:
  Bool.pick(Unit -> Maybe<&2, T.Usage>, truthy(raw), _ => Some{parseUsage(model, raw)}, _ => None{})(Unit{})

# upstream fills the output in place, so a failure after the responseId and
# usage were read keeps them.
type Collected is Data:
  Collected{output: T.AssistantImages, error: Maybe<&2, String>}

def withOutput(output: T.AssistantImages, id: Maybe<&2, String>, usage: Maybe<&2, T.Usage>, content: Result<&2, &2, String, List<&2, T.TextImageContent>>) -> Collected:
  match output content:
    case T.AssistantImages{api, provider, model, items, _, _, stop, error, timestamp} Fail{message}: Collected{T.AssistantImages{api, provider, model, items, id, usage, stop, error, timestamp}, Some{message}}
    case T.AssistantImages{api, provider, model, _, _, _, stop, error, timestamp} Done{items}: Collected{T.AssistantImages{api, provider, model, items, id, usage, stop, error, timestamp}, None{}}

# The response handling after `withResponse()`: responseId, usage when
# truthy, then the first choice's text and data-URL images.
def collected(model: Model(), output: T.AssistantImages, +response: J()) -> Collected:
  +body = {Some{response} : Maybe<&2, J()>}
  withOutput(output, responseIdOf(member(body, "id")), usageOf(model, member(body, "usage")), firstChoice(member(body, "choices")))

# Failures
# --------

type Failure<-Reason: Data, -E: Data> is Data:
  Unauthorized{message: String}
  HookFailure{cause: E}
  RequestRejected{cause: Client.RequestError}
  InvalidRetryOptions{cause: Retry.OptionsError}
  EntropyFailure{cause: Seed.SeedError}
  RequestFailure{cause: Retry.RetryFailure<Client.AttemptError<Reason>>}
  BodyFailure{cause: Response.TextError<Client.ReadError(Reason)>}
  InvalidBody{}
  ResponseFailure{message: String}

def describeRetryOptions(cause: Retry.OptionsError) -> String:
  match cause:
    case Retry.InvalidRetryCount{_}: "maxRetries must be a non-negative integer within the native natural-number range"
    case Retry.InvalidDelayLimit{_}: "maxRetryDelayMs must be finite and non-negative"

# formatProviderError(normalizeProviderError(error)) with no prefix.
def describe(~Reason: Data, ~E: Data, ~render: E -> String, failure: Failure<Reason, E>) -> String:
  match failure:
    case Unauthorized{message}: message
    case HookFailure{cause}: render(cause)
    case RequestRejected{cause}: Client.describeRequest(cause)
    case InvalidRetryOptions{cause}: describeRetryOptions(cause)
    case EntropyFailure{cause}: Client.describeEntropy(cause)
    case RequestFailure{cause}: Client.describeRetry(Reason, cause, None{})
    case BodyFailure{_}: "Could not read the response body"
    case InvalidBody{}: "The response body is not valid JSON"
    case ResponseFailure{message}: message

def failed(~Reason: Data, ~E: Data, ~render: E -> String, parent: Abort.AbortSignal<Reason>, output: T.AssistantImages, failure: Failure<Reason, E>) -> IO(T.AssistantImages):
  do IO<T.AssistantImages>:
    aborted : Bool <- Abort.aborted(Reason, parent)
    return failedOutput(output, aborted, describe(~Reason, ~E, ~render, failure))

# Request lifecycle
# -----------------

type AttemptEnvironment<-Reason: Data> is Data:
  AttemptEnvironment{request: Client.Request, parent: Abort.AbortSignal<Reason>, fetch: Fetch.Fetch(Reason), diagnosticLimit: Nat}

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
def acquire(~Reason: Data, ~E: Data, fetch: Fetch.Fetch(Reason), request: Client.Request, parent: Abort.AbortSignal<Reason>, retry: Retry.ProviderRetryOptions<Reason>) -> IO(Acquired(Reason, E)):
  do IO<Acquired(Reason, E)>:
    +date : C.Callback<String, F64> <- Retry.dateParser()
    seeded : Result<&2, &1, Seed.SeedError, Retry.Runtime<Reason>> <- Retry.new(~Reason, date)
    attempted(~Reason, ~E, AttemptEnvironment{request, parent, fetch, 65536n}, retry, date, seeded)

def providerResponse(+metadata: Metadata.Metadata) -> T.ProviderResponse:
  T.ProviderResponse{F.fromU32(Metadata.metadataStatus(metadata)), ProviderHeaders.headersToRecord(Metadata.headers(metadata))}

def jsonBody(-Reason: Data, -E: Data, value: Result<&2, &2, Parse.ParseError, V.Value>) -> Result<&2, &2, Failure<Reason, E>, J()>:
  match value:
    case Fail{_}: Fail{InvalidBody{}}
    case Done{parsed}: Done{Convert.toJson(parsed)}

def parsedBody(-Reason: Data, -E: Data, text: Result<&2, &2, Response.TextError<Client.ReadError(Reason)>, String>) -> Result<&2, &2, Failure<Reason, E>, J()>:
  match text:
    case Fail{cause}: Fail{BodyFailure{cause}}
    case Done{+body}: jsonBody(Reason, E, Parse.parse(body))

def finished(~Reason: Data, ~E: Data, ~render: E -> String, parent: Abort.AbortSignal<Reason>, result: Collected) -> IO(T.AssistantImages):
  match result:
    case Collected{partial, Some{message}}: failed(~Reason, ~E, ~render, parent, partial, ResponseFailure{message})
    case Collected{value, None{}}: IO.pure(T.AssistantImages, value)

def notified(~Reason: Data, ~E: Data, ~render: E -> String, parent: Abort.AbortSignal<Reason>, model: Model(), +output: T.AssistantImages, body: J(), hooked: Result<&2, &2, E, Unit>) -> IO(T.AssistantImages):
  match hooked:
    case Fail{cause}: failed(~Reason, ~E, ~render, parent, output, HookFailure{cause})
    case Done{_}: finished(~Reason, ~E, ~render, parent, collected(model, output, body))

# onResponse sees the status and headers once withResponse() has the parsed
# body.
def notify(~Reason: Data, ~E: Data, ~render: E -> String, parent: Abort.AbortSignal<Reason>, +model: Model(), output: T.AssistantImages, hook: Maybe<&2, T.ResponseCallback(Model(), E)>, metadata: Metadata.Metadata, body: Result<&2, &2, Failure<Reason, E>, J()>) -> IO(T.AssistantImages):
  match body hook:
    case Fail{cause} _: failed(~Reason, ~E, ~render, parent, output, cause)
    case Done{value} None{}: notified(~Reason, ~E, ~render, parent, model, output, value, Done{Unit{}})
    case Done{value} Some{callback}:
      do IO<T.AssistantImages>:
        hooked : Result<&2, &2, E, Unit> <- C.call(T.ResponseInput<Model()>, Result<&2, &2, E, Unit>, callback, T.ResponseInput{providerResponse(metadata), model})
        notified(~Reason, ~E, ~render, parent, model, output, value, hooked)

def received(~Reason: Data, ~E: Data, ~render: E -> String, parent: Abort.AbortSignal<Reason>, model: Model(), output: T.AssistantImages, hook: Maybe<&2, T.ResponseCallback(Model(), E)>, response: Response.Response<Client.State(Reason)>) -> IO(T.AssistantImages):
  match response:
    case Response.Response{+metadata, body}:
      do IO<T.AssistantImages>:
        text : Result<&2, &2, Response.TextError<Client.ReadError(Reason)>, String> <- Response.textWith(~(Client.ReadError(Reason)), ~(Client.State(Reason)), ~(Client.read(Reason)), ~(Client.close(Reason)), RESPONSE_LIMIT(), body)
        notify(~Reason, ~E, ~render, parent, model, output, hook, metadata, parsedBody(Reason, E, text))

def acquired(~Reason: Data, ~E: Data, ~render: E -> String, parent: Abort.AbortSignal<Reason>, model: Model(), output: T.AssistantImages, hook: Maybe<&2, T.ResponseCallback(Model(), E)>, result: Acquired(Reason, E)) -> IO(T.AssistantImages):
  match result:
    case Fail{cause}: failed(~Reason, ~E, ~render, parent, output, cause)
    case Done{response}: received(~Reason, ~E, ~render, parent, model, output, hook, response)

type Setup<-Reason: Data, -E: Data> is Data:
  Setup{urlContext: URL.Context, defaults: Client.Defaults, fetch: Fetch.Fetch(Reason), key: String, headers: T.ProviderHeaders(), timeout: Maybe<&2, F64>, retries: Maybe<&2, F64>, delay: Maybe<&2, F64>, onResponse: Maybe<&2, T.ResponseCallback(Model(), E)>}

def requested(~Reason: Data, ~E: Data, ~render: E -> String, +parent: Abort.AbortSignal<Reason>, model: Model(), output: T.AssistantImages, fetch: Fetch.Fetch(Reason), hook: Maybe<&2, T.ResponseCallback(Model(), E)>, request: Result<&2, &2, Client.RequestError, Client.Request>, retry: Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Reason>>) -> IO(T.AssistantImages):
  match request retry:
    case Fail{cause} _: failed(~Reason, ~E, ~render, parent, output, RequestRejected{cause})
    case _ Fail{cause}: failed(~Reason, ~E, ~render, parent, output, InvalidRetryOptions{cause})
    case Done{value} Done{options}:
      do IO<T.AssistantImages>:
        result : Acquired(Reason, E) <- acquire(~Reason, ~E, fetch, value, parent, options)
        acquired(~Reason, ~E, ~render, parent, model, output, hook, result)

def modelBaseUrl(model: Model()) -> String:
  match model:
    case T.ImagesModel{_, _, _, _, baseUrl, _, _, _, _, _, _, _, _}: baseUrl

def configured(~Reason: Data, ~E: Data, ~render: E -> String, +parent: Abort.AbortSignal<Reason>, +model: Model(), output: T.AssistantImages, setup: Setup<Reason, E>, payload: J()) -> IO(T.AssistantImages):
  match setup:
    case Setup{urlContext, defaults, fetch, key, headers, timeout, retries, delay, hook}:
      requested(~Reason, ~E, ~render, parent, model, output, fetch, hook, Client.prepareChatRequest(urlContext, defaults, key, headers, modelBaseUrl(model), timeout, payload), Retry.resolve(Reason, retries, delay, Some{parent}))

# `nextParams !== undefined` replaces the params.
def payloaded(~Reason: Data, ~E: Data, ~render: E -> String, +parent: Abort.AbortSignal<Reason>, +model: Model(), output: T.AssistantImages, setup: Setup<Reason, E>, +original: J(), result: Result<&2, &2, E, Maybe<&2, J()>>) -> IO(T.AssistantImages):
  match result:
    case Fail{cause}: failed(~Reason, ~E, ~render, parent, output, HookFailure{cause})
    case Done{replacement}: configured(~Reason, ~E, ~render, parent, model, output, setup, Maybe.default(&2, J(), replacement, original))

def withPayload(~Reason: Data, ~E: Data, ~render: E -> String, +parent: Abort.AbortSignal<Reason>, +model: Model(), output: T.AssistantImages, setup: Setup<Reason, E>, +params: J(), hook: Maybe<&2, T.PayloadCallback(J(), Model(), E)>) -> IO(T.AssistantImages):
  match hook:
    case None{}: payloaded(~Reason, ~E, ~render, parent, model, output, setup, params, Done{None{}})
    case Some{callback}:
      do IO<T.AssistantImages>:
        result : Result<&2, &2, E, Maybe<&2, J()>> <- C.call(T.PayloadInput<J(), Model()>, Result<&2, &2, E, Maybe<&2, J()>>, callback, T.PayloadInput{params, model})
        payloaded(~Reason, ~E, ~render, parent, model, output, setup, params, result)

def modelProvider(model: Model()) -> String:
  match model:
    case T.ImagesModel{_, _, _, provider, _, _, _, _, _, _, _, _, _}: provider

def keyed(apiKey: Maybe<&2, String>) -> Maybe<&2, String>:
  match apiKey:
    case Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: None{}

# The key check comes first, as upstream throws before building the client.
def keyChecked(~Reason: Data, ~E: Data, ~render: E -> String, +parent: Abort.AbortSignal<Reason>, +model: Model(), context: T.ImagesContext, output: T.AssistantImages, key: Maybe<&2, String>, urlContext: URL.Context, defaults: Client.Defaults, fetch: Fetch.Fetch(Reason), headers: Maybe<&2, T.ProviderHeaders()>, timeoutMs: Maybe<&2, F64>, maxRetries: Maybe<&2, F64>, maxRetryDelayMs: Maybe<&2, F64>, onPayload: Maybe<&2, T.PayloadCallback(J(), Model(), E)>, onResponse: Maybe<&2, T.ResponseCallback(Model(), E)>) -> IO(T.AssistantImages):
  match key:
    case None{}: failed(~Reason, ~E, ~render, parent, output, Unauthorized{"No API key for provider: " ++ modelProvider(model)})
    case Some{value}: withPayload(~Reason, ~E, ~render, parent, model, output, Setup{urlContext, defaults, fetch, value, clientHeaders(modelHeaders(model), headers), timeoutMs, maxRetries, maxRetryDelayMs, onResponse}, buildParams(model, context), onPayload)

def started(~Reason: Data, ~Telemetry: Data, ~E: Data, ~render: E -> String, fetch: Fetch.Fetch(Reason), urlContext: URL.Context, defaults: Client.Defaults, +parent: Abort.AbortSignal<Reason>, +model: Model(), context: T.ImagesContext, options: Options(Reason, Telemetry, E), output: T.AssistantImages) -> IO(T.AssistantImages):
  match options:
    case T.ImagesOptions{_, _, apiKey, custom, _, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, _}:
      keyChecked(~Reason, ~E, ~render, parent, model, context, output, keyed(apiKey), urlContext, defaults, Maybe.default(&2, Fetch.Fetch(Reason), custom, fetch), headers, timeoutMs, maxRetries, maxRetryDelayMs, onPayload, onResponse)

# upstream generateImages. `fetch` is the native transport unless the options
# carry a custom fetch; `defaults` are the SDK client's identity headers.
def generateImages(~Reason: Data, ~Telemetry: Data, ~E: Data, ~render: E -> String, fetch: Fetch.Fetch(Reason), urlContext: URL.Context, defaults: Client.Defaults, +parent: Abort.AbortSignal<Reason>, +model: Model(), context: T.ImagesContext, options: Maybe<&2, Options(Reason, Telemetry, E)>) -> IO(T.AssistantImages):
  do IO<T.AssistantImages>:
    timestamp : F64 <- Date.now()
    started(~Reason, ~Telemetry, ~E, ~render, fetch, urlContext, defaults, parent, model, context, Maybe.default(&2, Options(Reason, Telemetry, E), options, T.emptyImagesOptions(Abort.AbortSignal<Reason>, Telemetry, Fetch.Fetch(Reason), E)), createOutput(model, timestamp))

# upstream openrouterImagesApi (openrouter-images.lazy.ts): the api value
# providers generate through. The native transport, URL tables and SDK
# identity headers are injected; a request without a signal runs under a
# local one that never aborts.
type ImagesTransport is Data:
  ImagesTransport{fetch: Fetch.Fetch(Unit), urlContext: URL.Context, defaults: Client.Defaults}

def requestSignal(-E: Data, options: Maybe<&2, Images.Options(E)>) -> Maybe<&2, Abort.AbortSignal<Unit>>:
  match options:
    case Some{T.ImagesOptions{signal, _, _, _, _, _, _, _, _, _, _, _}}: signal
    case None{}: None{}

def signalled(~E: Data, ~render: E -> String, transport: ImagesTransport, +model: Model(), context: T.ImagesContext, options: Maybe<&2, Images.Options(E)>, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(T.AssistantImages):
  match transport signal:
    case ImagesTransport{fetch, urlContext, defaults} Some{parent}: generateImages(~Unit, ~Unit, ~E, ~render, fetch, urlContext, defaults, parent, model, context, options)
    case ImagesTransport{fetch, urlContext, defaults} None{}:
      do IO<T.AssistantImages>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        result : T.AssistantImages <- generateImages(~Unit, ~Unit, ~E, ~render, fetch, urlContext, defaults, Abort.signal(Unit, controller), model, context, options)
        Abort.dispose(Unit, controller)
        return result

def apiBody(~E: Data, ~render: E -> String, transport: ImagesTransport, request: Images.ImagesRequest<E>) -> IO(T.AssistantImages):
  match request:
    case Images.ImagesRequest{model, context, +options}: signalled(~E, ~render, transport, model, context, options, requestSignal(E, options))

def openrouterImagesApi(~E: Data, ~render: E -> String, transport: ImagesTransport) -> IO(Images.ProviderImages(E)):
  C.create(~ImagesTransport, ~(Images.ImagesRequest<E>), ~T.AssistantImages, ~(apiBody(~E, ~render)), transport)
