import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/transcript.bend as Transcript
import ../packages/ai/src/api/openai-responses-options.bend as Options
import ../packages/ai/src/api/openai-responses-auth.bend as Auth
import ../packages/ai/src/api/openai-responses-policy.bend as Policy
import ../packages/ai/src/api/openai-responses-headers.bend as Headers
import ../packages/ai/src/api/openai-responses-params.bend as Params
import ../packages/ai/src/api/openai-responses-request.bend as Request
import ../packages/ai/src/api/constrained-sampling.bend as Sampling
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/ai/src/api/openai-responses-prepare.bend as P

# Pure result assembly preserves all successful outputs and typed failures.
law failed_payload_preserves_cause:
  for apiKey: String
  for baseUrl: String
  for headers: T.ProviderHeaders()
  for compat: Policy.ResolvedCompat
  for fields: R.Record<String>
  for retention: T.CacheRetention
  for cause: Request.BuildError
  {P.finish(apiKey, baseUrl, headers, compat, fields, retention, Fail{cause}) == Fail{P.PayloadFailure{cause}} : Result<&2, &2, P.Error, P.Prepared>}

law successful_preparation_preserves_all_fields:
  for apiKey: String
  for baseUrl: String
  for headers: T.ProviderHeaders()
  for compat: Policy.ResolvedCompat
  for fields: R.Record<String>
  for retention: T.CacheRetention
  for payload: T.JsonValue
  {P.finish(apiKey, baseUrl, headers, compat, fields, retention, Done{payload}) == Done{P.Prepared{apiKey, baseUrl, headers, payload, compat, fields, retention}} : Result<&2, &2, P.Error, P.Prepared>}

# These IO-program equalities assert absence of downstream effects on rejection.
# The template is instantiated at the JSON-wire / Unit-diagnostics types.
# Every runtime argument remains universally quantified. Bend templates require
# closed compile-time arguments; these are not claims over other instantiations.
# They do not establish termination of arbitrary successful conversion effects.
def wireIdentity(value: T.JsonValue) -> T.JsonValue: value
law credential_failure_has_no_effects:
  for model: T.Model<T.JsonValue>
  for context: T.TranscriptContext<V.Value, R.Record<V.Value>, Unit, Unit>
  for body: Params.RequestOptions<T.JsonValue>
  for configuration: P.ModelSettings
  for userAgent: String
  for headers: Maybe<&2, T.ProviderHeaders()>
  for retention: Maybe<&2, T.CacheRetention>
  for env: Maybe<&2, T.ProviderEnv()>
  for cause: Auth.CredentialError
  {P.withCredential(~T.JsonValue, ~wireIdentity, ~Unit, ~Unit, model, context, body, configuration, userAgent, headers, retention, env, Fail{cause}) == IO.pure(Result<&2, &2, P.Error, P.Prepared>, Fail{P.CredentialFailure{cause}}) : IO(Result<&2, &2, P.Error, P.Prepared>)}

law grammar_failure_has_no_effects:
  for model: T.Model<T.JsonValue>
  for context: T.TranscriptContext<V.Value, R.Record<V.Value>, Unit, Unit>
  for body: Params.RequestOptions<T.JsonValue>
  for configuration: P.ModelSettings
  for userAgent: String
  for headers: Maybe<&2, T.ProviderHeaders()>
  for apiKey: String
  for retention: T.CacheRetention
  for cause: Sampling.Error
  {P.withGrammar(~T.JsonValue, ~wireIdentity, ~Unit, ~Unit, model, context, body, configuration, userAgent, headers, apiKey, retention, Fail{cause}) == IO.pure(Result<&2, &2, P.Error, P.Prepared>, Fail{P.GrammarFailure{cause}}) : IO(Result<&2, &2, P.Error, P.Prepared>)}

law responses_model_preserves_configuration:
  for +provider: String
  for +baseUrl: String
  for headers: Maybe<&2, R.Record<String>>
  for compat: Maybe<&2, T.OpenAIResponsesCompat>
  {P.compatible(T.OpenAIResponsesApi{}, provider, baseUrl, headers, compat) == Done{P.ModelSettings{provider, baseUrl, headers, Policy.getCompat(provider, baseUrl, compat)}} : Result<&2, &2, P.Error, P.ModelSettings>}

law custom_api_is_rejected:
  for identifier: String
  for provider: String
  for baseUrl: String
  for headers: Maybe<&2, R.Record<String>>
  for compat: Maybe<&2, Empty>
  {P.compatible(T.CustomModelApi{identifier}, provider, baseUrl, headers, compat) == Fail{P.UnsupportedApi{T.CustomModelApi{identifier}}} : Result<&2, &2, P.Error, P.ModelSettings>}

# An absent field leaves the entire object unchanged. Explicit null is a value,
# including when it replaces an existing field. These cover arbitrary objects.
law omitted_string_preserves_object:
  for fields: R.Record<T.JsonValue>
  for key: String
  {Params.optionalNullableString(fields, key, None{}) == fields : R.Record<T.JsonValue>}

law explicit_null_replaces_field:
  for fields: R.Record<T.JsonValue>
  for key: String
  {Params.optionalNullableString(fields, key, Some{T.NullValue{}}) == R.set(T.JsonValue, fields, key, T.JsonNull{}) : R.Record<T.JsonValue>}

law explicit_string_replaces_field:
  for fields: R.Record<T.JsonValue>
  for key: String
  for value: String
  {Params.optionalNullableString(fields, key, Some{T.PresentValue{value}}) == R.set(T.JsonValue, fields, key, T.JsonString{value}) : R.Record<T.JsonValue>}
