import Base
import ./unicode-17-category.bend as Category

# ECMAScript regular expressions (RegExp) as a backtracking matcher over
# Unicode scalars: capture groups, lookahead and lookbehind, backreferences,
# lazy and greedy quantifiers, and the flags i, m, s, g, y. The pattern
# language follows ECMA-262 with Annex B's web-compatible syntax outside
# unicode mode. Differences from JavaScript: indices count scalars, not
# UTF-16 code units; case-insensitive matching folds ASCII letters only; a
# match that needs more than the step budget fails instead of running on;
# the property escapes `\p{…}`/`\P{…}` know the General_Category classes
# L, N, P and S (Letter, Number, Punctuation, Symbol, optionally after `gc=`
# or `General_Category=`) and reject other properties as syntax errors.

# Syntax
# ------

type ClassItem is Data:
  Range{low: U32, high: U32}
  Digit{negated: Bool}
  Word{negated: Bool}
  Space{negated: Bool}
  # A General_Category class of unicode-17-category.bend (1 L, 2 N, 3 P, 4 S).
  Category{negated: Bool, category: U32}

# ASCII sets as four 32-bit words for codes 0-31, 32-63, 64-95 and 96-127.
type Ascii is Data: Ascii{w0: U32, w1: U32, w2: U32, w3: U32}

# What a match of the rest of the pattern needs of the scalar after a
# position that has one: nothing known, a scalar of a set (its ASCII members
# and whether any from 128 up can be one), or, after a repeated single-scalar
# atom, none that the atom accepts.
type Follow is Data:
  Anything{}
  Scalars{ascii: Ascii, wide: Bool}
  Disjoint{}

type Node is Data:
  Empty{}
  Literal{code: U32}
  AnyChar{}
  CharClass{negated: Bool, items: List<&2, ClassItem>}
  LineStart{}
  LineEnd{}
  WordBoundary{negated: Bool}
  Group{index: Maybe<&2, Nat>, body: Node}
  Look{ahead: Bool, negated: Bool, body: Node}
  Backref{index: Nat}
  NamedBackref{name: String}
  DecimalEscape{digits: List<&2, U32>}
  # `starts`: what each option, then the rest of the pattern, needs next
  # (see Continuations; empty until computed).
  Alternation{options: List<&2, Node>, starts: List<&2, Follow>}
  Sequence{items: List<&2, Node>}
  # `follow`: what the rest of the pattern needs next (see Continuations).
  Repeat{body: Node, min: Nat, max: Maybe<&2, Nat>, greedy: Bool, firstGroup: Nat, groupCount: Nat, follow: Follow}

type Flags is Data: Flags{global: Bool, ignoreCase: Bool, multiline: Bool, dotAll: Bool, unicode: Bool, sticky: Bool}

type NamedGroup is Data: NamedGroup{name: String, index: Nat}

type RegExp is Data: RegExp{source: String, flags: Flags, root: Node, groupCount: Nat, names: List<&2, NamedGroup>}

type Error is Data: SyntaxError{message: String}

def reversedCodes(text: String, codes: List<&2, U32>) -> List<&2, U32>:
  match text:
    case SNil{}: codes
    case SCon{Chr{code}, rest}: reversedCodes(rest, code <> codes)
def codes(text: String) -> List<&2, U32>: List.reverse(&2, U32, reversedCodes(text, Nil{}))

def reversedText(values: List<&2, U32>, text: String) -> String:
  match values:
    case Nil{}: text
    case code <> rest: reversedText(rest, SCon{Chr{code}, text})
def fromCodes(values: List<&2, U32>) -> String: reversedText(List.reverse(&2, U32, values), SNil{})

def isDigitCode(+code: U32) -> Bool: U32.is_ge(code, 48) && U32.is_le(code, 57)
def isWordCode(+code: U32) -> Bool:
  isDigitCode(code) || (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 97) && U32.is_le(code, 122)) || U32.is_eq(code, 95)
def isLineTerminator(+code: U32) -> Bool:
  U32.is_eq(code, 10) || U32.is_eq(code, 13) || U32.is_eq(code, 8232) || U32.is_eq(code, 8233)
# WhiteSpace and LineTerminator (the \s class).
def isSpaceCode(+code: U32) -> Bool:
  (U32.is_ge(code, 9) && U32.is_le(code, 13)) || U32.is_eq(code, 32) || U32.is_eq(code, 160) || U32.is_eq(code, 5760)
    || (U32.is_ge(code, 8192) && U32.is_le(code, 8202)) || U32.is_eq(code, 8232) || U32.is_eq(code, 8233)
    || U32.is_eq(code, 8239) || U32.is_eq(code, 8287) || U32.is_eq(code, 12288) || U32.is_eq(code, 65279)

def hexValue(+code: U32) -> Maybe<&2, U32>:
  Bool.pick(Unit -> Maybe<&2, U32>, isDigitCode(code), _ => Some{(code - 48 : U32)},
    _ => Bool.pick(Unit -> Maybe<&2, U32>, U32.is_ge(code, 97) && U32.is_le(code, 102), _ => Some{(code - 87 : U32)},
      _ => Bool.pick(Maybe<&2, U32>, U32.is_ge(code, 65) && U32.is_le(code, 70), Some{(code - 55 : U32)}, None{}))(Unit{}))(Unit{})

# Up to `count` hex digits into a value; None if fewer are present.
type Hex is Data: Hex{value: U32, rest: List<&2, U32>}
def hexOr(digit: Maybe<&2, U32>) -> U32: Maybe.default(&2, U32, digit, 0)
def isHex(digit: Maybe<&2, U32>) -> Bool: Bool.not(Maybe.is_none(&2, U32, digit))
def hexDigits(count: Nat, value: U32, input: List<&2, U32>) -> Maybe<&2, Hex>:
  match count input:
    case Zero{} input: Some{Hex{value, input}}
    case Succ{more} +code <> rest:
      Bool.pick(Unit -> Maybe<&2, Hex>, isHex(hexValue(code)), _ => hexDigits(more, (value * 16 + hexOr(hexValue(code)) : U32), rest), _ => None{})(Unit{})
    case Succ{_} Nil{}: None{}

# Escapes shared by atoms and classes: the resulting code and the remaining
# input; `c` escapes need a following letter (Annex B keeps "\c" literal).
type Escaped is Data: Escaped{code: U32, rest: List<&2, U32>}
def controlEscape(input: List<&2, U32>) -> Maybe<&2, Escaped>:
  match input:
    case +code <> rest: Bool.pick(Maybe<&2, Escaped>, (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 97) && U32.is_le(code, 122)), Some{Escaped{(code % 32 : U32), rest}}, None{})
    case Nil{}: None{}
def hexEscaped(fallback: U32, +input: List<&2, U32>, found: Maybe<&2, Hex>) -> Escaped:
  match found:
    case Some{Hex{value, rest}}: Escaped{value, rest}
    case None{}: Escaped{fallback, input}
# \xHH and \uHHHH; without enough digits the letter itself (identity escape).
def hexEscape(count: Nat, fallback: U32, +input: List<&2, U32>) -> Escaped:
  hexEscaped(fallback, input, hexDigits(count, 0, input))

# \u{...} in unicode mode: one to six hex digits up to 0x10FFFF.
def bracedHex(input: List<&2, U32>, +value: U32, +count: Nat) -> Maybe<&2, Escaped>:
  match input:
    case 125 <> rest: Bool.pick(Maybe<&2, Escaped>, Nat.is_gt(count, 0n) && U32.is_le(value, 1114111), Some{Escaped{value, rest}}, None{})
    case +code <> rest:
      Bool.pick(Unit -> Maybe<&2, Escaped>, isHex(hexValue(code)) && Nat.is_lt(count, 6n), _ => bracedHex(rest, (value * 16 + hexOr(hexValue(code)) : U32), count + 1n), _ => None{})(Unit{})
    case Nil{}: None{}

# Annex B legacy octal escapes: up to three octal digits with value <= 0o377.
def octalDigit(+code: U32) -> Bool: U32.is_ge(code, 48) && U32.is_le(code, 55)
def legacyThird(+value: U32, allowThird: Bool, input: List<&2, U32>) -> Escaped:
  match input:
    case +third <> +rest:
      Bool.pick(Unit -> Escaped, allowThird && octalDigit(third),
        _ => Escaped{(value * 8 + (third - 48 : U32) : U32), rest},
        _ => Escaped{value, third <> rest})(Unit{})
    case Nil{}: Escaped{value, Nil{}}
def legacyOctal(+first: U32, input: List<&2, U32>) -> Escaped:
  match input:
    case +second <> +rest2:
      Bool.pick(Unit -> Escaped, octalDigit(second),
        _ => legacyThird(((first - 48 : U32) * 8 + (second - 48 : U32) : U32), U32.is_le(first, 51), rest2),
        _ => Escaped{(first - 48 : U32), second <> rest2})(Unit{})
    case Nil{}: Escaped{(first - 48 : U32), Nil{}}

