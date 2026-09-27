import Base
import ../../../core/session-manager.bend as Session
import ../../../../../runtime/src/regex.bend as Regex
import ../../../../../runtime/src/stable-sort.bend as Sort
import ../../../../../runtime/src/text.bend as Text
import ../../../../../tui/src/fuzzy.bend as Fuzzy

type Token is Data: Word{text: String} Phrase{text: String,firstWord: String}
type Query is Data: Tokens{tokens: List<&2,Token>} Pattern{regex: Regex.Regex} Invalid{message: String}
type Ranked is Data: Ranked{session: Session.SessionInfo,score: F64}

def searchText(info: Session.SessionInfo) -> String:
  match info:
    case Session.SessionInfo{_,id,cwd,name,_,_,_,_,_,messages}:
      id ++ " " ++ Maybe.default(&2,String,name,"") ++ " " ++ messages ++ " " ++ cwd
def hasSessionName(info: Session.SessionInfo) -> Bool:
  match info:
    case Session.SessionInfo{_,_,_,name,_,_,_,_,_,_}: Bool.not(String.is_empty(String.trim(Maybe.default(&2,String,name,""))))

def compact(text: String,+space: Bool,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{Chr{+point},+rest}:
      Bool.pick(Unit -> String,Text.whitespace(point),
        _ => compact(rest,True{},reversed),
        _ => compact(rest,False{},SCon{Chr{point},Bool.pick(String,space && Bool.not(String.is_empty(reversed)),SCon{' ',reversed},reversed)}))(Unit{})
def normalizeWhitespaceLower(text: String) -> String: compact(String.to_lower(text),False{},"")

def asciiFirstWord(text: String,+reversed: String) -> String:
  match text:
    case SNil{}: String.to_lower(String.reverse(reversed))
    case SCon{Chr{+point},rest}:
      Bool.pick(Unit -> String,Text.whitespace(point),_ => String.to_lower(String.reverse(reversed)),
        _ => Bool.pick(Unit -> String,U32.is_lt(point,128),_ => asciiFirstWord(rest,SCon{Chr{point},reversed}),_ => "")(Unit{}))(Unit{})
def pushed(buffer: String,quoted: Bool,+tokens: List<&2,Token>) -> List<&2,Token>:
  +word = String.trim(buffer)
  Bool.pick(List<&2,Token>,String.is_empty(word),tokens,Bool.pick(Token,quoted,Phrase{word,asciiFirstWord(word,"")},Word{word}) <> tokens)
def scan(text: String,+quoted: Bool,+buffer: String,+tokens: List<&2,Token>) -> List<&2,Token> & Bool:
  match text:
    case SNil{}: (List.reverse(&2,Token,pushed(buffer,quoted,tokens)),quoted)
    case SCon{'"',+rest}: scan(rest,Bool.not(quoted),"",pushed(buffer,quoted,tokens))
    case SCon{Chr{+point},+rest}:
      Bool.pick(Unit -> List<&2,Token> & Bool,Text.whitespace(point) && Bool.not(quoted),
        _ => scan(rest,quoted,"",pushed(buffer,False{},tokens)),
        _ => scan(rest,quoted,buffer ++ SCon{Chr{point},SNil{}},tokens))(Unit{})
def plain(text: String,+buffer: String,+reversed: List<&2,Token>) -> List<&2,Token>:
  match text:
    case SNil{}: List.reverse(&2,Token,pushed(buffer,False{},reversed))
    case SCon{Chr{+point},+rest}:
      Bool.pick(Unit -> List<&2,Token>,Text.whitespace(point),
        _ => plain(rest,"",pushed(buffer,False{},reversed)),
        _ => plain(rest,buffer ++ SCon{Chr{point},SNil{}},reversed))(Unit{})
def compiled(result: Result<&2,&2,Regex.Error,Regex.Regex>) -> Query:
  match result:
    case Done{regex}: Pattern{regex}
    case Fail{Regex.Syntax{message}}: Invalid{"Invalid regex: " ++ message}
    case Fail{_}: Invalid{"Invalid regex"}
def regexQuery(pattern: String) -> Query: compiled(Regex.compile(pattern,True{}))
def tokenQuery(scanned: List<&2,Token> & Bool,trimmed: String) -> Query:
  match scanned:
    case (_,True{}): Tokens{plain(trimmed,"",Nil{})}
    case (tokens,False{}): Tokens{tokens}
def parseSearchQuery(query: String) -> Query:
  +trimmed = String.trim(query)
  Bool.pick(Unit -> Query,String.starts_with(trimmed,"re:"),
    _ => Bool.pick(Unit -> Query,String.is_empty(String.trim(String.drop(trimmed,3n))),
      _ => Invalid{"Empty regex"},_ => regexQuery(String.trim(String.drop(trimmed,3n))))(Unit{}),
    _ => tokenQuery(scan(trimmed,False{},"",Nil{}),trimmed))(Unit{})

def indexFrom(text: String,+needle: String,+index: Nat) -> Maybe<&2,Nat>:
  match text:
    case SNil{}: Bool.pick(Maybe<&2,Nat>,String.is_empty(needle),Some{index},None{})
    case SCon{+char,+rest}: Bool.pick(Unit -> Maybe<&2,Nat>,String.starts_with(SCon{char,rest},needle),_ => Some{index},_ => indexFrom(rest,needle,index + 1n))(Unit{})
def phrasePosition(+lowered: String,value: String) -> Maybe<&2,Nat>:
  indexFrom(compact(lowered,False{},""),normalizeWhitespaceLower(value),0n)
def fuzzyAmount(found: Fuzzy.FuzzyMatch) -> Maybe<&2,F64>:
  match found:
    case Fuzzy.FuzzyMatch{False{},_}: None{}
    case Fuzzy.FuzzyMatch{True{},amount}: Some{amount}
def tokenScore(tokens: List<&2,Token>,+text: String,+score: F64) -> Maybe<&2,F64>:
  match tokens:
    case Nil{}: Some{score}
    case Word{value} <> rest: Maybe.bind(&2,F64,F64,fuzzyAmount(Fuzzy.fuzzyMatch(value,text)),amount => tokenScore(rest,text,F64.add(score,amount)))
    case Phrase{value,+first} <> rest:
      +lowered = String.to_lower(text)
      Bool.pick(Unit -> Maybe<&2,F64>,String.is_empty(first) || String.contains(lowered,first),
        _ => Maybe.bind(&2,Nat,F64,phrasePosition(lowered,value),index => tokenScore(rest,text,F64.add(score,F64.mul(U32.to_f64(U32.from_nat(index)),F64.div(U32.to_f64(1),U32.to_f64(10)))))),
        _ => None{})(Unit{})
def matchSession(info: Session.SessionInfo,query: Query) -> Maybe<&2,F64>:
  match query:
    case Invalid{_}: None{}
    case Pattern{regex}: Bool.pick(Maybe<&2,F64>,Regex.isMatch(regex,searchText(info)),Some{U32.to_f64(0)},None{})
    case Tokens{tokens}: tokenScore(tokens,searchText(info),U32.to_f64(0))
def problem(query: Query) -> Maybe<&2,String>:
  match query:
    case Invalid{message}: Some{message}
    case _: None{}

def recent(items: List<&2,Session.SessionInfo>,+query: Query) -> List<&2,Session.SessionInfo>:
  match items:
    case Nil{}: Nil{}
    case +info <> +rest:
      Bool.pick(Unit -> List<&2,Session.SessionInfo>,Maybe.is_some(&2,F64,matchSession(info,query)),
        _ => info <> recent(rest,query),_ => recent(rest,query))(Unit{})
def ranked(items: List<&2,Session.SessionInfo>,+query: Query,+reversed: List<&2,Ranked>) -> List<&2,Ranked>:
  match items:
    case Nil{}: List.reverse(&2,Ranked,reversed)
    case +info <> rest:
      ranked(rest,query,Maybe.default(&2,List<&2,Ranked>,Maybe.map(&2,F64,List<&2,Ranked>,score => Ranked{info,score} <> reversed,matchSession(info,query)),reversed))
def modified(info: Session.SessionInfo) -> F64:
  match info: case Session.SessionInfo{_,_,_,_,_,_,modified,_,_,_}: modified
def before(left: Ranked,right: Ranked) -> Bool:
  match left right:
    case Ranked{old,+oldScore} Ranked{new,+newScore}:
      F64.is_lt(oldScore,newScore) || (F64.is_eq(oldScore,newScore) && F64.is_ge(modified(old),modified(new)))
def unrank(items: List<&2,Ranked>) -> List<&2,Session.SessionInfo>:
  match items:
    case Nil{}: Nil{}
    case Ranked{info,_} <> rest: info <> unrank(rest)
def searched(+items: List<&2,Session.SessionInfo>,query: String,relevance: Bool) -> List<&2,Session.SessionInfo>:
  +parsed = parseSearchQuery(query)
  Bool.pick(List<&2,Session.SessionInfo>,relevance,unrank(Sort.sort(~Ranked,~before,ranked(items,parsed,Nil{}))),recent(items,parsed))
def filterAndSortSessions(+items: List<&2,Session.SessionInfo>,query: String,relevance: Bool) -> List<&2,Session.SessionInfo>:
  +trimmed = String.trim(query)
  Bool.pick(Unit -> List<&2,Session.SessionInfo>,String.is_empty(trimmed),_ => items,
    _ => searched(items,trimmed,relevance))(Unit{})
