import Base
import ./dns-name.bend as Name

# Flags correspond to the resolver's default-name, search-list and no-TLD
# policies. Input dot count/absolute status are supplied by the caller so text
# policy is not guessed from binary labels (which can themselves contain dots).
type Policy is Data:
  Policy{ndots: U32, defaultNames: Bool, searchNames: Bool, noTld: Bool}

type Origin is Data:
  Initial{}
  Suffix{index: Nat}
  Final{}

# Invalid configured domains occupy their original search position. Their
# candidate is a typed failure; response policy decides whether to continue.
type Domain is Data:
  Valid{name: Name.Name}
  Invalid{error: Name.Error}

type Cursor is Data:
  Cursor{base: Name.Name, dots: U32, noTld: Bool, first: Bool, domains: List<&2, Domain>, index: Nat, triedDirect: Bool, triedRoot: Bool, searched: Bool}

type Step is Data:
  Exhausted{}
  Candidate{origin: Origin, name: Result<&2, &2, Name.Error, Name.Name>, next: Cursor}

def checked(+name: Name.Name, encoded: Result<&2, &2, Name.Error, List<&2, U32>>) -> Result<&2, &2, Name.Error, Name.Name>:
  match encoded:
    case Fail{error}: Fail{error}
    case Done{_}: Done{name}

def valid(+name: Name.Name) -> Result<&2, &2, Name.Error, Name.Name>:
  checked(name, Name.encode(name))

def prepend(reversed: List<&2, List<&2, U32>>, suffix: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match reversed:
    case Nil{}: suffix
    case label <> rest: prepend(rest, label <> suffix)

def joined(base: Name.Name, domain: Name.Name) -> Name.Name:
  match base domain:
    case Name.Name{labels} Name.Name{suffix}: Name.Name{prepend(List.reverse(&2, List<&2, U32>, labels), suffix)}

def root(name: Name.Name) -> Bool:
  match name:
    case Name.Name{Nil{}}: True{}
    case _: False{}

def domainList(allowed: Bool, all: Bool, domains: List<&2, Domain>) -> List<&2, Domain>:
  match allowed all domains:
    case False{} _ _: Nil{}
    case True{} True{} names: names
    case True{} False{} Nil{}: Nil{}
    case True{} False{} first <> _: first <> Nil{}

def preparedDomains(absolute: Bool, base: Name.Name, +dots: U32, domains: List<&2, Domain>, policy: Policy) -> Cursor:
  match absolute policy:
    case True{} _: Cursor{base, dots, False{}, True{}, Nil{}, Zero{}, False{}, False{}, False{}}
    case False{} Policy{ndots, defaultNames, +searchNames, noTld}:
      Cursor{base, dots, noTld, U32.is_ge(dots, ndots), domainList(Bool.pick(Bool, U32.is_zero(dots), defaultNames, searchNames), searchNames, domains), Zero{}, False{}, False{}, False{}}

# Names are validated individually when requested, including the composed wire
# length. No candidate is silently removed merely because it cannot be encoded.
def startDomains(base: Name.Name, dots: U32, absolute: Bool, domains: List<&2, Domain>, policy: Policy) -> Cursor:
  preparedDomains(absolute, base, dots, domains, policy)

def wrapDomains(names: List<&2, Name.Name>, reversed: List<&2, Domain>) -> List<&2, Domain>:
  match names:
    case Nil{}: List.reverse(&2, Domain, reversed)
    case name <> rest: wrapDomains(rest, Valid{name} <> reversed)

# Existing callers supplying wire names retain the same entry point.
def prepared(absolute: Bool, base: Name.Name, dots: U32, domains: List<&2, Name.Name>, policy: Policy) -> Cursor:
  preparedDomains(absolute, base, dots, wrapDomains(domains, Nil{}), policy)

def start(base: Name.Name, dots: U32, absolute: Bool, domains: List<&2, Name.Name>, policy: Policy) -> Cursor:
  prepared(absolute, base, dots, domains, policy)

def domainRoot(domain: Domain) -> Bool:
  match domain:
    case Valid{name}: root(name)
    case Invalid{_}: False{}

def domainCandidate(base: Name.Name, domain: Domain) -> Result<&2, &2, Name.Error, Name.Name>:
  match domain:
    case Valid{name}: valid(joined(base, name))
    case Invalid{error}: Fail{error}

def finalCandidate(allowed: Bool, +base: Name.Name, dots: U32, noTld: Bool, index: Nat, triedRoot: Bool, searched: Bool) -> Step:
  match allowed:
    case False{}: Exhausted{}
    case True{}: Candidate{Final{}, valid(base), Cursor{base, dots, noTld, False{}, Nil{}, index, True{}, triedRoot, searched}}

def next(cursor: Cursor) -> Step:
  match cursor:
    case Cursor{+base, dots, noTld, True{}, domains, index, _, triedRoot, searched}:
      Candidate{Initial{}, valid(base), Cursor{base, dots, noTld, False{}, domains, index, True{}, triedRoot, searched}}
    case Cursor{+base, dots, noTld, False{}, +domain <> rest, +index, triedDirect, triedRoot, _}:
      Candidate{Suffix{index}, domainCandidate(base, domain), Cursor{base, dots, noTld, False{}, rest, Succ{index}, triedDirect, triedRoot || domainRoot(domain), True{}}}
    case Cursor{base, +dots, +noTld, False{}, Nil{}, index, triedDirect, +triedRoot, +searched}:
      finalCandidate(Bool.not(triedDirect || triedRoot) && (Bool.not(U32.is_zero(dots)) || Bool.not(searched) || Bool.not(noTld)), base, dots, noTld, index, triedRoot, searched)

# A response policy can stop suffix searching but still attempt the final bare
# name where allowed. Only actually yielded root suffixes suppress that attempt.
def stopSearch(cursor: Cursor) -> Cursor:
  match cursor:
    case Cursor{base, dots, noTld, first, _, index, triedDirect, triedRoot, searched}: Cursor{base, dots, noTld, first, Nil{}, index, triedDirect, triedRoot, searched}
