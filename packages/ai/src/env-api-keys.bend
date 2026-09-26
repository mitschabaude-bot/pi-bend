import Base
import ./types.bend as T
import ./utils/provider-env.bend as Env
import ../../runtime/src/filesystem.bend as FS
import ../../runtime/src/record.bend as R

# pi-mono packages/ai/src/env-api-keys.ts: the environment variables that can
# hold a provider's API key, and the key (or "<authenticated>" for ambient
# Vertex and Bedrock credentials) they provide. Values are read with
# getProviderEnvValue: the request's provider env first, then the process.
#
# Upstream memoizes the default Vertex ADC file check in a module variable
# (and does not cache while its Node modules load); this port checks the file
# on each call, so a credentials file created later is seen.
def ANTHROPIC_AUTH_TOKEN_ENV() -> String: "ANTHROPIC_AUTH_TOKEN"
def ANTHROPIC_OAUTH_TOKEN_ENV() -> String: "ANTHROPIC_OAUTH_TOKEN"
def ANTHROPIC_API_KEY_ENV() -> String: "ANTHROPIC_API_KEY"

def envVar(+provider: String) -> Maybe<&2, String>:
  match provider:
    case "ant-ling": Some{"ANT_LING_API_KEY"}
    case "qwen-token-plan": Some{"QWEN_TOKEN_PLAN_API_KEY"}
    case "qwen-token-plan-cn": Some{"QWEN_TOKEN_PLAN_CN_API_KEY"}
    case "qwen-token-plan-individual": Some{"QWEN_TOKEN_PLAN_API_KEY"}
    case "openai": Some{"OPENAI_API_KEY"}
    case "azure-openai-responses": Some{"AZURE_OPENAI_API_KEY"}
    case "nvidia": Some{"NVIDIA_API_KEY"}
    case "deepseek": Some{"DEEPSEEK_API_KEY"}
    case "google": Some{"GEMINI_API_KEY"}
    case "google-vertex": Some{"GOOGLE_CLOUD_API_KEY"}
    case "groq": Some{"GROQ_API_KEY"}
    case "cerebras": Some{"CEREBRAS_API_KEY"}
    case "xai": Some{"XAI_API_KEY"}
    case "radius": Some{"RADIUS_API_KEY"}
    case "openrouter": Some{"OPENROUTER_API_KEY"}
    case "vercel-ai-gateway": Some{"AI_GATEWAY_API_KEY"}
    case "zai": Some{"ZAI_API_KEY"}
    case "zai-coding-cn": Some{"ZAI_CODING_CN_API_KEY"}
    case "mistral": Some{"MISTRAL_API_KEY"}
    case "minimax": Some{"MINIMAX_API_KEY"}
    case "minimax-cn": Some{"MINIMAX_CN_API_KEY"}
    case "moonshotai": Some{"MOONSHOT_API_KEY"}
    case "moonshotai-cn": Some{"MOONSHOT_API_KEY"}
    case "huggingface": Some{"HF_TOKEN"}
    case "fireworks": Some{"FIREWORKS_API_KEY"}
    case "together": Some{"TOGETHER_API_KEY"}
    case "baseten": Some{"BASETEN_API_KEY"}
    case "opencode": Some{"OPENCODE_API_KEY"}
    case "opencode-go": Some{"OPENCODE_API_KEY"}
    case "kimi-coding": Some{"KIMI_API_KEY"}
    case "meta": Some{"META_API_KEY"}
    case "cloudflare-workers-ai": Some{"CLOUDFLARE_API_KEY"}
    case "cloudflare-ai-gateway": Some{"CLOUDFLARE_API_KEY"}
    case "xiaomi": Some{"XIAOMI_API_KEY"}
    case "xiaomi-token-plan-cn": Some{"XIAOMI_TOKEN_PLAN_CN_API_KEY"}
    case "xiaomi-token-plan-ams": Some{"XIAOMI_TOKEN_PLAN_AMS_API_KEY"}
    case "xiaomi-token-plan-sgp": Some{"XIAOMI_TOKEN_PLAN_SGP_API_KEY"}
    case _: None{}

# upstream getApiKeyEnvVars. ANTHROPIC_AUTH_TOKEN takes part in discovery, but
# getEnvApiKey skips it: requests pass it as Authorization: Bearer.
def getApiKeyEnvVars(+provider: String) -> Maybe<&2, List<&2, String>>:
  match provider:
    case "github-copilot": Some{"COPILOT_GITHUB_TOKEN" <> Nil{}}
    case "anthropic": Some{ANTHROPIC_AUTH_TOKEN_ENV() <> ANTHROPIC_OAUTH_TOKEN_ENV() <> ANTHROPIC_API_KEY_ENV() <> Nil{}}
    case other: Maybe.map(&2, String, List<&2, String>, name => name <> Nil{}, envVar(other))

def present(value: Maybe<&2, String>) -> Bool:
  match value:
    case Some{SCon{_, _}}: True{}
    case _: False{}

def kept(keep: Bool, name: String, rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}: name <> rest
    case False{}: rest

def foundVars(names: List<&2, String>, +env: Maybe<&2, T.ProviderEnv()>) -> IO(List<&2, String>):
  match names:
    case Nil{}: IO.pure(List<&2, String>, Nil{})
    case +name <> rest:
      do IO<List<&2, String>>:
        value : Maybe<&2, String> <- Env.getProviderEnvValue(name, env)
        later : List<&2, String> <- foundVars(rest, env)
        return kept(present(value), name, later)

