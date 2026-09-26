import Base
import ../src/types.bend as T
import ../src/api/anthropic-messages.bend as Anthropic
import ../src/api/google-generative-ai.bend as Google
import ../src/api/mistral-conversations.bend as Mistral
import ../src/api/openai-completions.bend as Completions
import ../src/api/openai-responses.bend as Responses
import ../src/api/azure-openai-responses.bend as Azure
import ./responses-payload.bend as RP
import ../src/utils/transcript.bend as Transcript
import ../../runtime/src/f64.bend as F
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/schema-value.bend as V

# pi-mono f07218c4d packages/ai/test/pre-generation-error.test.ts. Upstream's
# streamSimple throws synchronously when auth is missing; here it returns the
# error before a stream exists (the options mapping for Anthropic, Google,
# Mistral and Chat Completions; streamSimple's Result for the Responses
# family), and the agent glue returns that failure without opening a stream.
def model(api: T.ModelApi) -> T.Model<T.JsonValue>:
  +zero = F.fromU32(0)
  T.Model{"test-model", "Test", api, "test-provider", "https://example.invalid", False{}, None{}, T.InputText{} <> Nil{}, None{}, T.ModelCost{zero, zero, zero, zero, None{}}, None{}, F.fromU32(1000), F.fromU32(100), None{}, None{}, None{}}

def context() -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>:
  Transcript.normalizeContext(V.Value, V.Value, Unit, Unit, T.Context{None{}, Nil{}, None{}})

def empty(-Signal: Data, -Fetch: Data) -> Maybe<&2, T.SimpleStreamOptions<T.JsonValue, Signal, Unit, Fetch, String>>:
  Some{T.emptySimpleStreamOptions(T.JsonValue, Signal, Unit, Fetch, String)}

def thrown(-A: Data, result: Result<&2, &2, String, A>) -> String:
  match result:
    case Fail{message}: message
    case Done{_}: "(no error)"

def responsesThrown(result: Responses.SimpleRun(Unit, Unit, String)) -> IO(String):
  match result:
    case Fail{cause}: IO.pure(String, Responses.describePreparation(cause))
    case Done{owner}:
      do IO<String>:
        settled : Responses.RunResult<Unit, Unit, String> <- Responses.dispose(Unit, Unit, String, owner)
        return "(no error)"

def rendered(error: String) -> String: error

def responsesMissing(api: T.ModelApi) -> IO(String):
  do IO<String>:
    result : Responses.SimpleRun(Unit, Unit, String) <- Responses.streamSimple(~Unit, ~Unit, ~Unit, ~Unit, ~String, ~rendered, RP.config(), model(api), context(), empty(Abort.AbortSignal<Unit>, Fetch.Fetch(Unit)))
    responsesThrown(result)

def azureMissing() -> IO(String):
  do IO<String>:
    result : Responses.SimpleRun(Unit, Unit, String) <- Azure.streamSimple(~Unit, ~Unit, ~Unit, ~Unit, ~String, ~rendered, RP.config(), model(T.AzureOpenAIResponsesApi{}), context(), empty(Abort.AbortSignal<Unit>, Fetch.Fetch(Unit)))
    responsesThrown(result)

def expectThrows(+api: String, +message: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(message, "No API key for provider: test-provider"), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "FAIL " ++ api ++ ": " ++ message))

def run() -> IO(Unit):
  do IO<Unit>:
    expectThrows("anthropic-messages", thrown(Anthropic.AnthropicOptions<Unit, Unit, Unit, String, Unit>, Anthropic.streamSimpleOptions(~Unit, ~Unit, ~Unit, ~Unit, ~Unit, ~String, ~Unit, model(T.AnthropicMessagesApi{}), context(), empty(Unit, Unit))))
    expectThrows("google-generative-ai", thrown(Google.GoogleOptions<Unit, Unit, Unit, String>, Google.streamSimpleOptions(~Unit, ~Unit, ~Unit, ~Unit, ~Unit, ~String, model(T.GoogleGenerativeAiApi{}), context(), empty(Unit, Unit))))
    expectThrows("mistral-conversations", thrown(Mistral.Options(Unit, Unit, Unit, String), Mistral.streamSimpleOptions(~Unit, ~Unit, ~Unit, ~Unit, ~Unit, ~String, model(T.MistralConversationsApi{}), context(), empty(Unit, Unit))))
    expectThrows("openai-completions", thrown(Completions.Options(Unit, Unit, Unit, String), Completions.streamSimpleOptions(~Unit, ~Unit, ~Unit, ~Unit, ~Unit, ~String, model(T.OpenAICompletionsApi{}), context(), empty(Unit, Unit))))
    azure : String <- azureMissing()
    expectThrows("azure-openai-responses", azure)
    codex : String <- responsesMissing(T.OpenAICodexResponsesApi{})
    expectThrows("openai-codex-responses", codex)
    responses : String <- responsesMissing(T.OpenAIResponsesApi{})
    expectThrows("openai-responses", responses)
    IO.print("PASS throws synchronously when auth is missing")

def main() -> IO(Unit): run()
