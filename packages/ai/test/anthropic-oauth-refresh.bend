import Base
import ../src/auth/oauth/anthropic.bend as OAuth
import ../src/auth/types.bend as Auth
import ./anthropic-messages-client.bend as TestClient
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/date.bend as Date
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V

def original() -> Auth.Credential:
  Auth.OAuthCredential{"old-refresh", "old-access", F.fromU32(0), R.new(V.Value)}

def credentialOkay(now: F64, credential: Auth.Credential) -> Bool:
  match credential:
    case Auth.OAuthCredential{"new-refresh", "new-access", expires, _}: F.isGreater(F.compare(expires, now))
    case _: False{}

def authOkay(value: Result<&2, &2, String, Auth.ModelAuth>) -> Bool:
  match value:
    case Done{Auth.ModelAuth{Some{"new-access"}, _, _}}: True{}
    case _: False{}

def refreshed(auth: Auth.OAuthAuth, result: Result<&2, &2, String, Auth.Credential>) -> IO(Unit):
  match auth result:
    case Auth.OAuthAuth{_, _, _, _, derive} Done{+credential}:
      do IO<Unit>:
        now : F64 <- Date.now()
        derived : Result<&2, &2, String, Auth.ModelAuth> <- C.call(Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>, derive, credential)
        Bool.pick(IO(Unit), credentialOkay(now, credential) && authOkay(derived), IO.print("OAuth refresh pass"), IO.die(Unit, 1, "Anthropic OAuth refresh mismatch"))
    case _ _: IO.die(Unit, 1, "Anthropic OAuth refresh failed")

def invoke(+auth: Auth.OAuthAuth, signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  match auth:
    case Auth.OAuthAuth{_, _, _, +refresh, _}:
      do IO<Unit>:
        result : Result<&2, &2, String, Auth.Credential> <- C.call(Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>, refresh, Auth.RefreshInput{original(), signal})
        refreshed(auth, result)

def active(tokenUrl: String, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (runtime, +fetch):
      do IO<Unit>:
        +auth : Auth.OAuthAuth <- OAuth.anthropicOAuthWithTokenURL(fetch, TestClient.urlContext(), tokenUrl)
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        invoke(auth, Abort.signal(Unit, controller))
        Abort.dispose(Unit, controller)
        Auth.disposeOAuthAuth(auth)
        Fetch.retire(Unit, fetch)
        Fetch.dispose(runtime)

def initialized(tokenUrl: String, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "network initialization failed")
    case Done{runtime}:
      do IO<Unit>:
        pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit, runtime)
        active(tokenUrl, pair)

def run(tokenUrl: String) -> IO(Unit):
  do IO<Unit>:
    runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(), TestClient.networkOptions())
    initialized(tokenUrl, runtime)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case tokenUrl <> Nil{}: run(tokenUrl)
    case _: IO.die(Unit, 1, "token URL required")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
