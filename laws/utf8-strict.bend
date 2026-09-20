import Base
import ../packages/runtime/src/utf8.bend as Shared
import ../packages/runtime/src/utf8-strict.bend as UTF8

law failure_retained:
  for bytes: List<&2, U32>
  for +error: UTF8.Error
  {UTF8.feed(bytes, Fail{error}) == Fail{error} : Result<&2, &2, UTF8.Error, UTF8.State>}

law chunk_composition:
  for +left: List<&2, U32>
  for +right: List<&2, U32>
  for +state: Result<&2, &2, UTF8.Error, UTF8.State>
  {UTF8.feed(List.append(&2, U32, left, right), state) == UTF8.feed(right, UTF8.feed(left, state)) : Result<&2, &2, UTF8.Error, UTF8.State>}

law finish_failure:
  for +error: UTF8.Error
  {UTF8.finish(Fail{error}) == Fail{error} : Result<&2, &2, UTF8.Error, String>}

law empty_input:
  for mode: UTF8.BOM
  {UTF8.decodeWith(mode, Nil{}) == Done{""} : Result<&2, &2, UTF8.Error, String>}

law incomplete_rejected:
  for +offset: Nat
  for remaining: U32
  for value: U32
  for lower: U32
  for upper: U32
  for seen: Bool
  for text: String
  {UTF8.finish(Done{UTF8.State{offset, Shared.Accumulator{Shared.Decoder{Shared.Continuation{remaining, value, lower, upper}, seen}, text}}}) == Fail{UTF8.IncompleteSequence{offset}} : Result<&2, &2, UTF8.Error, String>}

law invalid_byte_rejected:
  for +offset: Nat
  for accumulator: Shared.Accumulator
  for allowed: Bool
  for +byte: U32
  {UTF8.checked(False{}, allowed, UTF8.State{offset, accumulator}, byte) == Fail{UTF8.InvalidByte{offset, byte}} : Result<&2, &2, UTF8.Error, UTF8.State>}
