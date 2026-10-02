import Base
import ../packages/ai/src/api/options.bend as Options
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/core/provider-composer.bend as Composer
import ../packages/ai/src/api/openai-codex-sessions.bend as Sessions
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/models.bend as AiModels
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/auth/context.bend as Context
import ../packages/ai/src/api/openai-client.bend as Client
import ../packages/ai/src/api/openai-responses.bend as Responses
import ../packages/ai/src/providers/cloudflare-ai-gateway.bend as Gateway
import ../packages/ai/src/providers/cloudflare-workers-ai.bend as Workers
import ../packages/ai/src/utils/transcript.bend as Transcript
import ../packages/agent/src/types.bend as Agent
import ../packages/coding-agent/src/core/auth-storage.bend as AuthStorage
import ../packages/coding-agent/src/core/model-runtime.bend as Models
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

# Actual ModelRuntime completion and extension-style resolved-auth API requests.
# A capturing fetch records the transport boundary without accessing the network.
# Arguments: <provider> <model id> <full|key|none> [runtime|resolved].

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


def text(value: String) -> V.Value: V.Text{value}

def object(entries: List<&2, R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{entries}}

def lookup() -> Ai.Tool<V.Value>:
  Ai.Tool{"lookup", "Look up a value", object([R.Property{"type", text("object")}, R.Property{"properties", object([R.Property{"value", object([R.Property{"type", text("string")}])}])}, R.Property{"required", V.ArrayValue{[text("value")]}}]), None{}}

def context() -> Ai.TranscriptContext<V.Value, V.Value, V.Value, Tools.ToolDetails>:
  Transcript.normalizeContext(V.Value, V.Value, V.Value, Tools.ToolDetails, Ai.Context{None{}, Ai.User{Ai.UserMessage{Ai.UserText{"hi"}, F.fromU32(1)}} <> Nil{}, Some{[lookup()]}})

# agent-runtime preparedOptions without other request-level values: the
# resolved key, headers and env, a session id, the capturing fetch and no
# retries.
def options(key: Maybe<&2, String>, headers: Maybe<&2, Ai.ProviderHeaders()>, env: Maybe<&2, Ai.ProviderEnv()>, fetch: Fetch.Fetch(Unit)) -> Options():
  Ai.SimpleStreamOptions{None{}, None{}, key, Some{fetch}, env, None{}, None{}, headers, None{}, Some{F.fromU32(0)}, None{}, None{}, None{}, None{}, None{}, None{}, Some{"session-1"}, None{}, None{}, None{}, None{}, None{}, None{}}

def authHeader(value: Ai.Nullable<String>) -> String:
  match value:
    case Ai.NullValue{}: "null"
    case Ai.PresentValue{value}: value

def authLines(entries: List<&2, R.Property<Ai.Nullable<String>>>) -> String:
  match entries:
    case Nil{}: ""
    case R.Property{key, value} <> rest: "authheader " ++ String.to_lower(key) ++ ": " ++ authHeader(value) ++ "\n" ++ authLines(rest)

def resolvedComplete(+runtime: Models.ModelRuntime, stream: Composer.ProviderStream(), fetch: Fetch.Fetch(Unit), +model: Models.Model(), resolution: Models.RequestAuthResult()) -> IO(Unit):
  match resolution:
    case Fail{reason}: IO.print("error " ++ reason)
    case Done{Models.ResolvedRequestAuth{key, +headers, baseUrl, +env}}:
      do IO<Unit>:
        streams : AiModels.ProviderStreams <- Models.getProviderStreams(runtime, Ai.modelProvider(model))
        routed : Models.Model() = AiModels.streamModel(Ai.JsonValue, streams, Models.withAuthBaseUrl(model, baseUrl), env)
        request : Options.RequestOptions<Tools.ToolError> = Options.RawOptions{Options.CommonOptions{Ai.StreamOptions{None{}, None{}, key, Some{fetch}, env, None{}, None{}, headers, None{}, Some{F.fromU32(0)}, None{}, None{}, None{}, None{}, None{}, None{}, Some{"session-1"}, None{}, None{}}}}
        output : Composer.StreamOutput() <- C.call(Composer.StreamRequest(), Composer.StreamOutput(), stream, Agent.StreamInput{routed, context(), Some{request}})
        reply : Ai.AssistantMessage<V.Value, V.Value> <- Models.completed(model, output)
        IO.print(authLines(R.entries(Ai.Nullable<String>, Maybe.default(&2, Ai.ProviderHeaders(), headers, R.new(Ai.Nullable<String>)))))

