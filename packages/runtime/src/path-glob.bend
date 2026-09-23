import Base
import ./glob.bend as Glob
import ./case-fold.bend as Fold
import ./stable-sort.bend as Sort

# Path glob programs use a linear reachability row, including brace branches.
# '*' and '?' cannot cross '/', '**' can, and no alternative expansion occurs.
type Error is Data:
  DanglingEscape{}
  UnterminatedClass{}
  ReversedRange{}
  UnopenedAlternatives{}
  UnclosedAlternatives{}
  NestedAlternatives{}

type Token is Data:
  Literal{char: Char}
  Any{}
  Star{}
  CrossStar{}
  Class{negative: Bool, ranges: List<&2,Glob.Range>}
  Prefix{}
  Suffix{}
  Middle{}
  Begin{}
  Choice{}
  End{}

type Pattern is Data:
  Pattern{tokens: List<&2,Token>, insensitive: Bool}

type Parser is Data:
  Outside{reversed: List<&2,Token>}
  Alternatives{outer: List<&2,Token>, branches: List<&2,List<&2,Token>>, reversed: List<&2,Token>}

type ParsedClass is Data:
  ParsedClass{token: Token, rest: String}

def inRange(+char: Char, ranges: List<&2,Glob.Range>) -> Bool:
  Glob.inRanges(char,ranges)
def foldedInRange(chars: List<&2,Char>, +ranges: List<&2,Glob.Range>) -> Bool:
  match chars:
    case Nil{}: False{}
    case char <> rest: inRange(char,ranges) || foldedInRange(rest,ranges)

def accepts(token: Token, +char: Char, +insensitive: Bool) -> Bool:
  match token:
    case Literal{+literal}: Bool.pick(Unit -> Bool,insensitive,_ => Fold.equal(literal,char),_ => Char.is_eq(literal,char))(Unit{})
    case Any{}: Bool.not(Char.is_eq(char,'/'))
    case Star{}: Bool.not(Char.is_eq(char,'/'))
    case CrossStar{}: True{}
    case Class{negative,+ranges}:
      +found = Bool.pick(Unit -> Bool,insensitive,_ => foldedInRange(Fold.variants(char),ranges),_ => inRange(char,ranges))(Unit{})
      Bool.pick(Bool,negative,Bool.not(found),found)
    case _: False{}

# Parser rows store reversed tokens; helper appends never duplicate patterns.
def push(state: Parser, token: Token) -> Parser:
  match state:
    case Outside{tokens}: Outside{token <> tokens}
    case Alternatives{outer,branches,tokens}: Alternatives{outer,branches,token <> tokens}

def current(state: Parser) -> List<&2,Token>:
  match state:
    case Outside{tokens}: tokens
    case Alternatives{_,_,tokens}: tokens

def replace(state: Parser, tokens: List<&2,Token>) -> Parser:
  match state:
    case Outside{_}: Outside{tokens}
    case Alternatives{outer,branches,_}: Alternatives{outer,branches,tokens}

def appendBranch(branch: List<&2,Token>, branches: List<&2,List<&2,Token>>) -> List<&2,List<&2,Token>>:
  match branch:
    case Nil{}: branches
    case values: List.reverse(&2,Token,values) <> branches

def separated(branches: List<&2,List<&2,Token>>) -> List<&2,Token>:
  match branches:
    case Nil{}: Nil{}
    case last <> Nil{}: last
    case first <> rest: List.append(&2,Token,first,Choice{} <> separated(rest))

def close(state: Parser) -> Result<&2,&2,Error,Parser>:
  match state:
    case Outside{_}: Fail{UnopenedAlternatives{}}
    case Alternatives{outer,+branches,+tokens}:
      +choices = appendBranch(tokens,branches)
      compiled = Bool.pick(Unit -> List<&2,Token>,List.is_empty(&2,List<&2,Token>,choices),_ => Nil{},_ => Begin{} <> List.append(&2,Token,separated(List.reverse(&2,List<&2,Token>,choices)),End{} <> Nil{}))(Unit{})
      Done{Outside{List.append(&2,Token,List.reverse(&2,Token,compiled),outer)}}

def open(state: Parser) -> Result<&2,&2,Error,Parser>:
  match state:
    case Outside{tokens}: Done{Alternatives{tokens,Nil{},Nil{}}}
    case Alternatives{_,_,_}: Fail{NestedAlternatives{}}

