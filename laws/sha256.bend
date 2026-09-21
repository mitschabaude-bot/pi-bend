import Base
import ../packages/runtime/src/sha256.bend as SHA

# Arbitrary chunk boundaries preserve the complete state and first error,
# including partial words/blocks and the encoded message length.
law chunk_composition:
  for +left: List<&2, U32>
  for +right: List<&2, U32>
  for +state: Result<&2, &2, SHA.Error, SHA.State>
  {SHA.feed(List.append(&2, U32, left, right), state) == SHA.feed(right, SHA.feed(left, state)) : Result<&2, &2, SHA.Error, SHA.State>}
