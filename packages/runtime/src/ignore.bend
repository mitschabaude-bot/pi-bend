import Base
import ./glob.bend as G
import ./string.bend as S
import ./case-fold.bend as CaseFold

# Immutable gitignore rules. Components keep ordinary stars separate from **;
# ordered evaluation of every ancestor prevents reopening an excluded parent.
type Error is Data:
  InvalidPattern{pattern: String, cause: G.Error}
  InvalidPath{path: String}

type Component is Data:
  Segment{pattern: G.Pattern}
  Recursive{}

type Rule is Data:
  Rule{negative: Bool, directoryOnly: Bool, components: List<&2,Component>}

type Matcher is Data:
  Matcher{ignoreCase: Bool, rules: List<&2,Rule>}

type Decision is Data:
  Decision{ignored: Bool, unignored: Bool}

def new(ignoreCase: Bool) -> Matcher: Matcher{ignoreCase,Nil{}}
def empty() -> Matcher: new(True{})

# Fold membership before negating a class; folding range endpoints is unsound.
def equivalentInRanges(chars: List<&2,Char>,+ranges: List<&2,G.Range>) -> Bool:
  match chars:
    case Nil{}: False{}
    case char <> rest:
      Bool.pick(Unit -> Bool,G.inRanges(char,ranges),_ => True{},_ => equivalentInRanges(rest,ranges))(Unit{})
def tokenMatches(insensitive: Bool,token: G.Token,+char: Char) -> Bool:
  match token:
    case G.Literal{+literal}:
      Bool.pick(Unit -> Bool,insensitive,_ => CaseFold.equal(literal,char),_ => Char.is_eq(literal,char))(Unit{})
    case G.Set{negative,+ranges}:
      +found = Bool.pick(Unit -> Bool,insensitive,_ => equivalentInRanges(CaseFold.variants(char),ranges),_ => G.inRanges(char,ranges))(Unit{})
      Bool.pick(Bool,negative,Bool.not(found),found)
    case _: True{}

# A row holds reachability at each token boundary. Star transitions combine
# consuming another scalar with advancing without consuming; no backtracking.
def initialTail(tokens: List<&2,G.Token>,reachable: Bool,reversed: List<&2,Bool>) -> List<&2,Bool>:
  match tokens:
    case Nil{}: List.reverse(&2,Bool,reversed)
    case G.Star{} <> rest:
      +next = reachable
      initialTail(rest,next,next <> reversed)
    case _ <> rest: initialTail(rest,False{},False{} <> reversed)
def initial(tokens: List<&2,G.Token>,+reachable: Bool) -> List<&2,Bool>:
  initialTail(tokens,reachable,reachable <> Nil{})
def row(tokens: List<&2,G.Token>, previous: List<&2,Bool>, +char: Char,+insensitive: Bool, before: Bool, left: Bool, reversed: List<&2,Bool>) -> List<&2,Bool>:
  match tokens previous:
    case Nil{} _: List.reverse(&2,Bool,reversed)
    case _ Nil{}: List.reverse(&2,Bool,reversed)
    case G.Star{} <> rest +above <> tail:
      +next = above || left
      row(rest,tail,char,insensitive,above,next,next <> reversed)
    case token <> rest +above <> tail:
      +next = before && tokenMatches(insensitive,token,char)
      row(rest,tail,char,insensitive,above,next,next <> reversed)
def last(values: List<&2,Bool>, answer: Bool) -> Bool:
  match values:
    case Nil{}: answer
    case value <> rest: last(rest,value)
def segmentRun(+tokens: List<&2,G.Token>, text: String,+insensitive: Bool, states: List<&2,Bool>) -> Bool:
  match text states:
    case SNil{} _: last(states,False{})
    case SCon{char,rest} before <> tail:
      segmentRun(tokens,rest,insensitive,row(tokens,tail,char,insensitive,before,False{},False{} <> Nil{}))
    case _ Nil{}: False{}
def hasStar(tokens: List<&2,G.Token>) -> Bool:
  match tokens:
    case Nil{}: False{}
    case G.Star{} <> _: True{}
    case _ <> rest: hasStar(rest)
