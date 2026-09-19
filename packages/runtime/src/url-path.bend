import Base
import ./url-percent.bend as Percent
import ./url-scheme.bend as Scheme
import ./url-query.bend as Query

type Parsed is Data:
  Parsed{segments: List<&2, String>, query: Maybe<&2, String>, fragment: Maybe<&2, String>}

type Segment is Data:
  Current{}
  Parent{}
  Name{value: String}

# Recognize one or two literal/percent-encoded dots with a bounded lexer.
# Longer names stay ordinary segments without decoding other percent escapes.
type DotState is Data:
  Dots{count: U32}
  PercentDot{count: U32}
  HexDot{count: U32}
  NotDots{}

def dotStart(room: Bool, dot: Bool, percent: Bool, count: U32) -> DotState:
  match room dot percent:
    case False{} _ _: NotDots{}
    case True{} True{} _: Dots{(count + 1 : U32)}
    case True{} False{} True{}: PercentDot{count}
    case _ _ _: NotDots{}

def dotHex(valid: Bool, count: U32) -> DotState:
  match valid:
    case True{}: HexDot{count}
    case False{}: NotDots{}

def dotEnd(valid: Bool, count: U32) -> DotState:
  match valid:
    case True{}: Dots{(count + 1 : U32)}
    case False{}: NotDots{}

def dotStep(state: DotState, +char: Char) -> DotState:
  match state:
    case Dots{+count}: dotStart(U32.is_lt(count, 2), Char.is_eq(char, '.'), Char.is_eq(char, '%'), count)
    case PercentDot{count}: dotHex(Char.is_eq(char, '2'), count)
    case HexDot{count}: dotEnd(Char.is_eq(char, 'e') || Char.is_eq(char, 'E'), count)
    case NotDots{}: NotDots{}

def dotCount(text: String, state: DotState) -> Maybe<&2, U32>:
  match text state:
    case _ NotDots{}: None{}
    case SNil{} Dots{count}: Some{count}
    case SNil{} _: None{}
    case SCon{char, rest} previous: dotCount(rest, dotStep(previous, char))

def classified(count: Maybe<&2, U32>, text: String) -> Segment:
  match count:
    case Some{1}: Current{}
    case Some{2}: Parent{}
    case _: Name{Percent.encode(Percent.Path{}, text)}

def segment(+text: String) -> Segment:
  classified(dotCount(text, Dots{0}), text)

def drive(text: String) -> Bool:
  match text:
    case SCon{Chr{code}, SCon{':', SNil{}}}: Scheme.alpha(code)
    case SCon{Chr{code}, SCon{'|', SNil{}}}: Scheme.alpha(code)
    case _: False{}

def normalizedDrive(text: String) -> Bool:
  match text:
    case SCon{Chr{code}, SCon{':', SNil{}}}: Scheme.alpha(code)
    case _: False{}

def normalizeDrive(valid: Bool, text: String) -> String:
  match valid text:
    case True{} SCon{letter, _}: SCon{letter, SCon{':', SNil{}}}
    case _ value: value

def retainedDrive(keep: Bool, value: String) -> List<&2, String>:
  match keep:
    case True{}: value <> Nil{}
    case False{}: Nil{}

# The working path is reversed, so shortening is constant time. A file drive
# root cannot be removed by '..', including when resolving against a base.
def shorten(reversed: List<&2, String>, file: Bool) -> List<&2, String>:
  match reversed:
    case Nil{}: Nil{}
    case +value <> Nil{}: retainedDrive(file && normalizedDrive(value), value)
    case _ <> rest: rest

def trailing(last: Bool, reversed: List<&2, String>) -> List<&2, String>:
  match last:
    case True{}: "" <> reversed
    case False{}: reversed

def appendName(reversed: List<&2, String>, file: Bool, +value: String) -> List<&2, String>:
  match reversed:
    case Nil{}: normalizeDrive(file && drive(value), value) <> Nil{}
    case rest: value <> rest

def push(part: Segment, file: Bool, last: Bool, reversed: List<&2, String>) -> List<&2, String>:
  match part:
    case Current{}: trailing(last, reversed)
    case Parent{}: trailing(last, shorten(reversed, file))
    case Name{value}: appendName(reversed, file, value)

def finish(reversed: List<&2, String>, query: Maybe<&2, String>, fragment: Maybe<&2, String>) -> Parsed:
  Parsed{List.reverse(&2, String, reversed), query, fragment}

def queryResult(result: Query.Parsed, reversed: List<&2, String>) -> Parsed:
  match result:
    case Query.Parsed{value, fragment}: finish(reversed, Some{value}, fragment)

def query(text: String, set: Percent.EncodeSet, reversed: String, segments: List<&2, String>) -> Parsed:
  queryResult(Query.scan(text, set, reversed), segments)

def scan(text: String, +special: Bool, +file: Bool, reversed: String, segments: List<&2, String>) -> Parsed:
  match text special:
    case SNil{} _: finish(push(segment(String.reverse(reversed)), file, True{}, segments), None{}, None{})
    case SCon{'/', rest} isSpecial: scan(rest, isSpecial, file, "", push(segment(String.reverse(reversed)), file, False{}, segments))
    case SCon{'\\', rest} True{}: scan(rest, True{}, file, "", push(segment(String.reverse(reversed)), file, False{}, segments))
    case SCon{'?', rest} isSpecial: query(rest, Query.encodeSet(isSpecial), "", push(segment(String.reverse(reversed)), file, True{}, segments))
    case SCon{'#', rest} _: finish(push(segment(String.reverse(reversed)), file, True{}, segments), None{}, Some{Percent.encode(Percent.Fragment{}, rest)})
    case SCon{char, rest} isSpecial: scan(rest, isSpecial, file, SCon{char, reversed}, segments)

def isFile(scheme: Scheme.Scheme) -> Bool:
  match scheme:
    case Scheme.File{}: True{}
    case _: False{}

# Enter the hierarchical path state, after any leading slash was consumed by
# path-start/relative handling. Existing segments are normalized base segments;
# the caller applies relative-path shortening/reset before entering this state.
def parse(text: String, +scheme: Scheme.Scheme, base: List<&2, String>) -> Parsed:
  scan(text, Scheme.isSpecial(scheme), isFile(scheme), "", List.reverse(&2, String, base))

# Path-start entry after authority parsing. Special schemes always have a path;
# non-special schemes retain an empty segment list until path input occurs.
def startSpecial(text: String, +file: Bool, segments: List<&2, String>) -> Parsed:
  match text:
    case SCon{'/', rest}: scan(rest, True{}, file, "", segments)
    case SCon{'\\', rest}: scan(rest, True{}, file, "", segments)
    case other: scan(other, True{}, file, "", segments)

def startOther(text: String, segments: List<&2, String>) -> Parsed:
  match text:
    case SNil{}: finish(segments, None{}, None{})
    case SCon{'/', rest}: scan(rest, False{}, False{}, "", segments)
    case SCon{'?', rest}: query(rest, Percent.Query{}, "", segments)
    case SCon{'#', rest}: finish(segments, None{}, Some{Percent.encode(Percent.Fragment{}, rest)})
    case other: scan(other, False{}, False{}, "", segments)

def startState(text: String, special: Bool, file: Bool, segments: List<&2, String>) -> Parsed:
  match special:
    case True{}: startSpecial(text, file, segments)
    case False{}: startOther(text, segments)

def start(text: String, +scheme: Scheme.Scheme, base: List<&2, String>) -> Parsed:
  startState(text, Scheme.isSpecial(scheme), isFile(scheme), List.reverse(&2, String, base))
