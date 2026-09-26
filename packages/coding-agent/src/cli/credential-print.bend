import Base
import ./args.bend as Args
import ./auth-command.bend as Command
import ./auth-check.bend as Check
import ../core/model-runtime.bend as Models
import ../../../ai/src/auth/types.bend as Auth
import ../../../ai/src/auth/resolve.bend as Resolve
import ../../../ai/src/models.bend as AiModels
import ../../../runtime/src/f64.bend as F

# upstream cli/credential-print.ts: `pi auth print-api-key` and
# `print-bearer-token`. getAuth refreshes and persists an OAuth credential
# that expires within the requested validity (30 minutes by default for
# bearer tokens) through the normal request-auth path.

def DEFAULT_BEARER_TOKEN_MIN_EXPIRY_MS() -> Nat: 1800000n

type Candidate is Data:
  Candidate{id: String, model: Maybe<&2, Models.Model()>}

type Found is Data:
  Found{providerId: String, value: String}

def typeOf(infos: List<&2, Auth.CredentialInfo>, +providerId: String) -> Maybe<&2, Auth.CredentialType>:
  match infos:
    case Nil{}: None{}
    case Auth.CredentialInfo{+id, kind} <> rest: Bool.pick(Unit -> Maybe<&2, Auth.CredentialType>, String.eq(id, providerId), _ => Some{kind}, _ => typeOf(rest, providerId))(Unit{})

def isOAuth(kind: Maybe<&2, Auth.CredentialType>) -> Bool:
  match kind:
    case Some{Auth.OAuthType{}}: True{}
    case _: False{}

def skipped(kind: Command.AuthCommandKind, credential: Maybe<&2, Auth.CredentialType>) -> Bool:
  match kind:
    case Command.ApiKey{}: isOAuth(credential)
    case Command.BearerToken{}: Bool.not(isOAuth(credential))
    case Command.Check{}: False{}

def overrides(kind: Command.AuthCommandKind, minExpiryMs: Maybe<&2, Nat>, signal: Auth.Signal()) -> Resolve.AuthResolutionOverrides:
  match kind:
    case Command.BearerToken{}: Resolve.AuthResolutionOverrides{None{}, None{}, Some{F.fromNat(Maybe.default(&2, Nat, minExpiryMs, DEFAULT_BEARER_TOKEN_MIN_EXPIRY_MS()))}, signal}
    case _: Resolve.AuthResolutionOverrides{None{}, None{}, None{}, signal}

def resolvedFor(+runtime: Models.ModelRuntime, candidate: Candidate, options: Resolve.AuthResolutionOverrides) -> IO(Resolve.Resolution()):
  match candidate:
    case Candidate{_, Some{model}}: Models.getModelAuth(runtime, model, options)
    case Candidate{id, None{}}: Models.getAuth(runtime, id, options)

def credentialOf(+providerId: String, resolution: Resolve.Resolution()) -> Result<&2, &2, String, Maybe<&2, Found>>:
  match resolution:
    case Fail{error}: Fail{Resolve.errorMessage(error)}
    case Done{auth}: Done{Maybe.map(&2, String, Found, value => Found{providerId, value}, Command.getAuthCredential(auth))}

def candidateId(candidate: Candidate) -> String:
  match candidate:
    case Candidate{id, _}: id

def prepended(first: Result<&2, &2, String, Maybe<&2, Found>>, rest: Result<&2, &2, String, List<&2, Found>>) -> Result<&2, &2, String, List<&2, Found>>:
  match first rest:
    case Fail{message} _: Fail{message}
    case _ Fail{message}: Fail{message}
    case Done{Some{found}} Done{more}: Done{found <> more}
    case Done{None{}} Done{more}: Done{more}

def credentialsFrom(+runtime: Models.ModelRuntime, +infos: List<&2, Auth.CredentialInfo>, +kind: Command.AuthCommandKind, +minExpiryMs: Maybe<&2, Nat>, +signal: Auth.Signal(), candidates: List<&2, Candidate>) -> IO(Result<&2, &2, String, List<&2, Found>>):
  match candidates:
    case Nil{}: IO.pure(Result<&2, &2, String, List<&2, Found>>, Done{Nil{}})
    case +candidate <> +rest:
      +id = candidateId(candidate)
      Bool.pick(Unit -> IO(Result<&2, &2, String, List<&2, Found>>), skipped(kind, typeOf(infos, id)),
        _ => credentialsFrom(runtime, infos, kind, minExpiryMs, signal, rest),
        _ => do IO<Result<&2, &2, String, List<&2, Found>>>:
          resolution : Resolve.Resolution() <- resolvedFor(runtime, candidate, overrides(kind, minExpiryMs, signal))
          later : Result<&2, &2, String, List<&2, Found>> <- credentialsFrom(runtime, infos, kind, minExpiryMs, signal, rest)
          return prepended(credentialOf(id, resolution), later))(Unit{})