def fixedSegment(tokens: List<&2,G.Token>,text: String,+insensitive: Bool) -> Bool:
  match tokens text:
    case Nil{} SNil{}: True{}
    case token <> rest SCon{char,tail}:
      Bool.pick(Unit -> Bool,tokenMatches(insensitive,token,char),_ => fixedSegment(rest,tail,insensitive),_ => False{})(Unit{})
    case _ _: False{}
def segment(pattern: G.Pattern,+text: String,+insensitive: Bool) -> Bool:
  match pattern:
    case G.Pattern{+tokens}:
      Bool.pick(Unit -> Bool,hasStar(tokens),_ => segmentRun(tokens,text,insensitive,initial(tokens,True{})),_ => fixedSegment(tokens,text,insensitive))(Unit{})

def componentInitialTail(components: List<&2,Component>,reachable: Bool,reversed: List<&2,Bool>) -> List<&2,Bool>:
  match components:
    case Nil{}: List.reverse(&2,Bool,reversed)
    case Recursive{} <> rest:
      +next = reachable
      componentInitialTail(rest,next,next <> reversed)
    case _ <> rest: componentInitialTail(rest,False{},False{} <> reversed)
def componentInitial(components: List<&2,Component>,+reachable: Bool) -> List<&2,Bool>:
  componentInitialTail(components,reachable,reachable <> Nil{})
def componentRow(components: List<&2,Component>,previous: List<&2,Bool>,+text: String,+insensitive: Bool,before: Bool,left: Bool,reversed: List<&2,Bool>) -> List<&2,Bool>:
  match components previous:
    case Nil{} _: List.reverse(&2,Bool,reversed)
    case _ Nil{}: List.reverse(&2,Bool,reversed)
    case Recursive{} <> rest +above <> tail:
      +next = above || left
      componentRow(rest,tail,text,insensitive,above,next,next <> reversed)
    case Segment{pattern} <> rest +above <> tail:
      +next = before && segment(pattern,text,insensitive)
      componentRow(rest,tail,text,insensitive,above,next,next <> reversed)
# Carry each rule's automaton through the path once. Parent checks reuse these
# states rather than rebuilding and rematching every prefix.
type Cursor is Data:
  Cursor{negative: Bool, directoryOnly: Bool, components: List<&2,Component>, states: List<&2,Bool>}
type WalkState is Data:
  WalkState{cursors: List<&2,Cursor>, decision: Maybe<&2,Decision>}
def initialCursors(rules: List<&2,Rule>,reversed: List<&2,Cursor>) -> List<&2,Cursor>:
  match rules:
    case Nil{}: List.reverse(&2,Cursor,reversed)
    case Rule{negative,only,+components} <> rest:
      initialCursors(rest,Cursor{negative,only,components,componentInitial(components,True{})} <> reversed)
def selected(previous: Maybe<&2,Decision>,matches: Bool,+negative: Bool) -> Maybe<&2,Decision>:
  match previous:
    case Some{decision}: Some{decision}
    case None{}: Bool.pick(Maybe<&2,Decision>,matches,Some{Decision{Bool.not(negative),negative}},None{})
def advanceCursors(cursors: List<&2,Cursor>,+text: String,+directory: Bool,+insensitive: Bool,reversed: List<&2,Cursor>,decision: Maybe<&2,Decision>) -> WalkState:
  match cursors:
    case Nil{}: WalkState{List.reverse(&2,Cursor,reversed),decision}
    case Cursor{+negative,+only,+components,before <> tail} <> rest:
      +next = componentRow(components,tail,text,insensitive,before,False{},False{} <> Nil{})
      advanceCursors(rest,text,directory,insensitive,Cursor{negative,only,components,next} <> reversed,
        selected(decision,(Bool.not(only) || directory) && last(next,False{}),negative))
    case Cursor{negative,only,components,Nil{}} <> rest:
      advanceCursors(rest,text,directory,insensitive,Cursor{negative,only,components,Nil{}} <> reversed,decision)
def walk(parts: List<&2,String>,state: WalkState,+directory: Bool,+insensitive: Bool) -> Decision:
  match parts state:
    case Nil{} WalkState{_,decision}: Maybe.default(&2,Decision,decision,Decision{False{},False{}})
    case _ WalkState{_,Some{Decision{True{},_}}}: Decision{True{},False{}}
    case part <> Nil{} WalkState{cursors,_}:
      walk(Nil{},advanceCursors(cursors,part,directory,insensitive,Nil{},None{}),directory,insensitive)
    case part <> rest WalkState{cursors,_}:
      walk(rest,advanceCursors(cursors,part,True{},insensitive,Nil{},None{}),directory,insensitive)
