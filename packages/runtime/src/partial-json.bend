import Base
import ./json-parse.bend as Json
import ./schema-value.bend as V
import ./record.bend as R
import ./f64.bend as F
import ./number-string.bend as Number

# Native implementation of the default recovery mode used by Pi from
# partial-json 0.1.7. See licenses/partial-json.txt for its MIT attribution.
# Containers and cursors are persistent values; no host object semantics apply.
type Error is Data:
  EmptyInput{}
  UnexpectedEnd{}
  MalformedInput{}
  InputLimit{}

type Cursor is Data:
  Cursor{remaining: String, position: Nat}

type Outcome is Data:
  Parsed{value: V.Value, cursor: Cursor}
  Rejected{error: Error, cursor: Cursor}

def advance(cursor: Cursor, +count: Nat) -> Cursor:
  match cursor:
    case Cursor{text, position}: Cursor{String.drop(text, count), position + count}

def skipChars(text: String, position: Nat) -> Cursor:
  match text:
    case SCon{' ', rest}: skipChars(rest, position + 1n)
    case SCon{'\t', rest}: skipChars(rest, position + 1n)
    case SCon{'\n', rest}: skipChars(rest, position + 1n)
    case SCon{'\r', rest}: skipChars(rest, position + 1n)
    case other: Cursor{other, position}

def skip(cursor: Cursor) -> Cursor:
  match cursor:
    case Cursor{text, position}: skipChars(text, position)

def afterValue(cursor: Cursor) -> Cursor:
  match cursor:
    case Cursor{SCon{',', rest}, position}: Cursor{rest, position + 1n}
    case other: other

def parsed(result: Result<&2, &2, Json.Error, V.Value>, cursor: Cursor) -> Outcome:
  match result:
    case Done{value}: Parsed{value, cursor}
    case Fail{_}: Rejected{MalformedInput{}, cursor}

# Drop a final backslash only when it is an unmatched escape introducer.
def closeText(escaped: Bool, reversed: String) -> String:
  match escaped reversed:
    case True{} SCon{'\\', rest}: String.reverse(rest) ++ "\""
    case _ text: String.reverse(text) ++ "\""

def beforeLastSlash(reversed: String) -> Maybe<&2, String>:
  match reversed:
    case SNil{}: None{}
    case SCon{'\\', rest}: Some{String.reverse(rest)}
    case SCon{_, rest}: beforeLastSlash(rest)

def retryString(prefix: Maybe<&2, String>, cursor: Cursor) -> Outcome:
  match prefix:
    case None{}: Rejected{MalformedInput{}, cursor}
    case Some{text}: parsed(Json.parse(text ++ "\""), cursor)

def incompleteString(first: Result<&2, &2, Json.Error, V.Value>, reversed: String, cursor: Cursor) -> Outcome:
  match first:
    case Done{value}: Parsed{value, cursor}
    case Fail{_}: retryString(beforeLastSlash(reversed), cursor)

def nextEscape(+char: Char, escaped: Bool) -> Bool:
  match char:
    case '\\': Bool.not(escaped)
    case _: False{}

def scanString(text: String, +position: Nat, escaped: Bool, +reversed: String) -> Outcome:
  match text escaped:
    case SNil{} value: incompleteString(Json.parse(closeText(value, reversed)), reversed, Cursor{"", position})
    case SCon{'"', rest} False{}: parsed(Json.parse(String.reverse(SCon{'"', reversed})), Cursor{rest, position + 1n})
    case SCon{char, rest} escaped:
      +current = {char : Char}
      scanString(rest, position + 1n, nextEscape(current, escaped), SCon{current, reversed})

def readString(cursor: Cursor) -> Outcome:
  match cursor:
    case Cursor{SNil{}, position}: Rejected{UnexpectedEnd{}, Cursor{"", position + 1n}}
    case Cursor{SCon{char, rest}, position}: scanString(rest, position + 1n, False{}, SCon{char, SNil{}})

def prefix(word: String, text: String) -> Bool:
  match word text:
    case SNil{} _: True{}
    case SCon{Chr{a}, restA} SCon{Chr{b}, restB}: U32.is_eq(a, b) && prefix(restA, restB)
    case _ _: False{}

def wordMatches(+word: String, +text: String) -> Bool:
  prefix(word, text) || prefix(text, word)

def negativeInfinity(text: String) -> Bool:
  match text:
    case SCon{'-', SCon{char, rest}}: wordMatches("Infinity", SCon{char, rest})
    case _: False{}

