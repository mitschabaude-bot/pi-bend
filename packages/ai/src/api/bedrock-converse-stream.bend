import Base
import ../types.bend as T
import ../utils/cost.bend as Cost
import ../utils/diagnostics.bend as Diagnostics
import ../utils/event-stream.bend as Events
import ../utils/headers.bend as HeaderUtils
import ../utils/json.bend as JsonWire
import ../utils/json-parse.bend as JsonRepair
import ../utils/model-api.bend as ModelApi
import ../utils/provider-env.bend as Env
import ../utils/sanitize-unicode.bend as Unicode
import ../utils/schema-json.bend as SchemaJson
import ../utils/text.bend as Text
import ../utils/thinking-levels.bend as Levels
import ../utils/transcript.bend as Transcript
import ./constrained-sampling.bend as Sampling
import ./provider-fetch.bend as Http
import ./bedrock-credentials.bend as Credentials
import ./credential-http.bend as CredentialHttp
import ./simple-options.bend as Simple
import ./transform-messages.bend as Transform
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/aws-eventstream.bend as EventStream
import ../../../runtime/src/aws-sigv4.bend as SigV4
import ../../../runtime/src/base64.bend as Base64
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-message.bend as Headers
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/text.bend as Space
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/utf16.bend as Utf16
import ../../../runtime/src/utf8.bend as Utf8

# The Amazon Bedrock ConverseStream provider (upstream
# api/bedrock-converse-stream.ts). Upstream drives the AWS SDK; here the
# parts of the SDK it relies on are explicit: the client configuration pi
# builds (profile, region, endpoint, credentials, bearer token), the
# restJson request with SigV4 or bearer auth, the event-stream response and
# the SDK's error shapes. Credentials come from bedrock-credentials.bend.

def J() -> Data: T.JsonValue

def str(value: String) -> J(): T.JsonString{value}

def num(value: F64) -> J(): T.JsonNumber{value}

def obj(fields: List<&2, R.Property<J()>>) -> J(): T.JsonObject{R.Record{fields}}

def arr(values: List<&2, J()>) -> J(): T.JsonArray{values}

def field(name: String, value: J(), rest: List<&2, R.Property<J()>>) -> List<&2, R.Property<J()>>: R.Property{name, value} <> rest

def optional(name: String, value: Maybe<&2, J()>, rest: List<&2, R.Property<J()>>) -> List<&2, R.Property<J()>>:
  match value:
    case None{}: rest
    case Some{item}: R.Property{name, item} <> rest

def zero() -> F64: F.fromU32(0)

def EMPTY_TEXT_PLACEHOLDER() -> String: "<empty>"

def REDACTED_THINKING_PLACEHOLDER() -> String: "[Reasoning redacted]"

# Options
# -------

type BedrockThinkingDisplay is Data:
  DisplaySummarized{}
  DisplayOmitted{}

# upstream BedrockOptions["toolChoice"].
type BedrockToolChoice is Data:
  ChoiceAuto{}
  ChoiceAny{}
  ChoiceNone{}
  ChoiceTool{name: String}

# upstream BedrockOptions extends StreamOptions; the shared options are one
# field.
type BedrockOptions<-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data> is Data:
  BedrockOptions{base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, region: Maybe<&2, String>, profile: Maybe<&2, String>, toolChoice: Maybe<&2, BedrockToolChoice>, reasoning: Maybe<&2, T.ThinkingLevel>, thinkingBudgets: Maybe<&2, T.ThinkingBudgets>, interleavedThinking: Maybe<&2, Bool>, thinkingDisplay: Maybe<&2, BedrockThinkingDisplay>, requestMetadata: Maybe<&2, R.Record<String>>, bearerToken: Maybe<&2, String>}

def Options(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data) -> Data: BedrockOptions<Signal, Telemetry, Fetch, Error>

