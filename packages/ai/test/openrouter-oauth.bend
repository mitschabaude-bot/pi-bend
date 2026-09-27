import Base
import ../src/auth/types.bend as Auth
import ../src/auth/resolve.bend as Resolve
import ../src/auth/oauth/openrouter.bend as OpenRouterOAuth
import ../src/images-models.bend as Images
import ../src/models.bend as Models
import ../src/providers/openrouter.bend as OpenRouter
import ../src/providers/openrouter-images.bend as OpenRouterImages
import ./images-models.bend as ImagesTest
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V
import ./anthropic-messages-client.bend as TestClient

# pi-mono f07218c4d packages/ai/test/openrouter-oauth.test.ts, the provider
# half: both OpenRouter providers expose the OAuth handler next to API-key
# auth, and resolve one stored OAuth key. The login flow runs against a
# loopback server in tests/oauth_flows_check.py. Upstream stores the key in an
# InMemoryCredentialStore and resolves it with createModels/createImagesModels
# getAuth; here a store holding that credential and Resolve.resolveProviderAuth
# (what both collections' getAuth call) stand in. The handler's fetch is
# never called.

def expect(+name: String, +actual: String, +expected: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(actual, expected), IO.print("PASS " ++ name), IO.die(Unit, 1, "FAIL " ++ name ++ ": " ++ actual ++ " != " ++ expected))

def unexpectedFetch(unused: Unit, input: Fetch.Input<Unit>) -> IO(Fetch.Result_(Unit)): IO.die(Fetch.Result_(Unit), 1, "unexpected fetch")

def handler() -> IO(Auth.OAuthAuth):
  do IO<Auth.OAuthAuth>:
    fetch : Fetch.Fetch(Unit) <- C.create(~Unit, ~(Fetch.Input<Unit>), ~(Fetch.Result_(Unit)), ~unexpectedFetch, Unit{})
    OpenRouterOAuth.openRouterOAuth(fetch, TestClient.urlContext())

# Number.MAX_SAFE_INTEGER
def permanent() -> F64: F.subtract(F.multiply(F.fromU32(2097152), F.multiply(F.fromU32(2147483648), F.fromU32(2))), F.fromU32(1))

# A store holding one provider's credential.
type Stored is Data:
  Stored{providerId: String, credential: Auth.Credential}

def storedFor(stored: Stored, request: Auth.Request) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match stored request:
    case Stored{owner, credential} Auth.Request{+providerId, _}: IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{Bool.pick(Maybe<&2, Auth.Credential>, String.eq(providerId, owner), Some{credential}, None{})})

def unchanged(stored: Stored, request: Auth.Modify) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match stored request:
    case Stored{owner, credential} Auth.Modify{+providerId, _, _}: IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{Bool.pick(Maybe<&2, Auth.Credential>, String.eq(providerId, owner), Some{credential}, None{})})

def noneListed(unused: Unit, signal: Auth.Signal()) -> IO(Auth.StoreResult(List<&2, Auth.CredentialInfo>)): IO.pure(Auth.StoreResult(List<&2, Auth.CredentialInfo>), Done{Nil{}})

def deleted(unused: Unit, request: Auth.Request) -> IO(Auth.StoreResult(Unit)): IO.pure(Auth.StoreResult(Unit), Done{Unit{}})

def storeWith(+providerId: String, +credential: Auth.Credential) -> IO(Auth.CredentialStore):
  do IO<Auth.CredentialStore>:
    reader : C.Callback<Auth.Request, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~Stored, ~Auth.Request, ~(Auth.StoreResult(Maybe<&2, Auth.Credential>)), ~storedFor, Stored{providerId, credential})
    lister : C.Callback<Auth.Signal(), Auth.StoreResult(List<&2, Auth.CredentialInfo>)> <- C.create(~Unit, ~(Auth.Signal()), ~(Auth.StoreResult(List<&2, Auth.CredentialInfo>)), ~noneListed, Unit{})
    modifier : C.Callback<Auth.Modify, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~Stored, ~Auth.Modify, ~(Auth.StoreResult(Maybe<&2, Auth.Credential>)), ~unchanged, Stored{providerId, credential})
    deleter : C.Callback<Auth.Request, Auth.StoreResult(Unit)> <- C.create(~Unit, ~Auth.Request, ~(Auth.StoreResult(Unit)), ~deleted, Unit{})
    return Auth.CredentialStore{reader, lister, modifier, deleter}

def exposure(auth: Auth.ProviderAuth) -> String:
  match auth:
    case Auth.ProviderAuth{Some{_}, Some{Auth.OAuthAuth{_, _, Some{label}, _, _, _}}}: "apiKey+oauth:" ++ label
    case Auth.ProviderAuth{Some{_}, Some{_}}: "apiKey+oauth:<no label>"
    case Auth.ProviderAuth{_, None{}}: "no oauth"
    case Auth.ProviderAuth{None{}, _}: "no apiKey"

def textAuth(provider: Models.Provider) -> Auth.ProviderAuth:
  match provider:
    case Models.Provider{_, _, _, auth, _, _, _}: auth

def keyOf(resolution: Resolve.Resolution()) -> String:
  match resolution:
    case Fail{error}: "error:" ++ Resolve.errorMessage(error)
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{key}, _, _}, _, _}}}: key
    case Done{_}: "undefined"

def run() -> IO(Unit):
  do IO<Unit>:
    +oauth : Auth.OAuthAuth <- handler()
    +text : Models.Provider <- OpenRouter.openrouterProvider(Some{oauth})
    api : Images.ProviderImages(ImagesTest.Error()) <- ImagesTest.okApi()
    +images : Images.ImagesProvider<ImagesTest.Error()> <- OpenRouterImages.openrouterImagesProvider(ImagesTest.Error(), Some{oauth}, api)
    expect("openrouter-oauth.test.ts > OpenRouter OAuth > is exposed by both OpenRouter providers alongside API-key auth", exposure(textAuth(text)) ++ "|" ++ exposure(Images.providerAuth(ImagesTest.Error(), images)), "apiKey+oauth:Sign in with OpenRouter|apiKey+oauth:Sign in with OpenRouter")
    +credentials : Auth.CredentialStore <- storeWith("openrouter", Auth.OAuthCredential{"", "sk-or-stored", permanent(), R.new(V.Value)})
    +context : Auth.AuthContext <- ImagesTest.fakeAuthContext(ImagesTest.vars(Nil{}))
    textResolved : Resolve.Resolution() <- Resolve.resolveProviderAuth(Resolve.ProviderRef{"openrouter", textAuth(text)}, credentials, context, Resolve.noOverrides())
    imageModels : Images.ImagesModels<ImagesTest.Error()> <- IO.pure(Images.ImagesModels<ImagesTest.Error()>, Images.setProvider(ImagesTest.Error(), Images.createImagesModels(ImagesTest.Error(), credentials, context), images))
    imageResolved : Resolve.Resolution() <- Images.getAuth(ImagesTest.Error(), imageModels, "openrouter", Resolve.noOverrides())
    expect("openrouter-oauth.test.ts > OpenRouter OAuth > resolves the same stored OAuth key for text and image providers", keyOf(textResolved) ++ "|" ++ keyOf(imageResolved), "sk-or-stored|sk-or-stored")

def main() -> IO(Unit): run()
