import Base
import ../types.bend as T
import ./openai-responses-service-tier.bend as Tier
import ./openai-responses-stream-pricing.bend as Pricing
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/callback.bend as C

# The provider owns its default pricing callback; stream processing borrows it.
# Keep the affine owner separate from the freely reusable options value.
type Owner<-E: Data> is Type:
  Owner{pricing: C.Callback<Pricing.PricingRequest, Result<&2, &2, E, T.Usage>>}

def options(-E: Data, requested: Maybe<&2, String>, grammar: R.Record<String>, callback: C.Callback<Pricing.PricingRequest, Result<&2, &2, E, T.Usage>>) -> Pricing.OpenAIResponsesStreamOptions<E>:
  Pricing.OpenAIResponsesStreamOptions{requested, Some{grammar}, None{}, Some{callback}}

def borrow(-E: Data, owner: Owner<E>, requested: Maybe<&2, String>, grammar: R.Record<String>) -> Owner<E> & Pricing.OpenAIResponsesStreamOptions<E>:
  match owner:
    case Owner{+callback}: (Owner{callback}, options(E, requested, grammar, callback))

def create(~E: Data, modelId: String) -> IO(Owner<E>):
  do IO<Owner<E>>:
    callback : C.Callback<Pricing.PricingRequest, Result<&2, &2, E, T.Usage>> <- Tier.create(~E, modelId)
    return Owner{callback}

# Run after processing has stopped borrowing the options, including failure.
def dispose(-E: Data, owner: Owner<E>) -> IO(Unit):
  match owner:
    case Owner{callback}: C.dispose(Pricing.PricingRequest, Result<&2, &2, E, T.Usage>, callback)