def comma(state: Parser) -> Parser:
  match state:
    case Outside{tokens}: Outside{Literal{','} <> tokens}
    case Alternatives{outer,branches,tokens}: Alternatives{outer,appendBranch(tokens,branches),Nil{}}

def range(+first: U32, +last: U32, previous: List<&2,Glob.Range>) -> Result<&2,&2,Error,List<&2,Glob.Range>>:
  Bool.pick(Result<&2,&2,Error,List<&2,Glob.Range>>,U32.is_le(first,last),Done{Glob.Range{first,last} <> previous},Fail{ReversedRange{}})

def rangeEnd(ranges: List<&2,Glob.Range>, last: U32) -> Result<&2,&2,Error,List<&2,Glob.Range>>:
  match ranges:
    case Glob.Range{first,_} <> rest: range(first,last,rest)
    case Nil{}: Fail{ReversedRange{}}

def classRun(text: String, +negative: Bool, first: Bool, pending: Bool, ranges: List<&2,Glob.Range>) -> Result<&2,&2,Error,ParsedClass>:
  match text first pending:
    case SNil{} _ _: Fail{UnterminatedClass{}}
    case SCon{']',rest} False{} False{}: Done{ParsedClass{Class{negative,ranges},rest}}
    case SCon{']',rest} False{} True{}: Done{ParsedClass{Class{negative,Glob.Range{45,45} <> ranges},rest}}
    case SCon{'-',rest} False{} False{}: classRun(rest,negative,False{},True{},ranges)
    case SCon{Chr{code},rest} _ True{}:
      Result.bind(&2,&2,Error,List<&2,Glob.Range>,ParsedClass,rangeEnd(ranges,code),updated => classRun(rest,negative,False{},False{},updated))
    case SCon{Chr{code},rest} _ False{}:
      +code = {code: U32}
      classRun(rest,negative,False{},False{},Glob.Range{code,code} <> ranges)

def readClass(text: String) -> Result<&2,&2,Error,ParsedClass>:
  match text:
    case SCon{'!',rest}: classRun(rest,True{},True{},False{},Nil{})
    case SCon{'^',rest}: classRun(rest,True{},True{},False{},Nil{})
    case value: classRun(value,False{},True{},False{},Nil{})

def boundary(tokens: List<&2,Token>) -> Bool:
  match tokens:
    case Nil{}: True{}
    case Literal{'/'} <> _: True{}
    case Prefix{} <> _: True{}
    case Middle{} <> _: True{}
    case _: False{}

def recursive(tokens: List<&2,Token>, suffix: Bool) -> List<&2,Token>:
  match tokens:
    case Nil{}: Prefix{} <> Nil{}
    case Prefix{} <> rest: Prefix{} <> rest
    case Middle{} <> rest: Bool.pick(Token,suffix,Suffix{},Middle{}) <> rest
    case Literal{'/'} <> rest: Bool.pick(Token,suffix,Suffix{},Middle{}) <> rest
    case values: Star{} <> values

type Stars is Data:
  Stars{state: Parser, rest: String}

def alternateSuffix(state: Parser) -> Bool:
  match state:
    case Alternatives{_,_,Nil{}}: False{}
    case Alternatives{_,_,_}: True{}
    case _: False{}

def doubleStar(text: String, +state: Parser) -> Stars:
  match text:
    case SNil{}: Stars{replace(state,recursive(current(state),True{})),""}
    case SCon{'/',rest}: Stars{replace(state,recursive(current(state),False{})),rest}
    case SCon{'}',rest}: Stars{Bool.pick(Unit -> Parser,alternateSuffix(state),_ => replace(state,recursive(current(state),True{})),_ => push(state,Star{}))(Unit{}),SCon{'}',rest}}
    case SCon{',',rest}: Stars{Bool.pick(Unit -> Parser,alternateSuffix(state),_ => replace(state,recursive(current(state),True{})),_ => push(state,Star{}))(Unit{}),SCon{',',rest}}
    case value: Stars{push(state,Star{}),value}

def star(text: String, +state: Parser) -> Stars:
  match text:
    case SCon{'*',+rest}:
      Bool.pick(Unit -> Stars,boundary(current(state)),_ => doubleStar(rest,state),_ => Stars{push(state,Star{}),rest})(Unit{})
    case value: Stars{push(state,Star{}),value}

