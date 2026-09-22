import Base
import ../laws/http-response.bend as Laws
import ../laws/bounded.bend as BoundedLaws
import ./bounded.bend as Bounded
import ../packages/runtime/src/http-response.bend as Buffer
import ../packages/runtime/src/bounded.bend as Bytes
import ../packages/runtime/src/http-message.bend as Head
import ../packages/runtime/src/http-message.bend as Headers

# Http body buffer

def Laws.successful_body_preserved(E, bytes): {==}
def Laws.primary_failure_preserved(E, error): {==}
def Laws.cleanup_failure_rejects_body(E, bytes, error): {==}
def Laws.simultaneous_failures_preserved(E, primary, cleanup): {==}
def Laws.read_failure_rejects_prefix(E, buffer, error): {==}

def Laws.any_excess_stops(E, prefix, byte, suffix):
  %Equal.sym(Bytes.State, Bytes.consumed(List.append(&2, U32, prefix, byte <> suffix), Bytes.create(List.length(&2, U32, prefix))), Bytes.consumed(byte <> suffix, Bytes.consumed(prefix, Bytes.create(List.length(&2, U32, prefix)))), BoundedLaws.chunk_composition(prefix, byte <> suffix, Bytes.create(List.length(&2, U32, prefix)))) : {Buffer.buffered(E, _) == Buffer.Finished{Fail{Buffer.ByteLimitExceeded{}}} : Buffer.Decision<E>}
  %Equal.sym(Bytes.State, Bytes.consumed(prefix, Bytes.create(List.length(&2, U32, prefix))), Bytes.State{0n, List.reverse(&2, U32, prefix), False{}}, Bounded.filled_state(prefix)) : {Buffer.buffered(E, Bytes.consumed(byte <> suffix, _)) == Buffer.Finished{Fail{Buffer.ByteLimitExceeded{}}} : Buffer.Decision<E>}
  {==}


# Http body source

def Laws.bytes_are_not_decoded_or_changed(T, E, map, bytes): {==}
def Laws.eof_is_not_an_empty_chunk(T, E, map): {==}
def Laws.read_failure_uses_the_mapping(T, E, map, error): {==}
def Laws.close_failure_uses_the_mapping(T, E, map, error): {==}
def Laws.closed_owner_release_has_no_transport_io(T, State, E, map, close, fields): {==}


# Http response metadata

def Laws.fields_partition(left, initial, right):
  match left:
    case Nil{}: {==}
    case first <> rest: Laws.fields_partition(rest, Headers.appendField(initial, first), right)
def Laws.empty_fields_preserve_headers(initial): {==}
def Laws.original_head_retained(head, expose):
  match head:
    case Head.ResponseHead{_, _}: {==}
def Laws.exposure_retained(head, expose):
  match head:
    case Head.ResponseHead{_, _}: {==}
def Laws.status_retained(major, minor, code, reason, fields, expose): {==}
def Laws.success_classification(major, minor, code, reason, fields, expose): {==}
def Laws.one_field_preserved(initial, field): {==}
def Laws.received_headers_retained(line, fields, expose): {==}


# Http response progress

def Laws.final_head_transfers_metadata(E, head, expose): {==}
def Laws.informational_heads_do_not_finish(E, head): {==}
def Laws.nonempty_chunks_preserve_bytes(E, first, rest): {==}
def Laws.hidden_body_does_not_expose_bytes(E, bytes):
  match bytes:
    case Nil{}: {==}
    case _ <> _: {==}
def Laws.empty_chunk_is_not_completion(E, expose):
  match expose:
    case False{}: {==}
    case True{}: {==}
def Laws.completion_retains_trailers(E, expose, fields):
  match expose:
    case False{}: {==}
    case True{}: {==}
def Laws.hidden_body_does_not_hide_failure(E, expose, error):
  match expose:
    case False{}: {==}
    case True{}: {==}
def Laws.cleanup_retains_primary(E, error): {==}
def Laws.dual_failure_retains_both(E, error, cleanup): {==}
def Laws.cleanup_failure_is_not_success(E, cleanup): {==}


# Http abort classification

def Laws.lone_transport_uses_classifier(E, classify, error): {==}
def Laws.lone_cleanup_uses_classifier(E, classify, error): {==}
def Laws.combined_failures_are_not_cancellation(E, classify, error, cleanup): {==}
def Laws.unexpected_events_are_not_cancellation(E, classify, event): {==}
def Laws.missing_head_is_not_cancellation(E, classify): {==}
def Laws.missing_completion_is_not_cancellation(E, classify): {==}
