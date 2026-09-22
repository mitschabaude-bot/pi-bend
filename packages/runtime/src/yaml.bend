import Base
import ./record.bend as R
import ./string.bend as Strings
import ./number-string.bend as Numbers
import ./f64.bend as F
import ./json.bend as Json

# YAML's immutable data model. Mapping keys used by configuration are strings;
# unsupported schema/tag constructs are explicit errors, never silently skipped.
type Value is Data:
  Null{}
  Boolean{value: Bool}
  Number{value: F64}
  Text{value: String}
  Sequence{values: List<&2,Value>}
  Mapping{fields: R.Record<Value>}
type Error is Data:
  Error{line: Nat,column: Nat,message: String}
def ResultOf(-A: Data) -> Data: Result<&2,&2,Error,A>

def asText(value: Value) -> Maybe<&2,String>:
  match value:
    case Text{value}: Some{value}
    case _: None{}
def errorMessage(error: Error) -> String:
  match error:
    case Error{line,column,message}: message ++ " at line " ++ Nat.show(line) ++ ", column " ++ Nat.show(column)

def trimLeft(value: String) -> String:
  match value:
    case SCon{' ',rest}: trimLeft(rest)
    case SCon{'\t',rest}: trimLeft(rest)
    case SCon{'\n',rest}: trimLeft(rest)
    case SCon{'\r',rest}: trimLeft(rest)
    case other: other

def trim(value: String) -> String: String.reverse(trimLeft(String.reverse(trimLeft(value))))
def length(value: String,count: Nat) -> Nat:
  match value:
    case SNil{}: count
    case SCon{_,rest}: length(rest,1n+count)
def whitespace(char: Char) -> Bool:
  match char:
    case ' ': True{}
    case '\t': True{}
    case '\n': True{}
    case '\r': True{}
    case _: False{}
def digit(+code: U32) -> Bool: U32.is_ge(code,48) && U32.is_le(code,57)
def numericStart(value: String) -> Bool:
  match value:
    case SCon{Chr{code},_}: digit(code)
    case _: False{}
def unsignedDecimal(value: String) -> Bool:
  match value:
    case SCon{'.',rest}: numericStart(rest)
    case other: numericStart(other)
def decimalStart(value: String) -> Bool:
  match value:
    case SCon{'-',rest}: unsignedDecimal(rest)
    case SCon{'+',rest}: unsignedDecimal(rest)
    case SCon{'.',rest}: numericStart(rest)
    case other: numericStart(other)
def scalarNumber(+value: String,+number: F64) -> Value:
  Bool.pick(Value,F.isNaN(number),Text{value},Number{number})
def plain(+value: String) -> Value:
  match value:
    case "": Null{}
    case "~": Null{}
    case "null": Null{}
    case "Null": Null{}
    case "NULL": Null{}
    case "true": Boolean{True{}}
    case "True": Boolean{True{}}
    case "TRUE": Boolean{True{}}
    case "false": Boolean{False{}}
    case "False": Boolean{False{}}
    case "FALSE": Boolean{False{}}
    case ".nan": Number{F.nan()}
    case ".NaN": Number{F.nan()}
    case ".NAN": Number{F.nan()}
    case ".inf": Number{F.infinity(False{})}
    case ".Inf": Number{F.infinity(False{})}
    case ".INF": Number{F.infinity(False{})}
    case "-.inf": Number{F.negate(F.infinity(False{}))}
    case "-.Inf": Number{F.negate(F.infinity(False{}))}
    case "-.INF": Number{F.negate(F.infinity(False{}))}
    case "+.inf": Number{F.infinity(False{})}
    case "+.Inf": Number{F.infinity(False{})}
    case "+.INF": Number{F.infinity(False{})}
    case SCon{'0',SCon{'b',_}}: Text{value}
    case _: Bool.pick(Value,decimalStart(value),scalarNumber(value,Numbers.toNumber(value)),Text{value})

type Quoted is Data:
  Quoted{value: String,remaining: String}
type Escape is Data:
  NoEscape{}
  Escaping{}
  HexEscape{remaining: Nat,value: U32}
type QuoteState is Data:
  QuoteMore{remaining: String,reversed: String,escapeState: Escape}
  QuoteDone{value: Quoted}
  QuoteError{message: String}

def scalarCode(+code: U32) -> Bool:
  U32.is_le(code,1114111) && Bool.not(U32.is_ge(code,55296) && U32.is_le(code,57343))
def escapedHex(digit: Maybe<&2,U32>,remaining: Nat,code: U32,rest: String,reversed: String) -> QuoteState:
  match digit remaining:
    case None{} _: QuoteError{"Invalid hexadecimal escape"}
    case Some{value} 0n:
      +point = (code * 16 + value : U32)
      Bool.pick(Unit -> QuoteState,scalarCode(point),_ => QuoteMore{rest,SCon{Chr{point},reversed},NoEscape{}},_ => QuoteError{"Escape is not a Unicode scalar"})(Unit{})
    case Some{value} 1n+n: QuoteMore{rest,reversed,HexEscape{n,(code * 16 + value : U32)}}
