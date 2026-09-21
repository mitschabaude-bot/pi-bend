import Base
import ../packages/ai/src/api/openai-responses-default-session.bend as Default
import ../packages/ai/src/api/openai-responses-stream-defaults.bend as Owner
import ../packages/ai/src/api/openai-responses-native-session.bend as Native
import ../packages/ai/src/api/openai-responses-native-session-error.bend as Errors
import ../packages/ai/src/api/openai-responses-stream-pricing.bend as Pricing
import ../packages/ai/src/api/openai-responses-prepare.bend as Preparation
import ../packages/ai/src/api/openai-responses-policy.bend as Policy
import ../packages/ai/src/types.bend as T
import ../packages/runtime/src/record.bend as R

# Preparation's grammar mapping must reach processing even when the payload
# hook later replaces the serialized request body.
law prepared_grammar_is_preserved:
  for key: String
  for url: String
  for headers: T.ProviderHeaders()
  for payload: T.JsonValue
  for compat: Policy.ResolvedCompat
  for grammar: R.Record<String>
  for retention: T.CacheRetention
  {Default.grammar(Preparation.Prepared{key, url, headers, payload, compat, grammar, retention}) == grammar : R.Record<String>}

law default_pricing_precedes_dependency_retirement:
  for -E: Data
  for owner: Owner.Owner<E>
  for dependencies: IO(Unit)
  {Default.retire(E, owner, dependencies) == IO.bind(Unit, Unit, Owner.dispose(E, owner), ignored => dependencies) : IO(Unit)}

def suppliedPricing(-Reason: Data, -SourceError: Data, -HookError: Data, value: Native.Context<Reason, SourceError, HookError>) -> Pricing.OpenAIResponsesStreamOptions<Errors.Error<Reason, SourceError, HookError>>:
  match value:
    case Native.Context{_, _, _, _, pricing, _, _, _}: pricing

law owned_pricing_reaches_processor_context:
  for -Reason: Data
  for -SourceError: Data
  for -HookError: Data
  for dependencies: Default.Dependencies<Reason, SourceError>
  for pricing: Pricing.OpenAIResponsesStreamOptions<Errors.Error<Reason, SourceError, HookError>>
  {suppliedPricing(Reason, SourceError, HookError, Default.context(Reason, SourceError, HookError, dependencies, pricing)) == pricing : Pricing.OpenAIResponsesStreamOptions<Errors.Error<Reason, SourceError, HookError>>}
