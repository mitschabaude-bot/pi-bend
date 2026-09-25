import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/models.bend as AiModels
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/auth/resolve.bend as Resolve
import ../packages/ai/src/auth/context.bend as Context
import ../packages/ai/src/api/openai-client.bend as Client
import ../packages/ai/src/api/openai-responses.bend as Responses
import ../packages/ai/src/providers/cloudflare-ai-gateway.bend as Gateway
import ../packages/ai/src/providers/cloudflare-workers-ai.bend as Workers
import ../packages/ai/src/utils/transcript.bend as Transcript
import ../packages/agent/src/types.bend as Agent
import ../packages/agent/src/providers.bend as Providers
import ../packages/coding-agent/src/core/auth-storage.bend as AuthStorage
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/coding-agent/src/core/anthropic-provider.bend as Anthropic
import ../packages/coding-agent/src/core/openai-completions-provider.bend as Completions
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/connection-driver.bend as Connect
import ../packages/runtime/src/dns-resolver.bend as DNS
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/http-exchange.bend as HTTP
import ../packages/runtime/src/http-message.bend as Message
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/url.bend as URL

# The Cloudflare request path against upstream ModelRuntime streaming
# (tests/cloudflare_request_check.py). Each case stores a credential in
# memory, builds a model runtime over the two Cloudflare providers with the
# process environment as ambient auth context, resolves the model's auth,
# lets the provider's streams materialize the endpoint for the resolved env
# and streams through the model api's provider with a capturing fetch, as
# agent-runtime's openProvider does. Prints the captured URL and headers.
# Arguments: <provider> <model id> <credential: full | key | none>.

def Options() -> Data: Ai.SimpleStreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Tools.ToolError>
def Captured() -> Data: Maybe<&2, String>

def urls() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def config(agent: String) -> Responses.Config:
  Responses.Config{urls(), Client.Defaults{agent, R.new(String), None{}, None{}}, Fetch.Files{"/etc/resolv.conf", "/etc/hosts", 4096, 1048576n, 5000, 65535}, HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Message.Limits{8192n, 8192n, 65536n, 100n}}}, HTTP.NoTLS{}, 65536n, False{}}

def headerLines(entries: List<&2, Message.Header>) -> String:
  match entries:
    case Nil{}: ""
    case Message.Header{name, value} <> rest: "header " ++ String.to_lower(name) ++ ": " ++ value ++ "\n" ++ headerLines(rest)

def bodyLine(body: Message.Input) -> String:
  match body:
    case Message.Text{text}: "body " ++ text ++ "\n"
    case _: "body -\n"

def capture(slot: Ref.Ref<Captured()>, input: Fetch.Input<Unit>) -> IO(Fetch.Result_(Unit)):
  match input:
    case Fetch.Input{url, _, headers, body, _}:
      do IO<Fetch.Result_(Unit)>:
        Ref.write(Captured(), slot, Some{"url " ++ URL.serialize(url, False{}) ++ "\n" ++ headerLines(Message.entries(headers)) ++ bodyLine(body)})
        return Fail{Fetch.Rejected{Message.TLSRequired{}}}

def credentialOf(+provider: String, mode: String) -> R.Record<Auth.Credential>:
  match mode:
    case "full": R.Record{[R.Property{provider, Auth.ApiKeyCredential{Some{"test-token"}, Some{R.Record{[R.Property{"CLOUDFLARE_ACCOUNT_ID", "test-account"}, R.Property{"CLOUDFLARE_GATEWAY_ID", "test-gateway"}]}}}}]}
    case "key": R.Record{[R.Property{provider, Auth.ApiKeyCredential{Some{"test-token"}, None{}}}]}
    case _: R.new(Auth.Credential)

def storeOf(pair: AuthStorage.AuthStorageOwner & AuthStorage.AuthStorage) -> IO(Auth.CredentialStore):
  match pair:
    case (_, storage): AuthStorage.store(storage)

def text(value: String) -> V.Value: V.Text{value}

def object(entries: List<&2, R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{entries}}

def lookup() -> Ai.Tool<V.Value>:
  Ai.Tool{"lookup", "Look up a value", object([R.Property{"type", text("object")}, R.Property{"properties", object([R.Property{"value", object([R.Property{"type", text("string")}])}])}, R.Property{"required", V.ArrayValue{[text("value")]}}]), None{}}

def context() -> Ai.TranscriptContext<V.Value, V.Value, Unit, Tools.ToolDetails>:
  Transcript.normalizeContext(V.Value, V.Value, Unit, Tools.ToolDetails, Ai.Context{None{}, Ai.User{Ai.UserMessage{Ai.UserText{"hi"}, F.fromU32(1)}} <> Nil{}, Some{[lookup()]}})