def escapeCharacter(code: U32,rest: String,reversed: String) -> QuoteState:
  match code:
    case 48: QuoteMore{rest,SCon{Chr{0},reversed},NoEscape{}}
    case 97: QuoteMore{rest,SCon{Chr{7},reversed},NoEscape{}}
    case 98: QuoteMore{rest,SCon{Chr{8},reversed},NoEscape{}}
    case 116: QuoteMore{rest,SCon{'\t',reversed},NoEscape{}}
    case 110: QuoteMore{rest,SCon{'\n',reversed},NoEscape{}}
    case 118: QuoteMore{rest,SCon{Chr{11},reversed},NoEscape{}}
    case 102: QuoteMore{rest,SCon{Chr{12},reversed},NoEscape{}}
    case 114: QuoteMore{rest,SCon{'\r',reversed},NoEscape{}}
    case 101: QuoteMore{rest,SCon{Chr{27},reversed},NoEscape{}}
    case 32: QuoteMore{rest,SCon{' ',reversed},NoEscape{}}
    case 34: QuoteMore{rest,SCon{'"',reversed},NoEscape{}}
    case 47: QuoteMore{rest,SCon{'/',reversed},NoEscape{}}
    case 92: QuoteMore{rest,SCon{'\\',reversed},NoEscape{}}
    case 78: QuoteMore{rest,SCon{Chr{133},reversed},NoEscape{}}
    case 95: QuoteMore{rest,SCon{Chr{160},reversed},NoEscape{}}
    case 76: QuoteMore{rest,SCon{Chr{8232},reversed},NoEscape{}}
    case 80: QuoteMore{rest,SCon{Chr{8233},reversed},NoEscape{}}
    case 120: QuoteMore{rest,reversed,HexEscape{1n,0}}
    case 117: QuoteMore{rest,reversed,HexEscape{3n,0}}
    case 85: QuoteMore{rest,reversed,HexEscape{7n,0}}
    case 10: QuoteMore{trimLeft(rest),reversed,NoEscape{}}
    case _: QuoteError{"Invalid quoted escape"}
def singleQuote(rest: String,reversed: String) -> QuoteState:
  match rest:
    case SCon{'\'',tail}: QuoteMore{tail,SCon{'\'',reversed},NoEscape{}}
    case other: QuoteDone{Quoted{String.reverse(reversed),other}}
def quoteStep(remaining: String,escapeState: Escape,delimiter: Char,reversed: String) -> QuoteState:
  match remaining escapeState delimiter:
    case SNil{} _ _: QuoteError{"Unterminated quoted scalar"}
    case SCon{Chr{code},rest} HexEscape{n,value} _: escapedHex(Json.hexDigit(code),n,value,rest,reversed)
    case SCon{Chr{code},rest} Escaping{} _: escapeCharacter(code,rest,reversed)
    case SCon{'\'',rest} NoEscape{} '\'': singleQuote(rest,reversed)
    case SCon{'"',rest} NoEscape{} '"': QuoteDone{Quoted{String.reverse(reversed),rest}}
    case SCon{'\\',rest} NoEscape{} '"': QuoteMore{rest,reversed,Escaping{}}
    case SCon{'\n',rest} NoEscape{} _: QuoteMore{trimLeft(rest),SCon{' ',reversed},NoEscape{}}
    case SCon{char,rest} NoEscape{} _: QuoteMore{rest,SCon{char,reversed},NoEscape{}}
def quoteRun(fuel: Nat,+delimiter: Char,state: QuoteState) -> ResultOf(Quoted):
  match fuel state:
    case _ QuoteError{message}: Fail{Error{1n,1n,message}}
    case _ QuoteDone{value}: Done{value}
    case 0n _: Fail{Error{1n,1n,"Quoted scalar limit"}}
    case 1n+n QuoteMore{rest,reversed,escape}: quoteRun(n,delimiter,quoteStep(rest,escape,delimiter,reversed))
def quoted(delimiter: Char,+value: String) -> ResultOf(Quoted):
  quoteRun(1n+length(value,0n),delimiter,QuoteMore{value,"",NoEscape{}})

# A small pushdown parser handles nested flow collections without machine-stack
# recursion. Fuel is proportional to input plus punctuation/return transitions.
type Token is Data:
  Atom{value: Value}
  Mark{char: Char}
  Anchor{name: String}
  Alias{name: String}
  End{}
  Bad{message: String}
type Lexeme is Data:
  Lexeme{token: Token,remaining: String}
def quotedToken(result: ResultOf(Quoted)) -> Lexeme:
  match result:
    case Fail{Error{_,_,message}}: Lexeme{Bad{message},""}
    case Done{Quoted{value,rest}}: Lexeme{Atom{Text{value}},rest}
def spaceScan(text: String,inComment: Bool) -> String:
  match text inComment:
    case SNil{} _: ""
    case SCon{'\n',rest} _: spaceScan(rest,False{})
    case SCon{_,rest} True{}: spaceScan(rest,True{})
    case SCon{' ',rest} False{}: spaceScan(rest,False{})
    case SCon{'\t',rest} False{}: spaceScan(rest,False{})
    case SCon{'\r',rest} False{}: spaceScan(rest,False{})
    case SCon{'#',rest} False{}: spaceScan(rest,True{})
    case other False{}: other
def flowSpace(text: String) -> String: spaceScan(text,False{})

