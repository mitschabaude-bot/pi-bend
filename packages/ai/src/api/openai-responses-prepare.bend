import Base
import ../types.bend as T
import ../utils/transcript.bend as Transcript
import ./openai-responses-options.bend as Options
import ./openai-responses-auth.bend as Auth
import ./openai-responses-policy.bend as Policy
import ./openai-responses-headers.bend as Headers
import ./openai-responses-params.bend as Params
import ./openai-responses-request.bend as Request
import ./constrained-sampling.bend as Sampling
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R

type Error is Data:
  UnsupportedApi{api: T.ModelApi}
  CredentialFailure{cause: Auth.CredentialError}
  GrammarFailure{cause: Sampling.Error}
  PayloadFailure{cause: Request.BuildError}

# No socket, callback or task is acquired by preparation. Transport and hooks
# use the caller's unchanged options after this succeeds.
type Prepared is Data:
  Prepared{apiKey: String, baseUrl: String, headers: T.ProviderHeaders(), payload: T.JsonValue, compat: Policy.ResolvedCompat, grammarToolInputProperties: R.Record<String>, cacheRetention: T.CacheRetention}

type ModelSettings is Data:
  ModelSettings{provider: String, baseUrl: String, headers: Maybe<&2, R.Record<String>>, compat: Policy.ResolvedCompat}

# Azure and Codex have their own provider entry points/authentication contracts.
# A dynamically selected model must still satisfy this provider's API type.
def compatible(api: T.ModelApi, +provider: String, +baseUrl: String, headers: Maybe<&2, R.Record<String>>, compat: Maybe<&2, T.ModelCompatibility(api)>) -> Result<&2, &2, Error, ModelSettings>:
  match api:
    case T.OpenAIResponsesApi{}: Done{ModelSettings{provider, baseUrl, headers, Policy.getCompat(provider, baseUrl, compat)}}
    case other: Fail{UnsupportedApi{other}}

def modelSettings(-J: Data, model: T.Model<J>) -> Result<&2, &2, Error, ModelSettings>:
  match model:
    case T.Model{_, _, api, provider, baseUrl, _, _, _, _, _, _, _, headers, compat}: compatible(api, provider, baseUrl, headers, compat)

def midConversation(compat: Policy.ResolvedCompat) -> Bool:
  match compat:
    case Policy.ResolvedCompat{_, enabled, _, _, _, _, _, _, _, _}: enabled

def grammarEnabled(compat: Policy.ResolvedCompat) -> Bool:
  match compat:
    case Policy.ResolvedCompat{_, _, _, _, _, enabled, _, _, _, _}: enabled

def affinity(compat: Policy.ResolvedCompat) -> T.SessionAffinityFormat:
  match compat:
    case Policy.ResolvedCompat{_, _, format, _, _, _, _, _, _, _}: format

def sessionId(-Choice: Data, options: Params.RequestOptions<Choice>) -> Maybe<&2, String>:
  match options:
    case Params.RequestOptions{_, _, _, _, _, _, value, _}: value

def grammar(-G: Data, -D: Data, context: T.TranscriptContext<V.Value, R.Record<V.Value>, G, D>, enabled: Bool) -> Result<&2, &2, Sampling.Error, R.Record<String>>:
  match context:
    case T.TranscriptContext{messages}: Sampling.createGrammarToolInputProperties(Some{Transcript.getDeclaredTools(V.Value, R.Record<V.Value>, G, D, messages)}, enabled)

def finish(apiKey: String, baseUrl: String, headers: T.ProviderHeaders(), compat: Policy.ResolvedCompat, grammarResult: R.Record<String>, retention: T.CacheRetention, payload: Result<&2, &2, Request.BuildError, T.JsonValue>) -> Result<&2, &2, Error, Prepared>:
  match payload:
    case Fail{cause}: Fail{PayloadFailure{cause}}
    case Done{value}: Done{Prepared{apiKey, baseUrl, headers, value, compat, grammarResult, retention}}

