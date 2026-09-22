import Base
import ./case-fold.bend as Fold
import ./u32-table.bend as Table
import ./unicode-17-regex.bend as Unicode
import ./base64.bend as Base64

# Unicode-scalar regular expressions. Captures and greediness do not affect the
# existence of a match, the operation used by the grep tool. A Thompson program
# tracks each state at most once at an input boundary, including empty cycles.
type Error is Data:
  Syntax{message: String}
  SizeLimit{}
  RequiresByteInput{}

type Class is Data:
  Range{first: U32,last: U32}
  Union{left: Class,right: Class}
  Intersection{left: Class,right: Class}
  Difference{left: Class,right: Class}
  Symmetric{left: Class,right: Class}
  Negation{value: Class}
  EmptyClass{}
  Property{ranges: Table.Table<U32>}
  CaseAscii{value: Class}

def atMost(point: U32,last: Maybe<&2,U32>) -> Bool:
  match last:
    case None{}: False{}
    case Some{last}: U32.is_le(point,last)

def swapAscii(+point: U32) -> U32:
  Bool.pick(U32,U32.is_ge(point,65) && U32.is_le(point,90),(point + 32 : U32),Bool.pick(U32,U32.is_ge(point,97) && U32.is_le(point,122),(point - 32 : U32),point))

def rangeVariants(chars: List<&2,Char>,+low: U32,+high: U32) -> Bool:
  match chars:
    case Nil{}: False{}
    case Chr{+point} <> rest: Bool.pick(Unit -> Bool,U32.is_ge(point,low) && U32.is_le(point,high),_ => True{},_ => rangeVariants(rest,low,high))(Unit{})

def propertyVariants(chars: List<&2,Char>,+table: Table.Table<U32>) -> Bool:
  match chars:
    case Nil{}: False{}
    case Chr{+point} <> rest: Bool.pick(Unit -> Bool,atMost(point,Table.floor(U32,table,point)),_ => True{},_ => propertyVariants(rest,table))(Unit{})

type ClassTask is Data:
  Evaluate{value: Class,point: U32,insensitive: U32}
  OrElse{value: Class,point: U32,insensitive: U32}
  AndThen{value: Class,point: U32,insensitive: U32}
  Subtract{value: Class,point: U32,insensitive: U32}
  Exclusive{value: Class,point: U32,insensitive: U32}
  Invert{}
  Xor{left: Bool}

type ClassEvaluation is Data:
  ClassEvaluation{work: List<&2,ClassTask>,value: Bool}

def rangeAccept(+low: U32,+high: U32,+point: U32,+insensitive: U32) -> Bool:
  Bool.pick(Unit -> Bool,U32.is_eq(insensitive,1),_ => rangeVariants(Fold.variants(Chr{point}),low,high),_ => (U32.is_ge(point,low) && U32.is_le(point,high)) || (U32.is_eq(insensitive,2) && U32.is_ge(swapAscii(point),low) && U32.is_le(swapAscii(point),high)))(Unit{})

def propertyAccept(+ranges: Table.Table<U32>,+point: U32,+insensitive: U32) -> Bool:
  Bool.pick(Unit -> Bool,U32.is_eq(insensitive,1),_ => propertyVariants(Fold.variants(Chr{point}),ranges),_ => atMost(point,Table.floor(U32,ranges,point)) || (U32.is_eq(insensitive,2) && atMost(swapAscii(point),Table.floor(U32,ranges,swapAscii(point)))))(Unit{})

def classEvaluationStep(state: ClassEvaluation) -> ClassEvaluation:
  match state:
    case ClassEvaluation{Nil{},value}: ClassEvaluation{Nil{},value}
    case ClassEvaluation{Invert{} <> work,value}: ClassEvaluation{work,Bool.not(value)}
    case ClassEvaluation{Xor{left} <> work,right}: ClassEvaluation{work,Bool.xor(left,right)}
    case ClassEvaluation{OrElse{_,_,_} <> work,True{}}: ClassEvaluation{work,True{}}
    case ClassEvaluation{OrElse{value,point,insensitive} <> work,False{}}: ClassEvaluation{Evaluate{value,point,insensitive} <> work,False{}}
    case ClassEvaluation{AndThen{_,_,_} <> work,False{}}: ClassEvaluation{work,False{}}
    case ClassEvaluation{AndThen{value,point,insensitive} <> work,True{}}: ClassEvaluation{Evaluate{value,point,insensitive} <> work,False{}}
    case ClassEvaluation{Subtract{_,_,_} <> work,False{}}: ClassEvaluation{work,False{}}
    case ClassEvaluation{Subtract{value,point,insensitive} <> work,True{}}: ClassEvaluation{Evaluate{value,point,insensitive} <> Invert{} <> work,False{}}
    case ClassEvaluation{Exclusive{value,point,insensitive} <> work,left}: ClassEvaluation{Evaluate{value,point,insensitive} <> Xor{left} <> work,False{}}
    case ClassEvaluation{Evaluate{Range{low,high},point,insensitive} <> work,_}: ClassEvaluation{work,rangeAccept(low,high,point,insensitive)}
    case ClassEvaluation{Evaluate{Property{ranges},point,insensitive} <> work,_}: ClassEvaluation{work,propertyAccept(ranges,point,insensitive)}
    case ClassEvaluation{Evaluate{EmptyClass{},_,_} <> work,_}: ClassEvaluation{work,False{}}
    case ClassEvaluation{Evaluate{Negation{value},point,insensitive} <> work,_}: ClassEvaluation{Evaluate{value,point,insensitive} <> Invert{} <> work,False{}}
    case ClassEvaluation{Evaluate{CaseAscii{value},point,_} <> work,_}: ClassEvaluation{Evaluate{value,point,2} <> work,False{}}
    case ClassEvaluation{Evaluate{Union{a,b},+point,+insensitive} <> work,_}: ClassEvaluation{Evaluate{a,point,insensitive} <> OrElse{b,point,insensitive} <> work,False{}}
    case ClassEvaluation{Evaluate{Intersection{a,b},+point,+insensitive} <> work,_}: ClassEvaluation{Evaluate{a,point,insensitive} <> AndThen{b,point,insensitive} <> work,False{}}
    case ClassEvaluation{Evaluate{Difference{a,b},+point,+insensitive} <> work,_}: ClassEvaluation{Evaluate{a,point,insensitive} <> Subtract{b,point,insensitive} <> work,False{}}
    case ClassEvaluation{Evaluate{Symmetric{a,b},+point,+insensitive} <> work,_}: ClassEvaluation{Evaluate{a,point,insensitive} <> Exclusive{b,point,insensitive} <> work,False{}}

# Each frame finishes one finite class subtree. The explicit stack also handles
# long flat classes without depending on the backend's call-stack size.
@unsafe
def evaluateClass(state: ClassEvaluation) -> Bool:
  match state:
    case ClassEvaluation{Nil{},value}: value
    case state: evaluateClass(classEvaluationStep(state))

def accepts(value: Class,point: U32,insensitive: Bool) -> Bool:
  match value:
    case Range{low,high}: rangeAccept(low,high,point,Bool.to_u32(insensitive))
    case Property{ranges}: propertyAccept(ranges,point,Bool.to_u32(insensitive))
    case value: evaluateClass(ClassEvaluation{Evaluate{value,point,Bool.to_u32(insensitive)} <> Nil{},False{}})

def contains(value: Class,point: U32) -> Bool: accepts(value,point,False{})

type Assertion is Data:
  Start{}
  End{}
  LineStart{crlf: Bool}
  LineEnd{crlf: Bool}
  Boundary{kind: U32,word: Class,unicode: Bool}

type Expression is Data:
  Empty{}
  Character{value: Class,insensitive: Bool}
  ByteCharacter{value: Class}
  Assert{value: Assertion}
  Sequence{left: Expression,right: Expression}
  Alternative{left: Expression,right: Expression}
  Repeat{value: Expression,minimum: Nat,maximum: Maybe<&2,Nat>}

type Instruction is Data:
  Consume{value: Class,insensitive: Bool,next: U32}
  ConsumeByte{value: Class,next: U32}
  Check{value: Assertion,next: U32}
  Split{left: U32,right: U32}
  Accept{}

type Builder is Data:
  Builder{next: U32,reversed: List<&2,Table.Entry<Instruction>>}

def push(instruction: Instruction,state: Builder) -> U32 & Builder:
  match state:
    case Builder{+next,reversed}: (next,Builder{(next + 1 : U32),Table.Entry{next,instruction} <> reversed})

def nextIndex(state: Builder) -> U32:
  match state:
    case Builder{index,_}: index

def bounded(+value: Nat) -> Nat: Bool.pick(Nat,Nat.is_le(value,65536n),value,65537n)

def repeatCost(+size: Nat,minimum: Nat,maximum: Maybe<&2,Nat>) -> Nat:
  match maximum:
    case None{}: Bool.pick(Nat,Nat.is_eq(size,Zero{}),Zero{},bounded(1n + (minimum + 1n) * size))
    case Some{+maximum}: Bool.pick(Nat,Nat.is_eq(size,Zero{}),Zero{},bounded(maximum * size + maximum - minimum))

