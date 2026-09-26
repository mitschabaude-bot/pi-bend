import Base
import ../src/types.bend as T
import ../src/env-api-keys.bend as Keys
import ../../runtime/src/record.bend as R

# pi-mono f07218c4d packages/ai/test/env-api-keys.test.ts. Upstream sets and
# deletes process.env entries; here each case passes them as the provider env
# (read before the process environment), and a deleted variable is absent from
# it. The run requires the process environment not to define the variables
# the cases delete (checked first), so a developer's own keys cannot leak in.
def Env() -> Data: Maybe<&2, T.ProviderEnv()>

def env(entries: List<&2, R.Property<String>>) -> Env(): Some{R.Record{entries}}

def var(name: String, value: String) -> R.Property<String>: R.Property{name, value}

def showList(value: Maybe<&2, List<&2, String>>) -> String:
  match value:
    case None{}: "undefined"
    case Some{names}: "[" ++ String.join(names, ",") ++ "]"

def showMaybe(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "undefined"
    case Some{text}: text

def check(ok: Bool, +name: String, detail: String) -> IO(Unit):
  Bool.pick(IO(Unit), ok, IO.pure(Unit, Unit{}), IO.die(Unit, 1, "FAIL " ++ name ++ ": " ++ detail))

def expectKeys(+name: String, +provider: String, +environment: Env(), +want: String) -> IO(Unit):
  do IO<Unit>:
    found : Maybe<&2, List<&2, String>> <- Keys.findEnvKeys(provider, environment)
    +shown : String <- IO.pure(String, showList(found))
    check(String.eq(shown, want), name, "findEnvKeys(" ++ provider ++ ") = " ++ shown ++ ", want " ++ want)

def expectKey(+name: String, +provider: String, +environment: Env(), +want: String) -> IO(Unit):
  do IO<Unit>:
    key : Maybe<&2, String> <- Keys.getEnvApiKey(provider, environment)
    +shown : String <- IO.pure(String, showMaybe(key))
    check(String.eq(shown, want), name, "getEnvApiKey(" ++ provider ++ ") = " ++ shown ++ ", want " ++ want)

# The process environment must not supply any variable a case deletes.
def processClean() -> IO(Unit):
  do IO<Unit>:
    anthropic : Maybe<&2, List<&2, String>> <- Keys.findEnvKeys("anthropic", None{})
    copilot : Maybe<&2, String> <- Keys.getEnvApiKey("github-copilot", None{})
    zai : Maybe<&2, String> <- Keys.getEnvApiKey("zai-coding-cn", None{})
    check(Maybe.is_none(&2, List<&2, String>, anthropic) && Maybe.is_none(&2, String, copilot) && Maybe.is_none(&2, String, zai), "env-api-keys", "unset ANTHROPIC_*, COPILOT_GITHUB_TOKEN and ZAI_CODING_CN_API_KEY in the process environment to run this suite")

def run() -> IO(Unit):
  do IO<Unit>:
    processClean()
    +generic : Env() <- IO.pure(Env(), env([var("GH_TOKEN", "gh-token"), var("GITHUB_TOKEN", "github-token")]))
    expectKeys("does not treat generic GitHub tokens as GitHub Copilot credentials", "github-copilot", generic, "undefined")
    expectKey("does not treat generic GitHub tokens as GitHub Copilot credentials", "github-copilot", generic, "undefined")
    IO.print("PASS does not treat generic GitHub tokens as GitHub Copilot credentials")
    +copilot : Env() <- IO.pure(Env(), env([var("COPILOT_GITHUB_TOKEN", "copilot-token"), var("GH_TOKEN", "gh-token"), var("GITHUB_TOKEN", "github-token")]))
    expectKeys("resolves GitHub Copilot credentials from COPILOT_GITHUB_TOKEN", "github-copilot", copilot, "[COPILOT_GITHUB_TOKEN]")
    expectKey("resolves GitHub Copilot credentials from COPILOT_GITHUB_TOKEN", "github-copilot", copilot, "copilot-token")
    IO.print("PASS resolves GitHub Copilot credentials from COPILOT_GITHUB_TOKEN")
    +zai : Env() <- IO.pure(Env(), env([var("ZAI_CODING_CN_API_KEY", "zai-coding-cn-token")]))
    expectKeys("resolves ZAI China Coding Plan credentials from ZAI_CODING_CN_API_KEY", "zai-coding-cn", zai, "[ZAI_CODING_CN_API_KEY]")
    expectKey("resolves ZAI China Coding Plan credentials from ZAI_CODING_CN_API_KEY", "zai-coding-cn", zai, "zai-coding-cn-token")
    IO.print("PASS resolves ZAI China Coding Plan credentials from ZAI_CODING_CN_API_KEY")
    +all : Env() <- IO.pure(Env(), env([var("ANTHROPIC_AUTH_TOKEN", "auth-token"), var("ANTHROPIC_OAUTH_TOKEN", "oauth-token"), var("ANTHROPIC_API_KEY", "api-key")]))
    expectKeys("reports ANTHROPIC_AUTH_TOKEN but preserves OAuth token API key lookup", "anthropic", all, "[ANTHROPIC_AUTH_TOKEN,ANTHROPIC_OAUTH_TOKEN,ANTHROPIC_API_KEY]")
    expectKey("reports ANTHROPIC_AUTH_TOKEN but preserves OAuth token API key lookup", "anthropic", all, "oauth-token")
    IO.print("PASS reports ANTHROPIC_AUTH_TOKEN but preserves OAuth token API key lookup")
    +auth : Env() <- IO.pure(Env(), env([var("ANTHROPIC_AUTH_TOKEN", "auth-token")]))
    expectKeys("does not return ANTHROPIC_AUTH_TOKEN as an API key", "anthropic", auth, "[ANTHROPIC_AUTH_TOKEN]")
    expectKey("does not return ANTHROPIC_AUTH_TOKEN as an API key", "anthropic", auth, "undefined")
    IO.print("PASS does not return ANTHROPIC_AUTH_TOKEN as an API key")
    +oauth : Env() <- IO.pure(Env(), env([var("ANTHROPIC_OAUTH_TOKEN", "oauth-token")]))
    expectKeys("preserves ANTHROPIC_OAUTH_TOKEN as an API key", "anthropic", oauth, "[ANTHROPIC_OAUTH_TOKEN]")
    expectKey("preserves ANTHROPIC_OAUTH_TOKEN as an API key", "anthropic", oauth, "oauth-token")
    IO.print("PASS preserves ANTHROPIC_OAUTH_TOKEN as an API key")
    expectKey("falls back to ANTHROPIC_API_KEY for API key lookup", "anthropic", env([var("ANTHROPIC_API_KEY", "api-key")]), "api-key")
    IO.print("PASS falls back to ANTHROPIC_API_KEY for API key lookup")

# Differential mode (tests/env_api_keys_check.py): each argument is
# "provider|NAME=value;NAME=value"; prints "provider|findEnvKeys|getEnvApiKey".
def pairOf(parts: List<&2, String>) -> List<&2, R.Property<String>>:
  match parts:
    case name <> value <> Nil{}: var(name, value) <> Nil{}
    case _: Nil{}

def pair(entry: String) -> List<&2, R.Property<String>>: pairOf(String.split(entry, '='))

def entries(parts: List<&2, String>) -> List<&2, R.Property<String>>:
  match parts:
    case Nil{}: Nil{}
    case part <> rest: List.append(&2, R.Property<String>, pair(part), entries(rest))

def differential(+provider: String, +spec: String) -> IO(Unit):
  +environment = env(entries(String.split(spec, ';')))
  do IO<Unit>:
    found : Maybe<&2, List<&2, String>> <- Keys.findEnvKeys(provider, environment)
    key : Maybe<&2, String> <- Keys.getEnvApiKey(provider, environment)
    IO.print("D " ++ provider ++ "|" ++ showList(found) ++ "|" ++ showMaybe(key))

def caseOf(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case provider <> spec <> Nil{}: differential(provider, spec)
    case _: IO.die(Unit, 1, "invalid case")

def differentialCase(argument: String) -> IO(Unit): caseOf(String.split(argument, '|'))

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case argument <> rest:
      do IO<Unit>:
        differentialCase(argument)
        cases(rest)

def selected(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: run()
    case some: cases(some)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    selected(args)
