import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/provider-header-state.bend as S
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/http-header.bend as H

law layers_partition:
  for +left: List<&2, Maybe<&2, T.ProviderHeaders()>>
  for +initial: Result<&2, &2, H.HeaderError, S.State>
  for +right: List<&2, Maybe<&2, T.ProviderHeaders()>>
  {S.layers(List.append(&2, Maybe<&2, T.ProviderHeaders()>, left, right), initial) == S.layers(right, S.layers(left, initial)) : Result<&2, &2, H.HeaderError, S.State>}

law empty_layers_preserve_result:
  for initial: Result<&2, &2, H.HeaderError, S.State>
  {S.layers(Nil{}, initial) == initial : Result<&2, &2, H.HeaderError, S.State>}

law absent_layer_preserves_result:
  for initial: Result<&2, &2, H.HeaderError, S.State>
  {S.apply(None{}, initial) == initial : Result<&2, &2, H.HeaderError, S.State>}

law entries_preserve_first_error:
  for values: List<&2, R.Property<T.Nullable<String>>>
  for cause: H.HeaderError
  {S.entries(values, Fail{cause}) == Fail{cause} : Result<&2, &2, H.HeaderError, S.State>}

law latest_setting_is_observable:
  for state: S.State
  for +name: String
  for +value: T.Nullable<String>
  {S.lookup(S.put(state, name, value), name) == Some{value} : Maybe<&2, T.Nullable<String>>}

law later_setting_replaces_earlier:
  for +state: S.State
  for +name: String
  for first: T.Nullable<String>
  for +second: T.Nullable<String>
  {S.put(S.put(state, name, first), name, second) == S.put(state, name, second) : S.State}

law removal_remains_explicit:
  for state: S.State
  for +name: String
  {S.removed(S.lookup(S.put(state, name, T.NullValue{}), name)) == True{} : Bool}

law assignment_clears_removal:
  for state: S.State
  for +name: String
  for value: String
  {S.removed(S.lookup(S.put(state, name, T.PresentValue{value}), name)) == False{} : Bool}

law materialization_partition:
  for +left: List<&2, R.Property<T.Nullable<String>>>
  for +right: List<&2, R.Property<T.Nullable<String>>>
  {S.materialize(List.append(&2, R.Property<T.Nullable<String>>, left, right)) == List.append(&2, R.Property<List<&2, String>>, S.materialize(left), S.materialize(right)) : List<&2, R.Property<List<&2, String>>>}

law removal_has_no_wire_field:
  for name: String
  for values: List<&2, R.Property<T.Nullable<String>>>
  {S.materialize(R.Property{name, T.NullValue{}} <> values) == S.materialize(values) : List<&2, R.Property<List<&2, String>>>}

law assignment_retains_wire_value:
  for name: String
  for value: String
  for values: List<&2, R.Property<T.Nullable<String>>>
  {S.materialize(R.Property{name, T.PresentValue{value}} <> values) == R.Property{name, value <> Nil{}} <> S.materialize(values) : List<&2, R.Property<List<&2, String>>>}

law singleton_layer_applies_configuration:
  for layer: Maybe<&2, T.ProviderHeaders()>
  for initial: Result<&2, &2, H.HeaderError, S.State>
  {S.layers(layer <> Nil{}, initial) == S.apply(layer, initial) : Result<&2, &2, H.HeaderError, S.State>}

law singleton_entry_applies_field:
  for state: S.State
  for name: String
  for value: T.Nullable<String>
  {S.entries(R.Property{name, value} <> Nil{}, Done{state}) == S.field(state, name, value) : Result<&2, &2, H.HeaderError, S.State>}

law entries_partition:
  for +left: List<&2, R.Property<T.Nullable<String>>>
  for +initial: Result<&2, &2, H.HeaderError, S.State>
  for +right: List<&2, R.Property<T.Nullable<String>>>
  {S.entries(List.append(&2, R.Property<T.Nullable<String>>, left, right), initial) == S.entries(right, S.entries(left, initial)) : Result<&2, &2, H.HeaderError, S.State>}
