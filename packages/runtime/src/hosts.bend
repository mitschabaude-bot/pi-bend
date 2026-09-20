import Base
import ./dns-response.bend as Case

# A hosts entry retains the file's canonical spelling and aliases. Address
# values are generic so name matching and ordering laws need no socket IO.
type Entry<-Address: Data> is Data:
  Entry{address: Address, canonical: String, aliases: List<&2, String>}

def same(left: String, right: String) -> Bool:
  match left right:
    case SNil{} SNil{}: True{}
    case SCon{Chr{a}, xs} SCon{Chr{b}, ys}: U32.is_eq(Case.fold(a), Case.fold(b)) && same(xs, ys)
    case _ _: False{}

def alias(+name: String, names: List<&2, String>) -> Bool:
  match names:
    case Nil{}: False{}
    case first <> rest: same(name, first) || alias(name, rest)

def matches(-Address: Data, +name: String, entry: Entry<Address>) -> Bool:
  match entry:
    case Entry{_, canonical, aliases}: same(name, canonical) || alias(name, aliases)

def selected(-Address: Data, matches: Bool, entry: Entry<Address>, rest: List<&2, Entry<Address>>) -> List<&2, Entry<Address>>:
  match matches:
    case True{}: entry <> rest
    case False{}: rest

# Preserve all matching occurrences, including duplicates, in source order.
# Address-family policy and canonical-name selection belong to the caller.
def lookup(-Address: Data, +name: String, entries: List<&2, Entry<Address>>) -> List<&2, Entry<Address>>:
  match entries:
    case Nil{}: Nil{}
    case +first <> rest: selected(Address, matches(Address, name, first), first, lookup(Address, name, rest))
