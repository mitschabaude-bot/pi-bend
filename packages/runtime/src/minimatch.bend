import Base
import ./f64.bend as F
import ./number-string.bend as Number
import ./regex.bend as Regex

# minimatch@10.2.6 with default options on posix, including its dependency
# brace-expansion@5.0.9. Matching follows the upstream pipeline exactly:
# comment/empty/negation handling, brace expansion, slash splitting, level-one
# optimization, segment compilation through the extglob AST into a regular
# expression, and the globstar-aware `matchOne` walk.
#
# JavaScript strings are UTF-16 and upstream observes that width (`?`, class
# members and `f.length` see code units), so patterns and paths are handled as
# lists of UTF-16 code units; generated expressions are parsed with the same
# `u` flag upstream compiles them with, and matched by a set-of-positions
# evaluator using the Unicode 17 property tables of `regex.bend`.
#
# API: `minimatch(path, pattern)`; `tryMinimatch` reports the patterns
# upstream rejects by throwing (`Fail{InvalidRegExp}`), where `minimatch`
# answers False; `compile(pattern)` and `test(matcher, path)` reuse one
# compiled pattern (upstream `new Minimatch(pattern).match(path)`);
# `braceExpand(pattern)` is `minimatch.braceExpand`.

# ---------------------------------------------------------------------------
# UTF-16 code units
# ---------------------------------------------------------------------------

def unitsGo(text: String, +reversed: List<&2, U32>) -> List<&2, U32>:
  match text:
    case SNil{}: List.reverse(&2, U32, reversed)
    case SCon{Chr{+code}, +rest}:
      +offset = (code - 65536 : U32)
      Bool.pick(Unit -> List<&2, U32>, U32.is_ge(code, 65536),
        _ => unitsGo(rest, (56320 + U32.and(offset, 1023) : U32) <> (55296 + U32.shrn(offset, 10n) : U32) <> reversed),
        _ => unitsGo(rest, code <> reversed))(Unit{})

# The UTF-16 code units of a scalar string.
def units(text: String) -> List<&2, U32>: unitsGo(text, Nil{})

def highUnit(+code: U32) -> Bool: U32.is_ge(code, 55296) && U32.is_le(code, 56319)
def lowUnit(+code: U32) -> Bool: U32.is_ge(code, 56320) && U32.is_le(code, 57343)

# Code points of a unit string, as a `u`-flag expression reads it: surrogate
# pairs combine, unpaired surrogates stay single code points.
def pointsGo(text: List<&2, U32>, +reversed: List<&2, U32>) -> List<&2, U32>:
  match text:
    case Nil{}: List.reverse(&2, U32, reversed)
    case +high <> +low <> +rest:
      Bool.pick(Unit -> List<&2, U32>, highUnit(high) && lowUnit(low),
        _ => pointsGo(rest, (65536 + (high - 55296) * 1024 + low - 56320 : U32) <> reversed),
        _ => pointsGo(low <> rest, high <> reversed))(Unit{})
    case code <> Nil{}: List.reverse(&2, U32, code <> reversed)

def codePoints(text: List<&2, U32>) -> List<&2, U32>: pointsGo(text, Nil{})

# Scalars of a unit string; unpaired surrogates become U+FFFD.
def scalarsGo(points: List<&2, U32>, reversed: String) -> String:
  match points:
    case Nil{}: String.reverse(reversed)
    case +code <> rest: scalarsGo(rest, SCon{Chr{Bool.pick(U32, highUnit(code) || lowUnit(code) || U32.is_gt(code, 1114111), 65533, code)}, reversed})

def scalars(text: List<&2, U32>) -> String: scalarsGo(codePoints(text), SNil{})

# An unrestricted recursion budget: every walk below terminates structurally,
# the fuel only makes that visible to the checker.
def deep() -> Nat: 4294967295n

def isLineTerminator(+code: U32) -> Bool:
  U32.is_eq(code, 10) || U32.is_eq(code, 13) || U32.is_eq(code, 8232) || U32.is_eq(code, 8233)

def startsWithCode(text: List<&2, U32>, code: U32) -> Bool:
  match text:
    case first <> _: U32.is_eq(first, code)
    case Nil{}: False{}

def isEmpty(text: List<&2, U32>) -> Bool:
  match text:
    case Nil{}: True{}
    case _: False{}

# List helpers in tail form: the Bun lane has a bounded native stack.
def onto(-A: Data, reversed: List<&2, A>, items: List<&2, A>) -> List<&2, A>:
  match reversed:
    case Nil{}: items
    case item <> rest: onto(A, rest, item <> items)

def appended(-A: Data, left: List<&2, A>, right: List<&2, A>) -> List<&2, A>: onto(A, List.reverse(&2, A, left), right)

def countGo(-A: Data, items: List<&2, A>, total: Nat) -> Nat:
  match items:
    case Nil{}: total
    case _ <> rest: countGo(A, rest, 1n + total)

def lengthOf(-A: Data, items: List<&2, A>) -> Nat: countGo(A, items, 0n)

def prefixGo(-A: Data, count: Nat, items: List<&2, A>, reversed: List<&2, A>) -> List<&2, A>:
  match count items:
    case 0n _: List.reverse(&2, A, reversed)
    case _ Nil{}: List.reverse(&2, A, reversed)
    case 1n+more item <> rest: prefixGo(A, more, rest, item <> reversed)

def firstOf(-A: Data, items: List<&2, A>, count: Nat) -> List<&2, A>: prefixGo(A, count, items, Nil{})

def cat(left: List<&2, U32>, right: List<&2, U32>) -> List<&2, U32>: appended(U32, left, right)
def size(text: List<&2, U32>) -> Nat: lengthOf(U32, text)
def take(text: List<&2, U32>, count: Nat) -> List<&2, U32>: firstOf(U32, text, count)
def skip(text: List<&2, U32>, count: Nat) -> List<&2, U32>: List.drop(&2, U32, text, count)

