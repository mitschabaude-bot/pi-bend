import Base
import ../src/types.bend as T
import ../src/auth/types.bend as Auth
import ../src/providers/cloudflare-auth.bend as Cloudflare
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/record.bend as R

# The two Cloudflare cases of upstream providers.test.ts ("builtin providers")
# and native cases for cloudflare-auth.ts's per-field merge, source label and
# abort checks. Upstream resolves through createModels().getAuth with a fake
# auth context; the Bend cases call the provider's ApiKeyAuth.resolve with the
# same context, which is what getAuth does without a stored credential.
# Results render as `key|headers|env|source` (`-` for absent).

def Env() -> Data: R.Record<String>

def lookup(env: Env(), name: String) -> IO(Maybe<&2, String>):
  IO.pure(Maybe<&2, String>, R.get(String, env, name))

def unused(env: Env(), path: String) -> IO(Bool): IO.pure(Bool, False{})

def fakeAuthContext(env: Env()) -> IO(Auth.AuthContext):
  do IO<Auth.AuthContext>:
    +values : Env() <- IO.pure(Env(), env)
    environment : C.Callback<String, Maybe<&2, String>> <- C.create(~Env(), ~String, ~Maybe<&2, String>, ~lookup, values)
    exists : C.Callback<String, Bool> <- C.create(~Env(), ~String, ~Bool, ~unused, values)
    return Auth.AuthContext{environment, exists}

def vars(entries: List<&2, R.Property<String>>) -> Env(): R.Record{entries}

def optional(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "-"
    case Some{text}: text

def headerValue(value: T.Nullable<String>) -> String:
  match value:
    case T.NullValue{}: "null"
    case T.PresentValue{text}: text

def headerList(entries: List<&2, R.Property<T.Nullable<String>>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: (name ++ ":" ++ headerValue(value)) <> headerList(rest)

def envList(entries: List<&2, R.Property<String>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: (name ++ "=" ++ value) <> envList(rest)

def headersText(headers: Maybe<&2, T.ProviderHeaders()>) -> String:
  match headers:
    case None{}: "-"
    case Some{R.Record{entries}}: String.join(headerList(entries), ",")

def envText(env: Maybe<&2, T.ProviderEnv()>) -> String:
  match env:
    case None{}: "-"
    case Some{R.Record{entries}}: String.join(envList(entries), ",")

def rendered(outcome: Auth.AuthOutcome()) -> String:
  match outcome:
    case Fail{message}: "error:" ++ message
    case Done{None{}}: "undefined"
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{key, headers, _}, env, source}}}:
      optional(key) ++ "|" ++ headersText(headers) ++ "|" ++ envText(env) ++ "|" ++ optional(source)

def resolveWith(auth: Auth.ApiKeyAuth, context: Auth.AuthContext, credential: Maybe<&2, Auth.Credential>, signal: Abort.AbortSignal<Unit>) -> IO(Auth.AuthOutcome()):
  match auth:
    case Auth.ApiKeyAuth{_, _, resolve}: C.call(Auth.ResolveInput, Auth.AuthOutcome(), resolve, Auth.ResolveInput{context, credential, signal})

def resolvedText(auth: IO(Auth.ApiKeyAuth), env: Env(), credential: Maybe<&2, Auth.Credential>, cancel: Bool) -> IO(String):
  do IO<String>:
    selected : Auth.ApiKeyAuth <- auth
    context : Auth.AuthContext <- fakeAuthContext(env)
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    won : Bool <- Bool.pick(IO(Bool), cancel, Abort.abort(Unit, controller, None{}), IO.pure(Bool, False{}))
    outcome : Auth.AuthOutcome() <- resolveWith(selected, context, credential, Abort.signal(Unit, controller))
    Abort.dispose(Unit, controller)
    return rendered(outcome)

def expect(+name: String, actual: IO(String), +expected: String) -> IO(Unit):
  do IO<Unit>:
    +value : String <- actual
    Bool.pick(IO(Unit), String.eq(value, expected), IO.print("PASS " ++ name), IO.die(Unit, 1, "FAIL " ++ name ++ ": " ++ value ++ " != " ++ expected))

def keyVar() -> R.Property<String>: R.Property{"CLOUDFLARE_API_KEY", "cf-key"}
def accountVar() -> R.Property<String>: R.Property{"CLOUDFLARE_ACCOUNT_ID", "account-id"}
def gatewayVar() -> R.Property<String>: R.Property{"CLOUDFLARE_GATEWAY_ID", "gateway-id"}

def storedCredential(value: Maybe<&2, String>, env: List<&2, R.Property<String>>) -> Maybe<&2, Auth.Credential>:
  Some{Auth.ApiKeyCredential{value, Some{R.Record{env}}}}

def workers() -> IO(Auth.ApiKeyAuth): Cloudflare.cloudflareWorkersAIAuth()
def gatewayAuth() -> IO(Auth.ApiKeyAuth): Cloudflare.cloudflareAIGatewayAuth()

def promptAnswer(_: Unit,prompt: Auth.AuthPrompt) -> IO(Result<&2,&2,String,String>):
  match prompt:
    case Auth.SecretPrompt{"Enter Cloudflare API key",_,_}: IO.pure(Result<&2,&2,String,String>,Done{"cf-key"})
    case Auth.TextPrompt{"Enter Cloudflare account ID",_,_}: IO.pure(Result<&2,&2,String,String>,Done{"account-id"})
    case Auth.TextPrompt{"Enter Cloudflare AI Gateway ID",_,_}: IO.pure(Result<&2,&2,String,String>,Done{"gateway-id"})
    case _: IO.pure(Result<&2,&2,String,String>,Fail{"unexpected prompt"})
