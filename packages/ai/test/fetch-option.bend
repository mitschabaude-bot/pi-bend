import Base
import ../src/types.bend as T
import ../src/api/openai-responses.bend as Responses
import ../src/api/azure-openai-responses.bend as Azure
import ../src/api/openai-codex-responses.bend as Codex
import ../src/api/openrouter-images.bend as Images
import ../src/api/openai-client.bend as Client
import ../src/utils/event-stream.bend as Events
import ../src/utils/transcript.bend as Transcript
import ./anthropic-harness.bend as A
import ./anthropic-fetch-option.bend as Anthropic
import ./google-fetch-option.bend as Google
import ./responses-payload.bend as RP
import ./anthropic-messages-client.bend as Network
import ../../coding-agent/src/core/openai-completions-provider.bend as Completions
import ../../coding-agent/src/core/stream-providers.bend as Streams
import ../../coding-agent/src/core/tools/index.bend as Tools
import ../../agent/src/types.bend as Agent
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/http-message.bend as H
import ../../runtime/src/http-response.bend as Response
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V

# fetch-option.test.ts: invoke the production adapters with an injected fetch.
# Native clients have no mutable global fetch. Their explicit default capability
# stands for the ambient fetch; selecting the custom one must leave it untouched.
def Options() -> Data: Streams.Options()
def Message() -> Data: T.AssistantMessage<V.Value, V.Value>
def Event() -> Data: T.AssistantMessageEvent<V.Value, V.Value>

def model(api: T.ModelApi) -> T.Model<T.JsonValue>:
  T.Model{"test-model", "Test Model", api, "test-provider", "https://upstream.test/v1", False{}, None{}, [T.InputText{}], None{}, T.ModelCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}}, None{}, F.fromU32(10000), F.fromU32(1000), None{}, None{}, None{}}

def context() -> Streams.Context():
  Transcript.normalizeContext(V.Value, V.Value, V.Value, Tools.ToolDetails, T.Context{None{}, [T.User{T.UserMessage{T.UserText{"hello"}, F.fromU32(1)}}], None{}})

def options(fetch: Fetch.Fetch(Unit), key: String) -> Options():
  T.SimpleStreamOptions{None{}, None{}, Some{key}, Some{fetch}, None{}, None{}, None{}, None{}, None{}, Some{F.fromU32(0)}, None{}, None{}, None{}, None{}, Some{T.Sse{}}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def rejected(reference: Ref.Ref<Nat>, input: Fetch.Input<Unit>) -> IO(Fetch.Result_(Unit)):
  do IO<Fetch.Result_(Unit)>:
    Ref.modify(Nat, Unit, reference, count => (Nat.add(count, 1n), Unit{}))
    return Done{Response.Response{Response.fromHead(H.ResponseHead{H.StatusLine{1, 1, 401, Nil{}}, [H.Header{"content-type", "application/json"}]}, True{}), Response.Closed{None{}}}}

def forbidden(unused: Unit, input: Fetch.Input<Unit>) -> IO(Fetch.Result_(Unit)):
  IO.die(Fetch.Result_(Unit), 1, "ambient fetch must not be called")

def errorMessage(message: Message()) -> Maybe<&2, String>: T.assistantErrorMessage(V.Value, V.Value, message)

def consumeLease(result: Streams.Output()) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 1, Tools.errorMessage(error))
    case Done{Agent.StreamLease{events, release}}:
      do IO<Unit>:
        message : Message() <- Events.resultValue(Event(), Message(), events)
        finished : Result<&2, &2, Tools.ToolError, Unit> <- release
        return Unit{}

def consumeRun(pair: Responses.Run<Unit, V.Value, Tools.ToolError> & Events.AssistantMessageEventStream(V.Value, V.Value)) -> IO(Unit):
  match pair:
    case (owner, events):
      do IO<Unit>:
        message : Message() <- Events.resultValue(Event(), Message(), events)
        finished : Responses.RunResult<Unit, V.Value, Tools.ToolError> <- Responses.dispose(Unit, V.Value, Tools.ToolError, owner)
        return Unit{}

def responsesDone(result: Responses.SimpleRun(Unit, V.Value, Tools.ToolError)) -> IO(Unit):
  do IO<Unit>:
    owner : Responses.Run<Unit, V.Value, Tools.ToolError> <- RP.startedRun(Unit, V.Value, Tools.ToolError, result)
    consumeRun(Responses.borrow(Unit, V.Value, Tools.ToolError, owner))

def adapters(+ambient: Fetch.Fetch(Unit), +custom: Fetch.Fetch(Unit), +count: Ref.Ref<Nat>) -> IO(Unit):
  do IO<Unit>:
    completions : Streams.Output() <- Completions.open(ambient, Network.urlContext(), model(T.OpenAICompletionsApi{}), context(), Some{options(custom, "test-key")})
    consumeLease(completions)
    responses : Responses.SimpleRun(Unit, V.Value, Tools.ToolError) <- Responses.streamSimple(~Unit, ~Unit, ~V.Value, ~Tools.ToolDetails, ~Tools.ToolError, ~Tools.errorMessage, RP.config(), model(T.OpenAIResponsesApi{}), context(), Some{options(custom, "test-key")})
    responsesDone(responses)
    azure : Responses.SimpleRun(Unit, V.Value, Tools.ToolError) <- Azure.streamSimple(~Unit, ~Unit, ~V.Value, ~Tools.ToolDetails, ~Tools.ToolError, ~Tools.errorMessage, RP.config(), model(T.AzureOpenAIResponsesApi{}), context(), Some{options(custom, "test-key")})
    responsesDone(azure)
    calls : Nat <- Ref.read(Nat, count)
    A.check(Nat.is_eq(calls, 3n), "OpenAI adapters must each call custom fetch once")
    A.pass("passes fetch through streamSimple to OpenAI SDK adapters")

