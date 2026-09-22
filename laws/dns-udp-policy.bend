import Base
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-message.bend as Edns
import ../packages/runtime/src/dns-transport.bend as Policy

law server_failure_retries:
  for empty: Bool
  for truncated: Bool
  for ignore: Bool
  {Policy.decide(Policy.FailureCode{}, empty, truncated, ignore) == Policy.Retry{Policy.ServerFailure{}} : Policy.UdpPolicyDecision}

law not_implemented_retries:
  for empty: Bool
  for truncated: Bool
  for ignore: Bool
  {Policy.decide(Policy.NotImplementedCode{}, empty, truncated, ignore) == Policy.Retry{Policy.NotImplemented{}} : Policy.UdpPolicyDecision}

law refusal_retries:
  for empty: Bool
  for truncated: Bool
  for ignore: Bool
  {Policy.decide(Policy.RefusedCode{}, empty, truncated, ignore) == Policy.Retry{Policy.Refused{}} : Policy.UdpPolicyDecision}

law unhelpful_success_retries:
  for truncated: Bool
  for ignore: Bool
  {Policy.decide(Policy.Success{}, True{}, truncated, ignore) == Policy.Retry{Policy.UnhelpfulEmpty{}} : Policy.UdpPolicyDecision}

# Other statuses retain their result regardless of the empty-answer heuristic.
law other_status_not_empty_failure:
  for +code: U32
  for empty: Bool
  for +truncated: Bool
  for +ignore: Bool
  {Policy.decide(Policy.Other{code}, empty, truncated, ignore) == Policy.decide(Policy.Other{code}, False{}, truncated, ignore) : Policy.UdpPolicyDecision}

law truncation_uses_tcp:
  for code: U32
  for empty: Bool
  {Policy.decide(Policy.Other{code}, empty, True{}, False{}) == Policy.UseTCP{} : Policy.UdpPolicyDecision}

law ignore_truncation_accepts:
  for code: U32
  for empty: Bool
  for truncated: Bool
  {Policy.decide(Policy.Other{code}, empty, truncated, True{}) == Policy.Accept{} : Policy.UdpPolicyDecision}

law useful_success_matches_other:
  for code: U32
  for +truncated: Bool
  for +ignore: Bool
  {Policy.decide(Policy.Success{}, False{}, truncated, ignore) == Policy.decide(Policy.Other{code}, False{}, truncated, ignore) : Policy.UdpPolicyDecision}

law invalid_extension_stops_policy:
  for header: Message.Header
  for ignore: Bool
  for +error: Edns.EdnsResponseError
  {Policy.inspectedUdpPolicy(header, ignore, Fail{error}) == Fail{error} : Result<&2, &2, Edns.EdnsResponseError, Policy.UdpPolicyDecision>}
