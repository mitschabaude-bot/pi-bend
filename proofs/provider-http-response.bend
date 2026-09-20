import Base
import ../laws/provider-http-response.bend as Laws
import ../packages/ai/src/utils/provider-http-response.bend as Provider
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response-metadata.bend as Metadata

def Laws.accepted_owner_has_no_body_io(E, State, read, close, limit, metadata, body, accepted):
  Equal.cong(Bool, IO(Result<&2, &1, Provider.Failure<E>, Response.Response<State>>), successful => Provider.select(E, State, read, close, limit, metadata, body, successful), Metadata.ok(metadata), True{}, accepted)

def Laws.rejected_diagnostic_is_preserved(E, State, metadata, body): {==}
def Laws.retry_metadata_projection(E, original, message, major, minor, status, reason, raw, fields, expose): {==}

def Laws.rejected_owner_runs_diagnostic_first(E, State, read, close, limit, metadata, body, rejected):
  Equal.cong(Bool, IO(Result<&2, &1, Provider.Failure<E>, Response.Response<State>>), successful => Provider.select(E, State, read, close, limit, metadata, body, successful), Metadata.ok(metadata), False{}, rejected)