# Keep the dependency's last-lowercase-e recovery boundary. It can lie beyond
# the current number, so use the original input rather than only the token.
def lastExponent(text: String, +position: Nat, previous: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match text:
    case SNil{}: previous
    case SCon{'e', rest}: lastExponent(rest, position + 1n, Some{position})
    case SCon{_, rest}: lastExponent(rest, position + 1n, previous)

def rangeEnd(value: Maybe<&2, Nat>) -> Nat:
  match value:
    case None{}: 0n
    case Some{position}: position

def orderedRange(ascending: Bool, source: String, +start: Nat, +end: Nat) -> String:
  match ascending:
    case True{}: String.take(String.drop(source, start), end - start)
    case False{}: String.take(String.drop(source, end), start - end)

def between(source: String, +start: Nat, +end: Nat) -> String:
  orderedRange(Nat.is_le(start, end), source, start, end)

def numberFallback(first: Result<&2, &2, Json.Error, V.Value>, text: String, source: String, start: Nat, end: Maybe<&2, Nat>, cursor: Cursor) -> Outcome:
  match first text:
    case Done{value} _: Parsed{value, cursor}
    case Fail{_} "-": Rejected{UnexpectedEnd{}, cursor}
    case Fail{_} _: parsed(Json.parse(between(source, start, rangeEnd(end))), cursor)

def numberEnd(reversed: String, +cursor: Cursor, source: String, start: Nat, lastE: Maybe<&2, Nat>) -> Outcome:
  +text = String.reverse(reversed)
  numberFallback(Json.parse(text), text, source, start, lastE, cursor)

def scanNumber(text: String, position: Nat, reversed: String, source: String, start: Nat, lastE: Maybe<&2, Nat>) -> Outcome:
  match text:
    case SNil{}: numberEnd(reversed, Cursor{"", position}, source, start, lastE)
    case SCon{',', rest}: numberEnd(reversed, Cursor{SCon{',', rest}, position}, source, start, lastE)
    case SCon{']', rest}: numberEnd(reversed, Cursor{SCon{']', rest}, position}, source, start, lastE)
    case SCon{'}', rest}: numberEnd(reversed, Cursor{SCon{'}', rest}, position}, source, start, lastE)
    case SCon{char, rest}: scanNumber(rest, position + 1n, SCon{char, reversed}, source, start, lastE)

def readNumber(cursor: Cursor, +source: String, lastE: Maybe<&2, Nat>) -> Outcome:
  match cursor:
    case Cursor{+text, 0n}: numberFallback(Json.parse(text), text, source, 0n, lastE, Cursor{"", String.length(text)})
    case Cursor{text, +position}: scanNumber(text, position, "", source, position, lastE)

def literal(value: V.Value, text: String, position: Nat, count: Nat) -> Outcome:
  Parsed{value, advance(Cursor{text, position}, count)}

type Literal is Data:
  Literal{value: V.Value, length: Nat}

def recognizedLiteral(+text: String) -> Maybe<&2, Literal>:
  Bool.pick(Maybe<&2, Literal>, wordMatches("null", text), Some{Literal{V.Null{}, 4n}},
  Bool.pick(Maybe<&2, Literal>, wordMatches("true", text), Some{Literal{V.Boolean{True{}}, 4n}},
  Bool.pick(Maybe<&2, Literal>, wordMatches("false", text), Some{Literal{V.Boolean{False{}}, 5n}},
  Bool.pick(Maybe<&2, Literal>, wordMatches("Infinity", text), Some{Literal{V.Number{F.infinity(False{})}, 8n}},
  Bool.pick(Maybe<&2, Literal>, negativeInfinity(text), Some{Literal{V.Number{F.infinity(True{})}, 9n}},
  Bool.pick(Maybe<&2, Literal>, wordMatches("NaN", text), Some{Literal{V.Number{F.nan()}, 3n}}, None{}))))))

def scalarValue(found: Maybe<&2, Literal>, text: String, position: Nat, source: String, lastE: Maybe<&2, Nat>) -> Outcome:
  match found:
    case Some{Literal{value, count}}: literal(value, text, position, count)
    case None{}: readNumber(Cursor{text, position}, source, lastE)

def readScalar(+text: String, position: Nat, source: String, lastE: Maybe<&2, Nat>) -> Outcome:
  scalarValue(recognizedLiteral(text), text, position, source, lastE)

type Frame is Data:
  ArrayFrame{reversed: List<&2, V.Value>}
  ObjectFrame{fields: R.Record<V.Value>, key: String}

type Action is Data:
  Read{cursor: Cursor}
  ReadArray{cursor: Cursor, reversed: List<&2, V.Value>}
  ReadObject{cursor: Cursor, fields: R.Record<V.Value>}
  Deliver{value: V.Value, cursor: Cursor}
  Reject{error: Error, cursor: Cursor}

type Machine is Data:
  Running{action: Action, frames: List<&2, Frame>}
  Finished{result: Result<&2, &2, Error, V.Value>}

def outcomeStep(outcome: Outcome, frames: List<&2, Frame>) -> Machine:
  match outcome:
    case Parsed{value, cursor}: Running{Deliver{value, cursor}, frames}
    case Rejected{error, cursor}: Running{Reject{error, cursor}, frames}

def beginValue(cursor: Cursor, frames: List<&2, Frame>, source: String, lastE: Maybe<&2, Nat>) -> Machine:
  match cursor:
    case Cursor{SNil{}, position}: Running{Reject{UnexpectedEnd{}, Cursor{"", position}}, frames}
    case Cursor{SCon{'"', rest}, position}: outcomeStep(readString(Cursor{SCon{'"', rest}, position}), frames)
    case Cursor{SCon{'[', rest}, position}: Running{ReadArray{Cursor{rest, position + 1n}, Nil{}}, frames}
    case Cursor{SCon{'{', rest}, position}: Running{ReadObject{skip(Cursor{rest, position + 1n}), R.new(V.Value)}, frames}
    case Cursor{text, position}: outcomeStep(readScalar(text, position, source, lastE), frames)

def beginArray(cursor: Cursor, reversed: List<&2, V.Value>, frames: List<&2, Frame>) -> Machine:
  match cursor:
    case Cursor{SCon{']', rest}, position}: Running{Deliver{V.ArrayValue{List.reverse(&2, V.Value, reversed)}, Cursor{rest, position + 1n}}, frames}
    case other: Running{Read{other}, ArrayFrame{reversed} <> frames}

def objectKey(outcome: Outcome, fields: R.Record<V.Value>, frames: List<&2, Frame>) -> Machine:
  match outcome:
    case Parsed{V.Text{key}, cursor}: Running{Read{advance(skip(cursor), 1n)}, ObjectFrame{fields, key} <> frames}
    case Parsed{_, cursor}: Running{Deliver{V.ObjectValue{fields}, cursor}, frames}
    case Rejected{_, cursor}: Running{Deliver{V.ObjectValue{fields}, cursor}, frames}

def readKey(cursor: Cursor, fields: R.Record<V.Value>, frames: List<&2, Frame>) -> Machine:
  match cursor:
    case Cursor{SNil{}, position}: Running{Deliver{V.ObjectValue{fields}, Cursor{"", position}}, frames}
    case other: objectKey(readString(other), fields, frames)

def beginObject(cursor: Cursor, fields: R.Record<V.Value>, frames: List<&2, Frame>) -> Machine:
  match cursor:
    case Cursor{SCon{'}', rest}, position}: Running{Deliver{V.ObjectValue{fields}, Cursor{rest, position + 1n}}, frames}
    case other: readKey(skip(other), fields, frames)

def delivered(value: V.Value, cursor: Cursor, frames: List<&2, Frame>) -> Machine:
  match frames:
    case Nil{}: Finished{Done{value}}
    case ArrayFrame{reversed} <> rest: Running{ReadArray{afterValue(skip(cursor)), value <> reversed}, rest}
    case ObjectFrame{fields, key} <> rest: Running{ReadObject{afterValue(skip(cursor)), R.set(V.Value, fields, key, value)}, rest}

# Each container retains its successfully read members when a later member is
# incomplete or malformed. Recovering a container removes one stack frame.
def rejected(error: Error, cursor: Cursor, frames: List<&2, Frame>) -> Machine:
  match frames:
    case Nil{}: Finished{Fail{error}}
    case ArrayFrame{reversed} <> rest: Running{Deliver{V.ArrayValue{List.reverse(&2, V.Value, reversed)}, cursor}, rest}
    case ObjectFrame{fields, _} <> rest: Running{Deliver{V.ObjectValue{fields}, cursor}, rest}

def step(action: Action, frames: List<&2, Frame>, source: String, lastE: Maybe<&2, Nat>) -> Machine:
  match action:
    case Read{cursor}: beginValue(skip(cursor), frames, source, lastE)
    case ReadArray{cursor, reversed}: beginArray(cursor, reversed, frames)
    case ReadObject{cursor, fields}: beginObject(cursor, fields, frames)
    case Deliver{value, cursor}: delivered(value, cursor, frames)
    case Reject{error, cursor}: rejected(error, cursor, frames)

# Every state consumes input or advances/unwinds one container. Eight steps per
# source character plus a final allowance bounds even fully truncated input.
def run(fuel: Nat, machine: Machine, +source: String, +lastE: Maybe<&2, Nat>) -> Result<&2, &2, Error, V.Value>:
  match fuel machine:
    case _ Finished{result}: result
    case 0n _: Fail{InputLimit{}}
    case 1n+n Running{action, frames}: run(n, step(action, frames, source, lastE), source, lastE)

def parseTrimmed(+text: String) -> Result<&2, &2, Error, V.Value>:
  match text:
    case SNil{}: Fail{EmptyInput{}}
    case other: run(8n * String.length(other) + 16n, Running{Read{Cursor{other, 0n}}, Nil{}}, other, lastExponent(other, 0n, None{}))

def parse(text: String) -> Result<&2, &2, Error, V.Value>:
  parseTrimmed(Number.trim(text))