def decimalRun(input: List<&2, U32>, +digits: List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  match input:
    case +code <> +rest: Bool.pick(Unit -> List<&2, U32> & List<&2, U32>, isDigitCode(code), _ => decimalRun(rest, code <> digits), _ => (List.reverse(&2, U32, digits), code <> rest))(Unit{})
    case Nil{}: (List.reverse(&2, U32, digits), Nil{})
def decimalValue(digits: List<&2, U32>, value: Nat) -> Nat:
  match digits:
    case Nil{}: value
    case code <> rest: decimalValue(rest, value * 10n + U32.to_nat((code - 48 : U32)))

# Character classes
# -----------------

type ClassAtom is Data:
  ClassCode{code: U32}
  ClassSet{item: ClassItem}

type ClassStep is Data: ClassStep{atom: ClassAtom, rest: List<&2, U32>}

def classEscaped(value: Escaped) -> Result<&2, &2, Error, ClassStep>:
  match value: case Escaped{code, rest}: Done{ClassStep{ClassCode{code}, rest}}

def unicodeBraced(found: Maybe<&2, Escaped>) -> Result<&2, &2, Error, ClassStep>:
  match found:
    case Some{escaped}: classEscaped(escaped)
    case None{}: Fail{SyntaxError{"Invalid Unicode escape"}}
def unicodeEscape(unicode: Bool, input: List<&2, U32>) -> Result<&2, &2, Error, ClassStep>:
  match unicode input:
    case True{} 123 <> rest: unicodeBraced(bracedHex(rest, 0, 0n))
    case _ input: classEscaped(hexEscape(4n, 117, input))

def classControl(value: Maybe<&2, Escaped>, +rest: List<&2, U32>) -> Result<&2, &2, Error, ClassStep>:
  match value:
    case Some{escaped}: classEscaped(escaped)
    case None{}: Done{ClassStep{ClassCode{92}, 99 <> rest}}

# `\p{Name}` in unicode mode: the name up to '}' and the class it names.
def propertyCategory(name: String) -> Maybe<&2, U32>:
  match name:
    case "L": Some{1}
    case "Letter": Some{1}
    case "N": Some{2}
    case "Number": Some{2}
    case "P": Some{3}
    case "Punctuation": Some{3}
    case "S": Some{4}
    case "Symbol": Some{4}
    case _: None{}
def unprefixed(+name: String) -> String:
  Bool.pick(Unit -> String, String.starts_with(name, "gc="), _ => String.drop(name, 3n),
    _ => Bool.pick(Unit -> String, String.starts_with(name, "General_Category="), _ => String.drop(name, 17n), _ => name)(Unit{}))(Unit{})
def propertyNamed(negated: Bool, found: Maybe<&2, U32>, rest: List<&2, U32>) -> Result<&2, &2, Error, ClassStep>:
  match found:
    case Some{category}: Done{ClassStep{ClassSet{Category{negated, category}}, rest}}
    case None{}: Fail{SyntaxError{"Invalid property name"}}
def propertyName(negated: Bool, input: List<&2, U32>, +name: List<&2, U32>) -> Result<&2, &2, Error, ClassStep>:
  match input:
    case 125 <> rest: propertyNamed(negated, propertyCategory(unprefixed(fromCodes(List.reverse(&2, U32, name)))), rest)
    case code <> rest: propertyName(negated, rest, code <> name)
    case Nil{}: Fail{SyntaxError{"Invalid property name"}}
def propertyEscape(negated: Bool, input: List<&2, U32>) -> Result<&2, &2, Error, ClassStep>:
  match input:
    case 123 <> rest: propertyName(negated, rest, Nil{})
    case _: Fail{SyntaxError{"Invalid property name"}}

# Annex B: an escaped c without a control letter is a literal backslash.
def classEscapeLetter(+code: U32, +rest: List<&2, U32>, unicode: Bool) -> Result<&2, &2, Error, ClassStep>:
  match code:
    case 100: Done{ClassStep{ClassSet{Digit{False{}}}, rest}}
    case 68: Done{ClassStep{ClassSet{Digit{True{}}}, rest}}
    case 119: Done{ClassStep{ClassSet{Word{False{}}}, rest}}
    case 87: Done{ClassStep{ClassSet{Word{True{}}}, rest}}
    case 115: Done{ClassStep{ClassSet{Space{False{}}}, rest}}
    case 83: Done{ClassStep{ClassSet{Space{True{}}}, rest}}
    case 98: Done{ClassStep{ClassCode{8}, rest}}
    case 116: Done{ClassStep{ClassCode{9}, rest}}
    case 110: Done{ClassStep{ClassCode{10}, rest}}
    case 118: Done{ClassStep{ClassCode{11}, rest}}
    case 102: Done{ClassStep{ClassCode{12}, rest}}
    case 114: Done{ClassStep{ClassCode{13}, rest}}
    case 120: classEscaped(hexEscape(2n, 120, rest))
    case 117: unicodeEscape(unicode, rest)
    case 99: classControl(controlEscape(rest), rest)
    case 112: Bool.pick(Unit -> Result<&2, &2, Error, ClassStep>, unicode, _ => propertyEscape(False{}, rest), _ => Done{ClassStep{ClassCode{112}, rest}})(Unit{})
    case 80: Bool.pick(Unit -> Result<&2, &2, Error, ClassStep>, unicode, _ => propertyEscape(True{}, rest), _ => Done{ClassStep{ClassCode{80}, rest}})(Unit{})
    case _: Bool.pick(Unit -> Result<&2, &2, Error, ClassStep>, octalDigit(code) && Bool.not(unicode), _ => classEscaped(legacyOctal(code, rest)), _ => Done{ClassStep{ClassCode{code}, rest}})(Unit{})

def classAtom(input: List<&2, U32>, unicode: Bool) -> Result<&2, &2, Error, ClassStep>:
  match input:
    case 92 <> code <> rest: classEscapeLetter(code, rest, unicode)
    case 92 <> Nil{}: Fail{SyntaxError{"\\ at end of pattern"}}
    case code <> rest: Done{ClassStep{ClassCode{code}, rest}}
    case Nil{}: Fail{SyntaxError{"Unterminated character class"}}

def rangeItem(low: ClassAtom, high: ClassAtom) -> Result<&2, &2, Error, ClassItem>:
  match low high:
    case ClassCode{+a} ClassCode{+b}: Bool.pick(Result<&2, &2, Error, ClassItem>, U32.is_le(a, b), Done{Range{a, b}}, Fail{SyntaxError{"Range out of order in character class"}})
    case _ _: Fail{SyntaxError{"Invalid character class"}}

def itemOf(atom: ClassAtom) -> ClassItem:
  match atom:
    case ClassCode{+code}: Range{code, code}
    case ClassSet{item}: item

# Class bodies are read one atom at a time; "a-b" forms a range, and in
# Annex B mode a set escape beside '-' leaves the '-' literal. One step reads
# one atom; `pending` is the last atom, which a following '-' may extend.
type ClassBody is Data: ClassBody{items: List<&2, ClassItem>, rest: List<&2, U32>}
type ClassState is Data:
  ClassReading{input: List<&2, U32>, items: List<&2, ClassItem>, pending: Maybe<&2, ClassAtom>}
  ClassDone{body: ClassBody}
  ClassFailed{error: Error}

def isSet(atom: ClassAtom) -> Bool:
  match atom:
    case ClassSet{_}: True{}
    case ClassCode{_}: False{}

def flushed(pending: Maybe<&2, ClassAtom>, items: List<&2, ClassItem>) -> List<&2, ClassItem>:
  match pending:
    case None{}: items
    case Some{atom}: itemOf(atom) <> items

def afterAtom(result: Result<&2, &2, Error, ClassStep>, items: List<&2, ClassItem>) -> ClassState:
  match result:
    case Fail{error}: ClassFailed{error}
    case Done{ClassStep{atom, rest}}: ClassReading{rest, items, Some{atom}}

# `low` '-' `high`: a range between codes; beside a set, three items (Annex B)
# or an error in unicode mode.
def rangedCodes(result: Result<&2, &2, Error, ClassItem>, rest: List<&2, U32>, items: List<&2, ClassItem>) -> ClassState:
  match result:
    case Fail{error}: ClassFailed{error}
    case Done{item}: ClassReading{rest, item <> items, None{}}
def rangedWith(sets: Bool, unicode: Bool, low: ClassAtom, high: ClassAtom, rest: List<&2, U32>, items: List<&2, ClassItem>) -> ClassState:
  match sets unicode:
    case True{} True{}: ClassFailed{SyntaxError{"Invalid character class"}}
    case True{} False{}: ClassReading{rest, itemOf(high) <> Range{45, 45} <> itemOf(low) <> items, None{}}
    case False{} _: rangedCodes(rangeItem(low, high), rest, items)
def ranged(+low: ClassAtom, +high: ClassAtom, rest: List<&2, U32>, items: List<&2, ClassItem>, unicode: Bool) -> ClassState:
  rangedWith(isSet(low) || isSet(high), unicode, low, high, rest, items)
def rangeEnd(+low: ClassAtom, result: Result<&2, &2, Error, ClassStep>, items: List<&2, ClassItem>, unicode: Bool) -> ClassState:
  match result:
    case Fail{error}: ClassFailed{error}
    case Done{ClassStep{high, rest}}: ranged(low, high, rest, items, unicode)

def classStep(state: ClassState, +unicode: Bool) -> ClassState:
  match state:
    case ClassReading{93 <> rest, +items, pending}: ClassDone{ClassBody{List.reverse(&2, ClassItem, flushed(pending, items)), rest}}
    case ClassReading{45 <> +rest, +items, Some{+low}}:
      Bool.pick(Unit -> ClassState, List.is_empty(&2, U32, rest) || U32.is_eq(Maybe.default(&2, U32, List.head(&2, U32, rest), 0), 93),
        _ => ClassReading{rest, Range{45, 45} <> itemOf(low) <> items, None{}},
        _ => rangeEnd(low, classAtom(rest, unicode), items, unicode))(Unit{})
    case ClassReading{input, items, pending}: afterAtom(classAtom(input, unicode), flushed(pending, items))
    case other: other

def classLoop(fuel: Nat, state: ClassState, +unicode: Bool) -> Result<&2, &2, Error, ClassBody>:
  match fuel state:
    case _ ClassDone{body}: Done{body}
    case _ ClassFailed{error}: Fail{error}
    case Zero{} _: Fail{SyntaxError{"Unterminated character class"}}
    case Succ{more} state: classLoop(more, classStep(state, unicode), unicode)

# After '[' (and '^'): the class items up to the closing ']'.
def classBody(+input: List<&2, U32>, unicode: Bool) -> Result<&2, &2, Error, ClassBody>:
  classLoop(List.length(&2, U32, input) + 1n, ClassReading{input, Nil{}, None{}}, unicode)

# Pattern parsing
# ---------------

# A term with the capture groups it contains (for clearing on repetition) and
# whether a quantifier may follow it.
type Term is Data: Term{node: Node, firstGroup: Nat, groupCount: Nat, quantifiable: Bool}
type GroupKind is Data:
  RootGroup{}
  CaptureGroup{index: Nat}
  PlainGroup{}
  LookGroup{ahead: Bool, negated: Bool}
# An open group: capture groups allocated before it, finished alternatives
# (reversed) and the current alternative's terms (reversed).
type Frame is Data: Frame{kind: GroupKind, opened: Nat, alternatives: List<&2, Node>, terms: List<&2, Term>}
type ParseState is Data:
  Parsing{input: List<&2, U32>, frames: List<&2, Frame>, groups: Nat, names: List<&2, NamedGroup>}
  Parsed{root: Node, groups: Nat, names: List<&2, NamedGroup>}
  ParseFailed{error: Error}

def termNodes(terms: List<&2, Term>, nodes: List<&2, Node>) -> List<&2, Node>:
  match terms:
    case Nil{}: nodes
    case Term{node, _, _, _} <> rest: termNodes(rest, node <> nodes)
def singleOr(nodes: List<&2, Node>) -> Node:
  match nodes:
    case node <> Nil{}: node
    case nodes: Sequence{nodes}
def sequenceOf(terms: List<&2, Term>) -> Node: singleOr(termNodes(terms, Nil{}))
def alternationOf(alternatives: List<&2, Node>, terms: List<&2, Term>) -> Node:
  match alternatives:
    case Nil{}: sequenceOf(terms)
    case _: Alternation{List.reverse(&2, Node, sequenceOf(terms) <> alternatives), Nil{}}
def kindNode(kind: GroupKind, body: Node) -> Node:
  match kind:
    case RootGroup{}: body
    case CaptureGroup{index}: Group{Some{index}, body}
    case PlainGroup{}: Group{None{}, body}
    case LookGroup{ahead, negated}: Look{ahead, negated, body}
# Lookbehinds are never quantifiable; lookaheads only in Annex B mode.
def kindQuantifiable(kind: GroupKind, unicode: Bool) -> Bool:
  match kind:
    case LookGroup{True{}, _}: Bool.not(unicode)
    case LookGroup{False{}, _}: False{}
    case _: True{}

def withTerm(frames: List<&2, Frame>, term: Term) -> List<&2, Frame>:
  match frames:
    case Frame{kind, opened, alternatives, terms} <> rest: Frame{kind, opened, alternatives, term <> terms} <> rest
    case Nil{}: Nil{}
def pushed(state: ParseState, +term: Term, rest: List<&2, U32>) -> ParseState:
  match state:
    case Parsing{_, frames, groups, names}: Parsing{rest, withTerm(frames, term), groups, names}
    case other: other
def atom(node: Node) -> Term: Term{node, 0n, 0n, True{}}
def assertion(node: Node) -> Term: Term{node, 0n, 0n, False{}}

# Quantifiers: {n}, {n,}, {n,m}; Annex B reads an invalid brace as a literal.
type Bounds is Data: Bounds{min: Nat, max: Maybe<&2, Nat>, rest: List<&2, U32>}
def braceClose(min: Nat, max: Maybe<&2, Nat>, input: List<&2, U32>) -> Maybe<&2, Bounds>:
  match input:
    case 125 <> rest: Some{Bounds{min, max, rest}}
    case _: None{}
def braceUpperRun(+min: Nat, run: List<&2, U32> & List<&2, U32>) -> Maybe<&2, Bounds>:
  match run:
    case (Nil{}, rest): braceClose(min, None{}, rest)
    case (digits, rest): braceClose(min, Some{decimalValue(digits, 0n)}, rest)
def braceUpper(+min: Nat, input: List<&2, U32>) -> Maybe<&2, Bounds>: braceUpperRun(min, decimalRun(input, Nil{}))
def braceAfterMin(+min: Nat, input: List<&2, U32>) -> Maybe<&2, Bounds>:
  match input:
    case 44 <> rest: braceUpper(min, rest)
    case input: braceClose(min, Some{min}, input)
def braceBoundsRun(run: List<&2, U32> & List<&2, U32>) -> Maybe<&2, Bounds>:
  match run:
    case (Nil{}, _): None{}
    case (digits, rest): braceAfterMin(decimalValue(digits, 0n), rest)
def braceBounds(input: List<&2, U32>) -> Maybe<&2, Bounds>: braceBoundsRun(decimalRun(input, Nil{}))

type Quantifier is Data: Quantifier{min: Nat, max: Maybe<&2, Nat>, greedy: Bool, rest: List<&2, U32>}
def laziness(min: Nat, max: Maybe<&2, Nat>, input: List<&2, U32>) -> Quantifier:
  match input:
    case 63 <> rest: Quantifier{min, max, False{}, rest}
    case input: Quantifier{min, max, True{}, input}
def boundsQuantifier(bounds: Bounds) -> Quantifier:
  match bounds: case Bounds{min, max, rest}: laziness(min, max, rest)
def quantifierAt(input: List<&2, U32>) -> Maybe<&2, Quantifier>:
  match input:
    case 42 <> rest: Some{laziness(0n, None{}, rest)}
    case 43 <> rest: Some{laziness(1n, None{}, rest)}
    case 63 <> rest: Some{laziness(0n, Some{1n}, rest)}
    case 123 <> rest: Maybe.map(&2, Bounds, Quantifier, bounds => boundsQuantifier(bounds), braceBounds(rest))
    case _: None{}

def failed(message: String) -> ParseState: ParseFailed{SyntaxError{message}}

def lastQuantified(frames: List<&2, Frame>, quantifier: Quantifier, +groups: Nat, +names: List<&2, NamedGroup>) -> ParseState:
  match frames quantifier:
    case Frame{kind, opened, alternatives, Term{node, +first, +count, True{}} <> terms} <> rest Quantifier{min, max, greedy, input}:
      Parsing{input, Frame{kind, opened, alternatives, Term{Repeat{node, min, max, greedy, first, count, Anything{}}, first, count, False{}} <> terms} <> rest, groups, names}
    case _ _: failed("Nothing to repeat")

# A '{' that does not start a quantifier is a literal in Annex B mode.
def quantified(+input: List<&2, U32>, found: Maybe<&2, Quantifier>, frames: List<&2, Frame>, +groups: Nat, +names: List<&2, NamedGroup>, unicode: Bool) -> ParseState:
  match found unicode:
    case Some{quantifier} _: lastQuantified(frames, quantifier, groups, names)
    case None{} True{}: failed("Incomplete quantifier")
    case None{} False{}: Parsing{List.drop(&2, U32, input, 1n), withTerm(frames, atom(Literal{123})), groups, names}

def alternated(frames: List<&2, Frame>) -> List<&2, Frame>:
  match frames:
    case Frame{kind, opened, alternatives, terms} <> rest: Frame{kind, opened, sequenceOf(terms) <> alternatives, Nil{}} <> rest
    case Nil{}: Nil{}

type Named is Data: Named{name: List<&2, U32>, rest: List<&2, U32>}
def nameChars(input: List<&2, U32>, +name: List<&2, U32>) -> Maybe<&2, Named>:
  match input:
    case 62 <> rest: Bool.pick(Maybe<&2, Named>, List.is_empty(&2, U32, name), None{}, Some{Named{List.reverse(&2, U32, name), rest}})
    case +code <> rest: Bool.pick(Unit -> Maybe<&2, Named>, isWordCode(code) || U32.is_eq(code, 36) || U32.is_gt(code, 127), _ => nameChars(rest, code <> name), _ => None{})(Unit{})
    case Nil{}: None{}

def openFrame(kind: GroupKind, rest: List<&2, U32>, frames: List<&2, Frame>, +groups: Nat, names: List<&2, NamedGroup>) -> ParseState:
  Parsing{rest, Frame{kind, groups, Nil{}, Nil{}} <> frames, groups, names}
def openCapture(rest: List<&2, U32>, frames: List<&2, Frame>, +groups: Nat, names: List<&2, NamedGroup>) -> ParseState:
  Parsing{rest, Frame{CaptureGroup{groups + 1n}, groups, Nil{}, Nil{}} <> frames, groups + 1n, names}
def openNamed(found: Maybe<&2, Named>, frames: List<&2, Frame>, +groups: Nat, names: List<&2, NamedGroup>) -> ParseState:
  match found:
    case None{}: failed("Invalid capture group name")
    case Some{Named{name, rest}}: Parsing{rest, Frame{CaptureGroup{groups + 1n}, groups, Nil{}, Nil{}} <> frames, groups + 1n, NamedGroup{fromCodes(name), groups + 1n} <> names}

def openAngle(input: List<&2, U32>, frames: List<&2, Frame>, +groups: Nat, names: List<&2, NamedGroup>) -> ParseState:
  match input:
    case 61 <> rest: openFrame(LookGroup{False{}, False{}}, rest, frames, groups, names)
    case 33 <> rest: openFrame(LookGroup{False{}, True{}}, rest, frames, groups, names)
    case rest: openNamed(nameChars(rest, Nil{}), frames, groups, names)
def openSpecial(input: List<&2, U32>, frames: List<&2, Frame>, +groups: Nat, names: List<&2, NamedGroup>) -> ParseState:
  match input:
    case 58 <> rest: openFrame(PlainGroup{}, rest, frames, groups, names)
    case 61 <> rest: openFrame(LookGroup{True{}, False{}}, rest, frames, groups, names)
    case 33 <> rest: openFrame(LookGroup{True{}, True{}}, rest, frames, groups, names)
    case 60 <> rest: openAngle(rest, frames, groups, names)
    case _: failed("Invalid group")
def opened(input: List<&2, U32>, frames: List<&2, Frame>, +groups: Nat, names: List<&2, NamedGroup>) -> ParseState:
  match input:
    case 63 <> rest: openSpecial(rest, frames, groups, names)
    case rest: openCapture(rest, frames, groups, names)

def closedFrame(frame: Frame, parent: List<&2, Frame>, rest: List<&2, U32>, +groups: Nat, names: List<&2, NamedGroup>, unicode: Bool) -> ParseState:
  match frame:
    case Frame{+group, +before, alternatives, terms}:
      Parsing{rest, withTerm(parent, Term{kindNode(group, alternationOf(alternatives, terms)), before + 1n, groups - before, kindQuantifiable(group, unicode)}), groups, names}
def closed(rest: List<&2, U32>, frames: List<&2, Frame>, +groups: Nat, names: List<&2, NamedGroup>, unicode: Bool) -> ParseState:
  match frames:
    case Frame{RootGroup{}, _, _, _} <> _: failed("Unmatched ')'")
    case frame <> parent: closedFrame(frame, parent, rest, groups, names, unicode)
    case Nil{}: failed("Unmatched ')'")

def finished(frames: List<&2, Frame>, groups: Nat, names: List<&2, NamedGroup>) -> ParseState:
  match frames:
    case Frame{RootGroup{}, _, alternatives, terms} <> Nil{}: Parsed{alternationOf(alternatives, terms), groups, List.reverse(&2, NamedGroup, names)}
    case _: failed("Unterminated group")

# A class escape used as an atom: a code is a literal, a set a one-item class.
def escapedAtom(result: Result<&2, &2, Error, ClassStep>, frames: List<&2, Frame>, groups: Nat, names: List<&2, NamedGroup>) -> ParseState:
  match result:
    case Fail{error}: ParseFailed{error}
    case Done{ClassStep{ClassCode{code}, rest}}: Parsing{rest, withTerm(frames, atom(Literal{code})), groups, names}
    case Done{ClassStep{ClassSet{item}, rest}}: Parsing{rest, withTerm(frames, atom(CharClass{False{}, [item]})), groups, names}

def decimalAtom(run: List<&2, U32> & List<&2, U32>, frames: List<&2, Frame>, groups: Nat, names: List<&2, NamedGroup>) -> ParseState:
  match run:
    case (digits, rest): Parsing{rest, withTerm(frames, atom(DecimalEscape{digits})), groups, names}

def namedReference(found: Maybe<&2, Named>, +input: List<&2, U32>, frames: List<&2, Frame>, groups: Nat, names: List<&2, NamedGroup>) -> ParseState:
  match found:
    case Some{Named{name, rest}}: Parsing{rest, withTerm(frames, atom(NamedBackref{fromCodes(name)})), groups, names}
    case None{}: Parsing{input, withTerm(frames, atom(Literal{107})), groups, names}

def referenceEscape(+input: List<&2, U32>, frames: List<&2, Frame>, +groups: Nat, +names: List<&2, NamedGroup>) -> ParseState:
  match input:
    case 60 <> rest: namedReference(nameChars(rest, Nil{}), input, frames, groups, names)
    case rest: Parsing{rest, withTerm(frames, atom(Literal{107})), groups, names}
def octalStep(value: Escaped) -> ClassStep:
  match value: case Escaped{code, rest}: ClassStep{ClassCode{code}, rest}

def legacyZero(input: List<&2, U32>, unicode: Bool) -> ClassStep:
  match input unicode:
    case +code <> +rest False{}: Bool.pick(Unit -> ClassStep, octalDigit(code), _ => octalStep(legacyOctal(48, code <> rest)), _ => ClassStep{ClassCode{0}, code <> rest})(Unit{})
    case input _: ClassStep{ClassCode{0}, input}
# \0 is NUL unless a digit follows; Annex B then reads a legacy octal escape.
def escapedCode(+code: U32, +rest: List<&2, U32>, +frames: List<&2, Frame>, +groups: Nat, +names: List<&2, NamedGroup>, unicode: Bool) -> ParseState:
  match code:
    case 98: Parsing{rest, withTerm(frames, assertion(WordBoundary{False{}})), groups, names}
    case 66: Parsing{rest, withTerm(frames, assertion(WordBoundary{True{}})), groups, names}
    case 107: referenceEscape(rest, frames, groups, names)
    case 48: escapedAtom(Done{legacyZero(rest, unicode)}, frames, groups, names)
    case _: Bool.pick(Unit -> ParseState, isDigitCode(code), _ => decimalAtom(decimalRun(code <> rest, Nil{}), frames, groups, names), _ => escapedAtom(classEscapeLetter(code, rest, unicode), frames, groups, names))(Unit{})
def escaped(input: List<&2, U32>, frames: List<&2, Frame>, +groups: Nat, +names: List<&2, NamedGroup>, unicode: Bool) -> ParseState:
  match input:
    case Nil{}: failed("\\ at end of pattern")
    case code <> rest: escapedCode(code, rest, frames, groups, names, unicode)

def classAtomNode(negated: Bool, result: Result<&2, &2, Error, ClassBody>, frames: List<&2, Frame>, groups: Nat, names: List<&2, NamedGroup>) -> ParseState:
  match result:
    case Fail{error}: ParseFailed{error}
    case Done{ClassBody{items, rest}}: Parsing{rest, withTerm(frames, atom(CharClass{negated, items})), groups, names}
def classOpened(input: List<&2, U32>, frames: List<&2, Frame>, groups: Nat, names: List<&2, NamedGroup>, +unicode: Bool) -> ParseState:
  match input:
    case 94 <> rest: classAtomNode(True{}, classBody(rest, unicode), frames, groups, names)
    case input: classAtomNode(False{}, classBody(input, unicode), frames, groups, names)

def parseStep(state: ParseState, +unicode: Bool) -> ParseState:
  match state:
    case Parsing{Nil{}, frames, groups, names}: finished(frames, groups, names)
    case Parsing{124 <> +rest, frames, groups, names}: Parsing{rest, alternated(frames), groups, names}
    case Parsing{40 <> +rest, frames, groups, names}: opened(rest, frames, groups, names)
    case Parsing{41 <> +rest, frames, groups, names}: closed(rest, frames, groups, names, unicode)
    case Parsing{94 <> +rest, frames, groups, names}: Parsing{rest, withTerm(frames, assertion(LineStart{})), groups, names}
    case Parsing{36 <> +rest, frames, groups, names}: Parsing{rest, withTerm(frames, assertion(LineEnd{})), groups, names}
    case Parsing{46 <> +rest, frames, groups, names}: Parsing{rest, withTerm(frames, atom(AnyChar{})), groups, names}
    case Parsing{92 <> +rest, frames, groups, names}: escaped(rest, frames, groups, names, unicode)
    case Parsing{91 <> +rest, frames, groups, names}: classOpened(rest, frames, groups, names, unicode)
    case Parsing{42 <> +rest, frames, groups, names}: quantified(42 <> rest, quantifierAt(42 <> rest), frames, groups, names, unicode)
    case Parsing{43 <> +rest, frames, groups, names}: quantified(43 <> rest, quantifierAt(43 <> rest), frames, groups, names, unicode)
    case Parsing{63 <> +rest, frames, groups, names}: quantified(63 <> rest, quantifierAt(63 <> rest), frames, groups, names, unicode)
    case Parsing{123 <> +rest, frames, groups, names}: quantified(123 <> rest, quantifierAt(123 <> rest), frames, groups, names, unicode)
    case Parsing{code <> rest, frames, groups, names}: Parsing{rest, withTerm(frames, atom(Literal{code})), groups, names}
    case other: other

def parseLoop(fuel: Nat, state: ParseState, +unicode: Bool) -> ParseState:
  match fuel state:
    case _ Parsed{root, groups, names}: Parsed{root, groups, names}
    case _ ParseFailed{error}: ParseFailed{error}
    case Zero{} _: failed("Pattern too complex")
    case Succ{more} state: parseLoop(more, parseStep(state, unicode), unicode)

# Decimal escapes and named references resolve when matched, once the
# group count and names are known (Annex B needs the count).

def literals(codes: List<&2, U32>) -> List<&2, Node>:
  match codes:
    case Nil{}: Nil{}
    case code <> rest: Literal{code} <> literals(rest)

def octalNode(value: Escaped) -> Node:
  match value: case Escaped{code, rest}: Sequence{Literal{code} <> literals(rest)}

# Annex B: \N beyond the group count is a legacy octal escape followed by
# literal digits, or an identity escape for 8 and 9.
def decimalLiteral(digits: List<&2, U32>) -> Node:
  match digits:
    case Nil{}: Empty{}
    case +first <> +rest:
      Bool.pick(Unit -> Node, octalDigit(first), _ => octalNode(legacyOctal(first, rest)), _ => Sequence{literals(first <> rest)})(Unit{})
def decimalResolved(+digits: List<&2, U32>, +groups: Nat) -> Node:
  +value = decimalValue(digits, 0n)
  Bool.pick(Unit -> Node, Nat.is_le(value, groups) && Nat.is_gt(value, 0n), _ => Backref{value}, _ => decimalLiteral(digits))(Unit{})

def namedIndex(names: List<&2, NamedGroup>, +name: String) -> Maybe<&2, Nat>:
  match names:
    case Nil{}: None{}
    case NamedGroup{+other, index} <> rest: Bool.pick(Unit -> Maybe<&2, Nat>, String.eq(other, name), _ => Some{index}, _ => namedIndex(rest, name))(Unit{})
def namedResolved(found: Maybe<&2, Nat>, +name: String) -> Node:
  match found:
    case Some{index}: Backref{index}
    case None{}: Sequence{literals(codes("k<" ++ name ++ ">"))}

# Flags
# -----

def noFlags() -> Flags: Flags{False{}, False{}, False{}, False{}, False{}, False{}}
def withFlag(flags: Flags, code: U32) -> Maybe<&2, Flags>:
  match flags code:
    case Flags{False{}, i, m, s, u, y} 103: Some{Flags{True{}, i, m, s, u, y}}
    case Flags{g, False{}, m, s, u, y} 105: Some{Flags{g, True{}, m, s, u, y}}
    case Flags{g, i, False{}, s, u, y} 109: Some{Flags{g, i, True{}, s, u, y}}
    case Flags{g, i, m, False{}, u, y} 115: Some{Flags{g, i, m, True{}, u, y}}
    case Flags{g, i, m, s, False{}, y} 117: Some{Flags{g, i, m, s, True{}, y}}
    case Flags{g, i, m, s, u, False{}} 121: Some{Flags{g, i, m, s, u, True{}}}
    case flags 100: Some{flags}
    case _ _: None{}
def parsedFlags(input: List<&2, U32>, flags: Maybe<&2, Flags>) -> Maybe<&2, Flags>:
  match input flags:
    case _ None{}: None{}
    case Nil{} flags: flags
    case code <> rest Some{current}: parsedFlags(rest, withFlag(current, code))

def unicodeOf(flags: Flags) -> Bool:
  match flags: case Flags{_, _, _, _, unicode, _}: unicode

# 2 to the power `bit`, for bits 0 to 31.
def power(bit: U32) -> U32:
  match bit:
    case 0: 1
    case 1: 2
    case 2: 4
    case 3: 8
    case 4: 16
    case 5: 32
    case 6: 64
    case 7: 128
    case 8: 256
    case 9: 512
    case 10: 1024
    case 11: 2048
    case 12: 4096
    case 13: 8192
    case 14: 16384
    case 15: 32768
    case 16: 65536
    case 17: 131072
    case 18: 262144
    case 19: 524288
    case 20: 1048576
    case 21: 2097152
    case 22: 4194304
    case 23: 8388608
    case 24: 16777216
    case 25: 33554432
    case 26: 67108864
    case 27: 134217728
    case 28: 268435456
    case 29: 536870912
    case 30: 1073741824
    case 31: 2147483648
    case _: 0
# Whether an ASCII set holds `code` (below 128).
def asciiHas(set: Ascii, +code: U32) -> Bool:
  match set:
    case Ascii{a, b, c, d}:
      +word = Bool.pick(U32, U32.is_lt(code, 64), Bool.pick(U32, U32.is_lt(code, 32), a, b), Bool.pick(U32, U32.is_lt(code, 96), c, d))
      Bool.not(U32.is_eq(U32.and(word, power((code % 32 : U32))), 0))

# Matching
# --------

type Span is Data: Span{start: Nat, end: Nat}
# The input around the current position, oriented in the matching direction:
# `ahead` holds the scalars still to read (forwards those after the position,
# backwards, in a lookbehind, those before it, nearest first) and `passed`
# the scalar on the other side, the one last stepped over. A step takes one
# node of `ahead` and allocates nothing; a lookaround that turns the direction
# rebuilds `ahead` from the subject.
type Cursor is Data: Cursor{passed: Maybe<&2, U32>, ahead: List<&2, U32>, index: Nat}

# Goals still to match; Iterate and AfterIteration follow ECMA-262
# RepeatMatcher with the remaining `min`/`max`.
type Goal is Data:
  RunNode{node: Node, forward: Bool}
  CloseGroup{group: Nat, start: Nat, forward: Bool}
  Iterate{body: Node, min: Nat, max: Maybe<&2, Nat>, greedy: Bool, first: Nat, count: Nat, follow: Follow, forward: Bool}
  AfterIteration{body: Node, min: Nat, max: Maybe<&2, Nat>, greedy: Bool, first: Nat, count: Nat, follow: Follow, start: Nat, forward: Bool}
  # A greedy run of single scalars gives back `taken` (the last first) down
  # to `remaining` of them; `passed` is the scalar before the run.
  GiveBack{taken: List<&2, U32>, remaining: Nat, passed: Maybe<&2, U32>, follow: Follow, forward: Bool}
  TakeMore{node: Node, remaining: Maybe<&2, Nat>, follow: Follow, forward: Bool}
  LookDone{}

# Backtracking points. A Barrier delimits a lookaround: reaching LookDone
# discards the choices above it (lookarounds are atomic), and exhausting them
# pops the Barrier, which resumes after a negative lookaround. Alternatives
# holds the untried options of a disjunction (each continuing with `goals`)
# and yields them one at a time.
type Choice is Data:
  Alternative{goals: List<&2, Goal>, cursor: Cursor, captures: List<&2, Maybe<&2, Span>>}
  Alternatives{options: List<&2, Node>, forward: Bool, goals: List<&2, Goal>, cursor: Cursor, captures: List<&2, Maybe<&2, Span>>}
  Barrier{negated: Bool, goals: List<&2, Goal>, cursor: Cursor, captures: List<&2, Maybe<&2, Span>>}

type Machine is Data:
  Running{goals: List<&2, Goal>, cursor: Cursor, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>}
  Succeeded{cursor: Cursor, captures: List<&2, Maybe<&2, Span>>}
  NoMatch{}

type Settings is Data: Settings{ignoreCase: Bool, multiline: Bool, dotAll: Bool, input: List<&2, U32>, groups: Nat, names: List<&2, NamedGroup>}

def untried(options: List<&2, Node>, forward: Bool, goals: List<&2, Goal>, cursor: Cursor, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> List<&2, Choice>:
  match options:
    case Nil{}: choices
    case options: Alternatives{options, forward, goals, cursor, captures} <> choices
def backtrack(choices: List<&2, Choice>) -> Machine:
  match choices:
    case Nil{}: NoMatch{}
    case Alternative{+goals, +cursor, +captures} <> rest: Running{goals, cursor, captures, rest}
    case Alternatives{option <> more, +forward, +goals, +cursor, +captures} <> rest: Running{RunNode{option, forward} <> goals, cursor, captures, untried(more, forward, goals, cursor, captures, rest)}
    case Alternatives{Nil{}, _, _, _, _} <> rest: backtrack(rest)
    case Barrier{True{}, goals, cursor, captures} <> rest: Running{goals, cursor, captures, rest}
    case Barrier{False{}, _, _, _} <> rest: backtrack(rest)

# LookDone: the lookaround body matched. Positive: continue after it with its
# captures; negative: the lookaround fails.
def lookMatched(choices: List<&2, Choice>, captures: List<&2, Maybe<&2, Span>>) -> Machine:
  match choices:
    case Nil{}: NoMatch{}
    case Alternative{_, _, _} <> rest: lookMatched(rest, captures)
    case Alternatives{_, _, _, _, _} <> rest: lookMatched(rest, captures)
    case Barrier{False{}, goals, cursor, _} <> rest: Running{goals, cursor, captures, rest}
    case Barrier{True{}, _, _, _} <> rest: backtrack(rest)

# ASCII case folding (Canonicalize for letters).
def upper(+code: U32) -> U32: Bool.pick(U32, U32.is_ge(code, 97) && U32.is_le(code, 122), (code - 32 : U32), code)
def lower(+code: U32) -> U32: Bool.pick(U32, U32.is_ge(code, 65) && U32.is_le(code, 90), (code + 32 : U32), code)
def sameChar(ignoreCase: Bool, +left: U32, +right: U32) -> Bool:
  match ignoreCase:
    case True{}: U32.is_eq(upper(left), upper(right))
    case False{}: U32.is_eq(left, right)

def itemHas(item: ClassItem, +code: U32) -> Bool:
  match item:
    case Range{low, high}: U32.is_ge(code, low) && U32.is_le(code, high)
    case Digit{negated}: Bool.xor(isDigitCode(code), negated)
    case Word{negated}: Bool.xor(isWordCode(code), negated)
    case Space{negated}: Bool.xor(isSpaceCode(code), negated)
    case Category{negated, category}: Bool.xor(U32.is_eq(Category.category(code), category), negated)
def itemsHave(items: List<&2, ClassItem>, +code: U32) -> Bool:
  match items:
    case Nil{}: False{}
    case item <> rest: itemHas(item, code) || itemsHave(rest, code)
def classHas(ignoreCase: Bool, +items: List<&2, ClassItem>, +code: U32) -> Bool:
  match ignoreCase:
    case True{}: itemsHave(items, code) || itemsHave(items, upper(code)) || itemsHave(items, lower(code))
    case False{}: itemsHave(items, code)

def nodeAccepts(node: Node, settings: Settings, +code: U32) -> Bool:
  match node settings:
    case Literal{expected} Settings{ignoreCase, _, _, _, _, _}: sameChar(ignoreCase, expected, code)
    case AnyChar{} Settings{_, _, dotAll, _, _, _}: dotAll || Bool.not(isLineTerminator(code))
    case CharClass{negated, items} Settings{ignoreCase, _, _, _, _, _}: Bool.xor(classHas(ignoreCase, items, code), negated)
    case _ _: False{}
# The index one step on in the matching direction, and one step back.
def toward(+index: Nat, forward: Bool) -> Nat:
  match forward:
    case True{}: index + 1n
    case False{}: index - 1n
def away(+index: Nat, forward: Bool) -> Nat:
  match forward:
    case True{}: index - 1n
    case False{}: index + 1n
def stepped(cursor: Cursor, forward: Bool) -> Maybe<&2, Cursor>:
  match cursor:
    case Cursor{_, code <> ahead, index}: Some{Cursor{Some{code}, ahead, toward(index, forward)}}
    case Cursor{_, Nil{}, _}: None{}

# One scalar in the matching direction.
def consumed(accepted: Bool, cursor: Cursor, goals: List<&2, Goal>, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match accepted:
    case True{}: Running{goals, cursor, captures, choices}
    case False{}: backtrack(choices)
def single(node: Node, settings: Settings, cursor: Cursor, forward: Bool, goals: List<&2, Goal>, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match cursor:
    case Cursor{_, +code <> ahead, index}: consumed(nodeAccepts(node, settings, code), Cursor{Some{code}, ahead, toward(index, forward)}, goals, captures, choices)
    case Cursor{_, Nil{}, _}: backtrack(choices)

def isLineTerminatorAt(code: Maybe<&2, U32>) -> Bool:
  match code:
    case Some{value}: isLineTerminator(value)
    case None{}: False{}
def isWordAt(code: Maybe<&2, U32>) -> Bool:
  match code:
    case Some{value}: isWordCode(value)
    case None{}: False{}
# The scalars before and after the position, whichever the direction.
def previousCode(cursor: Cursor, forward: Bool) -> Maybe<&2, U32>:
  match cursor forward:
    case Cursor{passed, _, _} True{}: passed
    case Cursor{_, ahead, _} False{}: List.head(&2, U32, ahead)
def followingCode(cursor: Cursor, forward: Bool) -> Maybe<&2, U32>:
  match cursor forward:
    case Cursor{_, ahead, _} True{}: List.head(&2, U32, ahead)
    case Cursor{passed, _, _} False{}: passed

def assertionHolds(node: Node, multiline: Bool, +cursor: Cursor, +forward: Bool) -> Bool:
  match node:
    case LineStart{}: Maybe.is_none(&2, U32, previousCode(cursor, forward)) || (multiline && isLineTerminatorAt(previousCode(cursor, forward)))
    case LineEnd{}: Maybe.is_none(&2, U32, followingCode(cursor, forward)) || (multiline && isLineTerminatorAt(followingCode(cursor, forward)))
    case WordBoundary{negated}: Bool.xor(Bool.xor(isWordAt(previousCode(cursor, forward)), isWordAt(followingCode(cursor, forward))), negated)
    case _: False{}

def checked(holds: Bool, cursor: Cursor, goals: List<&2, Goal>, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match holds:
    case True{}: Running{goals, cursor, captures, choices}
    case False{}: backtrack(choices)

def runAll(nodes: List<&2, Node>, +forward: Bool, rest: List<&2, Goal>) -> List<&2, Goal>:
  match nodes:
    case Nil{}: rest
    case node <> more: RunNode{node, forward} <> runAll(more, forward, rest)

# Lookarounds. A body of one scalar reads the neighbouring scalar; any other
# body runs in the lookaround's direction, from a cursor turned to it.
def reversedPrefix(input: List<&2, U32>, count: Nat, reversed: List<&2, U32>) -> List<&2, U32>:
  match count input:
    case Zero{} _: reversed
    case Succ{_} Nil{}: reversed
    case Succ{more} code <> rest: reversedPrefix(rest, more, code <> reversed)
def inputOf(settings: Settings) -> List<&2, U32>:
  match settings: case Settings{_, _, _, input, _, _}: input
def turned(cursor: Cursor, forward: Bool, ahead: Bool, settings: Settings) -> Cursor:
  match cursor forward ahead:
    case Cursor{_, after, +index} True{} False{}: Cursor{List.head(&2, U32, after), reversedPrefix(inputOf(settings), index, Nil{}), index}
    case Cursor{_, before, +index} False{} True{}: Cursor{List.head(&2, U32, before), List.drop(&2, U32, inputOf(settings), index), index}
    case cursor _ _: cursor
# `accepted`, the last use of `node` (so the test before it only reads the
# node; see BEND-054).
def acceptedBy(accepted: Bool, node: Node) -> Bool: accepted
def neighbourAccepts(+node: Node, settings: Settings, code: Maybe<&2, U32>) -> Bool:
  match code:
    case Some{value}: acceptedBy(nodeAccepts(node, settings, value), node)
    case None{}: False{}
def neighbour(+cursor: Cursor, forward: Bool, ahead: Bool) -> Maybe<&2, U32>:
  match ahead:
    case True{}: followingCode(cursor, forward)
    case False{}: previousCode(cursor, forward)
def lookStep(+ahead: Bool, negated: Bool, body: Node, +forward: Bool, rest: List<&2, Goal>, +settings: Settings, +cursor: Cursor, +captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match body:
    case Literal{code}: checked(Bool.xor(neighbourAccepts(Literal{code}, settings, neighbour(cursor, forward, ahead)), negated), cursor, rest, captures, choices)
    case AnyChar{}: checked(Bool.xor(neighbourAccepts(AnyChar{}, settings, neighbour(cursor, forward, ahead)), negated), cursor, rest, captures, choices)
    case CharClass{inverted, items}: checked(Bool.xor(neighbourAccepts(CharClass{inverted, items}, settings, neighbour(cursor, forward, ahead)), negated), cursor, rest, captures, choices)
    case body: Running{[RunNode{body, ahead}, LookDone{}], turned(cursor, forward, ahead, settings), captures, Barrier{negated, rest, cursor, captures} <> choices}

def setCapture(captures: List<&2, Maybe<&2, Span>>, index: Nat, span: Span) -> List<&2, Maybe<&2, Span>>:
  match captures index:
    case Nil{} _: Nil{}
    case _ <> rest Succ{Zero{}}: Some{span} <> rest
    case capture <> rest Succ{more}: capture <> setCapture(rest, more, span)
    case captures Zero{}: captures
# Clears `count` captures from group `first` on (group 1 heads `captures`);
# the list after them is shared, not rebuilt.
def clearedRun(count: Nat, captures: List<&2, Maybe<&2, Span>>) -> List<&2, Maybe<&2, Span>>:
  match count captures:
    case Zero{} kept: kept
    case _ Nil{}: Nil{}
    case Succ{more} _ <> rest: None{} <> clearedRun(more, rest)
def clearCaptures(+count: Nat, +captures: List<&2, Maybe<&2, Span>>, +first: Nat) -> List<&2, Maybe<&2, Span>>:
  match count:
    case Zero{}: captures
    case count: List.append(&2, Maybe<&2, Span>, List.take(&2, Maybe<&2, Span>, captures, first - 1n), clearedRun(count, List.drop(&2, Maybe<&2, Span>, captures, first - 1n)))
def spanOf(+start: Nat, +index: Nat, forward: Bool) -> Span:
  match forward:
    case True{}: Span{start, index}
    case False{}: Span{index, start}

def captured(captures: List<&2, Maybe<&2, Span>>, index: Nat) -> Maybe<&2, Span>:
  match captures index:
    case Nil{} _: None{}
    case capture <> _ Succ{Zero{}}: capture
    case _ <> rest Succ{more}: captured(rest, more)
    case _ Zero{}: None{}

def slice(input: List<&2, U32>, span: Span) -> List<&2, U32>:
  match span: case Span{+start, end}: List.take(&2, U32, List.drop(&2, U32, input, start), end - start)

# A backreference matches the captured text again (backwards: its reversal
# against the preceding scalars).
def prefixMatches(expected: List<&2, U32>, found: List<&2, U32>, +ignoreCase: Bool) -> Bool:
  match expected found:
    case Nil{} _: True{}
    case _ Nil{}: False{}
    case +code <> rest +other <> more: sameChar(ignoreCase, code, other) && prefixMatches(rest, more, ignoreCase)
def advanced(count: Nat, cursor: Cursor, +forward: Bool) -> Maybe<&2, Cursor>:
  match count cursor:
    case Zero{} cursor: Some{cursor}
    case Succ{more} Cursor{_, code <> ahead, index}: advanced(more, Cursor{Some{code}, ahead, toward(index, forward)}, forward)
    case Succ{_} Cursor{_, Nil{}, _}: None{}
def aheadOf(cursor: Cursor) -> List<&2, U32>:
  match cursor: case Cursor{_, ahead, _}: ahead
def orientedText(+expected: List<&2, U32>, forward: Bool) -> List<&2, U32>:
  match forward:
    case True{}: expected
    case False{}: List.reverse(&2, U32, expected)
def textAdvanced(matched: Bool, count: Nat, cursor: Cursor, forward: Bool) -> Maybe<&2, Cursor>:
  match matched:
    case True{}: advanced(count, cursor, forward)
    case False{}: None{}
def textMatched(+expected: List<&2, U32>, +cursor: Cursor, ignoreCase: Bool, +forward: Bool) -> Maybe<&2, Cursor>:
  textAdvanced(prefixMatches(orientedText(expected, forward), aheadOf(cursor), ignoreCase), List.length(&2, U32, expected), cursor, forward)

def indexOf(cursor: Cursor) -> Nat:
  match cursor: case Cursor{_, _, index}: index

def moved(next: Maybe<&2, Cursor>, rest: List<&2, Goal>, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match next:
    case Some{cursor}: Running{rest, cursor, captures, choices}
    case None{}: backtrack(choices)

def backrefStep(span: Maybe<&2, Span>, settings: Settings, +cursor: Cursor, forward: Bool, rest: List<&2, Goal>, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match span settings:
    case None{} _: Running{rest, cursor, captures, choices}
    case Some{found} Settings{ignoreCase, _, _, input, _, _}: moved(textMatched(slice(input, found), cursor, ignoreCase, forward), rest, captures, choices)
def groupsOf(settings: Settings) -> Nat:
  match settings: case Settings{_, _, _, _, groups, _}: groups
def namesOf(settings: Settings) -> List<&2, NamedGroup>:
  match settings: case Settings{_, _, _, _, _, names}: names
def multilineOf(settings: Settings) -> Bool:
  match settings: case Settings{_, multiline, _, _, _, _}: multiline

# Repetition of a single-scalar atom (no captures, never empty) takes its run
# of scalars in one step, then yields them back one at a time when greedy
# (GiveBack) or takes one more at a time when lazy (TakeMore): the choices
# RepeatMatcher makes per iteration, in the same order. Positions where the
# continuation cannot start (`follow`) are not tried: a greedy run the
# continuation cannot start with keeps what it took, and a lazy one passes
# over scalars the continuation cannot start with.
def follows(follow: Follow, +code: U32) -> Bool:
  match follow:
    case Anything{}: True{}
    case Scalars{ascii, wide}: Bool.pick(Bool, U32.is_lt(code, 128), asciiHas(ascii, code), wide)
    case Disjoint{}: False{}
def lessOne(max: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match max:
    case Some{value}: Some{value - 1n}
    case None{}: None{}
def keeps(follow: Follow) -> Bool:
  match follow:
    case Disjoint{}: False{}
    case _: True{}
def kept(keep: Bool, +code: U32, taken: List<&2, U32>) -> List<&2, U32>:
  match keep:
    case True{}: code <> taken
    case False{}: taken
# The run from the scalar `code`, before `rest` (`accepts`: `node` accepts
# `code`); with `keep`, the scalars taken, the last first. The scalar ahead is
# a parameter, not read from the list, so the scan takes each node once.
type Scanned is Data: Scanned{cursor: Cursor, count: Nat, taken: List<&2, U32>}
def scanRun(rest: List<&2, U32>, +code: U32, accepts: Bool, +node: Node, +settings: Settings, +forward: Bool, +keep: Bool, max: Maybe<&2, Nat>, passed: Maybe<&2, U32>, +index: Nat, +count: Nat, taken: List<&2, U32>) -> Scanned:
  match accepts max rest:
    case True{} Some{Zero{}} rest: Scanned{Cursor{passed, code <> rest, index}, count, taken}
    case False{} _ rest: Scanned{Cursor{passed, code <> rest, index}, count, taken}
    case True{} max +next <> more: scanRun(more, next, nodeAccepts(node, settings, next), node, settings, forward, keep, lessOne(max), Some{code}, toward(index, forward), count + 1n, kept(keep, code, taken))
    case True{} _ Nil{}: Scanned{Cursor{Some{code}, Nil{}, toward(index, forward)}, count + 1n, kept(keep, code, taken)}
def scanFrom(+node: Node, +settings: Settings, +forward: Bool, +keep: Bool, max: Maybe<&2, Nat>, cursor: Cursor) -> Scanned:
  match cursor:
    case Cursor{passed, +code <> rest, index}: scanRun(rest, code, nodeAccepts(node, settings, code), node, settings, forward, keep, max, passed, index, 0n, Nil{})
    case Cursor{passed, Nil{}, index}: Scanned{Cursor{passed, Nil{}, index}, 0n, Nil{}}
# A lazy run's next position where the continuation can start, from the
# scalar `code` before `rest`: `skip` says whether `node` accepts `code`, the
# continuation cannot start with it and `max` allows another.
type Skipped is Data: Skipped{cursor: Cursor, remaining: Maybe<&2, Nat>}
def skippable(+code: U32, node: Node, settings: Settings, follow: Follow, max: Maybe<&2, Nat>) -> Bool:
  match max:
    case Some{Zero{}}: False{}
    case _: nodeAccepts(node, settings, code) && Bool.not(follows(follow, code))
def skipRun(rest: List<&2, U32>, +code: U32, skip: Bool, +node: Node, +settings: Settings, +follow: Follow, +forward: Bool, +max: Maybe<&2, Nat>, passed: Maybe<&2, U32>, +index: Nat) -> Skipped:
  match skip rest:
    case True{} +next <> more: skipRun(more, next, skippable(next, node, settings, follow, lessOne(max)), node, settings, follow, forward, lessOne(max), Some{code}, toward(index, forward))
    case True{} Nil{}: Skipped{Cursor{Some{code}, Nil{}, toward(index, forward)}, lessOne(max)}
    case False{} rest: Skipped{Cursor{passed, code <> rest, index}, max}
def skipFrom(+node: Node, +settings: Settings, +follow: Follow, +forward: Bool, +max: Maybe<&2, Nat>, cursor: Cursor) -> Skipped:
  match cursor:
    case Cursor{passed, +code <> rest, index}: skipRun(rest, code, skippable(code, node, settings, follow, max), node, settings, follow, forward, max, passed, index)
    case Cursor{passed, Nil{}, index}: Skipped{Cursor{passed, Nil{}, index}, max}
def givenBack(remaining: Nat, taken: List<&2, U32>, passed: Maybe<&2, U32>, follow: Follow, forward: Bool, rest: List<&2, Goal>, cursor: Cursor, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> List<&2, Choice>:
  match remaining follow:
    case Zero{} _: choices
    case _ Disjoint{}: choices
    case more follow: Alternative{GiveBack{taken, more, passed, follow, forward} <> rest, cursor, captures} <> choices
def greedyEnd(short: Bool, scanned: Scanned, +min: Nat, passed: Maybe<&2, U32>, follow: Follow, +forward: Bool, +rest: List<&2, Goal>, +captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match short scanned:
    case True{} _: backtrack(choices)
    case False{} Scanned{+cursor, count, taken}: Running{rest, cursor, captures, givenBack(count - min, taken, passed, follow, forward, rest, cursor, captures, choices)}
def countOf(scanned: Scanned) -> Nat:
  match scanned: case Scanned{_, count, _}: count
def greedyRun(+scanned: Scanned, +min: Nat, passed: Maybe<&2, U32>, follow: Follow, forward: Bool, rest: List<&2, Goal>, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  greedyEnd(Nat.is_lt(countOf(scanned), min), scanned, min, passed, follow, forward, rest, captures, choices)
def lazyNext(skipped: Skipped, +node: Node, +follow: Follow, +forward: Bool, +rest: List<&2, Goal>, +captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match skipped:
    case Skipped{+cursor, remaining}: Running{rest, cursor, captures, Alternative{TakeMore{node, remaining, follow, forward} <> rest, cursor, captures} <> choices}
def remainingAfter(max: Maybe<&2, Nat>, +min: Nat) -> Maybe<&2, Nat>:
  match max:
    case Some{value}: Some{value - min}
    case None{}: None{}
def lazyEnd(short: Bool, scanned: Scanned, +min: Nat, max: Maybe<&2, Nat>, +node: Node, +follow: Follow, +settings: Settings, +forward: Bool, rest: List<&2, Goal>, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match short scanned:
    case True{} _: backtrack(choices)
    case False{} Scanned{cursor, _, _}: lazyNext(skipFrom(node, settings, follow, forward, remainingAfter(max, min), cursor), node, follow, forward, rest, captures, choices)
def lazyRun(+scanned: Scanned, +min: Nat, max: Maybe<&2, Nat>, node: Node, follow: Follow, settings: Settings, forward: Bool, rest: List<&2, Goal>, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  lazyEnd(Nat.is_lt(countOf(scanned), min), scanned, min, max, node, follow, settings, forward, rest, captures, choices)
def passedOf(cursor: Cursor) -> Maybe<&2, U32>:
  match cursor: case Cursor{passed, _, _}: passed
def singleRepeat(+node: Node, +min: Nat, max: Maybe<&2, Nat>, greedy: Bool, +follow: Follow, +forward: Bool, rest: List<&2, Goal>, +settings: Settings, +cursor: Cursor, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match greedy:
    case True{}: greedyRun(scanFrom(node, settings, forward, keeps(follow), max, cursor), min, passedOf(cursor), follow, forward, rest, captures, choices)
    case False{}: lazyRun(scanFrom(node, settings, forward, False{}, Some{min}, cursor), min, max, node, follow, settings, forward, rest, captures, choices)
def repeatStep(body: Node, +min: Nat, +max: Maybe<&2, Nat>, +greedy: Bool, first: Nat, count: Nat, follow: Follow, +forward: Bool, +rest: List<&2, Goal>, +settings: Settings, +cursor: Cursor, +captures: List<&2, Maybe<&2, Span>>, +choices: List<&2, Choice>) -> Machine:
  match body:
    case Literal{code}: singleRepeat(Literal{code}, min, max, greedy, follow, forward, rest, settings, cursor, captures, choices)
    case AnyChar{}: singleRepeat(AnyChar{}, min, max, greedy, follow, forward, rest, settings, cursor, captures, choices)
    case CharClass{negated, items}: singleRepeat(CharClass{negated, items}, min, max, greedy, follow, forward, rest, settings, cursor, captures, choices)
    case other: Running{Iterate{other, min, max, greedy, first, count, follow, forward} <> rest, cursor, captures, choices}
# The next position a greedy run gives back to where the continuation can
# start: `viable` says whether the scalar given back next is one it can start
# with.
type Returned is Data: Returned{cursor: Cursor, taken: List<&2, U32>, remaining: Nat}
def viableAt(taken: List<&2, U32>, follow: Follow) -> Bool:
  match taken:
    case code <> _: follows(follow, code)
    case Nil{}: True{}
def headOr(codes: List<&2, U32>, passed: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match codes:
    case code <> _: Some{code}
    case Nil{}: passed
def unstepped(taken: List<&2, U32>, viable: Bool, remaining: Nat, passed: Maybe<&2, U32>, +follow: Follow, ahead: List<&2, U32>, +index: Nat, +forward: Bool) -> Maybe<&2, Returned>:
  match viable remaining taken:
    case _ Zero{} _: None{}
    case _ _ Nil{}: None{}
    case True{} Succ{more} +code <> +earlier: Some{Returned{Cursor{headOr(earlier, passed), code <> ahead, away(index, forward)}, earlier, more}}
    case False{} Succ{more} +code <> +earlier: unstepped(earlier, viableAt(earlier, follow), more, passed, follow, code <> ahead, away(index, forward), forward)
def givingBack(found: Maybe<&2, Returned>, passed: Maybe<&2, U32>, follow: Follow, +forward: Bool, +rest: List<&2, Goal>, +captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match found:
    case None{}: backtrack(choices)
    case Some{Returned{+cursor, taken, remaining}}: Running{rest, cursor, captures, givenBack(remaining, taken, passed, follow, forward, rest, cursor, captures, choices)}
def giveBackStep(+taken: List<&2, U32>, remaining: Nat, +passed: Maybe<&2, U32>, +follow: Follow, +forward: Bool, rest: List<&2, Goal>, cursor: Cursor, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match cursor:
    case Cursor{_, ahead, index}: givingBack(unstepped(taken, viableAt(taken, follow), remaining, passed, follow, ahead, index, forward), passed, follow, forward, rest, captures, choices)
def takenMore(accepted: Bool, +remaining: Maybe<&2, Nat>, +node: Node, +follow: Follow, +settings: Settings, +forward: Bool, rest: List<&2, Goal>, cursor: Cursor, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match accepted:
    case True{}: lazyNext(skipFrom(node, settings, follow, forward, remaining, cursor), node, follow, forward, rest, captures, choices)
    case False{}: backtrack(choices)
def takingMore(remaining: Maybe<&2, Nat>, +node: Node, +follow: Follow, +settings: Settings, +forward: Bool, +rest: List<&2, Goal>, cursor: Cursor, +captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match remaining cursor:
    case Some{Zero{}} _: backtrack(choices)
    case _ Cursor{_, +code <> ahead, index}: takenMore(nodeAccepts(node, settings, code), lessOne(remaining), node, follow, settings, forward, rest, Cursor{Some{code}, ahead, toward(index, forward)}, captures, choices)
    case _ Cursor{_, Nil{}, _}: backtrack(choices)

# The options that can match before `next` (every one at the end).
def keptIf(keep: Bool, option: Node, options: List<&2, Node>) -> List<&2, Node>:
  match keep:
    case True{}: option <> options
    case False{}: options
def viableOptions(options: List<&2, Node>, starts: List<&2, Follow>, next: Maybe<&2, U32>) -> List<&2, Node>:
  match options starts next:
    case Nil{} _ _: Nil{}
    case options Nil{} _: options
    case options _ None{}: options
    case option <> more start <> others Some{+code}: keptIf(follows(start, code), option, viableOptions(more, others, Some{code}))
def optionsStep(options: List<&2, Node>, +forward: Bool, +rest: List<&2, Goal>, +cursor: Cursor, +captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match options:
    case Nil{}: backtrack(choices)
    case first <> more: Running{RunNode{first, forward} <> rest, cursor, captures, untried(more, forward, rest, cursor, captures, choices)}
def nodeStep(node: Node, +forward: Bool, +rest: List<&2, Goal>, +settings: Settings, +cursor: Cursor, +captures: List<&2, Maybe<&2, Span>>, +choices: List<&2, Choice>) -> Machine:
  match node:
    case Empty{}: Running{rest, cursor, captures, choices}
    case Literal{code}: single(Literal{code}, settings, cursor, forward, rest, captures, choices)
    case AnyChar{}: single(AnyChar{}, settings, cursor, forward, rest, captures, choices)
    case CharClass{negated, +items}: single(CharClass{negated, items}, settings, cursor, forward, rest, captures, choices)
    case LineStart{}: checked(assertionHolds(LineStart{}, multilineOf(settings), cursor, forward), cursor, rest, captures, choices)
    case LineEnd{}: checked(assertionHolds(LineEnd{}, multilineOf(settings), cursor, forward), cursor, rest, captures, choices)
    case WordBoundary{negated}: checked(assertionHolds(WordBoundary{negated}, False{}, cursor, forward), cursor, rest, captures, choices)
    case Group{Some{index}, body}: Running{RunNode{body, forward} <> CloseGroup{index, indexOf(cursor), forward} <> rest, cursor, captures, choices}
    case Group{None{}, body}: Running{RunNode{body, forward} <> rest, cursor, captures, choices}
    case Look{ahead, negated, body}: lookStep(ahead, negated, body, forward, rest, settings, cursor, captures, choices)
    case Backref{index}: backrefStep(captured(captures, index), settings, cursor, forward, rest, captures, choices)
    case Alternation{options, starts}: optionsStep(viableOptions(options, starts, followingCode(cursor, forward)), forward, rest, cursor, captures, choices)
    case Sequence{+items}: Running{runAll(Bool.pick(List<&2, Node>, forward, items, List.reverse(&2, Node, items)), forward, rest), cursor, captures, choices}
    case Repeat{body, min, max, greedy, first, count, follow}: repeatStep(body, min, max, greedy, first, count, follow, forward, rest, settings, cursor, captures, choices)
    case DecimalEscape{digits}: Running{RunNode{decimalResolved(digits, groupsOf(settings)), forward} <> rest, cursor, captures, choices}
    case NamedBackref{+name}: Running{RunNode{namedResolved(namedIndex(namesOf(settings), name), name), forward} <> rest, cursor, captures, choices}

# `viable`: the continuation may start here (it is not tried where it cannot).
def iterated(min: Nat, max: Maybe<&2, Nat>, greedy: Bool, viable: Bool, iteration: List<&2, Goal>, cleared: List<&2, Maybe<&2, Span>>, rest: List<&2, Goal>, +cursor: Cursor, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match min max greedy viable:
    case _ Some{Zero{}} _ _: Running{rest, cursor, captures, choices}
    case Succ{_} _ _ _: Running{iteration, cursor, cleared, choices}
    case Zero{} _ _ False{}: Running{iteration, cursor, cleared, choices}
    case Zero{} _ True{} True{}: Running{iteration, cursor, cleared, Alternative{rest, cursor, captures} <> choices}
    case Zero{} _ False{} True{}: Running{rest, cursor, captures, Alternative{iteration, cursor, cleared} <> choices}
def followsNext(follow: Follow, next: Maybe<&2, U32>) -> Bool:
  match next:
    case Some{code}: follows(follow, code)
    case None{}: True{}
def iterateStep(+body: Node, +min: Nat, +max: Maybe<&2, Nat>, +greedy: Bool, +first: Nat, +count: Nat, +follow: Follow, +forward: Bool, +rest: List<&2, Goal>, +cursor: Cursor, +captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  iterated(min, max, greedy, followsNext(follow, followingCode(cursor, forward)), RunNode{body, forward} <> AfterIteration{body, min, max, greedy, first, count, follow, indexOf(cursor), forward} <> rest, clearCaptures(count, captures, first), rest, cursor, captures, choices)

# An optional iteration (min 0) that consumed nothing ends the repetition.
def afterEnd(empty: Bool, body: Node, +min: Nat, max: Maybe<&2, Nat>, greedy: Bool, first: Nat, count: Nat, follow: Follow, forward: Bool, rest: List<&2, Goal>, cursor: Cursor, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match empty:
    case True{}: backtrack(choices)
    case False{}: Running{Iterate{body, min - 1n, lessOne(max), greedy, first, count, follow, forward} <> rest, cursor, captures, choices}
def afterStep(body: Node, +min: Nat, max: Maybe<&2, Nat>, greedy: Bool, first: Nat, count: Nat, follow: Follow, +start: Nat, forward: Bool, rest: List<&2, Goal>, +cursor: Cursor, captures: List<&2, Maybe<&2, Span>>, +choices: List<&2, Choice>) -> Machine:
  afterEnd(Nat.is_eq(min, 0n) && Nat.is_eq(indexOf(cursor), start), body, min, max, greedy, first, count, follow, forward, rest, cursor, captures, choices)

def goalStep(goal: Goal, rest: List<&2, Goal>, settings: Settings, +cursor: Cursor, captures: List<&2, Maybe<&2, Span>>, choices: List<&2, Choice>) -> Machine:
  match goal:
    case RunNode{node, forward}: nodeStep(node, forward, rest, settings, cursor, captures, choices)
    case CloseGroup{group, start, forward}: Running{rest, cursor, setCapture(captures, group, spanOf(start, indexOf(cursor), forward)), choices}
    case Iterate{body, min, max, greedy, first, count, follow, forward}: iterateStep(body, min, max, greedy, first, count, follow, forward, rest, cursor, captures, choices)
    case AfterIteration{body, min, max, greedy, first, count, follow, start, forward}: afterStep(body, min, max, greedy, first, count, follow, start, forward, rest, cursor, captures, choices)
    case GiveBack{taken, remaining, passed, follow, forward}: giveBackStep(taken, remaining, passed, follow, forward, rest, cursor, captures, choices)
    case TakeMore{node, remaining, follow, forward}: takingMore(remaining, node, follow, settings, forward, rest, cursor, captures, choices)
    case LookDone{}: lookMatched(choices, captures)

def machineStep(settings: Settings, machine: Machine) -> Machine:
  match machine:
    case Running{Nil{}, cursor, captures, _}: Succeeded{cursor, captures}
    case Running{goal <> rest, cursor, captures, choices}: goalStep(goal, rest, settings, cursor, captures, choices)
    case other: other

# The step budget bounds catastrophic backtracking; an exhausted budget is a
# failed attempt.
def machineLoop(fuel: Nat, +settings: Settings, machine: Machine) -> Machine:
  match fuel machine:
    case _ Succeeded{cursor, captures}: Succeeded{cursor, captures}
    case _ NoMatch{}: NoMatch{}
    case Zero{} _: NoMatch{}
    case Succ{more} machine: machineLoop(more, settings, machineStep(settings, machine))

def STEP_BUDGET() -> Nat: 1000000n

# Execution
# ---------

type Match is Data: Match{index: Nat, end: Nat, captures: List<&2, Maybe<&2, Span>>}

def undefinedCaptures(count: Nat) -> List<&2, Maybe<&2, Span>>:
  match count:
    case Zero{}: Nil{}
    case Succ{more}: None{} <> undefinedCaptures(more)

def attempt(root: Node, groups: Nat, settings: Settings, cursor: Cursor) -> Machine:
  machineLoop(STEP_BUDGET(), settings, Running{[RunNode{root, True{}}], cursor, undefinedCaptures(groups), Nil{}})

def found(result: Machine, start: Nat) -> Maybe<&2, Match>:
  match result:
    case Succeeded{cursor, captures}: Some{Match{start, indexOf(cursor), captures}}
    case _: None{}

def settingsOf(flags: Flags, input: List<&2, U32>, groups: Nat, names: List<&2, NamedGroup>) -> Settings:
  match flags: case Flags{_, ignoreCase, multiline, dotAll, _, _}: Settings{ignoreCase, multiline, dotAll, input, groups, names}
def stickyOf(flags: Flags) -> Bool:
  match flags: case Flags{_, _, _, _, _, sticky}: sticky

# Leftmost match starting at the cursor or later (only there when sticky);
# `current` is the attempt at the cursor.
def searched(ahead: List<&2, U32>, current: Maybe<&2, Match>, +root: Node, +groups: Nat, +settings: Settings, +sticky: Bool, passed: Maybe<&2, U32>, +index: Nat) -> Maybe<&2, Match>:
  match current sticky ahead:
    case Some{value} _ _: Some{value}
    case None{} True{} _: None{}
    case None{} False{} Nil{}: None{}
    case None{} False{} +code <> +rest: searched(rest, found(attempt(root, groups, settings, Cursor{Some{code}, rest, index + 1n}), index + 1n), root, groups, settings, sticky, Some{code}, index + 1n)
def passedAt(all: List<&2, U32>, index: Nat) -> Maybe<&2, U32>:
  match index:
    case Zero{}: None{}
    case Succ{previous}: List.get(&2, U32, all, previous)
def execFrom(+all: List<&2, U32>, +lastIndex: Nat, +flags: Flags, +root: Node, +groups: Nat, names: List<&2, NamedGroup>) -> Maybe<&2, Match>:
  +passed = passedAt(all, lastIndex)
  +after = List.drop(&2, U32, all, lastIndex)
  +settings = settingsOf(flags, all, groups, names)
  searched(after, found(attempt(root, groups, settings, Cursor{passed, after, lastIndex}), lastIndex), root, groups, settings, stickyOf(flags), passed, lastIndex)
def execWithin(within: Bool, +all: List<&2, U32>, +lastIndex: Nat, +flags: Flags, +root: Node, +groups: Nat, names: List<&2, NamedGroup>) -> Maybe<&2, Match>:
  match within:
    case True{}: execFrom(all, lastIndex, flags, root, groups, names)
    case False{}: None{}

# RegExpBuiltinExec from `lastIndex` (the caller applies g/y lastIndex updates).
def exec(regex: RegExp, input: String, +lastIndex: Nat) -> Maybe<&2, Match>:
  match regex:
    case RegExp{_, +flags, +root, +groups, names}:
      +all = codes(input)
      execWithin(Nat.is_le(lastIndex, List.length(&2, U32, all)), all, lastIndex, flags, root, groups, names)

def test(regex: RegExp, input: String) -> Bool: Bool.not(Maybe.is_none(&2, Match, exec(regex, input, 0n)))

# The text of a capture (0 is the whole match).
def matchText(input: String, span: Span) -> String: fromCodes(slice(codes(input), span))

# Scanning prepared input
# -----------------------
# Callers that try many patterns over one input (a lexer) keep the input as
# scalars and a Cursor, instead of re-splitting the string for every exec.

def cursorAt(input: List<&2, U32>) -> Cursor: Cursor{None{}, input, 0n}
def advance(cursor: Cursor) -> Maybe<&2, Cursor>: stepped(cursor, True{})
def position(cursor: Cursor) -> Nat: indexOf(cursor)
def following(cursor: Cursor) -> List<&2, U32>: aheadOf(cursor)
def preceding(cursor: Cursor) -> Maybe<&2, U32>: passedOf(cursor)
def nextScalar(cursor: Cursor) -> Maybe<&2, U32>: List.head(&2, U32, aheadOf(cursor))

# The sticky match of `regex` at `cursor`; `input` is the whole subject, whose
# scalar indices the cursor and the result use.
def matchAt(regex: RegExp, input: List<&2, U32>, +cursor: Cursor) -> Maybe<&2, Match>:
  match regex:
    case RegExp{_, flags, root, +groups, names}: found(attempt(root, groups, settingsOf(flags, input, groups, names), cursor), indexOf(cursor))


def ignoreCaseOf(flags: Flags) -> Bool:
  match flags: case Flags{_, value, _, _, _, _}: value
def dotAllOf(flags: Flags) -> Bool:
  match flags: case Flags{_, _, _, value, _, _}: value
# Start analysis
# --------------
# The scalars a match can begin with, so a scanner can skip positions where a
# pattern cannot start. A pattern that can match without consuming a scalar,
# or whose first scalar is not known statically (backreferences), is
# `nullable`: every position is a candidate. Otherwise a match can only start
# before a scalar some node of `firsts` accepts; `ascii` holds those below 128
# and `wide` says whether any from 128 up can be one.

type Start is Data: Start{nullable: Bool, firsts: List<&2, Node>, ascii: Ascii, wide: Bool, bounded: Bool, ends: Bool}

def noAscii() -> Ascii: Ascii{0, 0, 0, 0}
def allAscii() -> Ascii: Ascii{4294967295, 4294967295, 4294967295, 4294967295}
def asciiUnion(left: Ascii, right: Ascii) -> Ascii:
  match left right:
    case Ascii{a, b, c, d} Ascii{e, f, g, h}: Ascii{U32.or(a, e), U32.or(b, f), U32.or(c, g), U32.or(d, h)}
def asciiComplement(set: Ascii) -> Ascii:
  match set:
    case Ascii{a, b, c, d}: Ascii{U32.not(a), U32.not(b), U32.not(c), U32.not(d)}
# ASCII case folding: a letter of either case adds the other.
def asciiFolded(set: Ascii) -> Ascii:
  match set:
    case Ascii{a, b, +c, +d}: Ascii{a, b, U32.or(c, U32.and(d, 134217726)), U32.or(d, U32.and(c, 134217726))}
# Bits low..high of the word holding codes base..base+31.
def wordRange(+base: U32, +low: U32, +high: U32) -> U32:
  +from = U32.max(low, base)
  +to = U32.min(high, (base + 31 : U32))
  Bool.pick(Unit -> U32, U32.is_gt(from, to), _ => 0, _ => ((power((to - base : U32)) - 1 : U32) * 2 + 1 - (power((from - base : U32)) - 1 : U32) : U32))(Unit{})
def asciiRange(+low: U32, +high: U32) -> Ascii: Ascii{wordRange(0, low, high), wordRange(32, low, high), wordRange(64, low, high), wordRange(96, low, high)}
def negatedIf(negated: Bool, set: Ascii) -> Ascii:
  match negated:
    case True{}: asciiComplement(set)
    case False{}: set
# The ASCII members of the General_Category classes.
def categoryAscii(category: U32) -> Ascii:
  match category:
    case 1: asciiUnion(asciiRange(65, 90), asciiRange(97, 122))
    case 2: asciiRange(48, 57)
    case 3: Ascii{0, 2348873710, 3087007745, 671088640}
    case 4: Ascii{0, 1879050256, 1073741824, 1342177281}
    case _: noAscii()
def itemAscii(item: ClassItem) -> Ascii:
  match item:
    case Range{low, high}: asciiRange(low, high)
    case Digit{negated}: negatedIf(negated, asciiRange(48, 57))
    case Word{negated}: negatedIf(negated, asciiUnion(asciiUnion(asciiRange(48, 57), asciiRange(65, 90)), asciiUnion(asciiRange(97, 122), asciiRange(95, 95))))
    case Space{negated}: negatedIf(negated, asciiUnion(asciiRange(9, 13), asciiRange(32, 32)))
    case Category{negated, category}: negatedIf(negated, categoryAscii(category))
def itemWide(item: ClassItem) -> Bool:
  match item:
    case Range{_, high}: U32.is_ge(high, 128)
    case Digit{negated}: negated
    case Word{negated}: negated
    case Space{_}: True{}
    case Category{_, _}: True{}
def itemsAscii(items: List<&2, ClassItem>, set: Ascii, wide: Bool) -> Ascii & Bool:
  match items:
    case Nil{}: (set, wide)
    case +item <> rest: itemsAscii(rest, asciiUnion(set, itemAscii(item)), wide || itemWide(item))
def classAscii(+negated: Bool, ignoreCase: Bool, found: Ascii & Bool) -> Ascii & Bool:
  match found:
    case (+set, wide): (negatedIf(negated, Bool.pick(Ascii, ignoreCase, asciiFolded(set), set)), negated || wide)
def literalAscii(ignoreCase: Bool, +code: U32) -> Ascii:
  match ignoreCase:
    case True{}: asciiUnion(asciiRange(upper(code), upper(code)), asciiRange(lower(code), lower(code)))
    case False{}: asciiRange(code, code)
# The ASCII scalars a single-scalar node accepts, and whether it accepts any
# wider one.
def nodeAscii(node: Node, ignoreCase: Bool, dotAll: Bool) -> Ascii & Bool:
  match node:
    case Literal{+code}: (literalAscii(ignoreCase, code), U32.is_ge(code, 128))
    case AnyChar{}: (Bool.pick(Ascii, dotAll, allAscii(), asciiComplement(asciiUnion(asciiRange(10, 10), asciiRange(13, 13)))), True{})
    case CharClass{negated, items}: classAscii(negated, ignoreCase, itemsAscii(items, noAscii(), False{}))
    case _: (noAscii(), True{})
def merged(prior: Ascii & Bool, more: Ascii, broad: Bool) -> Ascii & Bool:
  match prior:
    case (set, wide): (asciiUnion(set, more), wide || broad)
def withNode(found: Ascii & Bool, prior: Ascii & Bool) -> Ascii & Bool:
  match found:
    case (more, broad): merged(prior, more, broad)
def firstsAscii(firsts: List<&2, Node>, +ignoreCase: Bool, +dotAll: Bool, found: Ascii & Bool) -> Ascii & Bool:
  match firsts:
    case Nil{}: found
    case node <> rest: firstsAscii(rest, ignoreCase, dotAll, withNode(nodeAscii(node, ignoreCase, dotAll), found))
def wordAscii() -> Ascii: itemAscii(Word{False{}})
def asciiWithin(set: Ascii, outer: Ascii) -> Bool:
  match set outer:
    case Ascii{a, b, c, d} Ascii{e, f, g, h}: U32.is_eq(U32.and(a, U32.not(e)), 0) && U32.is_eq(U32.and(b, U32.not(f)), 0) && U32.is_eq(U32.and(c, U32.not(g)), 0) && U32.is_eq(U32.and(d, U32.not(h)), 0)
# `\b` right before a word scalar means the preceding scalar is not one.
def started(firsts: List<&2, Node>, bounded: Bool, ends: Bool, found: Ascii & Bool) -> Start:
  match found:
    case (+set, +wide): Start{False{}, firsts, set, wide, bounded && Bool.not(wide) && asciiWithin(set, wordAscii()), ends}

# Pending paths are node sequences still to be examined, each noting whether
# it passed a `\b` since the match start; an exhausted path matched without
# consuming. `bounded` holds while every first scalar follows a `\b`.
type Path is Data: Path{nodes: List<&2, Node>, bounded: Bool}
type Expansion is Data: Expansion{paths: List<&2, Path>, firsts: List<&2, Node>, bounded: Bool, ends: Bool}
def prefixed(options: List<&2, Node>, +rest: List<&2, Node>, +bounded: Bool, others: List<&2, Path>) -> List<&2, Path>:
  match options:
    case Nil{}: others
    case option <> more: Path{option <> rest, bounded} <> prefixed(more, rest, bounded, others)
def lineTerminators() -> Node: CharClass{False{}, [Range{10, 10}, Range{13, 13}, Range{8232, 8233}]}
# `$` holds only before a line terminator (multiline) or at the end: a path
# through it asks for a line terminator next or ends there (`ends`). In a
# continuation (`follow`, where a scalar follows the position) the end is not
# a case.
def lineEndExpanded(+multiline: Bool, others: List<&2, Path>, firsts: List<&2, Node>, +all: Bool, +bounded: Bool) -> Expansion:
  match multiline:
    case True{}: Expansion{others, lineTerminators() <> firsts, all && bounded, True{}}
    case False{}: Expansion{others, firsts, all, True{}}
def expanded(node: Node, +rest: List<&2, Node>, +bounded: Bool, others: List<&2, Path>, firsts: List<&2, Node>, all: Bool, +ends: Bool, +multiline: Bool) -> Expansion:
  match node:
    case Literal{code}: Expansion{others, Literal{code} <> firsts, all && bounded, ends}
    case AnyChar{}: Expansion{others, AnyChar{} <> firsts, all && bounded, ends}
    case CharClass{negated, items}: Expansion{others, CharClass{negated, items} <> firsts, all && bounded, ends}
    case WordBoundary{False{}}: Expansion{Path{rest, True{}} <> others, firsts, all, ends}
    case LineEnd{}: lineEndExpanded(multiline, others, firsts, all, bounded)
    case Group{_, body}: Expansion{Path{body <> rest, bounded} <> others, firsts, all, ends}
    case Alternation{options, _}: Expansion{prefixed(options, rest, bounded, others), firsts, all, ends}
    case Sequence{items}: Expansion{Path{List.append(&2, Node, items, rest), bounded} <> others, firsts, all, ends}
    case Repeat{body, Zero{}, _, _, _, _, _}: Expansion{Path{body <> rest, bounded} <> Path{rest, bounded} <> others, firsts, all, ends}
    case Repeat{body, _, _, _, _, _, _}: Expansion{Path{body <> rest, bounded} <> others, firsts, all, ends}
    case Backref{_}: Expansion{Path{Nil{}, bounded} <> others, firsts, all, ends}
    case NamedBackref{_}: Expansion{Path{Nil{}, bounded} <> others, firsts, all, ends}
    case DecimalEscape{_}: Expansion{Path{Nil{}, bounded} <> others, firsts, all, ends}
    case _: Expansion{Path{rest, bounded} <> others, firsts, all, ends}
def nullableStart() -> Start: Start{True{}, Nil{}, allAscii(), True{}, False{}, True{}}
def multilineFlag(flags: Flags) -> Bool:
  match flags: case Flags{_, _, multiline, _, _, _}: multiline
def startLoop(fuel: Nat, expansion: Expansion, +flags: Flags) -> Start:
  match fuel expansion:
    case _ Expansion{Nil{}, +firsts, bounded, ends}: started(firsts, bounded, ends, firstsAscii(firsts, ignoreCaseOf(flags), dotAllOf(flags), (noAscii(), False{})))
    case Zero{} _: nullableStart()
    case _ Expansion{Path{Nil{}, _} <> _, _, _, _}: nullableStart()
    case Succ{more} Expansion{Path{node <> rest, bounded} <> others, firsts, all, ends}: startLoop(more, expanded(node, rest, bounded, others, firsts, all, ends, multilineFlag(flags)), flags)
def startOf(regex: RegExp) -> Start:
  match regex:
    case RegExp{_, flags, root, _, _}: startLoop(4096n, Expansion{[Path{[root], False{}}], Nil{}, True{}, False{}}, flags)

def firstAccepts(firsts: List<&2, Node>, +settings: Settings, +code: U32) -> Bool:
  match firsts:
    case Nil{}: False{}
    case node <> rest: nodeAccepts(node, settings, code) || firstAccepts(rest, settings, code)
def startsWide(wide: Bool, firsts: List<&2, Node>, flags: Flags, +code: U32) -> Bool:
  match wide:
    case True{}: firstAccepts(firsts, settingsOf(flags, Nil{}, 0n, Nil{}), code)
    case False{}: False{}
def startsScalar(ascii: Bool, set: Ascii, wide: Bool, bounded: Bool, firsts: List<&2, Node>, flags: Flags, previous: Maybe<&2, U32>, +code: U32) -> Bool:
  match ascii:
    case True{}: asciiHas(set, code) && Bool.not(bounded && isWordAt(previous))
    case False{}: startsWide(wide, firsts, flags, code)
def startsAt(start: Start, flags: Flags, previous: Maybe<&2, U32>, next: Maybe<&2, U32>) -> Bool:
  match start next:
    case Start{True{}, _, _, _, _, _} _: True{}
    case Start{False{}, _, _, _, _, ends} None{}: ends
    case Start{False{}, firsts, ascii, wide, bounded, _} Some{+code}: startsScalar(U32.is_lt(code, 128), ascii, wide, bounded, firsts, flags, previous, code)
# Whether a match of `regex` may begin at `cursor` (never false when one does).
def canStart(regex: RegExp, start: Start, +cursor: Cursor) -> Bool:
  match regex:
    case RegExp{_, flags, _, _, _}: startsAt(start, flags, passedOf(cursor), nextScalar(cursor))

# A match with the cursor at its end, where a scan continues.
type Found is Data: Found{result: Match, cursor: Cursor}
def foundAt(result: Machine, start: Nat) -> Maybe<&2, Found>:
  match result:
    case Succeeded{+cursor, captures}: Some{Found{Match{start, indexOf(cursor), captures}, cursor}}
    case _: None{}
def attemptIf(candidate: Bool, root: Node, +groups: Nat, flags: Flags, input: List<&2, U32>, names: List<&2, NamedGroup>, +cursor: Cursor) -> Maybe<&2, Found>:
  match candidate:
    case True{}: foundAt(attempt(root, groups, settingsOf(flags, input, groups, names), cursor), indexOf(cursor))
    case False{}: None{}
def attemptAt(regex: RegExp, start: Start, input: List<&2, U32>, +cursor: Cursor) -> Maybe<&2, Found>:
  match regex:
    case RegExp{_, +flags, root, groups, names}: attemptIf(startsAt(start, flags, passedOf(cursor), nextScalar(cursor)), root, groups, flags, input, names, cursor)
# The first position from the one before `code` (then `rest`) where a match
# may begin (`candidate`: there).
def flagsOf(regex: RegExp) -> Flags:
  match regex: case RegExp{_, flags, _, _, _}: flags
def candidateFrom(rest: List<&2, U32>, +code: U32, candidate: Bool, +start: Start, +flags: Flags, passed: Maybe<&2, U32>, +index: Nat) -> Cursor:
  match candidate rest:
    case True{} rest: Cursor{passed, code <> rest, index}
    case False{} +next <> more: candidateFrom(more, next, startsAt(start, flags, Some{code}, Some{next}), start, flags, Some{code}, index + 1n)
    case False{} Nil{}: Cursor{Some{code}, Nil{}, index + 1n}
# The first such position after `previous`, the scalar before `ahead`.
def candidateAfter(ahead: List<&2, U32>, +previous: U32, +start: Start, +flags: Flags, +index: Nat) -> Cursor:
  match ahead:
    case +code <> rest: candidateFrom(rest, code, startsAt(start, flags, Some{previous}, Some{code}), start, flags, Some{previous}, index)
    case Nil{}: Cursor{Some{previous}, Nil{}, index}
def searchFrom(fuel: Nat, +regex: RegExp, +start: Start, +input: List<&2, U32>, attempt: Maybe<&2, Found>, cursor: Cursor) -> Maybe<&2, Found>:
  match fuel attempt cursor:
    case _ Some{result} _: Some{result}
    case _ None{} Cursor{_, Nil{}, _}: None{}
    case Zero{} None{} _: None{}
    case Succ{more} None{} Cursor{_, code <> ahead, index}:
      +next = candidateAfter(ahead, code, start, flagsOf(regex), index + 1n)
      searchFrom(more, regex, start, input, attemptAt(regex, start, input, next), next)
# The leftmost match of `regex` at `cursor` or after it (a global or
# unanchored exec from the cursor's index), attempted only where the start
# analysis `start` allows one; `input` is the whole subject.
def search(+regex: RegExp, +start: Start, +input: List<&2, U32>, +cursor: Cursor) -> Maybe<&2, Found>:
  searchFrom(4294967295n, regex, start, input, attemptAt(regex, start, input, cursor), cursor)

# Continuations
# -------------
# Each repetition records what the rest of the pattern after it needs of the
# next scalar (its `follow`), computed with the start analysis over that
# rest. A repeated single-scalar atom whose scalars cannot start the rest is
# `Disjoint`: no position its run could give back can match. Lookbehinds
# match backwards; repetitions in them keep `Anything`.
def asciiDisjoint(left: Ascii, right: Ascii) -> Bool:
  match left right:
    case Ascii{a, b, c, d} Ascii{e, f, g, h}: U32.is_eq(U32.or(U32.or(U32.and(a, e), U32.and(b, f)), U32.or(U32.and(c, g), U32.and(d, h))), 0)
def disjointOr(accepted: Ascii & Bool, follow: Follow) -> Follow:
  match accepted follow:
    case (set, wide) Scalars{+ascii, +broad}: Bool.pick(Follow, asciiDisjoint(set, ascii) && Bool.not(wide && broad), Disjoint{}, Scalars{ascii, broad})
    case _ follow: follow
def singleFollow(body: Node, follow: Follow, +flags: Flags) -> Follow:
  match body:
    case Literal{code}: disjointOr(nodeAscii(Literal{code}, ignoreCaseOf(flags), dotAllOf(flags)), follow)
    case AnyChar{}: disjointOr(nodeAscii(AnyChar{}, ignoreCaseOf(flags), dotAllOf(flags)), follow)
    case CharClass{negated, items}: disjointOr(nodeAscii(CharClass{negated, items}, ignoreCaseOf(flags), dotAllOf(flags)), follow)
    case _: follow
def followOfStart(start: Start) -> Follow:
  match start:
    case Start{True{}, _, _, _, _, _}: Anything{}
    case Start{False{}, _, ascii, wide, _, _}: Scalars{ascii, wide}
def followOf(+backward: Bool, +body: Node, after: List<&2, Node>, +flags: Flags) -> Follow:
  match backward:
    case True{}: Anything{}
    case False{}: singleFollow(body, followOfStart(startLoop(4096n, Expansion{[Path{after, False{}}], Nil{}, True{}, False{}}, flags)), flags)
# What each option, then `after`, needs next.
def optionFollows(options: List<&2, Node>, +after: List<&2, Node>, +flags: Flags) -> List<&2, Follow>:
  match options:
    case Nil{}: Nil{}
    case option <> more: followOfStart(startLoop(4096n, Expansion{[Path{option <> after, False{}}], Nil{}, True{}, False{}}, flags)) <> optionFollows(more, after, flags)
def optionStarts(backward: Bool, options: List<&2, Node>, after: List<&2, Node>, flags: Flags) -> List<&2, Follow>:
  match backward:
    case True{}: Nil{}
    case False{}: optionFollows(options, after, flags)
def firstNode(nodes: List<&2, Node>, fallback: Node) -> Node:
  match nodes:
    case node <> _: node
    case Nil{}: fallback
# `nodes` with their repetitions' follows: the items of a sequence
# (`sequence`), each followed by the items after it, or alternatives, each
# followed by `after` alone. `fuel` bounds the depth.
def annotated(fuel: Nat, nodes: List<&2, Node>, +sequence: Bool, +after: List<&2, Node>, +backward: Bool, +flags: Flags) -> List<&2, Node>:
  match fuel nodes:
    case _ Nil{}: Nil{}
    case Zero{} nodes: nodes
    case Succ{+more} Group{index, +body} <> +rest:
      Group{index, firstNode(annotated(more, [body], False{}, Bool.pick(List<&2, Node>, sequence, Sequence{rest} <> after, after), backward, flags), body)} <> annotated(more, rest, sequence, after, backward, flags)
    case Succ{+more} Look{+ahead, negated, +body} <> rest:
      Look{ahead, negated, firstNode(annotated(more, [body], False{}, Nil{}, Bool.not(ahead), flags), body)} <> annotated(more, rest, sequence, after, backward, flags)
    case Succ{+more} Alternation{+options, _} <> +rest:
      +next = Bool.pick(List<&2, Node>, sequence, Sequence{rest} <> after, after)
      Alternation{annotated(more, options, False{}, next, backward, flags), optionStarts(backward, options, next, flags)} <> annotated(more, rest, sequence, after, backward, flags)
    case Succ{+more} Sequence{items} <> +rest:
      Sequence{annotated(more, items, True{}, Bool.pick(List<&2, Node>, sequence, Sequence{rest} <> after, after), backward, flags)} <> annotated(more, rest, sequence, after, backward, flags)
    case Succ{+more} Repeat{+body, min, max, greedy, first, count, _} <> +rest:
      +next = Bool.pick(List<&2, Node>, sequence, Sequence{rest} <> after, after)
      Repeat{firstNode(annotated(more, [body], False{}, [Alternation{[Sequence{body <> next}, Sequence{next}], Nil{}}], backward, flags), body), min, max, greedy, first, count, followOf(backward, body, next, flags)} <> annotated(more, rest, sequence, after, backward, flags)
    case Succ{+more} node <> rest: node <> annotated(more, rest, sequence, after, backward, flags)
def withFollows(+root: Node, +source: String, +flags: Flags) -> Node:
  firstNode(annotated(String.length(source) + 1n, [root], False{}, Nil{}, False{}, flags), root)

# Compiling
# ---------

def compiled(+source: String, +flags: Flags, state: ParseState) -> Result<&2, &2, Error, RegExp>:
  match state:
    case Parsed{root, groups, names}: Done{RegExp{source, flags, withFollows(root, source, flags), groups, names}}
    case ParseFailed{error}: Fail{error}
    case Parsing{_, _, _, _}: Fail{SyntaxError{"Pattern too complex"}}

def compileFlags(+source: String, flags: Maybe<&2, Flags>) -> Result<&2, &2, Error, RegExp>:
  match flags:
    case None{}: Fail{SyntaxError{"Invalid flags"}}
    case Some{+valid}:
      +input = codes(source)
      compiled(source, valid, parseLoop(List.length(&2, U32, input) * 2n + 2n, Parsing{input, [Frame{RootGroup{}, 0n, Nil{}, Nil{}}], 0n, Nil{}}, unicodeOf(valid)))

# new RegExp(source, flags)
def compile(source: String, flags: String) -> Result<&2, &2, Error, RegExp>:
  compileFlags(source, parsedFlags(codes(flags), Some{noFlags()}))