def nonemptyList(values: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  match values:
    case Nil{}: None{}
    case other: Some{other}

def foundIn(names: Maybe<&2, List<&2, String>>, env: Maybe<&2, T.ProviderEnv()>) -> IO(Maybe<&2, List<&2, String>>):
  match names:
    case None{}: IO.pure(Maybe<&2, List<&2, String>>, None{})
    case Some{list}:
      do IO<Maybe<&2, List<&2, String>>>:
        found : List<&2, String> <- foundVars(list, env)
        return nonemptyList(found)

# upstream findEnvKeys: the configured variables that hold a nonempty value,
# in lookup order; undefined when there are none.
def findEnvKeys(provider: String, env: Maybe<&2, T.ProviderEnv()>) -> IO(Maybe<&2, List<&2, String>>):
  foundIn(getApiKeyEnvVars(provider), env)

def firstNotAuthToken(names: List<&2, String>) -> Maybe<&2, String>:
  match names:
    case Nil{}: None{}
    case "ANTHROPIC_AUTH_TOKEN" <> rest: firstNotAuthToken(rest)
    case name <> _: Some{name}

def apiKeyEnv(+provider: String, keys: Maybe<&2, List<&2, String>>) -> Maybe<&2, String>:
  match keys:
    case None{}: None{}
    case Some{+names}: Bool.pick(Maybe<&2, String>, String.eq(provider, "anthropic"), firstNotAuthToken(names), List.head(&2, String, names))

def scopedValue(env: Maybe<&2, T.ProviderEnv()>, name: String) -> Maybe<&2, String>:
  match env:
    case None{}: None{}
    case Some{fields}: R.get(String, fields, name)

def defaultAdcPath(home: Result<&2, &2, FS.Error, String>) -> Maybe<&2, String>:
  match home:
    case Done{dir}: Some{FS.child(FS.child(FS.child(dir, ".config"), "gcloud"), "application_default_credentials.json")}
    case Fail{_}: None{}

def existing(path: Maybe<&2, String>) -> IO(Bool):
  match path:
    case None{}: IO.pure(Bool, False{})
    case Some{file}: FS.accessible(file, 0)

def adcFromEnv(gacPath: Maybe<&2, String>) -> IO(Bool):
  match gacPath:
    case Some{SCon{c, cs}}: FS.accessible(SCon{c, cs}, 0)
    case _:
      do IO<Bool>:
        home : Result<&2, &2, FS.Error, String> <- FS.homedir()
        existing(defaultAdcPath(home))

# upstream hasVertexAdcCredentials: an explicit GOOGLE_APPLICATION_CREDENTIALS
# in the request env must exist; otherwise the resolved variable's file, or
# the gcloud default file.
def adcWith(explicit: Maybe<&2, String>, env: Maybe<&2, T.ProviderEnv()>) -> IO(Bool):
  match explicit:
    case Some{SCon{c, cs}}: FS.accessible(SCon{c, cs}, 0)
    case _:
      do IO<Bool>:
        gacPath : Maybe<&2, String> <- Env.getProviderEnvValue("GOOGLE_APPLICATION_CREDENTIALS", env)
        adcFromEnv(gacPath)

def hasVertexAdcCredentials(+env: Maybe<&2, T.ProviderEnv()>) -> IO(Bool): adcWith(scopedValue(env, "GOOGLE_APPLICATION_CREDENTIALS"), env)

def anyValue(names: List<&2, String>, +env: Maybe<&2, T.ProviderEnv()>) -> IO(Bool):
  match names:
    case Nil{}: IO.pure(Bool, False{})
    case +name <> rest:
      do IO<Bool>:
        value : Maybe<&2, String> <- Env.getProviderEnvValue(name, env)
        later : Bool <- anyValue(rest, env)
        return present(value) || later

def authenticated(ok: Bool) -> Maybe<&2, String>:
  match ok:
    case True{}: Some{"<authenticated>"}
    case False{}: None{}

def vertexAmbient(+env: Maybe<&2, T.ProviderEnv()>) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    credentials : Bool <- hasVertexAdcCredentials(env)
    project : Bool <- anyValue("GOOGLE_CLOUD_PROJECT" <> "GCLOUD_PROJECT" <> Nil{}, env)
    location : Bool <- anyValue("GOOGLE_CLOUD_LOCATION" <> Nil{}, env)
    return authenticated(credentials && project && location)

def bedrockAmbient(+env: Maybe<&2, T.ProviderEnv()>) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    single : Bool <- anyValue("AWS_PROFILE" <> "AWS_BEARER_TOKEN_BEDROCK" <> "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" <> "AWS_CONTAINER_CREDENTIALS_FULL_URI" <> "AWS_WEB_IDENTITY_TOKEN_FILE" <> Nil{}, env)
    access : Bool <- anyValue("AWS_ACCESS_KEY_ID" <> Nil{}, env)
    secret : Bool <- anyValue("AWS_SECRET_ACCESS_KEY" <> Nil{}, env)
    return authenticated(single || (access && secret))

def ambient(+provider: String, +env: Maybe<&2, T.ProviderEnv()>) -> IO(Maybe<&2, String>):
  match provider:
    case "google-vertex": vertexAmbient(env)
    case "amazon-bedrock": bedrockAmbient(env)
    case _: IO.pure(Maybe<&2, String>, None{})

def keyed(+provider: String, +env: Maybe<&2, T.ProviderEnv()>, name: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match name:
    case Some{variable}: Env.getProviderEnvValue(variable, env)
    case None{}: ambient(provider, env)

# upstream getEnvApiKey: the first found variable's value (for Anthropic the
# first that is not ANTHROPIC_AUTH_TOKEN), else ambient Vertex or Bedrock
# credentials as "<authenticated>".
def getEnvApiKey(+provider: String, +env: Maybe<&2, T.ProviderEnv()>) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    keys : Maybe<&2, List<&2, String>> <- findEnvKeys(provider, env)
    keyed(provider, env, apiKeyEnv(provider, keys))
