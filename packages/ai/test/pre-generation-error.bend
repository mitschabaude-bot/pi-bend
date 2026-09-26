import Base
import ../src/types.bend as T
import ../src/api/anthropic-messages.bend as Anthropic
import ../src/api/google-generative-ai.bend as Google
import ../src/api/mistral-conversations.bend as Mistral
import ../src/utils/transcript.bend as Transcript
import ../../runtime/src/f64.bend as F
import ../../runtime/src/schema-value.bend as V

# pi-mono f07218c4d packages/ai/test/pre-generation-error.test.ts for the
# APIs whose streamSimple fails before a stream exists (upstream throws
# synchronously): the options mapping returns the error, and the agent glue
# returns it without opening a stream. Azure OpenAI Responses, OpenAI Codex
# Responses, OpenAI Completions and OpenAI Responses still report a missing
# key as a stream error; those expectations stay pending.
def model(api: T.ModelApi) -> T.Model<T.JsonValue>:
  +zero = F.fromU32(0)
  T.Model{"test-model", "Test", api, "test-provider", "https://example.invalid", False{}, None{}, T.InputText{} <> Nil{}, None{}, T.ModelCost{zero, zero, zero, zero, None{}}, None{}, F.fromU32(1000), F.fromU32(100), None{}, None{}, None{}}

def context() -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>:
  Transcript.normalizeContext(V.Value, V.Value, Unit, Unit, T.Context{None{}, Nil{}, None{}})

def empty() -> Maybe<&2, T.SimpleStreamOptions<T.JsonValue, Unit, Unit, Unit, String>>:
  Some{T.emptySimpleStreamOptions(T.JsonValue, Unit, Unit, Unit, String)}

def thrown(-A: Data, result: Result<&2, &2, String, A>) -> String:
  match result:
    case Fail{message}: message
    case Done{_}: "(no error)"

def expectThrows(+api: String, +message: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(message, "No API key for provider: test-provider"), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "FAIL " ++ api ++ ": " ++ message))

def run() -> IO(Unit):
  do IO<Unit>:
    expectThrows("anthropic-messages", thrown(Anthropic.AnthropicOptions<Unit, Unit, Unit, String, Unit>, Anthropic.streamSimpleOptions(~Unit, ~Unit, ~Unit, ~Unit, ~Unit, ~String, ~Unit, model(T.AnthropicMessagesApi{}), context(), empty())))
    expectThrows("google-generative-ai", thrown(Google.GoogleOptions<Unit, Unit, Unit, String>, Google.streamSimpleOptions(~Unit, ~Unit, ~Unit, ~Unit, ~Unit, ~String, model(T.GoogleGenerativeAiApi{}), context(), empty())))
    expectThrows("mistral-conversations", thrown(Mistral.Options(Unit, Unit, Unit, String), Mistral.streamSimpleOptions(~Unit, ~Unit, ~Unit, ~Unit, ~Unit, ~String, model(T.MistralConversationsApi{}), context(), empty())))
    IO.print("PASS throws synchronously when auth is missing (anthropic-messages, google-generative-ai, mistral-conversations)")

def main() -> IO(Unit): run()