def expand(tokens: List<&2,Token>, reversed: List<&2,Token>) -> List<&2,Token>:
  match tokens:
    case Nil{}: List.reverse(&2,Token,reversed)
    case Prefix{} <> rest: expand(rest,End{} <> Literal{'/'} <> CrossStar{} <> Choice{} <> Begin{} <> reversed)
    case Suffix{} <> rest: expand(rest,CrossStar{} <> Literal{'/'} <> reversed)
    case Middle{} <> rest: expand(rest,End{} <> Literal{'/'} <> CrossStar{} <> Choice{} <> Begin{} <> Literal{'/'} <> reversed)
    case token <> rest: expand(rest,token <> reversed)

def finish(state: Parser) -> Result<&2,&2,Error,List<&2,Token>>:
  match state:
    case Alternatives{_,_,_}: Fail{UnclosedAlternatives{}}
    case Outside{Prefix{} <> Nil{}}: Done{CrossStar{} <> Nil{}}
    case Outside{tokens}: Done{expand(List.reverse(&2,Token,tokens),Nil{})}

def starsText(value: Stars) -> String:
  match value:
    case Stars{_,rest}: rest

def starsState(value: Stars) -> Parser:
  match value:
    case Stars{state,_}: state

def classRest(value: ParsedClass) -> String:
  match value:
    case ParsedClass{_,rest}: rest

def classToken(value: ParsedClass) -> Token:
  match value:
    case ParsedClass{token,_}: token

def scan(fuel: Nat, text: String, state: Parser) -> Result<&2,&2,Error,List<&2,Token>>:
  match fuel text:
    case _ SNil{}: finish(state)
    case Zero{} _: Fail{UnclosedAlternatives{}}
    case Succ{left} SCon{Chr{92},SNil{}}: Fail{DanglingEscape{}}
    case Succ{left} SCon{Chr{92},SCon{char,rest}}: scan(left,rest,push(state,Literal{char}))
    case Succ{left} SCon{'?',rest}: scan(left,rest,push(state,Any{}))
    case Succ{left} SCon{'*',rest}:
      +parsed = star(rest,state)
      scan(left,starsText(parsed),starsState(parsed))
    case Succ{left} SCon{'[',rest}: Result.bind(&2,&2,Error,ParsedClass,List<&2,Token>,readClass(rest),+parsed => scan(left,classRest(parsed),push(state,classToken(parsed))))
    case Succ{left} SCon{'{',rest}: Result.bind(&2,&2,Error,Parser,List<&2,Token>,open(state),next => scan(left,rest,next))
    case Succ{left} SCon{'}',rest}: Result.bind(&2,&2,Error,Parser,List<&2,Token>,close(state),next => scan(left,rest,next))
    case Succ{left} SCon{',',rest}: scan(left,rest,comma(state))
    case Succ{left} SCon{char,rest}: scan(left,rest,push(state,Literal{char}))

def rangeBefore(a: Glob.Range, b: Glob.Range) -> Bool:
  match a b:
    case Glob.Range{first,_} Glob.Range{second,_}: U32.is_le(first,second)

def positiveUppercase(ranges: List<&2,Glob.Range>) -> Bool:
  match ranges:
    case Nil{}: False{}
    case Glob.Range{first,last} <> rest:
      Fold.isUppercase(Chr{first}) || Fold.isUppercase(Chr{last}) || positiveUppercase(rest)

def negativeUppercase(ranges: List<&2,Glob.Range>, +start: U32) -> Bool:
  match ranges:
    case Nil{}: U32.is_le(start,1114111) && Fold.isUppercase(Chr{start})
    case Glob.Range{+first,+last} <> rest:
      gap = U32.is_lt(start,first) && (Fold.isUppercase(Chr{start}) || Fold.isUppercase(Chr{(first - 1 : U32)}))
      gap || negativeUppercase(rest,U32.max(start,(last + 1 : U32)))

def smartCase(tokens: List<&2,Token>) -> Bool:
  match tokens:
    case Nil{}: False{}
    case Literal{char} <> rest: Fold.isUppercase(char) || smartCase(rest)
    case Class{False{},ranges} <> rest: positiveUppercase(ranges) || smartCase(rest)
    case Class{True{},ranges} <> rest: negativeUppercase(Sort.sort(~Glob.Range,~rangeBefore,ranges),0) || smartCase(rest)
    case _ <> rest: smartCase(rest)

