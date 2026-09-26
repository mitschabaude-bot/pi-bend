import Base
import ../packages/coding-agent/src/cli/args.bend as Args
import ../packages/coding-agent/src/cli/auth-command.bend as Command
import ../packages/coding-agent/src/cli/auth-check.bend as Check
import ../packages/coding-agent/src/cli/credential-print.bend as Print
import ../packages/coding-agent/src/core/auth-storage.bend as AuthStorage
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/auth/context.bend as Context
import ../packages/ai/src/models.bend as AiModels
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/providers/radius.bend as Radius
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/date.bend as Date
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/http-message.bend as Headers
import ../packages/runtime/src/posix-path.bend as Path
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/schema-value.bend as V
import ./loopback-fetch.bend as Loop

# upstream packages/coding-agent/test/auth-check.test.ts and
# credential-print.test.ts. Runtimes are the production model runtime over
# in-memory or read-only credentials (upstream ModelRuntime.create with an
# in-memory models store and no model network). Upstream replaces the
# registered OAuth refresh with a spy; here the Codex OAuth handlers are an
# injected fixture that counts refreshes. Args: a fresh temporary directory
# and the package directory (collation data).

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

# Fixtures
# --------

def Counter() -> Data: Ref.Ref<Nat>

def unusedLogin(unused: Unit, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()): IO.pure(Auth.LoginOutcome(), Fail{"unused"})

# The refreshed credential upstream's spies return: a fresh token valid for an hour.
def refreshed(counter: Counter(), input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>):
  match input:
    case Auth.RefreshInput{Auth.OAuthCredential{refresh, _, _, extra}, _}:
      do IO<Result<&2, &2, String, Auth.Credential>>:
        count : Unit <- Ref.modify(Nat, Unit, counter, n => (1n+n, Unit{}))
        now : F64 <- Date.now()
        return Done{Auth.OAuthCredential{refresh, "fresh-token", F.add(now, F.fromU32(3600000)), extra}}
    case _: IO.pure(Result<&2, &2, String, Auth.Credential>, Fail{"not oauth"})

def accessAuth(unused: Unit, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  match credential:
    case Auth.OAuthCredential{_, access, _, _}: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Done{Auth.ModelAuth{Some{access}, None{}, None{}}})
    case _: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{"not oauth"})

# Kimi Code's OAuth sends the token as an Authorization header.
def headerAuth(unused: Unit, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  match credential:
    case Auth.OAuthCredential{_, access, _, _}: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Done{Auth.ModelAuth{None{}, Some{R.Record{[R.Property{"Authorization", Ai.PresentValue{"Bearer " ++ access}}]}}, None{}}})
    case _: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{"not oauth"})

def fixtureOAuth(name: String, counter: Counter(), headers: Bool) -> IO(Auth.OAuthAuth):
  do IO<Auth.OAuthAuth>:
    login : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~Unit, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~unusedLogin, Unit{})
    refresher : C.Callback<Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>> <- C.create(~Counter(), ~Auth.RefreshInput, ~Result<&2, &2, String, Auth.Credential>, ~refreshed, counter)
    deriver : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- Bool.pick(IO(C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>>), headers, C.create(~Unit, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~headerAuth, Unit{}), C.create(~Unit, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~accessAuth, Unit{}))
    return Auth.OAuthAuth{name, True{}, None{}, login, refresher, deriver}

def noFetch(unused: Unit, input: Fetch.Input<Unit>) -> IO(Fetch.Result_(Unit)):
  IO.pure(Fetch.Result_(Unit), Fail{Fetch.InvalidRequest{Headers.BufferedRequestHeaderError{Headers.InvalidName{}}}})

# The production runtime (createAuthCheckModelRuntime) with the fixture
# Codex OAuth; the model network is never used.
def runtimeOver(store: Auth.CredentialStore, +counter: Counter()) -> IO(Models.ModelRuntime):
  do IO<Models.ModelRuntime>:
    codex : Auth.OAuthAuth <- fixtureOAuth("ChatGPT Plus/Pro (Codex Subscription)", counter, False{})
    anthropic : Auth.OAuthAuth <- fixtureOAuth("Anthropic (Claude Pro/Max)", counter, False{})
    fetch : Fetch.Fetch(Unit) <- C.create(~Unit, ~Fetch.Input<Unit>, ~Fetch.Result_(Unit), ~noFetch, Unit{})
    Check.createAuthCheckModelRuntime(store, codex, anthropic, Radius.RadiusTransport{fetch, Loop.urlContext()})