def cost(expression: Expression) -> Nat:
  match expression:
    case Empty{}: 0n
    case Character{_,_}: 1n
    case ByteCharacter{_}: 1n
    case Assert{_}: 1n
    case Sequence{a,b}: bounded(cost(a) + cost(b))
    case Alternative{a,b}: bounded(1n + bounded(cost(a) + cost(b)))
    case Repeat{a,minimum,maximum}: repeatCost(cost(a),minimum,maximum)

# The compiler uses an explicit work stack; large bounded repetitions and long
# concatenations do not consume the host call stack. State expansion is checked
# before this pass, including the split states required by nullable loops.
type CompileTask is Data:
  Compile{expression: Expression,continuation: U32}
  ContinueSequence{expression: Expression}
  ContinueAlternative{expression: Expression,continuation: U32}
  FinishAlternative{left: U32}
  ContinueOptional{expression: Expression,continuation: U32}
  FinishSplit{continuation: U32}

type Compilation is Data:
  Compilation{work: List<&2,CompileTask>,builder: Builder,entry: U32}

def emitted(work: List<&2,CompileTask>,pair: U32 & Builder) -> Compilation:
  (entry,builder) = pair
  Compilation{work,builder,entry}

def compileRepeat(+value: Expression,minimum: Nat,maximum: Maybe<&2,Nat>,+continuation: U32,+work: List<&2,CompileTask>,+builder: Builder) -> Compilation:
  match minimum maximum:
    case Zero{} Some{Zero{}}: Compilation{work,builder,continuation}
    case Zero{} Some{Succ{remaining}}: Compilation{Compile{Repeat{value,Zero{},Some{remaining}},continuation} <> ContinueOptional{value,continuation} <> work,builder,continuation}
    case Zero{} None{}: Compilation{Compile{value,(nextIndex(builder) + U32.from_nat(cost(value)) : U32)} <> FinishSplit{continuation} <> work,builder,continuation}
    case Succ{minimum} maximum: Compilation{Compile{Repeat{value,minimum,Maybe.map(&2,Nat,Nat,n => n - 1n,maximum)},continuation} <> ContinueSequence{value} <> work,builder,continuation}

def compileStep(state: Compilation) -> Compilation:
  match state:
    case Compilation{Nil{},builder,+entry}: Compilation{Nil{},builder,entry}
    case Compilation{ContinueSequence{expression} <> work,builder,+entry}: Compilation{Compile{expression,entry} <> work,builder,entry}
    case Compilation{ContinueAlternative{expression,continuation} <> work,builder,+entry}: Compilation{Compile{expression,continuation} <> FinishAlternative{entry} <> work,builder,entry}
    case Compilation{FinishAlternative{left} <> work,builder,+entry}: emitted(work,push(Split{left,entry},builder))
    case Compilation{ContinueOptional{expression,continuation} <> work,builder,+entry}: Compilation{Compile{expression,entry} <> FinishSplit{continuation} <> work,builder,entry}
    case Compilation{FinishSplit{continuation} <> work,builder,+entry}: emitted(work,push(Split{entry,continuation},builder))
    case Compilation{Compile{Empty{},continuation} <> work,builder,_}: Compilation{work,builder,continuation}
    case Compilation{Compile{Character{value,insensitive},continuation} <> work,builder,_}: emitted(work,push(Consume{value,insensitive,continuation},builder))
    case Compilation{Compile{ByteCharacter{value},continuation} <> work,builder,_}: emitted(work,push(ConsumeByte{value,continuation},builder))
    case Compilation{Compile{Assert{value},continuation} <> work,builder,_}: emitted(work,push(Check{value,continuation},builder))
    case Compilation{Compile{Sequence{a,b},+continuation} <> work,builder,_}: Compilation{Compile{b,continuation} <> ContinueSequence{a} <> work,builder,continuation}
    case Compilation{Compile{Alternative{a,b},+continuation} <> work,builder,_}: Compilation{Compile{a,continuation} <> ContinueAlternative{b,continuation} <> work,builder,continuation}
    case Compilation{Compile{Repeat{+value,+minimum,+maximum},+continuation} <> +work,+builder,_}:
      Bool.pick(Unit -> Compilation,Nat.is_eq(cost(value),Zero{}),_ => Compilation{work,builder,continuation},_ => compileRepeat(value,minimum,maximum,continuation,work,builder))(Unit{})

@unsafe
def finishCompilation(state: Compilation) -> U32 & Builder:
  match state:
    case Compilation{Nil{},builder,+entry}: (entry,builder)
    case state: finishCompilation(compileStep(state))

# Exact literal searches use KMP instead of keeping a growing NFA frontier for
# every possible start in repeated text. Prefix construction and scanning are
# linear in comparisons; immutable indexed lookups add a logarithmic factor.
type LiteralRow is Data:
  LiteralRow{char: Char,failure: U32}

def literalRow(value: Maybe<&2,LiteralRow>) -> LiteralRow:
  match value:
    case Some{row}: row
    case None{}: LiteralRow{Chr{0},0}

def rowChar(row: LiteralRow) -> Char:
  match row:
    case LiteralRow{char,_}: char

def rowFailure(row: LiteralRow) -> U32:
  match row:
    case LiteralRow{_,failure}: failure

def sameLiteral(+a: Char,+b: Char,insensitive: Bool) -> Bool:
  Bool.pick(Unit -> Bool,insensitive,_ => Fold.equal(a,b),_ => Char.is_eq(a,b))(Unit{})

def literalAdvance(fuel: Nat,+table: Table.Table<LiteralRow>,+char: Char,+prefix: U32,+insensitive: Bool) -> U32:
  match fuel:
    case Zero{}: 0
    case Succ{fuel}:
      Bool.pick(Unit -> U32,sameLiteral(rowChar(literalRow(Table.get(LiteralRow,table,prefix))),char,insensitive),_ => (prefix + 1 : U32),
        _ => Bool.pick(Unit -> U32,U32.is_eq(prefix,0),_ => 0,_ => literalAdvance(fuel,table,char,rowFailure(literalRow(Table.get(LiteralRow,table,(prefix - 1 : U32)))),insensitive))(Unit{}))(Unit{})

def literalRows(text: String,+index: U32,reversed: List<&2,Table.Entry<LiteralRow>>) -> Table.Table<LiteralRow>:
  match text:
    case SNil{}: Table.fromSortedEntries(LiteralRow,List.reverse(&2,Table.Entry<LiteralRow>,reversed))
    case SCon{char,rest}: literalRows(rest,(index + 1 : U32),Table.Entry{index,LiteralRow{char,0}} <> reversed)

def literalFailures(text: String,+index: U32,prefix: U32,+table: Table.Table<LiteralRow>,+insensitive: Bool) -> Table.Table<LiteralRow>:
  match text:
    case SNil{}: table
    case SCon{+char,rest}:
      +next = literalAdvance(U32.to_nat(index) + 1n,table,char,prefix,insensitive)
      literalFailures(rest,(index + 1 : U32),next,Table.replace(LiteralRow,table,index,LiteralRow{char,next}),insensitive)

def literalTable(+text: String,insensitive: Bool) -> Table.Table<LiteralRow>:
  match text:
    case SNil{}: Table.fromSortedEntries(LiteralRow,Nil{})
    case SCon{char,rest}: literalFailures(rest,1,0,literalRows(SCon{char,rest},0,Nil{}),insensitive)

type Literal is Data:
  Literal{text: String,insensitive: Bool}

def literalMode(value: Maybe<&2,Bool>) -> Bool:
  match value:
    case None{}: False{}
    case Some{value}: value

def sameMode(previous: Maybe<&2,Bool>,mode: Bool) -> Bool:
  match previous:
    case None{}: True{}
    case Some{previous}: Bool.not(Bool.xor(previous,mode))

@unsafe
def expressionLiteral(work: List<&2,Expression>,+reversed: String,+insensitive: Maybe<&2,Bool>) -> Maybe<&2,Literal>:
  match work:
    case Nil{}: Some{Literal{String.reverse(reversed),literalMode(insensitive)}}
    case Empty{} <> rest: expressionLiteral(rest,reversed,insensitive)
    case Sequence{a,b} <> rest: expressionLiteral(a <> b <> rest,reversed,insensitive)
    case Repeat{_,Zero{},Some{Zero{}}} <> rest: expressionLiteral(rest,reversed,insensitive)
    case Repeat{+value,Succ{+minimum},Some{Succ{+maximum}}} <> +rest:
      Bool.pick(Unit -> Maybe<&2,Literal>,Nat.is_eq(cost(value),Zero{}),_ => expressionLiteral(rest,reversed,insensitive),_ => Bool.pick(Unit -> Maybe<&2,Literal>,Nat.is_eq(minimum,maximum),_ => expressionLiteral(value <> Repeat{value,minimum,Some{maximum}} <> rest,reversed,insensitive),_ => None{})(Unit{}))(Unit{})
    case Character{Range{+first,last},+mode} <> rest:
      Bool.pick(Unit -> Maybe<&2,Literal>,U32.is_eq(first,last) && sameMode(insensitive,mode),_ => expressionLiteral(rest,SCon{Chr{first},reversed},Some{mode}),_ => None{})(Unit{})
    case _: None{}