def completedRequest(+runtime: Models.ModelRuntime, stream: Composer.ProviderStream(), +fetch: Fetch.Fetch(Unit), kind: String, +selected: Models.Model()) -> IO(Unit):
  match kind:
    case "resolved":
      do IO<Unit>:
        auth : Models.RequestAuthResult() <- Models.getApiKeyAndHeaders(runtime, selected)
        resolvedComplete(runtime, stream, fetch, selected, auth)
    case "runtime":
      do IO<Unit>:
        reply : Ai.AssistantMessage<V.Value, V.Value> <- Models.completeSimple(runtime, selected, Ai.Context{None{}, [Ai.User{Ai.UserMessage{Ai.UserText{"hi"}, F.fromU32(1)}}], Some{[lookup()]}}, Some{options(None{}, None{}, None{}, fetch)}, Models.noTransforms())
        return Unit{}
    case _: IO.die(Unit, 2, "unknown Cloudflare request kind")

def found(runtime: Models.ModelRuntime, stream: Composer.ProviderStream(), fetch: Fetch.Fetch(Unit), kind: String, model: Maybe<&2, Models.Model()>) -> IO(Unit):
  match model:
    case None{}: IO.print("error unknown model")
    case Some{selected}: completedRequest(runtime, stream, fetch, kind, selected)

def printed(value: Captured()) -> IO(Unit):
  match value:
    case None{}: IO.print("error no request")
    case Some{text}: IO.print(text ++ "end")

def runOwned(+provider: String, modelId: String, kind: String, pair: AuthStorage.AuthStorageOwner & AuthStorage.AuthStorage) -> IO(Unit):
  match pair:
    case Tuple{owner, storage}:
      do IO<Unit>:
        +store : Auth.CredentialStore <- AuthStorage.store(storage)
        gateway : AiModels.Provider <- Gateway.cloudflareAIGatewayProvider()
        workers : AiModels.Provider <- Workers.cloudflareWorkersAIProvider()
        ambient : Auth.AuthContext <- Context.defaultProviderAuthContext()
        +runtime : Models.ModelRuntime <- Models.fromProviders([gateway, workers], store, ambient)
        +slot : Ref.Ref<Captured()> <- Ref.new(Captured(), None{})
        +fetch : Fetch.Fetch(Unit) <- C.create(~Ref.Ref<Captured()>, ~Fetch.Input<Unit>, ~Fetch.Result_(Unit), ~capture, slot)
        +sessions : Sessions.Pool<Unit> <- Sessions.create(Unit, Sessions.defaults())
        +calls : Ref.Ref<Nat> <- Ref.new(Nat, 0n)
        +api : Composer.ProviderStream() <- C.create(~Runtime.ApiTransport, ~Composer.StreamRequest(), ~Composer.StreamOutput(), ~Runtime.openApi, Runtime.ApiTransport{config("pi-test"), fetch, calls, sessions})
        Models.setApiStreams(runtime, Some{api})
        model : Maybe<&2, Ai.Model<Ai.JsonValue>> <- Models.getModel(runtime, provider, modelId)
        found(runtime, api, fetch, kind, model)
        Models.dispose(runtime)
        Sessions.dispose(Unit, sessions)
        count : Nat <- Ref.dispose(Nat, calls)
        C.dispose(Fetch.Input<Unit>, Fetch.Result_(Unit), fetch)
        captured : Captured() <- Ref.dispose(Captured(), slot)
        Auth.disposeStore(store)
        AuthStorage.dispose(owner)
        printed(captured)

def run(+provider: String, modelId: String, mode: String, kind: String) -> IO(Unit):
  do IO<Unit>:
    owner : AuthStorage.AuthStorageOwner <- AuthStorage.inMemory(credentialOf(provider, mode))
    runOwned(provider, modelId, kind, AuthStorage.borrow(owner))

def cases(args: List<String>) -> IO(Unit):
  match args:
    case provider <> modelId <> mode <> Nil{}: run(provider, modelId, mode, "runtime")
    case provider <> modelId <> mode <> kind <> Nil{}: run(provider, modelId, mode, kind)
    case _: IO.print("usage: <provider> <model id> <full|key|none>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
