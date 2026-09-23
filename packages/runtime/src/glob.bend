import Base

# Pure single-string glob matching. Slash and leading dot are ordinary scalars.
type Error is Data:
  DanglingEscape{}
  UnterminatedSet{}
  EmptySet{}
  ReversedRange{}

type Range is Data:
  Range{first: U32, last: U32}

type Token is Data:
  Literal{char: Char}
  Any{}
  Star{}
  Set{negated: Bool, ranges: List<&2, Range>}

type Pattern is Data:
  Pattern{tokens: List<&2, Token>}

type Parser is Data:
  Top{tokens: List<&2, Token>}
  InSet{tokens: List<&2, Token>, negated: Bool, seen: Bool, ranges: List<&2, Range>}
  AfterFirst{tokens: List<&2, Token>, negated: Bool, seen: Bool, ranges: List<&2, Range>, first: U32}
  NeedRange{tokens: List<&2, Token>, negated: Bool, ranges: List<&2, Range>, first: U32}

type Backtrack is Data:
  NoStar{}
  StarState{tokens: List<&2, Token>, text: String}

type MatchState is Data:
  Running{tokens: List<&2, Token>, text: String, star: Backtrack}
  Retrying{star: Backtrack}
  Success{}
  Failure{}

def charBetween(+char: Char, first: U32, last: U32) -> Bool:
  +code = Char.to_u32(char)
  U32.is_ge(code, first) && U32.is_le(code, last)

def addStar(reversed: List<&2, Token>) -> List<&2, Token>:
  match reversed:
    case Star{} <> rest: reversed
    case _: Star{} <> reversed

def setToken(negated: Bool, ranges: List<&2, Range>, tokens: List<&2, Token>) -> Parser:
  Top{Set{negated, List.reverse(&2, Range, ranges)} <> tokens}

def parse(text: String, state: Parser) -> Result<&2, &2, Error, Pattern>:
  match text state:
    case SNil{} Top{tokens}: Done{Pattern{List.reverse(&2, Token, tokens)}}
    case SNil{} _: Fail{UnterminatedSet{}}
    case SCon{Chr{92}, SNil{}} Top{_}: Fail{DanglingEscape{}}
    case SCon{Chr{92}, SCon{char, rest}} Top{tokens}: parse(rest, Top{Literal{char} <> tokens})
    case SCon{Chr{63}, rest} Top{tokens}: parse(rest, Top{Any{} <> tokens})
    case SCon{Chr{42}, rest} Top{tokens}: parse(rest, Top{addStar(tokens)})
    case SCon{Chr{91}, SCon{Chr{33}, rest}} Top{tokens}: parse(rest, InSet{tokens, True{}, False{}, Nil{}})
    case SCon{Chr{91}, rest} Top{tokens}: parse(rest, InSet{tokens, False{}, False{}, Nil{}})
    case SCon{char, rest} Top{tokens}: parse(rest, Top{Literal{char} <> tokens})

    case SCon{Chr{93}, rest} InSet{tokens, negated, True{}, ranges}: parse(rest, setToken(negated, ranges, tokens))
    case SCon{Chr{93}, _} InSet{_, _, False{}, _}: Fail{EmptySet{}}
    case SCon{Chr{92}, SNil{}} InSet{_, _, _, _}: Fail{DanglingEscape{}}
    case SCon{Chr{92}, SCon{Chr{code}, rest}} InSet{tokens, negated, seen, ranges}: parse(rest, AfterFirst{tokens, negated, seen, ranges, code})
    case SCon{Chr{code}, rest} InSet{tokens, negated, seen, ranges}: parse(rest, AfterFirst{tokens, negated, seen, ranges, code})

    case SCon{Chr{93}, rest} AfterFirst{tokens, negated, _, ranges, +first}: parse(rest, setToken(negated, Range{first, first} <> ranges, tokens))
    case SCon{Chr{45}, rest} AfterFirst{tokens, negated, _, ranges, first}: parse(rest, NeedRange{tokens, negated, ranges, first})
    case SCon{Chr{92}, SNil{}} AfterFirst{_, _, _, _, _}: Fail{DanglingEscape{}}
    case SCon{Chr{92}, SCon{Chr{code}, rest}} AfterFirst{tokens, negated, _, ranges, +first}: parse(rest, AfterFirst{tokens, negated, True{}, Range{first, first} <> ranges, code})
    case SCon{Chr{code}, rest} AfterFirst{tokens, negated, _, ranges, +first}: parse(rest, AfterFirst{tokens, negated, True{}, Range{first, first} <> ranges, code})

    case SNil{} NeedRange{_, _, _, _}: Fail{UnterminatedSet{}}
    case SCon{Chr{93}, rest} NeedRange{tokens, negated, ranges, +first}: parse(rest, setToken(negated, Range{45, 45} <> Range{first, first} <> ranges, tokens))
    case SCon{Chr{92}, SNil{}} NeedRange{_, _, _, _}: Fail{DanglingEscape{}}
    case SCon{Chr{92}, SCon{Chr{last}, rest}} NeedRange{tokens, negated, ranges, first}: parse(rest, InSet{tokens, negated, True{}, Range{first, last} <> ranges})
    case SCon{Chr{last}, rest} NeedRange{tokens, negated, ranges, first}: parse(rest, InSet{tokens, negated, True{}, Range{first, last} <> ranges})