def colonEnds(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{']',_}: True{}
    case SCon{'}',_}: True{}
    case SCon{',',_}: True{}
    case SCon{char,_}: whitespace(char)
def word(text: String,+reversed: String,separated: Bool) -> Lexeme:
  match text:
    case SNil{}: Lexeme{Atom{plain(trim(String.reverse(reversed)))},""}
    case SCon{+char,+rest}:
      +stop = Char.is_eq(char,',') || Char.is_eq(char,']') || Char.is_eq(char,'}') || (Char.is_eq(char,'#') && separated) || (Char.is_eq(char,':') && colonEnds(rest))
      Bool.pick(Unit -> Lexeme,stop,_ => Lexeme{Atom{plain(trim(String.reverse(reversed)))},SCon{char,rest}},_ => word(rest,SCon{char,reversed},whitespace(char)))(Unit{})
def anchorName(text: String,+reversed: String,+alias: Bool) -> Lexeme:
  match text:
    case SNil{}: Lexeme{Bool.pick(Token,alias,Alias{String.reverse(reversed)},Anchor{String.reverse(reversed)}),""}
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Lexeme,whitespace(char) || Char.is_eq(char,',') || Char.is_eq(char,']') || Char.is_eq(char,'}'),
        _ => Lexeme{Bool.pick(Token,alias,Alias{String.reverse(reversed)},Anchor{String.reverse(reversed)}),SCon{char,rest}},
        _ => anchorName(rest,SCon{char,reversed},alias))(Unit{})
def lexClean(text: String) -> Lexeme:
  match text:
    case SNil{}: Lexeme{End{},""}
    case SCon{'"',rest}: quotedToken(quoted('"',rest))
    case SCon{'\'',rest}: quotedToken(quoted('\'',rest))
    case SCon{'[',rest}: Lexeme{Mark{'['},rest}
    case SCon{']',rest}: Lexeme{Mark{']'},rest}
    case SCon{'{',rest}: Lexeme{Mark{'{'},rest}
    case SCon{'}',rest}: Lexeme{Mark{'}'},rest}
    case SCon{',',rest}: Lexeme{Mark{','},rest}
    case SCon{':',rest}: Lexeme{Mark{':'},rest}
    case SCon{'&',rest}: anchorName(rest,"",False{})
    case SCon{'*',rest}: anchorName(rest,"",True{})
    case SCon{'!',_}: Lexeme{Bad{"Explicit YAML tags are not supported"},""}
    case other: word(other,"",False{})
def lex(text: String) -> Lexeme: lexClean(flowSpace(text))

type Frame is Data:
  ArrayFrame{reversed: List<&2,Value>}
  KeyFrame{fields: R.Record<Value>}
  ValueFrame{key: String,fields: R.Record<Value>}
  AnchorFrame{name: String}
type Mode is Data:
  Need{}
  Have{value: Value}
  ArrayNext{reversed: List<&2,Value>}
  ArrayAfter{reversed: List<&2,Value>}
  KeyNext{fields: R.Record<Value>}
  ColonNext{key: String,fields: R.Record<Value>}
  MapAfter{fields: R.Record<Value>}
type Flow is Data:
  Flow{remaining: String,mode: Mode,frames: List<&2,Frame>,anchors: R.Record<Value>}
  FlowDone{value: Value,anchors: R.Record<Value>}
  FlowError{message: String}
type Parsed is Data:
  Parsed{value: Value,anchors: R.Record<Value>}

def bindValue(present: Bool,key: String,value: Value,fields: R.Record<Value>,rest: String,frames: List<&2,Frame>,anchors: R.Record<Value>) -> Flow:
  match present:
    case True{}: FlowError{"Duplicate mapping key: " ++ key}
    case False{}: Flow{rest,MapAfter{R.set(Value,fields,key,value)},frames,anchors}
def deliver(frames: List<&2,Frame>,value: Value,+rest: String,anchors: R.Record<Value>) -> Flow:
  match frames value:
    case Nil{} result:
      Bool.pick(Flow,String.is_empty(flowSpace(rest)),FlowDone{result,anchors},FlowError{"Unexpected trailing scalar content"})
    case ArrayFrame{reversed} <> tail result: Flow{rest,ArrayAfter{result <> reversed},tail,anchors}
    case KeyFrame{fields} <> tail Text{key}: Flow{rest,ColonNext{key,fields},tail,anchors}
    case KeyFrame{_} <> _ _: FlowError{"Mapping keys must be strings"}
    case ValueFrame{+key,+fields} <> tail result:
      bindValue(Bool.not(Maybe.is_none(&2,Value,R.get(Value,fields,key))),key,result,fields,rest,tail,anchors)
    case AnchorFrame{name} <> tail +result: Flow{rest,Have{result},tail,R.set(Value,anchors,name,result)}
def aliasValue(value: Maybe<&2,Value>,remaining: String,frames: List<&2,Frame>,anchors: R.Record<Value>) -> Flow:
  match value:
    case None{}: FlowError{"Unknown or recursive alias"}
    case Some{value}: Flow{remaining,Have{value},frames,anchors}
def need(token: Token,rest: String,frames: List<&2,Frame>,+anchors: R.Record<Value>) -> Flow:
  match token:
    case Atom{value}: Flow{rest,Have{value},frames,anchors}
    case Mark{'['}: Flow{rest,ArrayNext{Nil{}},frames,anchors}
    case Mark{'{'}: Flow{rest,KeyNext{R.new(Value)},frames,anchors}
    case Anchor{name}: Flow{rest,Need{},AnchorFrame{name} <> frames,anchors}
    case Alias{name}: aliasValue(R.get(Value,anchors,name),rest,frames,anchors)
    case Bad{message}: FlowError{message}
    case End{}: Flow{rest,Have{Null{}},frames,anchors}
    case _: FlowError{"Expected YAML value"}
