import Base
import ../packages/runtime/src/url.bend as S
import ../packages/runtime/src/url.bend as F
import ../packages/runtime/src/url.bend as P
import ../packages/runtime/src/numeric-host.bend as Host
import ../packages/runtime/src/hosts.bend as Family
import ../packages/runtime/src/url.bend as IPv4
import ../packages/runtime/src/url.bend as IPv6
import ../packages/runtime/src/numeric-host.bend as Scope
import ../packages/runtime/src/ipv6-scope.bend as Zone
import ../packages/runtime/src/socket.bend as Connect

# Url form strict

law decoded_values_are_preserved:
  for field: Nat
  for name: String
  for value: String
  {S.decodedFormStrict(field, Some{name}, Some{value}) == Done{F.Entry{name, value}} : Result<&2, &2, S.FormStrictError, F.Entry>}

law invalid_name_precedes_value:
  for field: Nat
  for value: Maybe<&2, String>
  {S.decodedFormStrict(field, None{}, value) == Fail{S.InvalidName{field}} : Result<&2, &2, S.FormStrictError, F.Entry>}

law invalid_value_retains_position:
  for field: Nat
  for name: String
  {S.decodedFormStrict(field, Some{name}, None{}) == Fail{S.InvalidValue{field}} : Result<&2, &2, S.FormStrictError, F.Entry>}

law prepend_retains_entry:
  for tuple: F.Entry
  for reversed: List<&2, F.Entry>
  {S.prepend(Done{tuple}, reversed) == Done{tuple <> reversed} : Result<&2, &2, S.FormStrictError, List<&2, F.Entry>>}

law prepend_preserves_failure:
  for cause: S.FormStrictError
  for reversed: List<&2, F.Entry>
  {S.prepend(Fail{cause}, reversed) == Fail{cause} : Result<&2, &2, S.FormStrictError, List<&2, F.Entry>>}

law step_preserves_first_failure:
  for field: Nat
  for text: String
  for cause: S.FormStrictError
  {S.step(field, text, Fail{cause}) == Fail{cause} : Result<&2, &2, S.FormStrictError, List<&2, F.Entry>>}

law fields_preserve_first_failure:
  for parts: List<&2, String>
  for field: Nat
  for cause: S.FormStrictError
  {S.fields(parts, field, Fail{cause}) == Fail{cause} : Result<&2, &2, S.FormStrictError, List<&2, F.Entry>>}

law empty_field_preserves_accumulator:
  for field: Nat
  for reversed: List<&2, F.Entry>
  {S.step(field, "", Done{reversed}) == Done{reversed} : Result<&2, &2, S.FormStrictError, List<&2, F.Entry>>}

law finish_preserves_failure:
  for cause: S.FormStrictError
  {S.finishFormStrict(Fail{cause}) == Fail{cause} : Result<&2, &2, S.FormStrictError, List<&2, F.Entry>>}

law query_marker_is_syntax:
  for text: String
  {S.queryFormStrict(SCon{'?', text}) == S.parseFormStrict(text) : Result<&2, &2, S.FormStrictError, List<&2, F.Entry>>}


# Url search params

# Ordered tuples, not object properties: duplicates and position are data.
law names_partition:
  for +left: List<&2, F.Entry>
  for +right: List<&2, F.Entry>
  {P.names(List.append(&2, F.Entry, left, right)) == List.append(&2, String, P.names(left), P.names(right)) : List<&2, String>}

law values_partition:
  for +left: List<&2, F.Entry>
  for +right: List<&2, F.Entry>
  {P.contents(List.append(&2, F.Entry, left, right)) == List.append(&2, String, P.contents(left), P.contents(right)) : List<&2, String>}

law normalization_partition:
  for +left: List<&2, F.Entry>
  for +right: List<&2, F.Entry>
  {P.normalizedSearchParams(List.append(&2, F.Entry, left, right)) == List.append(&2, F.Entry, P.normalizedSearchParams(left), P.normalizedSearchParams(right)) : List<&2, F.Entry>}

law names_retain_head:
  for name: String
  for value: String
  for rest: List<&2, F.Entry>
  {P.names(F.Entry{name, value} <> rest) == name <> P.names(rest) : List<&2, String>}