def withBase(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>) -> Options(Signal, Telemetry, Fetch, Error):
  BedrockOptions{base, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

# Model families
# --------------

def lowerId(model: T.Model<J()>) -> String: String.to_lower(T.modelId(model))

def modelName(model: T.Model<J()>) -> String:
  match model:
    case T.Model{_, name, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: name

def isSeparator(+c: Char) -> Bool:
  match c:
    case Chr{code}: Space.whitespace(code) || U32.is_eq(code, 95) || U32.is_eq(code, 46) || U32.is_eq(code, 58)

def dropSeparators(text: String) -> String:
  match text:
    case SCon{+c, +rest}: Bool.pick(String, isSeparator(c), dropSeparators(rest), SCon{c, rest})
    case other: other

# `.replace(/[\s_.:]+/g, "-")`.
@unsafe def dashed(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{+c, +rest}: Bool.pick(Unit -> String, isSeparator(c), _ => SCon{'-', dashed(dropSeparators(rest))}, _ => SCon{c, dashed(rest)})(Unit{})

# upstream getModelMatchCandidates.
def candidates(+model: T.Model<J()>) -> List<&2, String>:
  +id = lowerId(model)
  +name = String.to_lower(modelName(model))
  Bool.pick(List<&2, String>, String.is_empty(modelName(model)), [id, dashed(id)], [id, dashed(id), name, dashed(name)])

def containsAny(+value: String, needles: List<&2, String>) -> Bool:
  match needles:
    case Nil{}: False{}
    case needle <> rest: String.contains(value, needle) || containsAny(value, rest)

def anyContains(values: List<&2, String>, +needles: List<&2, String>) -> Bool:
  match values:
    case Nil{}: False{}
    case +value <> rest: containsAny(value, needles) || anyContains(rest, needles)

def supportsAdaptiveThinking(+model: T.Model<J()>) -> Bool:
  anyContains(candidates(model), ["opus-4-6", "opus-4-7", "opus-4-8", "opus-5", "sonnet-4-6", "sonnet-5", "fable-5"])

def supportsNativeXhighEffort(+model: T.Model<J()>) -> Bool:
  anyContains(candidates(model), ["opus-4-7", "opus-4-8", "opus-5", "sonnet-5", "fable-5"])

# upstream isAnthropicClaudeModel.
def isAnthropicClaudeModel(+model: T.Model<J()>) -> Bool:
  +id = lowerId(model)
  +name = String.to_lower(modelName(model))
  String.contains(id, "anthropic.claude") || String.contains(id, "anthropic/claude") || String.contains(name, "anthropic.claude") || String.contains(name, "anthropic/claude") || String.contains(name, "claude")

def supportsThinkingSignature(+model: T.Model<J()>) -> Bool: isAnthropicClaudeModel(model)

# upstream supportsPromptCaching; `forced` is AWS_BEDROCK_FORCE_CACHE=1.
def supportsPromptCaching(+model: T.Model<J()>, forced: Bool) -> Bool:
  +names = candidates(model)
  Bool.pick(Bool, anyContains(names, ["claude"]), anyContains(names, ["fable-5", "opus-5", "sonnet-5", "-4-", "claude-3-7-sonnet", "claude-3-5-haiku"]), forced)

def mappedEffort(value: Maybe<&2, T.Nullable<String>>, level: T.ThinkingLevel) -> String:
  match value level:
    case Some{T.PresentValue{mapped}} _: mapped
    case _ T.Minimal{}: "low"
    case _ T.Low{}: "low"
    case _ T.Medium{}: "medium"
    case _ _: "high"

def thinkingMap(model: T.Model<J()>) -> Maybe<&2, T.ThinkingLevelMap>:
  match model:
    case T.Model{_, _, _, _, _, _, mapping, _, _, _, _, _, _, _, _, _}: mapping

# upstream mapThinkingLevelToEffort.
def mapThinkingLevelToEffort(+model: T.Model<J()>, +level: T.ThinkingLevel) -> String:
  match level:
    case T.XHigh{}: Bool.pick(String, supportsNativeXhighEffort(model), "xhigh", mappedEffort(Levels.mapped(thinkingMap(model), T.Thinking{T.XHigh{}}), T.XHigh{}))
    case other: mappedEffort(Levels.mapped(thinkingMap(model), T.Thinking{other}), other)

# Client configuration
# --------------------

# upstream's BedrockRuntimeClientConfig as stream builds it: the profile, the
# region and explicit endpoint, static credentials, the bearer token (with
# authSchemePreference ["httpBearerAuth"]).
type ClientConfig is Data:
  ClientConfig{profile: Maybe<&2, String>, region: Maybe<&2, String>, endpoint: Maybe<&2, String>, credentials: Maybe<&2, SigV4.Credentials>, token: Maybe<&2, String>}

def lowerAlnumDash(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}: ((U32.is_ge(code, 97) && U32.is_le(code, 122)) || (U32.is_ge(code, 48) && U32.is_le(code, 57)) || U32.is_eq(code, 45)) && lowerAlnumDash(rest)

def partition(+text: String) -> Bool:
  String.eq(text, "aws") || (String.starts_with(text, "aws-") && String.length(text) > 4n && lowerAlnumDash(String.drop(text, 4n)))

def arnRegionOf(parts: List<&2, String>) -> Maybe<&2, String>:
  match parts:
    case "arn" <> +kind <> "bedrock" <> +region <> _ <> _: Bool.pick(Maybe<&2, String>, partition(kind) && Bool.not(String.is_empty(region)) && lowerAlnumDash(region), Some{region}, None{})
    case _: None{}

# `/^arn:aws(?:-[a-z0-9-]+)?:bedrock:([a-z0-9-]+):/` on the model id.
def arnRegion(model: T.Model<J()>) -> Maybe<&2, String>: arnRegionOf(String.split(T.modelId(model), ':'))

def endpointRegionOf(+host: String) -> Maybe<&2, String>:
  +stem = Bool.pick(String, String.ends_with(host, ".amazonaws.com.cn"), String.take(host, String.length(host) - 17n), Bool.pick(String, String.ends_with(host, ".amazonaws.com"), String.take(host, String.length(host) - 14n), ""))
  +region = Bool.pick(String, String.starts_with(stem, "bedrock-runtime-fips."), String.drop(stem, 21n), Bool.pick(String, String.starts_with(stem, "bedrock-runtime."), String.drop(stem, 16n), ""))
  Bool.pick(Maybe<&2, String>, Bool.not(String.is_empty(region)) && lowerAlnumDash(region), Some{region}, None{})

def hostRegion(url: Result<&2, &2, URL.Error, URL.URL>) -> Maybe<&2, String>:
  match url:
    case Done{URL.URL{_, _, _, Some{host}, _, _, _, _}}: endpointRegionOf(String.to_lower(URL.serializeHost(host)))
    case _: None{}

# upstream getStandardBedrockEndpointRegion.
def getStandardBedrockEndpointRegion(urlContext: URL.Context, baseUrl: String) -> Maybe<&2, String>:
  match baseUrl:
    case SNil{}: None{}
    case other: hostRegion(URL.parse(urlContext, other))

def nonempty(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: None{}

def firstOf(values: List<&2, Maybe<&2, String>>) -> Maybe<&2, String>:
  match values:
    case Nil{}: None{}
    case Some{SCon{c, cs}} <> _: Some{SCon{c, cs}}
    case _ <> rest: firstOf(rest)

# upstream getConfiguredBedrockCredentials.
def credentialsOf(access: Maybe<&2, String>, secret: Maybe<&2, String>, token: Maybe<&2, String>) -> Maybe<&2, SigV4.Credentials>:
  match access secret:
    case Some{SCon{a, as}} Some{SCon{b, bs}}: Some{SigV4.Credentials{SCon{a, as}, SCon{b, bs}, nonempty(token)}}
    case _ _: None{}

def envValue(+name: String, env: Maybe<&2, T.ProviderEnv()>) -> IO(Maybe<&2, String>): Env.getProviderEnvValue(name, env)

def scopedValue(env: Maybe<&2, T.ProviderEnv()>, +name: String) -> Maybe<&2, String>:
  match env:
    case None{}: None{}
    case Some{record}: nonempty(R.get(String, record, name))

# The environment values the configuration reads, looked up once.
type ConfigEnv is Data:
  ConfigEnv{profile: Maybe<&2, String>, region: Maybe<&2, String>, defaultRegion: Maybe<&2, String>, ambientProfile: Maybe<&2, String>, skipAuth: Maybe<&2, String>, bearer: Maybe<&2, String>, accessKey: Maybe<&2, String>, secretKey: Maybe<&2, String>, sessionToken: Maybe<&2, String>}

def configEnv(+env: Maybe<&2, T.ProviderEnv()>) -> IO(ConfigEnv):
  do IO<ConfigEnv>:
    profile : Maybe<&2, String> <- envValue("AWS_PROFILE", env)
    region : Maybe<&2, String> <- envValue("AWS_REGION", env)
    defaultRegion : Maybe<&2, String> <- envValue("AWS_DEFAULT_REGION", env)
    ambientProfile : Maybe<&2, String> <- envValue("AWS_PROFILE", None{})
    skipAuth : Maybe<&2, String> <- envValue("AWS_BEDROCK_SKIP_AUTH", env)
    bearer : Maybe<&2, String> <- envValue("AWS_BEARER_TOKEN_BEDROCK", env)
    accessKey : Maybe<&2, String> <- envValue("AWS_ACCESS_KEY_ID", env)
    secretKey : Maybe<&2, String> <- envValue("AWS_SECRET_ACCESS_KEY", env)
    sessionToken : Maybe<&2, String> <- envValue("AWS_SESSION_TOKEN", env)
    return ConfigEnv{profile, region, defaultRegion, ambientProfile, skipAuth, bearer, accessKey, secretKey, sessionToken}

def skipAuthOf(value: Maybe<&2, String>) -> Bool:
  match value:
    case Some{"1"}: True{}
    case _: False{}

def dummyCredentials() -> SigV4.Credentials: SigV4.Credentials{"dummy-access-key", "dummy-secret-key", None{}}

def regionFor(arn: Maybe<&2, String>, configured: Maybe<&2, String>, endpointRegion: Maybe<&2, String>, +explicit: Bool, +ambient: Bool) -> Maybe<&2, String>:
  match arn configured endpointRegion:
    case Some{region} _ _: Some{region}
    case None{} Some{region} _: Some{region}
    case None{} None{} Some{region}: Bool.pick(Maybe<&2, String>, explicit, Some{region}, Bool.pick(Maybe<&2, String>, ambient, None{}, Some{"us-east-1"}))
    case None{} None{} None{}: Bool.pick(Maybe<&2, String>, ambient, None{}, Some{"us-east-1"})

def credentialsFor(+skipAuth: Bool, +explicitProfile: Bool, ambient: Maybe<&2, SigV4.Credentials>) -> Maybe<&2, SigV4.Credentials>:
  match skipAuth explicitProfile ambient:
    case True{} _ _: Some{dummyCredentials()}
    case False{} False{} Some{credentials}: Some{credentials}
    case _ _ _: None{}

def tokenFor(+skipAuth: Bool, bearer: Maybe<&2, String>) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, skipAuth, None{}, bearer)

def modelBaseUrl(model: T.Model<J()>) -> String:
  match model:
    case T.Model{_, _, _, _, base, _, _, _, _, _, _, _, _, _, _, _}: base

# upstream stream's client configuration for a Node runtime (without the
# proxy and HTTP handler, which the native transport has no counterpart for).
def clientConfigWith(+model: T.Model<J()>, urlContext: URL.Context, +optionsProfile: Maybe<&2, String>, optionsRegion: Maybe<&2, String>, optionsBearer: Maybe<&2, String>, apiKey: Maybe<&2, String>, values: ConfigEnv) -> ClientConfig:
  match values:
    case ConfigEnv{profile, region, defaultRegion, +ambientProfile, skipAuth, bearer, accessKey, secretKey, sessionToken}:
      +configured = firstOf([optionsRegion, region, defaultRegion])
      +ambient = Maybe.is_some(&2, String, ambientProfile)
      +endpointRegion = getStandardBedrockEndpointRegion(urlContext, modelBaseUrl(model))
      +explicit = Maybe.is_none(&2, String, endpointRegion) || (Maybe.is_none(&2, String, configured) && Bool.not(ambient))
      +skip = skipAuthOf(skipAuth)
      ClientConfig{firstOf([optionsProfile, profile]), regionFor(arnRegion(model), configured, endpointRegion, explicit, ambient), Bool.pick(Maybe<&2, String>, explicit, Some{modelBaseUrl(model)}, None{}), credentialsFor(skip, Maybe.is_some(&2, String, optionsProfile), credentialsOf(accessKey, secretKey, sessionToken)), tokenFor(skip, firstOf([optionsBearer, apiKey, bearer]))}

def clientConfig(+model: T.Model<J()>, urlContext: URL.Context, profile: Maybe<&2, String>, region: Maybe<&2, String>, bearerToken: Maybe<&2, String>, apiKey: Maybe<&2, String>, +env: Maybe<&2, T.ProviderEnv()>) -> IO(ClientConfig):
  do IO<ClientConfig>:
    values : ConfigEnv <- configEnv(env)
    return clientConfigWith(model, urlContext, firstOf([profile, scopedValue(env, "AWS_PROFILE")]), region, bearerToken, apiKey, values)

# Request
# -------

def cacheRetentionName(value: T.CacheRetention) -> Bool:
  match value:
    case T.CacheNone{}: False{}
    case _: True{}

def isLong(value: T.CacheRetention) -> Bool:
  match value:
    case T.CacheLong{}: True{}
    case _: False{}

def cachePoint(+retention: T.CacheRetention) -> J():
  obj(field("cachePoint", obj(field("type", str("default"), Bool.pick(List<&2, R.Property<J()>>, isLong(retention), field("ttl", str("1h"), Nil{}), Nil{}))), Nil{}))

# The cache point is added for Claude models that support prompt caching,
# unless retention is "none".
def caching(+model: T.Model<J()>, +retention: T.CacheRetention, forced: Bool) -> Bool:
  cacheRetentionName(retention) && supportsPromptCaching(model, forced)

# upstream buildSystemPrompt.
def buildSystemPrompt(prompt: Maybe<&2, String>, +model: T.Model<J()>, +retention: T.CacheRetention, forced: Bool) -> Maybe<&2, J()>:
  match prompt:
    case Some{SCon{c, cs}}: Some{arr(obj(field("text", str(Unicode.sanitizeSurrogates(SCon{c, cs})), Nil{})) <> Bool.pick(List<&2, J()>, caching(model, retention, forced), cachePoint(retention) <> Nil{}, Nil{}))}
    case _: None{}

def allowedIdChar(+code: U32) -> Bool:
  (U32.is_ge(code, 97) && U32.is_le(code, 122)) || (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 48) && U32.is_le(code, 57)) || U32.is_eq(code, 95) || U32.is_eq(code, 45)

def sanitizedId(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{Chr{+code}, rest}: SCon{Bool.pick(Char, allowedIdChar(code), Chr{code}, '_'), sanitizedId(rest)}

# upstream normalizeToolCallId: [^a-zA-Z0-9_-] becomes "_", at most 64 UTF-16
# units (sanitized ids are ASCII, so code points).
def normalizeToolCallId(id: String) -> String: String.take(sanitizedId(Utf16.codeUnits(id)), 64n)

def textBlock(text: String) -> J(): obj(field("text", str(text), Nil{}))

# upstream createNonBlankTextBlock.
def nonBlankText(text: String) -> Maybe<&2, J()>:
  +sanitized = Unicode.sanitizeSurrogates(text)
  Bool.pick(Maybe<&2, J()>, String.is_empty(Space.trim(sanitized)), None{}, Some{textBlock(sanitized)})

def requiredText(text: String) -> J(): Maybe.default(&2, J(), nonBlankText(text), textBlock(EMPTY_TEXT_PLACEHOLDER()))

def imageFormat(+mimeType: String) -> Maybe<&2, String>:
  match mimeType:
    case "image/jpeg": Some{"jpeg"}
    case "image/jpg": Some{"jpeg"}
    case "image/png": Some{"png"}
    case "image/gif": Some{"gif"}
    case "image/webp": Some{"webp"}
    case _: None{}

type RequestError is Data:
  UnknownImageType{mimeType: String}
  InvalidImageData{}
  SamplingFailure{cause: Sampling.Error}

def requestErrorMessage(error: RequestError) -> String:
  match error:
    case UnknownImageType{mimeType}: "Unknown image type: " ++ mimeType
    case InvalidImageData{}: "Invalid image data"
    case SamplingFailure{cause}: Sampling.errorMessage(cause)

def Built(-A: Data) -> Data: Result<&2, &2, RequestError, A>

def reencoded(result: Result<&2, &2, Base64.Error, String>) -> Built(String):
  match result:
    case Fail{_}: Fail{InvalidImageData{}}
    case Done{text}: Done{text}

def encodedBytes(result: Result<&2, &2, Base64.Error, List<&2, U32>>) -> Built(String):
  match result:
    case Fail{_}: Fail{InvalidImageData{}}
    case Done{bytes}: reencoded(Base64.encode(bytes))

def imageWithFormat(data: String, format: Maybe<&2, String>, mimeType: String) -> Built(J()):
  match format:
    case None{}: Fail{UnknownImageType{mimeType}}
    case Some{name}: Result.map(&2, &2, RequestError, String, J(), bytes => obj(field("source", obj(field("bytes", str(bytes), Nil{})), field("format", str(name), Nil{}))), encodedBytes(Base64.decode(data)))

# upstream createImageBlock: the image bytes (base64 on the wire, as the SDK
# serializes a blob) and the format.
def createImageBlock(+mimeType: String, data: String) -> Built(J()): imageWithFormat(data, imageFormat(mimeType), mimeType)

def imageMember(image: Built(J())) -> Built(J()):
  Result.map(&2, &2, RequestError, J(), J(), block => obj(field("image", block, Nil{})), image)

def consBuilt(head: Built(J()), rest: Built(List<&2, J()>)) -> Built(List<&2, J()>):
  do Result<&2, &2, RequestError, List<&2, J()>>:
    value : J() <- head
    others : List<&2, J()> <- rest
    return value <> others

def consMaybe(head: Maybe<&2, J()>, rest: Built(List<&2, J()>)) -> Built(List<&2, J()>):
  match head:
    case None{}: rest
    case Some{value}: Result.map(&2, &2, RequestError, List<&2, J()>, List<&2, J()>, others => value <> others, rest)

def placeholderIfEmpty(values: List<&2, J()>) -> List<&2, J()>:
  match values:
    case Nil{}: textBlock(EMPTY_TEXT_PLACEHOLDER()) <> Nil{}
    case other: other

def userBlocks(parts: List<&2, T.TextImageContent>) -> Built(List<&2, J()>):
  match parts:
    case Nil{}: Done{Nil{}}
    case T.TextImageText{T.TextContent{text, _}} <> rest: consMaybe(nonBlankText(text), userBlocks(rest))
    case T.TextImageImage{T.ImageContent{data, mimeType}} <> rest: consBuilt(imageMember(createImageBlock(mimeType, data)), userBlocks(rest))

def role(name: String, content: List<&2, J()>) -> J(): obj(field("role", str(name), field("content", arr(content), Nil{})))

def userMessage(content: T.UserContent) -> Built(J()):
  match content:
    case T.UserText{text}: Done{role("user", requiredText(text) <> Nil{})}
    case T.UserBlocks{parts}: Result.map(&2, &2, RequestError, List<&2, J()>, J(), blocks => role("user", placeholderIfEmpty(blocks)), userBlocks(parts))

def namedEntries(entries: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{SNil{}, _} <> rest: namedEntries(rest)
    case entry <> rest: entry <> namedEntries(rest)

def entryNames(entries: List<&2, R.Property<V.Value>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, _} <> rest: name <> entryNames(rest)

def entryValues(entries: List<&2, R.Property<V.Value>>) -> List<&2, V.Value>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{_, value} <> rest: value <> entryValues(rest)

def zipEntries(names: List<&2, String>, values: List<&2, V.Value>) -> List<&2, R.Property<V.Value>>:
  match names values:
    case name <> otherNames value <> otherValues: R.Property{name, value} <> zipEntries(otherNames, otherValues)
    case _ _: Nil{}

# Every value of the list with empty member names removed at any depth.
@unsafe def stripped(values: List<&2, V.Value>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case V.ArrayValue{items} <> rest: V.ArrayValue{stripped(items)} <> stripped(rest)
    case V.ObjectValue{R.Record{entries}} <> rest:
      +named = namedEntries(entries)
      V.ObjectValue{R.Record{zipEntries(entryNames(named), stripped(entryValues(named)))}} <> stripped(rest)
    case value <> rest: value <> stripped(rest)

def firstValue(values: List<&2, V.Value>) -> V.Value:
  match values:
    case value <> _: value
    case Nil{}: V.Null{}

def withoutEmptyKeys(value: V.Value) -> V.Value: firstValue(stripped(value <> Nil{}))

# upstream sanitizeBedrockDocument: object members with empty names removed.
def sanitizeDocument(value: V.Value) -> J(): SchemaJson.toJson(withoutEmptyKeys(value))

def redactedEncoded(result: Result<&2, &2, Base64.Error, String>) -> Maybe<&2, J()>:
  match result:
    case Done{text}: Some{obj(field("reasoningContent", obj(field("redactedContent", str(text), Nil{})), Nil{}))}
    case Fail{_}: None{}

def redactedBytes(result: Result<&2, &2, Base64.Error, List<&2, U32>>) -> Maybe<&2, J()>:
  match result:
    case Done{+bytes <> rest}: redactedEncoded(Base64.encode(bytes <> rest))
    case _: None{}

def redactedBlock(signature: Maybe<&2, String>) -> Maybe<&2, J()>:
  match signature:
    case Some{SCon{c, cs}}: redactedBytes(Base64.decode(SCon{c, cs}))
    case _: None{}

def blankSignature(signature: Maybe<&2, String>) -> Bool:
  match signature:
    case Some{text}: String.is_empty(Space.trim(text))
    case None{}: True{}

def reasoningText(thinking: String, signature: Maybe<&2, String>) -> J():
  obj(field("reasoningContent", obj(field("reasoningText", obj(field("text", str(thinking), optional("signature", Maybe.map(&2, String, J(), str, signature), Nil{}))), Nil{})), Nil{}))

def signedThinking(+thinking: String, +signature: Maybe<&2, String>, +signed: Bool) -> J():
  Bool.pick(J(), signed, Bool.pick(J(), blankSignature(signature), textBlock(thinking), reasoningText(thinking, signature)), reasoningText(thinking, None{}))

def thinkingBlock(+thinking: String, signature: Maybe<&2, String>, redacted: Maybe<&2, Bool>, +signed: Bool) -> Maybe<&2, J()>:
  match redacted:
    case Some{True{}}: redactedBlock(signature)
    case _:
      +sanitized = Unicode.sanitizeSurrogates(thinking)
      Bool.pick(Maybe<&2, J()>, String.is_empty(Space.trim(sanitized)), None{}, Some{signedThinking(sanitized, signature, signed)})

def prependMaybe(value: Maybe<&2, J()>, rest: List<&2, J()>) -> List<&2, J()>:
  match value:
    case None{}: rest
    case Some{item}: item <> rest

def assistantBlocks(blocks: List<&2, T.AssistantContent<V.Value>>, +signed: Bool) -> List<&2, J()>:
  match blocks:
    case Nil{}: Nil{}
    case T.AssistantText{T.TextContent{text, _}} <> rest: prependMaybe(nonBlankText(text), assistantBlocks(rest, signed))
    case T.AssistantToolCall{T.ToolCall{id, name, arguments, _, _}} <> rest: obj(field("toolUse", obj(field("toolUseId", str(id), field("name", str(name), field("input", sanitizeDocument(arguments), Nil{})))), Nil{})) <> assistantBlocks(rest, signed)
    case T.AssistantThinking{T.ThinkingContent{thinking, signature, redacted}} <> rest: prependMaybe(thinkingBlock(thinking, signature, redacted, signed), assistantBlocks(rest, signed))

def resultBlocks(parts: List<&2, T.TextImageContent>) -> Built(List<&2, J()>):
  match parts:
    case Nil{}: Done{Nil{}}
    case T.TextImageImage{T.ImageContent{data, mimeType}} <> rest: consBuilt(imageMember(createImageBlock(mimeType, data)), resultBlocks(rest))
    case T.TextImageText{T.TextContent{text, _}} <> rest: consMaybe(nonBlankText(text), resultBlocks(rest))

def toolResult(-D: Data, result: T.ToolResultMessage<D>) -> Built(J()):
  match result:
    case T.ToolResultMessage{id, _, content, _, _, isError, _}: Result.map(&2, &2, RequestError, List<&2, J()>, J(), blocks => obj(field("toolResult", obj(field("toolUseId", str(id), field("content", arr(placeholderIfEmpty(blocks)), field("status", str(Bool.pick(String, isError, "error", "success")), Nil{})))), Nil{})), resultBlocks(content))

type Converted is Data:
  Converted{role: String, content: List<&2, J()>}

def leadingResults(-G: Data, -D: Data, messages: List<&2, T.Message<V.Value, V.Value, G, D>>, reversed: List<&2, T.ToolResultMessage<D>>) -> List<&2, T.ToolResultMessage<D>> & List<&2, T.Message<V.Value, V.Value, G, D>>:
  match messages:
    case T.ToolResult{result} <> rest: leadingResults(G, D, rest, result <> reversed)
    case other: (List.reverse(&2, T.ToolResultMessage<D>, reversed), other)

def toolResults(-D: Data, results: List<&2, T.ToolResultMessage<D>>) -> Built(List<&2, J()>):
  match results:
    case Nil{}: Done{Nil{}}
    case result <> rest: consBuilt(toolResult(D, result), toolResults(D, rest))

def prependConverted(value: Maybe<&2, Converted>, rest: List<&2, Converted>) -> List<&2, Converted>:
  match value:
    case None{}: rest
    case Some{item}: item <> rest

def consConverted(head: Built(Maybe<&2, Converted>), rest: Built(List<&2, Converted>)) -> Built(List<&2, Converted>):
  do Result<&2, &2, RequestError, List<&2, Converted>>:
    value : Maybe<&2, Converted> <- head
    others : List<&2, Converted> <- rest
    return prependConverted(value, others)

def userConverted(content: T.UserContent) -> Built(Maybe<&2, Converted>):
  match content:
    case T.UserText{text}: Done{Some{Converted{"user", requiredText(text) <> Nil{}}}}
    case T.UserBlocks{parts}: Result.map(&2, &2, RequestError, List<&2, J()>, Maybe<&2, Converted>, blocks => Some{Converted{"user", placeholderIfEmpty(blocks)}}, userBlocks(parts))

def assistantConverted(blocks: List<&2, J()>) -> Maybe<&2, Converted>:
  match blocks:
    case Nil{}: None{}
    case other: Some{Converted{"assistant", other}}

def resultsConverted(-D: Data, results: List<&2, T.ToolResultMessage<D>>) -> Built(Maybe<&2, Converted>):
  Result.map(&2, &2, RequestError, List<&2, J()>, Maybe<&2, Converted>, blocks => Some{Converted{"user", blocks}}, toolResults(D, results))

def groupedResults(-G: Data, -D: Data, pair: List<&2, T.ToolResultMessage<D>> & List<&2, T.Message<V.Value, V.Value, G, D>>, +signed: Bool, continue: List<&2, T.Message<V.Value, V.Value, G, D>> -> Bool -> Built(List<&2, Converted>)) -> Built(List<&2, Converted>):
  match pair:
    case (results, rest): consConverted(resultsConverted(D, results), continue(rest, signed))

# The transformed transcript; consecutive tool results join one user message.
@unsafe def convertList(-G: Data, -D: Data, messages: List<&2, T.Message<V.Value, V.Value, G, D>>, +signed: Bool) -> Built(List<&2, Converted>):
  match messages:
    case Nil{}: Done{Nil{}}
    case T.User{T.UserMessage{content, _}} <> rest: consConverted(userConverted(content), convertList(G, D, rest, signed))
    case T.Assistant{T.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}} <> rest: consConverted(Done{assistantConverted(assistantBlocks(content, signed))}, convertList(G, D, rest, signed))
    case T.ToolResult{result} <> rest: groupedResults(G, D, leadingResults(G, D, rest, result <> Nil{}), signed, remaining => flag => convertList(G, D, remaining, flag))
    case _ <> rest: convertList(G, D, rest, signed)

def withCachePoint(messages: List<&2, Converted>, +point: Maybe<&2, J()>) -> List<&2, Converted>:
  match messages:
    case Nil{}: Nil{}
    case Converted{+name, +content} <> Nil{}: Converted{name, Bool.pick(List<&2, J()>, String.eq(name, "user"), List.append(&2, J(), content, Maybe.default(&2, List<&2, J()>, Maybe.map(&2, J(), List<&2, J()>, value => value <> Nil{}, point), Nil{})), content)} <> Nil{}
    case message <> rest: message <> withCachePoint(rest, point)

def renderedMessages(messages: List<&2, Converted>) -> List<&2, J()>:
  match messages:
    case Nil{}: Nil{}
    case Converted{name, content} <> rest: role(name, content) <> renderedMessages(rest)

# upstream convertMessages over the transformed transcript: the cache point
# goes on a trailing user message.
def convertMessages(-G: Data, -D: Data, messages: List<&2, T.Message<V.Value, V.Value, G, D>>, +model: T.Model<J()>, +retention: T.CacheRetention, forced: Bool) -> Built(List<&2, J()>):
  Result.map(&2, &2, RequestError, List<&2, Converted>, List<&2, J()>, converted => renderedMessages(withCachePoint(converted, Bool.pick(Maybe<&2, J()>, caching(model, retention, forced), Some{cachePoint(retention)}, None{}))), convertList(G, D, messages, supportsThinkingSignature(model)))

# Tools
# -----

def strictField(strict: Maybe<&2, Bool>) -> List<&2, R.Property<J()>>:
  match strict:
    case Some{True{}}: field("strict", T.JsonBoolean{True{}}, Nil{})
    case _: Nil{}

def toolSpec(+tool: T.Tool<V.Value>, strict: Maybe<&2, Bool>, parameters: Result<&2, &2, Sampling.Error, V.Value>) -> Built(J()):
  match tool parameters:
    case _ Fail{cause}: Fail{SamplingFailure{cause}}
    case T.Tool{name, description, _, _} Done{schema}: Done{obj(field("toolSpec", obj(field("name", str(name), field("description", str(description), field("inputSchema", obj(field("json", SchemaJson.toJson(schema), Nil{})), strictField(strict))))), Nil{}))}

def strictTool(+tool: T.Tool<V.Value>, resolved: Result<&2, &2, Sampling.Error, Maybe<&2, Bool>>) -> Built(J()):
  match resolved:
    case Fail{cause}: Fail{SamplingFailure{cause}}
    case Done{+strict}: toolSpec(tool, strict, Sampling.getJsonSchemaToolParameters(tool, strict))

def toolSpecs(tools: List<&2, T.Tool<V.Value>>, +supportsStrict: Bool) -> Built(List<&2, J()>):
  match tools:
    case Nil{}: Done{Nil{}}
    case +tool <> rest: consBuilt(strictTool(tool, Sampling.resolveJsonSchemaStrictSampling(tool, supportsStrict)), toolSpecs(rest, supportsStrict))

def choiceJson(choice: Maybe<&2, BedrockToolChoice>) -> Maybe<&2, J()>:
  match choice:
    case Some{ChoiceAuto{}}: Some{obj(field("auto", obj(Nil{}), Nil{}))}
    case Some{ChoiceAny{}}: Some{obj(field("any", obj(Nil{}), Nil{}))}
    case Some{ChoiceTool{name}}: Some{obj(field("tool", obj(field("name", str(name), Nil{})), Nil{}))}
    case _: None{}

def noChoice(choice: Maybe<&2, BedrockToolChoice>) -> Bool:
  match choice:
    case Some{ChoiceNone{}}: True{}
    case _: False{}

# upstream convertToolConfig: no tool configuration without tools or with
# toolChoice "none".
def convertToolConfig(tools: List<&2, T.Tool<V.Value>>, +choice: Maybe<&2, BedrockToolChoice>, supportsStrict: Bool) -> Built(Maybe<&2, J()>):
  match tools:
    case Nil{}: Done{None{}}
    case +first <> rest: Bool.pick(Built(Maybe<&2, J()>), noChoice(choice), Done{None{}}, Result.map(&2, &2, RequestError, List<&2, J()>, Maybe<&2, J()>, specs => Some{obj(field("tools", arr(specs), optional("toolChoice", choiceJson(choice), Nil{})))}, toolSpecs(first <> rest, supportsStrict)))

# Thinking
# --------

def displayName(value: BedrockThinkingDisplay) -> String:
  match value:
    case DisplaySummarized{}: "summarized"
    case DisplayOmitted{}: "omitted"

# upstream isGovCloudBedrockTarget.
def isGovCloudBedrockTarget(+model: T.Model<J()>, configuredRegion: Maybe<&2, String>) -> Bool:
  +id = lowerId(model)
  Maybe.default(&2, Bool, Maybe.map(&2, String, Bool, region => String.starts_with(String.to_lower(region), "us-gov-"), configuredRegion), False{}) || String.starts_with(id, "us-gov.") || String.starts_with(id, "arn:aws-us-gov:")

def budgetFor(level: T.ThinkingLevel, budgets: Maybe<&2, T.ThinkingBudgets>) -> F64:
  match level budgets:
    case T.Minimal{} Some{T.ThinkingBudgets{Some{value}, _, _, _}}: value
    case T.Low{} Some{T.ThinkingBudgets{_, Some{value}, _, _}}: value
    case T.Medium{} Some{T.ThinkingBudgets{_, _, Some{value}, _}}: value
    case T.High{} Some{T.ThinkingBudgets{_, _, _, Some{value}}}: value
    case T.XHigh{} Some{T.ThinkingBudgets{_, _, _, Some{value}}}: value
    case T.Max{} Some{T.ThinkingBudgets{_, _, _, Some{value}}}: value
    case T.Minimal{} _: F.fromU32(1024)
    case T.Low{} _: F.fromU32(2048)
    case T.Medium{} _: F.fromU32(8192)
    case _ _: F.fromU32(16384)

def displayField(display: Maybe<&2, String>) -> List<&2, R.Property<J()>>:
  match display:
    case None{}: Nil{}
    case Some{value}: field("display", str(value), Nil{})

def claudeFields(+model: T.Model<J()>, +level: T.ThinkingLevel, budgets: Maybe<&2, T.ThinkingBudgets>, interleaved: Maybe<&2, Bool>, +display: Maybe<&2, String>) -> J():
  +adaptive = supportsAdaptiveThinking(model)
  +beta = Bool.pick(List<&2, R.Property<J()>>, Bool.not(adaptive) && Maybe.default(&2, Bool, interleaved, True{}), field("anthropic_beta", arr([str("interleaved-thinking-2025-05-14")]), Nil{}), Nil{})
  Bool.pick(J(), adaptive, obj(field("thinking", obj(field("type", str("adaptive"), displayField(display))), field("output_config", obj(field("effort", str(mapThinkingLevelToEffort(model, level)), Nil{})), beta))), obj(field("thinking", obj(field("type", str("enabled"), field("budget_tokens", num(budgetFor(level, budgets)), displayField(display)))), beta)))

# upstream buildAdditionalModelRequestFields.
def buildAdditionalModelRequestFields(+model: T.Model<J()>, reasoning: Maybe<&2, T.ThinkingLevel>, budgets: Maybe<&2, T.ThinkingBudgets>, interleaved: Maybe<&2, Bool>, display: Maybe<&2, BedrockThinkingDisplay>, configuredRegion: Maybe<&2, String>) -> Maybe<&2, J()>:
  match reasoning:
    case None{}: None{}
    case Some{level}: Bool.pick(Maybe<&2, J()>, T.modelReasoning(model) && isAnthropicClaudeModel(model), Some{claudeFields(model, level, budgets, interleaved, Bool.pick(Maybe<&2, String>, isGovCloudBedrockTarget(model, configuredRegion), None{}, Some{displayName(Maybe.default(&2, BedrockThinkingDisplay, display, DisplaySummarized{}))}))}, None{})

def stringEntries(entries: List<&2, R.Property<String>>) -> List<&2, R.Property<J()>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, str(value)} <> stringEntries(rest)

def metadataJson(record: R.Record<String>) -> J():
  match record:
    case R.Record{entries}: obj(stringEntries(entries))

# upstream stream's commandInput, as onPayload sees it.
def commandInput(+model: T.Model<J()>, messages: List<&2, J()>, system: Maybe<&2, J()>, maxTokens: Maybe<&2, F64>, temperature: Maybe<&2, F64>, toolConfig: Maybe<&2, J()>, additional: Maybe<&2, J()>, requestMetadata: Maybe<&2, R.Record<String>>) -> J():
  obj(field("modelId", str(T.modelId(model)), field("messages", arr(messages), optional("system", system, field("inferenceConfig", obj(optional("maxTokens", Maybe.map(&2, F64, J(), num, maxTokens), optional("temperature", Maybe.map(&2, F64, J(), num, temperature), Nil{}))), optional("toolConfig", toolConfig, optional("additionalModelRequestFields", additional, optional("requestMetadata", Maybe.map(&2, R.Record<String>, J(), metadataJson, requestMetadata), Nil{}))))))))

# The ConverseStream request members the SDK serializes into the JSON body,
# in its schema order; modelId is the path label.
def BODY_MEMBERS() -> List<&2, String>:
  ["messages", "system", "inferenceConfig", "toolConfig", "guardrailConfig", "additionalModelRequestFields", "promptVariables", "additionalModelResponseFieldPaths", "requestMetadata", "performanceConfig", "serviceTier", "outputConfig"]

def bodyMembers(names: List<&2, String>, +fields: R.Record<J()>) -> List<&2, R.Property<J()>>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest: optional(name, R.get(J(), fields, name), bodyMembers(rest, fields))

def wireBody(payload: J()) -> J():
  match payload:
    case T.JsonObject{fields}: obj(bodyMembers(BODY_MEMBERS(), fields))
    case other: other

def stringMember(value: Maybe<&2, J()>, fallback: String) -> String:
  match value:
    case Some{T.JsonString{text}}: text
    case _: fallback

def payloadModelId(payload: J(), fallback: String) -> String:
  match payload:
    case T.JsonObject{fields}: stringMember(R.get(J(), fields, "modelId"), fallback)
    case _: fallback

def extendedEscape(bytes: List<&2, U32>) -> String: SigV4.escapedBytes(bytes)

# The request path: the model id as an escaped label.
def requestPath(modelId: String) -> String: "/model/" ++ SigV4.escapeUri(modelId) ++ "/converse-stream"

# Stream fold
# -----------

def Message(-G: Data) -> Data: T.AssistantMessage<V.Value, G>

def Event(-G: Data) -> Data: T.AssistantMessageEvent<V.Value, G>

def Content() -> Data: T.AssistantContent<V.Value>

# upstream's per-block streaming scratch fields (index, partialJson,
# redactedChunks), kept beside the content block at `position`.
type Scratch is Data:
  Scratch{position: Nat, index: Maybe<&2, F64>, partialJson: String, redacted: Maybe<&2, List<&2, U32>>}

type State<-G: Data> is Data:
  State{output: Message(G), scratch: List<&2, Scratch>}

type Step<-G: Data> is Data:
  Step{state: State<G>, events: List<&2, Event(G)>}

def createOutput(-G: Data, model: T.Model<J()>, timestamp: F64) -> Message(G):
  match model:
    case T.Model{id, _, api, provider, _, _, _, _, _, _, _, _, _, _, _, _}: T.AssistantMessage{Nil{}, ModelApi.name(api), provider, id, None{}, None{}, None{}, None{}, T.Usage{zero(), zero(), zero(), zero(), None{}, None{}, zero(), T.UsageCost{zero(), zero(), zero(), zero(), zero()}}, T.Pending{}, None{}, None{}, None{}, None{}, timestamp}

def outputOf(-G: Data, state: State<G>) -> Message(G):
  match state:
    case State{output, _}: output

def contentOf(-G: Data, message: Message(G)) -> List<&2, Content()>: T.assistantContent(V.Value, G, message)

def withContent(-G: Data, message: Message(G), change: List<&2, Content()> -> List<&2, Content()>) -> Message(G):
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{change(content), api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}

def updatedAt(content: List<&2, Content()>, +index: Nat, change: Content() -> Content()) -> List<&2, Content()>:
  match content index:
    case Nil{} _: Nil{}
    case head <> rest 0n: change(head) <> rest
    case head <> rest 1n+previous: head <> updatedAt(rest, previous, change)

def blockAt(content: List<&2, Content()>, +index: Nat) -> Maybe<&2, Content()>:
  match content index:
    case Nil{} _: None{}
    case head <> _ 0n: Some{head}
    case _ <> rest 1n+previous: blockAt(rest, previous)

def sameIndex(value: Maybe<&2, F64>, +index: F64) -> Bool:
  match value:
    case Some{other}: F.isEqual(F.compare(other, index))
    case None{}: False{}

# `blocks.findIndex((b) => b.index === contentBlockIndex)`.
def scratchFor(entries: List<&2, Scratch>, +index: F64) -> Maybe<&2, Scratch>:
  match entries:
    case Nil{}: None{}
    case Scratch{+position, +at, +json, +redacted} <> rest: Bool.pick(Maybe<&2, Scratch>, sameIndex(at, index), Some{Scratch{position, at, json, redacted}}, scratchFor(rest, index))

def replaced(entries: List<&2, Scratch>, +updated: Scratch) -> List<&2, Scratch>:
  match entries updated:
    case Nil{} _: Nil{}
    case Scratch{+position, at, json, redacted} <> rest Scratch{+target, _, _, _}: Bool.pick(Scratch, Nat.is_eq(position, target), updated, Scratch{position, at, json, redacted}) <> replaced(rest, updated)

def appendBlock(-G: Data, state: State<G>, block: Content(), +index: F64) -> State<G> & Nat:
  match state:
    case State{+output, scratch}:
      +position = List.length(&2, Content(), contentOf(G, output))
      (State{withContent(G, output, content => List.append(&2, Content(), content, block <> Nil{})), List.append(&2, Scratch, scratch, Scratch{position, Some{index}, "", None{}} <> Nil{})}, position)

def nonNull(value: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  match value:
    case Some{V.Null{}}: None{}
    case other: other

def member(value: Maybe<&2, V.Value>, +name: String) -> Maybe<&2, V.Value>:
  match value:
    case Some{V.ObjectValue{fields}}: nonNull(R.get(V.Value, fields, name))
    case _: None{}

def textValue(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{text}}: Some{text}
    case _: None{}

def numberValue(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{number}}: Some{number}
    case _: None{}

def lastPosition(-G: Data, +message: Message(G)) -> F64: F.fromNat(List.length(&2, Content(), contentOf(G, message)) - 1n)

def toolStarted(-G: Data, pair: State<G> & Nat) -> Step<G>:
  match pair:
    case (State{+output, scratch}, position): Step{State{output, scratch}, T.ToolcallStart{F.fromNat(position), output} <> Nil{}}

def startedWith(-G: Data, state: State<G>, +index: F64, toolUse: Maybe<&2, V.Value>) -> Step<G>:
  match toolUse:
    case None{}: Step{state, Nil{}}
    case Some{+use}: toolStarted(G, appendBlock(G, state, T.AssistantToolCall{T.ToolCall{Maybe.default(&2, String, textValue(member(Some{use}, "toolUseId")), ""), Maybe.default(&2, String, textValue(member(Some{use}, "name")), ""), V.ObjectValue{R.new(V.Value)}, None{}, None{}}}, index))

# upstream handleContentBlockStart: a tool-use start opens a tool call block.
def blockStart(-G: Data, state: State<G>, +event: Maybe<&2, V.Value>) -> Step<G>:
  startedWith(G, state, Maybe.default(&2, F64, numberValue(member(event, "contentBlockIndex")), zero()), member(member(event, "start"), "toolUse"))

type DeltaKind is Data:
  TextDeltaKind{text: String}
  ToolDeltaKind{input: String}
  ReasoningDeltaKind{text: Maybe<&2, String>, signature: Maybe<&2, String>, redacted: List<&2, U32>}
  NoDelta{}

def truthyText(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{SCon{c, cs}}}: Some{SCon{c, cs}}
    case _: None{}

def blobBytes(result: Result<&2, &2, Base64.Error, List<&2, U32>>) -> List<&2, U32>:
  match result:
    case Done{bytes}: bytes
    case Fail{_}: Nil{}

def decodedBlob(value: Maybe<&2, V.Value>) -> List<&2, U32>:
  match value:
    case Some{V.Text{text}}: blobBytes(Base64.decode(text))
    case _: Nil{}

def present(value: Maybe<&2, V.Value>) -> Bool: Maybe.is_some(&2, V.Value, value)

def truthyObject(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.ObjectValue{_}}: True{}
    case Some{V.ArrayValue{_}}: True{}
    case _: False{}

def objectFieldsOf(value: Maybe<&2, V.Value>) -> R.Record<V.Value>:
  match value:
    case Some{V.ObjectValue{fields}}: fields
    case _: R.new(V.Value)

# `delta.text !== undefined`, then a tool-use input, then reasoning content.
def deltaKind(+delta: Maybe<&2, V.Value>) -> DeltaKind:
  +text = R.get(V.Value, objectFieldsOf(delta), "text")
  +toolUse = member(delta, "toolUse")
  +reasoning = member(delta, "reasoningContent")
  Bool.pick(DeltaKind, present(text), TextDeltaKind{Maybe.default(&2, String, textValue(text), "")}, Bool.pick(DeltaKind, truthyObject(toolUse), ToolDeltaKind{Maybe.default(&2, String, truthyText(member(toolUse, "input")), "")}, Bool.pick(DeltaKind, truthyObject(reasoning), ReasoningDeltaKind{truthyText(member(reasoning, "text")), truthyText(member(reasoning, "signature")), decodedBlob(member(reasoning, "redactedContent"))}, NoDelta{})))

def appendText(block: Content(), +delta: String) -> Content():
  match block:
    case T.AssistantText{T.TextContent{text, signature}}: T.AssistantText{T.TextContent{text ++ delta, signature}}
    case other: other

def isText(block: Maybe<&2, Content()>) -> Bool:
  match block:
    case Some{T.AssistantText{_}}: True{}
    case _: False{}

def isThinking(block: Maybe<&2, Content()>) -> Bool:
  match block:
    case Some{T.AssistantThinking{_}}: True{}
    case _: False{}

def isToolCall(block: Maybe<&2, Content()>) -> Bool:
  match block:
    case Some{T.AssistantToolCall{_}}: True{}
    case _: False{}

def positionOf(entry: Scratch) -> Nat:
  match entry:
    case Scratch{position, _, _, _}: position

def blockOf(-G: Data, state: State<G>, +position: Nat) -> Maybe<&2, Content()>:
  match state:
    case State{output, _}: blockAt(contentOf(G, output), position)

def textAppended(-G: Data, state: State<G>, +position: Nat, +text: String) -> Step<G>:
  match state:
    case State{output, scratch}:
      +message = withContent(G, output, content => updatedAt(content, position, block => appendText(block, text)))
      Step{State{message, scratch}, T.TextDelta{F.fromNat(position), text, message} <> Nil{}}

def textAt(-G: Data, +state: State<G>, +position: Nat, +text: String) -> Step<G>:
  Bool.pick(Step<G>, isText(blockOf(G, state, position)), textAppended(G, state, position, text), Step{state, Nil{}})

def withEvents(-G: Data, step: Step<G>, before: List<&2, Event(G)>) -> Step<G>:
  match step:
    case Step{state, events}: Step{state, List.append(&2, Event(G), before, events)}

def textStarted(-G: Data, pair: State<G> & Nat, +text: String) -> Step<G>:
  match pair:
    case (State{+output, scratch}, +position): withEvents(G, textAt(G, State{output, scratch}, position, text), T.TextStart{F.fromNat(position), output} <> Nil{})

# upstream handleContentBlockDelta for text: the first delta of an index
# opens its text block.
def textDelta(-G: Data, +state: State<G>, +index: F64, entry: Maybe<&2, Scratch>, +text: String) -> Step<G>:
  match entry:
    case None{}: textStarted(G, appendBlock(G, state, T.AssistantText{T.TextContent{"", None{}}}, index), text)
    case Some{found}: textAt(G, state, positionOf(found), text)

def withArguments(block: Content(), +arguments: V.Value) -> Content():
  match block:
    case T.AssistantToolCall{T.ToolCall{id, name, _, signature, namespace}}: T.AssistantToolCall{T.ToolCall{id, name, arguments, signature, namespace}}
    case other: other

def toolInput(-G: Data, state: State<G>, entry: Scratch, +input: String) -> Step<G>:
  match state entry:
    case State{output, scratch} Scratch{+position, at, json, redacted}:
      +accumulated = json ++ input
      +arguments = JsonRepair.parseStreamingJson(Some{accumulated})
      +message = withContent(G, output, content => updatedAt(content, position, block => withArguments(block, arguments)))
      Step{State{message, replaced(scratch, Scratch{position, at, accumulated, redacted})}, T.ToolcallDelta{F.fromNat(position), input, message} <> Nil{}}

def toolDelta(-G: Data, +state: State<G>, entry: Maybe<&2, Scratch>, +input: String) -> Step<G>:
  match entry:
    case None{}: Step{state, Nil{}}
    case Some{+found}: Bool.pick(Step<G>, isToolCall(blockOf(G, state, positionOf(found))), toolInput(G, state, found, input), Step{state, Nil{}})

def thinkingParts(block: Maybe<&2, Content()>) -> Maybe<&2, T.ThinkingContent>:
  match block:
    case Some{T.AssistantThinking{content}}: Some{content}
    case _: None{}

def isRedacted(value: Maybe<&2, T.ThinkingContent>) -> Bool:
  match value:
    case Some{T.ThinkingContent{_, _, Some{True{}}}}: True{}
    case _: False{}

def mapThinking(block: Content(), change: T.ThinkingContent -> T.ThinkingContent) -> Content():
  match block:
    case T.AssistantThinking{content}: T.AssistantThinking{change(content)}
    case other: other

def changedBlock(-G: Data, state: State<G>, +position: Nat, change: T.ThinkingContent -> T.ThinkingContent) -> State<G>:
  match state:
    case State{output, scratch}: State{withContent(G, output, content => updatedAt(content, position, block => mapThinking(block, change))), scratch}

def appendThinking(content: T.ThinkingContent, +delta: String) -> T.ThinkingContent:
  match content:
    case T.ThinkingContent{thinking, signature, redacted}: T.ThinkingContent{thinking ++ delta, signature, redacted}

def thinkingDelta(-G: Data, state: State<G>, +position: Nat, +delta: String) -> Step<G>:
  match state:
    case State{+output, scratch}: Step{State{output, scratch}, T.ThinkingDelta{F.fromNat(position), delta, output} <> Nil{}}

def thinkingText(-G: Data, state: State<G>, +position: Nat, text: Maybe<&2, String>) -> Step<G>:
  match text:
    case None{}: Step{state, Nil{}}
    case Some{+delta}: thinkingDelta(G, changedBlock(G, state, position, content => appendThinking(content, delta)), position, delta)

def appendSignature(content: T.ThinkingContent, +part: String) -> T.ThinkingContent:
  match content:
    case T.ThinkingContent{thinking, signature, redacted}: T.ThinkingContent{thinking, Some{Maybe.default(&2, String, signature, "") ++ part}, redacted}

def thinkingSignature(-G: Data, +state: State<G>, +position: Nat, signature: Maybe<&2, String>) -> State<G>:
  match signature:
    case None{}: state
    case Some{+part}: Bool.pick(State<G>, isRedacted(thinkingParts(blockOf(G, state, position))), state, changedBlock(G, state, position, content => appendSignature(content, part)))

def markedRedacted(content: T.ThinkingContent) -> T.ThinkingContent:
  match content:
    case T.ThinkingContent{thinking, _, _}: T.ThinkingContent{thinking ++ REDACTED_THINKING_PLACEHOLDER(), Some{""}, Some{True{}}}

def chunked(entries: List<&2, Scratch>, +position: Nat, +bytes: List<&2, U32>) -> List<&2, Scratch>:
  match entries:
    case Nil{}: Nil{}
    case Scratch{+at, +index, +json, +redacted} <> rest: Bool.pick(Scratch, Nat.is_eq(at, position), Scratch{at, index, json, Some{List.append(&2, U32, Maybe.default(&2, List<&2, U32>, redacted, Nil{}), bytes)}}, Scratch{at, index, json, redacted}) <> chunked(rest, position, bytes)

def withChunk(-G: Data, state: State<G>, +position: Nat, bytes: List<&2, U32>) -> State<G>:
  match state:
    case State{output, scratch}: State{output, chunked(scratch, position, bytes)}

# Encrypted reasoning: the first chunk marks the block redacted with the
# placeholder text; every chunk joins the scratch buffer.
def thinkingRedacted(-G: Data, +state: State<G>, +position: Nat, bytes: List<&2, U32>) -> Step<G>:
  match bytes:
    case Nil{}: Step{state, Nil{}}
    case +first <> +rest: Bool.pick(Step<G>, isRedacted(thinkingParts(blockOf(G, state, position))), Step{withChunk(G, state, position, first <> rest), Nil{}}, thinkingDelta(G, withChunk(G, changedBlock(G, state, position, markedRedacted), position, first <> rest), position, REDACTED_THINKING_PLACEHOLDER()))

type Reading<-G: Data> is Data:
  Reading{decoder: EventStream.Decoder, state: State<G>}

def withUsage(-G: Data, message: Message(G), usage: T.Usage) -> Message(G):
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, _, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}

def reasoningOf(usage: T.Usage) -> Maybe<&2, F64>:
  match usage:
    case T.Usage{_, _, _, _, _, reasoning, _, _}: reasoning

def truthyNumber(value: Maybe<&2, V.Value>) -> F64:
  match value:
    case Some{V.Number{+number}}: Bool.pick(F64, F.isEqual(F.compare(number, zero())) || F.isNaN(number), zero(), number)
    case _: zero()

def cacheDetails(values: List<&2, V.Value>, +total: F64) -> F64:
  match values:
    case Nil{}: total
    case +detail <> rest: cacheDetails(rest, Bool.pick(F64, String.eq(Maybe.default(&2, String, textValue(member(Some{detail}, "ttl")), ""), "1h"), F.add(total, Maybe.default(&2, F64, numberValue(member(Some{detail}, "inputTokens")), zero())), total))

def cacheWrite1h(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.ArrayValue{details}}: Some{cacheDetails(details, zero())}
    case _: None{}

def usageWithCost(+model: T.Model<J()>, usage: T.Usage) -> T.Usage:
  match usage:
    case T.Usage{+input, +output, +cacheRead, +cacheWrite, +longWrite, +reasoning, +total, _}: T.Usage{input, output, cacheRead, cacheWrite, longWrite, reasoning, total, Cost.calculate(J(), model, T.Usage{input, output, cacheRead, cacheWrite, longWrite, reasoning, total, T.UsageCost{zero(), zero(), zero(), zero(), zero()}})}

def usageFrom(+model: T.Model<J()>, +usage: Maybe<&2, V.Value>, reasoning: Maybe<&2, F64>) -> T.Usage:
  +input = truthyNumber(member(usage, "inputTokens"))
  +out = truthyNumber(member(usage, "outputTokens"))
  +total = truthyNumber(member(usage, "totalTokens"))
  usageWithCost(model, T.Usage{input, out, truthyNumber(member(usage, "cacheReadInputTokens")), truthyNumber(member(usage, "cacheWriteInputTokens")), cacheWrite1h(member(usage, "cacheDetails")), reasoning, Bool.pick(F64, F.isEqual(F.compare(total, zero())), F.add(input, out), total), T.UsageCost{zero(), zero(), zero(), zero(), zero()}})

def usageApplied(-G: Data, +model: T.Model<J()>, state: State<G>, +value: V.Value) -> State<G>:
  match state:
    case State{+output, scratch}: State{withUsage(G, output, usageFrom(model, Some{value}, reasoningOf(T.assistantUsage(V.Value, G, output)))), scratch}

def withMetadata(-G: Data, +model: T.Model<J()>, state: State<G>, usage: Maybe<&2, V.Value>) -> State<G>:
  match usage:
    case None{}: state
    case Some{value}: usageApplied(G, model, state, value)

# upstream handleMetadata.
def metadataEvent(-G: Data, +model: T.Model<J()>, state: State<G>, +event: Maybe<&2, V.Value>) -> State<G>:
  withMetadata(G, model, state, member(event, "usage"))

# What ends a request: upstream's thrown values, as the SDK or pi throw them.
type Failure is Data:
  # A non-2xx response: the SDK's BedrockRuntimeServiceException subclass.
  ServiceFailure{status: U32, name: String, message: String, requestId: Maybe<&2, String>}
  # A modeled exception frame: the SDK throws the modeled exception (named
  # after the frame's :exception-type) with the payload's message.
  StreamException{name: String, message: String}
  # An unmodeled error frame: an Error named after its :error-code.
  StreamErrorFrame{code: String, message: String}
  # Errors without provider metadata (transport failures, pi's own throws).
  PlainFailure{message: String}

# How reading ended.
type Outcome is Data:
  Consumed{}
  ReadFailed{}
  Thrown{failure: Failure}

type Loop<-G: Data> is Data:
  Pull{reading: Reading<G>}
  Frames{reading: Reading<G>, frames: List<&2, EventStream.Message>}
  Stop{state: State<G>, outcome: Outcome}

def withState(-G: Data, reading: Reading<G>, state: State<G>) -> Reading<G>:
  match reading:
    case Reading{decoder, _}: Reading{decoder, state}

def continued(-G: Data, reading: Reading<G>, frames: List<&2, EventStream.Message>, step: Step<G>) -> List<&2, Event(G)> & Loop<G>:
  match step:
    case Step{state, events}: (events, Frames{withState(G, reading, state), frames})

def then(-G: Data, step: Step<G>, next: State<G> -> Step<G>) -> Step<G>:
  match step:
    case Step{state, events}: withEvents(G, next(state), events)

def reasoningAt(-G: Data, +state: State<G>, +position: Nat, text: Maybe<&2, String>, signature: Maybe<&2, String>, redacted: List<&2, U32>) -> Step<G>:
  Bool.pick(Step<G>, isThinking(blockOf(G, state, position)), then(G, thinkingText(G, state, position, text), next => thinkingRedacted(G, thinkingSignature(G, next, position, signature), position, redacted)), Step{state, Nil{}})

def thinkingStarted(-G: Data, pair: State<G> & Nat, text: Maybe<&2, String>, signature: Maybe<&2, String>, redacted: List<&2, U32>) -> Step<G>:
  match pair:
    case (State{+output, scratch}, +position): withEvents(G, reasoningAt(G, State{output, scratch}, position, text, signature, redacted), T.ThinkingStart{F.fromNat(position), output} <> Nil{})

def reasoningDelta(-G: Data, +state: State<G>, +index: F64, entry: Maybe<&2, Scratch>, text: Maybe<&2, String>, signature: Maybe<&2, String>, redacted: List<&2, U32>) -> Step<G>:
  match entry:
    case None{}: thinkingStarted(G, appendBlock(G, state, T.AssistantThinking{T.ThinkingContent{"", Some{""}, None{}}}, index), text, signature, redacted)
    case Some{found}: reasoningAt(G, state, positionOf(found), text, signature, redacted)

def scratchOf(-G: Data, state: State<G>) -> List<&2, Scratch>:
  match state:
    case State{_, scratch}: scratch

def deltaStep(-G: Data, +state: State<G>, +index: F64, kind: DeltaKind) -> Step<G>:
  match kind:
    case TextDeltaKind{text}: textDelta(G, state, index, scratchFor(scratchOf(G, state), index), text)
    case ToolDeltaKind{input}: toolDelta(G, state, scratchFor(scratchOf(G, state), index), input)
    case ReasoningDeltaKind{text, signature, redacted}: reasoningDelta(G, state, index, scratchFor(scratchOf(G, state), index), text, signature, redacted)
    case NoDelta{}: Step{state, Nil{}}

# upstream handleContentBlockDelta.
def blockDelta(-G: Data, state: State<G>, +event: Maybe<&2, V.Value>) -> Step<G>:
  deltaStep(G, state, Maybe.default(&2, F64, numberValue(member(event, "contentBlockIndex")), zero()), deltaKind(member(event, "delta")))

def base64Text(result: Result<&2, &2, Base64.Error, String>) -> String:
  match result:
    case Done{text}: text
    case Fail{_}: ""

def flushedSignature(content: T.ThinkingContent, +bytes: List<&2, U32>) -> T.ThinkingContent:
  match content:
    case T.ThinkingContent{thinking, _, redacted}: T.ThinkingContent{thinking, Some{base64Text(Base64.encode(bytes))}, redacted}

def flushedIn(-G: Data, state: State<G>, +position: Nat, index: Maybe<&2, F64>, json: String, +bytes: List<&2, U32>) -> State<G>:
  match state:
    case State{output, scratch}: State{withContent(G, output, content => updatedAt(content, position, block => mapThinking(block, value => flushedSignature(value, bytes)))), replaced(scratch, Scratch{position, index, json, None{}})}

# upstream flushRedactedContent: the buffered encrypted reasoning becomes the
# base64 thinkingSignature and the buffer is dropped.
def flushed(-G: Data, state: State<G>, entry: Scratch) -> State<G>:
  match entry:
    case Scratch{position, index, json, Some{bytes}}: flushedIn(G, state, position, index, json, bytes)
    case _: state

# `delete block.index`.
def unindexed(entries: List<&2, Scratch>, +position: Nat) -> List<&2, Scratch>:
  match entries:
    case Nil{}: Nil{}
    case Scratch{+at, index, +json, +redacted} <> rest: Bool.pick(Scratch, Nat.is_eq(at, position), Scratch{at, None{}, json, redacted}, Scratch{at, index, json, redacted}) <> unindexed(rest, position)

def withoutIndex(-G: Data, state: State<G>, +position: Nat) -> State<G>:
  match state:
    case State{output, scratch}: State{output, unindexed(scratch, position)}

def textOf(block: Maybe<&2, Content()>) -> String:
  match block:
    case Some{T.AssistantText{T.TextContent{text, _}}}: text
    case Some{T.AssistantThinking{T.ThinkingContent{thinking, _, _}}}: thinking
    case _: ""

def callOf(block: Maybe<&2, Content()>) -> Maybe<&2, T.ToolCall<V.Value>>:
  match block:
    case Some{T.AssistantToolCall{call}}: Some{call}
    case _: None{}

def streamEnded(-G: Data, state: State<G>, result: Result<&2, &2, EventStream.Error, Unit>) -> Loop<G>:
  match result:
    case Fail{_}: Stop{state, Thrown{PlainFailure{"Truncated event stream"}}}
    case Done{_}: Stop{state, Consumed{}}

def ended(-G: Data, state: State<G>, +position: Nat, block: Maybe<&2, Content()>) -> Step<G>:
  match state block:
    case State{+output, scratch} Some{T.AssistantText{T.TextContent{text, _}}}: Step{State{output, scratch}, T.TextEnd{F.fromNat(position), text, output} <> Nil{}}
    case State{+output, scratch} Some{T.AssistantThinking{T.ThinkingContent{thinking, _, _}}}: Step{State{output, scratch}, T.ThinkingEnd{F.fromNat(position), thinking, output} <> Nil{}}
    case State{+output, scratch} Some{T.AssistantToolCall{call}}: Step{State{output, scratch}, T.ToolcallEnd{F.fromNat(position), call, output} <> Nil{}}
    case other _: Step{other, Nil{}}

def partialOf(entry: Scratch) -> String:
  match entry:
    case Scratch{_, _, json, _}: json

def finishedCall(-G: Data, state: State<G>, +position: Nat, json: String) -> State<G>:
  match state:
    case State{output, scratch}:
      +arguments = JsonRepair.parseStreamingJson(Some{json})
      State{withContent(G, output, content => updatedAt(content, position, block => withArguments(block, arguments))), scratch}

# upstream handleContentBlockStop: the block's end event, with a tool call's
# final arguments and a thinking block's flushed payload.
def stopped(-G: Data, state: State<G>, +entry: Scratch) -> Step<G>:
  +position = positionOf(entry)
  +cleared = withoutIndex(G, state, position)
  +finished = Bool.pick(State<G>, isToolCall(blockOf(G, cleared, position)), finishedCall(G, cleared, position, partialOf(entry)), flushed(G, cleared, entry))
  ended(G, finished, position, blockOf(G, finished, position))

def blockStopFor(-G: Data, +state: State<G>, entry: Maybe<&2, Scratch>) -> Step<G>:
  match entry:
    case None{}: Step{state, Nil{}}
    case Some{found}: stopped(G, state, found)

def blockStop(-G: Data, +state: State<G>, +event: Maybe<&2, V.Value>) -> Step<G>:
  blockStopFor(G, state, scratchFor(scratchOf(G, state), Maybe.default(&2, F64, numberValue(member(event, "contentBlockIndex")), zero())))

# upstream finalizeStreamingBlock over every block.
def finalizedEntries(-G: Data, entries: List<&2, Scratch>, state: State<G>) -> State<G>:
  match entries:
    case Nil{}: state
    case entry <> rest: finalizedEntries(G, rest, flushed(G, state, entry))

def finalized(-G: Data, +state: State<G>) -> Message(G): outputOf(G, finalizedEntries(G, scratchOf(G, state), state))

# upstream mapStopReason.
type StopMapping is Data:
  StopMapping{stopReason: T.StopReason, errorMessage: Maybe<&2, String>}

def mapStopReason(reason: Maybe<&2, String>) -> StopMapping:
  match reason:
    case Some{"end_turn"}: StopMapping{T.Stop{}, None{}}
    case Some{"stop_sequence"}: StopMapping{T.Stop{}, None{}}
    case Some{"max_tokens"}: StopMapping{T.Length{}, None{}}
    case Some{"model_context_window_exceeded"}: StopMapping{T.Length{}, None{}}
    case Some{"tool_use"}: StopMapping{T.ToolUse{}, None{}}
    case Some{SCon{c, cs}}: StopMapping{T.Error{}, Some{"Provider stopped with: " ++ SCon{c, cs}}}
    case _: StopMapping{T.Error{}, None{}}

def withStop(-G: Data, message: Message(G), raw: Maybe<&2, String>, mapped: StopMapping) -> Message(G):
  match message mapped:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, _, deferred, error, _, endTurn, timestamp} StopMapping{stop, errorMessage}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, Maybe.or(&2, String, errorMessage, error), raw, endTurn, timestamp}

def messageStop(-G: Data, state: State<G>, +event: Maybe<&2, V.Value>) -> State<G>:
  match state:
    case State{output, scratch}:
      +raw = textValue(member(event, "stopReason"))
      State{withStop(G, output, raw, mapStopReason(raw)), scratch}

# Failures
# --------

def BEDROCK_ERROR_PREFIX(+name: String) -> String:
  match name:
    case "InternalServerException": "Internal server error"
    case "ModelStreamErrorException": "Model stream error"
    case "ValidationException": "Validation error"
    case "ThrottlingException": "Throttling error"
    case "ServiceUnavailableException": "Service unavailable"
    case other: other

def containsIgnoringCase(+text: String, needle: String) -> Bool: String.contains(String.to_lower(text), needle)

def dataRetentionHint(+core: String) -> String:
  Bool.pick(String, containsIgnoringCase(core, "data retention mode"), " See https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html for supported data retention modes.", "")

def safeJson(value: J()) -> String: Maybe.default(&2, String, JsonWire.stringify(value), "null")

# upstream formatBedrockError.
def formatBedrockError(failure: Failure) -> String:
  match failure:
    case ServiceFailure{_, +name, +message, _}: BEDROCK_ERROR_PREFIX(name) ++ ": " ++ message ++ dataRetentionHint(message)
    case StreamException{+name, +message}: BEDROCK_ERROR_PREFIX(name) ++ ": " ++ message ++ dataRetentionHint(message)
    case StreamErrorFrame{_, +message}: message ++ dataRetentionHint(message)
    case PlainFailure{+message}: message ++ dataRetentionHint(message)

def boundedValue(+text: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, String.is_empty(text) || Nat.is_gt(Utf16.length(text), 200n), None{}, Some{text})

# upstream normalizeDiagnosticValue: trimmed, at most 200 UTF-16 units.
def normalizeDiagnosticValue(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case None{}: None{}
    case Some{text}: boundedValue(Space.trim(text))

def errorCode(+name: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, String.ends_with(name, "Exception"), normalizeDiagnosticValue(Some{name}), None{})

def detailFields(status: Maybe<&2, U32>, code: Maybe<&2, String>, requestId: Maybe<&2, String>) -> List<&2, R.Property<J()>>:
  optional("status", Maybe.map(&2, U32, J(), value => num(F.fromU32(value)), status), optional("errorCode", Maybe.map(&2, String, J(), str, code), optional("requestId", Maybe.map(&2, String, J(), str, requestId), Nil{})))

def failureDetails(failure: Failure, +fallback: Maybe<&2, String>) -> List<&2, R.Property<J()>>:
  match failure:
    case ServiceFailure{status, name, _, requestId}: detailFields(Some{status}, errorCode(name), Maybe.or(&2, String, normalizeDiagnosticValue(requestId), fallback))
    case StreamErrorFrame{code, _}: detailFields(None{}, errorCode(code), fallback)
    case StreamException{name, _}: detailFields(None{}, errorCode(name), fallback)
    case _: detailFields(None{}, None{}, fallback)

# upstream appendBedrockFailureDiagnostic: status, error code and request id
# when known, nothing otherwise.
def diagnosticWith(~G: Data, ~details: J() -> G, fields: List<&2, R.Property<J()>>, now: F64) -> Maybe<&2, Diagnostics.AssistantMessageDiagnostic<G>>:
  match fields:
    case Nil{}: None{}
    case +first <> rest:
      detail = details(obj(first <> rest))
      Some{Diagnostics.AssistantMessageDiagnostic{"bedrock_response_failure", now, None{}, Some{detail}}}

def failureDiagnostic(~G: Data, ~details: J() -> G, failure: Failure, fallback: Maybe<&2, String>, now: F64) -> Maybe<&2, Diagnostics.AssistantMessageDiagnostic<G>>:
  diagnosticWith(~G, ~details, failureDetails(failure, fallback), now)

# Reading the stream
# ------------------

def EventStreamOut(-G: Data) -> Data: Events.AssistantMessageEventStream(V.Value, G)

def push(-G: Data, +events: EventStreamOut(G), event: Event(G)) -> IO(Unit):
  Events.push(Event(G), Message(G), events, event)

def publish(-G: Data, +events: EventStreamOut(G), values: List<&2, Event(G)>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case event <> rest:
      do IO<Unit>:
        push(G, events, event)
        publish(G, events, rest)

def readingState(-G: Data, reading: Reading<G>) -> State<G>:
  match reading:
    case Reading{_, state}: state

def decoded(-G: Data, state: State<G>, result: Result<&2, &2, EventStream.Error, EventStream.Decoded>) -> Loop<G>:
  match result:
    case Fail{_}: Stop{state, Thrown{PlainFailure{"Invalid event stream frame"}}}
    case Done{EventStream.Decoded{decoder, frames}}: Frames{Reading{decoder, state}, frames}

def pulled(-Reason: Data, -G: Data, reading: Reading<G>, result: Result<&2, &2, Http.ReadError(Reason), Maybe<&2, List<&2, U32>>>) -> Loop<G>:
  match reading result:
    case Reading{_, state} Fail{_}: Stop{state, ReadFailed{}}
    case Reading{decoder, state} Done{None{}}: streamEnded(G, state, EventStream.finish(decoder))
    case Reading{decoder, state} Done{Some{bytes}}: decoded(G, state, EventStream.decode(decoder, bytes))

def parsedPayload(result: Result<&2, &2, Decode.ParseError, V.Value>) -> Maybe<&2, V.Value>:
  match result:
    case Done{value}: Some{value}
    case Fail{_}: None{}

def jsonPayload(bytes: List<&2, U32>) -> Maybe<&2, V.Value>: parsedPayload(Decode.parse(EventStream.utf8Text(bytes)))

def stateStep(-G: Data, state: State<G>) -> Step<G>: Step{state, Nil{}}

# What sending needs besides the payload.
type Setup<-Reason: Data, -E: Data> is Data:
  Setup{config: ClientConfig, headers: Maybe<&2, T.ProviderHeaders()>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, fetch: Fetch.Fetch(Reason), urlContext: URL.Context}

# The request settings that do not depend on the transcript.
type Request<-E: Data> is Data:
  Request{system: Maybe<&2, String>, retention: T.CacheRetention, forced: Bool, maxTokens: Maybe<&2, F64>, temperature: Maybe<&2, F64>, choice: Maybe<&2, BedrockToolChoice>, additional: Maybe<&2, J()>, requestMetadata: Maybe<&2, R.Record<String>>, onPayload: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>}

def appendDiagnostic(-G: Data, diagnostics: Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<G>>>, diagnostic: Maybe<&2, Diagnostics.AssistantMessageDiagnostic<G>>) -> Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<G>>>:
  match diagnostic:
    case None{}: diagnostics
    case Some{value}: Some{List.append(&2, Diagnostics.AssistantMessageDiagnostic<G>, Maybe.default(&2, List<&2, Diagnostics.AssistantMessageDiagnostic<G>>, diagnostics, Nil{}), value <> Nil{})}

def withErrorStop(-G: Data, message: Message(G), stop: T.StopReason, errorMessage: String, diagnostic: Maybe<&2, Diagnostics.AssistantMessageDiagnostic<G>>) -> Message(G):
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, _, deferred, _, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, appendDiagnostic(G, diagnostics, diagnostic), usage, stop, deferred, Some{errorMessage}, raw, endTurn, timestamp}

def failedEvent(~G: Data, ~details: J() -> G, output: Message(G), +aborted: Bool, +failure: Failure, requestId: Maybe<&2, String>, now: F64) -> Event(G):
  +diagnostic = Bool.pick(Maybe<&2, Diagnostics.AssistantMessageDiagnostic<G>>, aborted, None{}, failureDiagnostic(~G, ~details, failure, requestId, now))
  T.StreamError{Bool.pick(T.ErrorReason, aborted, T.ErrorAborted{}, T.ErrorError{}), withErrorStop(G, output, Bool.pick(T.StopReason, aborted, T.Aborted{}, T.Error{}), formatBedrockError(failure), diagnostic)}

# upstream's catch block: every block finalized, the stop reason from the
# caller's signal and the formatted error, with the failure diagnostic for
# errors (not aborts).
def failed(~Reason: Data, ~G: Data, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +state: State<G>, failure: Failure, requestId: Maybe<&2, String>) -> IO(Unit):
  do IO<Unit>:
    aborted : Bool <- Abort.aborted(Reason, parent)
    now : F64 <- Date.now()
    push(G, events, failedEvent(~G, ~details, finalized(G, state), aborted, failure, requestId, now))

def setupConfig(-Reason: Data, -E: Data, setup: Setup<Reason, E>) -> ClientConfig:
  match setup:
    case Setup{config, _, _, _, _}: config

# How a request authenticates: the bearer token, or SigV4 credentials.
type Auth is Data:
  BearerAuth{token: String}
  SignedAuth{credentials: SigV4.Credentials}

def regionOf(config: ClientConfig) -> Maybe<&2, String>:
  match config:
    case ClientConfig{_, region, _, _, _}: region

def profileOf(config: ClientConfig) -> Maybe<&2, String>:
  match config:
    case ClientConfig{profile, _, _, _, _}: profile

# The service endpoint for a region (bedrock-runtime, amazonaws.com.cn in the
# China partition) unless the configuration names one.
def endpointFor(endpoint: Maybe<&2, String>, +region: String) -> String:
  match endpoint:
    case Some{SCon{c, cs}}: SCon{c, cs}
    case _: "https://bedrock-runtime." ++ region ++ Bool.pick(String, String.starts_with(region, "cn-"), ".amazonaws.com.cn", ".amazonaws.com")

def trimTrailingSlashes(reversed: String) -> String:
  match reversed:
    case SCon{'/', rest}: trimTrailingSlashes(rest)
    case other: String.reverse(other)

def requestUrl(endpoint: String, +modelId: String) -> String: trimTrailingSlashes(String.reverse(endpoint)) ++ requestPath(modelId)

def reservedHeader(+name: String) -> Bool:
  +lower = String.to_lower(name)
  String.starts_with(lower, "x-amz-") || String.eq(lower, "authorization") || String.eq(lower, "host")

# upstream addCustomHeadersMiddleware: caller headers other than the SigV4
# and auth ones, added before signing.
def customFields(entries: List<&2, R.Property<String>>) -> List<&2, SigV4.Field>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{+name, value} <> rest:
      +tail = customFields(rest)
      Bool.pick(List<&2, SigV4.Field>, reservedHeader(name), tail, SigV4.Field{name, value} <> tail)

def customRecord(record: Maybe<&2, R.Record<String>>) -> List<&2, SigV4.Field>:
  match record:
    case Some{R.Record{entries}}: customFields(entries)
    case None{}: Nil{}

def custom(headers: Maybe<&2, T.ProviderHeaders()>) -> List<&2, SigV4.Field>: customRecord(HeaderUtils.providerHeadersToRecord(headers))

def authority(url: URL.URL) -> String:
  match url:
    case URL.URL{_, _, _, Some{host}, None{}, _, _, _}: URL.serializeHost(host)
    case URL.URL{_, _, _, Some{host}, Some{port}, _, _, _}: URL.serializeHost(host) ++ ":" ++ U32.show(port)
    case _: ""

def pathOf(url: URL.URL) -> String:
  match url:
    case URL.URL{_, _, _, _, _, path, _, _}: URL.serializePath(path)

def signedFields(signed: SigV4.Signed) -> List<&2, SigV4.Field>:
  match signed:
    case SigV4.Signed{headers, _, _}: headers

def authorizedWith(auth: Auth, region: String, date: String, +url: URL.URL, +body: List<&2, U32>, +base: List<&2, SigV4.Field>) -> List<&2, SigV4.Field>:
  match auth:
    case BearerAuth{token}: List.append(&2, SigV4.Field, base, SigV4.Field{"authorization", "Bearer " ++ token} <> Nil{})
    case SignedAuth{credentials}: signedFields(SigV4.sign(credentials, region, "bedrock", date, SigV4.Request{"POST", pathOf(url), Nil{}, base, body}))

# The request headers: content type, host and length, the caller's headers,
# then SigV4 (x-amz-date, token, payload hash, authorization) or the bearer
# token.
def authorized(auth: Auth, region: String, date: String, +url: URL.URL, +body: List<&2, U32>, extra: List<&2, SigV4.Field>) -> List<&2, SigV4.Field>:
  authorizedWith(auth, region, date, url, body, List.append(&2, SigV4.Field, [SigV4.Field{"content-type", "application/json"}, SigV4.Field{"content-length", Nat.show(List.length(&2, U32, body))}, SigV4.Field{"host", authority(url)}], extra))

def isoDate(value: Maybe<&2, String>) -> String: SigV4.amzDate(Maybe.default(&2, String, value, "1970-01-01T00:00:00.000Z"))

# The transport writes Host and Content-Length itself, from the same URL and
# body the signature covers.
def skipped(+result: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, +name: String, value: String) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  Bool.pick(Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, String.eq(String.to_lower(name), "host") || String.eq(String.to_lower(name), "content-length"), result, Http.layered(result, name, value))

def fieldHeaders(fields: List<&2, SigV4.Field>, result: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match fields:
    case Nil{}: result
    case SigV4.Field{name, value} <> rest: fieldHeaders(rest, skipped(result, name, value))

def requestHeaders(fields: List<&2, SigV4.Field>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>: fieldHeaders(fields, Done{Headers.new()})

def entryValue(entries: List<&2, R.Property<String>>, +name: String) -> Maybe<&2, String>:
  match entries:
    case Nil{}: None{}
    case R.Property{+key, +value} <> rest: Bool.pick(Maybe<&2, String>, String.eq(String.to_lower(key), name), Some{value}, entryValue(rest, name))

def headerValue(headers: R.Record<String>, +name: String) -> Maybe<&2, String>:
  match headers:
    case R.Record{entries}: entryValue(entries, name)

# The SDK's $metadata.requestId.
def requestIdOf(+headers: R.Record<String>) -> Maybe<&2, String>:
  firstOf([headerValue(headers, "x-amzn-requestid"), headerValue(headers, "x-amzn-request-id"), headerValue(headers, "x-amz-request-id")])

def beforeChar(text: String, +stop: Char) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{+c, rest}: Bool.pick(String, String.eq(SCon{c, SNil{}}, SCon{stop, SNil{}}), SNil{}, SCon{c, beforeChar(rest, stop)})

def secondPart(parts: List<&2, String>, text: String) -> String:
  match parts:
    case _ <> second <> _: second
    case _: text

def afterHash(+text: String) -> String: secondPart(String.split(text, '#'), text)

# @aws-sdk/core sanitizeErrorCode.
def sanitizeErrorCode(+raw: String) -> String: afterHash(beforeChar(beforeChar(raw, ','), ':'))

def valueMember(entries: List<&2, R.Property<V.Value>>, +name: String) -> Maybe<&2, String>:
  match entries:
    case Nil{}: None{}
    case R.Property{+key, V.Text{+value}} <> rest: Bool.pick(Maybe<&2, String>, String.eq(String.to_lower(key), name), Some{value}, valueMember(rest, name))
    case _ <> rest: valueMember(rest, name)

def objectMember(fields: R.Record<V.Value>, +name: String) -> Maybe<&2, String>:
  match fields:
    case R.Record{entries}: valueMember(entries, name)

def errorFields(result: Result<&2, &2, Decode.ParseError, V.Value>) -> R.Record<V.Value>:
  match result:
    case Done{V.ObjectValue{fields}}: fields
    case _: R.new(V.Value)

def exactMember(fields: R.Record<V.Value>, name: String) -> Maybe<&2, String>: textValue(R.get(V.Value, fields, name))

# A non-2xx response as the SDK's service exception: the code from
# x-amzn-errortype, the body's code or __type; the message from message or
# Message.
def serviceFailure(+status: U32, +headers: R.Record<String>, body: String) -> Failure:
  +fields = errorFields(Decode.parse(body))
  +code = Maybe.map(&2, String, String, raw => sanitizeErrorCode(raw), firstOf([headerValue(headers, "x-amzn-errortype"), objectMember(fields, "code"), exactMember(fields, "__type")]))
  ServiceFailure{status, Maybe.default(&2, String, code, "Unknown"), Maybe.default(&2, String, firstOf([exactMember(fields, "message"), exactMember(fields, "Message")]), "UnknownError"), requestIdOf(headers)}

def errorText(~Reason: Data, result: Result<&2, &2, Response.TextError<Http.ExchangeError(Reason)>, String>) -> String:
  match result:
    case Done{text}: text
    case Fail{_}: ""

def assistantRole(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.Text{"assistant"}}: True{}
    case _: False{}

def isAssistantRole(payload: Maybe<&2, V.Value>) -> Bool: assistantRole(member(payload, "role"))

def messageStarted(-G: Data, state: State<G>, +payload: Maybe<&2, V.Value>) -> Step<G>:
  match state:
    case State{+output, scratch}: Step{State{output, scratch}, T.Start{output} <> Nil{}}

def eventStepIn(-G: Data, +model: T.Model<J()>, +reading: Reading<G>, frames: List<&2, EventStream.Message>, kind: String, +payload: Maybe<&2, V.Value>, +state: State<G>) -> List<&2, Event(G)> & Loop<G>:
  match kind:
    case "messageStart": Bool.pick(List<&2, Event(G)> & Loop<G>, isAssistantRole(payload), continued(G, reading, frames, messageStarted(G, state, payload)), (Nil{}, Stop{state, Thrown{PlainFailure{"Unexpected assistant message start but got user message start instead"}}}))
    case "contentBlockStart": continued(G, reading, frames, blockStart(G, state, payload))
    case "contentBlockDelta": continued(G, reading, frames, blockDelta(G, state, payload))
    case "contentBlockStop": continued(G, reading, frames, blockStop(G, state, payload))
    case "messageStop": continued(G, reading, frames, stateStep(G, messageStop(G, state, payload)))
    case "metadata": continued(G, reading, frames, stateStep(G, metadataEvent(G, model, state, payload)))
    case _: continued(G, reading, frames, stateStep(G, state))

# One event frame, by its :event-type.
def eventStep(-G: Data, +model: T.Model<J()>, +reading: Reading<G>, frames: List<&2, EventStream.Message>, +kind: String, +payload: Maybe<&2, V.Value>) -> List<&2, Event(G)> & Loop<G>:
  eventStepIn(G, model, reading, frames, kind, payload, readingState(G, reading))

def capitalized(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{c, rest}: String.to_upper(SCon{c, SNil{}}) ++ rest

def messageOf(+payload: Maybe<&2, V.Value>) -> Maybe<&2, String>: firstOf([textValue(member(payload, "message")), textValue(member(payload, "Message"))])

def typedFrame(-G: Data, +model: T.Model<J()>, +reading: Reading<G>, frames: List<&2, EventStream.Message>, messageType: Maybe<&2, String>, +headers: List<&2, EventStream.Header>, +payload: List<&2, U32>) -> List<&2, Event(G)> & Loop<G>:
  match messageType:
    case Some{"exception"}: (Nil{}, Stop{readingState(G, reading), Thrown{StreamException{capitalized(Maybe.default(&2, String, EventStream.header(headers, ":exception-type"), "")), Maybe.default(&2, String, messageOf(jsonPayload(payload)), "UnknownError")}}})
    case Some{"error"}: (Nil{}, Stop{readingState(G, reading), Thrown{StreamErrorFrame{Maybe.default(&2, String, EventStream.header(headers, ":error-code"), "UnknownError"), Maybe.default(&2, String, EventStream.header(headers, ":error-message"), "UnknownError")}}})
    case _: eventStep(G, model, reading, frames, Maybe.default(&2, String, EventStream.header(headers, ":event-type"), ""), jsonPayload(payload))

# One decoded frame: an event, a modeled exception or an unmodeled error.
def frameStep(-G: Data, +model: T.Model<J()>, +reading: Reading<G>, frames: List<&2, EventStream.Message>, frame: EventStream.Message) -> List<&2, Event(G)> & Loop<G>:
  match frame:
    case EventStream.Message{+headers, payload}: typedFrame(G, model, reading, frames, EventStream.header(headers, ":message-type"), headers, payload)

def published(-G: Data, +events: EventStreamOut(G), pair: List<&2, Event(G)> & Loop<G>) -> IO(Loop<G>):
  match pair:
    case (values, following):
      do IO<Loop<G>>:
        publish(G, events, values)
        return following

@unsafe def drive(~Reason: Data, ~G: Data, +events: EventStreamOut(G), +source: Http.Source(Reason), +model: T.Model<J()>, state: Loop<G>) -> IO(State<G> & Outcome):
  match state:
    case Stop{result, outcome}: IO.pure(State<G> & Outcome, (result, outcome))
    case Pull{reading}:
      do IO<State<G> & Outcome>:
        result : Result<&2, &2, Http.ReadError(Reason), Maybe<&2, List<&2, U32>>> <- Http.read(~Reason, source)
        drive(~Reason, ~G, events, source, model, pulled(Reason, G, reading, result))
    case Frames{reading, Nil{}}: drive(~Reason, ~G, events, source, model, Pull{reading})
    case Frames{reading, frame <> rest}:
      do IO<State<G> & Outcome>:
        following : Loop<G> <- published(G, events, frameStep(G, model, reading, rest, frame))
        drive(~Reason, ~G, events, source, model, following)

def doneReason(stop: T.StopReason) -> T.DoneReason:
  match stop:
    case T.Length{}: T.DoneLength{}
    case T.ToolUse{}: T.DoneToolUse{}
    case T.Deferred{}: T.DoneDeferred{}
    case _: T.DoneStop{}

def errorOrUnknown(value: Maybe<&2, String>) -> String:
  match value:
    case Some{SCon{c, cs}}: SCon{c, cs}
    case _: "An unknown error occurred"

def stoppedWith(~Reason: Data, ~G: Data, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +state: State<G>, requestId: Maybe<&2, String>, stop: T.StopReason) -> IO(Unit):
  match stop:
    case T.Pending{}: failed(~Reason, ~G, ~details, events, parent, state, PlainFailure{"Bedrock stream ended without a stop reason"}, requestId)
    case T.Error{}: failed(~Reason, ~G, ~details, events, parent, state, PlainFailure{errorOrUnknown(T.assistantErrorMessage(V.Value, G, outputOf(G, state)))}, requestId)
    case T.Aborted{}: failed(~Reason, ~G, ~details, events, parent, state, PlainFailure{errorOrUnknown(T.assistantErrorMessage(V.Value, G, outputOf(G, state)))}, requestId)
    case other:
      +message = finalized(G, state)
      push(G, events, T.StreamDone{doneReason(other), message})

def completed(~Reason: Data, ~G: Data, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +state: State<G>, requestId: Maybe<&2, String>, aborted: Bool) -> IO(Unit):
  match aborted:
    case True{}: failed(~Reason, ~G, ~details, events, parent, state, PlainFailure{"Request was aborted"}, requestId)
    case False{}: stoppedWith(~Reason, ~G, ~details, events, parent, state, requestId, T.assistantStopReason(V.Value, G, outputOf(G, state)))

def readFailure(aborted: Bool) -> Failure:
  match aborted:
    case True{}: PlainFailure{"Request aborted"}
    case False{}: PlainFailure{"terminated"}

def settled(~Reason: Data, ~G: Data, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +requestId: Maybe<&2, String>, pair: State<G> & Outcome) -> IO(Unit):
  match pair:
    case (state, Consumed{}):
      do IO<Unit>:
        aborted : Bool <- Abort.aborted(Reason, parent)
        completed(~Reason, ~G, ~details, events, parent, state, requestId, aborted)
    case (state, ReadFailed{}):
      do IO<Unit>:
        aborted : Bool <- Abort.aborted(Reason, parent)
        failed(~Reason, ~G, ~details, events, parent, state, readFailure(aborted), requestId)
    case (state, Thrown{failure}): failed(~Reason, ~G, ~details, events, parent, state, failure, requestId)

def streamed(~Reason: Data, ~G: Data, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, +requestId: Maybe<&2, String>, pair: Http.Owner(Reason) & Http.Source(Reason)) -> IO(Unit):
  match pair:
    case (owner, source):
      do IO<Unit>:
        result : State<G> & Outcome <- drive(~Reason, ~G, events, source, model, Pull{Reading{EventStream.create(), state}})
        Http.release(~Reason, owner)
        settled(~Reason, ~G, ~details, events, parent, requestId, result)

def releasedPair(~Reason: Data, pair: Http.Owner(Reason) & Http.Source(Reason)) -> IO(Unit):
  match pair:
    case (owner, _): Http.release(~Reason, owner)

def discarded(~Reason: Data, body: Http.Body(Reason)) -> IO(Unit):
  do IO<Unit>:
    pair : Http.Owner(Reason) & Http.Source(Reason) <- Http.reader(~Reason, body)
    releasedPair(~Reason, pair)

def hooked(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, +requestId: Maybe<&2, String>, body: Http.Body(Reason), result: Result<&2, &2, E, Unit>) -> IO(Unit):
  match result:
    case Fail{cause}:
      do IO<Unit>:
        discarded(~Reason, body)
        failed(~Reason, ~G, ~details, events, parent, state, PlainFailure{render(cause)}, requestId)
    case Done{_}:
      do IO<Unit>:
        pair : Http.Owner(Reason) & Http.Source(Reason) <- Http.reader(~Reason, body)
        streamed(~Reason, ~G, ~details, events, parent, model, state, requestId, pair)

def succeededWith(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, +metadata: Response.Metadata, body: Http.Body(Reason), +requestId: Maybe<&2, String>) -> IO(Unit):
  match hook:
    case None{}: hooked(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, requestId, body, Done{Unit{}})
    case Some{callback}:
      do IO<Unit>:
        result : Result<&2, &2, E, Unit> <- C.call(T.ResponseInput<T.Model<J()>>, Result<&2, &2, E, Unit>, callback, T.ResponseInput{Http.providerResponse(metadata), model})
        hooked(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, requestId, body, result)

# upstream's deserialize-step middleware hands onResponse the raw response
# before the event stream is read.
def succeeded(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, +metadata: Response.Metadata, body: Http.Body(Reason)) -> IO(Unit):
  succeededWith(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, hook, metadata, body, normalizeDiagnosticValue(requestIdOf(HeaderUtils.headersToRecord(Response.headers(metadata)))))

def statusChecked(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, +metadata: Response.Metadata, body: Http.Body(Reason), ok: Bool) -> IO(Unit):
  match ok:
    case True{}: succeeded(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, hook, metadata, body)
    case False{}:
      do IO<Unit>:
        text : Result<&2, &2, Response.TextError<Http.ExchangeError(Reason)>, String> <- Http.responseText(~Reason, 1048576n, body)
        failed(~Reason, ~G, ~details, events, parent, state, serviceFailure(Response.metadataStatus(metadata), HeaderUtils.headersToRecord(Response.headers(metadata)), errorText(~Reason, text)), None{})

def transportFailure(-Reason: Data, aborted: Bool) -> Failure:
  match aborted:
    case True{}: PlainFailure{"Request aborted"}
    case False{}: PlainFailure{"fetch failed"}

def responded(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, response: Fetch.Result_(Reason)) -> IO(Unit):
  match response:
    case Fail{_}:
      do IO<Unit>:
        aborted : Bool <- Abort.aborted(Reason, parent)
        failed(~Reason, ~G, ~details, events, parent, state, transportFailure(Reason, aborted), None{})
    case Done{Response.Response{+metadata, body}}: statusChecked(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, hook, metadata, body, Response.ok(metadata))

def exchanged(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, fetch: Fetch.Fetch(Reason), request: Http.Request, pair: Deadline.Scope<Reason> & Fetch.Signal(Reason)) -> IO(Unit):
  match pair:
    case (scope, signal):
      do IO<Unit>:
        response : Fetch.Result_(Reason) <- Http.post(~Reason, fetch, signal, request)
        responded(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, hook, response)
        closed : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Unit{}

# The SDK passes only the caller's signal; the native fetch takes a deadline
# scope, which here never expires (the maximum U32 milliseconds).
def exchange(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, fetch: Fetch.Fetch(Reason), request: Http.Request) -> IO(Unit):
  do IO<Unit>:
    scope : Deadline.Scope<Reason> <- Deadline.create(Reason, 4294967295, parent)
    exchanged(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, hook, fetch, request, Deadline.borrow(Reason, scope))

def dispatched(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, fetch: Fetch.Fetch(Reason), url: URL.URL, headers: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, body: String) -> IO(Unit):
  match headers:
    case Fail{_}: failed(~Reason, ~G, ~details, events, parent, state, PlainFailure{"Invalid header"}, None{})
    case Done{fields}: exchange(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, hook, fetch, Http.Request{url, fields, body})

def addressed(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, setup: Setup<Reason, E>, auth: Auth, +region: String, +body: String, url: Result<&2, &2, URL.Error, URL.URL>) -> IO(Unit):
  match setup url:
    case _ Fail{_}: failed(~Reason, ~G, ~details, events, parent, state, PlainFailure{"Invalid URL"}, None{})
    case Setup{_, headers, hook, fetch, _} Done{+address}:
      do IO<Unit>:
        now : F64 <- Date.now()
        dispatched(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, hook, fetch, address, requestHeaders(authorized(auth, region, isoDate(Date.formatIso(now)), address, Utf8.encode(body), custom(headers))), body)

def setupContext(-Reason: Data, -E: Data, setup: Setup<Reason, E>) -> URL.Context:
  match setup:
    case Setup{_, _, _, _, context}: context

def endpointOf(config: ClientConfig) -> Maybe<&2, String>:
  match config:
    case ClientConfig{_, _, endpoint, _, _}: endpoint

def regioned(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, +setup: Setup<Reason, E>, auth: Auth, +payload: J(), region: Maybe<&2, String>) -> IO(Unit):
  match region:
    case None{}: failed(~Reason, ~G, ~details, events, parent, state, PlainFailure{"Region is missing"}, None{})
    case Some{+value}: addressed(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, setup, auth, value, Maybe.default(&2, String, JsonWire.stringify(wireBody(payload)), "{}"), URL.parse(setupContext(Reason, E, setup), requestUrl(endpointFor(endpointOf(setupConfig(Reason, E, setup)), value), payloadModelId(payload, T.modelId(model)))))

def withRegion(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, +setup: Setup<Reason, E>, auth: Auth, +payload: J(), configured: Maybe<&2, String>) -> IO(Unit):
  match configured:
    case Some{region}: regioned(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, setup, auth, payload, Some{region})
    case None{}:
      do IO<Unit>:
        region : Maybe<&2, String> <- Credentials.resolveRegion(profileOf(setupConfig(Reason, E, setup)))
        regioned(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, setup, auth, payload, region)

# The SDK resolves the region (config, AWS_REGION, the profile) when sending.
def withAuth(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, +setup: Setup<Reason, E>, +payload: J(), auth: Result<&2, &2, String, Auth>) -> IO(Unit):
  match auth:
    case Fail{message}: failed(~Reason, ~G, ~details, events, parent, state, PlainFailure{message}, None{})
    case Done{value}: withRegion(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, setup, value, payload, regionOf(setupConfig(Reason, E, setup)))

def clientRegion(configured: Maybe<&2, String>, profile: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match configured:
    case Some{region}: IO.pure(Maybe<&2, String>, Some{region})
    case None{}: Credentials.resolveRegion(profile)

def setupFetch(-Reason: Data, -E: Data, setup: Setup<Reason, E>) -> Fetch.Fetch(Reason):
  match setup:
    case Setup{_, _, _, fetch, _}: fetch

def signedWith(result: Result<&2, &2, String, SigV4.Credentials>) -> Result<&2, &2, String, Auth>:
  match result:
    case Fail{message}: Fail{message}
    case Done{credentials}: Done{SignedAuth{credentials}}

# The endpoint (and so the region) resolves before the request is signed; the
# chain's own requests are not tied to the caller's abort signal.
def chained(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, +setup: Setup<Reason, E>, +payload: J(), profile: Maybe<&2, String>, region: Maybe<&2, String>) -> IO(Unit):
  match region:
    case None{}: failed(~Reason, ~G, ~details, events, parent, state, PlainFailure{"Region is missing"}, None{})
    case Some{+value}:
      do IO<Unit>:
        controller : Abort.AbortController<Reason> <- Abort.new(Reason)
        resolved : Result<&2, &2, String, SigV4.Credentials> <- Credentials.resolveCredentials(~Reason, Credentials.Chain{CredentialHttp.Transport{setupFetch(Reason, E, setup), setupContext(Reason, E, setup), Abort.signal(Reason, controller)}, Some{value}, profile})
        withAuth(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, setup, payload, signedWith(resolved))

def fromChain(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, +setup: Setup<Reason, E>, +payload: J(), +profile: Maybe<&2, String>) -> IO(Unit):
  do IO<Unit>:
    region : Maybe<&2, String> <- clientRegion(regionOf(setupConfig(Reason, E, setup)), profile)
    chained(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, setup, payload, profile, region)

def sendWith(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, +setup: Setup<Reason, E>, +payload: J(), config: ClientConfig) -> IO(Unit):
  match config:
    case ClientConfig{_, _, _, _, Some{token}}: withAuth(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, setup, payload, Done{BearerAuth{token}})
    case ClientConfig{_, _, _, Some{credentials}, None{}}: withAuth(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, setup, payload, Done{SignedAuth{credentials}})
    case ClientConfig{profile, _, _, None{}, None{}}: fromChain(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, setup, payload, profile)

# Bearer token, configured credentials, then the SDK's default chain.
def send(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, +setup: Setup<Reason, E>, +payload: J()) -> IO(Unit):
  sendWith(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, setup, payload, setupConfig(Reason, E, setup))

def payloaded(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, +setup: Setup<Reason, E>, original: J(), result: Result<&2, &2, E, Maybe<&2, J()>>) -> IO(Unit):
  match result:
    case Fail{cause}: failed(~Reason, ~G, ~details, events, parent, state, PlainFailure{render(cause)}, None{})
    case Done{replacement}: send(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, setup, Maybe.default(&2, J(), replacement, original))

def withPayloadHook(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, +setup: Setup<Reason, E>, +payload: J(), hook: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>) -> IO(Unit):
  match hook:
    case None{}: send(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, setup, payload)
    case Some{callback}:
      do IO<Unit>:
        result : Result<&2, &2, E, Maybe<&2, J()>> <- C.call(T.PayloadInput<J(), T.Model<J()>>, Result<&2, &2, E, Maybe<&2, J()>>, callback, T.PayloadInput{payload, model})
        payloaded(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, setup, payload, result)

def built(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, +setup: Setup<Reason, E>, request: Request<E>, messages: Built(List<&2, J()>), tools: Built(Maybe<&2, J()>)) -> IO(Unit):
  match messages tools request:
    case Fail{cause} _ _: failed(~Reason, ~G, ~details, events, parent, state, PlainFailure{requestErrorMessage(cause)}, None{})
    case _ Fail{cause} _: failed(~Reason, ~G, ~details, events, parent, state, PlainFailure{requestErrorMessage(cause)}, None{})
    case Done{converted} Done{toolConfig} Request{system, +retention, forced, maxTokens, temperature, _, additional, metadata, hook}:
      withPayloadHook(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, setup, commandInput(model, converted, buildSystemPrompt(system, model, retention, forced), maxTokens, temperature, toolConfig, additional, metadata), hook)

def supportsStrictMode(model: T.Model<J()>) -> Bool:
  match model:
    case T.Model{_, _, T.BedrockConverseStreamApi{}, _, _, _, _, _, _, _, _, _, _, _, _, Some{T.BedrockCompat{Some{True{}}}}}: True{}
    case _: False{}

def convertedWith(~Reason: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, +setup: Setup<Reason, E>, request: Request<E>, tools: List<&2, T.Tool<V.Value>>, messages: List<&2, T.Message<V.Value, V.Value, G, D>>) -> IO(Unit):
  match request:
    case Request{system, +retention, +forced, maxTokens, temperature, +choice, additional, metadata, hook}: built(~Reason, ~E, ~G, ~render, ~details, events, parent, model, state, setup, Request{system, retention, forced, maxTokens, temperature, choice, additional, metadata, hook}, convertMessages(G, D, messages, model, retention, forced), convertToolConfig(tools, choice, supportsStrictMode(model)))

def transformed(~Reason: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, +setup: Setup<Reason, E>, +request: Request<E>, tools: List<&2, T.Tool<V.Value>>, result: Result<&2, &2, Sampling.Error, List<&2, T.Message<V.Value, V.Value, G, D>>>) -> IO(Unit):
  match result:
    case Fail{cause}: failed(~Reason, ~G, ~details, events, parent, state, PlainFailure{Sampling.errorMessage(cause)}, None{})
    case Done{messages}: convertedWith(~Reason, ~E, ~G, ~D, ~render, ~details, events, parent, model, state, setup, request, tools, messages)

def normalizedInput(-A: Data, -G: Data, -M: Data, input: Transform.NormalizeToolCallIdInput<A, G, M>) -> IO(Result<&2, &2, Sampling.Error, String>):
  match input:
    case Transform.NormalizeToolCallIdInput{id, _, _}: IO.pure(Result<&2, &2, Sampling.Error, String>, Done{normalizeToolCallId(id)})

def normalizeBody(-A: Data, -G: Data, -M: Data, unused: Unit) -> Transform.NormalizeToolCallIdInput<A, G, M> -> IO(Result<&2, &2, Sampling.Error, String>):
  input => normalizedInput(A, G, M, input)

# convertMessages' transformMessages over the transcript without its leading
# system message, with Bedrock's tool-call ids.
def prepared(~Reason: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, +setup: Setup<Reason, E>, +request: Request<E>, context: T.TranscriptContext<V.Value, V.Value, G, D>) -> IO(Unit):
  match context:
    case T.TranscriptContext{+messages}:
      do IO<Unit>:
        +normalizer : Transform.Normalizer(V.Value, G, J(), Sampling.Error) <- C.create(~Unit, ~Transform.NormalizeToolCallIdInput<V.Value, G, J()>, ~Result<&2, &2, Sampling.Error, String>, ~(normalizeBody(V.Value, G, J())), Unit{})
        result : Result<&2, &2, Sampling.Error, List<&2, T.Message<V.Value, V.Value, G, D>>> <- Transform.transformMessages(~V.Value, ~V.Value, ~G, ~D, ~J(), ~Sampling.Error, Transcript.withoutInitialSystemMessage(V.Value, V.Value, G, D, messages), model, Some{normalizer})
        C.dispose(Transform.NormalizeToolCallIdInput<V.Value, G, J()>, Result<&2, &2, Sampling.Error, String>, normalizer)
        transformed(~Reason, ~E, ~G, ~D, ~render, ~details, events, parent, model, state, setup, request, Transcript.getCurrentTools(V.Value, V.Value, G, D, messages), result)

# upstream resolveCacheRetention: "short" unless set, or PI_CACHE_RETENTION=long.
def retentionOf(cacheRetention: Maybe<&2, T.CacheRetention>, legacy: Maybe<&2, String>) -> T.CacheRetention:
  match cacheRetention legacy:
    case Some{value} _: value
    case None{} Some{"long"}: T.CacheLong{}
    case None{} _: T.CacheShort{}

def forcedCache(value: Maybe<&2, String>) -> Bool:
  match value:
    case Some{"1"}: True{}
    case _: False{}

def systemText(-G: Data, -D: Data, messages: List<&2, T.Message<V.Value, V.Value, G, D>>) -> Maybe<&2, String>:
  Maybe.map(&2, T.SystemMessage<V.Value>, String, message => Text.renderComplete(V.Value, message), Transcript.getInitialSystemMessage(V.Value, V.Value, G, D, messages))

def contextMessages(-G: Data, -D: Data, context: T.TranscriptContext<V.Value, V.Value, G, D>) -> List<&2, T.Message<V.Value, V.Value, G, D>>:
  match context:
    case T.TranscriptContext{messages}: messages

def inferenceMaxTokens(+model: T.Model<J()>, maxTokens: Maybe<&2, F64>) -> Maybe<&2, F64>:
  match maxTokens:
    case Some{value}: Some{value}
    case None{}: Bool.pick(Maybe<&2, F64>, isAnthropicClaudeModel(model), Some{T.modelMaxTokens(model)}, None{})

type Settings<-Reason: Data, -E: Data> is Data:
  Settings{profile: Maybe<&2, String>, region: Maybe<&2, String>, bearer: Maybe<&2, String>, apiKey: Maybe<&2, String>, env: Maybe<&2, T.ProviderEnv()>, retention: Maybe<&2, T.CacheRetention>, maxTokens: Maybe<&2, F64>, temperature: Maybe<&2, F64>, choice: Maybe<&2, BedrockToolChoice>, reasoning: Maybe<&2, T.ThinkingLevel>, budgets: Maybe<&2, T.ThinkingBudgets>, interleaved: Maybe<&2, Bool>, display: Maybe<&2, BedrockThinkingDisplay>, metadata: Maybe<&2, R.Record<String>>, headers: Maybe<&2, T.ProviderHeaders()>, onPayload: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, fetch: Fetch.Fetch(Reason)}

def createState(-G: Data, model: T.Model<J()>, timestamp: F64) -> State<G>: State{createOutput(G, model, timestamp), Nil{}}

def started(~Reason: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +urlContext: URL.Context, settings: Settings<Reason, E>) -> IO(Unit):
  match settings:
    case Settings{profile, +region, bearer, apiKey, +env, retention, maxTokens, temperature, choice, reasoning, budgets, interleaved, display, metadata, headers, onPayload, onResponse, fetch}:
      +collapsed = Transcript.collapseSystemMessages(V.Value, V.Value, G, D, context)
      do IO<Unit>:
        timestamp : F64 <- Date.now()
        config : ClientConfig <- clientConfig(model, urlContext, profile, region, bearer, apiKey, env)
        legacy : Maybe<&2, String> <- envValue("PI_CACHE_RETENTION", env)
        forced : Maybe<&2, String> <- envValue("AWS_BEDROCK_FORCE_CACHE", env)
        regionEnv : Maybe<&2, String> <- envValue("AWS_REGION", env)
        defaultRegion : Maybe<&2, String> <- envValue("AWS_DEFAULT_REGION", env)
        prepared(~Reason, ~E, ~G, ~D, ~render, ~details, events, parent, model, createState(G, model, timestamp), Setup{config, headers, onResponse, fetch, urlContext}, Request{systemText(G, D, contextMessages(G, D, collapsed)), retentionOf(retention, legacy), forcedCache(forced), inferenceMaxTokens(model, maxTokens), temperature, choice, buildAdditionalModelRequestFields(model, reasoning, budgets, interleaved, display, firstOf([region, regionEnv, defaultRegion])), metadata, onPayload}, collapsed)

# Streaming
# ---------

# Responses
# ---------

# Sending
# -------

# Preparing
# ---------

# upstream stream. The caller supplies the default fetch and the request's
# abort signal; events go to `events`, which the terminal event completes.
def stream(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), fetch: Fetch.Fetch(Reason), urlContext: URL.Context, +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Options(Abort.AbortSignal<Reason>, Telemetry, Fetch.Fetch(Reason), E)) -> IO(Unit):
  match options:
    case BedrockOptions{T.StreamOptions{_, _, apiKey, customFetch, env, onPayload, onResponse, headers, _, _, _, temperature, _, maxTokens, _, retention, _, _, _}, region, profile, choice, reasoning, budgets, interleaved, display, metadata, bearer}:
      started(~Reason, ~E, ~G, ~D, ~render, ~details, events, parent, model, context, urlContext, Settings{profile, region, bearer, apiKey, env, retention, maxTokens, temperature, choice, reasoning, budgets, interleaved, display, metadata, headers, onPayload, onResponse, Maybe.default(&2, Fetch.Fetch(Reason), customFetch, fetch)})

def simpleChoice(value: T.ToolChoice) -> BedrockToolChoice:
  match value:
    case T.AutoTool{}: ChoiceAuto{}
    case T.NoTool{}: ChoiceNone{}

def setBudget(budgets: T.ThinkingBudgets, level: Maybe<&2, T.ThinkingLevel>, +value: F64) -> Maybe<&2, T.ThinkingBudgets>:
  match budgets level:
    case T.ThinkingBudgets{a, b, c, d} Some{T.Minimal{}}: Some{T.ThinkingBudgets{Some{value}, b, c, d}}
    case T.ThinkingBudgets{a, b, c, d} Some{T.Low{}}: Some{T.ThinkingBudgets{a, Some{value}, c, d}}
    case T.ThinkingBudgets{a, b, c, d} Some{T.Medium{}}: Some{T.ThinkingBudgets{a, b, Some{value}, d}}
    case T.ThinkingBudgets{a, b, c, d} Some{_}: Some{T.ThinkingBudgets{a, b, c, Some{value}}}
    case other None{}: Some{other}

# `{ ...(thinkingBudgets || {}), [level]: value }`.
def budgetsWith(budgets: Maybe<&2, T.ThinkingBudgets>, level: Maybe<&2, T.ThinkingLevel>, +value: F64) -> Maybe<&2, T.ThinkingBudgets>:
  setBudget(Maybe.default(&2, T.ThinkingBudgets, budgets, T.ThinkingBudgets{None{}, None{}, None{}, None{}}), level, value)

def maxTokensOf(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>) -> Maybe<&2, F64>:
  match base:
    case T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, maxTokens, _, _, _, _, _}: maxTokens

def withMaxTokens(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, value: F64) -> T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>:
  match base:
    case T.StreamOptions{a, b, c, d, e, f, g, h, i, j, k, l, m, _, o, p, q, r, s}: T.StreamOptions{a, b, c, d, e, f, g, h, i, j, k, l, m, Some{value}, o, p, q, r, s}

type SimpleSettings is Data:
  SimpleSettings{toolChoice: Maybe<&2, T.ToolChoice>, reasoning: Maybe<&2, T.ThinkingLevel>, thinkingBudgets: Maybe<&2, T.ThinkingBudgets>}

def simpleSettings(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> SimpleSettings:
  match options:
    case None{}: SimpleSettings{None{}, None{}, None{}}
    case Some{T.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, choice, reasoning, _, budgets}}: SimpleSettings{choice, reasoning, budgets}

def reasoned(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, choice: Maybe<&2, T.ToolChoice>, reasoning: Maybe<&2, T.ThinkingLevel>, budgets: Maybe<&2, T.ThinkingBudgets>) -> Options(Signal, Telemetry, Fetch, Error):
  BedrockOptions{base, None{}, None{}, Maybe.map(&2, T.ToolChoice, BedrockToolChoice, simpleChoice, choice), reasoning, budgets, None{}, None{}, None{}, None{}}

def budgetedWith(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, choice: Maybe<&2, T.ToolChoice>, +level: T.ThinkingLevel, +budgets: Maybe<&2, T.ThinkingBudgets>, allocation: Simple.ThinkingTokenAllocation) -> Options(Signal, Telemetry, Fetch, Error):
  match allocation:
    case Simple.ThinkingTokenAllocation{adjusted, thinkingBudget}:
      +maxTokens = Simple.clampMaxTokensToContext(~G, ~D, ~J(), model, context, adjusted)
      reasoned(Signal, Telemetry, Fetch, Error, withMaxTokens(Signal, Telemetry, Fetch, Error, base, maxTokens), choice, Some{level}, budgetsWith(budgets, Simple.clampReasoning(Some{level}), F.minimum(thinkingBudget, F.maximum(zero(), F.subtract(maxTokens, F.fromU32(1024))))))

# Budget-based Claude: the output cap grows by the thinking budget, both
# clamped to the context window.
def budgeted(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, choice: Maybe<&2, T.ToolChoice>, +level: T.ThinkingLevel, +budgets: Maybe<&2, T.ThinkingBudgets>) -> Options(Signal, Telemetry, Fetch, Error):
  budgetedWith(~G, ~D, ~Signal, ~Telemetry, ~Fetch, ~Error, model, context, base, choice, level, budgets, Simple.adjustMaxTokensForThinking(maxTokensOf(Signal, Telemetry, Fetch, Error, base), T.modelMaxTokens(model), level, budgets))

def simpleWith(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, settings: SimpleSettings) -> Options(Signal, Telemetry, Fetch, Error):
  match settings:
    case SimpleSettings{+choice, None{}, _}: reasoned(Signal, Telemetry, Fetch, Error, base, choice, None{}, None{})
    case SimpleSettings{+choice, Some{+level}, +budgets}: Bool.pick(Options(Signal, Telemetry, Fetch, Error), isAnthropicClaudeModel(model) && Bool.not(supportsAdaptiveThinking(model)), budgeted(~G, ~D, ~Signal, ~Telemetry, ~Fetch, ~Error, model, context, base, choice, level, budgets), reasoned(Signal, Telemetry, Fetch, Error, base, choice, Some{level}, budgets))

# upstream streamSimple's options.
def streamSimpleOptions(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> Options(Signal, Telemetry, Fetch, Error):
  simpleWith(~G, ~D, ~Signal, ~Telemetry, ~Fetch, ~Error, model, context, Simple.buildBaseOptions(~G, ~D, ~J(), ~Signal, ~Telemetry, ~Fetch, ~Error, model, context, options, None{}), simpleSettings(Signal, Telemetry, Fetch, Error, options))

# upstream streamSimple.
def streamSimple(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, ~details: J() -> G, +events: EventStreamOut(G), fetch: Fetch.Fetch(Reason), urlContext: URL.Context, +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Maybe<&2, T.SimpleStreamOptions<J(), Abort.AbortSignal<Reason>, Telemetry, Fetch.Fetch(Reason), E>>) -> IO(Unit):
  stream(~Reason, ~Telemetry, ~E, ~G, ~D, ~render, ~details, events, fetch, urlContext, parent, model, context, streamSimpleOptions(~G, ~D, ~Abort.AbortSignal<Reason>, ~Telemetry, ~Fetch.Fetch(Reason), ~E, model, context, options))