def foundIds(values: List<&2, Found>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case Found{id, _} <> rest: id <> foundIds(rest)

def firstId(candidates: List<&2, Candidate>) -> Maybe<&2, String>:
  match candidates:
    case Candidate{id, _} <> _: Some{id}
    case Nil{}: None{}

def isApiKeyCommand(kind: Command.AuthCommandKind) -> Bool:
  match kind:
    case Command.ApiKey{}: True{}
    case _: False{}

def genericNone(kind: Command.AuthCommandKind) -> String:
  "No usable " ++ Bool.pick(String, isApiKeyCommand(kind), "API key", "OAuth bearer token") ++ " is configured"

def noneUsable(+infos: List<&2, Auth.CredentialInfo>, +kind: Command.AuthCommandKind, +explicit: Bool, first: Maybe<&2, String>) -> String:
  match first:
    case Some{+id}:
      +credential = typeOf(infos, id)
      Bool.pick(String, explicit && isApiKeyCommand(kind) && isOAuth(credential), "Provider \"" ++ id ++ "\" is configured with OAuth, not an API key",
        Bool.pick(String, explicit && Bool.not(isApiKeyCommand(kind)) && Bool.not(isOAuth(credential)), "Provider \"" ++ id ++ "\" is not configured with an OAuth bearer token", genericNone(kind)))
    case None{}: genericNone(kind)

def chosen(+infos: List<&2, Auth.CredentialInfo>, +kind: Command.AuthCommandKind, explicit: Bool, first: Maybe<&2, String>, found: Result<&2, &2, String, List<&2, Found>>) -> Result<&2, &2, String, String>:
  match found:
    case Fail{message}: Fail{message}
    case Done{Found{_, value} <> Nil{}}: Done{value}
    case Done{Nil{}}: Fail{noneUsable(infos, kind, explicit, first)}
    case Done{many}: Fail{"Multiple configured providers matched (" ++ String.join(foundIds(many), ", ") ++ "). Specify --provider."}

def printFrom(+runtime: Models.ModelRuntime, +infos: List<&2, Auth.CredentialInfo>, +kind: Command.AuthCommandKind, +minExpiryMs: Maybe<&2, Nat>, +signal: Auth.Signal(), explicit: Bool, candidates: Result<&2, &2, String, List<&2, Candidate>>) -> IO(Result<&2, &2, String, String>):
  match candidates:
    case Fail{message}: IO.pure(Result<&2, &2, String, String>, Fail{message})
    case Done{+list}:
      do IO<Result<&2, &2, String, String>>:
        found : Result<&2, &2, String, List<&2, Found>> <- credentialsFrom(runtime, infos, kind, minExpiryMs, signal, list)
        return chosen(infos, kind, explicit, firstId(list), found)

# Candidates
# ----------

def modelCandidate(+id: String, result: Models.ResolveCliModelResult) -> Result<&2, &2, String, List<&2, Candidate>>:
  match result:
    case Models.ResolveCliModelResult{Some{model}, _, _, None{}}: Done{[Candidate{id, Some{model}}]}
    case Models.ResolveCliModelResult{_, _, _, Some{error}}: Fail{error}
    case _: Fail{"Unable to resolve the requested provider/model"}

def explicitCandidates(+runtime: Models.ModelRuntime, +packageDir: String, +cliProvider: String, model: Maybe<&2, String>, found: Maybe<&2, AiModels.Provider>) -> IO(Result<&2, &2, String, List<&2, Candidate>>):
  match found model:
    case None{} _: IO.pure(Result<&2, &2, String, List<&2, Candidate>>, Fail{"Unknown provider \"" ++ cliProvider ++ "\". Use --list-models to see available providers."})
    case Some{provider} None{}: IO.pure(Result<&2, &2, String, List<&2, Candidate>>, Done{[Candidate{Models.providerId(provider), None{}}]})
    case Some{provider} Some{cliModel}:
      +id = Models.providerId(provider)
      do IO<Result<&2, &2, String, List<&2, Candidate>>>:
        result : Models.ResolveCliModelResult <- Check.resolveCliModel(runtime, packageDir, Some{id}, cliModel)
        return modelCandidate(id, result)

def customWarning(warning: Maybe<&2, String>) -> Bool:
  match warning:
    case Some{text}: String.contains(text, "Using custom model id")
    case None{}: False{}

def inferredCandidate(+id: String, result: Models.ResolveCliModelResult) -> Maybe<&2, Candidate>:
  match result:
    case Models.ResolveCliModelResult{Some{model}, _, warning, None{}}: Bool.pick(Maybe<&2, Candidate>, customWarning(warning), None{}, Some{Candidate{id, Some{model}}})
    case _: None{}

def inferredCandidates(+runtime: Models.ModelRuntime, +packageDir: String, +infos: List<&2, Auth.CredentialInfo>, +cliModel: String, providers: List<&2, AiModels.Provider>) -> IO(List<&2, Candidate>):
  match providers:
    case Nil{}: IO.pure(List<&2, Candidate>, Nil{})
    case provider <> +rest:
      +id = Models.providerId(provider)
      Bool.pick(Unit -> IO(List<&2, Candidate>), Maybe.is_some(&2, Auth.CredentialType, typeOf(infos, id)),
        _ => do IO<List<&2, Candidate>>:
          result : Models.ResolveCliModelResult <- Check.resolveCliModel(runtime, packageDir, Some{id}, cliModel)
          +later : List<&2, Candidate> <- inferredCandidates(runtime, packageDir, infos, cliModel, rest)
          return Maybe.default(&2, List<&2, Candidate>, Maybe.map(&2, Candidate, List<&2, Candidate>, candidate => candidate <> later, inferredCandidate(id, result)), later),
        _ => inferredCandidates(runtime, packageDir, infos, cliModel, rest))(Unit{})

def nonEmptyCandidates(+cliModel: String, candidates: List<&2, Candidate>) -> Result<&2, &2, String, List<&2, Candidate>>:
  match candidates:
    case Nil{}: Fail{"Model \"" ++ cliModel ++ "\" not found. Use --list-models to see available models."}
    case some: Done{some}

def candidatesFor(+runtime: Models.ModelRuntime, +packageDir: String, +infos: List<&2, Auth.CredentialInfo>, requested: Command.RequestedAuth) -> IO(Result<&2, &2, String, List<&2, Candidate>>):
  match requested:
    case Command.RequestedAuth{Some{+cliProvider}, model}:
      do IO<Result<&2, &2, String, List<&2, Candidate>>>:
        found : Maybe<&2, AiModels.Provider> <- Models.getProvider(runtime, cliProvider)
        explicitCandidates(runtime, packageDir, cliProvider, model, found)
    case Command.RequestedAuth{None{}, +model}:
      +cliModel = Maybe.default(&2, String, model, "")
      do IO<Result<&2, &2, String, List<&2, Candidate>>>:
        providers : List<&2, AiModels.Provider> <- Models.getProviders(runtime)
        found : List<&2, Candidate> <- inferredCandidates(runtime, packageDir, infos, cliModel, providers)
        return nonEmptyCandidates(cliModel, found)

def explicitProvider(requested: Command.RequestedAuth) -> Bool:
  match requested:
    case Command.RequestedAuth{Some{_}, _}: True{}
    case _: False{}

def withInfos(+runtime: Models.ModelRuntime, +packageDir: String, +kind: Command.AuthCommandKind, +minExpiryMs: Maybe<&2, Nat>, +signal: Auth.Signal(), +requested: Command.RequestedAuth, listed: Auth.StoreResult(List<&2, Auth.CredentialInfo>)) -> IO(Result<&2, &2, String, String>):
  match listed:
    case Fail{message}: IO.pure(Result<&2, &2, String, String>, Fail{message})
    case Done{+infos}:
      do IO<Result<&2, &2, String, String>>:
        candidates : Result<&2, &2, String, List<&2, Candidate>> <- candidatesFor(runtime, packageDir, infos, requested)
        printFrom(runtime, infos, kind, minExpiryMs, signal, explicitProvider(requested), candidates)

def validatedPrint(+runtime: Models.ModelRuntime, +packageDir: String, +kind: Command.AuthCommandKind, +minExpiryMs: Maybe<&2, Nat>, +signal: Auth.Signal(), requested: Result<&2, &2, String, Command.RequestedAuth>) -> IO(Result<&2, &2, String, String>):
  match requested:
    case Fail{message}: IO.pure(Result<&2, &2, String, String>, Fail{message})
    case Done{+value}:
      do IO<Result<&2, &2, String, String>>:
        listed : Auth.StoreResult(List<&2, Auth.CredentialInfo>) <- Auth.list(Models.credentialsOf(runtime), signal)
        withInfos(runtime, packageDir, kind, minExpiryMs, signal, value, listed)

# upstream resolveCredentialForPrint: the one usable credential of the
# requested kind; Fail carries the AuthCommandError (or resolution) message.
def resolveCredentialForPrint(args: Args.Args, +runtime: Models.ModelRuntime, +packageDir: String, +kind: Command.AuthCommandKind, +minExpiryMs: Maybe<&2, Nat>, +signal: Auth.Signal()) -> IO(Result<&2, &2, String, String>):
  validatedPrint(runtime, packageDir, kind, minExpiryMs, signal, Command.validateAuthCommandArgs(args, kind))
