import Base
import ../src/types.bend as T
import ../src/api/openai-client.bend as Client
import ../src/api/openai-responses.bend as Responses
import ./anthropic-harness.bend as A
import ../../runtime/src/callback.bend as C
import ../../runtime/src/connection-driver.bend as Connect
import ../../runtime/src/dns-resolver.bend as DNS
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/http-exchange.bend as HTTP
import ../../runtime/src/http-message.bend as Headers
import ../../runtime/src/http-response.bend as Response
import ../../runtime/src/idna.bend as IDNA
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/unicode-17-idna-mapping.bend as MappingData
import ../../runtime/src/unicode-17-idna-properties.bend as PropertiesData
import ../../runtime/src/unicode-17-normalization.bend as NormalizationData
import ../../runtime/src/url.bend as URL

# The OpenAI Responses payload as onPayload receives it: the hook captures
# the parameters and fails the request, as the upstream suites do. No
# transport is opened.
def J() -> Data: T.JsonValue

def Hook() -> Data: T.PayloadCallback(J(), T.Model<J()>, J())

def Context() -> Data: T.TranscriptContext<V.Value, V.Value, Unit, Unit>

def config() -> Responses.Config:
  Responses.Config{URL.Context{IDNA.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}, Client.Defaults{"pi-bend-test", R.new(String), None{}, None{}}, Fetch.Files{"/etc/resolv.conf", "/etc/hosts", 4096, 1048576n, 5000, 65535}, HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Headers.Limits{8192n, 8192n, 65536n, 100n}}}, HTTP.NoTLS{}, 65536n, False{}}

def rendered(payload: J()) -> String: "payload captured"

def capture(unused: Unit, input: T.PayloadInput<J(), T.Model<J()>>) -> IO(Result<&2, &2, J(), Maybe<&2, J()>>):
  match input:
    case T.PayloadInput{payload, _}: IO.pure(Result<&2, &2, J(), Maybe<&2, J()>>, Fail{payload})

def captured(result: Responses.RunResult<Unit, Unit, J()>) -> Maybe<&2, J()>:
  match result:
    case Responses.RunResult{Responses.Failed{_, _, Responses.HookFailure{payload}}, _}: Some{payload}
    case _: None{}

def settled(owner: Responses.Run<Unit, Unit, J()>, hook: Hook()) -> IO(Maybe<&2, J()>):
  do IO<Maybe<&2, J()>>:
    result : Responses.RunResult<Unit, Unit, J()> <- Responses.dispose(Unit, Unit, J(), owner)
    C.dispose(T.PayloadInput<J(), T.Model<J()>>, Result<&2, &2, J(), Maybe<&2, J()>>, hook)
    +payload : Maybe<&2, J()> <- IO.pure(Maybe<&2, J()>, captured(result))
    A.check(Maybe.is_some(&2, J(), payload), "payload captured")
    return payload

def newHook() -> IO(Hook()): C.create(~Unit, ~T.PayloadInput<J(), T.Model<J()>>, ~Result<&2, &2, J(), Maybe<&2, J()>>, ~capture, Unit{})

def simpleHooked(options: Responses.SimpleStreamOptions(Unit, Unit, J()), hook: Hook()) -> Responses.SimpleStreamOptions(Unit, Unit, J()):
  match options:
    case T.SimpleStreamOptions{signal, telemetry, key, fetch, env, _, response, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, session, ws, metadata, choice, reasoning, deferred, budgets}:
      T.SimpleStreamOptions{signal, telemetry, key, fetch, env, Some{hook}, response, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, session, ws, metadata, choice, reasoning, deferred, budgets}

def streamHooked(options: Responses.OpenAIResponsesOptions<Unit, Unit, J()>, hook: Hook()) -> Responses.OpenAIResponsesOptions<Unit, Unit, J()>:
  match options:
    case Responses.OpenAIResponsesOptions{signal, telemetry, key, fetch, env, _, response, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, session, ws, metadata, effort, summary, tier, choice}:
      Responses.OpenAIResponsesOptions{signal, telemetry, key, fetch, env, Some{hook}, response, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, session, ws, metadata, effort, summary, tier, choice}

# upstream streamSimple's payload.
def simplePayload(+model: T.Model<J()>, +context: Context(), options: Responses.SimpleStreamOptions(Unit, Unit, J())) -> IO(Maybe<&2, J()>):
  do IO<Maybe<&2, J()>>:
    +hook : Hook() <- newHook()
    owner : Responses.Run<Unit, Unit, J()> <- Responses.streamSimple(~Unit, ~Unit, ~Unit, ~Unit, ~J(), ~rendered, config(), model, context, Some{simpleHooked(options, hook)})
    settled(owner, hook)

# upstream `stream`'s payload.
def streamPayload(+model: T.Model<J()>, context: Context(), options: Responses.OpenAIResponsesOptions<Unit, Unit, J()>) -> IO(Maybe<&2, J()>):
  do IO<Maybe<&2, J()>>:
    +hook : Hook() <- newHook()
    owner : Responses.Run<Unit, Unit, J()> <- Responses.stream(~Unit, ~Unit, ~Unit, ~Unit, ~J(), ~rendered, config(), model, context, streamHooked(options, hook))
    settled(owner, hook)

# Stream options with an API key, cache retention, session id and provider env.
def options(retention: Maybe<&2, T.CacheRetention>, session: Maybe<&2, String>, env: Maybe<&2, T.ProviderEnv()>) -> Responses.OpenAIResponsesOptions<Unit, Unit, J()>:
  Responses.OpenAIResponsesOptions{None{}, None{}, Some{"fake-key"}, None{}, env, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, retention, session, None{}, None{}, None{}, None{}, None{}, None{}}
