import Base
import ./url-scheme.bend as Scheme

# Ordinary constructor input preprocessing. Setters on an existing URL can use
# removeTabsAndNewlines separately: their parser entry does not trim edge C0/space.
def visible(keep: Bool, char: Char) -> Maybe<&2, Char>:
  match keep:
    case True{}: Some{char}
    case False{}: None{}

def leading(text: String, first: Maybe<&2, Char>) -> String:
  match text first:
    case rest Some{char}: SCon{char, rest}
    case SNil{} None{}: ""
    case SCon{Chr{+code}, rest} None{}: leading(rest, visible(U32.is_gt(code, 32), Chr{code}))

def trim(text: String) -> String:
  String.reverse(leading(String.reverse(leading(text, None{})), None{}))

def retained(remove: Bool, char: Char, reversed: String) -> String:
  match remove:
    case True{}: reversed
    case False{}: SCon{char, reversed}

def filter(text: String, reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{Chr{+code}, rest}: filter(rest, retained(U32.is_eq(code, 9) || U32.is_eq(code, 10) || U32.is_eq(code, 13), Chr{code}, reversed))

def removeTabsAndNewlines(text: String) -> String: filter(text, "")
def prepare(text: String) -> String: removeTabsAndNewlines(trim(text))

type Found is Data:
  Found{scheme: Scheme.Scheme, remainder: String}

type Prefix is Data:
  Absolute{scheme: Scheme.Scheme, remainder: String}
  Relative{input: String}

# A failed candidate must not consume or lowercase a relative path. Keep the
# original immutable input only at the outer boundary, not in every scan frame.
def schemeChar(colon: Bool, code: U32, reversed: String) -> String:
  match colon:
    case True{}: reversed
    case False{}: SCon{Scheme.normalized(code), reversed}

def scan(text: String, valid: Bool, colon: Bool, reversed: String) -> Maybe<&2, Found>:
  match text valid colon:
    case _ False{} _: None{}
    case rest True{} True{}: Some{Found{Scheme.classify(String.reverse(reversed)), rest}}
    case SNil{} True{} False{}: None{}
    case SCon{Chr{+code}, rest} True{} False{}: scan(rest, Scheme.continuation(code) || U32.is_eq(code, 58), U32.is_eq(code, 58), schemeChar(U32.is_eq(code, 58), code, reversed))

def find(text: String) -> Maybe<&2, Found>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{+code}, rest}: scan(rest, Scheme.alpha(code), False{}, SCon{Scheme.normalized(code), ""})

def selected(found: Maybe<&2, Found>, original: String) -> Prefix:
  match found:
    case None{}: Relative{original}
    case Some{Found{scheme, remainder}}: Absolute{scheme, remainder}

# Input is already preprocessed. Absolute denotes a syntactically present
# scheme, not a successfully parsed URL; scheme-relative/base rules follow.
def prefix(+input: String) -> Prefix: selected(find(input), input)