def flowToken(mode: Mode,lexeme: Lexeme,+original: String,frames: List<&2,Frame>,anchors: R.Record<Value>) -> Flow:
  match mode lexeme:
    case Need{} Lexeme{token,rest}: need(token,rest,frames,anchors)
    case ArrayNext{reversed} Lexeme{Mark{']'},rest}: Flow{rest,Have{Sequence{List.reverse(&2,Value,reversed)}},frames,anchors}
    case ArrayNext{reversed} Lexeme{token,rest}: need(token,rest,ArrayFrame{reversed} <> frames,anchors)
    case ArrayAfter{reversed} Lexeme{Mark{','},rest}: Flow{rest,ArrayNext{reversed},frames,anchors}
    case ArrayAfter{reversed} Lexeme{Mark{']'},rest}: Flow{rest,Have{Sequence{List.reverse(&2,Value,reversed)}},frames,anchors}
    case KeyNext{fields} Lexeme{Mark{'}'},rest}: Flow{rest,Have{Mapping{fields}},frames,anchors}
    case KeyNext{fields} Lexeme{token,rest}: need(token,rest,KeyFrame{fields} <> frames,anchors)
    case ColonNext{key,fields} Lexeme{Mark{':'},rest}: Flow{rest,Need{},ValueFrame{key,fields} <> frames,anchors}
    case MapAfter{fields} Lexeme{Mark{','},rest}: Flow{rest,KeyNext{fields},frames,anchors}
    case MapAfter{fields} Lexeme{Mark{'}'},rest}: Flow{rest,Have{Mapping{fields}},frames,anchors}
    case _ Lexeme{Bad{message},_}: FlowError{message}
    case _ Lexeme{End{},_}: FlowError{"Unexpected end of flow collection"}
    case _ _: FlowError{"Unexpected flow collection token"}
def flowStep(state: Flow) -> Flow:
  match state:
    case Flow{rest,Have{value},frames,anchors}: deliver(frames,value,rest,anchors)
    case Flow{+rest,mode,frames,anchors}: flowToken(mode,lex(rest),rest,frames,anchors)
    case other: other
def flowRun(fuel: Nat,state: Flow) -> ResultOf(Parsed):
  match fuel state:
    case _ FlowDone{value,anchors}: Done{Parsed{value,anchors}}
    case _ FlowError{message}: Fail{Error{1n,1n,message}}
    case 0n _: Fail{Error{1n,1n,"Flow nesting limit"}}
    case 1n+n current: flowRun(n,flowStep(current))
def parseFlow(+value: String,anchors: R.Record<Value>) -> ResultOf(Parsed):
  flowRun(8n * (1n+length(value,0n)),Flow{value,Need{},Nil{},anchors})

# Find a block mapping separator outside quotes and nested flow collections.
# A plain scalar's colon is structural only when followed by whitespace/EOF.
type KeyValue is Data:
  KeyValue{key: String,value: String}
type ScanState is Data:
  ScanState{quote: Maybe<&2,Char>,escaped: Bool,depth: Nat}
def lesser(depth: Nat) -> Nat:
  match depth:
    case 0n: 0n
    case 1n+n: n
def scanState(+char: Char,state: ScanState) -> ScanState:
  match state:
    case ScanState{Some{q},True{},depth}: ScanState{Some{q},False{},depth}
    case ScanState{Some{+q},False{},depth}: ScanState{Bool.pick(Maybe<&2,Char>,Char.is_eq(char,q),None{},Some{q}),Char.is_eq(char,'\\') && Char.is_eq(q,'"'),depth}
    case ScanState{None{},_,+depth}:
      nextQuote = Bool.pick(Maybe<&2,Char>,Char.is_eq(char,'"') || Char.is_eq(char,'\''),Some{char},None{})
      nextDepth = Bool.pick(Nat,Char.is_eq(char,'[') || Char.is_eq(char,'{'),1n+depth,Bool.pick(Nat,Char.is_eq(char,']') || Char.is_eq(char,'}'),lesser(depth),depth))
      ScanState{nextQuote,False{},nextDepth}
def isSeparator(char: Char,state: ScanState,rest: String) -> Bool:
  match state:
    case ScanState{None{},_,0n}: Char.is_eq(char,':') && colonEnds(rest)
    case _: False{}
def separator(text: String,+reversed: String,+state: ScanState) -> Maybe<&2,KeyValue>:
  match text:
    case SNil{}: None{}
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Maybe<&2,KeyValue>,isSeparator(char,state,rest),
        _ => Some{KeyValue{trim(String.reverse(reversed)),trimLeft(rest)}},
        _ => separator(rest,SCon{char,reversed},scanState(char,state)))(Unit{})
def splitPair(text: String) -> Maybe<&2,KeyValue>: separator(text,"",ScanState{None{},False{},0n})
def commentless(text: String,+reversed: String,separated: Bool) -> String:
  match text:
    case SNil{}: trim(String.reverse(reversed))
    case SCon{+char,rest}:
      Bool.pick(Unit -> String,Char.is_eq(char,'#') && separated,_ => trim(String.reverse(reversed)),_ => commentless(rest,SCon{char,reversed},whitespace(char)))(Unit{})
def inline(value: String,anchors: R.Record<Value>) -> ResultOf(Parsed):
  match value:
    case SCon{'[',rest}: parseFlow(SCon{'[',rest},anchors)
    case SCon{'{',rest}: parseFlow(SCon{'{',rest},anchors)
    case SCon{'"',rest}: parseFlow(SCon{'"',rest},anchors)
    case SCon{'\'',rest}: parseFlow(SCon{'\'',rest},anchors)
    case SCon{'&',rest}: parseFlow(SCon{'&',rest},anchors)
    case SCon{'*',rest}: parseFlow(SCon{'*',rest},anchors)
    case SCon{'!',_}: Fail{Error{1n,1n,"Explicit YAML tags are not supported"}}
    case SCon{'@',_}: Fail{Error{1n,1n,"Reserved YAML scalar indicator"}}
    case SCon{'`',_}: Fail{Error{1n,1n,"Reserved YAML scalar indicator"}}
    case other: Done{Parsed{plain(commentless(other,"",True{})),anchors}}

