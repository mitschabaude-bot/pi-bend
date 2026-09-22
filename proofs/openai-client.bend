import Base
import ../packages/ai/src/api/openai-client.bend as Client
import ../laws/openai-client.bend as Laws
import ../packages/ai/src/types.bend as T
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/http-message.bend as H
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response.bend as Metadata
import ../laws/record.bend as RecordLaws
import ./record.bend as RecordProof

law disjunction_commutes:
  for +left: Bool
  for +right: Bool
  {Bool.or(left, right) == Bool.or(right, left) : Bool}

def disjunction_commutes(left, right):
  match left right:
    case False{} False{}: {==}
    case False{} True{}: {==}
    case True{} False{}: {==}
    case True{} True{}: {==}

def Laws.explicit_timeout_is_retained(value): {==}
def Laws.noninteger_timeout_is_rejected(value): {==}
def Laws.header_failure_preserves_cause(cause): {==}
def Laws.failed_authentication_has_no_headers(state): {==}
def Laws.accepted_authentication_preserves_headers(state): {==}
def Laws.removal_allows_authentication_override(other): {==}
def Laws.authentication_methods_are_interchangeable(authorization, apiKey):
  disjunction_commutes(Client.credentialAllows(authorization), Client.credentialAllows(apiKey))
def Laws.nonempty_credential_allows_authentication(head, tail, other): {==}
def Laws.absent_credentials_are_rejected(): {==}
def Laws.timeout_failure_bypasses_header_construction(configuration, apiKey, retryCount, client, body, request, cause): {==}
def Laws.diagnostic_read_failure_retains_cause(E, metadata, cause): {==}
def Laws.construction_retains_diagnostic(E, metadata, diagnostic, text): {==}
def Laws.encoding_failure_retains_diagnostic(E, metadata, diagnostic): {==}
def Laws.present_error_is_selected(fallback, error): {==}
def Laws.unrecognized_json_is_retained(value): {==}
def Laws.nonempty_message_text_is_retained(whole, head, tail): {==}
def Laws.text_normalization_preserves_rendered_message(metadata, text, message): {==}
def Laws.json_normalization_retains_input(metadata, value, message): {==}
def Laws.nonretryable_failures_stay_application_errors(E, original): {==}
def Laws.connection_failures_are_retryable(E, original): {==}
def Laws.expired_deadlines_are_retryable_timeouts(Reason, E, original): {==}
def Laws.parent_cancellation_is_never_retried(Reason, E, original, why): {==}
def Laws.cancellation_overrides_the_transport_category(Reason, E, original, why): {==}
def Laws.invalid_timeouts_are_never_retried(Reason, cause): {==}

def Laws.entries_preserve_first_error(values, cause):
  match values:
    case Nil{}: {==}
    case R.Property{_, _} <> rest: {==}

law empty_entries_preserve_result:
  for initial: Result<&2, &2, H.HeaderHeaderError, Client.HeaderState>
  {Client.layerEntries(Nil{}, initial) == initial : Result<&2, &2, H.HeaderHeaderError, Client.HeaderState>}

def empty_entries_preserve_result(initial):
  match initial:
    case Fail{_}: {==}
    case Done{_}: {==}

def Laws.singleton_layer_applies_configuration(layer, initial): {==}

def Laws.singleton_entry_applies_field(state, name, value):
  empty_entries_preserve_result(Client.layerField(state, name, value))

def Laws.latest_setting_is_observable(state, name, value):
  match state:
    case Client.HeaderState{fields}: RecordLaws.lookup_after_set(T.Nullable<String>, fields, name, value)

def Laws.later_setting_replaces_earlier(state, name, first, second):
  match state:
    case Client.HeaderState{fields}: Equal.cong(T.ProviderHeaders(), Client.HeaderState, value => Client.HeaderState{value}, R.set(T.Nullable<String>, R.set(T.Nullable<String>, fields, name, first), name, second), R.set(T.Nullable<String>, fields, name, second), RecordLaws.set_overwrite(T.Nullable<String>, fields, name, first, second))

def Laws.removal_remains_explicit(state, name):
  Equal.cong(Maybe<&2, T.Nullable<String>>, Bool, Client.removed, Client.lookup(Client.put(state, name, T.NullValue{}), name), Some{T.NullValue{}}, Laws.latest_setting_is_observable(state, name, T.NullValue{}))

def Laws.assignment_clears_removal(state, name, value):
  Equal.cong(Maybe<&2, T.Nullable<String>>, Bool, Client.removed, Client.lookup(Client.put(state, name, T.PresentValue{value}), name), Some{T.PresentValue{value}}, Laws.latest_setting_is_observable(state, name, T.PresentValue{value}))

def Laws.removal_has_no_wire_field(name, values): {==}
def Laws.assignment_retains_wire_value(name, value, values): {==}

def Laws.empty_layers_preserve_result(initial): {==}
def Laws.absent_layer_preserves_result(initial): {==}
def Laws.layers_partition(left, initial, right):
  match left:
    case Nil{}: {==}
    case head <> rest: Laws.layers_partition(rest, Client.applyLayer(head, initial), right)

def Laws.materialization_partition(left, right):
  match left:
    case Nil{}: {==}
    case R.Property{name, T.NullValue{}} <> rest: Laws.materialization_partition(rest, right)
    case R.Property{name, T.PresentValue{value}} <> rest:
      %Laws.materialization_partition(rest, right) : {R.Property{name, value <> Nil{}} <> Client.materialize(List.append(&2, R.Property<T.Nullable<String>>, rest, right)) == R.Property{name, value <> Nil{}} <> _ : List<&2, R.Property<List<&2, String>>>}
      {==}

def Laws.entries_partition(left, initial, right):
  match left initial:
    case Nil{} Fail{cause}: {==}
    case Nil{} Done{state}: {==}
    case R.Property{_, _} <> rest Fail{cause}:
      Equal.sym(Result<&2, &2, H.HeaderHeaderError, Client.HeaderState>, Client.layerEntries(right, Fail{cause}), Fail{cause}, Laws.entries_preserve_first_error(right, cause))
    case R.Property{name, value} <> rest Done{state}: Laws.entries_partition(rest, Client.layerField(state, name, value), right)

def Laws.accepted_owner_has_no_body_io(E, State, read, close, limit, metadata, body, accepted):
  Equal.cong(Bool, IO(Result<&2, &1, Client.StatusFailure<E>, Response.Response<State>>), successful => Client.select(E, State, read, close, limit, metadata, body, successful), Metadata.ok(metadata), True{}, accepted)

def Laws.retry_metadata_projection(E, original, message, major, minor, status, reason, raw, fields, expose): {==}

def Laws.rejected_owner_runs_diagnostic_first(E, State, read, close, limit, metadata, body, rejected):
  Equal.cong(Bool, IO(Result<&2, &1, Client.StatusFailure<E>, Response.Response<State>>), successful => Client.select(E, State, read, close, limit, metadata, body, successful), Metadata.ok(metadata), False{}, rejected)