def isIgnored(decision: Decision) -> Bool:
  match decision:
    case Decision{ignored,_}: ignored

def validParts(parts: List<&2,String>) -> Bool:
  match parts:
    case Nil{}: True{}
    case "" <> _: False{}
    case "." <> _: False{}
    case ".." <> _: False{}
    case _ <> rest: validParts(rest)
def hasNul(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{0},_}: True{}
    case SCon{_,rest}: hasNul(rest)
def testParts(matcher: Matcher,+original: String,parts: List<&2,String>,directory: Bool) -> Result<&2,&2,Error,Decision>:
  match matcher:
    case Matcher{insensitive,rules}:
      +forward = List.reverse(&2,String,parts)
      Bool.pick(Unit -> Result<&2,&2,Error,Decision>,validParts(forward) && Bool.not(S.equal(original,"")) && Bool.not(hasNul(original)),
        _ => Done{walk(forward,WalkState{initialCursors(rules,Nil{}),None{}},directory,insensitive)},_ => Fail{InvalidPath{original}})(Unit{})
def testSplit(matcher: Matcher,path: String,parts: List<&2,String>) -> Result<&2,&2,Error,Decision>:
  match parts:
    case "" <> rest: testParts(matcher,path,rest,True{})
    case parts: testParts(matcher,path,parts,False{})
def test(matcher: Matcher,+path: String) -> Result<&2,&2,Error,Decision>:
  testSplit(matcher,path,List.reverse(&2,String,S.split(path,'/')))
def ignores(matcher: Matcher,path: String) -> Result<&2,&2,Error,Bool>:
  Result.map(&2,&2,Error,Decision,Bool,isIgnored,test(matcher,path))

# Trim only unescaped trailing ASCII spaces; tabs remain literal.
def oddSlashes(reversed: String,odd: Bool) -> Bool:
  match reversed:
    case SCon{Chr{92},rest}: oddSlashes(rest,Bool.not(odd))
    case _: odd
def trailingSpace(+reversed: String) -> String:
  match reversed:
    case SCon{Chr{92},_}: Bool.pick(String,oddSlashes(reversed,False{}),String.reverse(SCon{Chr{32},reversed}),String.reverse(reversed))
    case SCon{Chr{32},rest}: trailingSpace(rest)
    case _: String.reverse(reversed)
def trailing(reversed: String) -> String:
  match reversed:
    case SCon{Chr{32},rest}: trailingSpace(rest)
    case _: String.reverse(reversed)
def stripCrReversed(text: String) -> String:
  match text:
    case SCon{Chr{13},rest}: String.reverse(rest)
    case reversed: String.reverse(reversed)

def stripCr(text: String) -> String:
  stripCrReversed(String.reverse(text))
def components(parts: List<&2,String>,reversed: List<&2,Component>) -> Result<&2,&2,G.Error,List<&2,Component>>:
  match parts:
    case Nil{}: Done{List.reverse(&2,Component,reversed)}
    case "**" <> Nil{}:
      Done{List.reverse(&2,Component,Recursive{} <> Segment{G.Pattern{G.Star{} <> Nil{}}} <> reversed)}
    case "**" <> rest: components(rest,Recursive{} <> reversed)
    case part <> rest:
      Result.bind(&2,&2,G.Error,G.Pattern,List<&2,Component>,G.compile(part),pattern => components(rest,Segment{pattern} <> reversed))
def compiledRule(original: String,negative: Bool,directory: Bool,anchored: Bool,result: Result<&2,&2,G.Error,List<&2,Component>>) -> Result<&2,&2,Error,Maybe<&2,Rule>>:
  match result:
    case Fail{cause}: Fail{InvalidPattern{original,cause}}
    case Done{+compiled}: Done{Some{Rule{negative,directory,Bool.pick(List<&2,Component>,anchored,compiled,Recursive{} <> compiled)}}}