# Block structure is driven by indentation; source lines retain their physical
# positions and terminators so block scalar chomping is independent of the body.
type Line is Data:
  Line{number: Nat,indent: Nat,content: String,terminated: Bool}
def indented(number: Nat,text: String,indent: Nat,terminated: Bool) -> Line:
  match text:
    case SCon{' ',rest}: indented(number,rest,1n+indent,terminated)
    case other: Line{number,indent,other,terminated}
def sourceLines(text: String,+number: Nat,reversed: String,lines: List<&2,Line>) -> List<&2,Line>:
  match text:
    case SNil{}: List.reverse(&2,Line,indented(number,String.reverse(reversed),0n,False{}) <> lines)
    case SCon{'\n',rest}: sourceLines(rest,1n+number,"",indented(number,String.reverse(reversed),0n,True{}) <> lines)
    case SCon{char,rest}: sourceLines(rest,number,SCon{char,reversed},lines)
def spaces(count: Nat,result: String) -> String:
  match count:
    case 0n: result
    case 1n+n: spaces(n,SCon{' ',result})
def emptyLine(value: String) -> Bool: String.is_empty(trim(value))
def ignoredLine(value: String) -> Bool:
  match value:
    case SCon{'#',_}: True{}
    case other: emptyLine(other)
def sequenceItem(value: String) -> Maybe<&2,String>:
  match value:
    case "-": Some{""}
    case SCon{'-',SCon{' ',rest}}: Some{trimLeft(rest)}
    case SCon{'-',SCon{'\t',rest}}: Some{trimLeft(rest)}
    case _: None{}

type Chomp is Data:
  Clip{}
  Strip{}
  Keep{}
type ScalarHeader is Data:
  ScalarHeader{folded: Bool,chomp: Chomp,indent: Maybe<&2,Nat>}
def headerChars(value: String,folded: Bool,chomp: Chomp,indent: Maybe<&2,Nat>,marked: Bool) -> ResultOf(ScalarHeader):
  match value:
    case SNil{}: Done{ScalarHeader{folded,chomp,indent}}
    case SCon{'#',_}: Done{ScalarHeader{folded,chomp,indent}}
    case SCon{' ',rest}: Bool.pick(ResultOf(ScalarHeader),ignoredLine(trimLeft(rest)),Done{ScalarHeader{folded,chomp,indent}},Fail{Error{1n,1n,"Unexpected block scalar header text"}})
    case SCon{'+',rest}: Bool.pick(Unit -> ResultOf(ScalarHeader),marked,_ => Fail{Error{1n,1n,"Repeated block chomping indicator"}},_ => headerChars(rest,folded,Keep{},indent,True{}))(Unit{})
    case SCon{'-',rest}: Bool.pick(Unit -> ResultOf(ScalarHeader),marked,_ => Fail{Error{1n,1n,"Repeated block chomping indicator"}},_ => headerChars(rest,folded,Strip{},indent,True{}))(Unit{})
    case SCon{Chr{+code},rest}:
      Bool.pick(Unit -> ResultOf(ScalarHeader),U32.is_ge(code,49) && U32.is_le(code,57) && Maybe.is_none(&2,Nat,indent),
        _ => headerChars(rest,folded,chomp,Some{U32.to_nat((code - 48 : U32))},marked),_ => Fail{Error{1n,1n,"Invalid block scalar indicator"}})(Unit{})
def scalarHeader(value: String) -> ResultOf(ScalarHeader):
  match value:
    case SCon{'|',rest}: headerChars(rest,False{},Clip{},None{},False{})
    case SCon{'>',rest}: headerChars(rest,True{},Clip{},None{},False{})
    case _: Fail{Error{1n,1n,"Expected block scalar"}}
type ScalarRows is Data:
  ScalarRows{rows: List<&2,Line>,remaining: List<&2,Line>,indent: Nat}
def scalarRows(lines: List<&2,Line>,+parent: Nat,+indent: Maybe<&2,Nat>,+rows: List<&2,Line>) -> ScalarRows:
  match lines:
    case Nil{}: ScalarRows{List.reverse(&2,Line,rows),Nil{},Maybe.default(&2,Nat,indent,1n+parent)}
    case Line{+number,+actual,+content,+terminated} <> +rest:
      +blank = emptyLine(content)
      +wanted = Maybe.default(&2,Nat,indent,actual)
      accept = blank || (Nat.is_gt(actual,parent) && Nat.is_ge(actual,wanted))
      Bool.pick(Unit -> ScalarRows,accept,
        _ => scalarRows(rest,parent,Bool.pick(Maybe<&2,Nat>,blank,indent,Some{wanted}),Line{number,actual,content,terminated} <> rows),
        _ => ScalarRows{List.reverse(&2,Line,rows),Line{number,actual,content,terminated} <> rest,Maybe.default(&2,Nat,indent,1n+parent)})(Unit{})
type ScalarRow is Data:
  ScalarRow{text: String,moreIndented: Bool,terminated: Bool}
