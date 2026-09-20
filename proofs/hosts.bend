import Base
import ../laws/hosts.bend as Laws
import ../packages/runtime/src/hosts.bend as Hosts
import ./string-equality.bend as Equality
import ../packages/runtime/src/dns-response.bend as Case

law selected_append:
  for -Address: Data
  for +matches: Bool
  for +entry: Hosts.Entry<Address>
  for +left: List<&2, Hosts.Entry<Address>>
  for +right: List<&2, Hosts.Entry<Address>>
  {Hosts.selected(Address, matches, entry, List.append(&2, Hosts.Entry<Address>, left, right)) == List.append(&2, Hosts.Entry<Address>, Hosts.selected(Address, matches, entry, left), right) : List<&2, Hosts.Entry<Address>>}

def selected_append(Address, matches, entry, left, right):
  match matches:
    case True{}: {==}
    case False{}: {==}

def Laws.lookup_empty(Address, name): {==}

def Laws.lookup_append(Address, name, left, right):
  match left:
    case Nil{}: {==}
    case first <> rest:
      %Equal.sym(List<&2, Hosts.Entry<Address>>, Hosts.lookup(Address, name, List.append(&2, Hosts.Entry<Address>, rest, right)), List.append(&2, Hosts.Entry<Address>, Hosts.lookup(Address, name, rest), Hosts.lookup(Address, name, right)), Laws.lookup_append(Address, name, rest, right)) : {Hosts.selected(Address, Hosts.matches(Address, name, first), first, _) == List.append(&2, Hosts.Entry<Address>, Hosts.selected(Address, Hosts.matches(Address, name, first), first, Hosts.lookup(Address, name, rest)), Hosts.lookup(Address, name, right)) : List<&2, Hosts.Entry<Address>>}
      selected_append(Address, Hosts.matches(Address, name, first), first, Hosts.lookup(Address, name, rest), Hosts.lookup(Address, name, right))

def Laws.parse_failure_retained(remaining, number, error):
  match remaining:
    case Nil{}: {==}
    case first <> rest: {==}

def Laws.invalid_line_discards_partial_database(number, prior, error): {==}


law number_reflexive:
  for +value: U32
  {True{} == U32.is_eq(value, value) : Bool}

def number_reflexive(value):
  match value:
    case U32{bits}:
      %Equality.word_reflexive(32n, bits) : {True{} == Cmp.is_eq(_) : Bool}
      {==}

law same_reflexive:
  for +name: String
  {True{} == Hosts.same(name, name) : Bool}

def same_reflexive(name):
  match name:
    case SNil{}: {==}
    case SCon{Chr{code}, rest}:
      %number_reflexive(Case.fold(code)) : {True{} == _ && Hosts.same(rest, rest) : Bool}
      same_reflexive(rest)

law or_right_true:
  for left: Bool
  {True{} == left || True{} : Bool}

def or_right_true(left):
  match left:
    case True{}: {==}
    case False{}: {==}

def Laws.canonical_matches(Address, address, name, aliases):
  %same_reflexive(name) : {True{} == _ || Hosts.alias(name, aliases) : Bool}
  {==}

def Laws.first_alias_matches(Address, address, name, canonical, aliases):
  %same_reflexive(name) : {True{} == Hosts.same(name, canonical) || (_ || Hosts.alias(name, aliases)) : Bool}
  or_right_true(Hosts.same(name, canonical))

def Laws.matched_entry_retained(Address, entry, rest): {==}
