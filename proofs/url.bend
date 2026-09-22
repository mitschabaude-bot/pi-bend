import Base
import ../laws/url.bend as Laws
import ../packages/runtime/src/url.bend as P
import ../packages/runtime/src/url.bend as F
import ../packages/runtime/src/numeric-host.bend as Host

# Url form strict

def Laws.decoded_values_are_preserved(field, name, value): {==}
def Laws.invalid_name_precedes_value(field, value): {==}
def Laws.invalid_value_retains_position(field, name): {==}
def Laws.prepend_retains_entry(tuple, reversed): {==}
def Laws.prepend_preserves_failure(cause, reversed): {==}
def Laws.step_preserves_first_failure(field, text, cause):
  match text:
    case SNil{}: {==}
    case SCon{_, _}: {==}
def Laws.fields_preserve_first_failure(parts, field, cause):
  match parts:
    case Nil{}: {==}
    case _ <> _: {==}
def Laws.empty_field_preserves_accumulator(field, reversed): {==}
def Laws.finish_preserves_failure(cause): {==}
def Laws.query_marker_is_syntax(text): {==}


# Url search params

def Laws.names_retain_head(name, value, rest): {==}
def Laws.values_retain_head(name, value, rest): {==}
def Laws.append_preserves_prefix(params, name, value): {==}
def Laws.empty_lookup(name): {==}

def Laws.remove_matching_head(entry, rest, name, value, matches):
  %Equal.sym(Bool, P.matches(entry, name, value), True{}, matches) : {Bool.pick(List<&2, F.Entry>, _, P.remove(rest, name, value), entry <> P.remove(rest, name, value)) == P.remove(rest, name, value) : List<&2, F.Entry>}
  {==}

def Laws.remove_preserves_other_head(entry, rest, name, value, different):
  %Equal.sym(Bool, P.matches(entry, name, value), False{}, different) : {Bool.pick(List<&2, F.Entry>, _, P.remove(rest, name, value), entry <> P.remove(rest, name, value)) == entry <> P.remove(rest, name, value) : List<&2, F.Entry>}
  {==}

def Laws.names_partition(left, right):
  match left:
    case Nil{}: {==}
    case F.Entry{name, _} <> rest:
      %Laws.names_partition(rest, right) : {name <> P.names(List.append(&2, F.Entry, rest, right)) == name <> _ : List<&2, String>}
      {==}

def Laws.values_partition(left, right):
  match left:
    case Nil{}: {==}
    case F.Entry{_, value} <> rest:
      %Laws.values_partition(rest, right) : {value <> P.contents(List.append(&2, F.Entry, rest, right)) == value <> _ : List<&2, String>}
      {==}

def Laws.normalization_partition(left, right):
  match left:
    case Nil{}: {==}
    case entry <> rest:
      %Laws.normalization_partition(rest, right) : {F.normalize(entry) <> P.normalizedSearchParams(List.append(&2, F.Entry, rest, right)) == F.normalize(entry) <> _ : List<&2, F.Entry>}
      {==}

law filtered_head_twice:
  for +entry: F.Entry
  for +rest: List<&2, F.Entry>
  for +name: String
  for +value: Maybe<&2, String>
  for +same: Bool
  for equal: {same == P.matches(entry, name, value) : Bool}
  for unchanged: {P.remove(rest, name, value) == rest : List<&2, F.Entry>}
  {P.remove(Bool.pick(List<&2, F.Entry>, same, rest, entry <> rest), name, value) == Bool.pick(List<&2, F.Entry>, same, rest, entry <> rest) : List<&2, F.Entry>}

def filtered_head_twice(entry, rest, name, value, same, equal, unchanged):
  match same:
    case True{}: unchanged
    case False{}:
      %equal : {Bool.pick(List<&2, F.Entry>, _, P.remove(rest, name, value), entry <> P.remove(rest, name, value)) == entry <> rest : List<&2, F.Entry>}
      Equal.cong(List<&2, F.Entry>, List<&2, F.Entry>, tail => entry <> tail, P.remove(rest, name, value), rest, unchanged)

def Laws.remove_idempotent(entries, name, value):
  match entries:
    case Nil{}: {==}
    case +entry <> +rest:
      filtered_head_twice(entry, P.remove(rest, name, value), name, value, P.matches(entry, name, value), {==}, Laws.remove_idempotent(rest, name, value))


# Numeric host

def Laws.unrestricted_preserves_input(input):
  match input:
    case Host.V4{address}: {==}
    case Host.V6{address, zone}: {==}
def Laws.ipv4_preserves_address(address): {==}
def Laws.ipv6_preserves_address_and_zone(address, zone): {==}
def Laws.ipv4_rejects_ipv6(address, zone): {==}
def Laws.ipv6_rejects_ipv4(address): {==}
def Laws.failed_parse_retained(family, error): {==}


# Numeric scope

def Laws.failed_input_needs_no_lookup(E, error): {==}
def Laws.ipv4_needs_no_lookup(E, address): {==}
def Laws.unscoped_ipv6_needs_no_lookup(E, address): {==}
def Laws.scoped_ipv6_retains_request(E, address, zone): {==}
def Laws.failed_scope_is_terminal(E, address, error): {==}
def Laws.successful_scope_retained(E, address, index): {==}