# A synthetic, untrusted JWT carrying the account field used by upstream.
def codexKey() -> String: "header.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL2F1dGgiOnsiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjb3VudCJ9fQ==.signature"

def httpAdapters(+ambient: Fetch.Fetch(Unit), +custom: Fetch.Fetch(Unit), count: Ref.Ref<Nat>) -> IO(Unit):
  do IO<Unit>:
    mistral : Streams.Output() <- Streams.mistral(ambient, Network.urlContext(), model(T.MistralConversationsApi{}), context(), Some{options(custom, "test-key")})
    consumeLease(mistral)
    codex : Responses.SimpleRun(Unit, V.Value, Tools.ToolError) <- Codex.streamSimple(~Unit, ~Unit, ~V.Value, ~Tools.ToolDetails, ~Tools.ToolError, ~Tools.errorMessage, RP.config(), model(T.OpenAICodexResponsesApi{}), context(), Some{options(custom, codexKey())})
    responsesDone(codex)
    messages : Streams.Output() <- Streams.piMessages(ambient, Network.urlContext(), model(T.PiMessagesApi{}), context(), Some{options(custom, "test-key")})
    consumeLease(messages)
    calls : Nat <- Ref.read(Nat, count)
    A.check(Nat.is_eq(calls, 6n), "Mistral/Codex/pi-messages must each call custom fetch once")
    A.pass("uses fetch for Mistral, Codex SSE, and pi-messages HTTP requests")

def vertexRejected(result: Streams.Output()) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 1, Tools.errorMessage(error))
    case Done{Agent.StreamLease{events, release}}:
      do IO<Unit>:
        message : Message() <- Events.resultValue(Event(), Message(), events)
        A.check(A.contains(errorMessage(message), "Custom fetch is not supported by the Google Vertex adapter"), "Vertex custom fetch rejection")
        finished : Result<&2, &2, Tools.ToolError, Unit> <- release
        return Unit{}

def vertex(+ambient: Fetch.Fetch(Unit), +custom: Fetch.Fetch(Unit), +count: Ref.Ref<Nat>) -> IO(Unit):
  do IO<Unit>:
    rejected : Streams.Output() <- Streams.vertex(ambient, Network.urlContext(), model(T.GoogleVertexApi{}), context(), Some{options(custom, "test-key")})
    vertexRejected(rejected)
    calls : Nat <- Ref.read(Nat, count)
    A.check(Nat.is_eq(calls, 6n), "Vertex must reject custom fetch without calling it")
    accepted : Streams.Output() <- Streams.vertex(custom, Network.urlContext(), model(T.GoogleVertexApi{}), context(), Some{options(custom, "test-key")})
    consumeLease(accepted)
    callsAfter : Nat <- Ref.read(Nat, count)
    A.check(Nat.is_eq(callsAfter, 7n), "Vertex must allow its explicit ambient fetch")
    A.pass("Google Vertex rejects custom fetch and accepts its own ambient handle")

def images(+ambient: Fetch.Fetch(Unit), custom: Fetch.Fetch(Unit), count: Ref.Ref<Nat>) -> IO(Unit):
  do IO<Unit>:
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    result : T.AssistantImages <- Images.generateImages(~Unit, ~Unit, ~Tools.ToolError, ~Tools.errorMessage, ambient, Network.urlContext(), Client.Defaults{"pi-bend-test", R.new(String), None{}, None{}}, Abort.signal(Unit, controller), T.ImagesModel{"test-images-model", "Test Images Model", "openrouter-images", "openrouter", "https://upstream.test/v1", None{}, [T.InputText{}], None{}, T.ModelCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}}, None{}, None{}, None{}, [T.InputImage{}]}, T.ImagesContext{[T.TextImageText{T.TextContent{"draw", None{}}}]}, Some{T.ImagesOptions{None{}, None{}, Some{"test-key"}, Some{custom}, None{}, None{}, None{}, None{}, None{}, Some{F.fromU32(0)}, None{}, None{}}})
    Abort.dispose(Unit, controller)
    calls : Nat <- Ref.read(Nat, count)
    A.check(Nat.is_eq(calls, 8n), "image generation must call custom fetch once")
    A.pass("uses fetch for image generation")

def run() -> IO(Unit):
  do IO<Unit>:
    Anthropic.run()
    Google.run()
    +count : Ref.Ref<Nat> <- Ref.new(Nat, 0n)
    +custom : Fetch.Fetch(Unit) <- C.create(~Ref.Ref<Nat>, ~Fetch.Input<Unit>, ~Fetch.Result_(Unit), ~rejected, count)
    +ambient : Fetch.Fetch(Unit) <- C.create(~Unit, ~Fetch.Input<Unit>, ~Fetch.Result_(Unit), ~forbidden, Unit{})
    adapters(ambient, custom, count)
    httpAdapters(ambient, custom, count)
    vertex(ambient, custom, count)
    images(ambient, custom, count)
    C.dispose(Fetch.Input<Unit>, Fetch.Result_(Unit), ambient)
    C.dispose(Fetch.Input<Unit>, Fetch.Result_(Unit), custom)
    retired : Nat <- Ref.dispose(Nat, count)
    return Unit{}

def main() -> IO(Unit): run()
