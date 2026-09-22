import Base
import ../../runtime/src/f64.bend as Number
import ../../runtime/src/case-fold.bend as Fold
import ../../runtime/src/text.bend as Space
import ../../runtime/src/stable-sort.bend as Sort

# Matching and scoring operate on Unicode scalars, with Unicode simple folding.
# Lower scores are better; equal scores retain the original item order.
type FuzzyMatch is Data:
  FuzzyMatch{matches: Bool, score: F64}
type Scan is Data:
  Scan{index: F64, last: F64, consecutive: F64, score: F64, boundary: Bool}

def boundary(+char: Char) -> Bool:
  Space.whitespace(Char.to_u32(char)) || Char.is_eq(char,'-') || Char.is_eq(char,'_') || Char.is_eq(char,'.') || Char.is_eq(char,'/') || Char.is_eq(char,':')

def advanced(hit: Bool, nextBoundary: Bool, state: Scan) -> Scan:
  match hit state:
    case False{} Scan{index,last,consecutive,score,_}: Scan{Number.add(index,U32.to_f64(1)),last,consecutive,score,nextBoundary}
    case True{} Scan{+index,+last,+consecutive,score,wordBoundary}:
      +adjacent = F64.is_eq(last,Number.subtract(index,U32.to_f64(1)))
      +run = Bool.pick(F64,adjacent,Number.add(consecutive,U32.to_f64(1)),U32.to_f64(0))
      gap = Bool.pick(F64,F64.is_ge(last,U32.to_f64(0)),Number.multiply(Number.subtract(Number.subtract(index,last),U32.to_f64(1)),U32.to_f64(2)),U32.to_f64(0))
      adjustment = {Bool.pick(F64,adjacent,Number.negate(Number.multiply(run,U32.to_f64(5))),gap): F64}
      adjusted = Number.add(score,adjustment)
      boundaryBonus = {Bool.pick(F64,wordBoundary,U32.to_f64(10),U32.to_f64(0)): F64}
      bonus = Number.subtract(adjusted,boundaryBonus)
      Scan{Number.add(index,U32.to_f64(1)),index,run,Number.add(bonus,Number.multiply(index,Number.divide(U32.to_f64(1),U32.to_f64(10)))),nextBoundary}

def scan(text: String, query: String, state: Scan) -> FuzzyMatch:
  match text query:
    case _ SNil{}: 
      match state:
        case Scan{_,_,_,score,_}: FuzzyMatch{True{},score}
    case SNil{} _: FuzzyMatch{False{},U32.to_f64(0)}
    case SCon{+char,restText} SCon{+wanted,+restQuery}:
      +hit = Fold.equal(wanted,char)
      scan(restText,Bool.pick(String,hit,restQuery,SCon{wanted,restQuery}),advanced(hit,boundary(char),state))

def foldedEqual(left: String,right: String) -> Bool:
  match left right:
    case SNil{} SNil{}: True{}
    case SCon{a,+left} SCon{b,+right}: Bool.pick(Unit -> Bool,Fold.equal(a,b),_ => foldedEqual(left,right),_ => False{})(Unit{})
    case _ _: False{}

def exactBonus(value: FuzzyMatch, exact: Bool) -> FuzzyMatch:
  match value:
    case FuzzyMatch{True{},score}:
      penalty = {Bool.pick(F64,exact,U32.to_f64(100),U32.to_f64(0)): F64}
      FuzzyMatch{True{},Number.subtract(score,penalty)}
    case other: other

def matchQuery(+query: String,+text: String) -> FuzzyMatch:
  match query:
    case SNil{}: FuzzyMatch{True{},U32.to_f64(0)}
    case query: exactBonus(scan(text,query,Scan{U32.to_f64(0),Number.negate(U32.to_f64(1)),U32.to_f64(0),U32.to_f64(0),True{}}),foldedEqual(query,text))

# Swap only two nonempty ASCII letter/digit blocks, after the primary fails.
def blockCharacter(letter: Bool,+char: Char) -> Bool:
  Bool.pick(Bool,letter,Char.is_alpha(char),Char.is_digit(char))
