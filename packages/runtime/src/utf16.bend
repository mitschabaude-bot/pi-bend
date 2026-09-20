import Base

# Canonicalize the representation, not Unicode spelling: merge adjacent UTF-16
# surrogate pairs into scalars while retaining every unpaired unit unchanged.
# No NFC/NFD or case normalization is performed.
type Step is Data:
  Step{pending: Maybe<&2, U32>, fragment: String}

def highSurrogate(+code: U32) -> Bool: U32.is_ge(code, 55296) && U32.is_le(code, 56319)
def lowSurrogate(+code: U32) -> Bool: U32.is_ge(code, 56320) && U32.is_le(code, 57343)

def unit(code: U32) -> String: SCon{Chr{code}, SNil{}}

def start(isHigh: Bool, code: U32) -> Step:
  match isHigh:
    case True{}: Step{Some{code}, ""}
    case False{}: Step{None{}, unit(code)}

def prepend(prefix: String, step: Step) -> Step:
  match step:
    case Step{pending, fragment}: Step{pending, prefix ++ fragment}

def pair(isLow: Bool, high: U32, +code: U32) -> Step:
  match isLow:
    case True{}: Step{None{}, unit((65536 + (high - 55296) * 1024 + code - 56320 : U32))}
    case False{}: prepend(unit(high), start(highSurrogate(code), code))

def consume(pending: Maybe<&2, U32>, +code: U32) -> Step:
  match pending:
    case None{}: start(highSurrogate(code), code)
    case Some{high}: pair(lowSurrogate(code), high, code)

def finish(pending: Maybe<&2, U32>) -> String:
  match pending:
    case None{}: ""
    case Some{high}: unit(high)

def reverseFragment(fragment: String, reversed: String) -> String:
  match fragment:
    case SNil{}: reversed
    case SCon{char, rest}: reverseFragment(rest, SCon{char, reversed})

def collect(chars: String, step: Step, reversed: String) -> String:
  match chars step:
    case SNil{} Step{pending, fragment}: String.reverse(reverseFragment(finish(pending), reverseFragment(fragment, reversed)))
    case SCon{Chr{code}, rest} Step{pending, fragment}: collect(rest, consume(pending, code), reverseFragment(fragment, reversed))

def normalize(text: String) -> String: collect(text, Step{None{}, ""}, "")

def equal(left: String, right: String) -> Bool: String.eq(normalize(left), normalize(right))