def withGrammar(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~G: Data, ~D: Data, model: T.Model<T.JsonValue>, +context: T.TranscriptContext<V.Value, R.Record<V.Value>, G, D>, +body: Params.RequestOptions<Choice>, preparedModelSettings: ModelSettings, userAgent: String, headers: Maybe<&2, T.ProviderHeaders()>, apiKey: String, +retention: T.CacheRetention, grammarResult: Result<&2, &2, Sampling.Error, R.Record<String>>) -> IO(Result<&2, &2, Error, Prepared>):
  match preparedModelSettings grammarResult:
    case _ Fail{cause}: IO.pure(Result<&2, &2, Error, Prepared>, Fail{GrammarFailure{cause}})
    case ModelSettings{provider, +baseUrl, modelHeaders, +compat} Done{+fields}:
      do IO<Result<&2, &2, Error, Prepared>>:
        merged : T.ProviderHeaders() = Headers.forContext(V.Value, R.Record<V.Value>, G, D, userAgent, provider, modelHeaders, context, affinity(compat), Policy.cacheSessionId(retention, sessionId(Choice, body)), headers)
        payload : Result<&2, &2, Request.BuildError, T.JsonValue> <- Request.buildParams(~Choice, ~encodeChoice, ~G, ~D, ~T.JsonValue, model, context, body, compat, fields, retention)
        return finish(apiKey, baseUrl, merged, compat, fields, retention, payload)

def withCredential(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~G: Data, ~D: Data, model: T.Model<T.JsonValue>, +context: T.TranscriptContext<V.Value, R.Record<V.Value>, G, D>, body: Params.RequestOptions<Choice>, +preparedModelSettings: ModelSettings, userAgent: String, headers: Maybe<&2, T.ProviderHeaders()>, retention: Maybe<&2, T.CacheRetention>, env: Maybe<&2, T.ProviderEnv()>, credential: Result<&2, &2, Auth.CredentialError, String>) -> IO(Result<&2, &2, Error, Prepared>):
  match preparedModelSettings credential:
    case _ Fail{cause}: IO.pure(Result<&2, &2, Error, Prepared>, Fail{CredentialFailure{cause}})
    case ModelSettings{_, _, _, compat} Done{apiKey}:
      do IO<Result<&2, &2, Error, Prepared>>:
        resolved : T.CacheRetention <- Policy.resolveCacheRetention(retention, env)
        withGrammar(~Choice, ~encodeChoice, ~G, ~D, model, context, body, preparedModelSettings, userAgent, headers, apiKey, resolved, grammar(G, D, context, grammarEnabled(compat)))

def providerName(preparedModelSettings: ModelSettings) -> String:
  match preparedModelSettings:
    case ModelSettings{provider, _, _, _}: provider

def resolvedCompatibility(preparedModelSettings: ModelSettings) -> Policy.ResolvedCompat:
  match preparedModelSettings:
    case ModelSettings{_, _, _, compat}: compat

def withModel(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~HookError: Data, model: T.Model<T.JsonValue>, context: T.TranscriptContext<V.Value, R.Record<V.Value>, G, D>, body: Params.RequestOptions<Choice>, options: T.StreamOptions<T.JsonValue, Signal, Telemetry, Fetch, HookError>, userAgent: String, resolved: Result<&2, &2, Error, ModelSettings>) -> IO(Result<&2, &2, Error, Prepared>):
  match options resolved:
    case _ Fail{cause}: IO.pure(Result<&2, &2, Error, Prepared>, Fail{cause})
    case T.StreamOptions{_, _, apiKey, _, env, _, _, +headers, _, _, _, _, _, _, _, retention, _, _, _} Done{+preparedModelSettings}:
      withCredential(~Choice, ~encodeChoice, ~G, ~D, model, Transcript.resolveTranscript(V.Value, R.Record<V.Value>, G, D, context, Some{midConversation(resolvedCompatibility(preparedModelSettings))}), body, preparedModelSettings, userAgent, headers, retention, env, Auth.getClientApiKey(providerName(preparedModelSettings), apiKey, headers))

# Public wire preparation. Model sampling, hook payloads and converted request
# bodies share canonical JSON; message/schema/tool types remain their own ADTs.
def prepare(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~HookError: Data, +model: T.Model<T.JsonValue>, context: T.TranscriptContext<V.Value, R.Record<V.Value>, G, D>, +options: Options.OpenAIResponsesOptions<T.JsonValue, Choice, Signal, Telemetry, Fetch, HookError>, userAgent: String) -> IO(Result<&2, &2, Error, Prepared>):
  withModel(~Choice, ~encodeChoice, ~G, ~D, ~Signal, ~Telemetry, ~Fetch, ~HookError, model, context, Options.requestOptions(Choice, Signal, Telemetry, Fetch, HookError, options), Options.toStreamOptions(T.JsonValue, Choice, Signal, Telemetry, Fetch, HookError, options), userAgent, modelSettings(T.JsonValue, model))
