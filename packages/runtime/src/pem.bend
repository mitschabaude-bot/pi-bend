import Base
import ./base64.bend as Base64
import ./string.bend as Split

# RFC 7468 textual containers. Preamble text and ASCII whitespace are allowed;
# boundaries must match and payloads must be canonical Base64. No legacy headers
# or arbitrary non-Base64 payload characters are silently discarded.
type Block is Data:
  Block{label: String, bytes: List<&2,U32>}

type Error is Data:
  InvalidBoundary{}
  MismatchedLabel{}
  UnterminatedBlock{}
  InvalidPayload{}

type Line is Data:
  Begin{label: String}
  End{label: String}
  Text{text: String}
  Malformed{}

type Parser is Data:
  Outside{blocks: List<&2,Block>}
  Inside{label: String, reversed: String, blocks: List<&2,Block>}

def whitespace(+value: U32) -> Bool:
  U32.is_eq(value,32) || (U32.is_ge(value,9) && U32.is_le(value,13))

def newlines(text: String, reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,rest}:
      newlines(rest,SCon{Bool.pick(Char,Char.is_eq(char,'\r'),'\n',char),reversed})

def trimStart(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{+value},+rest}:
      Bool.pick(Unit -> String,whitespace(value),unit => trimStart(rest),unit => SCon{Chr{value},rest})(Unit{})

def trim(text: String) -> String:
  String.reverse(trimStart(String.reverse(trimStart(text))))

def labelCharacters(text: String, previousSeparator: Bool, valid: Bool) -> Bool:
  match text:
    case SNil{}: valid && Bool.not(previousSeparator)
    case SCon{Chr{+value},rest}:
      +separator = U32.is_eq(value,32) || U32.is_eq(value,45)
      labelCharacters(rest,separator,valid && U32.is_ge(value,32) && U32.is_le(value,126) && Bool.not(separator && previousSeparator))

def validLabel(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+value},rest}: labelCharacters(rest,False{},U32.is_ge(value,33) && U32.is_le(value,126) && Bool.not(U32.is_eq(value,45)))

def boundary(valid: Bool, begin: Bool, +label: String) -> Line:
  match valid:
    case False{}: Malformed{}
    case True{}: Bool.pick(Line,begin,Begin{label},End{label})

def parseBoundary(+line: String, +begin: Bool) -> Line:
  +prefix = Bool.pick(Nat,begin,11n,9n)
  +name = String.take(String.drop(line,prefix),Nat.sub(String.length(line),Nat.add(prefix,5n)))
  boundary(String.starts_with(line,Bool.pick(String,begin,"-----BEGIN ","-----END ")) && String.starts_with(String.reverse(line),"-----") && validLabel(name),begin,name)

def classifyLine(+text: String) -> Line:
  Bool.pick(Unit -> Line,String.starts_with(text,"-----BEGIN"),unit => parseBoundary(text,True{}),unit =>
    Bool.pick(Unit -> Line,String.starts_with(text,"-----END"),unit => parseBoundary(text,False{}),unit => Text{text})(Unit{}))(Unit{})

def payload(text: String, +reversed: String) -> String:
  match text:
    case SNil{}: reversed
    case SCon{Chr{+value},rest}: payload(rest,Bool.pick(String,whitespace(value),reversed,SCon{Chr{value},reversed}))

def decoded(label: String, blocks: List<&2,Block>, result: Result<&2,&2,Base64.Error,List<&2,U32>>) -> Result<&2,&2,Error,Parser>:
  match result:
    case Fail{_}: Fail{InvalidPayload{}}
    case Done{bytes}: Done{Outside{Block{label,bytes} <> blocks}}

def close(matches: Bool, label: String, reversed: String, blocks: List<&2,Block>) -> Result<&2,&2,Error,Parser>:
  match matches:
    case False{}: Fail{MismatchedLabel{}}
    case True{}: decoded(label,blocks,Base64.decode(String.reverse(reversed)))

def advance(state: Parser, next: Line) -> Result<&2,&2,Error,Parser>:
  match state next:
    case Outside{blocks} Begin{label}: Done{Inside{label,"",blocks}}
    case Outside{blocks} Text{_}: Done{Outside{blocks}}
    case Inside{+label,reversed,blocks} End{end}: close(String.eq(label,end),label,reversed,blocks)
    case Inside{label,reversed,blocks} Text{text}: Done{Inside{label,payload(text,reversed),blocks}}
    case _ _: Fail{InvalidBoundary{}}

def finish(state: Parser) -> Result<&2,&2,Error,List<&2,Block>>:
  match state:
    case Outside{blocks}: Done{List.reverse(&2,Block,blocks)}
    case Inside{_,_,_}: Fail{UnterminatedBlock{}}

def scan(lines: List<&2,String>, result: Result<&2,&2,Error,Parser>) -> Result<&2,&2,Error,List<&2,Block>>:
  match lines result:
    case _ Fail{cause}: Fail{cause}
    case Nil{} Done{state}: finish(state)
    case head <> rest Done{state}: scan(rest,advance(state,classifyLine(trim(head))))

def decode(text: String) -> Result<&2,&2,Error,List<&2,Block>>:
  scan(Split.split(newlines(text,""),'\n'),Done{Outside{Nil{}}})
