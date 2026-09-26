import Base
import ./text.bend as Text
import ./json.bend as JSON
import ./schema-value.bend as V
import ./f64.bend as F

# node-semver 7.8.5 versions (strict, non-loose mode): parse, valid, compare
# and the comparisons built on it. Numeric identifiers are kept as their
# canonical decimal text. Components are at most Number.MAX_SAFE_INTEGER and
# compare exactly; a numeric pre-release identifier beyond it is compared as
# the JavaScript number it converts to, so neighbours that round to the same
# double compare equal, as in node-semver.

type Identifier is Data:
  Numeric{digits: String}
  Alphanumeric{text: String}

# `build` is kept for callers; comparisons ignore it, as node-semver's do.
type SemVer is Data:
  SemVer{major: String, minor: String, patch: String, prerelease: List<&2, Identifier>, build: List<&2, String>}

def MAX_LENGTH() -> Nat: 256n

# Number.MAX_SAFE_INTEGER
def MAX_SAFE_INTEGER() -> String: "9007199254740991"

# Characters
# ----------

def digitCode(+code: U32) -> Bool: U32.is_ge(code, 48) && U32.is_le(code, 57)

def letterDashCode(+code: U32) -> Bool:
  (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 97) && U32.is_le(code, 122)) || U32.is_eq(code, 45)

def digit(char: Char) -> Bool:
  match char:
    case Chr{+code}: digitCode(code)

def letterDash(char: Char) -> Bool:
  match char:
    case Chr{+code}: letterDashCode(code)

def alnumDash(char: Char) -> Bool:
  match char:
    case Chr{+code}: digitCode(code) || letterDashCode(code)