def storeOf(pair: AuthStorage.AuthStorageOwner & AuthStorage.AuthStorage) -> IO(Auth.CredentialStore):
  match pair:
    case (_, storage): AuthStorage.store(storage)

def memoryStore(credentials: List<&2, R.Property<Auth.Credential>>) -> IO(Auth.CredentialStore):
  do IO<Auth.CredentialStore>:
    owner : AuthStorage.AuthStorageOwner <- AuthStorage.inMemory(R.Record{credentials})
    storeOf(AuthStorage.borrow(owner))

def apiKey(key: String) -> Auth.Credential: Auth.ApiKeyCredential{Some{key}, None{}}

def oauth(access: String, expires: F64) -> Auth.Credential: Auth.OAuthCredential{"refresh-token", access, expires, R.new(V.Value)}

def args(values: List<&2, String>) -> Args.Args: Args.parseArgs(values)

def counted(counter: Counter()) -> IO(Nat): Ref.read(Nat, counter)

# Results
# -------

def sameText(left: Maybe<&2, String>, right: Maybe<&2, String>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: String.eq(a, b)
    case _ _: False{}

def resultIs(result: Result<&2, &2, String, Check.AuthCheckResult>, +status: String, +provider: String, +reason: Maybe<&2, String>, +authType: Maybe<&2, String>) -> Bool:
  match result:
    case Done{Check.AuthCheckResult{s, p, r, t}}: String.eq(Check.statusName(s), status) && String.eq(p, provider) && sameText(Maybe.map(&2, Check.AuthCheckReason, String, Check.reasonName, r), reason) && sameText(Maybe.map(&2, Auth.CredentialType, String, Check.typeName, t), authType)
    case Fail{_}: False{}

def statusIs(result: Result<&2, &2, String, Check.AuthCheckResult>, +status: String, +provider: Maybe<&2, String>, +reason: Maybe<&2, String>) -> Bool:
  match result:
    case Done{Check.AuthCheckResult{s, p, r, _}}: String.eq(Check.statusName(s), status) && Maybe.default(&2, Bool, Maybe.map(&2, String, Bool, wanted => String.eq(p, wanted), provider), True{}) && Maybe.default(&2, Bool, Maybe.map(&2, String, Bool, wanted => sameText(Maybe.map(&2, Check.AuthCheckReason, String, Check.reasonName, r), Some{wanted}), reason), True{})
    case Fail{_}: False{}

def credentialIs(result: Result<&2, &2, String, Maybe<&2, String>>, +expected: String) -> Bool:
  match result:
    case Done{Some{value}}: String.eq(value, expected)
    case _: False{}

def printed(result: Result<&2, &2, String, String>, +expected: String) -> Bool:
  match result:
    case Done{value}: String.eq(value, expected)
    case Fail{_}: False{}

def failsWith(result: Result<&2, &2, String, String>, +text: String) -> Bool:
  match result:
    case Fail{message}: String.contains(message, text)
    case Done{_}: False{}

def recheck(+runtime: Models.ModelRuntime, +packageDir: String, values: List<&2, String>) -> IO(Result<&2, &2, String, Check.AuthCheckResult>):
  Check.checkProviderAuth(args(values), runtime, packageDir, False{})

# auth-check.test.ts
# ------------------

def configured(+packageDir: String, +counter: Counter()) -> IO(Unit):
  do IO<Unit>:
    store : Auth.CredentialStore <- memoryStore([R.Property{"openai", apiKey("test-key")}])
    +runtime : Models.ModelRuntime <- runtimeOver(store, counter)
    ready : Result<&2, &2, String, Check.AuthCheckResult> <- recheck(runtime, packageDir, ["--provider", "openai"])
    check(resultIs(ready, "ready", "openai", None{}, Some{"api_key"}), "auth check command reports a configured provider as ready")
    byModel : Result<&2, &2, String, Check.AuthCheckResult> <- recheck(runtime, packageDir, ["--model", "openai/gpt-5.5"])
    both : Result<&2, &2, String, Check.AuthCheckResult> <- recheck(runtime, packageDir, ["--provider", "openai", "--model", "gpt-5.5"])
    check(resultIs(byModel, "ready", "openai", None{}, Some{"api_key"}) && statusIs(both, "ready", Some{"openai"}, None{}), "auth check command resolves the provider from --model")

def withoutRefresh(+packageDir: String) -> IO(Unit):
  do IO<Unit>:
    +counter : Counter() <- Ref.new(Nat, 0n)
    +apiStore : Auth.CredentialStore <- memoryStore([R.Property{"openai", apiKey("test-key")}])
    +apiRuntime : Models.ModelRuntime <- runtimeOver(apiStore, counter)
    key : Result<&2, &2, String, Maybe<&2, String>> <- Check.getProviderCredential("openai", apiRuntime, apiStore, False{})
    +store : Auth.CredentialStore <- memoryStore([R.Property{"openai-codex", oauth("old-token", F.fromU32(0))}])
    +runtime : Models.ModelRuntime <- runtimeOver(store, counter)
    token : Result<&2, &2, String, Maybe<&2, String>> <- Check.getProviderCredential("openai-codex", runtime, store, False{})
    calls : Nat <- counted(counter)
    check(credentialIs(key, "test-key") && credentialIs(token, "old-token") && Nat.is_eq(calls, 0n), "auth check command reads credentials without refreshing OAuth when requested")

def refreshesByDefault(+packageDir: String) -> IO(Unit):
  do IO<Unit>:
    +counter : Counter() <- Ref.new(Nat, 0n)
    store : Auth.CredentialStore <- memoryStore([R.Property{"openai-codex", oauth("old-token", F.fromU32(0))}])
    +runtime : Models.ModelRuntime <- runtimeOver(store, counter)
    result : Result<&2, &2, String, Check.AuthCheckResult> <- Check.checkProviderAuth(args(["--provider", "openai-codex"]), runtime, packageDir, True{})
    calls : Nat <- counted(counter)
    check(statusIs(result, "ready", None{}, None{}) && Nat.is_eq(calls, 1n), "auth check command refreshes OAuth by default")

def unknownProvider(+packageDir: String, +counter: Counter()) -> IO(Unit):
  do IO<Unit>:
    store : Auth.CredentialStore <- memoryStore(Nil{})
    +runtime : Models.ModelRuntime <- runtimeOver(store, counter)
    result : Result<&2, &2, String, Check.AuthCheckResult> <- recheck(runtime, packageDir, ["--provider", "not-installed"])
    check(resultIs(result, "not_ready", "not-installed", Some{"provider_not_found"}, None{}), "auth check command reports an unknown provider as not ready")

def readOnlyCheck(+packageDir: String, +counter: Counter(), +path: String) -> IO(Result<&2, &2, String, Check.AuthCheckResult>):
  do IO<Result<&2, &2, String, Check.AuthCheckResult>>:
    storage : AuthStorage.ReadOnlyAuthStorage <- AuthStorage.readOnly(path)
    +runtime : Models.ModelRuntime <- runtimeOver(AuthStorage.readOnlyStore(storage), counter)
    recheck(runtime, packageDir, ["--provider", "openai"])

def readOnlyCases(+packageDir: String, +counter: Counter(), +tempDir: String) -> IO(Unit):
  +authPath = Path.join(tempDir, "auth.json")
  +nested = Path.join(tempDir, "agent/auth.json")
  do IO<Unit>:
    written : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(authPath, "{\"openai\":{\"type\":\"api_key\",\"key\":\"$MISSING_AUTH_CHECK_KEY\"}}")
    unresolved : Result<&2, &2, String, Check.AuthCheckResult> <- readOnlyCheck(packageDir, counter, authPath)
    check(resultIs(unresolved, "not_ready", "openai", Some{"credentials_not_configured"}, None{}), "auth check command does not treat an unresolved stored environment reference as configured")
    broken : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(authPath, "{invalid-json")
    malformed : Result<&2, &2, String, Check.AuthCheckResult> <- readOnlyCheck(packageDir, counter, authPath)
    check(resultIs(malformed, "invalid", "openai", Some{"invalid_state"}, None{}), "auth check command reports malformed auth state as invalid")
    absent : Result<&2, &2, String, Check.AuthCheckResult> <- readOnlyCheck(packageDir, counter, nested)
    fileExists : Bool <- FS.accessible(nested, 0)
    dirExists : Bool <- FS.accessible(Path.join(tempDir, "agent"), 0)
    check(statusIs(absent, "not_ready", None{}, Some{"credentials_not_configured"}) && Bool.not(fileExists) && Bool.not(dirExists), "auth check command does not create an auth file or its parent directory")

def sameNat(left: Maybe<&2, Nat>, right: Maybe<&2, Nat>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: Nat.is_eq(a, b)
    case _ _: False{}

def commandIs(result: Result<&2, &2, String, Maybe<&2, Command.AuthCommand>>, +kind: String, +args: List<&2, String>, json: Bool, credentials: Bool, noRefresh: Bool, expiry: Maybe<&2, Nat>) -> Bool:
  match result:
    case Done{Some{Command.AuthCommand{k, a, j, c, n, e}}}: String.eq(Command.getAuthCommandName(k), kind) && String.eq("[" ++ String.join(a, "\u{0}") ++ "]", "[" ++ String.join(args, "\u{0}") ++ "]") && Bool.not(Bool.xor(j, json)) && Bool.not(Bool.xor(c, credentials)) && Bool.not(Bool.xor(n, noRefresh)) && sameNat(e, expiry)
    case _: False{}

def parsing() -> IO(Unit):
  check(commandIs(Command.parseAuthCommand(["auth", "check", "--provider", "openai"]), "auth check", ["--provider", "openai"], False{}, False{}, False{}, None{}) && commandIs(Command.parseAuthCommand(["auth", "check", "--json", "--credentials", "--no-refresh", "--provider", "openai"]), "auth check", ["--provider", "openai"], True{}, True{}, True{}, None{}), "auth check command accepts optional JSON output, credential output, and --no-refresh")

def authCheckRuntime(+counter: Counter()) -> IO(Unit):
  do IO<Unit>:
    store : Auth.CredentialStore <- memoryStore(Nil{})
    +runtime : Models.ModelRuntime <- runtimeOver(store, counter)
    provider : Maybe<&2, AiModels.Provider> <- Models.getProvider(runtime, "openai")
    check(Maybe.is_some(&2, AiModels.Provider, provider), "auth check command creates an auth-check runtime without catalog storage")

# credential-print.test.ts
# ------------------------

def printsApiKey(+packageDir: String, +counter: Counter()) -> IO(Unit):
  do IO<Unit>:
    store : Auth.CredentialStore <- memoryStore([R.Property{"openai", apiKey("test-api-key")}])
    +runtime : Models.ModelRuntime <- runtimeOver(store, counter)
    result : Result<&2, &2, String, String> <- Print.resolveCredentialForPrint(args(["--provider", "openai"]), runtime, packageDir, Command.ApiKey{}, None{}, None{})
    check(printed(result, "test-api-key"), "credential print commands prints a resolved API key")

# The registered kimi-coding provider with Kimi Code's OAuth, whose
# credentials become an Authorization header.
def kimiProvider(counter: Counter()) -> IO(AiModels.Provider):
  do IO<AiModels.Provider>:
    kimi : Auth.OAuthAuth <- fixtureOAuth("Kimi Code (subscription)", counter, True{})
    return AiModels.Provider{"kimi-coding", "Kimi For Coding", "https://api.kimi.com/coding", Auth.ProviderAuth{None{}, Some{kimi}}, Nil{}, AiModels.ApiStreams{}, None{}}

def bearerHeader(+packageDir: String, +counter: Counter()) -> IO(Unit):
  do IO<Unit>:
    now : F64 <- Date.now()
    store : Auth.CredentialStore <- memoryStore([R.Property{"kimi-coding", Auth.OAuthCredential{"test-refresh-token", "header-test-token", F.add(now, F.fromU32(3600000)), R.new(V.Value)}}])
    provider : AiModels.Provider <- kimiProvider(counter)
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    +runtime : Models.ModelRuntime <- Models.fromProviders([provider], store, context)
    result : Result<&2, &2, String, String> <- Print.resolveCredentialForPrint(args(["--provider", "kimi-coding"]), runtime, packageDir, Command.BearerToken{}, None{}, None{})
    check(printed(result, "header-test-token"), "credential print commands prints bearer tokens resolved from an Authorization header")

def storedAccess(value: Auth.StoreResult(Maybe<&2, Auth.Credential>)) -> String:
  match value:
    case Done{Some{Auth.OAuthCredential{_, access, _, _}}}: access
    case _: ""

def refreshBeforePrint(+packageDir: String) -> IO(Unit):
  do IO<Unit>:
    +counter : Counter() <- Ref.new(Nat, 0n)
    +store : Auth.CredentialStore <- memoryStore([R.Property{"openai-codex", Auth.OAuthCredential{"test-refresh-token", "old-test-token", F.fromU32(0), R.new(V.Value)}}])
    +runtime : Models.ModelRuntime <- runtimeOver(store, counter)
    result : Result<&2, &2, String, String> <- Print.resolveCredentialForPrint(args(["--provider", "openai-codex"]), runtime, packageDir, Command.BearerToken{}, None{}, None{})
    calls : Nat <- counted(counter)
    stored : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Auth.read(store, "openai-codex", None{})
    check(printed(result, "fresh-token") && Nat.is_eq(calls, 1n) && String.eq(storedAccess(stored), "fresh-token"), "credential print commands refreshes an expired OAuth token before printing it")

def parseFails(result: Result<&2, &2, String, Maybe<&2, Command.AuthCommand>>, +text: String) -> Bool:
  match result:
    case Fail{message}: String.contains(message, text)
    case Done{_}: False{}

def kindIs(result: Result<&2, &2, String, Maybe<&2, Command.AuthCommand>>, +kind: String) -> Bool:
  match result:
    case Done{Some{Command.AuthCommand{k, _, _, _, _, _}}}: String.eq(Command.getAuthCommandName(k), kind)
    case _: False{}

def parsedCommands() -> Bool:
  commandIs(Command.parseAuthCommand(["auth", "print-api-key", "--provider", "openai"]), "auth print-api-key", ["--provider", "openai"], False{}, False{}, False{}, None{}) && kindIs(Command.parseAuthCommand(["auth", "print-bearer-token"]), "auth print-bearer-token") && commandIs(Command.parseAuthCommand(["auth", "print-bearer-token", "--min-expiry", "30m"]), "auth print-bearer-token", Nil{}, False{}, False{}, False{}, Some{1800000n}) && parseFails(Command.parseAuthCommand(["auth", "print-api-key", "--min-expiry", "30m"]), "only supported by print-bearer-token")

def helpCommands() -> Bool:
  Command.isAuthCommandHelp(["auth", "--help"]) && Command.isAuthCommandHelp(["auth", "print-api-key", "--help"]) && Command.isAuthCommandHelp(["auth", "print-bearer-token", "-h"]) && Command.isAuthCommandHelp(["auth", "check", "--help"]) && parseFails(Command.parseAuthCommand(["auth", "unknown"]), "Unknown auth command")

def printParsing(+packageDir: String, +counter: Counter()) -> IO(Unit):
  do IO<Unit>:
    now : F64 <- Date.now()
    store : Auth.CredentialStore <- memoryStore([R.Property{"openai-codex", Auth.OAuthCredential{"test-refresh-token", "test-token-not-to-be-printed", F.add(now, F.fromU32(3600000)), R.new(V.Value)}}])
    +runtime : Models.ModelRuntime <- runtimeOver(store, counter)
    noArgs : Result<&2, &2, String, String> <- Print.resolveCredentialForPrint(args(Nil{}), runtime, packageDir, Command.ApiKey{}, None{}, None{})
    wrongType : Result<&2, &2, String, String> <- Print.resolveCredentialForPrint(args(["--provider", "openai-codex"]), runtime, packageDir, Command.ApiKey{}, None{}, None{})
    check(parsedCommands() && helpCommands() && failsWith(noArgs, "requires --provider <provider> or --model <model>") && failsWith(wrongType, "configured with OAuth"), "credential print commands parses credential commands and rejects invalid arguments or credential types")

def run(+tempDir: String, +packageDir: String) -> IO(Unit):
  do IO<Unit>:
    +counter : Counter() <- Ref.new(Nat, 0n)
    configured(packageDir, counter)
    withoutRefresh(packageDir)
    refreshesByDefault(packageDir)
    unknownProvider(packageDir, counter)
    readOnlyCases(packageDir, counter, tempDir)
    parsing()
    authCheckRuntime(counter)
    printsApiKey(packageDir, counter)
    bearerHeader(packageDir, counter)
    refreshBeforePrint(packageDir)
    printParsing(packageDir, counter)

def started(args: List<String>) -> IO(Unit):
  match args:
    case tempDir <> packageDir <> Nil{}: run(tempDir, packageDir)
    case _: IO.die(Unit, 2, "usage: auth-commands <tempDir> <packageDir>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    started(args)
