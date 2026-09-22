import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-client.bend as Client
import ../packages/ai/src/utils/error-body.bend as Body
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/http-response.bend as Consume
import ../packages/runtime/src/http-message.bend as H
import ../packages/runtime/src/http-response.bend as Metadata
import ../packages/runtime/src/http-message.bend as Headers
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/http-response.bend as Ops
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response.bend as Stream
import ../packages/runtime/src/http-response.bend as Progress
import ../packages/runtime/src/http-message.bend as Head
import ../packages/runtime/src/http-message.bend as Status
import ../packages/runtime/src/http-message.bend as Header
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/record.bend as Record
import ../packages/runtime/src/timer.bend as Duration

# Request headers: the SDK's timeout validation and authentication policy.

law explicit_timeout_is_retained:
  for value: F.F64
  {Client.effectiveTimeout(Some{value}) == value : F.F64}

law noninteger_timeout_is_rejected:
  for value: F.F64
  {Client.checkedTimeout(value, False{}) == Fail{Client.TimeoutNotInteger{value}} : Result<&2, &2, Client.HeaderError, F.F64>}

law header_failure_preserves_cause:
  for cause: H.HeaderHeaderError
  {Client.assembled(Fail{cause}) == Fail{Client.HeaderFailure{cause}} : Result<&2, &2, Client.HeaderError, Headers.Headers>}

law failed_authentication_has_no_headers:
  for state: Client.HeaderState
  {Client.authenticate(state, False{}) == Fail{Client.MissingAuthentication{}} : Result<&2, &2, Client.HeaderError, Headers.Headers>}

law accepted_authentication_preserves_headers:
  for state: Client.HeaderState
  {Client.authenticate(state, True{}) == Done{Client.wireHeaders(state)} : Result<&2, &2, Client.HeaderError, Headers.Headers>}

law removal_allows_authentication_override:
  for other: Maybe<&2, T.Nullable<String>>
  {Client.authenticationAllowed(Some{T.NullValue{}}, other) == True{} : Bool}

law authentication_methods_are_interchangeable:
  for +authorization: Maybe<&2, T.Nullable<String>>
  for +apiKey: Maybe<&2, T.Nullable<String>>
  {Client.authenticationAllowed(authorization, apiKey) == Client.authenticationAllowed(apiKey, authorization) : Bool}

law nonempty_credential_allows_authentication:
  for head: Char
  for tail: String
  for other: Maybe<&2, T.Nullable<String>>
  {Client.authenticationAllowed(Some{T.PresentValue{SCon{head, tail}}}, other) == True{} : Bool}

law absent_credentials_are_rejected:
  {Client.authenticationAllowed(None{}, None{}) == False{} : Bool}

law timeout_failure_bypasses_header_construction:
  for configuration: Client.Defaults
  for apiKey: String
  for retryCount: Nat
  for client: Maybe<&2, T.ProviderHeaders()>
  for body: Maybe<&2, T.ProviderHeaders()>
  for request: Maybe<&2, T.ProviderHeaders()>
  for cause: Client.HeaderError
  {Client.validated(configuration, apiKey, retryCount, client, body, request, Fail{cause}) == Fail{cause} : Result<&2, &2, Client.HeaderError, Headers.Headers>}

# APIError: every diagnostic and construction failure keeps its evidence.

law diagnostic_read_failure_retains_cause:
  for -E: Data
  for metadata: Metadata.Metadata
  for cause: Consume.TextError<E>
  {Client.fromResponse(E, Client.StatusFailure{metadata, Fail{cause}}) == Fail{Client.DiagnosticReadFailure{metadata, cause}} : Result<&2, &2, Client.ConstructionError<E>, Client.APIError>}

law construction_retains_diagnostic:
  for -E: Data
  for metadata: Metadata.Metadata
  for diagnostic: Client.Diagnostic
  for text: String
  {Client.constructed(E, metadata, diagnostic, Some{text}) == Done{Client.APIError{metadata, diagnostic, Client.statusMessage(Metadata.statusResponseMetadata(metadata), text)}} : Result<&2, &2, Client.ConstructionError<E>, Client.APIError>}

law encoding_failure_retains_diagnostic:
  for -E: Data
  for metadata: Metadata.Metadata
  for diagnostic: Client.Diagnostic
  {Client.constructed(E, metadata, diagnostic, None{}) == Fail{Client.DiagnosticEncodingFailure{metadata, diagnostic}} : Result<&2, &2, Client.ConstructionError<E>, Client.APIError>}

law present_error_is_selected:
  for fallback: T.JsonValue
  for error: T.JsonValue
  {Client.selected(fallback, Some{error}) == error : T.JsonValue}

law unrecognized_json_is_retained:
  for value: T.JsonValue
  {Client.selected(value, None{}) == value : T.JsonValue}

law nonempty_message_text_is_retained:
  for whole: T.JsonValue
  for head: Char
  for tail: String
  {Client.jsonMessage(whole, Some{T.JsonString{SCon{head, tail}}}) == Some{SCon{head, tail}} : Maybe<&2, String>}

