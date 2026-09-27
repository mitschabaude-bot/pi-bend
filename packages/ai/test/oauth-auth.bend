import Base
import ../src/auth/types.bend as Auth
import ../src/auth/resolve.bend as Resolve
import ../src/auth/oauth/anthropic.bend as AnthropicOAuth
import ../src/auth/oauth/github-copilot.bend as CopilotOAuth
import ../src/models.bend as Models
import ../src/types.bend as T
import ../src/providers/anthropic.bend as Anthropic
import ../src/providers/github-copilot.bend as GithubCopilot
import ./openrouter-oauth.bend as Stores
import ./images-models.bend as ImagesTest
import ./anthropic-messages-client.bend as TestClient
import ../../runtime/src/callback.bend as C
import ../../runtime/src/date.bend as Date
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V

# pi-mono f07218c4d packages/ai/test/oauth-auth.test.ts, "OAuth through
# Models.getAuth (lazy load chain)": a provider with its OAuth handler
# resolves a stored OAuth credential. Upstream stores it in an
# InMemoryCredentialStore and calls createModels(...).getAuth; here a store
# holding the credential and Resolve.resolveProviderAuth (what getAuth calls)
# stand in, and the handler is created directly instead of loaded lazily.
# The "OAuthAuth adapters" half runs in tests/oauth_flows_check.py.

def expect(+name: String, +actual: String, +expected: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(actual, expected), IO.print("PASS " ++ name), IO.die(Unit, 1, "FAIL " ++ name ++ ": " ++ actual ++ " != " ++ expected))

def optional(value: Maybe<&2, String>) -> String: Maybe.default(&2, String, value, "undefined")

def resolved(resolution: Resolve.Resolution()) -> String:
  match resolution:
    case Fail{error}: "error:" ++ Resolve.errorMessage(error)
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{key, _, baseUrl}, _, source}}}: optional(key) ++ "|" ++ optional(baseUrl) ++ "|" ++ optional(source)
    case Done{None{}}: "undefined"

def authOf(provider: Models.Provider) -> Auth.ProviderAuth:
  match provider:
    case Models.Provider{_, _, _, auth, _, _, _, _}: auth

def firstModelProvider(provider: Models.Provider) -> String:
  match provider:
    case Models.Provider{id, _, _, _, Nil{}, _, _, _}: id
    case Models.Provider{_, _, _, _, model <> _, _, _, _}: T.modelProvider(model)

def resolvedFor(provider: Models.Provider, +providerId: String, credential: Auth.Credential) -> IO(Resolve.Resolution()):
  do IO<Resolve.Resolution()>:
    credentials : Auth.CredentialStore <- Stores.storeWith(providerId, credential)
    context : Auth.AuthContext <- ImagesTest.fakeAuthContext(ImagesTest.vars(Nil{}))
    Resolve.resolveProviderAuth(Resolve.ProviderRef{providerId, authOf(provider)}, credentials, context, Resolve.noOverrides())

def run() -> IO(Unit):
  do IO<Unit>:
    +fetch : Fetch.Fetch(Unit) <- C.create(~Unit, ~(Fetch.Input<Unit>), ~(Fetch.Result_(Unit)), ~Stores.unexpectedFetch, Unit{})
    now : F64 <- Date.now()
    +later : F64 <- IO.pure(F64, F.add(now, F.fromU32(600000)))
    anthropicOAuth : Auth.OAuthAuth <- AnthropicOAuth.anthropicOAuth(fetch, TestClient.urlContext())
    +anthropic : Models.Provider <- Anthropic.anthropicProvider(Some{anthropicOAuth})
    first : Resolve.Resolution() <- resolvedFor(anthropic, firstModelProvider(anthropic), Auth.OAuthCredential{"r", "oauth-access-token", later, R.new(V.Value)})
    expect("oauth-auth.test.ts > OAuth through Models.getAuth (lazy load chain) > resolves stored anthropic oauth credentials via the lazy flow import", resolved(first), "oauth-access-token|undefined|OAuth")
    copilotOAuth : Auth.OAuthAuth <- CopilotOAuth.githubCopilotOAuth(fetch, TestClient.urlContext())
    +copilot : Models.Provider <- GithubCopilot.githubCopilotProvider(Some{copilotOAuth})
    +access : String <- IO.pure(String, "tid=abc;exp=123;proxy-ep=proxy.business.githubcopilot.com;rest")
    second : Resolve.Resolution() <- resolvedFor(copilot, firstModelProvider(copilot), Auth.OAuthCredential{"r", access, later, R.new(V.Value)})
    expect("oauth-auth.test.ts > OAuth through Models.getAuth (lazy load chain) > resolves stored github-copilot oauth credentials including per-credential baseUrl", resolved(second), access ++ "|https://api.business.githubcopilot.com|OAuth")

def main() -> IO(Unit): run()
