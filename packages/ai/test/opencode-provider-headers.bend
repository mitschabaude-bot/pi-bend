import Base
import ../src/types.bend as T
import ../src/models.bend as Models
import ../src/auth/types.bend as Auth
import ../src/utils/model-api.bend as Api
import ../src/providers/opencode-headers.bend as OpenCode
import ../src/providers/opencode.bend as Zen
import ../src/providers/opencode-go.bend as Go
import ../../runtime/src/f64.bend as F
import ../../runtime/src/record.bend as R

# pi-mono f07218c4d packages/ai/test/opencode-provider-headers.test.ts.
# Upstream wraps recording ProviderStreams and captures the options each
# method receives. Bend's provider wrapper is Models.OpenCodeStreams, whose
# streamSimple options are Models.streamSimpleOptions; `stream` options go
# through OpenCode.withSessionHeader directly (the agent only dispatches
# streamSimple). The native cases pin which APIs each OpenCode provider wraps
# and that models.json overlays inherit the wrapper.
def Options() -> Data: T.StreamOptions<T.JsonValue, Unit, Unit, Unit, String>
def Simple() -> Data: T.SimpleStreamOptions<T.JsonValue, Unit, Unit, Unit, String>

def model(api: T.ModelApi) -> T.Model<T.JsonValue>:
  T.Model{"test-model", "Test model", api, "opencode", "https://opencode.ai/zen/v1", False{}, None{}, [T.InputText{}], None{}, T.ModelCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}}, None{}, F.fromU32(1000), F.fromU32(100), None{}, None{}, None{}}

def testApi() -> T.ModelApi: T.CustomModelApi{"test-api"}

def openCodeStreams() -> Models.ProviderStreams: Models.OpenCodeStreams{[testApi()]}

def headerRecord(entries: List<&2, R.Property<T.Nullable<String>>>) -> Maybe<&2, T.ProviderHeaders()>: Some{R.Record{entries}}

def present(name: String, value: String) -> R.Property<T.Nullable<String>>: R.Property{name, T.PresentValue{value}}

def streamOptions(headers: Maybe<&2, T.ProviderHeaders()>, session: Maybe<&2, String>, cache: Maybe<&2, T.CacheRetention>) -> Options():
  T.StreamOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}, headers, None{}, None{}, None{}, None{}, None{}, None{}, None{}, cache, session, None{}, None{}}

def simpleOptions(headers: Maybe<&2, T.ProviderHeaders()>, session: Maybe<&2, String>, cache: Maybe<&2, T.CacheRetention>) -> Simple():
  T.SimpleStreamOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}, headers, None{}, None{}, None{}, None{}, None{}, None{}, None{}, cache, session, None{}, None{}, None{}, None{}, None{}, None{}}

def streamHeaders(options: Options()) -> Maybe<&2, T.ProviderHeaders()>:
  match options:
    case T.StreamOptions{_, _, _, _, _, _, _, headers, _, _, _, _, _, _, _, _, _, _, _}: headers

def simpleHeaders(options: Simple()) -> Maybe<&2, T.ProviderHeaders()>:
  match options:
    case T.SimpleStreamOptions{_, _, _, _, _, _, _, headers, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: headers

# The captured headers from `stream` and `streamSimple` for the options.
def viaStream(options: Options()) -> Maybe<&2, T.ProviderHeaders()>:
  streamHeaders(OpenCode.withSessionHeader(T.JsonValue, Unit, Unit, Unit, String, options))

def viaSimple(api: T.ModelApi, options: Simple()) -> Maybe<&2, T.ProviderHeaders()>:
  simpleHeaders(Models.streamSimpleOptions(T.JsonValue, T.JsonValue, Unit, Unit, Unit, String, openCodeStreams(), model(api), options))

def entryText(entries: List<&2, R.Property<T.Nullable<String>>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, T.PresentValue{value}} <> rest: (name ++ "=" ++ value) <> entryText(rest)
    case R.Property{name, T.NullValue{}} <> rest: (name ++ "=null") <> entryText(rest)

def show(headers: Maybe<&2, T.ProviderHeaders()>) -> String:
  match headers:
    case None{}: "undefined"
    case Some{R.Record{entries}}: "{" ++ String.join(entryText(entries), ",") ++ "}"

def report(+name: String, +actual: String, +expected: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(actual, expected), IO.print("PASS " ++ name), IO.die(Unit, 1, "FAIL " ++ name ++ ": " ++ actual ++ " != " ++ expected))

def names(apis: List<&2, T.ModelApi>) -> List<&2, String>:
  match apis:
    case Nil{}: Nil{}
    case api <> rest: Api.name(api) <> names(rest)

def wrappedApis(streams: Models.ProviderStreams) -> String:
  match streams:
    case Models.OpenCodeStreams{apis}: String.join(names(apis), ",")
    case _: "not wrapped"

def wrapped(provider: Models.Provider) -> String:
  match provider:
    case Models.Provider{_, _, _, _, _, streams, _}: wrappedApis(streams)

def inherited(provider: Models.Provider) -> String: wrappedApis(Models.inheritedStreams(Some{provider}))

def main() -> IO(Unit):
  do IO<Unit>:
    report("maps sessionId for stream requests even without cache retention", show(viaStream(streamOptions(None{}, Some{"conversation-1"}, Some{T.CacheNone{}}))), "{x-opencode-session=conversation-1}")
    report("maps sessionId for streamSimple requests even without cache retention", show(viaSimple(testApi(), simpleOptions(None{}, Some{"conversation-1"}, Some{T.CacheNone{}}))), "{x-opencode-session=conversation-1}")
    report("preserves a case-insensitive caller override", show(viaSimple(testApi(), simpleOptions(headerRecord([present("X-OpenCode-Session", "caller-value")]), Some{"generated-value"}, None{}))), "{X-OpenCode-Session=caller-value}")
    report("preserves a case-insensitive caller override", show(viaSimple(testApi(), simpleOptions(headerRecord([R.Property{"X-OpenCode-Session", T.NullValue{}}]), Some{"generated-value"}, None{}))), "{X-OpenCode-Session=null}")
    report("does not fabricate a session header when sessionId is absent", show(viaSimple(testApi(), simpleOptions(headerRecord([present("x-custom", "value")]), None{}, None{}))), "{x-custom=value}")
    report("appends the session header after the caller's headers", show(viaSimple(testApi(), simpleOptions(headerRecord([present("x-custom", "value")]), Some{"s"}, None{}))), "{x-custom=value,x-opencode-session=s}")
    report("an empty sessionId adds no header", show(viaSimple(testApi(), simpleOptions(None{}, Some{""}, None{}))), "undefined")
    report("APIs the provider does not wrap keep their options", show(viaSimple(T.PiMessagesApi{}, simpleOptions(None{}, Some{"s"}, None{}))), "undefined")
    zen : Models.Provider <- Zen.opencodeProvider()
    +go : Models.Provider <- Go.opencodeGoProvider()
    report("OpenCode Zen wraps its four APIs", wrapped(zen), "anthropic-messages,google-generative-ai,openai-completions,openai-responses")
    report("OpenCode Go wraps its three APIs", wrapped(go), "anthropic-messages,openai-completions,openai-responses")
    report("a models.json overlay of OpenCode Go keeps the wrapper for its models' APIs", inherited(go), "anthropic-messages,openai-completions,openai-responses")
