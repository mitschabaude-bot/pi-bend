import Base
import ./types.bend as Auth
import ../types.bend as T
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/abort.bend as Abort

# Standard api-key auth: a stored credential key wins, otherwise the first set
# environment variable resolves. Providers with non-standard resolution
# (provider env, ambient files, IAM) write their own ApiKeyAuth.

type EnvApiKey is Data:
  EnvApiKey{name: String, envVars: List<&2, String>}

type Found is Data:
  Found{name: String, value: String}

def found(name: String, value: Maybe<&2, String>) -> Maybe<&2, Found>:
  match value:
    case Some{SNil{}}: None{}
    case Some{text}: Some{Found{name, text}}
    case None{}: None{}

def firstEnv(+context: Auth.AuthContext, names: List<&2, String>, previous: Maybe<&2, Found>) -> IO(Maybe<&2, Found>):
  match names previous:
    case _ Some{value}: IO.pure(Maybe<&2, Found>, Some{value})
    case Nil{} None{}: IO.pure(Maybe<&2, Found>, None{})
    case +name <> rest None{}:
      do IO<Maybe<&2, Found>>:
        value : Maybe<&2, String> <- Auth.envValue(context, name)
        firstEnv(context, rest, found(name, value))

def keyResult(key: String, env: Maybe<&2, T.ProviderEnv()>, source: String) -> Auth.AuthOutcome():
  Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{key}, None{}, None{}}, env, Some{source}}}}

def ambient(found: Maybe<&2, Found>) -> Auth.AuthOutcome():
  match found:
    case None{}: Done{None{}}
    case Some{Found{name, value}}: keyResult(value, None{}, name)

def resolveKey(envVars: List<&2, String>, context: Auth.AuthContext, credential: Maybe<&2, Auth.Credential>) -> IO(Auth.AuthOutcome()):
  match credential:
    case Some{Auth.ApiKeyCredential{Some{SCon{first, rest}}, env}}: IO.pure(Auth.AuthOutcome(), keyResult(SCon{first, rest}, env, "stored credential"))
    case _:
      do IO<Auth.AuthOutcome()>:
        first : Maybe<&2, Found> <- firstEnv(context, envVars, None{})
        return ambient(first)

def resolveUnlessAborted(envVars: List<&2, String>, context: Auth.AuthContext, credential: Maybe<&2, Auth.Credential>, cancelled: Bool) -> IO(Auth.AuthOutcome()):
  match cancelled:
    case True{}: IO.pure(Auth.AuthOutcome(), Fail{"The operation was aborted"})
    case False{}: resolveKey(envVars, context, credential)

def resolveEnv(config: EnvApiKey, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  match config input:
    case EnvApiKey{_, envVars} Auth.ResolveInput{context, credential, signal}:
      do IO<Auth.AuthOutcome()>:
        cancelled : Bool <- Abort.aborted(Unit, signal)
        resolveUnlessAborted(envVars, context, credential, cancelled)

def envApiKeyAuth(+name: String, envVars: List<&2, String>) -> IO(Auth.ApiKeyAuth):
  do IO<Auth.ApiKeyAuth>:
    resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~EnvApiKey, ~Auth.ResolveInput, ~(Auth.AuthOutcome()), ~resolveEnv, EnvApiKey{name, envVars})
    return Auth.ApiKeyAuth{name, resolve}
