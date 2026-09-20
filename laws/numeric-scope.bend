import Base
import ../packages/runtime/src/numeric-scope.bend as Scope
import ../packages/runtime/src/numeric-host.bend as Host
import ../packages/runtime/src/ipv6-scope.bend as Zone
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/url-ipv6.bend as IPv6
import ../packages/runtime/src/abortable-connect.bend as Connect

law failed_input_needs_no_lookup:
  for -E: Data
  for +error: Host.Error
  {Scope.plan(E, Fail{error}) == Scope.Ready{Fail{Scope.InvalidInput{error}}} : Scope.Plan<E>}

law ipv4_needs_no_lookup:
  for -E: Data
  for +address: IPv4.Address
  {Scope.plan(E, Done{Host.V4{address}}) == Scope.Ready{Done{Connect.V4{address}}} : Scope.Plan<E>}

law unscoped_ipv6_needs_no_lookup:
  for -E: Data
  for +address: IPv6.Address
  {Scope.plan(E, Done{Host.V6{address, None{}}}) == Scope.Ready{Done{Connect.V6{address, 0}}} : Scope.Plan<E>}

law scoped_ipv6_retains_request:
  for -E: Data
  for +address: IPv6.Address
  for +zone: String
  {Scope.plan(E, Done{Host.V6{address, Some{zone}}}) == Scope.ResolveZone{address, zone} : Scope.Plan<E>}

law failed_scope_is_terminal:
  for -E: Data
  for address: IPv6.Address
  for +error: Zone.Error<E>
  {Scope.resolved(E, address, Fail{error}) == Fail{Scope.InvalidScope{error}} : Result<&2, &2, Scope.Error<E>, Connect.Address>}

law successful_scope_retained:
  for -E: Data
  for +address: IPv6.Address
  for +index: U32
  {Scope.resolved(E, address, Done{index}) == Done{Connect.V6{address, index}} : Result<&2, &2, Scope.Error<E>, Connect.Address>}
