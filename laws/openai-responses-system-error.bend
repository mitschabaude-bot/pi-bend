import Base
import ../packages/ai/src/api/openai-responses-system-error.bend as E
import ../packages/ai/src/api/openai-responses-owned-acquire.bend as Acquire

law acquisition_success_transfers_owner_unchanged:
  for -Reason: Data
  for -Hook: Data
  for -Owner: Type
  for owner: Owner
  {E.acquired(Reason, Hook, Owner, Done{owner}) == Done{owner} : Result<&2, &1, E.Error<Reason, Hook>, Owner>}

law acquisition_failure_preserves_complete_typed_cause:
  for -Reason: Data
  for -Hook: Data
  for -Owner: Type
  for cause: Acquire.Error(Reason, Hook)
  {E.acquired(Reason, Hook, Owner, Fail{cause}) == Fail{E.AcquisitionFailure{cause}} : Result<&2, &1, E.Error<Reason, Hook>, Owner>}

law release_failure_preserves_complete_typed_cause:
  for -Reason: Data
  for -Hook: Data
  for cause: Acquire.Inner(Reason, Hook)
  {E.released(Reason, Hook, Fail{cause}) == Fail{E.ReleaseFailure{cause}} : Result<&2, &2, E.Error<Reason, Hook>, Unit>}
