import Base
import ../laws/http-response-progress.bend as Laws

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