type Regex is Data:
  LiteralRegex{count: U32,table: Table.Table<LiteralRow>,insensitive: Bool}
  Regex{start: U32,count: U32,instructions: Table.Table<Instruction>}

def built(start: U32,state: Builder) -> Regex:
  match state:
    case Builder{+count,reversed}:
      Regex{start,count,Table.fromSortedEntries(Instruction,List.reverse(&2,Table.Entry<Instruction>,reversed))}

def finishProgram(pair: U32 & Builder) -> Regex:
  (start,state) = pair
  built(start,state)

def stringLength(text: String,count: Nat) -> Nat:
  match text:
    case SNil{}: count
    case SCon{_,rest}: stringLength(rest,Succ{count})

def compileLiteral(+text: String,+insensitive: Bool) -> Result<&2,&2,Error,Regex>:
  +count = stringLength(text,Zero{})
  Bool.pick(Unit -> Result<&2,&2,Error,Regex>,Nat.is_lt(count,65536n),_ => Done{LiteralRegex{U32.from_nat(count),literalTable(text,insensitive),insensitive}},_ => Fail{SizeLimit{}})(Unit{})

def compileSelected(literal: Maybe<&2,Literal>,expression: Expression) -> Regex:
  match literal:
    case Some{Literal{+text,+insensitive}}: LiteralRegex{U32.from_nat(stringLength(text,Zero{})),literalTable(text,insensitive),insensitive}
    case None{}: finishProgram(finishCompilation(Compilation{Compile{expression,0} <> Nil{},Builder{1,Table.Entry{0,Accept{}} <> Nil{}},0}))

def compileExpression(+expression: Expression) -> Result<&2,&2,Error,Regex>:
  Bool.pick(Unit -> Result<&2,&2,Error,Regex>,Nat.is_lt(cost(expression),65536n),
    _ => Done{compileSelected(expressionLiteral(expression <> Nil{},"",None{}),expression)},_ => Fail{SizeLimit{}})(Unit{})

def isChar(value: Maybe<&2,Char>,point: U32) -> Bool:
  match value:
    case None{}: False{}
    case Some{Chr{other}}: U32.is_eq(other,point)

def member(value: Maybe<&2,Char>,word: Class) -> Bool:
  match value:
    case None{}: False{}
    case Some{Chr{point}}: contains(word,point)

def boundary(kind: U32,+left: Bool,+right: Bool) -> Bool:
  match kind:
    case 0: Bool.xor(left,right)
    case 1: Bool.not(Bool.xor(left,right))
    case 2: Bool.not(left) && right
    case 3: left && Bool.not(right)
    case 4: Bool.not(left)
    case _: Bool.not(right)

def assertion(value: Assertion,+left: Maybe<&2,Char>,+right: Maybe<&2,Char>) -> Bool:
  match value:
    case Start{}: Maybe.is_none(&2,Char,left)
    case End{}: Maybe.is_none(&2,Char,right)
    case LineStart{crlf}: Maybe.is_none(&2,Char,left) || isChar(left,10) || (crlf && isChar(left,13) && Bool.not(isChar(right,10)))
    case LineEnd{+crlf}: Maybe.is_none(&2,Char,right) || (isChar(right,10) && Bool.not(crlf && isChar(left,13))) || (crlf && isChar(right,13))
    case Boundary{kind,+word,_}: boundary(kind,member(left,word),member(right,word))

type Frontier is Type:
  Frontier{seen: Array<U32>,pending: List<&2,U32>,next: List<&2,U32>,matched: Bool}

def consumes(value: Class,insensitive: Bool,right: Maybe<&2,Char>) -> Bool:
  match right:
    case None{}: False{}
    case Some{Chr{point}}: accepts(value,point,insensitive)

def instruction(value: Maybe<&2,Instruction>,seen: Array<U32>,+pending: List<&2,U32>,+next: List<&2,U32>,matched: Bool,+left: Maybe<&2,Char>,+right: Maybe<&2,Char>) -> Frontier:
  match value:
    case None{}: Frontier{seen,pending,next,matched}
    case Some{Accept{}}: Frontier{seen,pending,next,True{}}
    case Some{Split{a,b}}: Frontier{seen,a <> b <> pending,next,matched}
    case Some{Check{check,target}}: Frontier{seen,Bool.pick(List<&2,U32>,assertion(check,left,right),target <> pending,pending),next,matched}
    case Some{ConsumeByte{_,_}}: Frontier{seen,pending,next,matched}
    case Some{Consume{value,insensitive,target}}:
      Frontier{seen,pending,Bool.pick(List<&2,U32>,consumes(value,insensitive,right),target <> next,next),matched}

def visitFresh(fresh: Bool,seen: Array<U32>,+index: U32,stamp: U32,pending: List<&2,U32>,next: List<&2,U32>,matched: Bool,table: Table.Table<Instruction>,left: Maybe<&2,Char>,right: Maybe<&2,Char>) -> Frontier:
  match fresh:
    case False{}: Frontier{seen,pending,next,matched}
    case True{}: instruction(Table.get(Instruction,table,index),Array.set(U32,seen,index,stamp),pending,next,matched,left,right)

def visit(result: Array<U32> & U32,index: U32,+stamp: U32,pending: List<&2,U32>,next: List<&2,U32>,matched: Bool,table: Table.Table<Instruction>,left: Maybe<&2,Char>,right: Maybe<&2,Char>) -> Frontier:
  (seen,previous) = result
  visitFresh(Bool.not(U32.is_eq(previous,stamp)),seen,index,stamp,pending,next,matched,table,left,right)

def closure(fuel: Nat,state: Frontier,+stamp: U32,+table: Table.Table<Instruction>,+left: Maybe<&2,Char>,+right: Maybe<&2,Char>) -> Frontier:
  match fuel state:
    case _ Frontier{seen,_,next,True{}}: Frontier{seen,Nil{},next,True{}}
    case _ Frontier{seen,Nil{},next,matched}: Frontier{seen,Nil{},next,matched}
    case Zero{} state: state
    case Succ{remaining} Frontier{seen,+index <> pending,next,matched}:
      closure(remaining,visit(Array.get(U32,seen,index),index,stamp,pending,next,matched,table,left,right),stamp,table,left,right)

def arrayDepth(fuel: Nat,count: U32,depth: Nat) -> Nat:
  match fuel count:
    case _ 0: depth
    case Zero{} _: depth
    case Succ{fuel} count: arrayDepth(fuel,U32.shrn(count,1n),Succ{depth})

# A cursor owns its visitation array. Input chunks need not coincide with regex
# boundaries; only finish supplies end-of-input, so $ and word boundaries cannot
# accidentally treat a chunk boundary as the end of the haystack.
type Cursor is Type:
  Matched{}
  LiteralCursor{count: U32,table: Table.Table<LiteralRow>,insensitive: Bool,prefix: U32}
  NfaCursor{start: U32,count: U32,table: Table.Table<Instruction>,stamp: U32,left: Maybe<&2,Char>,pending: List<&2,U32>,seen: Array<U32>}

def create(regex: Regex) -> Cursor:
  match regex:
    case LiteralRegex{0,_,_}: Matched{}
    case LiteralRegex{count,table,insensitive}: LiteralCursor{count,table,insensitive,0}
    case Regex{start,+count,table}: NfaCursor{start,count,table,1,None{},Nil{},Array.new(U32,arrayDepth(32n,(count - 1 : U32),Zero{}),0)}

def afterLiteral(+prefix: U32,+count: U32,table: Table.Table<LiteralRow>,insensitive: Bool) -> Cursor:
  Bool.pick(Cursor,U32.is_eq(prefix,count),Matched{},LiteralCursor{count,table,insensitive,prefix})

def afterChar(+char: Char,+start: U32,+count: U32,+table: Table.Table<Instruction>,+stamp: U32,state: Frontier) -> Cursor:
  match state:
    case Frontier{_,_,_,True{}}: Matched{}
    case Frontier{seen,_,+next,False{}}:
      Bool.pick(Unit -> Cursor,U32.is_eq(stamp,4294967295),
        _ => NfaCursor{start,count,table,1,Some{char},next,Array.new(U32,arrayDepth(32n,(count - 1 : U32),Zero{}),0)},
        _ => NfaCursor{start,count,table,(stamp + 1 : U32),Some{char},next,seen})(Unit{})

