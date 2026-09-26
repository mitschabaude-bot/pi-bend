import Base
import ../types.bend as T
import ../utils/event-stream.bend as Events
import ../utils/headers.bend as HeaderUtils
import ../utils/provider-env.bend as Env
import ../utils/provider-retry.bend as Retry
import ../utils/json.bend as JsonWire
import ../utils/transcript.bend as Transcript
import ./google-generative-ai.bend as Google
import ./google-generative-ai-client.bend as GoogleClient
import ./google-generative-ai-stream.bend as Fold
import ./google-vertex-credentials.bend as Credentials
import ./openai-client.bend as SDK
import ./simple-options.bend as Simple
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-message.bend as H
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/url.bend as URL

# The Google Vertex AI provider (upstream api/google-vertex.ts) over the
# @google/genai 2.21.0 client in Vertex mode: an API key (x-goog-api-key on
# the global endpoint) or Application Default Credentials with a project and
# location (google-vertex-credentials.bend), pi's custom base URL handling,
# the SDK's Vertex request conversion, and the stream loop, retries and
# error handling it shares with Google Generative AI
# (google-generative-ai-client.bend, google-generative-ai-stream.bend).

def J() -> Data: T.JsonValue

def Fields() -> Data: R.Record<J()>

def Signal(-Reason: Data) -> Data: Abort.AbortSignal<Reason>

def EventStream(-G: Data) -> Data: Events.AssistantMessageEventStream(V.Value, G)

def str(value: String) -> J(): T.JsonString{value}

def obj(fields: List<&2, R.Property<J()>>) -> J(): T.JsonObject{R.Record{fields}}

def field(name: String, value: J()) -> R.Property<J()>: R.Property{name, value}

def API_VERSION() -> String: "v1"

def GCP_VERTEX_CREDENTIALS_MARKER() -> String: "gcp-vertex-credentials"

# Options
# -------

# upstream GoogleVertexOptions: GoogleOptions plus project and location.
type GoogleVertexOptions<-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data> is Data:
  GoogleVertexOptions{google: Google.GoogleOptions<Signal, Telemetry, Fetch, Error>, project: Maybe<&2, String>, location: Maybe<&2, String>}

def Options(-Reason: Data, -Telemetry: Data, -E: Data) -> Data: GoogleVertexOptions<Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>

def vertexOptions(-S: Data, -Tel: Data, -Fe: Data, -E: Data, result: Result<&2, &2, String, Google.GoogleOptions<S, Tel, Fe, E>>) -> Result<&2, &2, String, GoogleVertexOptions<S, Tel, Fe, E>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{google}: Done{GoogleVertexOptions{google, None{}, None{}}}

# upstream streamSimple's options: no API key is required (ADC applies), and
# Gemini 2.5 Flash-Lite takes the 2.5 Flash budgets. An unsupported level
# mapping is the error thrown before a stream exists.
def streamSimpleOptions(~G: Data, ~D: Data, ~S: Data, ~Tel: Data, ~Fe: Data, ~E: Data, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Maybe<&2, T.SimpleStreamOptions<J(), S, Tel, Fe, E>>) -> Result<&2, &2, String, GoogleVertexOptions<S, Tel, Fe, E>>:
  vertexOptions(S, Tel, Fe, E, Google.simpleWith(S, Tel, Fe, E, model, Simple.buildBaseOptions(~G, ~D, ~J(), ~S, ~Tel, ~Fe, ~E, model, context, options, None{}), options, False{}))

# Client configuration
# --------------------

