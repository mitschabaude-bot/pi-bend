import Base
import ../packages/ai/src/utils/provider-retry-map.bend as Map
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/runtime/src/f64.bend as F

law failure_identity:
  for -E: Data
  for value: Retry.RequestFailure<E>
  {Map.failure(E, E, cause => cause, value) == value : Retry.RequestFailure<E>}

law failure_composition:
  for -E: Data
  for -G: Data
  for -H: Data
  for first: E -> G
  for second: G -> H
  for value: Retry.RequestFailure<E>
  {Map.failure(G, H, second, Map.failure(E, G, first, value)) == Map.failure(E, H, cause => second(first(cause)), value) : Retry.RequestFailure<H>}

law provider_metadata_retained:
  for -E: Data
  for -G: Data
  for embed: E -> G
  for cause: E
  for message: String
  for status: Maybe<&2, F.F64>
  for hint: Maybe<&2, String>
  for milliseconds: Maybe<&2, String>
  for seconds: Maybe<&2, String>
  {Map.failure(E, G, embed, Retry.Provider{Retry.ProviderError{cause, message, status, hint, milliseconds, seconds}}) == Retry.Provider{Retry.ProviderError{embed(cause), message, status, hint, milliseconds, seconds}} : Retry.RequestFailure<G>}

law terminal_category_retained:
  for -E: Data
  for -G: Data
  for embed: E -> G
  for cause: E
  {Map.failure(E, G, embed, Retry.Other{cause}) == Retry.Other{embed(cause)} : Retry.RequestFailure<G>}

law successful_owner_transfers:
  for -E: Data
  for -G: Data
  for -Owner: Type
  for embed: E -> G
  for owner: Owner
  {Map.result(E, G, Owner, embed, Done{owner}) == Done{owner} : Result<&2, &1, Retry.RequestFailure<G>, Owner>}

law failed_result_lifts_mapping:
  for -E: Data
  for -G: Data
  for -Owner: Type
  for embed: E -> G
  for cause: Retry.RequestFailure<E>
  {Map.result(E, G, Owner, embed, Fail{cause}) == Fail{Map.failure(E, G, embed, cause)} : Result<&2, &1, Retry.RequestFailure<G>, Owner>}