# Start a candidate at every boundary, then close epsilon edges once. The next
# frontier consists exactly of states reached by consuming this scalar.
def feedChar(cursor: Cursor,+char: Char) -> Cursor:
  match cursor:
    case Matched{}: Matched{}
    case LiteralCursor{+count,+table,+insensitive,prefix}: afterLiteral(literalAdvance(U32.to_nat(count) + 1n,table,char,prefix,insensitive),count,table,insensitive)
    case NfaCursor{+start,+count,+table,+stamp,left,pending,seen}: afterChar(char,start,count,table,stamp,closure(U32.to_nat(count) * 3n + 2n,Frontier{seen,start <> pending,Nil{},False{}},stamp,table,left,Some{char}))

def feed(text: String,cursor: Cursor) -> Cursor:
  match text cursor:
    case _ Matched{}: Matched{}
    case SNil{} cursor: cursor
    case SCon{char,rest} cursor: feed(rest,feedChar(cursor,char))

def finalFrontier(state: Frontier) -> Bool:
  match state:
    case Frontier{_,_,_,matched}: matched

def finish(cursor: Cursor) -> Bool:
  match cursor:
    case Matched{}: True{}
    case LiteralCursor{_,_,_,_}: False{}
    case NfaCursor{start,+count,table,stamp,left,pending,seen}: finalFrontier(closure(U32.to_nat(count) * 3n + 2n,Frontier{seen,start <> pending,Nil{},False{}},stamp,table,left,None{}))

def isMatch(regex: Regex,text: String) -> Bool: finish(feed(text,create(regex)))

# The generated UCD payload stores delta-coded interval endpoints. Decode only
# referenced properties at compile time; matching uses an immutable range tree.
def propertyName(text: String,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,rest}:
      propertyName(rest,Bool.pick(String,Char.is_eq(char,'_') || Char.is_eq(char,'-') || Char.is_space(char),reversed,SCon{Bool.pick(Char,Char.is_eq(char,':'),'=',Char.to_lower(char)),reversed}))

def hashName(text: String,hash: U32) -> U32:
  match text:
    case SNil{}: hash
    case SCon{Chr{point},rest}: hashName(rest,(U32.xor(hash,point) * 16777619 : U32))

def decodedRanges(bytes: List<&2,U32>,+gap: Bool,+previous: U32,+start: U32,word: U32,+shift: Nat,+reversed: List<&2,Table.Entry<U32>>) -> Class:
  match bytes:
    case Nil{}: Property{Table.fromSortedEntries(U32,List.reverse(&2,Table.Entry<U32>,reversed))}
    case +byte <> +rest:
      +value = U32.or(word,U32.shln(U32.and(byte,127),shift))
      Bool.pick(Unit -> Class,U32.is_ge(byte,128),
        _ => decodedRanges(rest,gap,previous,start,value,shift + 7n,reversed),
        _ => decodedRanges(rest,Bool.not(gap),Bool.pick(U32,gap,previous,(start + value + 1 : U32)),Bool.pick(U32,gap,(previous + value : U32),start),0,Zero{},Bool.pick(List<&2,Table.Entry<U32>>,gap,reversed,Table.Entry{start,(start + value : U32)} <> reversed)))(Unit{})

def propertyBytes(result: Result<&2,&2,Base64.Error,List<&2,U32>>) -> Result<&2,&2,Error,Class>:
  match result:
    case Fail{_}: Fail{Syntax{"Invalid generated Unicode data"}}
    case Done{bytes}: Done{decodedRanges(bytes,True{},0,0,0,Zero{},Nil{})}

def propertyAlias(name: String,value: Maybe<&2,Unicode.Alias>) -> Result<&2,&2,Error,Class>:
  match value:
    case None{}: Fail{Syntax{"Unknown Unicode property"}}
    case Some{Unicode.Alias{expected,index}}: Bool.pick(Unit -> Result<&2,&2,Error,Class>,String.eq(name,expected),_ => propertyBytes(Base64.decode(Unicode.ranges(index))),_ => Fail{Syntax{"Unknown Unicode property"}})(Unit{})

def property(text: String) -> Result<&2,&2,Error,Class>:
  +name = propertyName(text,"")
  propertyAlias(name,Table.get(Unicode.Alias,Unicode.aliases(),hashName(name,2166136261)))

type Atom is Data:
  Atom{expression: Expression,rest: String}

def enabled(flags: U32,mask: U32) -> Bool: Bool.not(U32.is_eq(U32.and(flags,mask),0))

def character(+value: Class,+flags: U32) -> Expression:
  Bool.pick(Unit -> Expression,enabled(flags,1) && Bool.not(enabled(flags,32)),_ => Character{CaseAscii{value},False{}},_ => Character{value,enabled(flags,1)})(Unit{})

def byteCharacter(+value: Class,+flags: U32) -> Expression:
  Bool.pick(Expression,enabled(flags,1),ByteCharacter{CaseAscii{value}},ByteCharacter{value})

def literal(char: Char,flags: U32) -> Expression:
  +point = Char.to_u32(char)
  character(Range{point,point},flags)

def asciiWord() -> Class:
  Union{Range{48,57},Union{Range{65,90},Union{Range{97,122},Range{95,95}}}}

def shorthand(+kind: Char,unicode: Bool) -> Result<&2,&2,Error,Class>:
  match kind unicode:
    case 'd' True{}: property("Decimal_Number")
    case 's' True{}: property("White_Space")
    case 'w' True{}: property("Word")
    case 'd' False{}: Done{Range{48,57}}
    case 's' False{}: Done{Union{Range{9,13},Range{32,32}}}
    case 'w' False{}: Done{asciiWord()}
    case _ _: Fail{Syntax{"Unknown character class"}}

def matchesNonAsciiByte(fuel: Nat,+value: Class,+point: U32) -> Bool:
  match fuel:
    case Zero{}: False{}
    case Succ{fuel}: Bool.pick(Unit -> Bool,contains(value,point),_ => True{},_ => matchesNonAsciiByte(fuel,value,(point + 1 : U32)))(Unit{})

def scalarClass(+value: Class,+flags: U32,rest: String) -> Result<&2,&2,Error,Atom>:
  +selected = Bool.pick(Class,enabled(flags,32) || enabled(flags,128),value,Intersection{value,Range{0,255}})
  +requires = Bool.pick(Unit -> Bool,enabled(flags,32) || enabled(flags,128) || enabled(flags,512),_ => False{},_ => matchesNonAsciiByte(128n,selected,128))(Unit{})
  Bool.pick(Unit -> Result<&2,&2,Error,Atom>,requires,_ => Fail{RequiresByteInput{}},_ => Done{Atom{Bool.pick(Unit -> Expression,enabled(flags,512) && Bool.not(enabled(flags,32) || enabled(flags,128)),_ => byteCharacter(selected,flags),_ => character(selected,flags))(Unit{}),rest}})(Unit{})

def classAtom(result: Result<&2,&2,Error,Class>,flags: U32,negative: Bool,rest: String) -> Result<&2,&2,Error,Atom>:
  match result:
    case Fail{error}: Fail{error}
    case Done{+value}: scalarClass(Bool.pick(Class,negative,Negation{value},value),flags,rest)

def wordAtom(result: Result<&2,&2,Error,Class>,kind: U32,unicode: Bool,rest: String) -> Result<&2,&2,Error,Atom>:
  match result:
    case Fail{error}: Fail{error}
    case Done{word}: Done{Atom{Assert{Boundary{kind,word,unicode}},rest}}

def regexWhitespace(char: Char) -> Bool:
  match char:
    case Chr{+point}: (U32.is_ge(point,9) && U32.is_le(point,13)) || U32.is_eq(point,32) || U32.is_eq(point,133) || U32.is_eq(point,160) || U32.is_eq(point,5760) || (U32.is_ge(point,8192) && U32.is_le(point,8202)) || U32.is_eq(point,8232) || U32.is_eq(point,8233) || U32.is_eq(point,8239) || U32.is_eq(point,8287) || U32.is_eq(point,12288)

def escapedScalar(+point: U32,+flags: U32,+rest: String) -> Result<&2,&2,Error,Atom>:
  +raw = Bool.not(enabled(flags,32)) && enabled(flags,256)
  +nonAsciiClass = Bool.not(enabled(flags,32)) && enabled(flags,128) && U32.is_ge(point,128) && Bool.not(raw)
  Bool.pick(Unit -> Result<&2,&2,Error,Atom>,nonAsciiClass,
    _ => Fail{Bool.pick(Error,enabled(flags,512),Syntax{"Non-ASCII scalar in a byte class"},RequiresByteInput{})},
    _ => Bool.pick(Unit -> Result<&2,&2,Error,Atom>,raw && U32.is_ge(point,128) && Bool.not(enabled(flags,512)),
      _ => Fail{RequiresByteInput{}},
      _ => Bool.pick(Unit -> Result<&2,&2,Error,Atom>,U32.is_le(point,1114111) && Bool.not(U32.is_ge(point,55296) && U32.is_le(point,57343)),
        _ => Done{Atom{Bool.pick(Unit -> Expression,raw && enabled(flags,512) && Bool.not(enabled(flags,128)),_ => byteCharacter(Range{point,point},flags),_ => character(Range{point,point},flags))(Unit{}),rest}},
        _ => Fail{Syntax{"Invalid Unicode scalar escape"}})(Unit{}))(Unit{}))(Unit{})

