import Base
import ../src/types.bend as T
import ../src/api/openai-client.bend as Client
import ../src/api/openai-responses.bend as Responses
import ../src/api/openai-codex-responses.bend as CodexApi
import ../src/providers/openai-codex.models.bend as Codex
import ../src/utils/transcript.bend as Transcript
import ../../runtime/src/callback.bend as C
import ../../runtime/src/connection-driver.bend as Connect
import ../../runtime/src/dns-resolver.bend as DNS
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/http-exchange.bend as HTTP
import ../../runtime/src/http-message.bend as Headers
import ../../runtime/src/http-response.bend as Response
import ../../runtime/src/idna.bend as Domain
import ../../runtime/src/idna.bend as Label
import ../../runtime/src/idna.bend as Mapping
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/unicode-17-idna-mapping.bend as MappingData
import ../../runtime/src/unicode-17-idna-properties.bend as PropertiesData
import ../../runtime/src/unicode-17-normalization.bend as NormalizationData
import ../../runtime/src/url.bend as URL

# upstream max-thinking.test.ts "sends max to the Codex Responses API for %s"
# on the catalog models. As upstream, onPayload captures the request body by
# failing; the settled run returns it as its failure cause. No transport is
# opened. The other max-thinking cases are in model-thinking.bend and
# tests/model_catalog.test.ts.

# streamSimple failed before a stream existed: the case expected a stream.
def startedRun(-Reason: Data, -G: Data, -E: Data, result: Responses.SimpleRun(Reason, G, E)) -> IO(Responses.Run<Reason, G, E>):
  match result:
    case Done{owner}: IO.pure(Responses.Run<Reason, G, E>, owner)
    case Fail{_}: IO.die(Responses.Run<Reason, G, E>, 1, "streamSimple failed before a stream existed")

def Hook() -> Data: T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, T.JsonValue)
def Run() -> Type: Responses.Run<Unit, Unit, T.JsonValue>

# mockToken(): a JWT whose payload carries the ChatGPT account id.
def mockToken() -> String:
  "aaa.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL2F1dGgiOnsiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjX3Rlc3QifX0=.bbb"

def context() -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>:
  Transcript.normalizeContext(V.Value, V.Value, Unit, Unit, T.Context{Some{"You are a helpful assistant."}, T.User{T.UserMessage{T.UserText{"Hello"}, F.fromU32(1)}} <> Nil{}, None{}})

def config() -> Responses.Config:
  Responses.Config{URL.Context{Label.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()}, Domain.Options{Label.LabelOptions{False{}, False{}, True{}, Mapping.Nontransitional{}}, True{}, False{}}}, Client.Defaults{"pi-bend-test", R.new(String), None{}, None{}}, Fetch.Files{"/etc/resolv.conf", "/etc/hosts", 4096, 1048576n, 5000, 65535}, HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Headers.Limits{8192n, 8192n, 65536n, 100n}}}, HTTP.NoTLS{}, 65536n, False{}}

def rendered(payload: T.JsonValue) -> String: "payload captured"

def capture(unused: Unit, input: T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>) -> IO(Result<&2, &2, T.JsonValue, Maybe<&2, T.JsonValue>>):
  match input:
    case T.PayloadInput{payload, _}: IO.pure(Result<&2, &2, T.JsonValue, Maybe<&2, T.JsonValue>>, Fail{payload})

def captured(result: Responses.RunResult<Unit, Unit, T.JsonValue>) -> Maybe<&2, R.Record<T.JsonValue>>:
  match result:
    case Responses.RunResult{Responses.Failed{_, _, Responses.HookFailure{T.JsonObject{fields}}}, _}: Some{fields}
    case _: None{}

def text(value: Maybe<&2, T.JsonValue>) -> String:
  match value:
    case Some{T.JsonString{found}}: found
    case _: "(missing)"

# expect(payload).toMatchObject({ reasoning: { effort: "max", summary: "auto" } })
def reasoningMatches(value: Maybe<&2, T.JsonValue>) -> Bool:
  match value:
    case Some{T.JsonObject{+fields}}: String.eq(text(R.get(T.JsonValue, fields, "effort")), "max") && String.eq(text(R.get(T.JsonValue, fields, "summary")), "auto")
    case _: False{}

def verdict(+name: String, payload: Maybe<&2, R.Record<T.JsonValue>>) -> IO(Unit):
  match payload:
    case None{}: IO.die(Unit, 1, "FAIL " ++ name ++ ": payload not captured")
    case Some{fields}: Bool.pick(IO(Unit), reasoningMatches(R.get(T.JsonValue, fields, "reasoning")), IO.print("PASS " ++ name), IO.die(Unit, 1, "FAIL " ++ name ++ ": reasoning is not {effort: max, summary: auto}"))

def simpleOptions(hook: Hook()) -> Responses.SimpleStreamOptions(Unit, Unit, T.JsonValue):
  T.SimpleStreamOptions{None{}, None{}, Some{mockToken()}, None{}, None{}, Some{hook}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{T.Max{}}, None{}, None{}}

def sendsMax(+model: T.Model<T.JsonValue>) -> IO(Unit):
  do IO<Unit>:
    +hook : Hook() <- C.create(~Unit, ~T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, ~Result<&2, &2, T.JsonValue, Maybe<&2, T.JsonValue>>, ~capture, Unit{})
    started : Responses.SimpleRun(Unit, Unit, T.JsonValue) <- CodexApi.streamSimple(~Unit, ~Unit, ~Unit, ~Unit, ~T.JsonValue, ~rendered, config(), model, context(), Some{simpleOptions(hook)})
    owner : Run() <- startedRun(Unit, Unit, T.JsonValue, started)
    result : Responses.RunResult<Unit, Unit, T.JsonValue> <- Responses.dispose(Unit, Unit, T.JsonValue, owner)
    C.dispose(T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, Result<&2, &2, T.JsonValue, Maybe<&2, T.JsonValue>>, hook)
    verdict("sends max to the Codex Responses API for " ++ T.modelId(model), captured(result))

def main() -> IO(Unit):
  do IO<Unit>:
    sendsMax(Codex.model_gpt_5_6_sol())
    sendsMax(Codex.model_gpt_6_astra())
    sendsMax(Codex.model_gpt_6_sol())
    sendsMax(Codex.model_gpt_6_luna())