def validRanges(ranges: List<&2, Range>) -> Bool:
  match ranges:
    case Nil{}: True{}
    case Range{first, last} <> rest:
      Bool.pick(Unit -> Bool, U32.is_le(first, last), _ => validRanges(rest), _ => False{})(Unit{})

def validTokens(tokens: List<&2, Token>) -> Bool:
  match tokens:
    case Nil{}: True{}
    case Set{_, ranges} <> rest:
      Bool.pick(Unit -> Bool, validRanges(ranges), _ => validTokens(rest), _ => False{})(Unit{})
    case _ <> rest: validTokens(rest)

def checked(result: Result<&2, &2, Error, Pattern>) -> Result<&2, &2, Error, Pattern>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Pattern{+tokens}}: Bool.pick(Result<&2, &2, Error, Pattern>, validTokens(tokens), Done{Pattern{tokens}}, Fail{ReversedRange{}})

def compile(pattern: String) -> Result<&2, &2, Error, Pattern>:
  checked(parse(pattern, Top{Nil{}}))

def inRanges(+char: Char, ranges: List<&2, Range>) -> Bool:
  match ranges:
    case Nil{}: False{}
    case Range{first, last} <> rest:
      Bool.pick(Unit -> Bool, charBetween(char, first, last), _ => True{}, _ => inRanges(char, rest))(Unit{})

def tokenMatches(token: Token, char: Char) -> Bool:
  match token:
    case Literal{value}: Char.is_eq(value, char)
    case Any{}: True{}
    case Star{}: True{}
    case Set{negated, ranges}:
      match negated:
        case True{}: Bool.not(inRanges(char, ranges))
        case False{}: inRanges(char, ranges)

def nextMatch(ok: Bool, rest: List<&2, Token>, tail: String, star: Backtrack) -> MatchState:
  match ok:
    case True{}: Running{rest, tail, star}
    case False{}: Retrying{star}

def retryState(star: Backtrack) -> MatchState:
  match star:
    case NoStar{}: Failure{}
    case StarState{_, SNil{}}: Failure{}
    case StarState{+tokens, SCon{_, +rest}}: Running{tokens, rest, StarState{tokens, rest}}

def endState(text: String, star: Backtrack) -> MatchState:
  match text:
    case SNil{}: Success{}
    case _: Retrying{star}

def consumeState(token: Token, rest: List<&2, Token>, text: String, star: Backtrack) -> MatchState:
  match text:
    case SNil{}: Retrying{star}
    case SCon{char, tail}: nextMatch(tokenMatches(token, char), rest, tail, star)

def runningState(tokens: List<&2, Token>, +text: String, star: Backtrack) -> MatchState:
  match tokens:
    case Nil{}: endState(text, star)
    case Star{} <> +rest:
      Running{rest, text, StarState{rest, text}}
    case token <> rest: consumeState(token, rest, text, star)

def stepState(state: MatchState) -> MatchState:
  match state:
    case Success{}: Success{}
    case Failure{}: Failure{}
    case Retrying{star}: retryState(star)
    case Running{tokens, text, star}: runningState(tokens, text, star)

def matchRun(fuel: Nat, state: MatchState) -> Bool:
  match fuel state:
    case 0n _: False{}
    case 1n+_ Success{}: True{}
    case 1n+_ Failure{}: False{}
    case 1n+more _: matchRun(more, stepState(state))

def tokenLengthGo(tokens: List<&2, Token>, count: Nat) -> Nat:
  match tokens:
    case Nil{}: count
    case _ <> rest: tokenLengthGo(rest, 1n + count)

def tokenLength(tokens: List<&2, Token>) -> Nat:
  tokenLengthGo(tokens, 0n)

def textLengthGo(text: String, count: Nat) -> Nat:
  match text:
    case SNil{}: count
    case SCon{_, rest}: textLengthGo(rest, 1n + count)

def textLength(text: String) -> Nat:
  textLengthGo(text, 0n)

def matchFuel(tokens: List<&2, Token>, text: String) -> Nat:
  Nat.mul(Nat.add(tokenLength(tokens), 2n), Nat.add(textLength(text), 2n))

def matches(pattern: Pattern, +text: String) -> Bool:
  match pattern:
    case Pattern{+tokens}: matchRun(matchFuel(tokens, text), Running{tokens, text, NoStar{}})
