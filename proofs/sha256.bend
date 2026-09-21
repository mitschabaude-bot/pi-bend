import Base
import ../laws/sha256.bend as Laws
import ../packages/runtime/src/sha256.bend as SHA

def retained(bytes: List<&2, U32>, +error: SHA.Error) -> {SHA.feed(bytes, Fail{error}) == Fail{error} : Result<&2, &2, SHA.Error, SHA.State>}:
  match bytes:
    case Nil{}: {==}
    case _ <> _: {==}

def Laws.chunk_composition(left, right, state):
  match left:
    case Nil{}:
      match state:
        case Fail{error}: {==}
        case Done{value}: {==}
    case +head <> tail:
      match state:
        case Fail{+error}: Equal.sym(Result<&2, &2, SHA.Error, SHA.State>, SHA.feed(right, Fail{error}), Fail{error}, retained(right, error))
        case Done{value}: Laws.chunk_composition(tail, right, SHA.byte(U32.is_le(head, 255), value, head))
