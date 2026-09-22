import Base
import ./regex.bend as R
import ./u32-table.bend as Table
import ./utf8.bend as Utf8

# Byte-mode matching uses the same parser and Thompson program. Unicode edges
# consume one validated UTF-8 scalar; byte edges consume exactly one octet.
# Four frontiers schedule variable-width edges without expanding Unicode
# classes into enormous UTF-8 tries. Input lookahead never exceeds four bytes.
type Regex is Data:
  LiteralRegex{value: R.Regex}
  Regex{start: U32,count: U32,table: Table.Table<R.Instruction>}

def builtProgram(start: U32,builder: R.Builder) -> Regex:
  match builder:
    case R.Builder{count,reversed}: Regex{start,count,Table.fromSortedEntries(R.Instruction,List.reverse(&2,Table.Entry<R.Instruction>,reversed))}

def compiled(value: U32 & R.Builder) -> Regex:
  (start,builder) = value
  builtProgram(start,builder)

def selected(literal: Maybe<&2,R.Literal>,value: R.Expression) -> Regex:
  match literal:
    case Some{literal}: LiteralRegex{R.compileSelected(Some{literal},value)}
    case None{}: compiled(R.finishCompilation(R.Compilation{R.Compile{value,0} <> Nil{},R.Builder{1,Table.Entry{0,R.Accept{}} <> Nil{}},0}))

def expression(value: Result<&2,&2,R.Error,R.Expression>) -> Result<&2,&2,R.Error,Regex>:
  match value:
    case Fail{error}: Fail{error}
    case Done{+value}: Bool.pick(Unit -> Result<&2,&2,R.Error,Regex>,Nat.is_lt(R.cost(value),65536n),
      _ => Done{selected(R.expressionLiteral(value <> Nil{},"",None{}),value)},
      _ => Fail{R.SizeLimit{}})(Unit{})

def compile(pattern: String,insensitive: Bool) -> Result<&2,&2,R.Error,Regex>:
  expression(R.parsePattern(pattern,insensitive,True{}))

type Scalar is Data:
  Scalar{char: Char,width: U32}

# At most four bytes are inspected. Strict validation avoids replacement
# characters: malformed bytes remain available to explicit byte edges.
def prefixLoop(bytes: List<&2,U32>,step: Utf8.ByteStep,+width: U32,valid: Bool) -> Maybe<&2,Scalar>:
  match bytes step valid:
    case _ _ False{}: None{}
    case _ Utf8.ByteStep{_,point <> Nil{}} True{}: Some{Scalar{Chr{point},width}}
    case Nil{} _ _: None{}
    case +byte <> rest Utf8.ByteStep{+pending,_} True{}: prefixLoop(rest,Utf8.consume(pending,byte),(width + 1 : U32),Utf8.valid(pending,byte))

def prefix(bytes: List<&2,U32>,pending: Utf8.Pending,width: U32) -> Maybe<&2,Scalar>:
  prefixLoop(bytes,Utf8.ByteStep{pending,Nil{}},width,True{})

def scalarChar(value: Maybe<&2,Scalar>) -> Maybe<&2,Char>:
  match value:
    case None{}: None{}
    case Some{Scalar{char,_}}: Some{char}

def byteChar(bytes: List<&2,U32>) -> Maybe<&2,Char>:
  match bytes:
    case Nil{}: None{}
    case byte <> _: Some{Chr{byte}}

type Context is Data:
  Context{leftByte: Maybe<&2,Char>,rightByte: Maybe<&2,Char>,left: Maybe<&2,Char>,right: Maybe<&2,Scalar>}

def validSide(+byte: Maybe<&2,Char>,point: Maybe<&2,Char>) -> Bool:
  Maybe.is_none(&2,Char,byte) || Bool.not(Maybe.is_none(&2,Char,point))

def check(value: R.Assertion,context: Context) -> Bool:
  match value context:
    case R.Boundary{+kind,+word,True{}} Context{+lb,+rb,+left,right}:
      +right = scalarChar(right)
      +guard = Bool.pick(Bool,U32.is_eq(kind,1),validSide(lb,left) && validSide(rb,right),Bool.pick(Bool,U32.is_eq(kind,4),validSide(lb,left),Bool.pick(Bool,U32.is_eq(kind,5),validSide(rb,right),True{})))
      guard && R.boundary(kind,R.member(left,word),R.member(right,word))
    case value Context{left,right,_,_}: R.assertion(value,left,right)

type Future is Data:
  Future{one: List<&2,U32>,two: List<&2,U32>,three: List<&2,U32>,four: List<&2,U32>}

def schedule(width: U32,target: U32,future: Future) -> Future:
  match width future:
    case 1 Future{one,two,three,four}: Future{target <> one,two,three,four}
    case 2 Future{one,two,three,four}: Future{one,target <> two,three,four}
    case 3 Future{one,two,three,four}: Future{one,two,target <> three,four}
    case _ Future{one,two,three,four}: Future{one,two,three,target <> four}