def escapedPoint(+point: U32,+flags: U32,+rest: String) -> Result<&2,&2,Error,Atom>:
  Bool.pick(Unit -> Result<&2,&2,Error,Atom>,enabled(flags,1024) && Bool.not(enabled(flags,128)) && U32.is_eq(point,10),_ => Fail{Syntax{"Newline literals require multiline search"}},_ => escapedScalar(point,flags,rest))(Unit{})

def hexDigit(+point: U32) -> Maybe<&2,U32>:
  Bool.pick(Maybe<&2,U32>,U32.is_ge(point,48) && U32.is_le(point,57),Some{(point - 48 : U32)},Bool.pick(Maybe<&2,U32>,U32.is_ge(point,65) && U32.is_le(point,70),Some{(point - 55 : U32)},Bool.pick(Maybe<&2,U32>,U32.is_ge(point,97) && U32.is_le(point,102),Some{(point - 87 : U32)},None{})))

def addHex(value: Maybe<&2,U32>,+word: U32) -> Maybe<&2,U32>:
  match value:
    case None{}: None{}
    case Some{digit}: Bool.pick(Maybe<&2,U32>,U32.is_le(word,69631),Some{(word * 16 + digit : U32)},None{})

def hexEscape(text: String,+flags: U32,remaining: Nat,braced: Bool,+count: Nat,word: Maybe<&2,U32>) -> Result<&2,&2,Error,Atom>:
  match text remaining braced word:
    case _ _ _ None{}: Fail{Syntax{"Invalid hexadecimal escape"}}
    case SCon{'}',rest} _ True{} Some{word}: Bool.pick(Result<&2,&2,Error,Atom>,Nat.is_gt(count,Zero{}),escapedPoint(word,flags,rest),Fail{Syntax{"Empty hexadecimal escape"}})
    case text Zero{} False{} Some{word}: escapedPoint(word,flags,text)
    case SCon{char,rest} remaining True{} Some{word}:
      +remaining = {remaining : Nat}
      +word = {word : U32}
      +char = {char : Char}
      +rest = {rest : String}
      Bool.pick(Unit -> Result<&2,&2,Error,Atom>,enabled(flags,64) && regexWhitespace(char),_ => hexEscape(rest,flags,remaining,True{},count,Some{word}),_ => hexEscape(rest,flags,remaining,True{},Succ{count},addHex(hexDigit(Char.to_u32(char)),word)))(Unit{})
    case SCon{char,rest} Succ{remaining} False{} Some{word}:
      +point = Char.to_u32(char)
      +rest = {rest : String}
      +remaining = {remaining : Nat}
      +word = {word : U32}
      Bool.pick(Unit -> Result<&2,&2,Error,Atom>,enabled(flags,64) && regexWhitespace(Chr{point}),_ => hexEscape(rest,flags,Succ{remaining},False{},count,Some{word}),_ => hexEscape(rest,flags,remaining,False{},Succ{count},addHex(hexDigit(point),word)))(Unit{})
    case _ _ _ _: Fail{Syntax{"Unterminated hexadecimal escape"}}

def beginHex(text: String,+flags: U32,+width: Nat) -> Result<&2,&2,Error,Atom>:
  match text:
    case SCon{'{',rest}: hexEscape(rest,flags,6n,True{},Zero{},Some{0})
    case text: hexEscape(text,U32.or(flags,Bool.pick(U32,Nat.is_eq(width,2n),256,0)),width,False{},Zero{},Some{0})

def propertyQuery(text: String,negative: Bool,reversed: String,flags: U32,rest: String) -> Result<&2,&2,Error,Atom>:
  match text:
    case SNil{}: classAtom(property(String.reverse(reversed)),flags,negative,rest)
    case SCon{'!',SCon{'=',tail}}: propertyQuery(tail,Bool.not(negative),SCon{'=',reversed},flags,rest)
    case SCon{char,tail}: propertyQuery(tail,negative,SCon{char,reversed},flags,rest)

def namedProperty(text: String,flags: U32,negative: Bool,reversed: String) -> Result<&2,&2,Error,Atom>:
  match text:
    case SNil{}: Fail{Syntax{"Unterminated Unicode property"}}
    case SCon{'}',rest}: propertyQuery(String.reverse(reversed),negative,"",flags,rest)
    case SCon{char,rest}: namedProperty(rest,flags,negative,SCon{char,reversed})

def beginProperty(text: String,flags: U32,negative: Bool) -> Result<&2,&2,Error,Atom>:
  match text:
    case SCon{'{',rest}: namedProperty(rest,flags,negative,"")
    case SCon{char,rest}: classAtom(property(SCon{char,SNil{}}),flags,negative,rest)
    case SNil{}: Fail{Syntax{"Missing Unicode property"}}

def wordKind(name: String) -> Maybe<&2,U32>:
  match name:
    case "start": Some{2}
    case "end": Some{3}
    case "start-half": Some{4}
    case "end-half": Some{5}
    case _: None{}

def wordNamed(kind: Maybe<&2,U32>,+flags: U32,rest: String) -> Result<&2,&2,Error,Atom>:
  match kind:
    case None{}: Fail{Syntax{"Unknown word boundary"}}
    case Some{kind}: wordAtom(shorthand('w',enabled(flags,32)),kind,enabled(flags,32),rest)

def wordName(text: String,flags: U32,reversed: String) -> Result<&2,&2,Error,Atom>:
  match text:
    case SNil{}: Fail{Syntax{"Unterminated word boundary"}}
    case SCon{'}',rest}: wordNamed(wordKind(String.reverse(reversed)),flags,rest)
    case SCon{char,rest}: wordName(rest,flags,SCon{char,reversed})

def wordEscape(text: String,+flags: U32) -> Result<&2,&2,Error,Atom>:
  match text:
    case SCon{'{',rest}: wordName(rest,flags,"")
    case text: wordAtom(shorthand('w',enabled(flags,32)),0,enabled(flags,32),text)

def escape(text: String,+flags: U32) -> Result<&2,&2,Error,Atom>:
  match text:
    case SNil{}: Fail{Syntax{"Dangling escape"}}
    case SCon{'n',rest}: escapedPoint(10,flags,rest)
    case SCon{'r',rest}: escapedPoint(13,flags,rest)
    case SCon{'t',rest}: escapedPoint(9,flags,rest)
    case SCon{'a',rest}: escapedPoint(7,flags,rest)
    case SCon{'f',rest}: escapedPoint(12,flags,rest)
    case SCon{'v',rest}: escapedPoint(11,flags,rest)
    case SCon{'x',rest}: beginHex(rest,flags,2n)
    case SCon{'u',rest}: beginHex(rest,flags,4n)
    case SCon{'U',rest}: beginHex(rest,flags,8n)
    case SCon{'d',rest}: classAtom(shorthand('d',enabled(flags,32)),flags,False{},rest)
    case SCon{'D',rest}: classAtom(shorthand('d',enabled(flags,32)),flags,True{},rest)
    case SCon{'s',rest}: classAtom(shorthand('s',enabled(flags,32)),flags,False{},rest)
    case SCon{'S',rest}: classAtom(shorthand('s',enabled(flags,32)),flags,True{},rest)
    case SCon{'w',rest}: classAtom(shorthand('w',enabled(flags,32)),flags,False{},rest)
    case SCon{'W',rest}: classAtom(shorthand('w',enabled(flags,32)),flags,True{},rest)
    case SCon{'p',rest}: Bool.pick(Unit -> Result<&2,&2,Error,Atom>,enabled(flags,32),_ => beginProperty(rest,flags,False{}),_ => Fail{Syntax{"Unicode properties require Unicode mode"}})(Unit{})
    case SCon{'P',rest}: Bool.pick(Unit -> Result<&2,&2,Error,Atom>,enabled(flags,32),_ => beginProperty(rest,flags,True{}),_ => Fail{Syntax{"Unicode properties require Unicode mode"}})(Unit{})
    case SCon{'A',rest}: Done{Atom{Assert{Start{}},rest}}
    case SCon{'z',rest}: Done{Atom{Assert{End{}},rest}}
    case SCon{'b',rest}: wordEscape(rest,flags)
    case SCon{'B',rest}: wordAtom(shorthand('w',enabled(flags,32)),1,enabled(flags,32),rest)
    case SCon{'<',rest}: wordAtom(shorthand('w',enabled(flags,32)),2,enabled(flags,32),rest)
    case SCon{'>',rest}: wordAtom(shorthand('w',enabled(flags,32)),3,enabled(flags,32),rest)
    case SCon{char,rest}:
      +char = {char : Char}
      Bool.pick(Result<&2,&2,Error,Atom>,Char.is_alpha(char) || Char.is_digit(char),Fail{Syntax{"Unsupported escape (backreferences are not regular)"}},Done{Atom{literal(char,flags),rest}})

