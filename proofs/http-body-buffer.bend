import Base
import ../laws/http-body-buffer.bend as Laws
import ../laws/bounded-bytes.bend as BoundedLaws
import ./bounded-bytes.bend as Bounded
import ../packages/runtime/src/http-body-buffer.bend as Buffer
import ../packages/runtime/src/bounded-bytes.bend as Bytes

def Laws.successful_body_preserved(E, bytes): {==}
def Laws.primary_failure_preserved(E, error): {==}
def Laws.cleanup_failure_rejects_body(E, bytes, error): {==}
def Laws.simultaneous_failures_preserved(E, primary, cleanup): {==}
def Laws.read_failure_rejects_prefix(E, buffer, error): {==}

def Laws.any_excess_stops(E, prefix, byte, suffix):
  %Equal.sym(Bytes.State, Bytes.consumed(List.append(&2, U32, prefix, byte <> suffix), Bytes.create(List.length(&2, U32, prefix))), Bytes.consumed(byte <> suffix, Bytes.consumed(prefix, Bytes.create(List.length(&2, U32, prefix)))), BoundedLaws.chunk_composition(prefix, byte <> suffix, Bytes.create(List.length(&2, U32, prefix)))) : {Buffer.buffered(E, _) == Buffer.Finished{Fail{Buffer.ByteLimitExceeded{}}} : Buffer.Decision<E>}
  %Equal.sym(Bytes.State, Bytes.consumed(prefix, Bytes.create(List.length(&2, U32, prefix))), Bytes.State{0n, List.reverse(&2, U32, prefix), False{}}, Bounded.filled_state(prefix)) : {Buffer.buffered(E, Bytes.consumed(byte <> suffix, _)) == Buffer.Finished{Fail{Buffer.ByteLimitExceeded{}}} : Buffer.Decision<E>}
  {==}
