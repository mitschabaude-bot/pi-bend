import Base
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