law values_retain_head:
  for name: String
  for value: String
  for rest: List<&2, F.Entry>
  {P.contents(F.Entry{name, value} <> rest) == value <> P.contents(rest) : List<&2, String>}

law append_preserves_prefix:
  for +params: P.URLSearchParams
  for +name: String
  for +value: String
  {P.entries(P.append(params, name, value)) == List.append(&2, F.Entry, P.entries(params), F.normalize(F.Entry{name, value}) <> Nil{}) : List<&2, F.Entry>}

law remove_matching_head:
  for +entry: F.Entry
  for rest: List<&2, F.Entry>
  for +name: String
  for +value: Maybe<&2, String>
  for matches: {P.matches(entry, name, value) == True{} : Bool}
  {P.remove(entry <> rest, name, value) == P.remove(rest, name, value) : List<&2, F.Entry>}

law remove_preserves_other_head:
  for +entry: F.Entry
  for rest: List<&2, F.Entry>
  for +name: String
  for +value: Maybe<&2, String>
  for different: {P.matches(entry, name, value) == False{} : Bool}
  {P.remove(entry <> rest, name, value) == entry <> P.remove(rest, name, value) : List<&2, F.Entry>}

law empty_lookup:
  for name: String
  {P.get(P.new(), name) == None{} : Maybe<&2, String>}

law remove_idempotent:
  for +entries: List<&2, F.Entry>
  for +name: String
  for +value: Maybe<&2, String>
  {P.remove(P.remove(entries, name, value), name, value) == P.remove(entries, name, value) : List<&2, F.Entry>}


# Numeric host

law unrestricted_preserves_input:
  for +input: Host.Input
  {Host.selected(Family.Any{}, input) == Done{input} : Result<&2, &2, Host.Error, Host.Input>}

law ipv4_preserves_address:
  for +address: IPv4.Address
  {Host.selected(Family.IPv4Only{}, Host.V4{address}) == Done{Host.V4{address}} : Result<&2, &2, Host.Error, Host.Input>}

law ipv6_preserves_address_and_zone:
  for +address: IPv6.Ipv6Address
  for +zone: Maybe<&2, String>
  {Host.selected(Family.IPv6Only{}, Host.V6{address, zone}) == Done{Host.V6{address, zone}} : Result<&2, &2, Host.Error, Host.Input>}

law ipv4_rejects_ipv6:
  for address: IPv6.Ipv6Address
  for zone: Maybe<&2, String>
  {Host.selected(Family.IPv4Only{}, Host.V6{address, zone}) == Fail{Host.FamilyMismatch{}} : Result<&2, &2, Host.Error, Host.Input>}

law ipv6_rejects_ipv4:
  for address: IPv4.Address
  {Host.selected(Family.IPv6Only{}, Host.V4{address}) == Fail{Host.FamilyMismatch{}} : Result<&2, &2, Host.Error, Host.Input>}

law failed_parse_retained:
  for family: Family.Family
  for +error: Host.Error
  {Host.accepted(family, Fail{error}) == Fail{error} : Result<&2, &2, Host.Error, Host.Input>}


# Numeric scope

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
  for +address: IPv6.Ipv6Address
  {Scope.plan(E, Done{Host.V6{address, None{}}}) == Scope.Ready{Done{Connect.V6{address, 0}}} : Scope.Plan<E>}

law scoped_ipv6_retains_request:
  for -E: Data
  for +address: IPv6.Ipv6Address
  for +zone: String
  {Scope.plan(E, Done{Host.V6{address, Some{zone}}}) == Scope.ResolveZone{address, zone} : Scope.Plan<E>}

law failed_scope_is_terminal:
  for -E: Data
  for address: IPv6.Ipv6Address
  for +error: Zone.Error<E>
  {Scope.resolved(E, address, Fail{error}) == Fail{Scope.InvalidScope{error}} : Result<&2, &2, Scope.ScopeError<E>, Connect.Address>}

law successful_scope_retained:
  for -E: Data
  for +address: IPv6.Ipv6Address
  for +index: U32
  {Scope.resolved(E, address, Done{index}) == Done{Connect.V6{address, index}} : Result<&2, &2, Scope.ScopeError<E>, Connect.Address>}
