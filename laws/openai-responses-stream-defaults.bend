import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses-stream-defaults.bend as Defaults
import ../packages/ai/src/api/openai-responses-stream-pricing.bend as Pricing
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/record.bend as R

law borrowing_preserves_owner_and_configuration:
  for -E: Data
  for callback: C.Callback<Pricing.PricingRequest, Result<&2, &2, E, T.Usage>>
  for requested: Maybe<&2, String>
  for grammar: R.Record<String>
  {Defaults.borrow(E, Defaults.Owner{callback}, requested, grammar) == (Defaults.Owner{callback}, Pricing.OpenAIResponsesStreamOptions{requested, Some{grammar}, None{}, Some{callback}}) : Defaults.Owner<E> & Pricing.OpenAIResponsesStreamOptions<E>}

law disposal_retires_owned_pricing_callback:
  for -E: Data
  for callback: C.Callback<Pricing.PricingRequest, Result<&2, &2, E, T.Usage>>
  {Defaults.dispose(E, Defaults.Owner{callback}) == C.dispose(Pricing.PricingRequest, Result<&2, &2, E, T.Usage>, callback) : IO(Unit)}