def stripRows(rows: List<&2,Line>,+indent: Nat,reversed: List<&2,ScalarRow>) -> List<&2,ScalarRow>:
  match rows:
    case Nil{}: List.reverse(&2,ScalarRow,reversed)
    case Line{_,+actual,+content,terminated} <> rest:
      text = Bool.pick(String,emptyLine(content),"",spaces(Nat.sub(actual,indent),content))
      stripRows(rest,indent,ScalarRow{text,Nat.is_gt(actual,indent),terminated} <> reversed)
def lineBreaks(count: Nat,result: String) -> String:
  match count:
    case 0n: result
    case 1n+n: lineBreaks(n,SCon{'\n',result})
def newlines(count: Nat) -> String: lineBreaks(count,"")
def trimNewlines(value: String) -> String:
  match value:
    case SCon{'\n',rest}: trimNewlines(rest)
    case other: other
def scalarEnd(chomp: Chomp,reversed: String) -> String:
  match chomp:
    case Keep{}: String.reverse(reversed)
    case Strip{}: String.reverse(trimNewlines(reversed))
    case Clip{}:
      match reversed:
        case SCon{'\n',rest}: String.reverse(SCon{'\n',trimNewlines(rest)})
        case other: String.reverse(other)
def rowJoin(folded: Bool,previousMore: Bool,nextMore: Bool,blankCount: Nat) -> String:
  match folded previousMore nextMore blankCount:
    case True{} False{} False{} 0n: " "
    case True{} False{} False{} 1n+n: newlines(1n+n)
    case _ _ _ count: newlines(1n+count)
type RowPrevious is Data:
  RowPrevious{more: Bool,terminated: Bool}
def rowPrefix(previous: Maybe<&2,RowPrevious>,folded: Bool,more: Bool,blanks: Nat) -> String:
  match previous:
    case None{}: newlines(blanks)
    case Some{RowPrevious{prior,_}}: rowJoin(folded,prior,more,blanks)
def rowEnding(previous: Maybe<&2,RowPrevious>,+blanks: Nat) -> String:
  match previous:
    case Some{RowPrevious{_,_}}: newlines(1n+blanks)
    case _: newlines(blanks)
def finishRows(chomp: Chomp,previous: Maybe<&2,RowPrevious>,blanks: Nat,reversed: String) -> String:
  match chomp previous:
    case Clip{} None{}: ""
    case mode prior: scalarEnd(mode,String.reverse.go(rowEnding(prior,blanks),reversed))
def renderRows(rows: List<&2,ScalarRow>,+folded: Bool,+chomp: Chomp,+previous: Maybe<&2,RowPrevious>,+blanks: Nat,+reversed: String) -> String:
  match rows:
    case Nil{}: finishRows(chomp,previous,blanks,reversed)
    case ScalarRow{+text,+more,+terminated} <> +rest:
      Bool.pick(Unit -> String,emptyLine(text),
        _ => renderRows(rest,folded,chomp,previous,Bool.pick(Nat,terminated,1n+blanks,blanks),reversed),
        _ => renderRows(rest,folded,chomp,Some{RowPrevious{more,terminated}},0n,String.reverse.go(text,String.reverse.go(rowPrefix(previous,folded,more,blanks),reversed))))(Unit{})

type BlockKind is Data:
  BlockMap{fields: R.Record<Value>,pending: Maybe<&2,String>}
  BlockSequence{reversed: List<&2,Value>,pending: Bool}
type BlockFrame is Data:
  BlockFrame{indent: Nat,kind: BlockKind}
type Block is Data:
  Block{lines: List<&2,Line>,frames: List<&2,BlockFrame>,anchors: R.Record<Value>,root: Maybe<&2,Value>}
  BlockDone{value: Value}
  BlockError{error: Error}
def pending(kind: BlockKind) -> Bool:
  match kind:
    case BlockMap{_,Some{_}}: True{}
    case BlockSequence{_,waiting}: waiting
    case _: False{}
def attach(frames: List<&2,BlockFrame>,value: Value,lines: List<&2,Line>,anchors: R.Record<Value>,root: Maybe<&2,Value>) -> Block:
  match frames root:
    case Nil{} None{}: Block{lines,Nil{},anchors,Some{value}}
    case Nil{} Some{_}: BlockError{Error{1n,1n,"Multiple root values"}}
    case BlockFrame{indent,BlockMap{fields,Some{key}}} <> rest previous:
      Block{lines,BlockFrame{indent,BlockMap{R.set(Value,fields,key,value),None{}}} <> rest,anchors,previous}
    case BlockFrame{indent,BlockSequence{reversed,True{}}} <> rest previous:
      Block{lines,BlockFrame{indent,BlockSequence{value <> reversed,False{}}} <> rest,anchors,previous}
    case _ _: BlockError{Error{1n,1n,"Unexpected indented value"}}
def parsedAt(result: ResultOf(Parsed),+line: Nat,frames: List<&2,BlockFrame>,lines: List<&2,Line>,root: Maybe<&2,Value>) -> Block:
  match result:
    case Fail{Error{_,column,message}}: BlockError{Error{line,column,message}}
    case Done{Parsed{value,anchors}}: attach(frames,value,lines,anchors,root)
def finishKind(kind: BlockKind) -> Value:
  match kind:
    case BlockMap{fields,None{}}: Mapping{fields}
    case BlockMap{fields,Some{key}}: Mapping{R.set(Value,fields,key,Null{})}
    case BlockSequence{values,False{}}: Sequence{List.reverse(&2,Value,values)}
    case BlockSequence{values,True{}}: Sequence{List.reverse(&2,Value,Null{} <> values)}