def allChars(~ok: Char -> Bool, text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{+char, rest}: ok(char) && allChars(~ok, rest)

def anyChar(~ok: Char -> Bool, text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{+char, rest}: ok(char) || anyChar(~ok, rest)


# Magnitudes of canonical decimal text
# ------------------------------------

def lengthFirst(order: Cmp, +left: String, +right: String) -> Cmp:
  match order:
    case EQ{}: String.order(left, right)
    case other: other

def compareDigits(+left: String, +right: String) -> Cmp:
  lengthFirst(Nat.cmp(String.length(left), String.length(right)), left, right)

# Identifiers
# -----------

# NUMERICIDENTIFIER: 0|[1-9]\d*
def numericIdentifier(+text: String) -> Bool:
  match text:
    case SCon{'0', SNil{}}: True{}
    case SCon{'0', _}: False{}
    case SCon{_, _}: allChars(~digit, text)
    case SNil{}: False{}

# NONNUMERICIDENTIFIER: \d*[a-zA-Z-][a-zA-Z0-9-]*
def nonNumericIdentifier(+text: String) -> Bool:
  allChars(~alnumDash, text) && anyChar(~letterDash, text)

def notGreater(order: Cmp) -> Bool:
  match order:
    case GT{}: False{}
    case _: True{}

def safeInteger(+digits: String) -> Bool: notGreater(compareDigits(digits, MAX_SAFE_INTEGER()))

# A pre-release identifier: numeric when it is all digits.
def identifier(+text: String) -> Maybe<&2, Identifier>:
  Bool.pick(Maybe<&2, Identifier>, numericIdentifier(text), Some{Numeric{text}}, Bool.pick(Maybe<&2, Identifier>, nonNumericIdentifier(text), Some{Alphanumeric{text}}, None{}))

def identifiers(parts: List<&2, String>) -> Maybe<&2, List<&2, Identifier>>:
  match parts:
    case Nil{}: Some{Nil{}}
    case part <> rest: Maybe.bind(&2, Identifier, List<&2, Identifier>, identifier(part), head => Maybe.map(&2, List<&2, Identifier>, List<&2, Identifier>, tail => head <> tail, identifiers(rest)))

def buildIdentifiers(parts: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  match parts:
    case Nil{}: Some{Nil{}}
    case SNil{} <> _: None{}
    case +part <> rest: Bool.pick(Unit -> Maybe<&2, List<&2, String>>, allChars(~alnumDash, part), _ => Maybe.map(&2, List<&2, String>, List<&2, String>, tail => part <> tail, buildIdentifiers(rest)), _ => None{})(Unit{})

# Parsing
# -------

type Tail is Data:
  Tail{main: String, prerelease: Maybe<&2, String>, build: Maybe<&2, String>}

def splitAt(text: String, +char: Char, +reversed: String) -> String & Maybe<&2, String>:
  match text:
    case SNil{}: (String.reverse(reversed), None{})
    case SCon{+head, +rest}: Bool.pick(Unit -> String & Maybe<&2, String>, Char.is_eq(head, char), _ => (String.reverse(reversed), Some{rest}), _ => splitAt(rest, char, SCon{head, reversed}))(Unit{})

def withPrerelease(pair: String & Maybe<&2, String>, build: Maybe<&2, String>) -> Tail:
  match pair:
    case (main, prerelease): Tail{main, prerelease, build}

def tail(pair: String & Maybe<&2, String>) -> Tail:
  match pair:
    case (beforeBuild, build): withPrerelease(splitAt(beforeBuild, '-', ""), build)

def prereleaseOf(value: Maybe<&2, String>) -> Maybe<&2, List<&2, Identifier>>:
  match value:
    case None{}: Some{Nil{}}
    case Some{text}: identifiers(String.split(text, '.'))

def buildOf(value: Maybe<&2, String>) -> Maybe<&2, List<&2, String>>:
  match value:
    case None{}: Some{Nil{}}
    case Some{text}: buildIdentifiers(String.split(text, '.'))

def component(+text: String) -> Bool: numericIdentifier(text) && safeInteger(text)

def assembled(main: List<&2, String>, prerelease: Maybe<&2, List<&2, Identifier>>, build: Maybe<&2, List<&2, String>>) -> Maybe<&2, SemVer>:
  match main prerelease build:
    case (+major <> +minor <> +patch <> Nil{}) Some{identifiers} Some{builds}: Bool.pick(Maybe<&2, SemVer>, component(major) && component(minor) && component(patch), Some{SemVer{major, minor, patch, identifiers, builds}}, None{})
    case _ _ _: None{}

def parsedTail(value: Tail) -> Maybe<&2, SemVer>:
  match value:
    case Tail{main, prerelease, build}: assembled(String.split(main, '.'), prereleaseOf(prerelease), buildOf(build))

def withoutV(text: String) -> String:
  match text:
    case SCon{'v', rest}: rest
    case other: other

def bounded(+version: String) -> Maybe<&2, SemVer>:
  Bool.pick(Unit -> Maybe<&2, SemVer>, Nat.is_gt(String.length(version), MAX_LENGTH()), _ => None{}, _ => parsedTail(tail(splitAt(withoutV(Text.trim(version)), '+', ""))))(Unit{})

# node-semver parse(version): the version, or None where the constructor
# throws (too long, not a strict full version, or a component above
# Number.MAX_SAFE_INTEGER).
def parse(+version: String) -> Maybe<&2, SemVer>: bounded(version)

def showIdentifier(value: Identifier) -> String:
  match value:
    case Numeric{digits}: digits
    case Alphanumeric{text}: text

def showIdentifiers(values: List<&2, Identifier>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case head <> rest: showIdentifier(head) <> showIdentifiers(rest)

# SemVer.format(): major.minor.patch[-prerelease]
def format(value: SemVer) -> String:
  match value:
    case SemVer{major, minor, patch, Nil{}, _}: major ++ "." ++ minor ++ "." ++ patch
    case SemVer{major, minor, patch, prerelease, _}: major ++ "." ++ minor ++ "." ++ patch ++ "-" ++ String.join(showIdentifiers(prerelease), ".")

# valid(version): the normalized version, or None.
def valid(+version: String) -> Maybe<&2, String>: Maybe.map(&2, SemVer, String, format, parse(version))

# Comparison
# ----------

def asDouble(value: Result<&2, &2, JSON.ParseError, V.Value>) -> F64:
  match value:
    case Done{V.Number{number}}: number
    case _: F.fromU32(0)

def doubleOrder(order: Maybe<&2, Cmp>) -> Cmp: Maybe.default(&2, Cmp, order, EQ{})

# Safe integers compare exactly; larger ones as their rounded doubles.
def compareNumeric(+a: String, +b: String) -> Cmp:
  Bool.pick(Unit -> Cmp, safeInteger(a) && safeInteger(b), _ => compareDigits(a, b), _ => doubleOrder(F.compare(asDouble(JSON.parse(a)), asDouble(JSON.parse(b)))))(Unit{})

def compareIdentifiers(left: Identifier, right: Identifier) -> Cmp:
  match left right:
    case Numeric{a} Numeric{b}: compareNumeric(a, b)
    case Numeric{_} Alphanumeric{_}: LT{}
    case Alphanumeric{_} Numeric{_}: GT{}
    case Alphanumeric{a} Alphanumeric{b}: String.order(a, b)

def orElse(order: Cmp, next: Cmp) -> Cmp:
  match order:
    case EQ{}: next
    case other: other

# comparePre continues past identical identifiers only; any other pair
# decides, even when compareIdentifiers finds them equal.
def sameIdentifier(+left: Identifier, +right: Identifier) -> Bool:
  match left right:
    case Numeric{a} Numeric{b}: String.eq(a, b)
    case Alphanumeric{a} Alphanumeric{b}: String.eq(a, b)
    case _ _: False{}

def comparePreList(left: List<&2, Identifier>, right: List<&2, Identifier>) -> Cmp:
  match left right:
    case Nil{} Nil{}: EQ{}
    case _ Nil{}: GT{}
    case Nil{} _: LT{}
    case +a <> as +b <> bs: Bool.pick(Unit -> Cmp, sameIdentifier(a, b), _ => comparePreList(as, bs), _ => compareIdentifiers(a, b))(Unit{})

# Not having a pre-release ranks above having one.
def comparePre(left: List<&2, Identifier>, right: List<&2, Identifier>) -> Cmp:
  match left right:
    case Nil{} Nil{}: EQ{}
    case _ Nil{}: LT{}
    case Nil{} _: GT{}
    case a b: comparePreList(a, b)

def compareSemVer(left: SemVer, right: SemVer) -> Cmp:
  match left right:
    case SemVer{a1, a2, a3, ap, _} SemVer{b1, b2, b3, bp, _}:
      orElse(compareDigits(a1, b1), orElse(compareDigits(a2, b2), orElse(compareDigits(a3, b3), comparePre(ap, bp))))
