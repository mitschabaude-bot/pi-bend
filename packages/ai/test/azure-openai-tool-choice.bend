import Base
import ../src/types.bend as T
import ../src/api/azure-openai-responses.bend as Azure
import ../src/api/openai-client.bend as Client
import ../src/api/openai-responses.bend as Responses
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

# upstream azure-openai-tool-choice.test.ts. As upstream, onPayload captures
# the request body by failing: the hook's error is the payload itself, which
# the settled run returns as its failure cause. No transport is opened.

# streamSimple failed before a stream existed: the case expected a stream.
def startedRun(-Reason: Data, -G: Data, -E: Data, result: Responses.SimpleRun(Reason, G, E)) -> IO(Responses.Run<Reason, G, E>):
  match result:
    case Done{owner}: IO.pure(Responses.Run<Reason, G, E>, owner)
    case Fail{_}: IO.die(Responses.Run<Reason, G, E>, 1, "streamSimple failed before a stream existed")

def Hook() -> Data: T.PayloadCallback(T.JsonValue, T.Model<T.JsonValue>, T.JsonValue)
def Run() -> Type: Responses.Run<Unit, Unit, T.JsonValue>

def model() -> T.Model<T.JsonValue>:
  +zero = F.fromU32(0)
  T.Model{"test-deployment", "Test Deployment", T.AzureOpenAIResponsesApi{}, "azure-openai-responses", "http://127.0.0.1:9/openai/v1", False{}, None{}, T.InputText{} <> Nil{}, None{}, T.ModelCost{zero, zero, zero, zero, None{}}, None{}, F.fromU32(10000), F.fromU32(1000), None{}, None{}, None{}}

def readTool() -> T.Tool<V.Value>:
  T.Tool{"read", "Read a file", V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{R.Property{"path", V.ObjectValue{R.Record{R.Property{"type", V.Text{"string"}} <> Nil{}}}} <> Nil{}}}} <> R.Property{"required", V.ArrayValue{V.Text{"path"} <> Nil{}}} <> Nil{}}}, None{}}

def context() -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>:
  Transcript.normalizeContext(V.Value, V.Value, Unit, Unit, T.Context{None{}, T.User{T.UserMessage{T.UserText{"Summarize this"}, F.fromU32(1)}} <> Nil{}, Some{readTool() <> Nil{}}})

def config() -> Responses.Config:
  Responses.Config{URL.Context{Label.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()}, Domain.Options{Label.LabelOptions{False{}, False{}, True{}, Mapping.Nontransitional{}}, True{}, False{}}}, Client.Defaults{"pi-bend-test", R.new(String), None{}, None{}}, Fetch.Files{"/etc/resolv.conf", "/etc/hosts", 4096, 1048576n, 5000, 65535}, HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Headers.Limits{8192n, 8192n, 65536n, 100n}}}, HTTP.NoTLS{}, 65536n, False{}}

def rendered(payload: T.JsonValue) -> String: "payload captured"

def capture(unused: Unit, input: T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>) -> IO(Result<&2, &2, T.JsonValue, Maybe<&2, T.JsonValue>>):
  match input:
    case T.PayloadInput{payload, _}: IO.pure(Result<&2, &2, T.JsonValue, Maybe<&2, T.JsonValue>>, Fail{payload})

def toolChoice(value: Maybe<&2, T.JsonValue>) -> String:
  match value:
    case Some{T.JsonString{text}}: text
    case _: "(missing)"

def toolCount(value: Maybe<&2, T.JsonValue>) -> Nat:
  match value:
    case Some{T.JsonArray{items}}: List.length(&2, T.JsonValue, items)
    case _: 0n

def captured(result: Responses.RunResult<Unit, Unit, T.JsonValue>) -> Maybe<&2, R.Record<T.JsonValue>>:
  match result:
    case Responses.RunResult{Responses.Failed{_, _, Responses.HookFailure{T.JsonObject{fields}}}, _}: Some{fields}
    case _: None{}

def verdict(+name: String, +expected: String, payload: Maybe<&2, R.Record<T.JsonValue>>) -> IO(Unit):
  match payload:
    case None{}: IO.die(Unit, 1, "FAIL " ++ name ++ ": payload not captured")
    case Some{+fields}:
      +choice = toolChoice(R.get(T.JsonValue, fields, "tool_choice"))
      Bool.pick(IO(Unit), String.eq(choice, expected) && Nat.is_eq(toolCount(R.get(T.JsonValue, fields, "tools")), 1n), IO.print("PASS " ++ name), IO.die(Unit, 1, "FAIL " ++ name ++ ": tool_choice " ++ choice))

def checked(name: String, expected: String, owner: Run(), hook: Hook()) -> IO(Unit):
  do IO<Unit>:
    result : Responses.RunResult<Unit, Unit, T.JsonValue> <- Responses.dispose(Unit, Unit, T.JsonValue, owner)
    C.dispose(T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, Result<&2, &2, T.JsonValue, Maybe<&2, T.JsonValue>>, hook)
    verdict(name, expected, captured(result))

def streamOptions(hook: Hook()) -> Azure.AzureOpenAIResponsesOptions<Unit, Unit, T.JsonValue>:
  base = {T.StreamOptions{None{}, None{}, Some{"test-key"}, None{}, None{}, Some{hook}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}} : Responses.StreamOptions(Unit, Unit, T.JsonValue)}
  Azure.AzureOpenAIResponsesOptions{base, None{}, Some{T.JsonString{"required"}}, None{}, None{}, None{}, None{}, None{}}

def simpleOptions(hook: Hook()) -> Responses.SimpleStreamOptions(Unit, Unit, T.JsonValue):
  T.SimpleStreamOptions{None{}, None{}, Some{"test-key"}, None{}, None{}, Some{hook}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{T.NoTool{}}, None{}, None{}, None{}}

def main() -> IO(Unit):
  do IO<Unit>:
    +first : Hook() <- C.create(~Unit, ~T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, ~Result<&2, &2, T.JsonValue, Maybe<&2, T.JsonValue>>, ~capture, Unit{})
    specific : Run() <- Azure.stream(~Unit, ~Unit, ~Unit, ~Unit, ~T.JsonValue, ~rendered, config(), model(), context(), streamOptions(first))
    checked("forwards provider-specific tool choice while preserving tool definitions", "required", specific, first)
    +second : Hook() <- C.create(~Unit, ~T.PayloadInput<T.JsonValue, T.Model<T.JsonValue>>, ~Result<&2, &2, T.JsonValue, Maybe<&2, T.JsonValue>>, ~capture, Unit{})
    started : Responses.SimpleRun(Unit, Unit, T.JsonValue) <- Azure.streamSimple(~Unit, ~Unit, ~Unit, ~Unit, ~T.JsonValue, ~rendered, config(), model(), context(), Some{simpleOptions(second)})
    neutral : Run() <- startedRun(Unit, Unit, T.JsonValue, started)
    checked("forwards provider-neutral tool choice from simple options", "none", neutral, second)