def compile(+text: String) -> Result<&2,&2,Error,Pattern>:
  Result.map(&2,&2,Error,List<&2,Token>,Pattern,+tokens => Pattern{tokens,Bool.not(smartCase(tokens))},scan(Succ{Glob.textLength(text)},text,Outside{Nil{}}))

# Branch frames collect exits without materializing products of alternatives.
type Branch is Data:
  Branch{entry: Bool, exits: Bool}
type Row is Data:
  Row{reachable: Bool, branches: List<&2,Branch>}

def epsilon(token: Token, +left: Bool, branches: List<&2,Branch>) -> Row:
  match token branches:
    case Begin{} previous: Row{left,Branch{left,False{}} <> previous}
    case Choice{} Branch{+entry,exits} <> rest: Row{entry,Branch{entry,exits || left} <> rest}
    case End{} Branch{_,exits} <> rest: Row{left || exits,rest}
    case _ previous: Row{left,previous}

def isEmpty(token: Token) -> Bool:
  match token:
    case Star{}: True{}
    case CrossStar{}: True{}
    case Begin{}: True{}
    case Choice{}: True{}
    case End{}: True{}
    case _: False{}

def reachable(value: Row) -> Bool:
  match value:
    case Row{left,_}: left

def initial(tokens: List<&2,Token>, state: Row, reversed: List<&2,Bool>) -> List<&2,Bool>:
  match tokens state:
    case Nil{} Row{_,_}: List.reverse(&2,Bool,reversed)
    case +token <> rest Row{+left,branches}:
      +next = epsilon(token,Bool.pick(Bool,isEmpty(token),left,False{}),branches)
      initial(rest,next,reachable(next) <> reversed)

def advance(token: Token, before: Bool, after: Bool, +left: Bool, char: Char, insensitive: Bool, branches: List<&2,Branch>) -> Row:
  match token:
    case Star{}: Row{left || (after && accepts(Star{},char,insensitive)),branches}
    case CrossStar{}: Row{left || after,branches}
    case Begin{}: epsilon(Begin{},left,branches)
    case Choice{}: epsilon(Choice{},left,branches)
    case End{}: epsilon(End{},left,branches)
    case value: Row{Bool.pick(Unit -> Bool,before,_ => accepts(value,char,insensitive),_ => False{})(Unit{}),branches}

def row(tokens: List<&2,Token>, previous: List<&2,Bool>, before: Bool, state: Row, +char: Char, +insensitive: Bool, reversed: List<&2,Bool>) -> List<&2,Bool>:
  match tokens previous state:
    case Nil{} _ _: List.reverse(&2,Bool,reversed)
    case token <> rest +after <> tail Row{left,branches}:
      +next = advance(token,before,after,left,char,insensitive,branches)
      row(rest,tail,after,next,char,insensitive,reachable(next) <> reversed)
    case _ Nil{} _: Nil{}

def last(values: List<&2,Bool>, answer: Bool) -> Bool:
  match values:
    case Nil{}: answer
    case value <> rest: last(rest,value)

def run(text: String, +tokens: List<&2,Token>, +insensitive: Bool, states: List<&2,Bool>, start: Bool) -> Bool:
  match text:
    case SNil{}: last(states,start)
    case SCon{char,rest}: run(rest,tokens,insensitive,row(tokens,states,start,Row{False{},Nil{}},char,insensitive,Nil{}),False{})

def variable(tokens: List<&2,Token>) -> Bool:
  match tokens:
    case Nil{}: False{}
    case Star{} <> _: True{}
    case CrossStar{} <> _: True{}
    case Begin{} <> _: True{}
    case _ <> rest: variable(rest)

def fixed(tokens: List<&2,Token>, text: String, +insensitive: Bool) -> Bool:
  match tokens text:
    case Nil{} SNil{}: True{}
    case token <> rest SCon{char,tail}:
      Bool.pick(Unit -> Bool,accepts(token,char,insensitive),_ => fixed(rest,tail,insensitive),_ => False{})(Unit{})
    case _ _: False{}

def matches(pattern: Pattern, text: String) -> Bool:
  match pattern:
    case Pattern{+tokens,+insensitive}:
      +text = {text: String}
      Bool.pick(Unit -> Bool,variable(tokens),_ => run(text,tokens,insensitive,initial(tokens,Row{True{},Nil{}},Nil{}),True{}),_ => fixed(tokens,text,insensitive))(Unit{})