def asciiClass(name: String) -> Result<&2,&2,Error,Class>:
  match name:
    case "alnum": Done{Union{Range{48,57},Union{Range{65,90},Range{97,122}}}}
    case "alpha": Done{Union{Range{65,90},Range{97,122}}}
    case "ascii": Done{Range{0,127}}
    case "blank": Done{Union{Range{9,9},Range{32,32}}}
    case "cntrl": Done{Union{Range{0,31},Range{127,127}}}
    case "digit": Done{Range{48,57}}
    case "graph": Done{Range{33,126}}
    case "lower": Done{Range{97,122}}
    case "print": Done{Range{32,126}}
    case "punct": Done{Union{Range{33,47},Union{Range{58,64},Union{Range{91,96},Range{123,126}}}}}
    case "space": Done{Union{Range{9,13},Range{32,32}}}
    case "upper": Done{Range{65,90}}
    case "word": Done{asciiWord()}
    case "xdigit": Done{Union{Range{48,57},Union{Range{65,70},Range{97,102}}}}
    case _: Fail{Syntax{"Unknown ASCII character class"}}

def asciiName(text: String,flags: U32,negative: Bool,reversed: String) -> Result<&2,&2,Error,Atom>:
  match text:
    case SNil{}: Fail{Syntax{"Unterminated ASCII class"}}
    case SCon{':',SCon{']',rest}}: classAtom(asciiClass(String.reverse(reversed)),flags,negative,rest)
    case SCon{char,rest}: asciiName(rest,flags,negative,SCon{char,reversed})

def union(left: Class,right: Class) -> Class:
  match left right:
    case EmptyClass{} right: right
    case left EmptyClass{}: left
    case left right: Union{left,right}

def combine(operator: U32,left: Class,right: Class) -> Class:
  match operator:
    case 1: Intersection{left,right}
    case 2: Difference{left,right}
    case 3: Symmetric{left,right}
    case _: union(left,right)

type ClassFrame is Data:
  ClassFrame{negative: Bool,left: Class,operator: U32,current: Class,pending: Maybe<&2,U32>,range: Bool,initial: Bool}

type ClassParsing is Data:
  InClass{text: String,frame: ClassFrame,parents: List<&2,ClassFrame>}
  EndClass{value: Class,rest: String}
  BadClass{error: Error}

def pendingClass(current: Class,point: Maybe<&2,U32>) -> Class:
  match point:
    case None{}: current
    case Some{+point}: union(current,Range{point,point})

def classUnion(frame: ClassFrame) -> Class:
  match frame:
    case ClassFrame{_,left,operator,current,pending,_,_}: combine(operator,left,pendingClass(current,pending))

def frameValue(frame: ClassFrame) -> Class:
  match frame:
    case ClassFrame{negative,left,operator,current,pending,_,_}:
      +value = combine(operator,left,pendingClass(current,pending))
      Bool.pick(Class,negative,Negation{value},value)

def classSingle(value: Class) -> Maybe<&2,U32>:
  match value:
    case Range{+first,last}: Bool.pick(Maybe<&2,U32>,U32.is_eq(first,last),Some{first},None{})
    case _: None{}

def appendClassRange(first: Maybe<&2,U32>,last: Maybe<&2,U32>,text: String,negative: Bool,left: Class,operator: U32,current: Class,parents: List<&2,ClassFrame>) -> ClassParsing:
  match first last:
    case Some{+first} Some{+last}: Bool.pick(ClassParsing,U32.is_le(first,last),InClass{text,ClassFrame{negative,left,operator,union(current,Range{first,last}),None{},False{},False{}},parents},BadClass{Syntax{"Reversed character range"}})
    case _ _: BadClass{Syntax{"Character range endpoints must be single scalars"}}

def appendClass(value: Class,text: String,frame: ClassFrame,parents: List<&2,ClassFrame>) -> ClassParsing:
  match frame:
    case ClassFrame{negative,left,operator,current,pending,True{},_}: appendClassRange(pending,classSingle(value),text,negative,left,operator,current,parents)
    case ClassFrame{negative,left,operator,current,pending,False{},_}:
      InClass{text,ClassFrame{negative,left,operator,union(pendingClass(current,pending),value),None{},False{},False{}},parents}

# Keep a final literal pending so a following dash can form a range.
def appendScalar(+point: U32,text: String,frame: ClassFrame,parents: List<&2,ClassFrame>) -> ClassParsing:
  match frame:
    case ClassFrame{negative,left,operator,current,pending,True{},_}: appendClassRange(pending,Some{point},text,negative,left,operator,current,parents)
    case ClassFrame{negative,left,operator,current,pending,False{},_}: InClass{text,ClassFrame{negative,left,operator,pendingClass(current,pending),Some{point},False{},False{}},parents}

def classEscaped(result: Result<&2,&2,Error,Atom>,+frame: ClassFrame,+parents: List<&2,ClassFrame>) -> ClassParsing:
  match result:
    case Fail{error}: BadClass{error}
    case Done{Atom{Character{Range{+first,+last},_},+text}}: Bool.pick(Unit -> ClassParsing,U32.is_eq(first,last),_ => appendScalar(first,text,frame,parents),_ => appendClass(Range{first,last},text,frame,parents))(Unit{})
    case Done{Atom{Character{value,_},text}}: appendClass(value,text,frame,parents)
    case Done{_}: BadClass{Syntax{"Assertions are not valid in a character class"}}

def frameNegative(frame: ClassFrame) -> Bool:
  match frame:
    case ClassFrame{negative,_,_,_,_,_,_}: negative

def classOperator(operator: U32,text: String,frame: ClassFrame,parents: List<&2,ClassFrame>) -> ClassParsing:
  match operator frame:
    case _ ClassFrame{_,_,_,_,_,True{},_}: BadClass{Syntax{"Missing character range endpoint"}}
    case 2 ClassFrame{negative,left,previous,current,pending,False{},True{}}:
      appendScalar(45,text,ClassFrame{negative,left,previous,current,pending,False{},True{}},parents)
    case operator frame:
      +frame = {frame : ClassFrame}
      InClass{text,ClassFrame{frameNegative(frame),classUnion(frame),operator,EmptyClass{},None{},False{},False{}},parents}

def beginClass(text: String,parents: List<&2,ClassFrame>) -> ClassParsing:
  match text:
    case SCon{'^',rest}: InClass{rest,ClassFrame{True{},EmptyClass{},0,EmptyClass{},None{},False{},True{}},parents}
    case text: InClass{text,ClassFrame{False{},EmptyClass{},0,EmptyClass{},None{},False{},True{}},parents}

def endClass(text: String,frame: ClassFrame,parents: List<&2,ClassFrame>) -> ClassParsing:
  match frame parents:
    case ClassFrame{_,_,_,_,_,True{},_} _: BadClass{Syntax{"Missing character range endpoint"}}
    case frame Nil{}: EndClass{frameValue(frame),text}
    case frame parent <> parents: appendClass(frameValue(frame),text,parent,parents)

def classDash(text: String,frame: ClassFrame,parents: List<&2,ClassFrame>) -> ClassParsing:
  match text frame:
    case SCon{']',rest} frame: appendScalar(45,SCon{']',rest},frame,parents)
    case text ClassFrame{negative,left,operator,current,Some{point},False{},_}: InClass{text,ClassFrame{negative,left,operator,current,Some{point},True{},False{}},parents}
    case text frame: appendScalar(45,text,frame,parents)

def skipComment(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'\n',rest}: rest
    case SCon{_,rest}: skipComment(rest)

def classStep(state: ClassParsing,+flags: U32) -> ClassParsing:
  match state:
    case InClass{SNil{},_,_}: BadClass{Syntax{"Unterminated character class"}}
    case InClass{SCon{'^',rest},ClassFrame{False{},EmptyClass{},0,EmptyClass{},None{},False{},True{}},parents}: InClass{rest,ClassFrame{True{},EmptyClass{},0,EmptyClass{},None{},False{},True{}},parents}
    case InClass{SCon{']',rest},ClassFrame{negative,left,operator,current,pending,range,True{}},parents}: appendScalar(93,rest,ClassFrame{negative,left,operator,current,pending,range,True{}},parents)
    case InClass{SCon{']',rest},frame,parents}: endClass(rest,frame,parents)
    case InClass{SCon{'[',SCon{':',SCon{'^',rest}}},frame,parents}: classEscaped(asciiName(rest,U32.or(U32.and(flags,4294967294),128),True{},""),frame,parents)
    case InClass{SCon{'[',SCon{':',rest}},frame,parents}: classEscaped(asciiName(rest,U32.or(U32.and(flags,4294967294),128),False{},""),frame,parents)
    case InClass{SCon{'[',rest},frame,parents}: beginClass(rest,frame <> parents)
    case InClass{SCon{'&',SCon{'&',rest}},frame,parents}: classOperator(1,rest,frame,parents)
    case InClass{SCon{'-',SCon{'-',rest}},frame,parents}: classOperator(2,rest,frame,parents)
    case InClass{SCon{'~',SCon{'~',rest}},frame,parents}: classOperator(3,rest,frame,parents)
    case InClass{SCon{'-',rest},frame,parents}: classDash(rest,frame,parents)
    case InClass{SCon{'\\',rest},frame,parents}: classEscaped(escape(rest,U32.or(U32.and(flags,4294967294),128)),frame,parents)
    case InClass{SCon{'#',+rest},+frame,+parents}: Bool.pick(Unit -> ClassParsing,enabled(flags,64),_ => InClass{skipComment(rest),frame,parents},_ => appendScalar(35,rest,frame,parents))(Unit{})
    case InClass{SCon{char,rest},frame,parents}:
      +char = {char : Char}
      +rest = {rest : String}
      +frame = {frame : ClassFrame}
      +parents = {parents : List<&2,ClassFrame>}
      Bool.pick(Unit -> ClassParsing,enabled(flags,64) && regexWhitespace(char),_ => InClass{rest,frame,parents},_ => Bool.pick(Unit -> ClassParsing,Bool.not(enabled(flags,32)) && U32.is_ge(Char.to_u32(char),128),_ => BadClass{Bool.pick(Error,enabled(flags,512),Syntax{"Non-ASCII scalar in a byte class"},RequiresByteInput{})},_ => appendScalar(Char.to_u32(char),rest,frame,parents))(Unit{}))(Unit{})
    case state: state

