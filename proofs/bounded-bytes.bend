import Base
import ./list-reverse.bend as Reverse
import ./list-interleave.bend as NatProof
import ../laws/bounded-bytes.bend as Laws
import ../packages/runtime/src/bounded-bytes.bend as Bytes

def Laws.overflow_sticky(input, retained):
  match input:
    case Nil{}: {==}
    case byte <> rest: {==}

def Laws.chunk_composition(left, right, state):
  match left:
    case Nil{}:
      match state:
        case Bytes.State{0n, retained, False{}}: {==}
        case Bytes.State{0n, retained, True{}}: {==}
        case Bytes.State{1n+remaining, retained, False{}}: {==}
        case Bytes.State{1n+remaining, retained, True{}}: {==}
    case byte <> rest:
      match state:
        case Bytes.State{0n, retained, True{}}: Equal.sym(Bytes.State, Bytes.consumed(right, Bytes.State{0n, retained, True{}}), Bytes.State{0n, retained, True{}}, Laws.overflow_sticky(right, retained))
        case Bytes.State{1n+remaining, retained, True{}}: Equal.sym(Bytes.State, Bytes.consumed(right, Bytes.State{0n, retained, True{}}), Bytes.State{0n, retained, True{}}, Laws.overflow_sticky(right, retained))
        case Bytes.State{0n, retained, False{}}: Equal.sym(Bytes.State, Bytes.consumed(right, Bytes.State{0n, retained, True{}}), Bytes.State{0n, retained, True{}}, Laws.overflow_sticky(right, retained))
        case Bytes.State{1n+remaining, retained, False{}}: Laws.chunk_composition(rest, right, Bytes.State{remaining, byte <> retained, False{}})

def Laws.excess_retains_no_new_bytes(byte, rest, retained): {==}

def Laws.one_byte_consumes_budget(remaining, byte, retained):
  match remaining:
    case 0n: {==}
    case 1n+rest: {==}

law fitting_state:
  for +input: List<&2, U32>
  for +spare: Nat
  for +retained: List<&2, U32>
  {Bytes.consumed(input, Bytes.State{Nat.add(List.length(&2, U32, input), spare), retained, False{}}) == Bytes.State{spare, List.reverse.go(&2, U32, input, retained), False{}} : Bytes.State}

def fitting_state(input, spare, retained):
  match input:
    case Nil{}: {==}
    case byte <> rest: fitting_state(rest, spare, byte <> retained)

def Laws.fitting_input_preserved(input, spare):
  %Equal.sym(Bytes.State, Bytes.consumed(input, Bytes.create(Nat.add(List.length(&2, U32, input), spare))), Bytes.State{spare, List.reverse(&2, U32, input), False{}}, fitting_state(input, spare, Nil{})) : {Bytes.finish(_) == Done{input} : Result<&2, &2, Bytes.Error, List<&2, U32>>}
  Equal.cong(List<&2, U32>, Result<&2, &2, Bytes.Error, List<&2, U32>>, bytes => Done{bytes}, List.reverse(&2, U32, List.reverse(&2, U32, input)), input, Reverse.involution(U32, input))

law filled_state:
  for +input: List<&2, U32>
  {Bytes.consumed(input, Bytes.create(List.length(&2, U32, input))) == Bytes.State{0n, List.reverse(&2, U32, input), False{}} : Bytes.State}

def filled_state(input):
  %NatProof.add_zero(List.length(&2, U32, input)) : {Bytes.consumed(input, Bytes.create(_)) == Bytes.State{0n, List.reverse(&2, U32, input), False{}} : Bytes.State}
  fitting_state(input, 0n, Nil{})

def Laws.overflow_rejected(prefix, byte, suffix):
  %Equal.sym(Bytes.State, Bytes.consumed(List.append(&2, U32, prefix, byte <> suffix), Bytes.create(List.length(&2, U32, prefix))), Bytes.consumed(byte <> suffix, Bytes.consumed(prefix, Bytes.create(List.length(&2, U32, prefix)))), Laws.chunk_composition(prefix, byte <> suffix, Bytes.create(List.length(&2, U32, prefix)))) : {Bytes.finish(_) == Fail{Bytes.LimitExceeded{}} : Result<&2, &2, Bytes.Error, List<&2, U32>>}
  %Equal.sym(Bytes.State, Bytes.consumed(prefix, Bytes.create(List.length(&2, U32, prefix))), Bytes.State{0n, List.reverse(&2, U32, prefix), False{}}, filled_state(prefix)) : {Bytes.finish(Bytes.consumed(byte <> suffix, _)) == Fail{Bytes.LimitExceeded{}} : Result<&2, &2, Bytes.Error, List<&2, U32>>}
  {==}