def scalarEdge(value: R.Class,insensitive: Bool,target: U32,right: Maybe<&2,Scalar>,+future: Future) -> Future:
  match right:
    case None{}: future
    case Some{Scalar{Chr{point},width}}: Bool.pick(Future,R.accepts(value,point,insensitive),schedule(width,target,future),future)

def byteEdge(value: R.Class,target: U32,right: Maybe<&2,Char>,+future: Future) -> Future:
  match right:
    case None{}: future
    case Some{Chr{point}}: Bool.pick(Future,R.contains(value,point),schedule(1,target,future),future)

type Frontier is Type:
  Frontier{seen: Array<U32>,work: List<&2,U32>,future: Future,matched: Bool}

def instruction(value: Maybe<&2,R.Instruction>,seen: Array<U32>,+work: List<&2,U32>,future: Future,matched: Bool,+context: Context) -> Frontier:
  match value context:
    case None{} _: Frontier{seen,work,future,matched}
    case Some{R.Accept{}} _: Frontier{seen,work,future,True{}}
    case Some{R.Split{a,b}} _: Frontier{seen,a <> b <> work,future,matched}
    case Some{R.Check{value,target}} context: Frontier{seen,Bool.pick(List<&2,U32>,check(value,context),target <> work,work),future,matched}
    case Some{R.Consume{value,insensitive,target}} Context{_,_,_,right}: Frontier{seen,work,scalarEdge(value,insensitive,target,right,future),matched}
    case Some{R.ConsumeByte{value,target}} Context{_,right,_,_}: Frontier{seen,work,byteEdge(value,target,right,future),matched}

def visitFresh(fresh: Bool,seen: Array<U32>,+index: U32,stamp: U32,table: Table.Table<R.Instruction>,work: List<&2,U32>,future: Future,matched: Bool,context: Context) -> Frontier:
  match fresh:
    case False{}: Frontier{seen,work,future,matched}
    case True{}: instruction(Table.get(R.Instruction,table,index),Array.set(U32,seen,index,stamp),work,future,matched,context)

def visit(lookup: Array<U32> & U32,index: U32,+stamp: U32,table: Table.Table<R.Instruction>,work: List<&2,U32>,future: Future,matched: Bool,context: Context) -> Frontier:
  (seen,previous) = lookup
  visitFresh(Bool.not(U32.is_eq(previous,stamp)),seen,index,stamp,table,work,future,matched,context)

def closure(fuel: Nat,state: Frontier,+stamp: U32,+table: Table.Table<R.Instruction>,+context: Context) -> Frontier:
  match fuel state:
    case _ Frontier{seen,_,future,True{}}: Frontier{seen,Nil{},future,True{}}
    case _ Frontier{seen,Nil{},future,matched}: Frontier{seen,Nil{},future,matched}
    case Zero{} state: state
    case Succ{fuel} Frontier{seen,+index <> rest,future,matched}: closure(fuel,visit(Array.get(U32,seen,index),index,stamp,table,rest,future,matched,context),stamp,table,context)

type Cursor is Type:
  Matched{}
  LiteralCursor{regex: R.Regex,decoder: Utf8.Pending,state: R.Cursor}
  Cursor{program: Regex,stamp: U32,seen: Array<U32>,work: List<&2,U32>,future: Future,decoder: Utf8.Pending,leftByte: Maybe<&2,Char>,left: Maybe<&2,Char>,buffer: List<&2,U32>}

def create(regex: Regex) -> Cursor:
  match regex:
    case LiteralRegex{+regex}: LiteralCursor{regex,Utf8.Ready{},R.create(regex)}
    case Regex{+start,+count,+table}: Cursor{Regex{start,count,table},1,Array.new(U32,R.arrayDepth(32n,(count - 1 : U32),Zero{}),0),Nil{},Future{Nil{},Nil{},Nil{},Nil{}},Utf8.Ready{},None{},None{},Nil{}}

def previous(step: Utf8.ByteStep) -> Utf8.Pending & Maybe<&2,Char>:
  match step:
    case Utf8.ByteStep{pending,point <> Nil{}}: (pending,Some{Chr{point}})
    case Utf8.ByteStep{pending,_}: (pending,None{})

def decodedPrevious(+decoder: Utf8.Pending,+byte: U32) -> Utf8.Pending & Maybe<&2,Char>:
  Bool.pick(Unit -> Utf8.Pending & Maybe<&2,Char>,Utf8.valid(decoder,byte),_ => previous(Utf8.consume(decoder,byte)),
    _ => Bool.pick(Unit -> Utf8.Pending & Maybe<&2,Char>,Utf8.valid(Utf8.Ready{},byte),_ => previous(Utf8.start(byte)),_ => (Utf8.Ready{},None{}))(Unit{}))(Unit{})