def same(left: List<&2, U32>, right: List<&2, U32>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> restA b <> restB: Bool.pick(Unit -> Bool, U32.is_eq(a, b), _ => same(restA, restB), _ => False{})(Unit{})
    case _ _: False{}

def startsWith(text: List<&2, U32>, prefix: List<&2, U32>) -> Bool:
  match text prefix:
    case _ Nil{}: True{}
    case a <> restA b <> restB: Bool.pick(Unit -> Bool, U32.is_eq(a, b), _ => startsWith(restA, restB), _ => False{})(Unit{})
    case _ _: False{}

def endsWith(+text: List<&2, U32>, +suffix: List<&2, U32>) -> Bool:
  Nat.is_ge(size(text), size(suffix)) && same(skip(text, Nat.sub(size(text), size(suffix))), suffix)

def includesCode(text: List<&2, U32>, +code: U32) -> Bool:
  match text:
    case Nil{}: False{}
    case first <> rest: Bool.pick(Unit -> Bool, U32.is_eq(first, code), _ => True{}, _ => includesCode(rest, code))(Unit{})

def repeatGo(+code: U32, count: Nat, text: List<&2, U32>) -> List<&2, U32>:
  match count:
    case 0n: text
    case 1n+more: repeatGo(code, more, code <> text)

def repeatUnit(code: U32, count: Nat) -> List<&2, U32>: repeatGo(code, count, Nil{})

# JavaScript `text.split(separator)` for a one-unit separator.
def splitGo(text: List<&2, U32>, +separator: U32, +current: List<&2, U32>, +parts: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match text:
    case Nil{}: List.reverse(&2, List<&2, U32>, List.reverse(&2, U32, current) <> parts)
    case +code <> +rest:
      Bool.pick(Unit -> List<&2, List<&2, U32>>, U32.is_eq(code, separator),
        _ => splitGo(rest, separator, Nil{}, List.reverse(&2, U32, current) <> parts),
        _ => splitGo(rest, separator, code <> current, parts))(Unit{})

def splitOn(text: List<&2, U32>, separator: U32) -> List<&2, List<&2, U32>>: splitGo(text, separator, Nil{}, Nil{})

def lastOr(values: List<&2, List<&2, U32>>, fallback: List<&2, U32>) -> List<&2, U32>:
  match values:
    case Nil{}: fallback
    case value <> Nil{}: value
    case _ <> rest: lastOr(rest, fallback)

def withoutLast(values: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  List.reverse(&2, List<&2, U32>, List.drop(&2, List<&2, U32>, List.reverse(&2, List<&2, U32>, values), 1n))

def headOr(values: List<&2, List<&2, U32>>, fallback: List<&2, U32>) -> List<&2, U32>:
  match values:
    case Nil{}: fallback
    case value <> _: value

def allEmpty(values: List<&2, List<&2, U32>>) -> Bool:
  match values:
    case Nil{}: True{}
    case Nil{} <> rest: allEmpty(rest)
    case _: False{}

# ---------------------------------------------------------------------------
# brace-expansion@5.0.9
# ---------------------------------------------------------------------------

# Upstream swaps escaped `\\ \{ \} \, \.` for random sentinel strings; these
# units lie beyond Unicode, so they cannot collide with input either.
def escSlash() -> U32: 1114112
def escOpen() -> U32: 1114113
def escClose() -> U32: 1114114
def escComma() -> U32: 1114115
def escPeriod() -> U32: 1114116

def escapeBracesGo(text: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match text:
    case Nil{}: List.reverse(&2, U32, reversed)
    case 92 <> 92 <> rest: escapeBracesGo(rest, escSlash() <> reversed)
    case 92 <> 123 <> rest: escapeBracesGo(rest, escOpen() <> reversed)
    case 92 <> 125 <> rest: escapeBracesGo(rest, escClose() <> reversed)
    case 92 <> 44 <> rest: escapeBracesGo(rest, escComma() <> reversed)
    case 92 <> 46 <> rest: escapeBracesGo(rest, escPeriod() <> reversed)
    case code <> rest: escapeBracesGo(rest, code <> reversed)

def unescapeUnit(+code: U32) -> U32:
  Bool.pick(U32, U32.is_eq(code, 1114112), 92,
    Bool.pick(U32, U32.is_eq(code, 1114113), 123,
      Bool.pick(U32, U32.is_eq(code, 1114114), 125,
        Bool.pick(U32, U32.is_eq(code, 1114115), 44,
          Bool.pick(U32, U32.is_eq(code, 1114116), 46, code)))))

def unescapeBraces(text: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match text:
    case Nil{}: List.reverse(&2, U32, reversed)
    case code <> rest: unescapeBraces(rest, unescapeUnit(code) <> reversed)

def unescapeAll(values: List<&2, List<&2, U32>>, reversed: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match values:
    case Nil{}: List.reverse(&2, List<&2, U32>, reversed)
    case value <> rest: unescapeAll(rest, unescapeBraces(value, Nil{}) <> reversed)

# `str.indexOf(unit, from)`.
def indexGo(text: List<&2, U32>, +code: U32, +index: Nat) -> Maybe<&2, Nat>:
  match text:
    case Nil{}: None{}
    case first <> +rest:
      Bool.pick(Unit -> Maybe<&2, Nat>, U32.is_eq(first, code), _ => Some{index}, _ => indexGo(rest, code, 1n + index))(Unit{})

def indexFrom(text: List<&2, U32>, code: U32, +from: Nat) -> Maybe<&2, Nat>:
  indexGo(skip(text, from), code, from)

def afterIndex(index: Maybe<&2, Nat>) -> Nat:
  match index:
    case None{}: 0n
    case Some{value}: 1n + value

def hasIndex(index: Maybe<&2, Nat>) -> Bool:
  match index:
    case None{}: False{}
    case Some{_}: True{}

def sameIndex(left: Maybe<&2, Nat>, right: Maybe<&2, Nat>) -> Bool:
  match left right:
    case Some{a} Some{b}: Nat.is_eq(a, b)
    case _ _: False{}

def indexBefore(left: Maybe<&2, Nat>, right: Maybe<&2, Nat>) -> Bool:
  match left right:
    case Some{a} Some{b}: Nat.is_lt(a, b)
    case _ _: False{}

def natBefore(value: Maybe<&2, Nat>, +limit: Nat) -> Bool:
  match value:
    case Some{a}: Nat.is_lt(a, limit)
    case None{}: False{}

def orElseNat(value: Maybe<&2, Nat>, fallback: Nat) -> Nat:
  match value:
    case Some{a}: a
    case None{}: fallback

type Span is Data:
  Span{start: Nat, end: Nat}

def popped(begs: List<&2, Nat>) -> List<&2, Nat>:
  match begs:
    case Nil{}: Nil{}
    case _ <> rest: rest

def stackTop(begs: List<&2, Nat>) -> Maybe<&2, Nat>:
  match begs:
    case Nil{}: None{}
    case value <> _: Some{value}

def isSingle(begs: List<&2, Nat>) -> Bool:
  match begs:
    case _ <> Nil{}: True{}
    case _: False{}

def finalSpan(begs: List<&2, Nat>, left: Nat, right: Maybe<&2, Nat>) -> Maybe<&2, Span>:
  match begs right:
    case _ <> _ Some{end}: Some{Span{left, end}}
    case _ _: None{}

def nextIndex(+ai: Maybe<&2, Nat>, +bi: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  Bool.pick(Maybe<&2, Nat>, hasIndex(ai) && hasIndex(bi) && indexBefore(ai, bi), ai, bi)

# balanced-match@4.0.4 `range('{', '}', str)`, iterating over brace positions.
type Range is Data:
  Scanning{text: List<&2, U32>, ai: Maybe<&2, Nat>, bi: Maybe<&2, Nat>, i: Maybe<&2, Nat>, begs: List<&2, Nat>, left: Nat, right: Maybe<&2, Nat>}
  Ranged{result: Maybe<&2, Span>}

def openBrace(+text: List<&2, U32>, +i: Maybe<&2, Nat>, +bi: Maybe<&2, Nat>, begs: List<&2, Nat>, left: Nat, right: Maybe<&2, Nat>) -> Range:
  +ai = indexFrom(text, 123, afterIndex(i))
  Scanning{text, ai, bi, nextIndex(ai, bi), orElseNat(i, 0n) <> begs, left, right}

def closeBrace(+text: List<&2, U32>, +ai: Maybe<&2, Nat>, +bi: Maybe<&2, Nat>, +i: Maybe<&2, Nat>, +begs: List<&2, Nat>, +left: Nat, right: Maybe<&2, Nat>) -> Range:
  +closer = natBefore(stackTop(begs), left)
  +bi2 = indexFrom(text, 125, afterIndex(i))
  Scanning{text, ai, bi2, nextIndex(ai, bi2), popped(begs), Bool.pick(Nat, closer, orElseNat(stackTop(begs), 0n), left), Bool.pick(Maybe<&2, Nat>, closer, bi, right)}

def rangeStep(state: Range) -> Range:
  match state:
    case Ranged{result}: Ranged{result}
    case Scanning{+text, +ai, +bi, +i, +begs, +left, +right}:
      Bool.pick(Unit -> Range, hasIndex(i),
        _ => Bool.pick(Unit -> Range, sameIndex(i, ai),
          _ => openBrace(text, i, bi, begs, left, right),
          _ => Bool.pick(Unit -> Range, isSingle(begs),
            _ => Ranged{Some{Span{orElseNat(stackTop(begs), 0n), orElseNat(bi, 0n)}}},
            _ => closeBrace(text, ai, bi, i, begs, left, right))(Unit{}))(Unit{}),
        _ => Ranged{finalSpan(begs, left, right)})(Unit{})

def rangeLoop(fuel: Nat, state: Range) -> Maybe<&2, Span>:
  match fuel state:
    case _ Ranged{result}: result
    case 0n _: None{}
    case 1n+more _: rangeLoop(more, rangeStep(state))

def braceRange(+text: List<&2, U32>) -> Maybe<&2, Span>:
  +ai = indexFrom(text, 123, 0n)
  +bi = indexFrom(text, 125, afterIndex(ai))
  Bool.pick(Unit -> Maybe<&2, Span>, hasIndex(ai) && hasIndex(bi),
    _ => rangeLoop(deep(), Scanning{text, ai, bi, ai, Nil{}, size(text), None{}}),
    _ => None{})(Unit{})

type Balanced is Data:
  Balanced{pre: List<&2, U32>, body: List<&2, U32>, post: List<&2, U32>}

def balancedSpan(+text: List<&2, U32>, span: Maybe<&2, Span>) -> Maybe<&2, Balanced>:
  match span:
    case None{}: None{}
    case Some{Span{+start, +end}}:
      Some{Balanced{take(text, start), take(skip(text, 1n + start), Nat.sub(end, 1n + start)), skip(text, 1n + end)}}

def balanced(+text: List<&2, U32>) -> Maybe<&2, Balanced>: balancedSpan(text, braceRange(text))

def braced(body: List<&2, U32>) -> List<&2, U32>: 123 <> cat(body, 125 <> Nil{})

# `parseCommaParts`: `str.split(',')`, keeping nested brace sets whole.
def attachPost(+first: List<&2, List<&2, U32>>, joined: List<&2, U32>, +postParts: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  appended(List<&2, U32>, withoutLast(first), cat(joined, headOr(postParts, Nil{})) <> List.drop(&2, List<&2, U32>, postParts, 1n))

def commaParts(fuel: Nat, +text: List<&2, U32>, set: Maybe<&2, Balanced>) -> List<&2, List<&2, U32>>:
  match fuel set:
    case 0n _: text <> Nil{}
    case 1n+_ None{}: splitOn(text, 44)
    case 1n+more Some{Balanced{pre, body, +post}}:
      +first = splitOn(pre, 44)
      +joined = cat(lastOr(first, Nil{}), braced(body))
      Bool.pick(Unit -> List<&2, List<&2, U32>>, isEmpty(post),
        _ => appended(List<&2, U32>, withoutLast(first), joined <> Nil{}),
        _ => attachPost(first, joined, commaParts(more, post, balanced(post))))(Unit{})

def parseCommaParts(+text: List<&2, U32>) -> List<&2, List<&2, U32>>:
  commaParts(deep(), text, balanced(text))

def expansionMax() -> Nat: 100000n
def expansionMaxLength() -> Nat: 4000000n

# `combine`: every `acc[a] + pre + values[v]`, bounded by count and length.
type Combined is Data:
  Combined{out: List<&2, List<&2, U32>>, count: Nat, length: Nat, stopped: Bool}

def combineValues(values: List<&2, List<&2, U32>>, +prefix: List<&2, U32>, +drop: Bool, state: Combined) -> Combined:
  match values state:
    case _ Combined{out, count, length, True{}}: Combined{out, count, length, True{}}
    case Nil{} current: current
    case value <> +rest Combined{+out, +count, +length, False{}}:
      +expansion = cat(prefix, value)
      +total = length + size(expansion)
      Bool.pick(Unit -> Combined, Nat.is_ge(count, expansionMax()),
        _ => Combined{out, count, length, True{}},
        _ => Bool.pick(Unit -> Combined, drop && isEmpty(expansion),
          _ => combineValues(rest, prefix, drop, Combined{out, count, length, False{}}),
          _ => Bool.pick(Unit -> Combined, Nat.is_gt(total, expansionMaxLength()),
            _ => Combined{out, count, length, True{}},
            _ => combineValues(rest, prefix, drop, Combined{expansion <> out, 1n + count, total, False{}}))(Unit{}))(Unit{}))(Unit{})

def combineAll(acc: List<&2, List<&2, U32>>, +pre: List<&2, U32>, +values: List<&2, List<&2, U32>>, +drop: Bool, state: Combined) -> Combined:
  match acc:
    case Nil{}: state
    case first <> rest: combineAll(rest, pre, values, drop, combineValues(values, cat(first, pre), drop, state))

def combinedOut(state: Combined) -> List<&2, List<&2, U32>>:
  match state:
    case Combined{out, _, _, _}: List.reverse(&2, List<&2, U32>, out)

def combine(acc: List<&2, List<&2, U32>>, pre: List<&2, U32>, values: List<&2, List<&2, U32>>, drop: Bool) -> List<&2, List<&2, U32>>:
  combinedOut(combineAll(acc, pre, values, drop, Combined{Nil{}, 0n, 0n, False{}}))

def emptyOnly() -> List<&2, List<&2, U32>>: Nil{} <> Nil{}

def isDigit(+code: U32) -> Bool: U32.is_ge(code, 48) && U32.is_le(code, 57)
def isAsciiLetter(+code: U32) -> Bool: (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 97) && U32.is_le(code, 122))

def digitsRest(text: List<&2, U32>) -> List<&2, U32>:
  match text:
    case +code <> +rest: Bool.pick(Unit -> List<&2, U32>, isDigit(code), _ => digitsRest(rest), _ => code <> rest)(Unit{})
    case Nil{}: Nil{}

# Consume `-?\d+`, returning the remainder.
def unsignedDigits(text: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match text:
    case +code <> +rest: Bool.pick(Maybe<&2, List<&2, U32>>, isDigit(code), Some{digitsRest(rest)}, None{})
    case Nil{}: None{}

def signedDigits(text: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match text:
    case 45 <> rest: unsignedDigits(rest)
    case other: unsignedDigits(other)

def letter(text: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match text:
    case +code <> +rest: Bool.pick(Maybe<&2, List<&2, U32>>, isAsciiLetter(code), Some{rest}, None{})
    case Nil{}: None{}

def dots(text: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match text:
    case Some{46 <> 46 <> rest}: Some{rest}
    case _: None{}

def orSigned(text: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match text:
    case Some{rest}: signedDigits(rest)
    case None{}: None{}

def orLetter(text: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match text:
    case Some{rest}: letter(rest)
    case None{}: None{}

def sequenceEnd(text: Maybe<&2, List<&2, U32>>) -> Bool:
  match text:
    case Some{Nil{}}: True{}
    case _: False{}

# `(?:\.\.-?\d+)?$` after a sequence's second endpoint.
def sequenceTail(text: Maybe<&2, List<&2, U32>>) -> Bool:
  match text:
    case Some{Nil{}}: True{}
    case Some{46 <> 46 <> rest}: sequenceEnd(signedDigits(rest))
    case _: False{}

def isNumericSequence(+body: List<&2, U32>) -> Bool: sequenceTail(orSigned(dots(signedDigits(body))))
def isAlphaSequence(+body: List<&2, U32>) -> Bool: sequenceTail(orLetter(dots(letter(body))))

# `body.split(/\.\./)`.
def splitDotsGo(text: List<&2, U32>, +current: List<&2, U32>, +parts: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match text:
    case Nil{}: List.reverse(&2, List<&2, U32>, List.reverse(&2, U32, current) <> parts)
    case 46 <> 46 <> rest: splitDotsGo(rest, Nil{}, List.reverse(&2, U32, current) <> parts)
    case code <> rest: splitDotsGo(rest, code <> current, parts)

def splitDots(text: List<&2, U32>) -> List<&2, List<&2, U32>>: splitDotsGo(text, Nil{}, Nil{})

def firstCode(text: List<&2, U32>) -> U32:
  match text:
    case code <> _: code
    case Nil{}: 0

# `numeric`: parseInt for digits (Number agrees on `-?\d+`), else the char code.
def numeric(+text: List<&2, U32>) -> F64:
  Bool.pick(Unit -> F64, sequenceEnd(signedDigits(text)), _ => Number.toNumber(scalars(text)), _ => U32.to_f64(firstCode(text)))(Unit{})

def oneF64() -> F64: U32.to_f64(1)
def zeroF64() -> F64: U32.to_f64(0)

def isPadded(text: List<&2, U32>) -> Bool:
  match text:
    case 45 <> 48 <> code <> _: isDigit(code)
    case 48 <> code <> _: isDigit(code)
    case _: False{}

def anyPadded(values: List<&2, List<&2, U32>>) -> Bool:
  match values:
    case Nil{}: False{}
    case value <> rest: Bool.pick(Unit -> Bool, isPadded(value), _ => True{}, _ => anyPadded(rest))(Unit{})

def orEmpty(text: Maybe<&2, String>) -> String:
  match text:
    case Some{value}: value
    case None{}: ""

# `String(i)` for a JavaScript number.
def numberText(+value: F64) -> List<&2, U32>: units(orEmpty(F.toDecimal(value)))

def nth(values: List<&2, List<&2, U32>>, index: Nat) -> List<&2, U32>: headOr(List.drop(&2, List<&2, U32>, values, index), Nil{})

def charValue(+value: F64) -> List<&2, U32>:
  +code = U32.and(F64.to_u32(value), 65535)
  Bool.pick(List<&2, U32>, U32.is_eq(code, 92), Nil{}, code <> Nil{})

def paddedValue(+value: F64, pad: Bool, +width: Nat) -> List<&2, U32>:
  +text = numberText(value)
  +zeros = repeatUnit(48, Nat.sub(width, size(text)))
  Bool.pick(Unit -> List<&2, U32>, pad && Nat.is_gt(width, size(text)),
    _ => Bool.pick(List<&2, U32>, F64.is_lt(value, zeroF64()), 45 <> cat(zeros, skip(text, 1n)), cat(zeros, text)),
    _ => text)(Unit{})

def sequenceValues(fuel: Nat, +i: F64, +y: F64, +incr: F64, +reverse: Bool, +alpha: Bool, +pad: Bool, +width: Nat, +count: Nat, +length: Nat, +out: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match fuel:
    case 0n: List.reverse(&2, List<&2, U32>, out)
    case 1n+more:
      +within = Bool.pick(Bool, reverse, F64.is_ge(i, y), F64.is_le(i, y)) && Nat.is_lt(count, expansionMax())
      +value = Bool.pick(Unit -> List<&2, U32>, alpha, _ => charValue(i), _ => paddedValue(i, pad, width))(Unit{})
      +total = length + size(value)
      Bool.pick(Unit -> List<&2, List<&2, U32>>, within && Nat.is_le(total, expansionMaxLength()),
        _ => sequenceValues(more, F64.add(i, incr), y, incr, reverse, alpha, pad, width, 1n + count, total, value <> out),
        _ => List.reverse(&2, List<&2, U32>, out))(Unit{})

# `expandSequence`: `{x..y}` or `{x..y..step}`, numeric or alphabetic.
def expandSequence(+body: List<&2, U32>, alpha: Bool) -> List<&2, List<&2, U32>>:
  +parts = splitDots(body)
  +x = numeric(nth(parts, 0n))
  +y = numeric(nth(parts, 1n))
  +width = Nat.max(size(nth(parts, 0n)), size(nth(parts, 1n)))
  +step = Bool.pick(F64, Nat.is_eq(lengthOf(List<&2, U32>, parts), 3n), F64.max(F64.abs(numeric(nth(parts, 2n))), oneF64()), oneF64())
  +reverse = F64.is_lt(y, x)
  sequenceValues(expansionMax() + 1n, x, y, Bool.pick(F64, reverse, F64.neg(step), step), reverse, alpha, anyPadded(parts), width, 0n, 0n, Nil{})

def embraceAll(values: List<&2, List<&2, U32>>, reversed: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match values:
    case Nil{}: List.reverse(&2, List<&2, U32>, reversed)
    case value <> rest: embraceAll(rest, braced(value) <> reversed)

# `left.concat(right)` without deep recursion over `left`.
def prependReversed(reversed: List<&2, List<&2, U32>>, right: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match reversed:
    case Nil{}: right
    case value <> rest: prependReversed(rest, value <> right)

def concat(left: List<&2, List<&2, U32>>, right: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  prependReversed(List.reverse(&2, List<&2, U32>, left), right)

# The comma-set values after dropping empties and applying the bounds.
def boundedValues(values: List<&2, List<&2, U32>>, +drop: Bool, +count: Nat, +length: Nat, +reversed: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match values:
    case Nil{}: List.reverse(&2, List<&2, U32>, reversed)
    case +value <> +rest:
      Bool.pick(Unit -> List<&2, List<&2, U32>>, drop && isEmpty(value),
        _ => boundedValues(rest, drop, count, length, reversed),
        _ => Bool.pick(Unit -> List<&2, List<&2, U32>>, Nat.is_ge(count, expansionMax()) || Nat.is_gt(length + size(value), expansionMaxLength()),
          _ => List.reverse(&2, List<&2, U32>, reversed),
          _ => boundedValues(rest, drop, 1n + count, length + size(value), value <> reversed))(Unit{}))(Unit{})

# `/,(?!,).*\}/.test(post)`: 0 searching, 1 after a comma, 2 inside `.*`.
def commaThenClose(text: List<&2, U32>, +state: U32) -> Bool:
  match text:
    case Nil{}: False{}
    case +code <> +rest:
      Bool.pick(Unit -> Bool, U32.is_eq(state, 0),
        _ => commaThenClose(rest, Bool.pick(U32, U32.is_eq(code, 44), 1, 0)),
        _ => Bool.pick(Unit -> Bool, U32.is_eq(code, 125) || (U32.is_eq(state, 1) && U32.is_eq(code, 44)),
          _ => U32.is_eq(code, 125) || commaThenClose(rest, 1),
          _ => commaThenClose(rest, Bool.pick(U32, isLineTerminator(code), 0, 2)))(Unit{}))(Unit{})

def endsWithDollar(text: List<&2, U32>) -> Bool:
  match text:
    case Nil{}: False{}
    case code <> Nil{}: U32.is_eq(code, 36)
    case _ <> rest: endsWithDollar(rest)

# The `expand_` loop of brace-expansion as explicit steps: each brace group
# either ends the expansion or continues with the text after it.
type Brace is Data:
  Expand{text: List<&2, U32>, top: Bool}
  Values{items: List<&2, List<&2, U32>>}
  Loop{text: List<&2, U32>, acc: List<&2, List<&2, U32>>, drop: Bool, first: Bool, top: Bool}
  Group{set: Maybe<&2, Balanced>, text: List<&2, U32>, acc: List<&2, List<&2, U32>>, drop: Bool, first: Bool, top: Bool}
  Options{parts: List<&2, List<&2, U32>>, pre: List<&2, U32>, post: List<&2, U32>, acc: List<&2, List<&2, U32>>, drop: Bool, top: Bool}
  Nested{parts: List<&2, List<&2, U32>>, pre: List<&2, U32>, post: List<&2, U32>, acc: List<&2, List<&2, U32>>, drop: Bool, top: Bool}
  Spread{parts: List<&2, List<&2, U32>>, pre: List<&2, U32>, post: List<&2, U32>, acc: List<&2, List<&2, U32>>, drop: Bool, top: Bool}
  Combine{values: List<&2, List<&2, U32>>, pre: List<&2, U32>, post: List<&2, U32>, acc: List<&2, List<&2, U32>>, drop: Bool, top: Bool}
  Continue{post: List<&2, U32>, acc: List<&2, List<&2, U32>>, drop: Bool, top: Bool}

def expandTask(fuel: Nat, task: Brace) -> List<&2, List<&2, U32>>:
  match fuel task:
    case 0n _: Nil{}
    case 1n+(+more) Expand{text, top}: expandTask(more, Loop{text, emptyOnly(), False{}, True{}, top})
    case 1n+_ Values{Nil{}}: Nil{}
    case 1n+(+more) Values{item <> rest}: concat(expandTask(more, Expand{item, False{}}), expandTask(more, Values{rest}))
    case 1n+(+more) Loop{+text, acc, drop, first, top}: expandTask(more, Group{balanced(text), text, acc, drop, first, top})
    case 1n+_ Group{None{}, text, acc, drop, _, _}: combine(acc, text, emptyOnly(), drop)
    case 1n+(+more) Group{Some{Balanced{+pre, +body, +post}}, _, +acc, +drop, +first, +top}:
      +sequence = isNumericSequence(body) || isAlphaSequence(body)
      +grouped = Bool.pick(Bool, first, top && Bool.not(sequence), drop)
      Bool.pick(Unit -> List<&2, List<&2, U32>>, endsWithDollar(pre),
        _ => expandTask(more, Continue{post, combine(acc, cat(pre, braced(body)), emptyOnly(), drop && isEmpty(post)), drop, top}),
        _ => Bool.pick(Unit -> List<&2, List<&2, U32>>, sequence || includesCode(body, 44),
          _ => Bool.pick(Unit -> List<&2, List<&2, U32>>, sequence,
            _ => expandTask(more, Combine{expandSequence(body, isAlphaSequence(body)), pre, post, acc, grouped, top}),
            _ => expandTask(more, Options{parseCommaParts(body), pre, post, acc, grouped, top}))(Unit{}),
          _ => Bool.pick(Unit -> List<&2, List<&2, U32>>, commaThenClose(post, 0),
            _ => expandTask(more, Loop{cat(pre, 123 <> cat(body, escClose() <> post)), acc, drop, first, True{}}),
            _ => combine(acc, cat(pre, cat(braced(body), post)), emptyOnly(), drop))(Unit{}))(Unit{}))(Unit{})
    case 1n+(+more) Options{part <> Nil{}, pre, post, acc, drop, top}: expandTask(more, Nested{embraceAll(expandTask(more, Expand{part, False{}}), Nil{}), pre, post, acc, drop, top})
    case 1n+(+more) Options{parts, pre, post, acc, drop, top}: expandTask(more, Spread{parts, pre, post, acc, drop, top})
    case 1n+(+more) Nested{part <> Nil{}, pre, +post, acc, +drop, top}: expandTask(more, Continue{post, combine(acc, cat(pre, part), emptyOnly(), drop && isEmpty(post)), drop, top})
    case 1n+(+more) Nested{parts, pre, post, acc, drop, top}: expandTask(more, Spread{parts, pre, post, acc, drop, top})
    case 1n+(+more) Spread{parts, +pre, +post, +acc, +drop, top}:
      expandTask(more, Combine{boundedValues(expandTask(more, Values{parts}), drop && isEmpty(post) && isEmpty(pre) && allEmpty(acc), 0n, 0n, Nil{}), pre, post, acc, drop, top})
    case 1n+(+more) Combine{values, pre, +post, acc, +drop, top}: expandTask(more, Continue{post, combine(acc, pre, values, drop && isEmpty(post)), drop, top})
    case 1n+_ Continue{Nil{}, acc, _, _}: acc
    case 1n+(+more) Continue{post, acc, drop, top}: expandTask(more, Loop{post, acc, drop, False{}, top})

# Bash preserves a leading `{}`: brace-expansion escapes it first.
def leadingEmptySet(text: List<&2, U32>) -> List<&2, U32>:
  match text:
    case 123 <> 125 <> rest: 92 <> 123 <> 92 <> 125 <> rest
    case other: other

# brace-expansion `expand(str)`.
def expandBraces(+text: List<&2, U32>) -> List<&2, List<&2, U32>>:
  Bool.pick(Unit -> List<&2, List<&2, U32>>, isEmpty(text),
    _ => Nil{},
    _ => unescapeAll(expandTask(deep(), Expand{escapeBracesGo(leadingEmptySet(text), Nil{}), True{}}), Nil{}))(Unit{})

# `/\{(?:(?!\{).)*\}/.test(pattern)`: a `{` later closed on the same line.
def hasBraceSet(text: List<&2, U32>, +open: Bool) -> Bool:
  match text:
    case Nil{}: False{}
    case +code <> rest:
      Bool.pick(Unit -> Bool, open && U32.is_eq(code, 125), _ => True{}, _ => hasBraceSet(rest, U32.is_eq(code, 123) || (open && Bool.not(isLineTerminator(code)))))(Unit{})

# minimatch `braceExpand` with default options.
def braceExpandUnits(+pattern: List<&2, U32>) -> List<&2, List<&2, U32>>:
  Bool.pick(Unit -> List<&2, List<&2, U32>>, hasBraceSet(pattern, False{}), _ => expandBraces(pattern), _ => pattern <> Nil{})(Unit{})

# ---------------------------------------------------------------------------
# Glob segment AST (ast.js)
# ---------------------------------------------------------------------------

# `Seq` is a type-less AST node (the root, an extglob alternative, or an
# unfinished extglob); `Ext` an extglob `!?+*@(...)`. Upstream mutates a tree
# with parent links; flattening moves alternatives between nodes and
# `fillNegs` appends to the alternative lists still owned by the original `!`
# nodes. `index` is an alternative's recorded parent index, `fills` how many
# `!` continuations detached owners will append to it, `origin` the type an
# extglob was parsed with and `events` the continuations its alternative list
# receives from detached owners.
type Ast is Data:
  Text{text: List<&2, U32>}
  Seq{parts: List<&2, Ast>, index: Nat, fills: Nat}
  Ext{kind: U32, alts: List<&2, Ast>, empty: Bool, origin: U32, events: Nat}

def isExtglobType(+code: U32) -> Bool:
  U32.is_eq(code, 33) || U32.is_eq(code, 63) || U32.is_eq(code, 43) || U32.is_eq(code, 42) || U32.is_eq(code, 64)

# `adoptionAnyMap`: extglobs a parent can absorb while parsing past maxDepth.
def canAdoptAny(+parent: U32, +child: U32) -> Bool:
  +optional = U32.is_eq(child, 63) || U32.is_eq(child, 64)
  +repeated = U32.is_eq(child, 42) || U32.is_eq(child, 43)
  Bool.pick(Bool, U32.is_eq(parent, 42) || U32.is_eq(parent, 43), optional || repeated, optional)

# `adoptionMap`.
def canAdoptKind(+parent: U32, +child: U32) -> Bool:
  Bool.pick(Bool, U32.is_eq(parent, 42), isExtglobType(child) && Bool.not(U32.is_eq(child, 33)),
    Bool.pick(Bool, U32.is_eq(parent, 43), U32.is_eq(child, 43) || U32.is_eq(child, 64),
      Bool.pick(Bool, U32.is_eq(parent, 63), U32.is_eq(child, 63) || U32.is_eq(child, 64), U32.is_eq(child, 64))))

# `adoptionWithSpaceMap`.
def canAdoptSpaced(+parent: U32, +child: U32) -> Bool:
  Bool.pick(Bool, U32.is_eq(parent, 43), U32.is_eq(child, 63) || U32.is_eq(child, 42),
    (U32.is_eq(parent, 33) || U32.is_eq(parent, 64)) && U32.is_eq(child, 63))

# `usurpMap`: the resulting type, or 0 when the child cannot take over.
def usurpKind(+parent: U32, +child: U32) -> U32:
  Bool.pick(U32, U32.is_eq(parent, 64), Bool.pick(U32, isExtglobType(child), child, 0),
    Bool.pick(U32, U32.is_eq(parent, 33), Bool.pick(U32, U32.is_eq(child, 33), 64, 0),
      Bool.pick(U32, U32.is_eq(parent, 63), Bool.pick(U32, U32.is_eq(child, 42) || U32.is_eq(child, 43), 42, 0),
        Bool.pick(U32, U32.is_eq(parent, 43), Bool.pick(U32, U32.is_eq(child, 42) || U32.is_eq(child, 63), 42, 0), 0))))

def isNegation(+kind: U32) -> Bool: U32.is_eq(kind, 33)

# Whether an extglob list is filled by its own owner: parsed as `!`, still `!`.
def ownFill(+origin: U32, +kind: U32) -> Nat: Bool.pick(Nat, isNegation(origin) && isNegation(kind), 1n, 0n)

def pushText(acc: List<&2, U32>, parts: List<&2, Ast>) -> List<&2, Ast>:
  match acc:
    case Nil{}: parts
    case acc: Text{List.reverse(&2, U32, acc)} <> parts

def alternative(acc: List<&2, U32>, part: List<&2, Ast>) -> Ast:
  Seq{List.reverse(&2, Ast, pushText(acc, part)), 0n, 0n}

# `#parseAST`. `since` counts units after an open `[` (upstream compares
# positions against `braceStart`); `depth` is the extglob depth.
type Scan is Data:
  RootScan{text: List<&2, U32>, acc: List<&2, U32>, parts: List<&2, Ast>, escaping: Bool, inBrace: Bool, since: Nat, braceNeg: Bool}
  ExtScan{kind: U32, origin: List<&2, U32>, depth: Nat, text: List<&2, U32>, acc: List<&2, U32>, part: List<&2, Ast>, alts: List<&2, Ast>, escaping: Bool, inBrace: Bool, since: Nat, braceNeg: Bool}

type Parsed is Data:
  Parsed{node: Ast, rest: List<&2, U32>}

def parsedNode(value: Parsed) -> Ast:
  match value:
    case Parsed{node, _}: node

def parsedRest(value: Parsed) -> List<&2, U32>:
  match value:
    case Parsed{_, rest}: rest

def braceNegAfter(+since: Nat, +code: U32, +braceNeg: Bool) -> Bool:
  braceNeg || (Nat.is_eq(since, 1n) && (U32.is_eq(code, 94) || U32.is_eq(code, 33)))

def braceOpenAfter(+since: Nat, +code: U32, +braceNeg: Bool) -> Bool:
  Nat.is_eq(since, 1n) || Bool.not(U32.is_eq(code, 93)) || (Nat.is_eq(since, 2n) && braceNeg)

def parseScan(fuel: Nat, scan: Scan) -> Parsed:
  match fuel scan:
    case 0n _: Parsed{Seq{Nil{}, 0n, 0n}, Nil{}}
    case 1n+_ RootScan{Nil{}, acc, parts, _, _, _, _}: Parsed{Seq{List.reverse(&2, Ast, pushText(acc, parts)), 0n, 0n}, Nil{}}
    case 1n+(+more) RootScan{+code <> +rest, +acc, +parts, +escaping, +inBrace, +since, +braceNeg}:
      +next = Bool.pick(Nat, inBrace, 1n + since, since)
      Bool.pick(Unit -> Parsed, escaping || U32.is_eq(code, 92),
        _ => parseScan(more, RootScan{rest, code <> acc, parts, Bool.not(escaping), inBrace, next, braceNeg}),
        _ => Bool.pick(Unit -> Parsed, inBrace,
          _ => parseScan(more, RootScan{rest, code <> acc, parts, False{}, braceOpenAfter(next, code, braceNeg), next, braceNegAfter(next, code, braceNeg)}),
          _ => Bool.pick(Unit -> Parsed, U32.is_eq(code, 91),
            _ => parseScan(more, RootScan{rest, code <> acc, parts, False{}, True{}, 0n, False{}}),
            _ => Bool.pick(Unit -> Parsed, isExtglobType(code) && startsWithCode(rest, 40),
              _ => (+child = parseScan(more, ExtScan{code, code <> rest, 1n, skip(rest, 1n), Nil{}, Nil{}, Nil{}, False{}, False{}, 0n, False{}})
                    parseScan(more, RootScan{parsedRest(child), Nil{}, parsedNode(child) <> pushText(acc, parts), False{}, False{}, 0n, False{}})),
              _ => parseScan(more, RootScan{rest, code <> acc, parts, False{}, False{}, since, braceNeg}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
    case 1n+_ ExtScan{_, origin, _, Nil{}, _, _, _, _, _, _, _}: Parsed{Seq{Text{origin} <> Nil{}, 0n, 0n}, Nil{}}
    case 1n+(+more) ExtScan{+kind, +origin, +depth, +code <> +rest, +acc, +part, +alts, +escaping, +inBrace, +since, +braceNeg}:
      +next = Bool.pick(Nat, inBrace, 1n + since, since)
      +adopts = canAdoptAny(kind, code)
      Bool.pick(Unit -> Parsed, escaping || U32.is_eq(code, 92),
        _ => parseScan(more, ExtScan{kind, origin, depth, rest, code <> acc, part, alts, Bool.not(escaping), inBrace, next, braceNeg}),
        _ => Bool.pick(Unit -> Parsed, inBrace,
          _ => parseScan(more, ExtScan{kind, origin, depth, rest, code <> acc, part, alts, False{}, braceOpenAfter(next, code, braceNeg), next, braceNegAfter(next, code, braceNeg)}),
          _ => Bool.pick(Unit -> Parsed, U32.is_eq(code, 91),
            _ => parseScan(more, ExtScan{kind, origin, depth, rest, code <> acc, part, alts, False{}, True{}, 0n, False{}}),
            _ => Bool.pick(Unit -> Parsed, isExtglobType(code) && startsWithCode(rest, 40) && (Nat.is_le(depth, 2n) || adopts),
              _ => (+child = parseScan(more, ExtScan{code, code <> rest, depth + Bool.pick(Nat, adopts, 0n, 1n), skip(rest, 1n), Nil{}, Nil{}, Nil{}, False{}, False{}, 0n, False{}})
                    parseScan(more, ExtScan{kind, origin, depth, parsedRest(child), Nil{}, parsedNode(child) <> pushText(acc, part), alts, False{}, False{}, 0n, False{}})),
              _ => Bool.pick(Unit -> Parsed, U32.is_eq(code, 124),
                _ => parseScan(more, ExtScan{kind, origin, depth, rest, Nil{}, Nil{}, alternative(acc, part) <> alts, False{}, False{}, since, braceNeg}),
                _ => Bool.pick(Unit -> Parsed, U32.is_eq(code, 41),
                  _ => Parsed{Ext{kind, List.reverse(&2, Ast, alternative(acc, part) <> alts), isEmpty(acc), kind, 0n}, rest},
                  _ => parseScan(more, ExtScan{kind, origin, depth, rest, code <> acc, part, alts, False{}, False{}, since, braceNeg}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})

# `AST.fromGlob`.
def fromGlob(+pattern: List<&2, U32>) -> Ast:
  parsedNode(parseScan(deep(), RootScan{pattern, Nil{}, Nil{}, False{}, False{}, 0n, False{}}))

def addFills(alts: List<&2, Ast>, +count: Nat, reversed: List<&2, Ast>) -> List<&2, Ast>:
  match alts:
    case Nil{}: List.reverse(&2, Ast, reversed)
    case Seq{parts, index, fills} <> rest: addFills(rest, count, Seq{parts, index, fills + count} <> reversed)
    case other <> rest: addFills(rest, count, other <> reversed)

def astTail(items: List<&2, Ast>) -> List<&2, Ast>:
  match items:
    case Nil{}: Nil{}
    case _ <> rest: rest

def astHead(items: List<&2, Ast>) -> List<&2, Ast>:
  match items:
    case Nil{}: Nil{}
    case item <> _: item <> Nil{}

def astSize(items: List<&2, Ast>) -> Nat: lengthOf(Ast, items)

def prependAsts(reversed: List<&2, Ast>, items: List<&2, Ast>) -> List<&2, Ast>:
  match reversed:
    case Nil{}: items
    case item <> rest: prependAsts(rest, item <> items)

def catAsts(left: List<&2, Ast>, right: List<&2, Ast>) -> List<&2, Ast>: prependAsts(List.reverse(&2, Ast, left), right)

# `#flatten`: extglobs absorb (`#adopt`, `#adoptWithSpace`) or are replaced by
# (`#usurp`) a sole nested extglob, in up to ten passes over the alternatives.
# A pass continues after the alternatives an adoption inserted, like the
# upstream index loop does; `done` holds visited alternatives in reverse.
type Flat is Data:
  Parts{items: List<&2, Ast>, done: List<&2, Ast>}
  Pass{kind: U32, empty: Bool, origin: U32, events: Nat, done: List<&2, Ast>, todo: List<&2, Ast>, clean: Bool, passes: Nat}
  Check{kind: U32, empty: Bool, origin: U32, events: Nat, done: List<&2, Ast>, alt: Ast, todo: List<&2, Ast>, passes: Nat, clean: Bool}

def flatten(fuel: Nat, task: Flat) -> List<&2, Ast>:
  match fuel task:
    case 0n _: Nil{}
    case 1n+_ Parts{Nil{}, done}: List.reverse(&2, Ast, done)
    case 1n+(+more) Parts{Ext{kind, alts, empty, origin, events} <> rest, done}:
      flatten(more, Parts{rest, onto(Ast, flatten(more, Pass{kind, empty, origin, events, Nil{}, alts, True{}, 0n}), done)})
    case 1n+(+more) Parts{item <> rest, done}: flatten(more, Parts{rest, item <> done})
    case 1n+(+more) Pass{+kind, +empty, +origin, +events, done, Nil{}, clean, +passes}:
      +alts = List.reverse(&2, Ast, done)
      Bool.pick(Unit -> List<&2, Ast>, Bool.not(clean) && Nat.is_lt(1n + passes, 10n),
        _ => flatten(more, Pass{kind, empty, origin, events, Nil{}, alts, True{}, 1n + passes}),
        _ => Ext{kind, alts, empty, origin, events} <> Nil{})(Unit{})
    case 1n+(+more) Pass{kind, empty, origin, events, done, Seq{parts, index, fills} <> todo, clean, passes}:
      flatten(more, Check{kind, empty, origin, events, done, Seq{flatten(more, Parts{parts, Nil{}}), index, fills}, todo, passes, clean})
    case 1n+(+more) Pass{kind, empty, origin, events, done, alt <> todo, clean, passes}:
      flatten(more, Pass{kind, empty, origin, events, alt <> done, todo, clean, passes})
    case 1n+(+more) Check{+kind, +empty, +origin, +events, +done, Seq{Ext{+childKind, +childAlts, +childEmpty, +childOrigin, +childEvents} <> Nil{}, +index, +fills}, +todo, +passes, +clean}:
      +moved = childEvents + ownFill(childOrigin, childKind)
      Bool.pick(Unit -> List<&2, Ast>, canAdoptKind(kind, childKind),
        _ => (+adopted = addFills(childAlts, moved, Nil{})
              flatten(more, Pass{kind, empty, origin, events, catAsts(astHead(adopted), done), catAsts(astTail(adopted), todo), False{}, passes})),
        _ => Bool.pick(Unit -> List<&2, Ast>, canAdoptSpaced(kind, childKind),
          _ => (+adopted = addFills(catAsts(childAlts, Seq{Text{Nil{}} <> Nil{}, astSize(childAlts), 0n} <> Nil{}), moved, Nil{})
                flatten(more, Pass{kind, empty, origin, events, catAsts(astHead(adopted), done), catAsts(astTail(adopted), todo), False{}, passes})),
          _ => Bool.pick(Unit -> List<&2, Ast>, Bool.not(U32.is_eq(usurpKind(kind, childKind), 0)) && List.is_empty(&2, Ast, done) && List.is_empty(&2, Ast, todo),
            _ => flatten(more, Pass{usurpKind(kind, childKind), False{}, origin, moved, astHead(childAlts), astTail(childAlts), False{}, passes}),
            _ => flatten(more, Pass{kind, empty, origin, events, Seq{Ext{childKind, childAlts, childEmpty, childOrigin, childEvents} <> Nil{}, index, fills} <> done, todo, clean, passes}))(Unit{}))(Unit{}))(Unit{})
    case 1n+(+more) Check{kind, empty, origin, events, done, alt, todo, passes, clean}:
      flatten(more, Pass{kind, empty, origin, events, alt <> done, todo, clean, passes})

# `clone`: copies of continuation parts. Empty strings are not re-pushed, and
# every copied node records the index it was pushed at.
def cloneAsts(fuel: Nat, items: List<&2, Ast>, +position: Nat, reversed: List<&2, Ast>) -> List<&2, Ast>:
  match fuel items:
    case 0n _: List.reverse(&2, Ast, reversed)
    case 1n+_ Nil{}: List.reverse(&2, Ast, reversed)
    case 1n+(+more) Text{Nil{}} <> rest: cloneAsts(more, rest, position, reversed)
    case 1n+(+more) Text{text} <> rest: cloneAsts(more, rest, 1n + position, Text{text} <> reversed)
    case 1n+(+more) Seq{parts, _, _} <> rest: cloneAsts(more, rest, 1n + position, Seq{cloneAsts(more, parts, 0n, Nil{}), position, 0n} <> reversed)
    case 1n+(+more) Ext{+kind, alts, _, _, _} <> rest: cloneAsts(more, rest, 1n + position, Ext{kind, cloneAsts(more, alts, 0n, Nil{}), False{}, kind, 0n} <> reversed)

def repeated(+items: List<&2, Ast>, count: Nat) -> List<&2, Ast>:
  match count:
    case 0n: Nil{}
    case 1n+more: catAsts(items, repeated(items, more))

# `#fillNegs`: every `!` alternative list receives copies of what follows the
# extglob, up to the root. Later nodes are filled first, so parts are taken
# right to left (`items` is reversed) and each continuation is already filled.
# `copies` is a clone of the continuation, appended as often as the list's
# owners (`events`) and earlier detached owners (`fills`) require.
type Fill is Data:
  FillParts{items: List<&2, Ast>, cont: List<&2, Ast>, done: List<&2, Ast>}
  FillAlts{alts: List<&2, Ast>, cont: List<&2, Ast>, copies: List<&2, Ast>, events: Nat, done: List<&2, Ast>}

def fill(fuel: Nat, task: Fill) -> List<&2, Ast>:
  match fuel task:
    case 0n _: Nil{}
    case 1n+_ FillParts{Nil{}, _, done}: done
    case 1n+(+more) FillParts{Ext{+kind, alts, empty, +origin, +events} <> rest, +cont, +done}:
      +after = catAsts(done, cont)
      fill(more, FillParts{rest, cont, Ext{kind, fill(more, FillAlts{alts, after, cloneAsts(deep(), after, 0n, Nil{}), events + ownFill(origin, kind), Nil{}}), empty, origin, events} <> done})
    case 1n+(+more) FillParts{item <> rest, cont, done}: fill(more, FillParts{rest, cont, item <> done})
    case 1n+_ FillAlts{Nil{}, _, _, _, done}: List.reverse(&2, Ast, done)
    case 1n+(+more) FillAlts{Seq{parts, index, +fills} <> rest, +cont, +copies, +events, done}:
      fill(more, FillAlts{rest, cont, copies, events, Seq{catAsts(fill(more, FillParts{List.reverse(&2, Ast, parts), cont, Nil{}}), repeated(copies, fills + events)), index, fills} <> done})
    case 1n+(+more) FillAlts{item <> rest, cont, copies, events, done}: fill(more, FillAlts{rest, cont, copies, events, item <> done})

# ---------------------------------------------------------------------------
# Regular-expression sources (brace-expressions.js, ast.js, unescape.js)
# ---------------------------------------------------------------------------

def prependUnits(chunk: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match chunk:
    case Nil{}: reversed
    case code <> rest: prependUnits(rest, code <> reversed)

def isJsSpace(+code: U32) -> Bool:
  U32.is_eq(code, 9) || U32.is_eq(code, 10) || U32.is_eq(code, 11) || U32.is_eq(code, 12) || U32.is_eq(code, 13) || U32.is_eq(code, 32) || U32.is_eq(code, 160) || U32.is_eq(code, 5760) || (U32.is_ge(code, 8192) && U32.is_le(code, 8202)) || U32.is_eq(code, 8232) || U32.is_eq(code, 8233) || U32.is_eq(code, 8239) || U32.is_eq(code, 8287) || U32.is_eq(code, 12288) || U32.is_eq(code, 65279)

# `regExpEscape` of one unit: `[-[\]{}()*+?.,\\^$|#\s]` gain a backslash.
def escapeNeeded(+code: U32) -> Bool:
  U32.is_eq(code, 45) || U32.is_eq(code, 91) || U32.is_eq(code, 93) || U32.is_eq(code, 123) || U32.is_eq(code, 125) || U32.is_eq(code, 40) || U32.is_eq(code, 41) || U32.is_eq(code, 42) || U32.is_eq(code, 43) || U32.is_eq(code, 63) || U32.is_eq(code, 46) || U32.is_eq(code, 44) || U32.is_eq(code, 92) || U32.is_eq(code, 94) || U32.is_eq(code, 36) || U32.is_eq(code, 124) || U32.is_eq(code, 35) || isJsSpace(code)

def regExpEscape(+code: U32) -> List<&2, U32>: Bool.pick(List<&2, U32>, escapeNeeded(code), 92 <> code <> Nil{}, code <> Nil{})

# `braceEscape` of one unit: `[ ] \ -` gain a backslash inside a class.
def braceEscape(+code: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(code, 91) || U32.is_eq(code, 93) || U32.is_eq(code, 92) || U32.is_eq(code, 45), 92 <> code <> Nil{}, code <> Nil{})

# `reSpecials`: escaped glob characters that stay escaped in the expression.
def reSpecial(+code: U32) -> Bool:
  U32.is_eq(code, 40) || U32.is_eq(code, 41) || U32.is_eq(code, 46) || U32.is_eq(code, 42) || U32.is_eq(code, 123) || U32.is_eq(code, 125) || U32.is_eq(code, 43) || U32.is_eq(code, 63) || U32.is_eq(code, 91) || U32.is_eq(code, 93) || U32.is_eq(code, 94) || U32.is_eq(code, 36) || U32.is_eq(code, 92) || U32.is_eq(code, 33)

type Posix is Data:
  Posix{name: List<&2, U32>, source: List<&2, U32>, unicode: Bool, negated: Bool}

# `posixClasses`, in upstream's lookup order.
def posixClasses() -> List<&2, Posix>:
  Posix{units("[:alnum:]"), units("\\p{L}\\p{Nl}\\p{Nd}"), True{}, False{}} <>
  Posix{units("[:alpha:]"), units("\\p{L}\\p{Nl}"), True{}, False{}} <>
  Posix{units("[:ascii:]"), units("\\x00-\\x7f"), False{}, False{}} <>
  Posix{units("[:blank:]"), units("\\p{Zs}\\t"), True{}, False{}} <>
  Posix{units("[:cntrl:]"), units("\\p{Cc}"), True{}, False{}} <>
  Posix{units("[:digit:]"), units("\\p{Nd}"), True{}, False{}} <>
  Posix{units("[:graph:]"), units("\\p{Z}\\p{C}"), True{}, True{}} <>
  Posix{units("[:lower:]"), units("\\p{Ll}"), True{}, False{}} <>
  Posix{units("[:print:]"), units("\\p{C}"), True{}, False{}} <>
  Posix{units("[:punct:]"), units("\\p{P}"), True{}, False{}} <>
  Posix{units("[:space:]"), units("\\p{Z}\\t\\r\\n\\v\\f"), True{}, False{}} <>
  Posix{units("[:upper:]"), units("\\p{Lu}"), True{}, False{}} <>
  Posix{units("[:word:]"), units("\\p{L}\\p{Nl}\\p{Nd}\\p{Pc}"), True{}, False{}} <>
  Posix{units("[:xdigit:]"), units("A-Fa-f0-9"), False{}, False{}} <> Nil{}

def posixAt(classes: List<&2, Posix>, +text: List<&2, U32>) -> Maybe<&2, Posix>:
  match classes:
    case Nil{}: None{}
    case Posix{+name, source, unicode, negated} <> rest:
      Bool.pick(Unit -> Maybe<&2, Posix>, startsWith(text, name), _ => Some{Posix{name, source, unicode, negated}}, _ => posixAt(rest, text))(Unit{})

type ClassResult is Data:
  ClassResult{source: List<&2, U32>, uflag: Bool, consumed: Nat, magic: Bool}

def joinReversed(values: List<&2, List<&2, U32>>, reversed: List<&2, U32>) -> List<&2, U32>:
  match values:
    case Nil{}: reversed
    case value <> rest: joinReversed(rest, prependUnits(value, reversed))

def joinUnits(values: List<&2, List<&2, U32>>) -> List<&2, U32>:
  List.reverse(&2, U32, joinReversed(values, Nil{}))

# `/^\\?.$/`: a single, possibly escaped, non-line-terminator unit.
def singleUnit(value: List<&2, U32>) -> Maybe<&2, U32>:
  match value:
    case +code <> Nil{}: Bool.pick(Maybe<&2, U32>, isLineTerminator(code), None{}, Some{code})
    case _: None{}

def singleMember(value: List<&2, U32>) -> Maybe<&2, U32>:
  match value:
    case Nil{}: None{}
    case +first <> +rest: Bool.pick(Maybe<&2, U32>, U32.is_eq(first, 92) && Bool.not(List.is_empty(&2, U32, rest)), singleUnit(rest), singleUnit(first <> rest))

def hasUnit(value: Maybe<&2, U32>) -> Bool:
  match value:
    case Some{_}: True{}
    case None{}: False{}

def unitOr(value: Maybe<&2, U32>, fallback: U32) -> U32:
  match value:
    case Some{code}: code
    case None{}: fallback

def hasPosix(value: Maybe<&2, Posix>) -> Bool:
  match value:
    case Some{_}: True{}
    case None{}: False{}

def posixName(value: Posix) -> List<&2, U32>:
  match value:
    case Posix{name, _, _, _}: name

def posixSource(value: Posix) -> List<&2, U32>:
  match value:
    case Posix{_, source, _, _}: source

def posixUnicode(value: Posix) -> Bool:
  match value:
    case Posix{_, _, unicode, _}: unicode

def posixNegated(value: Posix) -> Bool:
  match value:
    case Posix{_, _, _, negated}: negated

def prependLists(values: List<&2, List<&2, U32>>, reversed: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match values:
    case Nil{}: reversed
    case value <> rest: prependLists(rest, value <> reversed)

def classBracket(caret: Bool, members: List<&2, List<&2, U32>>) -> List<&2, U32>:
  91 <> cat(Bool.pick(List<&2, U32>, caret, 94 <> Nil{}, Nil{}), cat(joinUnits(members), 93 <> Nil{}))

def classSource(+ranges: List<&2, List<&2, U32>>, +negs: List<&2, List<&2, U32>>, +negate: Bool) -> List<&2, U32>:
  +positive = classBracket(negate, ranges)
  +negative = classBracket(Bool.not(negate), negs)
  Bool.pick(List<&2, U32>, List.is_empty(&2, List<&2, U32>, negs), positive,
    Bool.pick(List<&2, U32>, List.is_empty(&2, List<&2, U32>, ranges), negative, 40 <> cat(positive, 124 <> cat(negative, 41 <> Nil{}))))

def literalMember(value: Maybe<&2, U32>, +ranges: List<&2, List<&2, U32>>, +negs: List<&2, List<&2, U32>>, +negate: Bool, +end: Nat) -> ClassResult:
  match value:
    case Some{code}: ClassResult{regExpEscape(code), False{}, end, False{}}
    case None{}: ClassResult{classSource(ranges, negs, negate), False{}, end, True{}}

def classDone(+ranges: List<&2, List<&2, U32>>, +negs: List<&2, List<&2, U32>>, +negate: Bool, +uflag: Bool, +end: Nat, +total: Nat) -> ClassResult:
  +single = List.is_empty(&2, List<&2, U32>, negs) && Nat.is_eq(lengthOf(List<&2, U32>, ranges), 1n) && Bool.not(negate)
  Bool.pick(Unit -> ClassResult, List.is_empty(&2, List<&2, U32>, ranges) && List.is_empty(&2, List<&2, U32>, negs),
    _ => ClassResult{units("$."), False{}, total, True{}},
    _ => Bool.pick(Unit -> ClassResult, single && hasUnit(singleMember(joinUnits(ranges))),
      _ => literalMember(singleMember(joinUnits(ranges)), ranges, negs, negate, end),
      _ => ClassResult{classSource(ranges, negs, negate), uflag, end, True{}})(Unit{}))(Unit{})


def rangeMember(+start: U32, +code: U32) -> List<&2, List<&2, U32>>:
  Bool.pick(List<&2, List<&2, U32>>, U32.is_gt(code, start), cat(braceEscape(start), 45 <> braceEscape(code)) <> Nil{},
    Bool.pick(List<&2, List<&2, U32>>, U32.is_eq(code, start), braceEscape(code) <> Nil{}, Nil{}))

def posixMember(value: Maybe<&2, Posix>) -> Posix:
  match value:
    case Some{posix}: posix
    case None{}: Posix{Nil{}, Nil{}, False{}, False{}}

# `parseClass(glob, position)` on the glob from its `[`. `index` counts from
# that `[`; ranges and negated classes accumulate in reverse.
def classScan(fuel: Nat, text: List<&2, U32>, +index: Nat, +total: Nat, +ranges: List<&2, List<&2, U32>>, +negs: List<&2, List<&2, U32>>, +sawStart: Bool, +uflag: Bool, +escaping: Bool, +negate: Bool, +start: Maybe<&2, U32>) -> ClassResult:
  match fuel text:
    case 0n _: ClassResult{Nil{}, False{}, 0n, False{}}
    case 1n+_ Nil{}: ClassResult{Nil{}, False{}, 0n, False{}}
    case 1n+(+more) +code <> +rest:
      +posix = posixAt(posixClasses(), code <> rest)
      Bool.pick(Unit -> ClassResult, (U32.is_eq(code, 33) || U32.is_eq(code, 94)) && Nat.is_eq(index, 1n),
        _ => classScan(more, rest, 1n + index, total, ranges, negs, sawStart, uflag, escaping, True{}, start),
        _ => Bool.pick(Unit -> ClassResult, U32.is_eq(code, 93) && sawStart && Bool.not(escaping),
          _ => classDone(List.reverse(&2, List<&2, U32>, ranges), List.reverse(&2, List<&2, U32>, negs), negate, uflag, 1n + index, total),
          _ => Bool.pick(Unit -> ClassResult, U32.is_eq(code, 92) && Bool.not(escaping),
            _ => classScan(more, rest, 1n + index, total, ranges, negs, True{}, uflag, True{}, negate, start),
            _ => Bool.pick(Unit -> ClassResult, U32.is_eq(code, 91) && Bool.not(escaping) && hasPosix(posix),
              _ => Bool.pick(Unit -> ClassResult, hasUnit(start),
                _ => ClassResult{units("$."), False{}, total, True{}},
                _ => (+found = posixMember(posix)
                      classScan(more, skip(code <> rest, size(posixName(found))), index + size(posixName(found)), total,
                        Bool.pick(List<&2, List<&2, U32>>, posixNegated(found), ranges, posixSource(found) <> ranges),
                        Bool.pick(List<&2, List<&2, U32>>, posixNegated(found), posixSource(found) <> negs, negs),
                        True{}, uflag || posixUnicode(found), False{}, negate, start)))(Unit{}),
              _ => Bool.pick(Unit -> ClassResult, hasUnit(start),
                _ => classScan(more, rest, 1n + index, total, prependLists(rangeMember(unitOr(start, 0), code), ranges), negs, True{}, uflag, False{}, negate, None{}),
                _ => Bool.pick(Unit -> ClassResult, startsWith(rest, 45 <> 93 <> Nil{}),
                  _ => classScan(more, skip(rest, 1n), 2n + index, total, cat(braceEscape(code), braceEscape(45)) <> ranges, negs, True{}, uflag, False{}, negate, None{}),
                  _ => Bool.pick(Unit -> ClassResult, startsWithCode(rest, 45),
                    _ => classScan(more, skip(rest, 1n), 2n + index, total, ranges, negs, True{}, uflag, False{}, negate, Some{code}),
                    _ => classScan(more, rest, 1n + index, total, braceEscape(code) <> ranges, negs, True{}, uflag, False{}, negate, None{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})

def classSourceOf(value: ClassResult) -> List<&2, U32>:
  match value:
    case ClassResult{source, _, _, _}: source

def classUflag(value: ClassResult) -> Bool:
  match value:
    case ClassResult{_, uflag, _, _}: uflag

def classConsumed(value: ClassResult) -> Nat:
  match value:
    case ClassResult{_, _, consumed, _}: consumed

def classMagic(value: ClassResult) -> Bool:
  match value:
    case ClassResult{_, _, _, magic}: magic

def parseClass(+text: List<&2, U32>) -> ClassResult:
  classScan(deep(), skip(text, 1n), 1n, size(text), Nil{}, Nil{}, False{}, False{}, False{}, False{}, None{})

type Glob is Data:
  Glob{source: List<&2, U32>, magic: Bool, uflag: Bool}

def allStars(text: List<&2, U32>) -> Bool:
  match text:
    case Nil{}: True{}
    case 42 <> rest: allStars(rest)
    case _: False{}

def starSource(noEmpty: Bool) -> List<&2, U32>: Bool.pick(List<&2, U32>, noEmpty, units("[^/]+?"), units("[^/]*?"))

# `#parseGlob`: one string part of a type-less node; `reversed` is the source.
def globScan(fuel: Nat, text: List<&2, U32>, +noEmpty: Bool, +reversed: List<&2, U32>, +magic: Bool, +uflag: Bool, +escaping: Bool, +inStar: Bool) -> Glob:
  match fuel text:
    case 0n _: Glob{List.reverse(&2, U32, reversed), magic, uflag}
    case 1n+_ Nil{}: Glob{List.reverse(&2, U32, reversed), magic, uflag}
    case 1n+(+more) +code <> +rest:
      Bool.pick(Unit -> Glob, escaping,
        _ => globScan(more, rest, noEmpty, code <> prependUnits(Bool.pick(List<&2, U32>, reSpecial(code), 92 <> Nil{}, Nil{}), reversed), magic, uflag, False{}, inStar),
        _ => Bool.pick(Unit -> Glob, U32.is_eq(code, 42),
          _ => Bool.pick(Unit -> Glob, inStar,
            _ => globScan(more, rest, noEmpty, reversed, magic, uflag, False{}, True{}),
            _ => globScan(more, rest, noEmpty, prependUnits(starSource(noEmpty), reversed), True{}, uflag, False{}, True{}))(Unit{}),
          _ => Bool.pick(Unit -> Glob, U32.is_eq(code, 92),
            _ => Bool.pick(Unit -> Glob, isEmpty(rest),
              _ => Glob{List.reverse(&2, U32, 92 <> 92 <> reversed), magic, uflag},
              _ => globScan(more, rest, noEmpty, reversed, magic, uflag, True{}, False{}))(Unit{}),
            _ => (+found = Bool.pick(Unit -> ClassResult, U32.is_eq(code, 91), _ => parseClass(code <> rest), _ => ClassResult{Nil{}, False{}, 0n, False{}})(Unit{})
                  Bool.pick(Unit -> Glob, Nat.is_gt(classConsumed(found), 0n),
                    _ => globScan(more, skip(rest, Nat.sub(classConsumed(found), 1n)), noEmpty, prependUnits(classSourceOf(found), reversed), magic || classMagic(found), uflag || classUflag(found), False{}, False{}),
                    _ => Bool.pick(Unit -> Glob, U32.is_eq(code, 63),
                      _ => globScan(more, rest, noEmpty, prependUnits(units("[^/]"), reversed), True{}, uflag, False{}, False{}),
                      _ => globScan(more, rest, noEmpty, prependUnits(regExpEscape(code), reversed), magic, uflag, False{}, False{}))(Unit{}))(Unit{})))(Unit{}))(Unit{}))(Unit{})

def parseGlob(+text: List<&2, U32>, noEmpty: Bool) -> Glob:
  globScan(deep(), text, noEmpty && allStars(text), Nil{}, False{}, False{}, False{}, False{})

def bracketOperand(+code: U32) -> Bool: Bool.not(U32.is_eq(code, 47) || U32.is_eq(code, 92))

def bracketedAt(text: List<&2, U32>) -> Bool:
  match text:
    case 91 <> +code <> 93 <> _: bracketOperand(code)
    case _: False{}

# `unescape` step one: `s.replace(/((?!\\).|^)\[([^/\\])\]/g, '$1$2')`.
def unescapeBrackets(fuel: Nat, text: List<&2, U32>, +start: Bool, +reversed: List<&2, U32>) -> List<&2, U32>:
  match fuel text:
    case 0n _: List.reverse(&2, U32, reversed)
    case 1n+_ Nil{}: List.reverse(&2, U32, reversed)
    case 1n+(+more) +first <> +rest:
      Bool.pick(Unit -> List<&2, U32>, Bool.not(U32.is_eq(first, 92)) && Bool.not(isLineTerminator(first)) && bracketedAt(rest),
        _ => unescapeBrackets(more, skip(rest, 3n), False{}, unitOr(List.head(&2, U32, skip(rest, 1n)), 0) <> first <> reversed),
        _ => Bool.pick(Unit -> List<&2, U32>, start && bracketedAt(first <> rest),
          _ => unescapeBrackets(more, skip(rest, 2n), False{}, unitOr(List.head(&2, U32, rest), 0) <> reversed),
          _ => unescapeBrackets(more, rest, False{}, first <> reversed))(Unit{}))(Unit{})

# `unescape` step two: `s.replace(/\\([^/])/g, '$1')`.
def unescapeSlashes(text: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match text:
    case Nil{}: List.reverse(&2, U32, reversed)
    case 92 <> Nil{}: List.reverse(&2, U32, 92 <> reversed)
    case 92 <> 47 <> rest: unescapeSlashes(rest, 47 <> 92 <> reversed)
    case 92 <> code <> rest: unescapeSlashes(rest, code <> reversed)
    case code <> rest: unescapeSlashes(rest, code <> reversed)

# `unescape` with default options.
def unescape(+text: List<&2, U32>) -> List<&2, U32>: unescapeSlashes(unescapeBrackets(deep(), text, True{}, Nil{}), Nil{})

# `toRegExpSource` results: the source, whether a type-less node has magic, the
# `u` flag, the (possibly rewritten) nodes, and how many alternatives joined.
type Out is Data:
  Out{source: List<&2, U32>, magic: Bool, uflag: Bool, items: List<&2, Ast>, count: Nat}

def outSource(value: Out) -> List<&2, U32>:
  match value:
    case Out{source, _, _, _, _}: source

def noOut() -> Out: Out{Nil{}, False{}, False{}, Nil{}, 0n}

# Parts and alternatives accumulate in reverse (source and nodes) and are
# put in order once complete.
def finished(acc: Out) -> Out:
  match acc:
    case Out{source, magic, uflag, items, count}: Out{List.reverse(&2, U32, source), magic, uflag, List.reverse(&2, Ast, items), count}

def accumulate(acc: Out, element: Out) -> Out:
  match acc element:
    case Out{source, magicA, uflagA, items, countA} Out{text, magicB, uflagB, nodes, countB}:
      Out{prependUnits(text, source), magicA || magicB, uflagA || uflagB, onto(Ast, nodes, items), countA + countB}

# `#partsToRegExp` joins alternatives with `|`, dropping empty ones when the
# extglob is the whole path portion.
def accumulateAlt(acc: Out, element: Out, filter: Bool) -> Out:
  match acc element:
    case Out{+source, magic, uflagA, items, +count} Out{+text, _, uflagB, nodes, _}:
      +keep = Bool.not(filter) || Bool.not(isEmpty(text))
      +joined = Bool.pick(List<&2, U32>, Nat.is_gt(count, 0n), prependUnits(text, 124 <> source), prependUnits(text, source))
      Out{Bool.pick(List<&2, U32>, keep, joined, source), magic, uflagA || uflagB, onto(Ast, nodes, items), count + Bool.pick(Nat, keep, 1n, 0n)}

def allText(items: List<&2, Ast>) -> Bool:
  match items:
    case Nil{}: True{}
    case Text{_} <> rest: allText(rest)
    case _: False{}

# `addPatternStart`: a source starting here might match a leading dot.
def patternStart(+code: U32) -> Bool: U32.is_eq(code, 91) || U32.is_eq(code, 46)
def startsAt(text: List<&2, U32>, index: Nat) -> Bool: patternStart(unitOr(List.head(&2, U32, skip(text, index)), 0))

def justDots(items: List<&2, Ast>) -> Bool:
  match items:
    case Text{46 <> Nil{}} <> Nil{}: True{}
    case Text{46 <> 46 <> Nil{}} <> Nil{}: True{}
    case _: False{}

def firstIsText(items: List<&2, Ast>) -> Bool:
  match items:
    case Text{_} <> _: True{}
    case _: False{}

# The dot and traversal protection a type-less node puts before its source.
def startGuard(+items: List<&2, Ast>, +source: List<&2, U32>, +start: Bool, +dot: Bool) -> List<&2, U32>:
  +noTraversal = (dot && startsAt(source, 0n)) || (startsWith(source, units("\\.")) && startsAt(source, 2n)) || (startsWith(source, units("\\.\\.")) && startsAt(source, 4n))
  Bool.pick(Unit -> List<&2, U32>, start && firstIsText(items) && Bool.not(justDots(items)),
    _ => Bool.pick(List<&2, U32>, noTraversal, units("(?!(?:^|/)\\.\\.?(?:$|/))"), Bool.pick(List<&2, U32>, Bool.not(dot) && startsAt(source, 0n), units("(?!\\.)"), Nil{})),
    _ => Nil{})(Unit{})

# `toRegExpSource` of a type-less node from its parts' output.
def wrapSeq(parts: Out, index: Nat, fills: Nat, start: Bool, end: Bool, neg: Bool, dot: Bool) -> Out:
  match parts:
    case Out{+source, magic, uflag, +items, _}:
      Out{cat(startGuard(items, source, start, dot), cat(source, Bool.pick(List<&2, U32>, end && neg, units("(?:$|\\/)"), Nil{}))), magic, uflag, Seq{items, index, fills} <> Nil{}, 1n}

def extClose(+kind: U32, +dotBody: Bool, +start: Bool, +dot: Bool) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, isNegation(kind), cat(units("))"), cat(Bool.pick(List<&2, U32>, start && Bool.not(dot), units("(?!\\.)"), Nil{}), units("[^/]*?)"))),
    Bool.pick(List<&2, U32>, U32.is_eq(kind, 64), units(")"),
      Bool.pick(List<&2, U32>, U32.is_eq(kind, 63), units(")?"),
        Bool.pick(List<&2, U32>, U32.is_eq(kind, 43) && dotBody, units(")"),
          Bool.pick(List<&2, U32>, U32.is_eq(kind, 42) && dotBody, units(")?"), 41 <> kind <> Nil{})))))

# The extglob part of `toRegExpSource`, given both alternative bodies.
def extSource(+kind: U32, empty: Bool, +start: Bool, +dot: Bool, +body: List<&2, U32>, +dotAllowed: List<&2, U32>) -> List<&2, U32>:
  +second = Bool.pick(List<&2, U32>, same(dotAllowed, body), Nil{}, dotAllowed)
  +joined = Bool.pick(List<&2, U32>, isEmpty(second), body, cat(units("(?:"), cat(body, cat(units(")(?:"), cat(second, units(")*?"))))))
  Bool.pick(List<&2, U32>, isNegation(kind) && empty,
    cat(Bool.pick(List<&2, U32>, start && Bool.not(dot), units("(?!\\.)"), Nil{}), units("[^/]+?")),
    cat(Bool.pick(List<&2, U32>, isNegation(kind), units("(?:(?!(?:"), units("(?:")), cat(joined, extClose(kind, Bool.not(isEmpty(second)), start, dot))))

# `toString` of an extglob whose alternatives are all empty.
def emptyExtText(+kind: U32, count: Nat) -> List<&2, U32>:
  kind <> 40 <> cat(repeatUnit(124, Nat.sub(count, 1n)), 41 <> Nil{})

def extOut(+kind: U32, +empty: Bool, +origin: U32, +events: Nat, +start: Bool, +dot: Bool, body: Out, dotAllowed: Out) -> Out:
  match body dotAllowed:
    case Out{+first, _, uflagA, _, _} Out{second, _, uflagB, items, _}:
      Out{extSource(kind, empty, start, dot, first, second), True{}, uflagA || uflagB, Ext{kind, items, empty, origin, events} <> Nil{}, 1n}

def globOut(glob: Glob, text: List<&2, U32>) -> Out:
  match glob:
    case Glob{source, magic, uflag}: Out{source, magic, uflag, Text{text} <> Nil{}, 1n}

type Gen is Data:
  GenParts{items: List<&2, Ast>, start: Bool, end: Bool, allNeg: Bool, noEmpty: Bool, dot: Bool, acc: Out}
  GenAlts{alts: List<&2, Ast>, start: Bool, end: Bool, neg: Bool, dot: Bool, filter: Bool, acc: Out}
  GenExt{kind: U32, empty: Bool, origin: U32, events: Nat, body: Out, start: Bool, end: Bool, dot: Bool}

# `toRegExpSource(allowDot)` over the tree. Starts and ends follow `isStart`
# and `isEnd`; invalid whole-portion extglobs turn into their literal text.
def gen(fuel: Nat, task: Gen) -> Out:
  match fuel task:
    case 0n _: noOut()
    case 1n+_ GenParts{Nil{}, _, _, _, _, _, acc}: finished(acc)
    case 1n+(+more) GenParts{Text{+text} <> rest, +start, +end, _, +noEmpty, +dot, acc}:
      gen(more, GenParts{rest, start, end, False{}, noEmpty, dot, accumulate(acc, globOut(parseGlob(text, noEmpty), text))})
    case 1n+(+more) GenParts{Ext{+kind, alts, empty, origin, events} <> +rest, +start, +end, +allNeg, +noEmpty, +dot, acc}:
      +first = start && allNeg
      +last = end && List.is_empty(&2, Ast, rest)
      +element = gen(more, GenExt{kind, empty, origin, events, gen(more, GenAlts{alts, first, last, isNegation(kind), dot, first && last, noOut()}), first, last, dot})
      gen(more, GenParts{rest, start, end, allNeg && isNegation(kind), noEmpty, dot, accumulate(acc, element)})
    case 1n+(+more) GenParts{Seq{+parts, index, fills} <> rest, +start, +end, +allNeg, +noEmpty, +dot, acc}:
      +first = start && allNeg
      +element = wrapSeq(gen(more, GenParts{parts, first, end, True{}, first && end && allText(parts), dot, noOut()}), index, fills, first, end, False{}, dot)
      gen(more, GenParts{rest, start, end, False{}, noEmpty, dot, accumulate(acc, element)})
    case 1n+_ GenAlts{Nil{}, _, _, _, _, _, acc}: finished(acc)
    case 1n+(+more) GenAlts{Seq{+parts, +index, fills} <> rest, +start, +end, +neg, +dot, +filter, acc}:
      +first = start && Nat.is_eq(index, 0n)
      +last = neg || end
      +element = wrapSeq(gen(more, GenParts{parts, first, last, True{}, first && last && allText(parts), dot, noOut()}), index, fills, first, last, neg, dot)
      gen(more, GenAlts{rest, start, end, neg, dot, filter, accumulateAlt(acc, element, filter)})
    case 1n+(+more) GenAlts{_ <> rest, start, end, neg, dot, filter, acc}: gen(more, GenAlts{rest, start, end, neg, dot, filter, acc})
    case 1n+(+more) GenExt{+kind, +empty, +origin, +events, Out{+body, +magic, +uflag, +alts, +count}, +start, +end, +dot}:
      Bool.pick(Unit -> Out, start && end && isEmpty(body) && Bool.not(isNegation(kind)),
        _ => (+text = emptyExtText(kind, astSize(alts))
              Out{text, False{}, False{}, Seq{Text{text} <> Nil{}, 0n, 0n} <> Nil{}, 1n}),
        _ => Bool.pick(Unit -> Out, (U32.is_eq(kind, 42) || U32.is_eq(kind, 43)) && Bool.not(dot),
          _ => extOut(kind, empty, origin, events, start, dot, Out{body, magic, uflag, alts, count}, gen(more, GenAlts{alts, start, end, isNegation(kind), True{}, start && end, noOut()})),
          _ => extOut(kind, empty, origin, events, start, dot, Out{body, magic, uflag, alts, count}, Out{Nil{}, False{}, False{}, alts, count}))(Unit{}))(Unit{})

# ---------------------------------------------------------------------------
# The generated expressions (ECMAScript RegExp syntax, with or without `u`)
# ---------------------------------------------------------------------------

# Expressions over UTF-16 units, or code points under `u`. Captures and
# greediness cannot change whether an anchored match exists, so matching
# computes the set of reachable end positions instead of backtracking.
type Member is Data:
  One{code: U32}
  Between{first: U32, last: U32}
  Category{class: Regex.Class, negated: Bool}

type Re is Data:
  Nothing{}
  Code{code: U32}
  Dot{}
  Set{negated: Bool, members: List<&2, Member>}
  Begin{}
  Finish{}
  Ahead{negated: Bool, body: Re}
  Then{first: Re, second: Re}
  Either{first: Re, second: Re}
  Repeat{body: Re, min: Nat, bounded: Bool}

# A parsed term: 0 an atom, 1 quantified, 2 quantified and lazy, 3 an
# assertion, 4 a lookahead (quantifiable only without `u`, Annex B).
type Term is Data:
  Term{re: Re, kind: U32}

# An open group: 0 the whole expression, 1 a group, 2 `(?!`, 3 `(?=`.
type Frame is Data:
  Frame{kind: U32, alts: List<&2, Re>, terms: List<&2, Term>}

type Read is Data:
  Read{re: Maybe<&2, Re>, rest: List<&2, U32>}

type MemberRead is Data:
  MemberRead{member: Maybe<&2, Member>, rest: List<&2, U32>}

def isSyntaxCharacter(+code: U32) -> Bool:
  U32.is_eq(code, 94) || U32.is_eq(code, 36) || U32.is_eq(code, 92) || U32.is_eq(code, 46) || U32.is_eq(code, 42) || U32.is_eq(code, 43) || U32.is_eq(code, 63) || U32.is_eq(code, 40) || U32.is_eq(code, 41) || U32.is_eq(code, 91) || U32.is_eq(code, 93) || U32.is_eq(code, 123) || U32.is_eq(code, 125) || U32.is_eq(code, 124) || U32.is_eq(code, 47)

def hexValue(+code: U32) -> U32:
  Bool.pick(U32, isDigit(code), (code - 48 : U32),
    Bool.pick(U32, U32.is_ge(code, 97) && U32.is_le(code, 102), (code - 87 : U32),
      Bool.pick(U32, U32.is_ge(code, 65) && U32.is_le(code, 70), (code - 55 : U32), 16)))

def isHex(+code: U32) -> Bool: U32.is_lt(hexValue(code), 16)

def controlEscape(+code: U32) -> U32:
  Bool.pick(U32, U32.is_eq(code, 116), 9, Bool.pick(U32, U32.is_eq(code, 110), 10, Bool.pick(U32, U32.is_eq(code, 114), 13,
    Bool.pick(U32, U32.is_eq(code, 118), 11, Bool.pick(U32, U32.is_eq(code, 102), 12, 0)))))

def nameUntilBrace(text: List<&2, U32>, reversed: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match text:
    case Nil{}: None{}
    case 125 <> _: Some{List.reverse(&2, U32, reversed)}
    case code <> rest: nameUntilBrace(rest, code <> reversed)

def classOf(result: Result<&2, &2, Regex.Error, Regex.Class>, negated: Bool) -> Maybe<&2, Member>:
  match result:
    case Done{class}: Some{Category{class, negated}}
    case Fail{_}: None{}

def categoryMember(name: Maybe<&2, List<&2, U32>>, negated: Bool) -> Maybe<&2, Member>:
  match name:
    case None{}: None{}
    case Some{value}: classOf(Regex.property(scalars(value)), negated)

def afterBrace(text: List<&2, U32>) -> List<&2, U32>:
  match text:
    case Nil{}: Nil{}
    case 125 <> rest: rest
    case _ <> rest: afterBrace(rest)

def hexEscape(text: List<&2, U32>, +unicode: Bool) -> MemberRead:
  match text:
    case +high <> +low <> +rest:
      Bool.pick(Unit -> MemberRead, isHex(high) && isHex(low),
        _ => MemberRead{Some{One{(hexValue(high) * 16 + hexValue(low) : U32)}}, rest},
        _ => MemberRead{Bool.pick(Maybe<&2, Member>, unicode, None{}, Some{One{120}}), high <> low <> rest})(Unit{})
    case other: MemberRead{Bool.pick(Maybe<&2, Member>, unicode, None{}, Some{One{120}}), other}

# A backslash escape (after the `\`): a single code, or a `\p{..}` category.
def escapeMember(text: List<&2, U32>, +unicode: Bool, +inClass: Bool) -> MemberRead:
  match text:
    case Nil{}: MemberRead{None{}, Nil{}}
    case +code <> +rest:
      Bool.pick(Unit -> MemberRead, U32.is_eq(code, 120),
        _ => hexEscape(rest, unicode),
        _ => Bool.pick(Unit -> MemberRead, U32.is_eq(controlEscape(code), 0),
          _ => Bool.pick(Unit -> MemberRead, unicode && (U32.is_eq(code, 112) || U32.is_eq(code, 80)) && startsWithCode(rest, 123),
            _ => MemberRead{categoryMember(nameUntilBrace(skip(rest, 1n), Nil{}), U32.is_eq(code, 80)), afterBrace(rest)},
            _ => Bool.pick(Unit -> MemberRead, inClass && U32.is_eq(code, 98),
              _ => MemberRead{Some{One{8}}, rest},
              _ => MemberRead{Bool.pick(Maybe<&2, Member>, unicode && Bool.not(isSyntaxCharacter(code) || (inClass && U32.is_eq(code, 45))), None{}, Some{One{code}}), rest})(Unit{}))(Unit{}),
          _ => MemberRead{Some{One{controlEscape(code)}}, rest})(Unit{}))(Unit{})

def classMember(text: List<&2, U32>, +unicode: Bool) -> MemberRead:
  match text:
    case Nil{}: MemberRead{None{}, Nil{}}
    case 92 <> rest: escapeMember(rest, unicode, True{})
    case code <> rest: MemberRead{Some{One{code}}, rest}

type ClassTask is Data:
  ClassNext{text: List<&2, U32>, members: List<&2, Member>}
  ClassAfter{read: MemberRead, members: List<&2, Member>}
  ClassRange{first: Member, read: MemberRead, members: List<&2, Member>}
  ClassAdd{members: Maybe<&2, List<&2, Member>>, text: List<&2, U32>}

def isCategory(member: Member) -> Bool:
  match member:
    case Category{_, _}: True{}
    case _: False{}

def rangeOf(first: Member, last: Member) -> Maybe<&2, Member>:
  match first last:
    case One{+a} One{+b}: Bool.pick(Maybe<&2, Member>, U32.is_gt(a, b), None{}, Some{Between{a, b}})
    case _ _: None{}

def rangeMembers(value: Maybe<&2, Member>, members: List<&2, Member>) -> Maybe<&2, List<&2, Member>>:
  match value:
    case None{}: None{}
    case Some{member}: Some{member <> members}

def rangeStartsAt(text: List<&2, U32>) -> Bool:
  match text:
    case 45 <> 93 <> _: False{}
    case 45 <> _ <> _: True{}
    case _: False{}

type ClassRead is Data:
  ClassRead{members: Maybe<&2, List<&2, Member>>, rest: List<&2, U32>}

# `ClassRanges` up to the closing `]`.
def classTask(fuel: Nat, task: ClassTask, +unicode: Bool) -> ClassRead:
  match fuel task:
    case 0n _: ClassRead{None{}, Nil{}}
    case 1n+_ ClassNext{Nil{}, _}: ClassRead{None{}, Nil{}}
    case 1n+_ ClassNext{93 <> rest, members}: ClassRead{Some{List.reverse(&2, Member, members)}, rest}
    case 1n+(+more) ClassNext{text, members}: classTask(more, ClassAfter{classMember(text, unicode), members}, unicode)
    case 1n+_ ClassAfter{MemberRead{None{}, rest}, _}: ClassRead{None{}, rest}
    case 1n+(+more) ClassAfter{MemberRead{Some{+member}, +rest}, +members}:
      Bool.pick(Unit -> ClassRead, rangeStartsAt(rest),
        _ => classTask(more, ClassRange{member, classMember(skip(rest, 1n), unicode), members}, unicode),
        _ => classTask(more, ClassNext{rest, member <> members}, unicode))(Unit{})
    case 1n+_ ClassRange{_, MemberRead{None{}, rest}, _}: ClassRead{None{}, rest}
    case 1n+(+more) ClassRange{+first, MemberRead{Some{+last}, +rest}, +members}:
      Bool.pick(Unit -> ClassRead, isCategory(first) || isCategory(last),
        _ => Bool.pick(Unit -> ClassRead, unicode, _ => ClassRead{None{}, rest}, _ => classTask(more, ClassNext{rest, last <> One{45} <> first <> members}, unicode))(Unit{}),
        _ => classTask(more, ClassAdd{rangeMembers(rangeOf(first, last), members), rest}, unicode))(Unit{})
    case 1n+_ ClassAdd{None{}, rest}: ClassRead{None{}, rest}
    case 1n+(+more) ClassAdd{Some{members}, rest}: classTask(more, ClassNext{rest, members}, unicode)


def classMembers(value: ClassRead) -> Maybe<&2, List<&2, Member>>:
  match value:
    case ClassRead{members, _}: members

def classRest(value: ClassRead) -> List<&2, U32>:
  match value:
    case ClassRead{_, rest}: rest

def memberOf(value: MemberRead) -> Maybe<&2, Member>:
  match value:
    case MemberRead{member, _}: member

def memberRest(value: MemberRead) -> List<&2, U32>:
  match value:
    case MemberRead{_, rest}: rest

def sequenceOf(terms: List<&2, Term>, acc: Re) -> Re:
  match terms:
    case Nil{}: acc
    case Term{re, _} <> rest: sequenceOf(rest, Then{re, acc})

# Alternatives combine as a balanced tree, keeping matching recursion shallow.
def pairUp(items: List<&2, Re>, reversed: List<&2, Re>) -> List<&2, Re>:
  match items:
    case Nil{}: reversed
    case one <> Nil{}: one <> reversed
    case first <> second <> rest: pairUp(rest, Either{first, second} <> reversed)

def balance(fuel: Nat, items: List<&2, Re>) -> Re:
  match fuel items:
    case _ Nil{}: Nothing{}
    case _ one <> Nil{}: one
    case 0n _: Nothing{}
    case 1n+more _: balance(more, pairUp(items, Nil{}))

def alternation(alts: List<&2, Re>, last: Re) -> Re: balance(64n, last <> alts)

def frameRe(frame: Frame) -> Re:
  match frame:
    case Frame{_, alts, terms}: alternation(alts, sequenceOf(terms, Nothing{}))

def frameKind(frame: Frame) -> U32:
  match frame:
    case Frame{kind, _, _}: kind

def withTerm(frame: Maybe<&2, Frame>, term: Term) -> Maybe<&2, Frame>:
  match frame:
    case None{}: None{}
    case Some{Frame{kind, alts, terms}}: Some{Frame{kind, alts, term <> terms}}

def addAtom(frame: Maybe<&2, Frame>, re: Maybe<&2, Re>) -> Maybe<&2, Frame>:
  match re:
    case None{}: None{}
    case Some{value}: withTerm(frame, Term{value, 0})

def memberAtom(member: Maybe<&2, Member>) -> Maybe<&2, Re>:
  match member:
    case None{}: None{}
    case Some{One{code}}: Some{Code{code}}
    case Some{other}: Some{Set{False{}, other <> Nil{}}}

def setAtom(negated: Bool, members: Maybe<&2, List<&2, Member>>) -> Maybe<&2, Re>:
  match members:
    case None{}: None{}
    case Some{values}: Some{Set{negated, values}}

def bar(frame: Frame) -> Frame:
  match frame:
    case Frame{kind, alts, terms}: Frame{kind, sequenceOf(terms, Nothing{}) <> alts, Nil{}}

def closeInto(frame: Frame, parent: Frame) -> Maybe<&2, Frame>:
  match frame:
    case Frame{1, alts, terms}: withTerm(Some{parent}, Term{frameRe(Frame{1, alts, terms}), 0})
    case Frame{2, alts, terms}: withTerm(Some{parent}, Term{Ahead{True{}, frameRe(Frame{2, alts, terms})}, 4})
    case Frame{3, alts, terms}: withTerm(Some{parent}, Term{Ahead{False{}, frameRe(Frame{3, alts, terms})}, 4})
    case _: None{}

def quantified(+code: U32, re: Re) -> Term:
  Term{Repeat{re, Bool.pick(Nat, U32.is_eq(code, 43), 1n, 0n), U32.is_eq(code, 63)}, 1}

def quantifyTerms(terms: List<&2, Term>, +code: U32, +unicode: Bool) -> Maybe<&2, List<&2, Term>>:
  match terms:
    case Term{re, 0} <> rest: Some{quantified(code, re) <> rest}
    case Term{re, 4} <> rest: Bool.pick(Maybe<&2, List<&2, Term>>, unicode, None{}, Some{quantified(code, re) <> rest})
    case Term{re, 1} <> rest: Bool.pick(Maybe<&2, List<&2, Term>>, U32.is_eq(code, 63), Some{Term{re, 2} <> rest}, None{})
    case _: None{}

def withTerms(kind: U32, alts: List<&2, Re>, terms: Maybe<&2, List<&2, Term>>) -> Maybe<&2, Frame>:
  match terms:
    case None{}: None{}
    case Some{values}: Some{Frame{kind, alts, values}}

def quantify(frame: Frame, code: U32, unicode: Bool) -> Maybe<&2, Frame>:
  match frame:
    case Frame{kind, alts, terms}: withTerms(kind, alts, quantifyTerms(terms, code, unicode))

def isQuantifier(+code: U32) -> Bool: U32.is_eq(code, 42) || U32.is_eq(code, 43) || U32.is_eq(code, 63)
def isLoneBracket(+code: U32) -> Bool: U32.is_eq(code, 123) || U32.is_eq(code, 125) || U32.is_eq(code, 93)

def negatedClass(text: List<&2, U32>) -> Bool: startsWithCode(text, 94)
def classBody(+text: List<&2, U32>) -> List<&2, U32>: Bool.pick(List<&2, U32>, negatedClass(text), skip(text, 1n), text)

# A quantifier, or a literal character.
def plainStep(+current: Frame, +code: U32, +unicode: Bool) -> Maybe<&2, Frame>:
  Bool.pick(Unit -> Maybe<&2, Frame>, isQuantifier(code),
    _ => quantify(current, code, unicode),
    _ => Bool.pick(Maybe<&2, Frame>, unicode && isLoneBracket(code), None{}, withTerm(Some{current}, Term{Code{code}, 0})))(Unit{})

type Token is Data:
  TEnd{}
  TBad{}
  TOpen{kind: U32, rest: List<&2, U32>}
  TClose{rest: List<&2, U32>}
  TBar{rest: List<&2, U32>}
  TTerm{term: Term, rest: List<&2, U32>}
  TEscape{rest: List<&2, U32>}
  TClass{rest: List<&2, U32>}
  TPlain{code: U32, rest: List<&2, U32>}

def token(text: List<&2, U32>) -> Token:
  match text:
    case Nil{}: TEnd{}
    case 40 <> 63 <> 58 <> rest: TOpen{1, rest}
    case 40 <> 63 <> 33 <> rest: TOpen{2, rest}
    case 40 <> 63 <> 61 <> rest: TOpen{3, rest}
    case 40 <> 63 <> _: TBad{}
    case 40 <> rest: TOpen{1, rest}
    case 41 <> rest: TClose{rest}
    case 124 <> rest: TBar{rest}
    case 94 <> rest: TTerm{Term{Begin{}, 3}, rest}
    case 36 <> rest: TTerm{Term{Finish{}, 3}, rest}
    case 46 <> rest: TTerm{Term{Dot{}, 0}, rest}
    case 92 <> rest: TEscape{rest}
    case 91 <> rest: TClass{rest}
    case code <> rest: TPlain{code, rest}

# The pattern grammar with explicit group frames; `None` is a SyntaxError.
def reScan(fuel: Nat, frame: Maybe<&2, Frame>, next: Token, outer: List<&2, Frame>, +unicode: Bool) -> Maybe<&2, Re>:
  match fuel frame next outer:
    case 0n _ _ _: None{}
    case _ None{} _ _: None{}
    case 1n+_ Some{+current} TEnd{} Nil{}: Bool.pick(Maybe<&2, Re>, U32.is_eq(frameKind(current), 0), Some{frameRe(current)}, None{})
    case 1n+_ Some{_} TEnd{} _: None{}
    case 1n+_ Some{_} TBad{} _: None{}
    case 1n+(+more) Some{current} TOpen{kind, rest} outer: reScan(more, Some{Frame{kind, Nil{}, Nil{}}}, token(rest), current <> outer, unicode)
    case 1n+(+more) Some{current} TClose{rest} parent <> outer: reScan(more, closeInto(current, parent), token(rest), outer, unicode)
    case 1n+_ Some{_} TClose{_} Nil{}: None{}
    case 1n+(+more) Some{current} TBar{rest} outer: reScan(more, Some{bar(current)}, token(rest), outer, unicode)
    case 1n+(+more) Some{current} TTerm{term, rest} outer: reScan(more, withTerm(Some{current}, term), token(rest), outer, unicode)
    case 1n+(+more) Some{current} TEscape{rest} outer:
      +read = escapeMember(rest, unicode, False{})
      reScan(more, addAtom(Some{current}, memberAtom(memberOf(read))), token(memberRest(read)), outer, unicode)
    case 1n+(+more) Some{current} TClass{+rest} outer:
      +read = classTask(deep(), ClassNext{classBody(rest), Nil{}}, unicode)
      reScan(more, addAtom(Some{current}, setAtom(negatedClass(rest), classMembers(read))), token(classRest(read)), outer, unicode)
    case 1n+(+more) Some{current} TPlain{code, rest} outer: reScan(more, plainStep(current, code, unicode), token(rest), outer, unicode)

# `new RegExp('^' + source + '$', uflag ? 'u' : '')`.
def compileRe(+source: List<&2, U32>, +unicode: Bool) -> Maybe<&2, Re>:
  +text = Bool.pick(List<&2, U32>, unicode, codePoints(source), source)
  reScan(deep(), Some{Frame{0, Nil{}, Nil{}}}, token(94 <> cat(text, 36 <> Nil{})), Nil{}, unicode)

type Pos is Data:
  Pos{index: U32, rest: List<&2, U32>}

# A set of positions by index: a binary trie over the index bits.
type Seen is Data:
  Unseen{}
  Seen{here: Bool, low: Seen, high: Seen}

def seenHas(set: Seen, +key: U32) -> Bool:
  match set:
    case Unseen{}: False{}
    case Seen{here, low, high}:
      Bool.pick(Unit -> Bool, U32.is_eq(key, 0), _ => here,
        _ => Bool.pick(Unit -> Bool, U32.is_eq(U32.and(key, 1), 0), _ => seenHas(low, U32.shr(key)), _ => seenHas(high, U32.shr(key)))(Unit{}))(Unit{})

def seenAdd(bits: Nat, set: Seen, +key: U32) -> Seen:
  match bits set:
    case 0n other: other
    case 1n+more Unseen{}: seenAdd(more, Seen{False{}, Unseen{}, Unseen{}}, key)
    case 1n+(+more) Seen{+here, +low, +high}:
      Bool.pick(Unit -> Seen, U32.is_eq(key, 0), _ => Seen{True{}, low, high},
        _ => Bool.pick(Unit -> Seen, U32.is_eq(U32.and(key, 1), 0), _ => Seen{here, seenAdd(more, low, U32.shr(key)), high}, _ => Seen{here, low, seenAdd(more, high, U32.shr(key))})(Unit{}))(Unit{})

def seenAll(positions: List<&2, Pos>, set: Seen) -> Seen:
  match positions:
    case Nil{}: set
    case Pos{index, _} <> rest: seenAll(rest, seenAdd(33n, set, index))

# The positions whose index is not in `set`.
def unseen(positions: List<&2, Pos>, +set: Seen, +reversed: List<&2, Pos>) -> List<&2, Pos>:
  match positions:
    case Nil{}: reversed
    case Pos{+index, rest} <> more: unseen(more, set, Bool.pick(List<&2, Pos>, seenHas(set, index), reversed, Pos{index, rest} <> reversed))

def unionPos(+left: List<&2, Pos>, right: List<&2, Pos>) -> List<&2, Pos>: unseen(right, seenAll(left, Unseen{}), left)

def memberAccepts(members: List<&2, Member>, +code: U32) -> Bool:
  match members:
    case Nil{}: False{}
    case One{value} <> rest: Bool.pick(Unit -> Bool, U32.is_eq(value, code), _ => True{}, _ => memberAccepts(rest, code))(Unit{})
    case Between{first, last} <> rest: Bool.pick(Unit -> Bool, U32.is_ge(code, first) && U32.is_le(code, last), _ => True{}, _ => memberAccepts(rest, code))(Unit{})
    case Category{class, negated} <> rest: Bool.pick(Unit -> Bool, Bool.xor(Regex.contains(class, code), negated), _ => True{}, _ => memberAccepts(rest, code))(Unit{})

def accepts(re: Re, +code: U32) -> Bool:
  match re:
    case Code{value}: U32.is_eq(value, code)
    case Dot{}: Bool.not(isLineTerminator(code))
    case Set{negated, members}: Bool.xor(memberAccepts(members, code), negated)
    case _: False{}

def stepPositions(+re: Re, positions: List<&2, Pos>, +reversed: List<&2, Pos>) -> List<&2, Pos>:
  match positions:
    case Nil{}: reversed
    case Pos{index, +code <> rest} <> more: stepPositions(re, more, Bool.pick(List<&2, Pos>, accepts(re, code), Pos{(index + 1 : U32), rest} <> reversed, reversed))
    case _ <> more: stepPositions(re, more, reversed)

def atBegin(positions: List<&2, Pos>, reversed: List<&2, Pos>) -> List<&2, Pos>:
  match positions:
    case Nil{}: reversed
    case Pos{0, rest} <> more: atBegin(more, Pos{0, rest} <> reversed)
    case _ <> more: atBegin(more, reversed)

def atFinish(positions: List<&2, Pos>, reversed: List<&2, Pos>) -> List<&2, Pos>:
  match positions:
    case Nil{}: reversed
    case Pos{index, Nil{}} <> more: atFinish(more, Pos{index, Nil{}} <> reversed)
    case _ <> more: atFinish(more, reversed)

type Run is Data:
  Run{re: Re, positions: List<&2, Pos>}
  Closure{body: Re, reached: List<&2, Pos>, seen: Seen, frontier: List<&2, Pos>}
  Grow{body: Re, reached: List<&2, Pos>, seen: Seen, fresh: List<&2, Pos>}
  Look{negated: Bool, body: Re, todo: List<&2, Pos>, kept: List<&2, Pos>}

# The end positions reachable from `positions` through the expression. Each
# position enters a repetition's frontier at most once.
def ends(fuel: Nat, task: Run) -> List<&2, Pos>:
  match fuel task:
    case 0n _: Nil{}
    case 1n+_ Run{_, Nil{}}: Nil{}
    case 1n+_ Run{Nothing{}, positions}: positions
    case 1n+_ Run{Begin{}, positions}: atBegin(positions, Nil{})
    case 1n+_ Run{Finish{}, positions}: atFinish(positions, Nil{})
    case 1n+(+more) Run{Ahead{negated, body}, positions}: ends(more, Look{negated, body, positions, Nil{}})
    case 1n+(+more) Run{Then{first, second}, positions}: ends(more, Run{second, ends(more, Run{first, positions})})
    case 1n+(+more) Run{Either{first, second}, +positions}: unionPos(ends(more, Run{first, positions}), ends(more, Run{second, positions}))
    case 1n+(+more) Run{Repeat{body, 0n, True{}}, +positions}: unionPos(positions, ends(more, Run{body, positions}))
    case 1n+(+more) Run{Repeat{body, _, True{}}, positions}: ends(more, Run{body, positions})
    case 1n+(+more) Run{Repeat{body, 0n, False{}}, +positions}: ends(more, Closure{body, positions, seenAll(positions, Unseen{}), positions})
    case 1n+(+more) Run{Repeat{+body, _, False{}}, positions}:
      +first = ends(more, Run{body, positions})
      ends(more, Closure{body, first, seenAll(first, Unseen{}), first})
    case 1n+_ Run{leaf, positions}: stepPositions(leaf, positions, Nil{})
    case 1n+(+more) Closure{+body, reached, +seen, frontier}: ends(more, Grow{body, reached, seen, unseen(ends(more, Run{body, frontier}), seen, Nil{})})
    case 1n+_ Grow{_, reached, _, Nil{}}: reached
    case 1n+(+more) Grow{body, reached, seen, +fresh}: ends(more, Closure{body, onto(Pos, fresh, reached), seenAll(fresh, seen), fresh})
    case 1n+_ Look{_, _, Nil{}, kept}: kept
    case 1n+(+more) Look{+negated, +body, +position <> rest, +kept}:
      +hit = Bool.not(List.is_empty(&2, Pos, ends(more, Run{body, position <> Nil{}})))
      ends(more, Look{negated, body, rest, Bool.pick(List<&2, Pos>, Bool.xor(hit, negated), position <> kept, kept)})

# Every start position: `test` searches, and `^` or `$` may sit inside an
# alternation (an escaped `|` stays a bare `|` in the source).
def starts(text: List<&2, U32>, +index: U32, reversed: List<&2, Pos>) -> List<&2, Pos>:
  match text:
    case Nil{}: Pos{index, Nil{}} <> reversed
    case +code <> +rest: starts(rest, (index + 1 : U32), Pos{index, code <> rest} <> reversed)

# `regexp.test(subject)` for a compiled `^...$` expression.
def testRe(re: Re, unicode: Bool, +subject: List<&2, U32>) -> Bool:
  Bool.not(List.is_empty(&2, Pos, ends(deep(), Run{re, starts(Bool.pick(List<&2, U32>, unicode, codePoints(subject), subject), 0, Nil{})})))

# ---------------------------------------------------------------------------
# Minimatch (index.js)
# ---------------------------------------------------------------------------

# A compiled path portion test. The first five are upstream's fast checks
# for the most common portion shapes; they replace the expression's `test`.
type Test is Data:
  StarTest{}
  StarExtTest{ext: List<&2, U32>}
  QmarksTest{length: Nat, ext: List<&2, U32>}
  StarDotStarTest{}
  DotStarTest{}
  RegexTest{re: Re, unicode: Bool}

# A path portion of a pattern: `**`, a literal, or a magic test.
type Part is Data:
  Globstar{}
  Literal{text: List<&2, U32>}
  Magic{test: Test}

# Upstream throws from the constructor when a generated expression is not a
# valid RegExp (for example an escaped `,` with the `u` flag).
type Error is Data:
  InvalidRegExp{source: String}

type Minimatch is Data:
  Comment{}
  EmptyPattern{}
  Compiled{negate: Bool, set: List<&2, List<&2, Part>>}

def leadingDot(text: List<&2, U32>) -> Bool: startsWithCode(text, 46)

def runTest(test: Test, +file: List<&2, U32>) -> Bool:
  match test:
    case StarTest{}: Bool.not(isEmpty(file)) && Bool.not(leadingDot(file))
    case StarExtTest{ext}: Bool.not(leadingDot(file)) && endsWith(file, ext)
    case QmarksTest{length, +ext}: Nat.is_eq(size(file), length) && Bool.not(leadingDot(file)) && (isEmpty(ext) || endsWith(file, ext))
    case StarDotStarTest{}: Bool.not(leadingDot(file)) && includesCode(file, 46)
    case DotStarTest{}: Bool.not(same(file, 46 <> Nil{})) && Bool.not(same(file, 46 <> 46 <> Nil{})) && leadingDot(file)
    case RegexTest{re, unicode}: testRe(re, unicode, file)

def withoutStars(text: List<&2, U32>, +code: U32) -> List<&2, U32>:
  match text:
    case Nil{}: Nil{}
    case +first <> +rest: Bool.pick(Unit -> List<&2, U32>, U32.is_eq(first, code), _ => withoutStars(rest, code), _ => first <> rest)(Unit{})

# `[^+@!?*[(]*`.
def plainExt(text: List<&2, U32>) -> Bool:
  match text:
    case Nil{}: True{}
    case +code <> rest:
      Bool.pick(Unit -> Bool, U32.is_eq(code, 43) || U32.is_eq(code, 64) || U32.is_eq(code, 33) || U32.is_eq(code, 63) || U32.is_eq(code, 42) || U32.is_eq(code, 91) || U32.is_eq(code, 40), _ => False{}, _ => plainExt(rest))(Unit{})

def starDotStarTail(text: List<&2, U32>) -> Bool:
  match text:
    case 46 <> 42 <> rest: allStars(rest)
    case _: False{}

def starDotStar(text: List<&2, U32>) -> Bool:
  match text:
    case 42 <> rest: starDotStarTail(withoutStars(rest, 42))
    case _: False{}


def dotStar(text: List<&2, U32>) -> Bool:
  match text:
    case 46 <> 42 <> rest: allStars(rest)
    case _: False{}

# The fast checks of `parse`, tried in upstream's order.
def fastTest(+text: List<&2, U32>) -> Maybe<&2, Test>:
  +stars = startsWithCode(text, 42)
  +marks = startsWithCode(text, 63)
  Bool.pick(Unit -> Maybe<&2, Test>, stars && allStars(text),
    _ => Some{StarTest{}},
    _ => Bool.pick(Unit -> Maybe<&2, Test>, stars && plainExt(withoutStars(text, 42)),
      _ => Some{StarExtTest{withoutStars(text, 42)}},
      _ => Bool.pick(Unit -> Maybe<&2, Test>, marks && plainExt(withoutStars(text, 63)),
        _ => Some{QmarksTest{size(text), withoutStars(text, 63)}},
        _ => Bool.pick(Unit -> Maybe<&2, Test>, starDotStar(text),
          _ => Some{StarDotStarTest{}},
          _ => Bool.pick(Maybe<&2, Test>, dotStar(text), Some{DotStarTest{}}, None{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})

def seqParts(node: Ast) -> List<&2, Ast>:
  match node:
    case Seq{parts, _, _}: parts
    case other: other <> Nil{}

def regexPart(re: Maybe<&2, Re>, unicode: Bool, +source: List<&2, U32>) -> Result<&2, &2, Error, Part>:
  match re:
    case Some{value}: Done{Magic{RegexTest{value, unicode}}}
    case None{}: Fail{InvalidRegExp{scalars(47 <> 94 <> cat(source, 36 <> 47 <> Nil{}))}}

# `AST.fromGlob(pattern).toMMPattern()`: the unescaped literal, or an expression.
def astPart(out: Out) -> Result<&2, &2, Error, Part>:
  match out:
    case Out{+source, +magic, +uflag, +items, count}:
      Bool.pick(Unit -> Result<&2, &2, Error, Part>, magic,
        _ => (+full = outSource(wrapSeq(Out{source, magic, uflag, items, count}, 0n, 0n, True{}, True{}, False{}, False{}))
              regexPart(compileRe(full, uflag), uflag, full)),
        _ => Done{Literal{unescape(source)}})(Unit{})

def compileAst(+parts: List<&2, Ast>) -> Result<&2, &2, Error, Part>:
  astPart(gen(deep(), GenParts{parts, True{}, True{}, True{}, allText(parts), False{}, noOut()}))

def fastPart(test: Maybe<&2, Test>, +text: List<&2, U32>) -> Result<&2, &2, Error, Part>:
  match test:
    case Some{value}: Done{Magic{value}}
    case None{}: compileAst(fill(deep(), FillParts{List.reverse(&2, Ast, flatten(deep(), Parts{seqParts(fromGlob(text)), Nil{}})), Nil{}, Nil{}}))

# `parse(pattern)` of one path portion.
def compilePart(+text: List<&2, U32>) -> Result<&2, &2, Error, Part>:
  Bool.pick(Unit -> Result<&2, &2, Error, Part>, same(text, 42 <> 42 <> Nil{}),
    _ => Done{Globstar{}},
    _ => Bool.pick(Unit -> Result<&2, &2, Error, Part>, isEmpty(text),
      _ => Done{Literal{Nil{}}},
      _ => fastPart(fastTest(text), text))(Unit{}))(Unit{})

# `split(/\/+/)`.
def slashSplitGo(text: List<&2, U32>, +current: List<&2, U32>, +parts: List<&2, List<&2, U32>>, +slash: Bool) -> List<&2, List<&2, U32>>:
  match text:
    case Nil{}: List.reverse(&2, List<&2, U32>, List.reverse(&2, U32, current) <> parts)
    case +code <> +rest:
      Bool.pick(Unit -> List<&2, List<&2, U32>>, U32.is_eq(code, 47),
        _ => Bool.pick(Unit -> List<&2, List<&2, U32>>, slash, _ => slashSplitGo(rest, current, parts, True{}), _ => slashSplitGo(rest, Nil{}, List.reverse(&2, U32, current) <> parts, True{}))(Unit{}),
        _ => slashSplitGo(rest, code <> current, parts, False{}))(Unit{})

def slashSplit(text: List<&2, U32>) -> List<&2, List<&2, U32>>: slashSplitGo(text, Nil{}, Nil{}, False{})

def isGlobstarText(text: List<&2, U32>) -> Bool:
  match text:
    case 42 <> 42 <> Nil{}: True{}
    case _: False{}

def isDotText(text: List<&2, U32>) -> Bool:
  match text:
    case 46 <> Nil{}: True{}
    case 46 <> 46 <> Nil{}: True{}
    case _: False{}

def isParentText(text: List<&2, U32>) -> Bool:
  match text:
    case 46 <> 46 <> Nil{}: True{}
    case _: False{}

# `levelOneOptimize`: drop repeated `**` and resolve `<p>/..`; `set` is the
# reduced list in reverse.
def levelOne(parts: List<&2, List<&2, U32>>, set: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match parts set:
    case Nil{} Nil{}: Nil{} <> Nil{}
    case Nil{} _: List.reverse(&2, List<&2, U32>, set)
    case +part <> +rest +prev <> +earlier:
      Bool.pick(Unit -> List<&2, List<&2, U32>>, isGlobstarText(part) && isGlobstarText(prev),
        _ => levelOne(rest, prev <> earlier),
        _ => Bool.pick(Unit -> List<&2, List<&2, U32>>, isParentText(part) && Bool.not(isEmpty(prev) || isDotText(prev) || isGlobstarText(prev)),
          _ => levelOne(rest, earlier),
          _ => levelOne(rest, part <> prev <> earlier))(Unit{}))(Unit{})
    case part <> rest Nil{}: levelOne(rest, part <> Nil{})

def compileParts(parts: List<&2, List<&2, U32>>) -> Result<&2, &2, Error, List<&2, Part>>:
  match parts:
    case Nil{}: Done{Nil{}}
    case part <> rest: Result.bind(&2, &2, Error, Part, List<&2, Part>, compilePart(part), compiled => Result.map(&2, &2, Error, List<&2, Part>, List<&2, Part>, others => compiled <> others, compileParts(rest)))

def compileSet(globs: List<&2, List<&2, U32>>) -> Result<&2, &2, Error, List<&2, List<&2, Part>>>:
  match globs:
    case Nil{}: Done{Nil{}}
    case glob <> rest: Result.bind(&2, &2, Error, List<&2, Part>, List<&2, List<&2, Part>>, compileParts(levelOne(slashSplit(glob), Nil{})), compiled => Result.map(&2, &2, Error, List<&2, List<&2, Part>>, List<&2, List<&2, Part>>, others => compiled <> others, compileSet(rest)))

# `parseNegate`: each leading `!` flips the pattern.
def negated(text: List<&2, U32>, +negate: Bool) -> Result<&2, &2, Error, Minimatch>:
  match text:
    case 33 <> rest: negated(rest, Bool.not(negate))
    case pattern: Result.map(&2, &2, Error, List<&2, List<&2, Part>>, Minimatch, set => Compiled{negate, set}, compileSet(braceExpandUnits(pattern)))

# `new Minimatch(pattern)`: comments and the empty pattern need no parsing.
def compileUnits(+pattern: List<&2, U32>) -> Result<&2, &2, Error, Minimatch>:
  Bool.pick(Unit -> Result<&2, &2, Error, Minimatch>, startsWithCode(pattern, 35),
    _ => Done{Comment{}},
    _ => Bool.pick(Unit -> Result<&2, &2, Error, Minimatch>, isEmpty(pattern), _ => Done{EmptyPattern{}}, _ => negated(pattern, False{}))(Unit{}))(Unit{})

def compile(pattern: String) -> Result<&2, &2, Error, Minimatch>: compileUnits(units(pattern))

def partHits(part: Part, +file: List<&2, U32>) -> Bool:
  match part:
    case Globstar{}: False{}
    case Literal{text}: same(text, file)
    case Magic{test}: runTest(test, file)

# `#matchOne` without globstars, from the first portion (`partial` is false).
def matchParts(file: List<&2, List<&2, U32>>, pattern: List<&2, Part>) -> Bool:
  match file pattern:
    case Nil{} Nil{}: True{}
    case Nil{} _: False{}
    case last <> Nil{} Nil{}: isEmpty(last)
    case _ Nil{}: False{}
    case +name <> rest part <> parts: Bool.pick(Unit -> Bool, partHits(part, name), _ => matchParts(rest, parts), _ => False{})(Unit{})

def isGlobstar(part: Part) -> Bool:
  match part:
    case Globstar{}: True{}
    case _: False{}

def hasGlobstar(pattern: List<&2, Part>) -> Bool:
  match pattern:
    case Nil{}: False{}
    case part <> rest: Bool.pick(Unit -> Bool, isGlobstar(part), _ => True{}, _ => hasGlobstar(rest))(Unit{})

def untilGlobstar(pattern: List<&2, Part>, reversed: List<&2, Part>) -> List<&2, Part>:
  match pattern:
    case Nil{}: List.reverse(&2, Part, reversed)
    case Globstar{} <> _: List.reverse(&2, Part, reversed)
    case part <> rest: untilGlobstar(rest, part <> reversed)

def afterGlobstar(pattern: List<&2, Part>) -> List<&2, Part>:
  match pattern:
    case Nil{}: Nil{}
    case Globstar{} <> rest: rest
    case _ <> rest: afterGlobstar(rest)

def partsLength(pattern: List<&2, Part>) -> Nat: lengthOf(Part, pattern)
def fileLength(file: List<&2, List<&2, U32>>) -> Nat: lengthOf(List<&2, U32>, file)

def globstarCount(pattern: List<&2, Part>, total: Nat) -> Nat:
  match pattern:
    case Nil{}: total
    case Globstar{} <> rest: globstarCount(rest, 1n + total)
    case _ <> rest: globstarCount(rest, total)

# The portions after the last globstar (the pattern has one).
def lastTail(count: Nat, +pattern: List<&2, Part>) -> List<&2, Part>:
  match count:
    case 0n: pattern
    case 1n+more: lastTail(more, afterGlobstar(pattern))

def dotted(file: List<&2, List<&2, U32>>) -> Bool:
  match file:
    case Nil{}: False{}
    case name <> rest: Bool.pick(Unit -> Bool, leadingDot(name), _ => True{}, _ => dotted(rest))(Unit{})

def lastEmpty(file: List<&2, List<&2, U32>>) -> Bool:
  match file:
    case Nil{}: False{}
    case last <> Nil{}: isEmpty(last)
    case _ <> rest: lastEmpty(rest)

# A body section between globstars and its last start index (`None` when
# upstream's computed bound is negative).
type Section is Data:
  Section{body: List<&2, Part>, after: Maybe<&2, Nat>}

def splitBody(pattern: List<&2, Part>, +current: List<&2, Part>, +sections: List<&2, List<&2, Part>>) -> List<&2, List<&2, Part>>:
  match pattern:
    case Nil{}: List.reverse(&2, List<&2, Part>, List.reverse(&2, Part, current) <> sections)
    case Globstar{} <> rest: splitBody(rest, Nil{}, List.reverse(&2, Part, current) <> sections)
    case part <> rest: splitBody(rest, part <> current, sections)

def prefixSums(sections: List<&2, List<&2, Part>>, +sum: Nat, reversed: List<&2, Nat>) -> List<&2, Nat>:
  match sections:
    case Nil{}: reversed
    case body <> rest: prefixSums(rest, sum + partsLength(body), sum <> reversed)

def signedBound(+total: Nat, +used: Nat) -> Maybe<&2, Nat>: Bool.pick(Maybe<&2, Nat>, Nat.is_ge(total, used), Some{Nat.sub(total, used)}, None{})

# `b[1] = fileLength - (nonGsPartsSums[i--] + b[0].length)`: upstream pairs
# the sections with the sums in reverse order.
def sectionBounds(sections: List<&2, List<&2, Part>>, sums: List<&2, Nat>, +total: Nat, reversed: List<&2, Section>) -> List<&2, Section>:
  match sections sums:
    case +body <> rest sum <> others: sectionBounds(rest, others, total, Section{body, signedBound(total, sum + partsLength(body))} <> reversed)
    case _ _: List.reverse(&2, Section, reversed)

def orEmptyName(name: Maybe<&2, List<&2, U32>>) -> List<&2, U32>:
  match name:
    case Some{value}: value
    case None{}: Nil{}

def fileAt(file: List<&2, List<&2, U32>>, index: Nat) -> List<&2, U32>: orEmptyName(List.get(&2, List<&2, U32>, file, index))

def withinBound(+index: Nat, after: Maybe<&2, Nat>) -> Bool:
  match after:
    case Some{bound}: Nat.is_le(index, bound)
    case None{}: False{}

# `#matchGlobStarBodySections`, with 0 false, 1 true and 2 null. Each body
# section is tried at every start up to its bound; recursion is capped at
# `maxGlobstarRecursion` (200) like upstream.
type Walk is Data:
  Sections{sections: List<&2, Section>, index: Nat, depth: Nat, sawTail: Bool}
  Try{body: List<&2, Part>, after: Maybe<&2, Nat>, rest: List<&2, Section>, index: Nat, depth: Nat, sawTail: Bool}
  Decide{result: U32, body: List<&2, Part>, after: Maybe<&2, Nat>, rest: List<&2, Section>, index: Nat, depth: Nat, sawTail: Bool}
  Advance{body: List<&2, Part>, after: Maybe<&2, Nat>, rest: List<&2, Section>, index: Nat, depth: Nat, sawTail: Bool}

def walk(fuel: Nat, +file: List<&2, List<&2, U32>>, task: Walk) -> U32:
  match fuel task:
    case 0n _: 0
    case 1n+_ Sections{Nil{}, +index, _, sawTail}:
      Bool.pick(U32, dotted(List.drop(&2, List<&2, U32>, file, index)), 0, Bool.pick(U32, sawTail || Nat.is_lt(index, fileLength(file)), 1, 0))
    case 1n+(+more) Sections{Section{body, after} <> rest, index, depth, sawTail}: walk(more, file, Try{body, after, rest, index, depth, sawTail})
    case 1n+(+more) Try{+body, +after, +rest, +index, +depth, +sawTail}:
      Bool.pick(Unit -> U32, withinBound(index, after),
        _ => Bool.pick(Unit -> U32, Nat.is_lt(depth, 200n) && matchParts(firstOf(List<&2, U32>, List.drop(&2, List<&2, U32>, file, index), partsLength(body)), body),
          _ => walk(more, file, Decide{walk(more, file, Sections{rest, index + partsLength(body), 1n + depth, sawTail}), body, after, rest, index, depth, sawTail}),
          _ => walk(more, file, Advance{body, after, rest, index, depth, sawTail}))(Unit{}),
        _ => 2)(Unit{})
    case 1n+(+more) Decide{0, body, after, rest, index, depth, sawTail}: walk(more, file, Advance{body, after, rest, index, depth, sawTail})
    case 1n+_ Decide{result, _, _, _, _, _, _}: result
    case 1n+(+more) Advance{body, after, rest, +index, depth, sawTail}:
      Bool.pick(Unit -> U32, leadingDot(fileAt(file, index)), _ => 0, _ => walk(more, file, Try{body, after, rest, 1n + index, depth, sawTail}))(Unit{})

# `#matchGlobstar`: the head and tail must match at the ends, the body
# sections in order between them; globstars never cross dot portions.
def matchGlobstarTail(+file: List<&2, List<&2, U32>>, +pattern: List<&2, Part>, +start: Nat) -> Bool:
  +tail = lastTail(globstarCount(pattern, 0n), pattern)
  +total = fileLength(file)
  +exact = Nat.is_eq(partsLength(tail), 0n) || matchParts(List.drop(&2, List<&2, U32>, file, Nat.sub(total, partsLength(tail))), tail)
  +trailing = Bool.not(exact) && lastEmpty(file) && Bool.not(Nat.is_eq(start + partsLength(tail), total)) && Nat.is_ge(total, 1n + partsLength(tail)) && matchParts(List.drop(&2, List<&2, U32>, file, Nat.sub(total, 1n + partsLength(tail))), tail)
  +tailMatch = Bool.pick(Nat, exact, partsLength(tail), 1n + partsLength(tail))
  +body = firstOf(Part, afterGlobstar(pattern), Nat.sub(partsLength(afterGlobstar(pattern)), Nat.add(partsLength(tail), 1n)))
  +sections = splitBody(body, Nil{}, Nil{})
  Bool.pick(Unit -> Bool, Nat.is_gt(start + partsLength(tail), total) || Bool.not(exact || trailing),
    _ => False{},
    _ => Bool.pick(Unit -> Bool, Nat.is_eq(globstarCount(pattern, 0n), 1n),
      _ => Bool.not(dotted(firstOf(List<&2, U32>, List.drop(&2, List<&2, U32>, file, start), Nat.sub(Nat.sub(total, tailMatch), start)))) && (Nat.is_gt(partsLength(tail), 0n) || Nat.is_gt(Nat.sub(total, tailMatch), start)),
      _ => U32.is_eq(walk(deep(), file, Sections{sectionBounds(sections, prefixSums(sections, 0n, Nil{}), Nat.sub(total, tailMatch), Nil{}), start, 0n, Nat.is_gt(partsLength(tail), 0n)}), 1))(Unit{}))(Unit{})

def matchGlobstar(+file: List<&2, List<&2, U32>>, +pattern: List<&2, Part>) -> Bool:
  +head = untilGlobstar(pattern, Nil{})
  Bool.pick(Unit -> Bool, matchParts(firstOf(List<&2, U32>, file, partsLength(head)), head),
    _ => matchGlobstarTail(file, pattern, partsLength(head)),
    _ => False{})(Unit{})

def matchOne(+file: List<&2, List<&2, U32>>, +pattern: List<&2, Part>) -> Bool:
  Bool.pick(Unit -> Bool, hasGlobstar(pattern), _ => matchGlobstar(file, pattern), _ => matchParts(file, pattern))(Unit{})

def matchSet(+file: List<&2, List<&2, U32>>, set: List<&2, List<&2, Part>>) -> Bool:
  match set:
    case Nil{}: False{}
    case pattern <> rest: Bool.pick(Unit -> Bool, matchOne(file, pattern), _ => True{}, _ => matchSet(file, rest))(Unit{})

# `Minimatch.match(path)`.
def test(matcher: Minimatch, path: String) -> Bool:
  match matcher:
    case Comment{}: False{}
    case EmptyPattern{}: String.is_empty(path)
    case Compiled{+negate, set}: Bool.xor(matchSet(slashSplit(units(path)), set), negate)

# `minimatch(path, pattern)` with default options; `Fail` where upstream throws.
def tryMinimatch(path: String, pattern: String) -> Result<&2, &2, Error, Bool>:
  Result.map(&2, &2, Error, Minimatch, Bool, matcher => test(matcher, path), compile(pattern))

def orFalse(result: Result<&2, &2, Error, Bool>) -> Bool:
  match result:
    case Done{value}: value
    case Fail{_}: False{}

# `minimatch(path, pattern)`; patterns upstream rejects match nothing.
def minimatch(path: String, pattern: String) -> Bool: orFalse(tryMinimatch(path, pattern))

def scalarsAll(values: List<&2, List<&2, U32>>, reversed: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: List.reverse(&2, String, reversed)
    case value <> rest: scalarsAll(rest, scalars(value) <> reversed)

# `minimatch.braceExpand(pattern)`.
def braceExpand(pattern: String) -> List<&2, String>: scalarsAll(braceExpandUnits(units(pattern)), Nil{})