def placeholderBody(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{'>', SNil{}}: True{}
    case SCon{'>', _}: False{}
    case SCon{_, rest}: placeholderBody(rest)

# /^<[^>]+>$/
def isPlaceholderApiKey(apiKey: String) -> Bool:
  match apiKey:
    case SCon{'<', SCon{c, rest}}: Bool.not(Char.is_eq(c, '>')) && placeholderBody(rest)
    case _: False{}

def usableKey(+key: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, String.is_empty(key) || String.eq(key, GCP_VERTEX_CREDENTIALS_MARKER()) || isPlaceholderApiKey(key), None{}, Some{key})

# upstream resolveApiKey: the trimmed key unless empty, the ADC marker or a
# `<placeholder>`.
def resolveApiKey(apiKey: Maybe<&2, String>) -> Maybe<&2, String>:
  match apiKey:
    case Some{key}: usableKey(String.trim(key))
    case None{}: None{}

def usableBase(+trimmed: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, String.is_empty(trimmed) || String.contains(trimmed, "{location}"), None{}, Some{trimmed})

# upstream resolveCustomBaseUrl: generated `{location}` templates are not
# forwarded.
def resolveCustomBaseUrl(baseUrl: String) -> Maybe<&2, String>: usableBase(String.trim(baseUrl))

def betaDigits(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{c, rest}: Char.is_digit(c) && betaDigits(rest)

def betaSuffix(text: String) -> Bool:
  match text:
    case SCon{'b', SCon{'e', SCon{'t', SCon{'a', rest}}}}: betaDigits(rest)
    case _: False{}

def digitsThen(text: String, seen: Bool) -> Bool:
  match text:
    case SNil{}: seen
    case SCon{+c, +rest}: Bool.pick(Unit -> Bool, Char.is_digit(c), _ => digitsThen(rest, True{}), _ => seen && betaSuffix(SCon{c, rest}))(Unit{})

# /^v\d+(?:beta\d*)?$/
def versionPart(part: String) -> Bool:
  match part:
    case SCon{'v', rest}: digitsThen(rest, False{})
    case _: False{}

def anyVersion(parts: List<&2, String>) -> Bool:
  match parts:
    case Nil{}: False{}
    case part <> rest: versionPart(part) || anyVersion(rest)

def untilQuery(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'?', _}: SNil{}
    case SCon{'#', _}: SNil{}
    case SCon{c, rest}: SCon{c, untilQuery(rest)}

def afterSlash(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'/', rest}: SCon{'/', rest}
    case SCon{_, rest}: afterSlash(rest)

def pathOf(text: String, rest: Maybe<&2, String>) -> String:
  match rest:
    case Some{authority}: untilQuery(afterSlash(authority))
    case None{}: untilQuery(text)

def schemeRest(text: String, index: Nat) -> Maybe<&2, String>:
  match text:
    case SNil{}: None{}
    case SCon{':', SCon{'/', SCon{'/', rest}}}: Some{rest}
    case SCon{_, rest}: schemeRest(rest, index)

# upstream baseUrlIncludesApiVersion: a path segment of the URL is a version.
def baseUrlIncludesApiVersion(+baseUrl: String) -> Bool:
  anyVersion(String.split(pathOf(baseUrl, schemeRest(baseUrl, 0n)), '/'))

# The client parts of upstream's buildHttpOptions.
type HttpOptions is Data:
  HttpOptions{baseUrl: Maybe<&2, String>, collection: Bool, apiVersion: Maybe<&2, String>, headers: Maybe<&2, R.Record<String>>}

# The GoogleGenAI constructor options upstream builds: an API key client or
# an ADC client with project, location and the key file.
type ClientConfig is Data:
  ApiKeyClient{apiKey: String, apiVersion: String, httpOptions: Maybe<&2, HttpOptions>}
  AdcClient{project: String, location: String, keyFilename: Maybe<&2, String>, apiVersion: String, httpOptions: Maybe<&2, HttpOptions>}

def modelHeaders(model: T.Model<J()>) -> Maybe<&2, R.Record<String>>:
  match model:
    case T.Model{_, _, _, _, _, _, _, _, _, _, _, _, _, _, headers, _}: headers

def modelBaseUrl(model: T.Model<J()>) -> String:
  match model:
    case T.Model{_, _, _, _, base, _, _, _, _, _, _, _, _, _, _, _}: base

def headerRecord(agent: String, model: T.Model<J()>, custom: Maybe<&2, T.ProviderHeaders()>) -> Maybe<&2, R.Record<String>>:
  HeaderUtils.providerHeadersToRecord(Some{HeaderUtils.overlay(HeaderUtils.overlayStrings(HeaderUtils.fromRecord(R.Record{[R.Property{"User-Agent", agent}]}), modelHeaders(model)), custom)})

def httpWith(base: Maybe<&2, String>, headers: Maybe<&2, R.Record<String>>) -> Maybe<&2, HttpOptions>:
  match base headers:
    case None{} None{}: None{}
    case None{} Some{fields}: Some{HttpOptions{None{}, False{}, None{}, Some{fields}}}
    case Some{+url} _: Some{HttpOptions{Some{url}, True{}, Bool.pick(Maybe<&2, String>, baseUrlIncludesApiVersion(url), Some{""}, None{}), headers}}

# upstream buildHttpOptions: the custom base URL at collection scope (and no
# appended version when it names one), and the headers.
def buildHttpOptions(agent: String, +model: T.Model<J()>, custom: Maybe<&2, T.ProviderHeaders()>) -> Maybe<&2, HttpOptions>:
  httpWith(resolveCustomBaseUrl(modelBaseUrl(model)), headerRecord(agent, model, custom))

def PROJECT_MISSING() -> String: "Vertex AI requires a project ID. Set GOOGLE_CLOUD_PROJECT/GCLOUD_PROJECT or pass project in options."

def LOCATION_MISSING() -> String: "Vertex AI requires a location. Set GOOGLE_CLOUD_LOCATION or pass location in options."

def firstNonempty(first: Maybe<&2, String>, second: Maybe<&2, String>) -> Maybe<&2, String>:
  match first:
    case Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: second

def adcConfig(project: Maybe<&2, String>, location: Maybe<&2, String>, keyFilename: Maybe<&2, String>, http: Maybe<&2, HttpOptions>) -> Result<&2, &2, String, ClientConfig>:
  match project location:
    case None{} _: Fail{PROJECT_MISSING()}
    case _ None{}: Fail{LOCATION_MISSING()}
    case Some{p} Some{l}: Done{AdcClient{p, l, keyFilename, API_VERSION(), http}}

def keyFile(config: ClientConfig) -> Maybe<&2, String>:
  match config:
    case AdcClient{_, _, file, _, _}: file
    case _: None{}

def keyedConfig(agent: String, +model: T.Model<J()>, key: Maybe<&2, String>, project: Maybe<&2, String>, location: Maybe<&2, String>, headers: Maybe<&2, T.ProviderHeaders()>, +env: Maybe<&2, T.ProviderEnv()>) -> IO(Result<&2, &2, String, ClientConfig>):
  match key:
    case Some{value}: IO.pure(Result<&2, &2, String, ClientConfig>, Done{ApiKeyClient{value, API_VERSION(), buildHttpOptions(agent, model, headers)}})
    case None{}:
      do IO<Result<&2, &2, String, ClientConfig>>:
        cloudProject : Maybe<&2, String> <- Env.getProviderEnvValue("GOOGLE_CLOUD_PROJECT", env)
        gcloudProject : Maybe<&2, String> <- Env.getProviderEnvValue("GCLOUD_PROJECT", env)
        cloudLocation : Maybe<&2, String> <- Env.getProviderEnvValue("GOOGLE_CLOUD_LOCATION", env)
        keyFile : Maybe<&2, String> <- Env.getProviderEnvValue("GOOGLE_APPLICATION_CREDENTIALS", env)
        return adcConfig(firstNonempty(project, firstNonempty(cloudProject, gcloudProject)), firstNonempty(location, cloudLocation), keyFile, buildHttpOptions(agent, model, headers))

# upstream's client choice: a Vertex API key, else ADC with the resolved
# project (option, GOOGLE_CLOUD_PROJECT, GCLOUD_PROJECT), location (option,
# GOOGLE_CLOUD_LOCATION) and GOOGLE_APPLICATION_CREDENTIALS key file.
def clientConfig(agent: String, +model: T.Model<J()>, apiKey: Maybe<&2, String>, project: Maybe<&2, String>, location: Maybe<&2, String>, headers: Maybe<&2, T.ProviderHeaders()>, env: Maybe<&2, T.ProviderEnv()>) -> IO(Result<&2, &2, String, ClientConfig>):
  keyedConfig(agent, model, resolveApiKey(apiKey), project, location, headers, env)

# SDK request
# -----------

def httpBase(http: Maybe<&2, HttpOptions>) -> Maybe<&2, String>:
  match http:
    case Some{HttpOptions{base, _, _, _}}: base
    case None{}: None{}

def httpVersion(http: Maybe<&2, HttpOptions>) -> Maybe<&2, String>:
  match http:
    case Some{HttpOptions{_, _, version, _}}: version
    case None{}: None{}

def httpCollection(http: Maybe<&2, HttpOptions>) -> Bool:
  match http:
    case Some{HttpOptions{Some{_}, True{}, _, _}}: True{}
    case _: False{}

def httpHeaders(http: Maybe<&2, HttpOptions>) -> R.Record<String>:
  match http:
    case Some{HttpOptions{_, _, _, Some{fields}}}: fields
    case _: R.new(String)

# ApiClient's default base URL for a Vertex client.
def locationBase(+location: String) -> String:
  Bool.pick(String, String.eq(location, "global"), "https://aiplatform.googleapis.com/", Bool.pick(String, String.eq(location, "us") || String.eq(location, "eu"), "https://aiplatform." ++ location ++ ".rep.googleapis.com/", "https://" ++ location ++ "-aiplatform.googleapis.com/"))

def defaultBase(config: ClientConfig) -> String:
  match config:
    case ApiKeyClient{_, _, _}: "https://aiplatform.googleapis.com/"
    case AdcClient{_, location, _, _, _}: locationBase(location)

def configHttp(config: ClientConfig) -> Maybe<&2, HttpOptions>:
  match config:
    case ApiKeyClient{_, _, http}: http
    case AdcClient{_, _, _, _, http}: http

def configVersion(config: ClientConfig) -> String:
  match config:
    case ApiKeyClient{_, version, _}: version
    case AdcClient{_, _, _, version, _}: version

# The project/location prefix, unless the base URL is collection-scoped.
def resourcePrefix(config: ClientConfig) -> Maybe<&2, String>:
  match config:
    case AdcClient{project, location, _, _, http}: Bool.pick(Maybe<&2, String>, httpCollection(http), None{}, Some{"projects/" ++ project ++ "/locations/" ++ location})
    case _: None{}

def withoutTrailingSlash(+base: String) -> String: GoogleClient.trimmedBase(base)

def joined(parts: List<&2, Maybe<&2, String>>) -> List<&2, String>:
  match parts:
    case Nil{}: Nil{}
    case Some{SCon{c, cs}} <> rest: SCon{c, cs} <> joined(rest)
    case _ <> rest: joined(rest)

def splitModel(parts: List<&2, String>, model: String) -> String:
  match parts:
    case owner <> name <> _: "publishers/" ++ owner ++ "/models/" ++ name
    case _: "publishers/google/models/" ++ model

def vertexModel(+model: String) -> String:
  Bool.pick(String, String.starts_with(model, "publishers/") || String.starts_with(model, "projects/") || String.starts_with(model, "models/"), model, Bool.pick(String, String.contains(model, "/"), splitModel(String.split(model, '/'), model), "publishers/google/models/" ++ model))

# tModel in Vertex mode.
def modelPath(+model: String) -> Result<&2, &2, String, String>:
  Bool.pick(Result<&2, &2, String, String>, String.contains(model, "..") || String.contains(model, "?") || String.contains(model, "&"), Fail{"invalid model parameter"}, Done{vertexModel(model)})

def modelOf(value: Maybe<&2, String>) -> Result<&2, &2, String, String>:
  match value:
    case Some{SCon{c, cs}}: modelPath(SCon{c, cs})
    case _: Fail{"model is required and must be a string"}

# ApiClient.constructUrl for `{model}:streamGenerateContent?alt=sse`.
def requestAddress(+config: ClientConfig, path: String) -> String:
  +http = configHttp(config)
  String.join(joined([Some{withoutTrailingSlash(Maybe.default(&2, String, httpBase(http), defaultBase(config)))}, Some{Maybe.default(&2, String, httpVersion(http), configVersion(config))}, resourcePrefix(config), Some{path ++ ":streamGenerateContent?alt=sse"}]), "/")

# generateContentParametersToVertex
def pick(+fields: Fields(), names: List<&2, String>) -> List<&2, R.Property<J()>>: Google.picked(fields, names)

def vertexPart(value: J()) -> J():
  match value:
    case T.JsonObject{+fields}: obj(pick(fields, ["mediaResolution", "audioTranscription", "codeExecutionResult", "executableCode", "fileData", "functionCall", "functionResponse", "inlineData", "text", "thought", "thoughtSignature", "videoMetadata", "mediaProcessing"]))
    case other: other

def vertexParts(values: List<&2, J()>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: vertexPart(value) <> vertexParts(rest)

def partsOf(value: Maybe<&2, J()>) -> Maybe<&2, J()>:
  match value:
    case Some{T.JsonArray{values}}: Some{T.JsonArray{vertexParts(values)}}
    case other: other

def vertexContent(value: J()) -> J():
  match value:
    case T.JsonObject{+fields}: obj(Google.optionalField("parts", partsOf(Google.get(fields, "parts")), Google.optionalField("role", Google.get(fields, "role"), Nil{})))
    case other: other

def vertexContents(values: List<&2, J()>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: vertexContent(value) <> vertexContents(rest)

def contentsOf(value: Maybe<&2, J()>) -> Maybe<&2, J()>:
  match value:
    case Some{T.JsonArray{values}}: Some{T.JsonArray{vertexContents(values)}}
    case other: other

# tContent: a string system instruction is one user text part.
def instructionContent(value: J()) -> J():
  match value:
    case T.JsonString{text}: obj([field("parts", T.JsonArray{[obj([field("text", str(text))])]}), field("role", str("user"))])
    case other: vertexContent(other)

def vertexTool(value: J()) -> J():
  match value:
    case T.JsonObject{+fields}: obj(pick(fields, ["retrieval", "googleMaps", "mcpServers", "codeExecution", "computerUse", "enterpriseWebSearch", "exaAiSearch", "functionDeclarations", "googleSearch", "googleSearchRetrieval", "parallelAiSearch", "urlContext"]))
    case other: other

def vertexTools(values: List<&2, J()>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: vertexTool(value) <> vertexTools(rest)

def toolsOf(value: Maybe<&2, J()>) -> Maybe<&2, J()>:
  match value:
    case Some{T.JsonArray{values}}: Some{T.JsonArray{vertexTools(values)}}
    case other: other

def toolConfigOf(value: J()) -> J():
  match value:
    case T.JsonObject{+fields}: obj(pick(fields, ["functionCallingConfig", "retrievalConfig"]))
    case other: other

def requestFields(+config: Fields()) -> List<&2, R.Property<J()>>:
  List.concat(&2, R.Property<J()>, [pick(config, ["serviceTier"]), Google.optionalField("systemInstruction", Maybe.map(&2, J(), J(), instructionContent, Google.get(config, "systemInstruction")), Nil{}), pick(config, ["safetySettings"]), Google.optionalField("tools", toolsOf(Google.get(config, "tools")), Nil{}), Google.optionalField("toolConfig", Maybe.map(&2, J(), J(), toolConfigOf, Google.get(config, "toolConfig")), Nil{}), pick(config, ["labels", "cachedContent", "modelArmorConfig"])])

def generationFields() -> List<&2, String>:
  ["temperature", "topP", "topK", "candidateCount", "maxOutputTokens", "stopSequences", "responseLogprobs", "logprobs", "presencePenalty", "frequencyPenalty", "seed", "responseMimeType", "responseSchema", "responseJsonSchema", "routingConfig", "modelConfig", "responseModalities", "mediaResolution", "speechConfig", "audioTimestamp", "thinkingConfig", "audioTranscriptionConfig", "imageConfig"]

# modelSelectionConfig is sent as modelConfig.
def generationConfig(+config: Fields()) -> J():
  obj(List.concat(&2, R.Property<J()>, [pick(config, ["temperature", "topP", "topK", "candidateCount", "maxOutputTokens", "stopSequences", "responseLogprobs", "logprobs", "presencePenalty", "frequencyPenalty", "seed", "responseMimeType", "responseSchema", "responseJsonSchema", "routingConfig"]), Google.optionalField("modelConfig", Google.get(config, "modelSelectionConfig"), Nil{}), pick(config, ["responseModalities", "mediaResolution", "speechConfig", "audioTimestamp", "thinkingConfig", "audioTranscriptionConfig", "imageConfig"])]))

def withConfig(contents: List<&2, R.Property<J()>>, config: Maybe<&2, J()>) -> J():
  match config:
    case None{}: obj(contents)
    case Some{+selected}: obj(List.concat(&2, R.Property<J()>, [contents, requestFields(Google.fieldsOf(selected)), [field("generationConfig", generationConfig(Google.fieldsOf(selected)))]]))

# The request body: contents, the config's request-level fields, then
# generationConfig.
def requestBody(params: J()) -> J():
  match params:
    case T.JsonObject{+fields}: withConfig(Google.optionalField("contents", contentsOf(Google.get(fields, "contents")), Nil{}), Google.get(fields, "config"))
    case other: other

def presentHeaders(fields: List<&2, R.Property<String>>) -> T.ProviderHeaders(): HeaderUtils.fromRecord(R.Record{fields})

def assembled(result: Result<&2, &2, H.HeaderSyntaxError, SDK.HeaderState>) -> Result<&2, &2, String, H.Headers>:
  match result:
    case Fail{_}: Fail{"Invalid header value"}
    case Done{state}: Done{SDK.wireHeaders(state)}

# httpOptions.headers, the SDK's identity and JSON content type, then the
# auth headers.
def requestHeaders(client: R.Record<String>, auth: List<&2, R.Property<String>>) -> Result<&2, &2, String, H.Headers>:
  assembled(SDK.build([Some{HeaderUtils.fromRecord(client)}, Some{presentHeaders([R.Property{"x-goog-api-client", GoogleClient.sdkLabel()}, R.Property{"Content-Type", "application/json"}])}, Some{presentHeaders(auth)}]))

def buildRequest(url: Result<&2, &2, URL.Error, URL.URL>, headers: Result<&2, &2, String, H.Headers>, body: Maybe<&2, String>) -> Result<&2, &2, String, SDK.Request>:
  match url headers body:
    case Fail{_} _ _: Fail{"Invalid URL"}
    case _ Fail{message} _: Fail{message}
    case _ _ None{}: Fail{"Could not encode request payload as JSON"}
    case Done{location} Done{fields} Some{text}: Done{SDK.Request{location, "post", fields, text, GoogleClient.unbounded()}}

def prepared(context: URL.Context, +config: ClientConfig, auth: List<&2, R.Property<String>>, +params: J(), path: Result<&2, &2, String, String>) -> Result<&2, &2, String, SDK.Request>:
  match path:
    case Fail{message}: Fail{message}
    case Done{name}: buildRequest(URL.parse(context, requestAddress(config, name)), requestHeaders(httpHeaders(configHttp(config)), auth), JsonWire.stringify(requestBody(params)))

def prepareRequest(context: URL.Context, config: ClientConfig, auth: List<&2, R.Property<String>>, +params: J()) -> Result<&2, &2, String, SDK.Request>:
  prepared(context, config, auth, params, modelOf(Google.payloadModel(params)))

# Entry
# -----

# The URL tables, pi's User-Agent, the process fetch the SDK uses, and the
# OAuth2 token endpoint for ADC.
type Setup<-Reason: Data> is Data:
  Setup{url: URL.Context, agent: String, fetch: Fetch.Fetch(Reason), tokenUrl: String}

def sendWith(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +state: Fold.State<G>, config: ClientConfig, retries: Maybe<&2, F64>, delay: Maybe<&2, F64>, +params: J(), auth: Result<&2, &2, String, List<&2, R.Property<String>>>) -> IO(Unit):
  match setup auth:
    case _ Fail{message}: GoogleClient.fail(~Reason, ~G, events, state, parent, message)
    case Setup{url, _, fetch, _} Done{headers}: GoogleClient.sendRequest(~Reason, ~G, events, parent, state, fetch, prepareRequest(url, config, headers, params), Retry.resolve(Reason, retries, delay, Some{parent}))

def apiKeyHeaders(config: ClientConfig) -> Maybe<&2, List<&2, R.Property<String>>>:
  match config:
    case ApiKeyClient{key, _, _}: Some{[R.Property{"x-goog-api-key", key}]}
    case _: None{}

def adcHeaders(~Reason: Data, fetch: Fetch.Fetch(Reason), url: URL.Context, +parent: Signal(Reason), tokenUrl: String, file: Maybe<&2, String>) -> IO(Result<&2, &2, String, List<&2, R.Property<String>>>):
  Credentials.requestHeaders(~Reason, fetch, url, parent, tokenUrl, file)

def authorizedWith(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +state: Fold.State<G>, +config: ClientConfig, retries: Maybe<&2, F64>, delay: Maybe<&2, F64>, +params: J(), keyHeaders: Maybe<&2, List<&2, R.Property<String>>>) -> IO(Unit):
  match keyHeaders setup:
    case Some{headers} _: sendWith(~Reason, ~G, events, parent, setup, state, config, retries, delay, params, Done{headers})
    case None{} Setup{url, agent, fetch, tokenUrl}:
      do IO<Unit>:
        headers : Result<&2, &2, String, List<&2, R.Property<String>>> <- adcHeaders(~Reason, fetch, url, parent, tokenUrl, keyFile(config))
        sendWith(~Reason, ~G, events, parent, Setup{url, agent, fetch, tokenUrl}, state, config, retries, delay, params, headers)

# The API key header, or the ADC headers (one token request per client, as
# a new GoogleAuth client is created for each stream).
def authorized(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +state: Fold.State<G>, +config: ClientConfig, retries: Maybe<&2, F64>, delay: Maybe<&2, F64>, +params: J()) -> IO(Unit):
  authorizedWith(~Reason, ~G, events, parent, setup, state, config, retries, delay, params, apiKeyHeaders(config))

def payloaded(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +state: Fold.State<G>, +config: ClientConfig, retries: Maybe<&2, F64>, delay: Maybe<&2, F64>, original: J(), result: Result<&2, &2, E, Maybe<&2, J()>>) -> IO(Unit):
  match result:
    case Fail{cause}: GoogleClient.fail(~Reason, ~G, events, state, parent, render(cause))
    case Done{replacement}: authorized(~Reason, ~G, events, parent, setup, state, config, retries, delay, Maybe.default(&2, J(), replacement, original))

def withPayload(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +state: Fold.State<G>, +model: T.Model<J()>, +config: ClientConfig, retries: Maybe<&2, F64>, delay: Maybe<&2, F64>, +params: J(), hook: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>) -> IO(Unit):
  match hook:
    case None{}: authorized(~Reason, ~G, events, parent, setup, state, config, retries, delay, params)
    case Some{callback}:
      do IO<Unit>:
        result : Result<&2, &2, E, Maybe<&2, J()>> <- C.call(T.PayloadInput<J(), T.Model<J()>>, Result<&2, &2, E, Maybe<&2, J()>>, callback, T.PayloadInput{params, model})
        payloaded(~Reason, ~E, ~G, ~render, events, parent, setup, state, config, retries, delay, params, result)

# buildParams rejects an already aborted signal.
def built(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +state: Fold.State<G>, +model: T.Model<J()>, +config: ClientConfig, retries: Maybe<&2, F64>, delay: Maybe<&2, F64>, hook: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>, params: Result<&2, &2, String, J()>, aborted: Bool) -> IO(Unit):
  match params aborted:
    case Fail{message} _: GoogleClient.fail(~Reason, ~G, events, state, parent, message)
    case Done{_} True{}: GoogleClient.fail(~Reason, ~G, events, state, parent, "Request aborted")
    case Done{+payload} False{}: withPayload(~Reason, ~E, ~G, ~render, events, parent, setup, state, model, config, retries, delay, payload, hook)

def googleOf(-Reason: Data, -Telemetry: Data, -E: Data, options: Options(Reason, Telemetry, E)) -> Google.GoogleOptions<Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>:
  match options:
    case GoogleVertexOptions{google, _, _}: google

def baseOf(-Reason: Data, -Telemetry: Data, -E: Data, options: Options(Reason, Telemetry, E)) -> T.StreamOptions<J(), Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>:
  match options:
    case GoogleVertexOptions{Google.GoogleOptions{base, _, _}, _, _}: base

def configuredWith(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Options(Reason, Telemetry, E), +state: Fold.State<G>, config: Result<&2, &2, String, ClientConfig>, base: T.StreamOptions<J(), Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>) -> IO(Unit):
  match config base:
    case Fail{message} _: GoogleClient.fail(~Reason, ~G, events, state, parent, message)
    case Done{+client} T.StreamOptions{_, _, _, _, _, hook, _, _, _, retries, delay, _, _, _, _, _, _, _, _}:
      do IO<Unit>:
        params : Result<&2, &2, String, J()> <- Google.buildParams(~G, ~D, ~(Signal(Reason)), ~Telemetry, ~(Fetch.Fetch(Reason)), ~E, model, context, googleOf(Reason, Telemetry, E, options))
        aborted : Bool <- Abort.aborted(Reason, parent)
        built(~Reason, ~E, ~G, ~render, events, parent, setup, state, model, client, retries, delay, hook, params, aborted)

def configured(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Options(Reason, Telemetry, E), +state: Fold.State<G>, config: Result<&2, &2, String, ClientConfig>) -> IO(Unit):
  configuredWith(~Reason, ~Telemetry, ~E, ~G, ~D, ~render, events, parent, setup, model, context, options, state, config, baseOf(Reason, Telemetry, E, options))

def setupAgent(-Reason: Data, setup: Setup<Reason>) -> String:
  match setup:
    case Setup{_, agent, _, _}: agent

def fetchChecked(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Options(Reason, Telemetry, E), +state: Fold.State<G>) -> IO(Unit):
  match options:
    case GoogleVertexOptions{Google.GoogleOptions{T.StreamOptions{_, _, _, Some{_}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}, _, _}, _, _}: GoogleClient.fail(~Reason, ~G, events, state, parent, "Custom fetch is not supported by the Google Vertex adapter")
    case GoogleVertexOptions{Google.GoogleOptions{T.StreamOptions{signal, telemetry, key, None{}, env, onPayload, onResponse, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, session, ws, metadata}, choice, thinking}, project, location}:
      do IO<Unit>:
        config : Result<&2, &2, String, ClientConfig> <- clientConfig(setupAgent(Reason, setup), model, key, project, location, headers, env)
        configured(~Reason, ~Telemetry, ~E, ~G, ~D, ~render, events, parent, setup, model, context, GoogleVertexOptions{Google.GoogleOptions{T.StreamOptions{signal, telemetry, key, None{}, env, onPayload, onResponse, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, session, ws, metadata}, choice, thinking}, project, location}, state, config)

# upstream `stream`: the producer's work up to `stream.end()` over the
# collapsed transcript. `parent` is the request's abort signal.
def stream(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Options(Reason, Telemetry, E), timestamp: F64) -> IO(Unit):
  fetchChecked(~Reason, ~Telemetry, ~E, ~G, ~D, ~render, events, parent, setup, model, Transcript.collapseSystemMessages(V.Value, V.Value, G, D, context), options, Fold.createFor(G, "google-vertex", model, timestamp))

def simpleSelected(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, timestamp: F64, selected: Result<&2, &2, String, Options(Reason, Telemetry, E)>) -> IO(Result<&2, &2, String, Unit>):
  match selected:
    case Fail{message}: IO.pure(Result<&2, &2, String, Unit>, Fail{message})
    case Done{options}:
      do IO<Result<&2, &2, String, Unit>>:
        stream(~Reason, ~Telemetry, ~E, ~G, ~D, ~render, events, parent, setup, model, context, options, timestamp)
        return Done{Unit{}}

# upstream streamSimple: a Fail is the error thrown before a stream exists.
def streamSimple(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Signal(Reason), +setup: Setup<Reason>, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Maybe<&2, T.SimpleStreamOptions<J(), Signal(Reason), Telemetry, Fetch.Fetch(Reason), E>>, timestamp: F64) -> IO(Result<&2, &2, String, Unit>):
  simpleSelected(~Reason, ~Telemetry, ~E, ~G, ~D, ~render, events, parent, setup, model, context, timestamp, streamSimpleOptions(~G, ~D, ~(Signal(Reason)), ~Telemetry, ~(Fetch.Fetch(Reason)), ~E, model, context, options))