law text_normalization_preserves_rendered_message:
  for metadata: Metadata.Metadata
  for text: String
  for message: String
  {Client.providerFailure(Client.APIError{metadata, Client.TextDiagnostic{text}, message}) == Body.ProviderFailure{Some{F.fromU32(Metadata.statusResponseMetadata(metadata))}, message, Nil{}} : Body.ProviderFailure}

law json_normalization_retains_input:
  for metadata: Metadata.Metadata
  for value: T.JsonValue
  for message: String
  {Client.providerFailure(Client.APIError{metadata, Client.JSONDiagnostic{value}, message}) == Body.ProviderFailure{Some{F.fromU32(Metadata.statusResponseMetadata(metadata))}, message, Body.ParsedBody{value} <> Nil{}} : Body.ProviderFailure}

# Retry classification of an attempt: only connection failures and deadline
# expiry become retryable provider errors; every original failure survives.

law nonretryable_failures_stay_application_errors:
  for -E: Data
  for original: E
  {Client.categorized(E, original, Fetch.NonRetryable{}) == Retry.Other{original} : Retry.RequestFailure<E>}

law connection_failures_are_retryable:
  for -E: Data
  for original: E
  {Client.categorized(E, original, Fetch.Connection{}) == Retry.Provider{Retry.ProviderError{original, "Connection error.", None{}, None{}, None{}, None{}}} : Retry.RequestFailure<E>}

law expired_deadlines_are_retryable_timeouts:
  for -Reason: Data
  for -E: Data
  for original: E
  {Client.aborted(Reason, E, original, Abort.Supplied{Deadline.Expired{}}) == Retry.Provider{Retry.ProviderError{original, "Request timed out.", None{}, None{}, None{}, None{}}} : Retry.RequestFailure<E>}

law parent_cancellation_is_never_retried:
  for -Reason: Data
  for -E: Data
  for original: E
  for why: Abort.AbortReason<Reason>
  {Client.aborted(Reason, E, original, Abort.Supplied{Deadline.ParentAbort{why}}) == Retry.Other{original} : Retry.RequestFailure<E>}

law cancellation_overrides_the_transport_category:
  for -Reason: Data
  for -E: Data
  for original: E
  for why: Abort.AbortReason<Deadline.Cause<Reason>>
  {Client.dispatched(Reason, E, original, Fetch.Connection{}, Some{why}) == Client.aborted(Reason, E, original, why) : Retry.RequestFailure<E>}

law invalid_timeouts_are_never_retried:
  for -Reason: Data
  for cause: Duration.MillisecondsError
  {Client.fetchFailure(Reason, Client.InvalidTimeout{cause}) == Retry.Other{Client.TransportFailure{Client.InvalidTimeout{cause}}} : Retry.RequestFailure<Client.AttemptError<Reason>>}

# Header layers: layered configuration composes, removal stays explicit until
# the wire headers are materialized.
law layers_partition:
  for +left: List<&2, Maybe<&2, T.ProviderHeaders()>>
  for +initial: Result<&2, &2, H.HeaderHeaderError, Client.HeaderState>
  for +right: List<&2, Maybe<&2, T.ProviderHeaders()>>
  {Client.layers(List.append(&2, Maybe<&2, T.ProviderHeaders()>, left, right), initial) == Client.layers(right, Client.layers(left, initial)) : Result<&2, &2, H.HeaderHeaderError, Client.HeaderState>}

law empty_layers_preserve_result:
  for initial: Result<&2, &2, H.HeaderHeaderError, Client.HeaderState>
  {Client.layers(Nil{}, initial) == initial : Result<&2, &2, H.HeaderHeaderError, Client.HeaderState>}

law absent_layer_preserves_result:
  for initial: Result<&2, &2, H.HeaderHeaderError, Client.HeaderState>
  {Client.applyLayer(None{}, initial) == initial : Result<&2, &2, H.HeaderHeaderError, Client.HeaderState>}

law entries_preserve_first_error:
  for values: List<&2, R.Property<T.Nullable<String>>>
  for cause: H.HeaderHeaderError
  {Client.layerEntries(values, Fail{cause}) == Fail{cause} : Result<&2, &2, H.HeaderHeaderError, Client.HeaderState>}

law latest_setting_is_observable:
  for state: Client.HeaderState
  for +name: String
  for +value: T.Nullable<String>
  {Client.lookup(Client.put(state, name, value), name) == Some{value} : Maybe<&2, T.Nullable<String>>}

law later_setting_replaces_earlier:
  for +state: Client.HeaderState
  for +name: String
  for first: T.Nullable<String>
  for +second: T.Nullable<String>
  {Client.put(Client.put(state, name, first), name, second) == Client.put(state, name, second) : Client.HeaderState}

law removal_remains_explicit:
  for state: Client.HeaderState
  for +name: String
  {Client.removed(Client.lookup(Client.put(state, name, T.NullValue{}), name)) == True{} : Bool}

law assignment_clears_removal:
  for state: Client.HeaderState
  for +name: String
  for value: String
  {Client.removed(Client.lookup(Client.put(state, name, T.PresentValue{value}), name)) == False{} : Bool}

