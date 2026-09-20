import Base
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-edns-response.bend as Edns
import ../packages/runtime/src/dns-udp-policy.bend as Policy

law server_failure_retries:
  for empty: Bool
  for truncated: Bool
  for ignore: Bool
  {Policy.decide(Policy.FailureCode{}, empty, truncated, ignore) == Policy.Retry{Policy.ServerFailure{}} : Policy.Decision}

law not_implemented_retries:
  for empty: Bool
  for truncated: Bool
  for ignore: Bool
  {Policy.decide(Policy.NotImplementedCode{}, empty, truncated, ignore) == Policy.Retry{Policy.NotImplemented{}} : Policy.Decision}

law refusal_retries:
  for empty: Bool
  for truncated: Bool
  for ignore: Bool
  {Policy.decide(Policy.RefusedCode{}, empty, truncated, ignore) == Policy.Retry{Policy.Refused{}} : Policy.Decision}

law unhelpful_success_retries:
  for truncated: Bool
  for ignore: Bool
  {Policy.decide(Policy.Success{}, True{}, truncated, ignore) == Policy.Retry{Policy.UnhelpfulEmpty{}} : Policy.Decision}

# Other statuses retain their result regardless of the empty-answer heuristic.
law other_status_not_empty_failure:
  for +code: U32
  for empty: Bool
  for +truncated: Bool
  for +ignore: Bool
  {Policy.decide(Policy.Other{code}, empty, truncated, ignore) == Policy.decide(Policy.Other{code}, False{}, truncated, ignore) : Policy.Decision}

law truncation_uses_tcp:
  for code: U32
  for empty: Bool
  {Policy.decide(Policy.Other{code}, empty, True{}, False{}) == Policy.UseTCP{} : Policy.Decision}

law ignore_truncation_accepts:
  for code: U32
  for empty: Bool
  for truncated: Bool
  {Policy.decide(Policy.Other{code}, empty, truncated, True{}) == Policy.Accept{} : Policy.Decision}

law useful_success_matches_other:
  for code: U32
  for +truncated: Bool
  for +ignore: Bool
  {Policy.decide(Policy.Success{}, False{}, truncated, ignore) == Policy.decide(Policy.Other{code}, False{}, truncated, ignore) : Policy.Decision}

law invalid_extension_stops_policy:
  for header: Message.Header
  for ignore: Bool
  for +error: Edns.Error
  {Policy.inspected(header, ignore, Fail{error}) == Fail{error} : Result<&2, &2, Edns.Error, Policy.Decision>}