def finishRule(+original: String,negative: Bool,directory: Bool,anchored: Bool,parts: List<&2,String>) -> Result<&2,&2,Error,Maybe<&2,Rule>>:
  compiledRule(original,negative,directory,anchored,components(parts,Nil{}))
def ruleParts(original: String,negative: Bool,directory: Bool,rooted: Bool,+parts: List<&2,String>) -> Result<&2,&2,Error,Maybe<&2,Rule>>:
  match parts:
    case _ <> Nil{}: finishRule(original,negative,directory,rooted,parts)
    case _: finishRule(original,negative,directory,True{},parts)
# Bracket-aware splitting keeps a slash inside a range from anchoring a rule.
# Normalize git's class syntax to the shared scalar glob token grammar.
type ClassText is Data:
  ClassText{name: String, rest: String}
def classText(text: String,reversed: String) -> Result<&2,&2,G.Error,ClassText>:
  match text:
    case SNil{}: Fail{G.UnterminatedSet{}}
    case SCon{Chr{58},SCon{Chr{93},rest}}: Done{ClassText{String.reverse(reversed),rest}}
    case SCon{char,rest}: classText(rest,SCon{char,reversed})
def classExpansion(name: String) -> Result<&2,&2,G.Error,String>:
  match name:
    case "alnum": Done{"0-9A-Za-z"}
    case "alpha": Done{"A-Za-z"}
    case "blank": Done{" \t"}
    case "cntrl": Done{SCon{Chr{0},SCon{Chr{45},SCon{Chr{31},SCon{Chr{127},SNil{}}}}}}
    case "digit": Done{"0-9"}
    case "graph": Done{"\\!-.0-~"}
    case "lower": Done{"a-z"}
    case "print": Done{" -.0-~"}
    case "punct": Done{"\\!-.:-@\\[-`{-~"}
    case "space": Done{" \t\n\r"}
    case "upper": Done{"A-Z"}
    case "xdigit": Done{"0-9A-Fa-f"}
    case _: Fail{G.EmptySet{}}
def expandedClass(value: ClassText) -> Result<&2,&2,G.Error,ClassText>:
  match value:
    case ClassText{name,rest}:
      Result.map(&2,&2,G.Error,String,ClassText,body => ClassText{body,rest},classExpansion(name))
def classRest(value: ClassText) -> String:
  match value:
    case ClassText{_,rest}: rest
def classBody(value: ClassText) -> String:
  match value:
    case ClassText{body,_}: body
type BracketState is Data:
  Outside{}
  Opening{}
  Negated{}
  Members{}
def memberState(state: BracketState) -> BracketState:
  match state:
    case Outside{}: Outside{}
    case _: Members{}
def partsScan(fuel: Nat,text: String,mode: BracketState,reversed: String,parts: List<&2,String>) -> Result<&2,&2,G.Error,List<&2,String>>:
  match fuel:
    case 0n: Fail{G.UnterminatedSet{}}
    case 1n+n:
      match text mode:
        case SNil{} _: Done{String.reverse(reversed) <> parts}
        case SCon{Chr{92},SCon{Chr{47},rest}} Outside{}: partsScan(n,rest,Outside{},"",String.reverse(reversed) <> parts)
        case SCon{Chr{92},SCon{char,rest}} +m:
          partsScan(n,rest,memberState(m),SCon{char,SCon{Chr{92},reversed}},parts)
        case SCon{Chr{47},rest} Outside{}: partsScan(n,rest,Outside{},"",String.reverse(reversed) <> parts)
        case SCon{Chr{47},rest} _: partsScan(n,rest,Members{},SCon{Chr{47},reversed},parts)
        case SCon{Chr{91},rest} Outside{}: partsScan(n,rest,Opening{},SCon{Chr{91},reversed},parts)
        case SCon{Chr{91},SCon{Chr{58},tail}} _:
          Result.bind(&2,&2,G.Error,ClassText,List<&2,String>,
            Result.bind(&2,&2,G.Error,ClassText,ClassText,classText(tail,""),expandedClass),
            +value => partsScan(n,classRest(value),Members{},String.reverse.go(classBody(value),reversed),parts))
        case SCon{Chr{91},rest} _: partsScan(n,rest,Members{},SCon{Chr{91},SCon{Chr{92},reversed}},parts)
        case SCon{Chr{93},rest} Opening{}: partsScan(n,rest,Members{},SCon{Chr{93},SCon{Chr{92},reversed}},parts)
        case SCon{Chr{93},rest} Negated{}: partsScan(n,rest,Members{},SCon{Chr{93},SCon{Chr{92},reversed}},parts)
        case SCon{Chr{93},rest} _: partsScan(n,rest,Outside{},SCon{Chr{93},reversed},parts)
        case SCon{Chr{94},rest} Opening{}: partsScan(n,rest,Negated{},SCon{Chr{33},reversed},parts)
        case SCon{Chr{33},rest} Opening{}: partsScan(n,rest,Negated{},SCon{Chr{33},reversed},parts)
        case SCon{char,rest} +m:
          partsScan(n,rest,memberState(m),SCon{char,reversed},parts)