def advanced(program: Regex,stamp: U32,seen: Array<U32>,future: Future,leftByte: Maybe<&2,Char>,buffer: List<&2,U32>,decoded: Utf8.Pending & Maybe<&2,Char>) -> Cursor:
  match future:
    case Future{one,two,three,four}:
      (decoder,left) = decoded
      Cursor{program,stamp,seen,one,Future{two,three,four,Nil{}},decoder,leftByte,left,buffer}

def stepped(+program: Regex,+stamp: U32,+count: U32,+decoder: Utf8.Pending,+byte: U32,+buffer: List<&2,U32>,state: Frontier) -> Cursor:
  match state:
    case Frontier{_,_,_,True{}}: Matched{}
    case Frontier{seen,_,+future,False{}}:
      Bool.pick(Unit -> Cursor,U32.is_eq(stamp,4294967295),
        _ => advanced(program,1,Array.new(U32,R.arrayDepth(32n,(count - 1 : U32),Zero{}),0),future,Some{Chr{byte}},buffer,decodedPrevious(decoder,byte)),
        _ => advanced(program,(stamp + 1 : U32),seen,future,Some{Chr{byte}},buffer,decodedPrevious(decoder,byte)))(Unit{})

def step(cursor: Cursor) -> Cursor:
  match cursor:
    case Cursor{Regex{+start,+count,+table},+stamp,seen,work,future,decoder,leftByte,left,+byte <> +rest}:
      stepped(Regex{start,count,table},stamp,count,decoder,byte,rest,closure(U32.to_nat(count) * 6n + 2n,Frontier{seen,start <> work,future,False{}},stamp,table,Context{leftByte,Some{Chr{byte}},left,prefix(byte <> rest,Utf8.Ready{},0)}))
    case cursor: cursor

def literalState(regex: R.Regex,decoder: Utf8.Pending,state: R.Cursor) -> Cursor:
  match state:
    case R.Matched{}: Matched{}
    case state: LiteralCursor{regex,decoder,state}

def literalDecoded(regex: R.Regex,step: Utf8.ByteStep,state: R.Cursor) -> Cursor:
  match step:
    case Utf8.ByteStep{decoder,point <> Nil{}}: literalState(regex,decoder,R.feedChar(state,Chr{point}))
    case Utf8.ByteStep{decoder,_}: LiteralCursor{regex,decoder,state}

def literalValid(valid: Bool,+regex: R.Regex,decoder: Utf8.Pending,+byte: U32,state: R.Cursor) -> Cursor:
  match valid:
    case True{}: literalDecoded(regex,Utf8.consume(decoder,byte),state)
    case False{}: Bool.pick(Unit -> Cursor,Utf8.valid(Utf8.Ready{},byte),_ => literalDecoded(regex,Utf8.start(byte),R.create(regex)),_ => LiteralCursor{regex,Utf8.Ready{},R.create(regex)})(Unit{})

def appendByte(+byte: U32,cursor: Cursor) -> Cursor:
  match cursor:
    case Matched{}: Matched{}
    case LiteralCursor{regex,+decoder,state}: literalValid(Utf8.valid(decoder,byte),regex,decoder,byte,state)
    case Cursor{program,stamp,seen,work,future,decoder,leftByte,left,buffer}: Cursor{program,stamp,seen,work,future,decoder,leftByte,left,List.append(&2,U32,buffer,byte <> Nil{})}

def buffered(cursor: Cursor) -> Cursor:
  match cursor:
    case Cursor{program,stamp,seen,work,future,decoder,leftByte,left,a <> b <> c <> d <> Nil{}}: step(Cursor{program,stamp,seen,work,future,decoder,leftByte,left,a <> b <> c <> d <> Nil{}})
    case cursor: cursor

# Octets have the Base File.read_bytes contract (0..255). File encoding/binary
# policy belongs to the caller and must not stop validating after a match.
def feed(bytes: List<&2,U32>,cursor: Cursor) -> Cursor:
  match bytes cursor:
    case _ Matched{}: Matched{}
    case Nil{} cursor: cursor
    case byte <> rest cursor: feed(rest,buffered(appendByte(byte,cursor)))

def finalFrontier(state: Frontier) -> Bool:
  match state:
    case Frontier{_,_,_,matched}: matched

def finishLoop(fuel: Nat,cursor: Cursor) -> Bool:
  match fuel cursor:
    case _ Matched{}: True{}
    case _ LiteralCursor{_,_,state}: R.finish(state)
    case _ Cursor{Regex{start,+count,table},stamp,seen,work,future,_,leftByte,left,Nil{}}: finalFrontier(closure(U32.to_nat(count) * 6n + 2n,Frontier{seen,start <> work,future,False{}},stamp,table,Context{leftByte,None{},left,None{}}))
    case Zero{} _: False{}
    case Succ{fuel} cursor: finishLoop(fuel,step(cursor))

def finish(cursor: Cursor) -> Bool: finishLoop(4n,cursor)

def isMatch(regex: Regex,bytes: List<&2,U32>) -> Bool: finish(feed(bytes,create(regex)))
