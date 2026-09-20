import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/provider-request.bend as Request
import ../packages/ai/src/utils/provider-retry.bend as Retry

law absent_replacement_retains_payload:
  for -P: Data
  for -E: Data
  for original: P
  {Request.selected(P, E, original, Done{None{}}) == Done{original} : Result<&2, &2, Request.Error<E>, P>}

law present_replacement_is_exact:
  for -P: Data
  for -E: Data
  for original: P
  for replacement: P
  {Request.selected(P, E, original, Done{Some{replacement}}) == Done{replacement} : Result<&2, &2, Request.Error<E>, P>}

law payload_failure_is_preserved:
  for -P: Data
  for -E: Data
  for original: P
  for cause: E
  {Request.selected(P, E, original, Fail{cause}) == Fail{Request.PayloadFailure{cause}} : Result<&2, &2, Request.Error<E>, P>}

law absent_payload_hook_has_no_effects:
  for -P: Data
  for -M: Data
  for -E: Data
  for original: P
  for model: M
  {Request.payload(P, M, E, original, model, None{}) == IO.pure(Result<&2, &2, Request.Error<E>, P>, Done{original}) : IO(Result<&2, &2, Request.Error<E>, P>)}

law successful_response_hook_retains_owner:
  for -E: Data
  for -Owner: Type
  for release: Owner -> IO(Result<&2, &2, E, Unit>)
  for owner: Owner
  {Request.responseResult(E, Owner, release, owner, Done{Unit{}}) == IO.pure(Result<&2, &1, Request.Error<E>, Owner>, Done{owner}) : IO(Result<&2, &1, Request.Error<E>, Owner>)}

law failed_response_hook_retires_owner_first:
  for -E: Data
  for -Owner: Type
  for release: Owner -> IO(Result<&2, &2, E, Unit>)
  for owner: Owner
  for cause: E
  {Request.responseResult(E, Owner, release, owner, Fail{cause}) == IO.bind(Result<&2, &2, E, Unit>, Result<&2, &1, Request.Error<E>, Owner>, release(owner), cleanup => IO.pure(Result<&2, &1, Request.Error<E>, Owner>, Fail{Request.ResponseFailure{cause, cleanup}})) : IO(Result<&2, &1, Request.Error<E>, Owner>)}

law failed_request_bypasses_response_hook:
  for -M: Data
  for -E: Data
  for -Owner: Type
  for model: M
  for hook: Maybe<&2, T.ResponseCallback(M, E)>
  for inspect: Owner -> Owner & T.ProviderResponse
  for release: Owner -> IO(Result<&2, &2, E, Unit>)
  for cause: Retry.RetryFailure<E>
  {Request.response(M, E, Owner, model, hook, inspect, release, Fail{cause}) == IO.pure(Result<&2, &1, Request.Error<E>, Owner>, Fail{Request.RequestFailure{cause}}) : IO(Result<&2, &1, Request.Error<E>, Owner>)}

law absent_response_hook_retains_owner_without_effects:
  for -M: Data
  for -E: Data
  for -Owner: Type
  for model: M
  for inspect: Owner -> Owner & T.ProviderResponse
  for release: Owner -> IO(Result<&2, &2, E, Unit>)
  for owner: Owner
  {Request.response(M, E, Owner, model, None{}, inspect, release, Done{owner}) == IO.pure(Result<&2, &1, Request.Error<E>, Owner>, Done{owner}) : IO(Result<&2, &1, Request.Error<E>, Owner>)}
