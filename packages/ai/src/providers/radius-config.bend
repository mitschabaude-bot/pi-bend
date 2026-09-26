import Base
import ../types.bend as T
import ../auth/types.bend as Auth
import ../api/provider-fetch.bend as Http
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-message.bend as Headers
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/url.bend as URL

# upstream providers/radius-config.ts: the Radius gateway's model config
# (GET /v1/config), its sanitization, the gateway URL normalization and the
# conversion of gateway models into pi-messages models.
#
# Gateway models carry the members of upstream's RadiusGatewayModel type (id,
# name, reasoning, thinkingLevelMap, input, cost, contextWindow, maxTokens);
# upstream's object spread would also copy undeclared members, which no
# consumer reads.

def DEFAULT_RADIUS_GATEWAY() -> String: "https://radius.pi.dev"

def J() -> Data: T.JsonValue

def Model() -> Data: T.Model<J()>

type RadiusGatewayModel is Data:
  RadiusGatewayModel{id: String, name: String, reasoning: Bool, thinkingLevelMap: Maybe<&2, T.ThinkingLevelMap>, input: List<&2, T.ModelInput>, cost: T.ModelCost, contextWindow: F64, maxTokens: F64}

type RadiusGatewayConfig is Data:
  RadiusGatewayConfig{baseUrl: String, models: List<&2, RadiusGatewayModel>}

# URL normalization
# -----------------

def lowerPrefix(text: String, prefix: String) -> Bool: String.starts_with(String.to_lower(text), prefix)

def trailingSlashes(reversed: String) -> String:
  match reversed:
    case SCon{'/', rest}: trailingSlashes(rest)
    case other: other

# `/^https?:\/\//i` gets no scheme added; trailing slashes are removed.
def normalizeRadiusGatewayUrl(+value: String) -> String:
  +withScheme = Bool.pick(String, lowerPrefix(value, "http://") || lowerPrefix(value, "https://"), value, "https://" ++ value)
  String.reverse(trailingSlashes(String.reverse(withScheme)))

# Sanitization
# ------------

