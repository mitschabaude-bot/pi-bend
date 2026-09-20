import Base

def dots(text: String) -> Nat:
  match text:
    case SNil{}: 0n
    case SCon{'.', rest}: Succ{dots(rest)}
    case SCon{_, rest}: dots(rest)

law append:
  for +left: String
  for +right: String
  {dots(left ++ right) == Nat.add(dots(left), dots(right)) : Nat}

def append(left, right):
  match left:
    case SNil{}: {==}
    case SCon{'.', rest}:
      %append(rest, right) : {Succ{dots(rest ++ right)} == Succ{_} : Nat}
      {==}
    case SCon{char, rest}: append(rest, right)