law materialization_partition:
  for +left: List<&2, R.Property<T.Nullable<String>>>
  for +right: List<&2, R.Property<T.Nullable<String>>>
  {Client.materialize(List.append(&2, R.Property<T.Nullable<String>>, left, right)) == List.append(&2, R.Property<List<&2, String>>, Client.materialize(left), Client.materialize(right)) : List<&2, R.Property<List<&2, String>>>}

law removal_has_no_wire_field:
  for name: String
  for values: List<&2, R.Property<T.Nullable<String>>>
  {Client.materialize(R.Property{name, T.NullValue{}} <> values) == Client.materialize(values) : List<&2, R.Property<List<&2, String>>>}

law assignment_retains_wire_value:
  for name: String
  for value: String
  for values: List<&2, R.Property<T.Nullable<String>>>
  {Client.materialize(R.Property{name, T.PresentValue{value}} <> values) == R.Property{name, value <> Nil{}} <> Client.materialize(values) : List<&2, R.Property<List<&2, String>>>}

law singleton_layer_applies_configuration:
  for layer: Maybe<&2, T.ProviderHeaders()>
  for initial: Result<&2, &2, H.HeaderHeaderError, Client.HeaderState>
  {Client.layers(layer <> Nil{}, initial) == Client.applyLayer(layer, initial) : Result<&2, &2, H.HeaderHeaderError, Client.HeaderState>}

law singleton_entry_applies_field:
  for state: Client.HeaderState
  for name: String
  for value: T.Nullable<String>
  {Client.layerEntries(R.Property{name, value} <> Nil{}, Done{state}) == Client.layerField(state, name, value) : Result<&2, &2, H.HeaderHeaderError, Client.HeaderState>}

law entries_partition:
  for +left: List<&2, R.Property<T.Nullable<String>>>
  for +initial: Result<&2, &2, H.HeaderHeaderError, Client.HeaderState>
  for +right: List<&2, R.Property<T.Nullable<String>>>
  {Client.layerEntries(List.append(&2, R.Property<T.Nullable<String>>, left, right), initial) == Client.layerEntries(right, Client.layerEntries(left, initial)) : Result<&2, &2, H.HeaderHeaderError, Client.HeaderState>}

# Status boundary: a successful response has no body IO before hand-off; a
# failed status consumes its diagnostic first and keeps retry metadata.
# Any successful metadata predicate hands off any affine body unchanged,
# without invoking either transport function or applying the diagnostic cap.
law accepted_owner_has_no_body_io:
  for -E: Data
  for -State: Type
  for read: Ops.Read(E, State)
  for close: Ops.Close(E, State)
  for limit: Nat
  for metadata: Metadata.Metadata
  for body: Response.Body<State>
  for accepted: {Metadata.ok(metadata) == True{} : Bool}
  {Client.accept(E, State, read, close, limit, Response.Response{metadata, body}) == IO.pure(Result<&2, &1, Client.StatusFailure<E>, Response.Response<State>>, Done{Response.Response{metadata, body}}) : IO(Result<&2, &1, Client.StatusFailure<E>, Response.Response<State>>)}

# A failed status runs the owned consumer before producing its typed failure.
# This is sequencing of IO programs, not a termination claim about the source.
law rejected_owner_runs_diagnostic_first:
  for -E: Data
  for -State: Type
  for read: Ops.Read(E, State)
  for close: Ops.Close(E, State)
  for limit: Nat
  for metadata: Metadata.Metadata
  for body: Response.Body<State>
  for rejected: {Metadata.ok(metadata) == False{} : Bool}
  {Client.accept(E, State, read, close, limit, Response.Response{metadata, body}) == IO.bind(Result<&2, &2, Consume.TextError<E>, String>, Result<&2, &1, Client.StatusFailure<E>, Response.Response<State>>, Consume.textUsing(E, State, read, close, limit, body), diagnostic => IO.pure(Result<&2, &1, Client.StatusFailure<E>, Response.Response<State>>, Fail{Client.StatusFailure{metadata, diagnostic}})) : IO(Result<&2, &1, Client.StatusFailure<E>, Response.Response<State>>)}

# Arbitrary original errors and rendered messages survive, status comes from
# the response head, and retry hints use normal Headers value coalescing.
law retry_metadata_projection:
  for -E: Data
  for original: E
  for message: String
  for major: U32
  for minor: U32
  for status: U32
  for reason: List<&2, U32>
  for raw: List<&2, Header.Header>
  for fields: Record.Record<List<&2, String>>
  for expose: Bool
  {Client.retryFailure(E, original, message, Metadata.Metadata{Head.ResponseHead{Status.StatusLine{major, minor, status, reason}, raw}, Headers.Headers{fields}, expose}) == Retry.Provider{Retry.ProviderError{original, message, Some{F.fromU32(status)}, Headers.joined("x-should-retry", Record.get(List<&2, String>, fields, "x-should-retry")), Headers.joined("retry-after-ms", Record.get(List<&2, String>, fields, "retry-after-ms")), Headers.joined("retry-after", Record.get(List<&2, String>, fields, "retry-after"))}} : Retry.RequestFailure<E>}
