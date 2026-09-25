import Base
import ./record.bend as R


# An immutable set of string identifiers. Insertion preserves existing members.
type StringSet is Data:
  StringSet{entries: R.Record<Unit>}

def empty() -> StringSet: StringSet{R.new(Unit)}
def contains(values: StringSet, value: String) -> Bool:
  match values:
    case StringSet{entries}: Bool.not(Maybe.is_none(&2, Unit, R.get(Unit, entries, value)))
def insert(values: StringSet, value: String) -> StringSet:
  match values:
    case StringSet{entries}: StringSet{R.set(Unit, entries, value, Unit{})}
def remove(values: StringSet, value: String) -> StringSet:
  match values:
    case StringSet{entries}: StringSet{R.remove(Unit, entries, value)}
def keys(entries: List<&2, R.Property<Unit>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, _} <> rest: key <> keys(rest)
def toList(values: StringSet) -> List<&2, String>:
  match values:
    case StringSet{entries}: keys(R.entries(Unit, entries))


# Character-delimited splitting with explicit accumulators. Tail recursion
# bounds machine-stack use independently of text length on every backend.
type State is Data:
  State{field: String, parts: List<&2, String>}

def advance(separator: Bool, char: Char, state: State) -> State:
  match separator state:
    case True{} State{field, parts}: State{"", String.reverse(field) <> parts}
    case False{} State{field, parts}: State{SCon{char, field}, parts}

def scan(text: String, +separator: Char, state: State) -> List<&2, String>:
  match text state:
    case SNil{} State{field, parts}: List.reverse(&2, String, String.reverse(field) <> parts)
    case SCon{+char, rest} previous: scan(rest, separator, advance(Char.is_eq(char, separator), char, previous))

def split(text: String, separator: Char) -> List<&2, String>:
  scan(text, separator, State{"", Nil{}})

# Scalar equality need not reconstruct the compared strings. The base ordering
# operation does reconstruct them and consumes machine stack on long prefixes.
def equalFrom(left: String, right: String, same: Bool) -> Bool:
  match left right same:
    case _ _ False{}: False{}
    case SNil{} SNil{} True{}: True{}
    case SCon{a,restA} SCon{b,restB} True{}: equalFrom(restA,restB,Char.is_eq(a,b))
    case _ _ True{}: False{}

def equal(left: String, right: String) -> Bool:
  equalFrom(left,right,True{})

# Preserve a path as one POSIX shell argument. File IO rejects NUL paths.
def quoteShell(value: String) -> String:
  "'" ++ String.join(split(value, '\''), "'\\\''") ++ "'"

# JavaScript's String.prototype.replaceAll with a string pattern: every
# non-overlapping occurrence, scanning left to right; an empty pattern matches
# before each character and at the end. After a match the scan skips the rest
# of the matched text; the output accumulates reversed.
type Scan is Data:
  Scan{skip: Nat, reversed: String}

def matchedHere(here: Bool, char: Char, +replacement: String, width: Nat, reversed: String) -> Scan:
  match here:
    case True{}: Scan{width, String.reverse(replacement) ++ reversed}
    case False{}: Scan{0n, SCon{char, reversed}}

def scanned(state: Scan, here: Bool, char: Char, +replacement: String, width: Nat) -> Scan:
  match state:
    case Scan{1n+skip, reversed}: Scan{skip, reversed}
    case Scan{0n, reversed}: matchedHere(here, char, replacement, width, reversed)

def replaceScan(text: String, +pattern: String, +replacement: String, +width: Nat, state: Scan) -> String:
  match text state:
    case SNil{} Scan{_, reversed}: String.reverse(reversed)
    case SCon{+char, +rest} previous: replaceScan(rest, pattern, replacement, width, scanned(previous, String.starts_with(SCon{char, rest}, pattern), char, replacement, width))

def interleave(text: String, +replacement: String, reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(String.reverse(replacement) ++ reversed)
    case SCon{char, rest}: interleave(rest, replacement, SCon{char, String.reverse(replacement) ++ reversed})

def replaceAll(text: String, pattern: String, replacement: String) -> String:
  match pattern:
    case SNil{}: interleave(text, replacement, "")
    case SCon{first, +rest}: replaceScan(text, SCon{first, rest}, replacement, String.length(rest), Scan{0n, ""})