def splitParts(original: String,negative: Bool,rooted: Bool,parts: List<&2,String>) -> Result<&2,&2,Error,Maybe<&2,Rule>>:
  match parts:
    case "" <> rest: ruleParts(original,negative,True{},rooted,List.reverse(&2,String,rest))
    case rest: ruleParts(original,negative,False{},rooted,List.reverse(&2,String,rest))
def checkedParts(+original: String,negative: Bool,rooted: Bool,result: Result<&2,&2,G.Error,List<&2,String>>) -> Result<&2,&2,Error,Maybe<&2,Rule>>:
  match result:
    case Fail{cause}: Fail{InvalidPattern{original,cause}}
    case Done{parts}: splitParts(original,negative,rooted,parts)
def splitRule(original: String,negative: Bool,rooted: Bool,+text: String) -> Result<&2,&2,Error,Maybe<&2,Rule>>:
  checkedParts(original,negative,rooted,partsScan(1n+G.textLength(text),text,Outside{},"",Nil{}))
def bodyRule(original: String,negative: Bool,text: String) -> Result<&2,&2,Error,Maybe<&2,Rule>>:
  match text:
    case SNil{}: Done{None{}}
    case SCon{Chr{47},rest}: splitRule(original,negative,True{},rest)
    case _: splitRule(original,negative,False{},text)
def preparedLine(+line: String,text: String) -> Result<&2,&2,Error,Maybe<&2,Rule>>:
  match text:
    case SNil{}: Done{None{}}
    case SCon{Chr{65279},rest}: preparedLine(line,rest)
    case SCon{Chr{35},_}: Done{None{}}
    case SCon{Chr{33},rest}: bodyRule(line,True{},rest)
    case body: bodyRule(line,False{},body)
def compileLine(+line: String) -> Result<&2,&2,Error,Maybe<&2,Rule>>:
  preparedLine(line,trailing(String.reverse(stripCr(line))))
def prependRule(value: Maybe<&2,Rule>,rules: List<&2,Rule>) -> List<&2,Rule>:
  match value:
    case None{}: rules
    case Some{rule}: rule <> rules
def addLines(lines: List<&2,String>,rules: List<&2,Rule>) -> Result<&2,&2,Error,List<&2,Rule>>:
  match lines:
    case Nil{}: Done{rules}
    case line <> rest:
      Result.bind(&2,&2,Error,Maybe<&2,Rule>,List<&2,Rule>,compileLine(line),value => addLines(rest,prependRule(value,rules)))
def add(matcher: Matcher,patterns: List<&2,String>) -> Result<&2,&2,Error,Matcher>:
  match matcher:
    case Matcher{insensitive,rules}:
      Result.map(&2,&2,Error,List<&2,Rule>,Matcher,next => Matcher{insensitive,next},addLines(patterns,rules))
def addText(matcher: Matcher,text: String) -> Result<&2,&2,Error,Matcher>:
  add(matcher,S.split(text,'\n'))

def patternError(cause: G.Error) -> String:
  match cause:
    case G.DanglingEscape{}: "dangling escape"
    case G.UnterminatedSet{}: "unterminated bracket expression"
    case G.EmptySet{}: "empty or unknown character class"
    case G.ReversedRange{}: "reversed character range"
def errorMessage(error: Error) -> String:
  match error:
    case InvalidPath{path}: "Expected a normalized relative path: " ++ path
    case InvalidPattern{pattern,cause}: "Invalid ignore pattern " ++ pattern ++ ": " ++ patternError(cause)