def closeBlock(frames: List<&2,BlockFrame>,lines: List<&2,Line>,anchors: R.Record<Value>,root: Maybe<&2,Value>) -> Block:
  match frames:
    case Nil{}: BlockDone{Maybe.default(&2,Value,root,Null{})}
    case BlockFrame{_,kind} <> rest: attach(rest,finishKind(kind),lines,anchors,root)

type Continuation is Data:
  Continuation{text: String,remaining: List<&2,Line>}
def continuation(lines: List<&2,Line>,+indent: Nat,reversed: List<&2,String>) -> Continuation:
  match lines:
    case Nil{}: Continuation{String.join(List.reverse(&2,String,reversed),"\n"),Nil{}}
    case Line{+number,+level,+content,+terminated} <> +rest:
      +reversed = reversed
      Bool.pick(Unit -> Continuation,Nat.is_gt(level,indent) || emptyLine(content),
        _ => continuation(rest,indent,content <> reversed),
        _ => Continuation{String.join(List.reverse(&2,String,reversed),"\n"),Line{number,level,content,terminated} <> rest})(Unit{})
def inlineLines(part: Continuation,number: Nat,frames: List<&2,BlockFrame>,anchors: R.Record<Value>,root: Maybe<&2,Value>) -> Block:
  match part:
    case Continuation{text,remaining}: parsedAt(inline(text,anchors),number,frames,remaining,root)
def scalarResult(rows: ScalarRows,folded: Bool,chomp: Chomp,frames: List<&2,BlockFrame>,anchors: R.Record<Value>,root: Maybe<&2,Value>) -> Block:
  match rows:
    case ScalarRows{rows,remaining,indent}: attach(frames,Text{renderRows(stripRows(rows,indent,Nil{}),folded,chomp,None{},0n,"")},remaining,anchors,root)
def blockScalar(header: ResultOf(ScalarHeader),lines: List<&2,Line>,number: Nat,+parent: Nat,frames: List<&2,BlockFrame>,anchors: R.Record<Value>,root: Maybe<&2,Value>) -> Block:
  match header:
    case Fail{Error{_,column,message}}: BlockError{Error{number,column,message}}
    case Done{ScalarHeader{folded,chomp,indent}}:
      scalarResult(scalarRows(lines,parent,Maybe.map(&2,Nat,Nat,value => Nat.add(parent,value),indent),Nil{}),folded,chomp,frames,anchors,root)
def scalarValue(+raw: String,lines: List<&2,Line>,number: Nat,indent: Nat,frames: List<&2,BlockFrame>,anchors: R.Record<Value>,root: Maybe<&2,Value>) -> Block:
  match raw:
    case SCon{'|',_}: blockScalar(scalarHeader(raw),lines,number,indent,frames,anchors,root)
    case SCon{'>',_}: blockScalar(scalarHeader(raw),lines,number,indent,frames,anchors,root)
    case _: inlineLines(continuation(lines,indent,raw <> Nil{}),number,frames,anchors,root)

def frame(indent: Nat,kind: BlockKind,tail: List<&2,BlockFrame>) -> List<&2,BlockFrame>:
  BlockFrame{indent,kind} <> tail
def mapKey(result: ResultOf(Parsed),raw: String,+number: Nat,+indent: Nat,fields: R.Record<Value>,tail: List<&2,BlockFrame>,+lines: List<&2,Line>,+anchors: R.Record<Value>,+root: Maybe<&2,Value>) -> Block:
  match result:
    case Fail{Error{_,column,message}}: BlockError{Error{number,column,message}}
    case Done{Parsed{Text{+key},_}}:
      +fields = fields
      +raw = raw
      +next = frame(indent,BlockMap{fields,Some{key}},tail)
      Bool.pick(Unit -> Block,Bool.not(Maybe.is_none(&2,Value,R.get(Value,fields,key))),
        _ => BlockError{Error{number,1n,"Duplicate mapping key: " ++ key}},
        _ => Bool.pick(Unit -> Block,ignoredLine(raw),_ => Block{lines,next,anchors,root},_ => scalarValue(raw,lines,number,indent,next,anchors,root))(Unit{}))(Unit{})
    case Done{_}: BlockError{Error{number,1n,"Mapping keys must be strings"}}
def mapLine(pair: Maybe<&2,KeyValue>,number: Nat,+indent: Nat,fields: R.Record<Value>,tail: List<&2,BlockFrame>,lines: List<&2,Line>,+anchors: R.Record<Value>,root: Maybe<&2,Value>) -> Block:
  match pair:
    case None{}: BlockError{Error{number,1n,"Expected a mapping entry"}}
    case Some{KeyValue{key,raw}}: mapKey(inline(key,anchors),raw,number,indent,fields,tail,lines,anchors,root)
def nestedSequence(raw: String,pair: Maybe<&2,KeyValue>,number: Nat,+indent: Nat,next: List<&2,BlockFrame>,lines: List<&2,Line>,anchors: R.Record<Value>,root: Maybe<&2,Value>) -> Block:
  match pair:
    case Some{_}: Block{Line{number,2n+indent,raw,True{}} <> lines,BlockFrame{2n+indent,BlockMap{R.new(Value),None{}}} <> next,anchors,root}
    case None{}: scalarValue(raw,lines,number,indent,next,anchors,root)
