import Base
import ../laws/dns-search-text.bend as Laws
import ../packages/runtime/src/dns-message.bend as Text

law counted_append:
  for +dot: Bool
  for +left: Nat
  for +right: Nat
  {Text.countedSearchText(dot, Nat.add(left, right)) == Nat.add(Text.countedSearchText(dot, left), right) : Nat}

def counted_append(dot, left, right):
  match dot:
    case True{}: {==}
    case False{}: {==}

def Laws.dots_append(left, right):
  match left:
    case SNil{}: {==}
    case SCon{Chr{code}, rest}:
      %Equal.sym(Nat, Text.dots(rest ++ right), Nat.add(Text.dots(rest), Text.dots(right)), Laws.dots_append(rest, right)) : {Text.countedSearchText(U32.is_eq(code, 46), _) == Nat.add(Text.countedSearchText(U32.is_eq(code, 46), Text.dots(rest)), Text.dots(right)) : Nat}
      counted_append(U32.is_eq(code, 46), Text.dots(rest), Text.dots(right))

def Laws.leading_dot_counted(text): {==}
def Laws.dots_empty(): {==}
def Laws.invalid_input_is_terminal(text, error): {==}
def Laws.prepared_fields_retained(text, name, absolute): {==}
