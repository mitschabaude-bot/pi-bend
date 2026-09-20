import Base
import ../laws/utf8-strict.bend as Laws
import ../packages/runtime/src/utf8-strict.bend as UTF8

def Laws.failure_retained(bytes, error):
  match bytes:
    case Nil{}: {==}
    case byte <> rest: {==}

def Laws.chunk_composition(left, right, state):
  match left:
    case Nil{}:
      match state:
        case Fail{error}: {==}
        case Done{value}: {==}
    case byte <> rest:
      match state:
        case Fail{error}: Equal.sym(Result<&2, &2, UTF8.Error, UTF8.State>, UTF8.feed(right, Fail{error}), Fail{error}, Laws.failure_retained(right, error))
        case Done{value}: Laws.chunk_composition(rest, right, UTF8.step(value, byte))

def Laws.finish_failure(error): {==}

def Laws.empty_input(mode):
  match mode:
    case UTF8.Preserve{}: {==}
    case UTF8.StripLeading{}: {==}

def Laws.incomplete_rejected(offset, remaining, value, lower, upper, seen, text): {==}

def Laws.invalid_byte_rejected(offset, accumulator, allowed, byte):
  match allowed:
    case False{}: {==}
    case True{}: {==}