def field(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

def textOf(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{item}}: Some{item}
    case _: None{}

def numberOf(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{item}}: Some{item}
    case _: None{}

def flagOf(value: Maybe<&2, V.Value>) -> Maybe<&2, Bool>:
  match value:
    case Some{V.Boolean{item}}: Some{item}
    case _: None{}

def inputOf(value: V.Value) -> List<&2, T.ModelInput>:
  match value:
    case V.Text{"text"}: [T.InputText{}]
    case V.Text{"image"}: [T.InputImage{}]
    case _: Nil{}

def inputsOf(values: List<&2, V.Value>) -> List<&2, T.ModelInput>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: List.append(&2, T.ModelInput, inputOf(value), inputsOf(rest))

def arrayOf(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, V.Value>>:
  match value:
    case Some{V.ArrayValue{items}}: Some{items}
    case _: None{}

# Cost prices are numbers; an absent price reads as 0 (upstream keeps it
# undefined and computes NaN costs).
def price(value: V.Value, name: String) -> F64: Maybe.default(&2, F64, numberOf(field(value, name)), F.fromU32(0))

def costOf(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ModelCost>:
  match value:
    case Some{V.ObjectValue{+fields}}: Some{T.ModelCost{price(V.ObjectValue{fields}, "input"), price(V.ObjectValue{fields}, "output"), price(V.ObjectValue{fields}, "cacheRead"), price(V.ObjectValue{fields}, "cacheWrite"), None{}}}
    case _: None{}

def levelNamed(+name: String) -> Maybe<&2, T.ModelThinkingLevel>:
  match name:
    case "off": Some{T.Off{}}
    case "minimal": Some{T.Thinking{T.Minimal{}}}
    case "low": Some{T.Thinking{T.Low{}}}
    case "medium": Some{T.Thinking{T.Medium{}}}
    case "high": Some{T.Thinking{T.High{}}}
    case "xhigh": Some{T.Thinking{T.XHigh{}}}
    case "max": Some{T.Thinking{T.Max{}}}
    case _: None{}

def mapping(level: Maybe<&2, T.ModelThinkingLevel>, value: V.Value, rest: List<&2, T.ThinkingLevelMapping>) -> List<&2, T.ThinkingLevelMapping>:
  match level value:
    case Some{selected} V.Text{text}: T.ThinkingLevelMapping{selected, Some{T.PresentValue{text}}} <> rest
    case Some{selected} V.Null{}: T.ThinkingLevelMapping{selected, Some{T.NullValue{}}} <> rest
    case _ _: rest

def mappings(values: List<&2, R.Property<V.Value>>) -> List<&2, T.ThinkingLevelMapping>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: mapping(levelNamed(name), value, mappings(rest))

def levelMapOf(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ThinkingLevelMap>:
  match value:
    case Some{V.ObjectValue{R.Record{values}}}: Some{T.ThinkingLevelMap{mappings(values)}}
    case _: None{}

type Checked is Data:
  Checked{id: Maybe<&2, String>, name: Maybe<&2, String>, reasoning: Maybe<&2, Bool>, input: Maybe<&2, List<&2, V.Value>>, cost: Maybe<&2, T.ModelCost>, window: Maybe<&2, F64>, maximum: Maybe<&2, F64>}

def checkedModel(checked: Checked, levels: Maybe<&2, T.ThinkingLevelMap>) -> Maybe<&2, RadiusGatewayModel>:
  match checked:
    case Checked{Some{id}, Some{name}, Some{reasoning}, Some{input}, Some{cost}, Some{window}, Some{maximum}}: Some{RadiusGatewayModel{id, name, reasoning, levels, inputsOf(input), cost, window, maximum}}
    case _: None{}

# upstream isRadiusGatewayModel.
def gatewayModel(+value: V.Value) -> Maybe<&2, RadiusGatewayModel>:
  checkedModel(Checked{textOf(field(value, "id")), textOf(field(value, "name")), flagOf(field(value, "reasoning")), arrayOf(field(value, "input")), costOf(field(value, "cost")), numberOf(field(value, "contextWindow")), numberOf(field(value, "maxTokens"))}, levelMapOf(field(value, "thinkingLevelMap")))

def prependModel(model: Maybe<&2, RadiusGatewayModel>, rest: List<&2, RadiusGatewayModel>) -> List<&2, RadiusGatewayModel>:
  match model:
    case Some{value}: value <> rest
    case None{}: rest

def gatewayModels(values: List<&2, V.Value>) -> List<&2, RadiusGatewayModel>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: prependModel(gatewayModel(value), gatewayModels(rest))

def configFrom(baseUrl: Maybe<&2, String>, models: Maybe<&2, List<&2, V.Value>>) -> Maybe<&2, RadiusGatewayConfig>:
  match baseUrl models:
    case Some{url} Some{items}: Some{RadiusGatewayConfig{url, gatewayModels(items)}}
    case _ _: None{}

# upstream sanitizeRadiusGatewayConfig: a string baseUrl and a models array,
# keeping only well-formed models.
def sanitizeRadiusGatewayConfig(+config: V.Value) -> Maybe<&2, RadiusGatewayConfig>:
  configFrom(textOf(field(config, "baseUrl")), arrayOf(field(config, "models")))

def gatewayOf(value: Maybe<&2, V.Value>) -> Maybe<&2, RadiusGatewayConfig>:
  match value:
    case Some{config}: sanitizeRadiusGatewayConfig(config)
    case None{}: None{}

# upstream getRadiusCredentialConfig: an OAuth credential's gatewayConfig.
def getRadiusCredentialConfig(credential: Maybe<&2, Auth.Credential>) -> Maybe<&2, RadiusGatewayConfig>:
  match credential:
    case Some{Auth.OAuthCredential{_, _, _, extra}}: gatewayOf(R.get(V.Value, extra, "gatewayConfig"))
    case _: None{}

def toModel(+providerId: String, +baseUrl: String, model: RadiusGatewayModel) -> Model():
  match model:
    case RadiusGatewayModel{id, name, reasoning, levels, input, cost, window, maximum}: T.Model{id, name, T.PiMessagesApi{}, providerId, baseUrl, reasoning, levels, input, None{}, cost, None{}, window, maximum, None{}, None{}, None{}}

def toModels(+providerId: String, +baseUrl: String, models: List<&2, RadiusGatewayModel>) -> List<&2, Model()>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: toModel(providerId, baseUrl, model) <> toModels(providerId, baseUrl, rest)

def getRadiusModelsFromConfig(providerId: String, config: RadiusGatewayConfig) -> List<&2, Model()>:
  match config:
    case RadiusGatewayConfig{baseUrl, models}: toModels(providerId, baseUrl, models)

def modelsOf(providerId: String, config: Maybe<&2, RadiusGatewayConfig>) -> List<&2, Model()>:
  match config:
    case Some{value}: getRadiusModelsFromConfig(providerId, value)
    case None{}: Nil{}

def getRadiusModels(providerId: String, credential: Maybe<&2, Auth.Credential>) -> List<&2, Model()>: modelsOf(providerId, getRadiusCredentialConfig(credential))

# Loading
# -------

def truncateHttpBody(body: String) -> String:
  +trimmed = String.trim(body)
  Bool.pick(String, Nat.is_gt(String.length(trimmed), 512n), String.take(trimmed, 512n) ++ "…", trimmed)

def textOr(text: Result<&2, &2, Response.TextError<Http.ExchangeError(Unit)>, String>) -> String:
  match text:
    case Done{body}: body
    case Fail{_}: ""

def failedStatus(gateway: String, status: U32, text: Result<&2, &2, Response.TextError<Http.ExchangeError(Unit)>, String>) -> Result<&2, &2, String, RadiusGatewayConfig>:
  Fail{"Could not load Radius config from " ++ gateway ++ ": " ++ U32.show(status) ++ ": " ++ truncateHttpBody(textOr(text))}

def sanitized(gateway: String, config: Maybe<&2, RadiusGatewayConfig>) -> Result<&2, &2, String, RadiusGatewayConfig>:
  match config:
    case Some{value}: Done{value}
    case None{}: Fail{"Invalid Radius config from " ++ gateway}

def jsonConfig(gateway: String, value: Result<&2, &2, Decode.ParseError, V.Value>) -> Result<&2, &2, String, RadiusGatewayConfig>:
  match value:
    case Fail{_}: Fail{"Unexpected token in JSON from " ++ gateway}
    case Done{config}: sanitized(gateway, sanitizeRadiusGatewayConfig(config))

def parsedConfig(gateway: String, text: Result<&2, &2, Response.TextError<Http.ExchangeError(Unit)>, String>) -> Result<&2, &2, String, RadiusGatewayConfig>:
  match text:
    case Fail{_}: Fail{"Invalid Radius config from " ++ gateway}
    case Done{+body}: jsonConfig(gateway, Decode.parse(body))

def received(+gateway: String, response: Fetch.Result_(Unit), aborted: Bool) -> IO(Result<&2, &2, String, RadiusGatewayConfig>):
  match response aborted:
    case Fail{_} True{}: IO.pure(Result<&2, &2, String, RadiusGatewayConfig>, Fail{"This operation was aborted"})
    case Fail{_} False{}: IO.pure(Result<&2, &2, String, RadiusGatewayConfig>, Fail{"fetch failed"})
    case Done{Response.Response{+metadata, body}} _:
      do IO<Result<&2, &2, String, RadiusGatewayConfig>>:
        +text : Result<&2, &2, Response.TextError<Http.ExchangeError(Unit)>, String> <- Http.responseText(~Unit, 16777216n, body)
        return Bool.pick(Result<&2, &2, String, RadiusGatewayConfig>, Response.ok(metadata), parsedConfig(gateway, text), failedStatus(gateway, Response.metadataStatus(metadata), text))

def configHeaders(apiKey: Maybe<&2, String>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match apiKey:
    case Some{SCon{c, cs}}: Http.headerList([R.Property{"accept", "application/json"}, R.Property{"authorization", "Bearer " ++ SCon{c, cs}}])
    case _: Http.headerList([R.Property{"accept", "application/json"}])

def exchanged(fetch: Fetch.Fetch(Unit), +parent: Abort.AbortSignal<Unit>, gateway: String, url: URL.URL, headers: Headers.Headers, pair: Deadline.Scope<Unit> & Fetch.Signal(Unit)) -> IO(Result<&2, &2, String, RadiusGatewayConfig>):
  match pair:
    case (scope, signal):
      do IO<Result<&2, &2, String, RadiusGatewayConfig>>:
        response : Fetch.Result_(Unit) <- C.call(Fetch.Input<Unit>, Fetch.Result_(Unit), fetch, Fetch.Input{url, "GET", headers, Headers.Absent{}, signal})
        aborted : Bool <- Abort.aborted(Unit, parent)
        result : Result<&2, &2, String, RadiusGatewayConfig> <- received(gateway, response, aborted)
        closed : Maybe<&2, Abort.AbortReason<Deadline.Cause<Unit>>> <- Deadline.close(Unit, scope)
        return result

def requested(fetch: Fetch.Fetch(Unit), +parent: Abort.AbortSignal<Unit>, gateway: String, url: Result<&2, &2, String, URL.URL>, headers: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>) -> IO(Result<&2, &2, String, RadiusGatewayConfig>):
  match url headers:
    case Fail{message} _: IO.pure(Result<&2, &2, String, RadiusGatewayConfig>, Fail{message})
    case _ Fail{_}: IO.pure(Result<&2, &2, String, RadiusGatewayConfig>, Fail{"Invalid header value"})
    case Done{address} Done{fields}:
      do IO<Result<&2, &2, String, RadiusGatewayConfig>>:
        scope : Deadline.Scope<Unit> <- Deadline.create(Unit, 4294967295, parent)
        exchanged(fetch, parent, gateway, address, fields, Deadline.borrow(Unit, scope))

def relativeResult(value: Result<&2, &2, URL.ResolveError, URL.URL>) -> Result<&2, &2, String, URL.URL>:
  match value:
    case Fail{_}: Fail{"Invalid URL"}
    case Done{url}: Done{url}

def resolvedUrl(base: Result<&2, &2, URL.Error, URL.URL>, context: URL.Context, path: String) -> Result<&2, &2, String, URL.URL>:
  match base:
    case Fail{_}: Fail{"Invalid URL"}
    case Done{parsed}: relativeResult(URL.relative(context, parsed, path))

# `new URL(path, gateway)`.
def gatewayUrl(+context: URL.Context, gateway: String, path: String) -> Result<&2, &2, String, URL.URL>:
  resolvedUrl(URL.parse(context, gateway), context, path)

# upstream loadRadiusGatewayConfig.
def loadRadiusGatewayConfig(fetch: Fetch.Fetch(Unit), urlContext: URL.Context, +gateway: String, apiKey: Maybe<&2, String>, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, RadiusGatewayConfig>):
  requested(fetch, signal, gateway, gatewayUrl(urlContext, gateway, "/v1/config"), configHeaders(apiKey))
