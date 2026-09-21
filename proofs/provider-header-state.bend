import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/provider-header-state.bend as S
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/http-header.bend as H
import ../laws/provider-header-state.bend as Laws
import ../laws/record.bend as RecordLaws
import ./record.bend as RecordProof

def Laws.entries_preserve_first_error(values, cause):
  match values:
    case Nil{}: {==}
    case R.Property{_, _} <> rest: {==}

law empty_entries_preserve_result:
  for initial: Result<&2, &2, H.HeaderError, S.State>
  {S.entries(Nil{}, initial) == initial : Result<&2, &2, H.HeaderError, S.State>}

def empty_entries_preserve_result(initial):
  match initial:
    case Fail{_}: {==}
    case Done{_}: {==}

def Laws.singleton_layer_applies_configuration(layer, initial): {==}

def Laws.singleton_entry_applies_field(state, name, value):
  empty_entries_preserve_result(S.field(state, name, value))

def Laws.latest_setting_is_observable(state, name, value):
  match state:
    case S.State{fields}: RecordLaws.lookup_after_set(T.Nullable<String>, fields, name, value)

def Laws.later_setting_replaces_earlier(state, name, first, second):
  match state:
    case S.State{fields}: Equal.cong(T.ProviderHeaders(), S.State, value => S.State{value}, R.set(T.Nullable<String>, R.set(T.Nullable<String>, fields, name, first), name, second), R.set(T.Nullable<String>, fields, name, second), RecordLaws.set_overwrite(T.Nullable<String>, fields, name, first, second))

def Laws.removal_remains_explicit(state, name):
  Equal.cong(Maybe<&2, T.Nullable<String>>, Bool, S.removed, S.lookup(S.put(state, name, T.NullValue{}), name), Some{T.NullValue{}}, Laws.latest_setting_is_observable(state, name, T.NullValue{}))

def Laws.assignment_clears_removal(state, name, value):
  Equal.cong(Maybe<&2, T.Nullable<String>>, Bool, S.removed, S.lookup(S.put(state, name, T.PresentValue{value}), name), Some{T.PresentValue{value}}, Laws.latest_setting_is_observable(state, name, T.PresentValue{value}))

def Laws.removal_has_no_wire_field(name, values): {==}
def Laws.assignment_retains_wire_value(name, value, values): {==}

def Laws.empty_layers_preserve_result(initial): {==}
def Laws.absent_layer_preserves_result(initial): {==}
def Laws.layers_partition(left, initial, right):
  match left:
    case Nil{}: {==}
    case head <> rest: Laws.layers_partition(rest, S.apply(head, initial), right)

def Laws.materialization_partition(left, right):
  match left:
    case Nil{}: {==}
    case R.Property{name, T.NullValue{}} <> rest: Laws.materialization_partition(rest, right)
    case R.Property{name, T.PresentValue{value}} <> rest:
      %Laws.materialization_partition(rest, right) : {R.Property{name, value <> Nil{}} <> S.materialize(List.append(&2, R.Property<T.Nullable<String>>, rest, right)) == R.Property{name, value <> Nil{}} <> _ : List<&2, R.Property<List<&2, String>>>}
      {==}

def Laws.entries_partition(left, initial, right):
  match left initial:
    case Nil{} Fail{cause}: {==}
    case Nil{} Done{state}: {==}
    case R.Property{_, _} <> rest Fail{cause}:
      Equal.sym(Result<&2, &2, H.HeaderError, S.State>, S.entries(right, Fail{cause}), Fail{cause}, Laws.entries_preserve_first_error(right, cause))
    case R.Property{name, value} <> rest Done{state}: Laws.entries_partition(rest, S.field(state, name, value), right)