def readClass(fuel: Nat,state: ClassParsing,+flags: U32) -> Result<&2,&2,Error,Atom>:
  match fuel state:
    case _ BadClass{error}: Fail{error}
    case _ EndClass{Range{10,10},rest}: Bool.pick(Unit -> Result<&2,&2,Error,Atom>,enabled(flags,1024),_ => Fail{Syntax{"Newline literals require multiline search"}},_ => scalarClass(Range{10,10},flags,rest))(Unit{})
    case _ EndClass{value,rest}: scalarClass(value,flags,rest)
    case Zero{} _: Fail{SizeLimit{}}
    case Succ{fuel} state: readClass(fuel,classStep(state,flags),flags)

def textLength(text: String,count: Nat) -> Nat:
  match text:
    case SNil{}: count
    case SCon{_,rest}: textLength(rest,Succ{count})

def expressionPairs(values: List<&2,Expression>,+alternative: Bool,reversed: List<&2,Expression>) -> List<&2,Expression>:
  match values:
    case Nil{}: List.reverse(&2,Expression,reversed)
    case last <> Nil{}: List.reverse(&2,Expression,last <> reversed)
    case +a <> +b <> rest: expressionPairs(rest,alternative,Bool.pick(Expression,alternative,Alternative{a,b},Sequence{a,b}) <> reversed)

def expressionRounds(fuel: Nat,values: List<&2,Expression>,+alternative: Bool) -> Expression:
  match fuel values:
    case _ Nil{}: Empty{}
    case _ value <> Nil{}: value
    case Zero{} _: Empty{}
    case Succ{fuel} values: expressionRounds(fuel,expressionPairs(values,alternative,Nil{}),alternative)

def expressions(values: List<&2,Expression>,alternative: Bool) -> Expression:
  expressionRounds(32n,List.reverse(&2,Expression,values),alternative)

type Frame is Data:
  Frame{flags: U32,sequence: List<&2,Expression>,alternatives: List<&2,Expression>,names: List<&2,String>}

type Parsing is Data:
  Parsing{text: String,frame: Frame,parents: List<&2,Frame>,depth: Nat}
  Parsed{expression: Expression}
  ParseError{error: Error}

def frameExpression(frame: Frame) -> Expression:
  match frame:
    case Frame{_,sequence,alternatives,_}: expressions(expressions(sequence,False{}) <> alternatives,True{})

def appendAtom(result: Result<&2,&2,Error,Atom>,frame: Frame,parents: List<&2,Frame>,depth: Nat) -> Parsing:
  match result frame:
    case Fail{error} _: ParseError{error}
    case Done{Atom{expression,text}} Frame{flags,sequence,alternatives,names}: Parsing{text,Frame{flags,expression <> sequence,alternatives,names},parents,depth}

def captureNames(frame: Frame) -> List<&2,String>:
  match frame:
    case Frame{_,_,_,names}: names

def withNames(frame: Frame,names: List<&2,String>) -> Frame:
  match frame:
    case Frame{flags,sequence,alternatives,_}: Frame{flags,sequence,alternatives,names}

def groupOpen(text: String,flags: U32,+frame: Frame,parents: List<&2,Frame>,+depth: Nat) -> Parsing:
  Bool.pick(Parsing,Nat.is_lt(depth,250n),Parsing{text,Frame{flags,Nil{},Nil{},captureNames(frame)},frame <> parents,Succ{depth}},ParseError{SizeLimit{}})

def groupClose(text: String,+frame: Frame,parents: List<&2,Frame>,depth: Nat) -> Parsing:
  match parents:
    case Nil{}: ParseError{Syntax{"Unopened group"}}
    case parent <> parents: appendAtom(Done{Atom{frameExpression(frame),text}},withNames(parent,captureNames(frame)),parents,depth - 1n)

def flagsOf(frame: Frame) -> U32:
  match frame:
    case Frame{flags,_,_,_}: flags

def flagsChanged(flags: U32,frame: Frame) -> Frame:
  match frame:
    case Frame{_,sequence,alternatives,names}: Frame{flags,sequence,alternatives,names}

def flagMask(char: Char) -> U32:
  match char:
    case 'i': 1
    case 'm': 2
    case 's': 4
    case 'R': 8
    case 'U': 16
    case 'u': 32
    case 'x': 64
    case _: 0

def groupFlags(text: String,+flags: U32,+enable: Bool,+seen: U32,frame: Frame,parents: List<&2,Frame>,depth: Nat) -> Parsing:
  match text:
    case SNil{}: ParseError{Syntax{"Unterminated group flags"}}
    case SCon{')',rest}: Bool.pick(Parsing,U32.is_eq(seen,0) || enabled(seen,128),ParseError{Syntax{"Empty group flags"}},Parsing{rest,flagsChanged(flags,frame),parents,depth})
    case SCon{':',rest}: Bool.pick(Unit -> Parsing,enabled(seen,128),_ => ParseError{Syntax{"Flag negation requires a flag"}},_ => groupOpen(rest,flags,frame,parents,depth))(Unit{})
    case SCon{'-',rest}: Bool.pick(Unit -> Parsing,enable,_ => groupFlags(rest,flags,False{},U32.or(seen,128),frame,parents,depth),_ => ParseError{Syntax{"Repeated flag negation"}})(Unit{})
    case SCon{char,rest}:
      +mask = flagMask(char)
      Bool.pick(Unit -> Parsing,U32.is_eq(mask,0) || enabled(seen,mask),_ => ParseError{Syntax{"Unknown or repeated group flag"}},_ => groupFlags(rest,Bool.pick(U32,enable,U32.or(flags,mask),U32.and(flags,U32.not(mask))),enable,U32.and(U32.or(seen,mask),4294967167),frame,parents,depth))(Unit{})