def wholeBlock(+letter: Bool,text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{char,+rest}: Bool.pick(Unit -> Bool,blockCharacter(letter,char),_ => wholeBlock(letter,rest),_ => False{})(Unit{})
def swapBlocks(+letter: Bool,text: String,+reversed: String) -> Maybe<&2,String>:
  match text:
    case SNil{}: None{}
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Maybe<&2,String>,blockCharacter(letter,char),
        _ => swapBlocks(letter,rest,SCon{char,reversed}),
        _ => Bool.pick(Maybe<&2,String>,wholeBlock(Bool.not(letter),SCon{char,rest}),Some{SCon{char,rest} ++ String.reverse(reversed)},None{}))(Unit{})
def swapped(query: String) -> Maybe<&2,String>:
  match query:
    case SNil{}: None{}
    case SCon{+char,+rest}: Bool.pick(Unit -> Maybe<&2,String>,Char.is_alpha(char) || Char.is_digit(char),_ => swapBlocks(Char.is_alpha(char),rest,SCon{char,""}),_ => None{})(Unit{})
def swappedResult(value: FuzzyMatch) -> FuzzyMatch:
  match value:
    case FuzzyMatch{True{},score}: FuzzyMatch{True{},Number.add(score,U32.to_f64(5))}
    case other: other

def fallback(primary: FuzzyMatch,query: String,text: String) -> FuzzyMatch:
  match primary:
    case FuzzyMatch{False{},_}:
      Maybe.default(&2,FuzzyMatch,Maybe.map(&2,String,FuzzyMatch,value => swappedResult(matchQuery(value,text)),swapped(query)),FuzzyMatch{False{},U32.to_f64(0)})
    case other: other

def fuzzyMatch(+query: String,+text: String) -> FuzzyMatch:
  fallback(matchQuery(query,text),query,text)

def tokenEnd(token: String,tokens: List<&2,String>) -> List<&2,String>:
  match token:
    case SNil{}: tokens
    case value: String.reverse(value) <> tokens

def tokens(text: String,+token: String,+result: List<&2,String>) -> List<&2,String>:
  match text:
    case SNil{}: List.reverse(&2,String,tokenEnd(token,result))
    case SCon{+char,+rest}:
      Bool.pick(Unit -> List<&2,String>,Space.whitespace(Char.to_u32(char)) || Char.is_eq(char,'/'),_ => tokens(rest,"",tokenEnd(token,result)),_ => tokens(rest,SCon{char,token},result))(Unit{})

def addScore(total: Maybe<&2,F64>,value: FuzzyMatch) -> Maybe<&2,F64>:
  match total value:
    case Some{score} FuzzyMatch{True{},amount}: Some{Number.add(score,amount)}
    case _ _: None{}
def tokenScore(query: List<&2,String>,+text: String,total: Maybe<&2,F64>) -> Maybe<&2,F64>:
  match query total:
    case _ None{}: None{}
    case Nil{} total: total
    case token <> rest total: tokenScore(rest,text,addScore(total,fuzzyMatch(token,text)))

type Scored<-A: Data> is Data:
  Scored{item: A,score: F64}
def retain(-A: Data,item: A,score: Maybe<&2,F64>,result: List<&2,Scored<A>>) -> List<&2,Scored<A>>:
  match score:
    case None{}: result
    case Some{value}: Scored{item,value} <> result

def ranked(~A: Data,~getText: A -> String,items: List<&2,A>,+query: List<&2,String>,result: List<&2,Scored<A>>) -> List<&2,Scored<A>>:
  match items:
    case Nil{}: List.reverse(&2,Scored<A>,result)
    case +item <> rest: ranked(~A,~getText,rest,query,retain(A,item,tokenScore(query,getText(item),Some{U32.to_f64(0)}),result))
def scoreBefore(-A: Data,left: Scored<A>,right: Scored<A>) -> Bool:
  match left right:
    case Scored{_,a} Scored{_,b}: F64.is_le(a,b)
def unranked(-A: Data,items: List<&2,Scored<A>>,result: List<&2,A>) -> List<&2,A>:
  match items:
    case Nil{}: List.reverse(&2,A,result)
    case Scored{item,_} <> rest: unranked(A,rest,item <> result)

def filtered(~A: Data,~getText: A -> String,items: List<&2,A>,query: List<&2,String>) -> List<&2,A>:
  match query:
    case Nil{}: items
    case query: unranked(A,Sort.sort(~Scored<A>,~(left => right => scoreBefore(A,left,right)),ranked(~A,~getText,items,query,Nil{})),Nil{})

def fuzzyFilter(~A: Data,~getText: A -> String,items: List<&2,A>,query: String) -> List<&2,A>:
  filtered(~A,~getText,items,tokens(query,"",Nil{}))
