import Base
import ../packages/runtime/src/bounded-bytes.bend as Bytes

law overflow_sticky:
  for input: List<&2, U32>
  for +retained: List<&2, U32>
  {Bytes.consumed(input, Bytes.State{0n, retained, True{}}) == Bytes.State{0n, retained, True{}} : Bytes.State}

# Every possible division into file-read chunks produces the same budget,
# retained bytes and overflow status as consuming the concatenated input.
law chunk_composition:
  for +left: List<&2, U32>
  for +right: List<&2, U32>
  for +state: Bytes.State
  {Bytes.consumed(List.append(&2, U32, left, right), state) == Bytes.consumed(right, Bytes.consumed(left, state)) : Bytes.State}

law excess_retains_no_new_bytes:
  for byte: U32
  for rest: List<&2, U32>
  for +retained: List<&2, U32>
  {Bytes.consumed(byte <> rest, Bytes.State{0n, retained, False{}}) == Bytes.State{0n, retained, True{}} : Bytes.State}

# Together with chunk composition, this specifies retention and budget
# consumption for every prefix that fits, not just particular byte values.
law one_byte_consumes_budget:
  for +remaining: Nat
  for +byte: U32
  for +retained: List<&2, U32>
  {Bytes.consumed(byte <> Nil{}, Bytes.State{1n+remaining, retained, False{}}) == Bytes.State{remaining, byte <> retained, False{}} : Bytes.State}
