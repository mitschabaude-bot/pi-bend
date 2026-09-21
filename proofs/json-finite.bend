import Base
import ../laws/json-finite.bend as Laws
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/json-finite.bend as S
import ../packages/runtime/src/record.bend as R

def Laws.finite_components_are_accepted(sign, exponent, significand): {==}
def Laws.infinities_are_rejected(sign): {==}
law lazy_conjunction:
  for +a: Bool
  for +b: Bool
  {Bool.pick(Unit -> Bool, a, unused => b, unused => False{})(Unit{}) == (a && b) : Bool}

def lazy_conjunction(a, b):
  match a:
    case False{}: {==}
    case True{}: {==}

def Laws.array_checks_head_and_tail(head, tail): lazy_conjunction(S.valid(head), S.valid(T.JsonArray{tail}))
def Laws.object_checks_value_and_tail(key, value, tail): lazy_conjunction(S.valid(value), S.valid(T.JsonObject{R.Record{tail}}))
def Laws.string_contents_are_not_numbers(text): {==}

law conjunction_associative:
  for +a: Bool
  for +b: Bool
  for +c: Bool
  {((a && b) && c) == (a && (b && c)) : Bool}

def conjunction_associative(a, b, c):
  match a:
    case False{}: {==}
    case True{}: {==}

def Laws.array_partition(left, right):
  match left:
    case Nil{}: {==}
    case +head <> +rest:
      +a = S.valid(head)
      +b = S.valid(T.JsonArray{rest})
      +c = S.valid(T.JsonArray{right})
      +tail = List.append(&2, T.JsonValue, rest, right)
      +whole = S.valid(T.JsonArray{head <> rest})
      Equal.trans(Bool, S.valid(T.JsonArray{head <> tail}), a && S.valid(T.JsonArray{tail}), whole && c,
        Laws.array_checks_head_and_tail(head, tail),
        Equal.trans(Bool, a && S.valid(T.JsonArray{tail}), a && (b && c), whole && c,
          Equal.cong(Bool, Bool, value => a && value, S.valid(T.JsonArray{tail}), b && c, Laws.array_partition(rest, right)),
          Equal.trans(Bool, a && (b && c), (a && b) && c, whole && c,
            Equal.sym(Bool, (a && b) && c, a && (b && c), conjunction_associative(a, b, c)),
            Equal.cong(Bool, Bool, value => value && c, a && b, whole,
              Equal.sym(Bool, whole, a && b, Laws.array_checks_head_and_tail(head, rest))))))

def Laws.invalid_numeric_leaf_is_rejected(value, invalid): invalid