def namedBefore(names: List<&2,String>,+name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case head <> rest: Bool.pick(Unit -> Bool,String.eq(head,name),_ => True{},_ => namedBefore(rest,name))(Unit{})

def nameProperty(result: Result<&2,&2,Error,Class>,char: Char) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{value}: contains(value,Char.to_u32(char))

def nameCharacter(+char: Char,+first: Bool) -> Bool:
  Bool.pick(Unit -> Bool,U32.is_le(Char.to_u32(char),127),
    _ => Char.is_alpha(char) || Char.is_eq(char,'_') || (Bool.not(first) && (Char.is_digit(char) || Char.is_eq(char,'.') || Char.is_eq(char,'[') || Char.is_eq(char,']'))),
    _ => nameProperty(property("Alphabetic"),char) || (Bool.not(first) && nameProperty(property("Number"),char)))(Unit{})

def namedGroup(text: String,+frame: Frame,parents: List<&2,Frame>,depth: Nat,+count: Nat,reversed: String) -> Parsing:
  match text:
    case SNil{}: ParseError{Syntax{"Unterminated capture name"}}
    case SCon{'>',rest}:
      +name = String.reverse(reversed)
      Bool.pick(Unit -> Parsing,Nat.is_gt(count,Zero{}) && Bool.not(namedBefore(captureNames(frame),name)),_ => groupOpen(rest,flagsOf(frame),withNames(frame,name <> captureNames(frame)),parents,depth),_ => ParseError{Syntax{"Empty or repeated capture name"}})(Unit{})
    case SCon{char,rest}:
      +char = {char : Char}
      Bool.pick(Unit -> Parsing,nameCharacter(char,Nat.is_eq(count,Zero{})),_ => namedGroup(rest,frame,parents,depth,Succ{count},SCon{char,reversed}),_ => ParseError{Syntax{"Invalid capture name"}})(Unit{})

def beginGroup(text: String,+frame: Frame,parents: List<&2,Frame>,depth: Nat) -> Parsing:
  match text:
    case SCon{'?',SCon{'P',SCon{'<',rest}}}: namedGroup(rest,frame,parents,depth,Zero{},"")
    case SCon{'?',SCon{'<',rest}}: namedGroup(rest,frame,parents,depth,Zero{},"")
    case SCon{'?',rest}: groupFlags(rest,flagsOf(frame),True{},0,frame,parents,depth)
    case text: groupOpen(text,flagsOf(frame),frame,parents,depth)

def lazySuffix(text: String) -> String:
  match text:
    case SCon{'?',rest}: rest
    case text: text

def repeated(text: String,minimum: Nat,maximum: Maybe<&2,Nat>,frame: Frame,parents: List<&2,Frame>,depth: Nat) -> Parsing:
  match frame:
    case Frame{_,Nil{},_,_}: ParseError{Syntax{"Repetition has no preceding expression"}}
    case Frame{flags,value <> sequence,alternatives,names}: Parsing{lazySuffix(text),Frame{flags,Repeat{value,minimum,maximum} <> sequence,alternatives,names},parents,depth}

def repeatBounds(text: String,+minimum: Nat,+maximum: Nat,+comma: Bool,+haveDigit: Bool,+frame: Frame,+parents: List<&2,Frame>,+depth: Nat) -> Parsing:
  match text:
    case SNil{}: ParseError{Syntax{"Unterminated repetition"}}
    case SCon{'}',+rest}: Bool.pick(Unit -> Parsing,comma,
      _ => Bool.pick(Unit -> Parsing,haveDigit,
        _ => Bool.pick(Unit -> Parsing,Nat.is_ge(maximum,minimum),_ => repeated(rest,minimum,Some{maximum},frame,parents,depth),_ => ParseError{Syntax{"Reversed repetition bounds"}})(Unit{}),
        _ => repeated(rest,minimum,None{},frame,parents,depth))(Unit{}),
      _ => Bool.pick(Unit -> Parsing,haveDigit,_ => repeated(rest,maximum,Some{maximum},frame,parents,depth),_ => ParseError{Syntax{"Empty repetition"}})(Unit{}))(Unit{})
    case SCon{',',rest}: Bool.pick(Unit -> Parsing,Bool.not(comma) && haveDigit,_ => repeatBounds(rest,maximum,Zero{},True{},False{},frame,parents,depth),_ => ParseError{Syntax{"Invalid repetition bounds"}})(Unit{})
    case SCon{char,rest}:
      +char = {char : Char}
      +rest = {rest : String}
      +number = maximum * 10n + U32.to_nat((Char.to_u32(char) - 48 : U32))
      Bool.pick(Unit -> Parsing,enabled(flagsOf(frame),64) && regexWhitespace(char),_ => repeatBounds(rest,minimum,maximum,comma,haveDigit,frame,parents,depth),_ => Bool.pick(Unit -> Parsing,Char.is_digit(char) && Nat.is_le(number,65536n),_ => repeatBounds(rest,minimum,number,comma,True{},frame,parents,depth),_ => ParseError{Syntax{"Invalid or excessive repetition count"}})(Unit{}))(Unit{})

def alternative(text: String,frame: Frame,parents: List<&2,Frame>,depth: Nat) -> Parsing:
  match frame:
    case Frame{flags,sequence,alternatives,names}: Parsing{text,Frame{flags,Nil{},expressions(sequence,False{}) <> alternatives,names},parents,depth}

def dot(+flags: U32) -> Expression:
  +value = Bool.pick(Class,enabled(flags,4),Range{0,1114111},Negation{Bool.pick(Class,enabled(flags,8),Union{Range{10,10},Range{13,13}},Range{10,10})})
  Bool.pick(Unit -> Expression,enabled(flags,32),_ => character(value,flags),_ => byteCharacter(Intersection{value,Range{0,255}},flags))(Unit{})

def parserStep(state: Parsing) -> Parsing:
  match state:
    case Parsing{SNil{},frame,Nil{},_}: Parsed{frameExpression(frame)}
    case Parsing{SNil{},_,_,_}: ParseError{Syntax{"Unclosed group"}}
    case Parsing{SCon{'(',rest},frame,parents,depth}: beginGroup(rest,frame,parents,depth)
    case Parsing{SCon{')',rest},frame,parents,depth}: groupClose(rest,frame,parents,depth)
    case Parsing{SCon{'|',rest},frame,parents,depth}: alternative(rest,frame,parents,depth)
    case Parsing{SCon{'*',rest},frame,parents,depth}: repeated(rest,Zero{},None{},frame,parents,depth)
    case Parsing{SCon{'+',rest},frame,parents,depth}: repeated(rest,1n,None{},frame,parents,depth)
    case Parsing{SCon{'?',rest},frame,parents,depth}: repeated(rest,Zero{},Some{1n},frame,parents,depth)
    case Parsing{SCon{'{',rest},frame,parents,depth}: repeatBounds(rest,Zero{},Zero{},False{},False{},frame,parents,depth)
    case Parsing{SCon{'[',+rest},+frame,parents,depth}: appendAtom(readClass(Succ{textLength(rest,Zero{})},beginClass(rest,Nil{}),flagsOf(frame)),frame,parents,depth)
    case Parsing{SCon{'\\',rest},+frame,parents,depth}: appendAtom(escape(rest,flagsOf(frame)),frame,parents,depth)
    case Parsing{SCon{'.',rest},+frame,parents,depth}: appendAtom(Bool.pick(Result<&2,&2,Error,Atom>,enabled(flagsOf(frame),32) || enabled(flagsOf(frame),512),Done{Atom{dot(flagsOf(frame)),rest}},Fail{RequiresByteInput{}}),frame,parents,depth)
    case Parsing{SCon{'^',rest},+frame,parents,depth}: appendAtom(Done{Atom{Assert{Bool.pick(Assertion,enabled(flagsOf(frame),2),LineStart{enabled(flagsOf(frame),8)},Start{})},rest}},frame,parents,depth)
    case Parsing{SCon{'$',rest},+frame,parents,depth}: appendAtom(Done{Atom{Assert{Bool.pick(Assertion,enabled(flagsOf(frame),2),LineEnd{enabled(flagsOf(frame),8)},End{})},rest}},frame,parents,depth)
    case Parsing{SCon{'\n',+rest},+frame,+parents,+depth}:
      Bool.pick(Unit -> Parsing,enabled(flagsOf(frame),64),_ => Parsing{rest,frame,parents,depth},_ => Bool.pick(Unit -> Parsing,enabled(flagsOf(frame),1024),_ => ParseError{Syntax{"Newline literals require multiline search"}},_ => appendAtom(Done{Atom{literal('\n',flagsOf(frame)),rest}},frame,parents,depth))(Unit{}))(Unit{})
    case Parsing{SCon{'#',+rest},+frame,+parents,+depth}: Bool.pick(Unit -> Parsing,enabled(flagsOf(frame),64),_ => Parsing{skipComment(rest),frame,parents,depth},_ => appendAtom(Done{Atom{literal('#',flagsOf(frame)),rest}},frame,parents,depth))(Unit{})
    case Parsing{SCon{char,rest},frame,parents,depth}:
      +char = {char : Char}
      +rest = {rest : String}
      +frame = {frame : Frame}
      +parents = {parents : List<&2,Frame>}
      +depth = {depth : Nat}
      Bool.pick(Unit -> Parsing,enabled(flagsOf(frame),64) && regexWhitespace(char),_ => Parsing{rest,frame,parents,depth},_ => appendAtom(Done{Atom{literal(char,flagsOf(frame)),rest}},frame,parents,depth))(Unit{})
    case state: state

def parse(fuel: Nat,state: Parsing) -> Result<&2,&2,Error,Expression>:
  match fuel state:
    case _ ParseError{error}: Fail{error}
    case _ Parsed{expression}: Done{expression}
    case Zero{} _: Fail{SizeLimit{}}
    case Succ{fuel} state: parse(fuel,parserStep(state))

def parsedExpression(result: Result<&2,&2,Error,Expression>) -> Result<&2,&2,Error,Regex>:
  match result:
    case Fail{error}: Fail{error}
    case Done{expression}: compileExpression(expression)

def parseWithFlags(+pattern: String,flags: U32) -> Result<&2,&2,Error,Expression>:
  parse(textLength(pattern,Zero{}) + 2n,Parsing{pattern,Frame{flags,Nil{},Nil{},Nil{}},Nil{},Zero{}})

def parsePattern(pattern: String,insensitive: Bool,bytes: Bool) -> Result<&2,&2,Error,Expression>:
  parseWithFlags(pattern,U32.or(Bool.pick(U32,insensitive,33,32),Bool.pick(U32,bytes,512,0)))

def compile(pattern: String,insensitive: Bool) -> Result<&2,&2,Error,Regex>:
  parsedExpression(parsePattern(pattern,insensitive,False{}))
