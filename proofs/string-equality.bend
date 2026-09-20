import Base

law word_reflexive:
  for +n: Nat
  for +value: Word(n)
  {EQ{} == Word.cmp(n, value, value) : Cmp}

def word_reflexive(n, value):
  match n:
    case 0n: {==}
    case 1n+p:
      match value:
        case WCon{False{}, tail}:
          %word_reflexive(p, tail) : {EQ{} == Word.cmp.fin(False{}, False{}, _) : Cmp}
          {==}
        case WCon{True{}, tail}:
          %word_reflexive(p, tail) : {EQ{} == Word.cmp.fin(True{}, True{}, _) : Cmp}
          {==}

law char_reflexive:
  for +value: Char
  {((value, value), EQ{}) == Char.cmp(value, value) : (Char & Char) & Cmp}

def char_reflexive(value):
  match value:
    case Chr{U32{bits}}:
      %word_reflexive(32n, bits) : {((Chr{U32{bits}}, Chr{U32{bits}}), EQ{}) == ((Chr{U32{bits}}, Chr{U32{bits}}), _) : (Char & Char) & Cmp}
      {==}

law string_reflexive:
  for +value: String
  {((value, value), EQ{}) == String.cmp(value, value) : (String & String) & Cmp}

def string_reflexive(value):
  match value:
    case SNil{}: {==}
    case SCon{head, tail}:
      %char_reflexive(head) : {((SCon{head, tail}, SCon{head, tail}), EQ{}) == String.cmp.fin(tail, tail, _) : (String & String) & Cmp}
      %string_reflexive(tail) : {((SCon{head, tail}, SCon{head, tail}), EQ{}) == String.cmp.rec(head, head, _) : (String & String) & Cmp}
      {==}

law eq_reflexive:
  for +value: String
  {True{} == String.eq(value, value) : Bool}

def eq_reflexive(value):
  Equal.cong((String & String) & Cmp, Bool, result => String.eq.fin(result), ((value, value), EQ{}), String.cmp(value, value), string_reflexive(value))

def flip(order: Cmp) -> Cmp:
  match order:
    case LT{}: GT{}
    case EQ{}: EQ{}
    case GT{}: LT{}

law bit_swap:
  for +a: Bool
  for +b: Bool
  {flip(Bool.cmp(a, b)) == Bool.cmp(b, a) : Cmp}

def bit_swap(a, b):
  match a b:
    case False{} False{}: {==}
    case False{} True{}: {==}
    case True{} False{}: {==}
    case True{} True{}: {==}

law word_step_swap:
  for +a: Bool
  for +b: Bool
  for +tail: Cmp
  {flip(Word.cmp.fin(a, b, tail)) == Word.cmp.fin(b, a, flip(tail)) : Cmp}

def word_step_swap(a, b, tail):
  match tail:
    case LT{}: {==}
    case EQ{}: bit_swap(a, b)
    case GT{}: {==}

law word_swap:
  for +n: Nat
  for +a: Word(n)
  for +b: Word(n)
  {flip(Word.cmp(n, a, b)) == Word.cmp(n, b, a) : Cmp}

def word_swap(n, a, b):
  match n:
    case 0n: {==}
    case 1n+p:
      match a b:
        case WCon{+ah, +at} WCon{+bh, +bt}:
          %word_swap(p, at, bt) : {flip(Word.cmp.fin(ah, bh, Word.cmp(p, at, bt))) == Word.cmp.fin(bh, ah, _) : Cmp}
          word_step_swap(ah, bh, Word.cmp(p, at, bt))

def swapped(-A: Data, result: (A & A) & Cmp) -> (A & A) & Cmp:
  match result:
    case Tuple{Tuple{a, b}, order}: ((b, a), flip(order))

law char_swap:
  for +a: Char
  for +b: Char
  {swapped(Char, Char.cmp(a, b)) == Char.cmp(b, a) : (Char & Char) & Cmp}

def char_swap(a, b):
  match a b:
    case Chr{U32{x}} Chr{U32{y}}:
      Equal.cong(Cmp, (Char & Char) & Cmp, order => ((Chr{U32{y}}, Chr{U32{x}}), order), flip(Word.cmp(32n, x, y)), Word.cmp(32n, y, x), word_swap(32n, x, y))

law string_rec_swap:
  for +a: Char
  for +b: Char
  for tails: (String & String) & Cmp
  {swapped(String, String.cmp.rec(a, b, tails)) == String.cmp.rec(b, a, swapped(String, tails)) : (String & String) & Cmp}

def string_rec_swap(a, b, tails):
  match tails:
    case Tuple{Tuple{_, _}, _}: {==}

law string_step_swap:
  for +a: String
  for +b: String
  for heads: (Char & Char) & Cmp
  for tails: {swapped(String, String.cmp(a, b)) == String.cmp(b, a) : (String & String) & Cmp}
  {swapped(String, String.cmp.fin(a, b, heads)) == String.cmp.fin(b, a, swapped(Char, heads)) : (String & String) & Cmp}

def string_step_swap(a, b, heads, tails):
  match heads:
    case Tuple{Tuple{_, _}, LT{}}: {==}
    case Tuple{Tuple{h1, h2}, EQ{}}:
      %tails : {swapped(String, String.cmp.rec(h1, h2, String.cmp(a, b))) == String.cmp.rec(h2, h1, _) : (String & String) & Cmp}
      string_rec_swap(h1, h2, String.cmp(a, b))
    case Tuple{Tuple{_, _}, GT{}}: {==}

law string_swap:
  for +a: String
  for +b: String
  {swapped(String, String.cmp(a, b)) == String.cmp(b, a) : (String & String) & Cmp}

def string_swap(a, b):
  match a b:
    case SNil{} SNil{}: {==}
    case SNil{} SCon{_, _}: {==}
    case SCon{_, _} SNil{}: {==}
    case SCon{ah, at} SCon{bh, bt}:
      %char_swap(ah, bh) : {swapped(String, String.cmp.fin(at, bt, Char.cmp(ah, bh))) == String.cmp.fin(bt, at, _) : (String & String) & Cmp}
      string_step_swap(at, bt, Char.cmp(ah, bh), string_swap(at, bt))

law swapped_equality:
  for result: (String & String) & Cmp
  {String.eq.fin(result) == String.eq.fin(swapped(String, result)) : Bool}

def swapped_equality(result):
  match result:
    case Tuple{Tuple{_, _}, LT{}}: {==}
    case Tuple{Tuple{_, _}, EQ{}}: {==}
    case Tuple{Tuple{_, _}, GT{}}: {==}

law eq_symmetric:
  for +a: String
  for +b: String
  {String.eq(a, b) == String.eq(b, a) : Bool}

def eq_symmetric(a, b):
  %string_swap(a, b) : {String.eq(a, b) == String.eq.fin(_) : Bool}
  swapped_equality(String.cmp(a, b))