def sequenceLine(item: Maybe<&2,String>,number: Nat,+indent: Nat,reversed: List<&2,Value>,tail: List<&2,BlockFrame>,+lines: List<&2,Line>,+anchors: R.Record<Value>,+root: Maybe<&2,Value>) -> Block:
  match item:
    case None{}: BlockError{Error{number,1n,"Expected a sequence entry"}}
    case Some{+raw}:
      +next = frame(indent,BlockSequence{reversed,True{}},tail)
      Bool.pick(Unit -> Block,ignoredLine(raw),_ => Block{lines,next,anchors,root},_ => nestedSequence(raw,splitPair(raw),number,indent,next,lines,anchors,root))(Unit{})
def ordinaryLine(number: Nat,+indent: Nat,+content: String,kind: BlockKind,tail: List<&2,BlockFrame>,lines: List<&2,Line>,anchors: R.Record<Value>,root: Maybe<&2,Value>) -> Block:
  match kind:
    case BlockMap{fields,None{}}: mapLine(splitPair(content),number,indent,fields,tail,lines,anchors,root)
    case BlockSequence{reversed,False{}}: sequenceLine(sequenceItem(content),number,indent,reversed,tail,lines,anchors,root)
    case waiting: attach(BlockFrame{indent,waiting} <> tail,Null{},Line{number,indent,content,True{}} <> lines,anchors,root)
def openKind(item: Maybe<&2,String>,pair: Maybe<&2,KeyValue>) -> Maybe<&2,BlockKind>:
  match item pair:
    case Some{_} _: Some{BlockSequence{Nil{},False{}}}
    case None{} Some{_}: Some{BlockMap{R.new(Value),None{}}}
    case _ _: None{}
def openNode(kind: Maybe<&2,BlockKind>,line: Line,lines: List<&2,Line>,frames: List<&2,BlockFrame>,anchors: R.Record<Value>,root: Maybe<&2,Value>) -> Block:
  match kind line:
    case Some{kind} Line{number,+indent,content,terminated}: Block{Line{number,indent,content,terminated} <> lines,BlockFrame{indent,kind} <> frames,anchors,root}
    case None{} Line{number,indent,content,_}: scalarValue(content,lines,number,indent,frames,anchors,root)
def descend(number: Nat,indent: Nat,+content: String,terminated: Bool,lines: List<&2,Line>,frames: List<&2,BlockFrame>,anchors: R.Record<Value>,root: Maybe<&2,Value>) -> Block:
  openNode(openKind(sequenceItem(content),splitPair(content)),Line{number,indent,content,terminated},lines,frames,anchors,root)
def positioned(frames: List<&2,BlockFrame>,+number: Nat,+indent: Nat,+content: String,+terminated: Bool,+lines: List<&2,Line>,+anchors: R.Record<Value>,+root: Maybe<&2,Value>) -> Block:
  match frames:
    case Nil{}: descend(number,indent,content,terminated,lines,Nil{},anchors,root)
    case BlockFrame{+level,+kind} <> +tail:
      +all = frame(level,kind,tail)
      Bool.pick(Unit -> Block,Nat.is_lt(indent,level),
        _ => closeBlock(all,Line{number,indent,content,terminated} <> lines,anchors,root),
        _ => Bool.pick(Unit -> Block,Nat.is_gt(indent,level),
          _ => Bool.pick(Unit -> Block,pending(kind),_ => descend(number,indent,content,terminated,lines,all,anchors,root),_ => BlockError{Error{number,1n,"Unexpected indentation"}})(Unit{}),
          _ => ordinaryLine(number,indent,content,kind,tail,lines,anchors,root))(Unit{}))(Unit{})
def blockLine(line: Line,+lines: List<&2,Line>,+frames: List<&2,BlockFrame>,+anchors: R.Record<Value>,+root: Maybe<&2,Value>) -> Block:
  match line:
    case Line{number,indent,+content,terminated}:
      Bool.pick(Unit -> Block,ignoredLine(content),_ => Block{lines,frames,anchors,root},_ => positioned(frames,number,indent,content,terminated,lines,anchors,root))(Unit{})
def blockStep(state: Block) -> Block:
  match state:
    case Block{Nil{},frames,anchors,root}: closeBlock(frames,Nil{},anchors,root)
    case Block{line <> rest,frames,anchors,root}: blockLine(line,rest,frames,anchors,root)
    case other: other
def blockRun(fuel: Nat,state: Block) -> ResultOf(Value):
  match fuel state:
    case _ BlockDone{value}: Done{value}
    case _ BlockError{error}: Fail{error}
    case 0n _: Fail{Error{1n,1n,"Document nesting limit"}}
    case 1n+n current: blockRun(n,blockStep(current))
def endColumn(lines: List<&2,Line>,+number: Nat) -> Nat:
  match lines:
    case Nil{}: 1n
    case Line{line,indent,content,_} <> rest:
      Bool.pick(Unit -> Nat,Nat.is_eq(line,number),_ => 1n + indent + length(content,0n),_ => endColumn(rest,number))(Unit{})
def located(result: ResultOf(Value),lines: List<&2,Line>) -> ResultOf(Value):
  match result:
    case Fail{Error{+line,column,+message}}:
      atEnd = Strings.equal(message,"Unexpected end of flow collection") || Strings.equal(message,"Unterminated quoted scalar")
      Fail{Error{line,Bool.pick(Nat,atEnd,endColumn(lines,line),column),message}}
    case other: other
def parse(+source: String) -> ResultOf(Value):
  +lines = sourceLines(source,1n,"",Nil{})
  located(blockRun(8n * (1n+length(source,0n)),Block{lines,Nil{},R.new(Value),None{}}),lines)