# agent-runtime preparedOptions without other request-level values: the
# resolved key, headers and env, a session id, the capturing fetch and no
# retries.
def options(key: Maybe<&2, String>, headers: Maybe<&2, Ai.ProviderHeaders()>, env: Maybe<&2, Ai.ProviderEnv()>, fetch: Fetch.Fetch(Unit)) -> Options():
  Ai.SimpleStreamOptions{None{}, None{}, key, Some{fetch}, env, None{}, None{}, headers, None{}, Some{F.fromU32(0)}, None{}, None{}, None{}, None{}, None{}, None{}, Some{"session-1"}, None{}, None{}, None{}, None{}, None{}, None{}}

def released(output: Result<&2, &1, Tools.ToolError, Agent.StreamLease<Unit, Tools.ToolError>>) -> IO(Unit):
  match output:
    case Fail{_}: IO.pure(Unit, Unit{})
    case Done{Agent.StreamLease{_, release}}:
      do IO<Unit>:
        result : Result<&2, &2, Tools.ToolError, Unit> <- release
        return Unit{}

def dispatched(+agent: String, fetch: Fetch.Fetch(Unit), model: Ai.Model<Ai.JsonValue>, selected: Options(), api: Ai.ModelApi) -> IO(Unit):
  match api:
    case Ai.AnthropicMessagesApi{}:
      do IO<Unit>:
        output : Result<&2, &1, Tools.ToolError, Agent.StreamLease<Unit, Tools.ToolError>> <- Anthropic.open(fetch, urls(), model, context(), Some{selected})
        released(output)
    case Ai.OpenAICompletionsApi{}:
      do IO<Unit>:
        output : Result<&2, &1, Tools.ToolError, Agent.StreamLease<Unit, Tools.ToolError>> <- Completions.open(fetch, urls(), model, context(), Some{selected})
        released(output)
    case _:
      do IO<Unit>:
        owner : Responses.Run<Unit, Unit, Tools.ToolError> <- Providers.streamSimple(~Unit, ~Unit, ~Tools.ToolDetails, ~Tools.ToolError, ~Tools.errorMessage, config(agent), api, model, context(), Some{selected})
        result : Responses.RunResult<Unit, Unit, Tools.ToolError> <- Responses.dispose(Unit, Unit, Tools.ToolError, owner)
        return Unit{}

def apiOf(model: Ai.Model<Ai.JsonValue>) -> Ai.ModelApi:
  match model:
    case Ai.Model{_, _, api, _, _, _, _, _, _, _, _, _, _, _, _, _}: api

def streamed(agent: String, +fetch: Fetch.Fetch(Unit), streams: AiModels.ProviderStreams, model: Ai.Model<Ai.JsonValue>, resolution: Resolve.Resolution()) -> IO(Unit):
  match resolution:
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{key, headers, _}, +env, _}}}:
      +resolved = AiModels.streamModel(Ai.JsonValue, streams, model, env)
      dispatched(agent, fetch, resolved, options(key, headers, env, fetch), apiOf(resolved))
    case Done{None{}}: IO.print("error Provider is not configured")
    case Fail{error}: IO.print("error " ++ Resolve.errorMessage(error))

def found(+runtime: Models.ModelRuntime, +provider: String, agent: String, fetch: Fetch.Fetch(Unit), model: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> IO(Unit):
  match model:
    case None{}: IO.print("error unknown model")
    case Some{+selected}:
      do IO<Unit>:
        resolution : Resolve.Resolution() <- Models.getModelAuth(runtime, selected, Resolve.noOverrides())
        streamed(agent, fetch, Models.getProviderStreams(runtime, provider), selected, resolution)

def printed(value: Captured()) -> IO(Unit):
  match value:
    case None{}: IO.print("error no request")
    case Some{text}: IO.print(text ++ "end")

def run(+provider: String, +modelId: String, mode: String) -> IO(Unit):
  do IO<Unit>:
    owner : AuthStorage.AuthStorageOwner <- AuthStorage.inMemory(credentialOf(provider, mode))
    store : Auth.CredentialStore <- storeOf(AuthStorage.borrow(owner))
    gateway : AiModels.Provider <- Gateway.cloudflareAIGatewayProvider()
    workers : AiModels.Provider <- Workers.cloudflareWorkersAIProvider()
    ambient : Auth.AuthContext <- Context.defaultProviderAuthContext()
    +runtime : Models.ModelRuntime <- Models.fromProviders([gateway, workers], store, ambient)
    +slot : Ref.Ref<Captured()> <- Ref.new(Captured(), None{})
    +fetch : Fetch.Fetch(Unit) <- C.create(~Ref.Ref<Captured()>, ~Fetch.Input<Unit>, ~Fetch.Result_(Unit), ~capture, slot)
    found(runtime, provider, "pi-test", fetch, Models.getModel(runtime, provider, modelId))
    C.dispose(Fetch.Input<Unit>, Fetch.Result_(Unit), fetch)
    captured : Captured() <- Ref.dispose(Captured(), slot)
    Models.dispose(runtime)
    printed(captured)

def cases(args: List<String>) -> IO(Unit):
  match args:
    case provider <> modelId <> mode <> Nil{}: run(provider, modelId, mode)
    case _: IO.print("usage: <provider> <model id> <full|key|none>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
