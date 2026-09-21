import Base
import ./provider-retry.bend as Retry

# Embed the original typed cause without reconstructing retry policy. Every
# provider message/status/hint remains exactly the value supplied by the source.
def failure(-E: Data, -F: Data, embed: E -> F, value: Retry.RequestFailure<E>) -> Retry.RequestFailure<F>:
  match value:
    case Retry.Other{cause}: Retry.Other{embed(cause)}
    case Retry.Provider{Retry.ProviderError{cause, message, status, hint, milliseconds, seconds}}:
      Retry.Provider{Retry.ProviderError{embed(cause), message, status, hint, milliseconds, seconds}}

# A successful affine owner transfers untouched; its type does not depend on
# the error embedding and no inspection or cleanup effect occurs here.
def result(-E: Data, -F: Data, -Owner: Type, embed: E -> F, value: Result<&2, &1, Retry.RequestFailure<E>, Owner>) -> Result<&2, &1, Retry.RequestFailure<F>, Owner>:
  match value:
    case Fail{cause}: Fail{failure(E, F, embed, cause)}
    case Done{owner}: Done{owner}