def credentialText(result: Auth.LoginOutcome()) -> String:
  match result:
    case Fail{reason}: "error:" ++ reason
    case Done{Auth.ApiKeyCredential{key,env}}: optional(key) ++ "|" ++ envText(env)
    case Done{_}: "wrong credential type"
def callLogin(auth: Auth.ApiKeyAuth,interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match auth:
    case Auth.ApiKeyAuth{_,Some{callback},_}: C.call(Auth.ProviderAuthInteraction,Auth.LoginOutcome(),callback,interaction)
    case _: IO.pure(Auth.LoginOutcome(),Fail{"login unavailable"})
def ignoreNotification(_: Unit,_: Auth.AuthEvent) -> IO(Unit): IO.pure(Unit,Unit{})
def loginText(auth: IO(Auth.ApiKeyAuth)) -> IO(String):
  do IO<String>:
    selected : Auth.ApiKeyAuth <- auth
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    +prompt : C.Callback<Auth.AuthPrompt,Result<&2,&2,String,String>> <- C.create(~Unit,~Auth.AuthPrompt,~Result<&2,&2,String,String>,~promptAnswer,Unit{})
    +notify : C.Callback<Auth.AuthEvent,Unit> <- C.create(~Unit,~Auth.AuthEvent,~Unit,~ignoreNotification,Unit{})
    result : Auth.LoginOutcome() <- callLogin(selected,Auth.ProviderAuthInteraction{Abort.signal(Unit,controller),prompt,notify})
    C.dispose(Auth.AuthEvent,Unit,notify)
    C.dispose(Auth.AuthPrompt,Result<&2,&2,String,String>,prompt)
    Abort.dispose(Unit,controller)
    return credentialText(result)

def main() -> IO(Unit):
  do IO<Unit>:
    expect("requires Cloudflare Workers AI account config and returns scoped env (missing account)", resolvedText(workers(), vars([keyVar()]), None{}, False{}), "undefined")
    expect("requires Cloudflare Workers AI account config and returns scoped env", resolvedText(workers(), vars([keyVar(), accountVar()]), None{}, False{}), "cf-key|-|CLOUDFLARE_ACCOUNT_ID=account-id|CLOUDFLARE_API_KEY")
    expect("requires Cloudflare AI Gateway account and gateway config and returns scoped env headers (missing gateway)", resolvedText(gatewayAuth(), vars([keyVar(), accountVar()]), None{}, False{}), "undefined")
    expect("requires Cloudflare AI Gateway account and gateway config and returns scoped env headers", resolvedText(gatewayAuth(), vars([keyVar(), accountVar(), gatewayVar()]), None{}, False{}), "-|cf-aig-authorization:Bearer cf-key,Authorization:null,x-api-key:null|CLOUDFLARE_ACCOUNT_ID=account-id,CLOUDFLARE_GATEWAY_ID=gateway-id|CLOUDFLARE_API_KEY")
    expect("a stored key picks up the ambient account and gateway ids", resolvedText(gatewayAuth(), vars([accountVar(), gatewayVar()]), storedCredential(Some{"stored-key"}, Nil{}), False{}), "-|cf-aig-authorization:Bearer stored-key,Authorization:null,x-api-key:null|CLOUDFLARE_ACCOUNT_ID=account-id,CLOUDFLARE_GATEWAY_ID=gateway-id|stored credential")
    expect("stored credential values win over the environment per field", resolvedText(gatewayAuth(), vars([keyVar(), accountVar(), gatewayVar()]), storedCredential(None{}, [R.Property{"CLOUDFLARE_GATEWAY_ID", "stored-gateway"}]), False{}), "-|cf-aig-authorization:Bearer cf-key,Authorization:null,x-api-key:null|CLOUDFLARE_ACCOUNT_ID=account-id,CLOUDFLARE_GATEWAY_ID=stored-gateway|stored credential")
    expect("a stored empty key does not fall back to the environment", resolvedText(workers(), vars([keyVar(), accountVar()]), storedCredential(Some{""}, Nil{}), False{}), "undefined")
    expect("the workers provider ignores the gateway id", resolvedText(workers(), vars([keyVar(), accountVar(), gatewayVar()]), None{}, False{}), "cf-key|-|CLOUDFLARE_ACCOUNT_ID=account-id|CLOUDFLARE_API_KEY")
    expect("an aborted signal stops an environment lookup", resolvedText(workers(), vars([keyVar(), accountVar()]), None{}, True{}), "error:The operation was aborted")
    expect("stored values need no environment lookup under an aborted signal", resolvedText(workers(), vars(Nil{}), storedCredential(Some{"stored-key"}, [accountVar()]), True{}), "stored-key|-|CLOUDFLARE_ACCOUNT_ID=account-id|stored credential")
    expect("Workers AI login saves the key and account",loginText(workers()),"cf-key|CLOUDFLARE_ACCOUNT_ID=account-id")
    expect("AI Gateway login also saves its gateway",loginText(gatewayAuth()),"cf-key|CLOUDFLARE_ACCOUNT_ID=account-id,CLOUDFLARE_GATEWAY_ID=gateway-id")
