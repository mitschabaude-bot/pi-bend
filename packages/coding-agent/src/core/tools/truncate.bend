import Base
import ../../../../runtime/src/string.bend as Strings
import ../../../../runtime/src/utf8.bend as Utf8
import ../../../../runtime/src/text.bend as Text

def DEFAULT_MAX_LINES() -> Nat: 2000n
def DEFAULT_MAX_BYTES() -> Nat: 51200n
def GREP_MAX_LINE_LENGTH() -> Nat: 500n

type Limit is Data:
  Lines{}
  Bytes{}

type TruncationOptions is Data:
  TruncationOptions{maxLines: Maybe<&2,Nat>, maxBytes: Maybe<&2,Nat>}

type TruncationResult is Data:
  TruncationResult{content: String, truncated: Bool, truncatedBy: Maybe<&2,Limit>, totalLines: Nat, totalBytes: Nat, outputLines: Nat, outputBytes: Nat, lastLinePartial: Bool, firstLineExceedsLimit: Bool, maxLines: Nat, maxBytes: Nat}

type LineResult is Data:
  LineResult{text: String, wasTruncated: Bool}

type Direction is Data:
  Head{}
  Tail{}

# A final newline terminates the last line; it does not create another one.
def counted(reversed: List<&2,String>) -> List<&2,String>:
  match reversed:
    case "" <> rest: List.reverse(&2,String,rest)
    case values: List.reverse(&2,String,values)

def splitLinesForCounting(content: String) -> List<&2,String>:
  counted(List.reverse(&2,String,Strings.split(content,'\n')))

def scalarWidth(+code: U32) -> Nat:
  Bool.pick(Nat,U32.is_lt(code,128),1n,Bool.pick(Nat,U32.is_lt(code,2048),2n,Bool.pick(Nat,U32.is_lt(code,65536),3n,4n)))

def countBytes(content: String, total: Nat) -> Nat:
  match content:
    case SNil{}: total
    case SCon{Chr{code},rest}: countBytes(rest,scalarWidth(code) + total)

def byteLength(content: String) -> Nat: countBytes(content,0n)

def countLines(lines: List<&2,String>, total: Nat) -> Nat:
  match lines:
    case Nil{}: total
    case _ <> rest: countLines(rest,1n+total)

# Skip only continuation bytes after cutting a UTF-8 suffix. Decoding preserves
# BOMs: a tool's file content is not a transport stream with an optional BOM.
def boundary(bytes: List<&2,U32>) -> List<&2,U32>:
  match bytes:
    case Nil{}: Nil{}
    case +byte <> +rest:
      Bool.pick(Unit -> List<&2,U32>,U32.is_eq(U32.and(byte,192),128),unused => boundary(rest),unused => byte <> rest)(Unit{})

def suffixBytes(+content: String, budget: Nat) -> String:
  encoded = boundary(List.drop(&2,U32,Utf8.encode(content),byteLength(content) - budget))
  Utf8.complete(Utf8.decode(Utf8.Decoder{Utf8.Ready{},True{}},encoded))

type Selection is Data:
  Selection{lines: List<&2,String>, count: Nat, bytes: Nat, cause: Limit, partial: Bool}

def overflow(direction: Direction, line: String, budget: Nat, selection: Selection) -> Selection:
  match direction selection:
    case Tail{} Selection{Nil{},0n,_,_,_}:
      +ending = suffixBytes(line,budget)
      Selection{ending <> Nil{},1n,byteLength(ending),Bytes{},True{}}
    case _ Selection{lines,count,bytes,_,partial}: Selection{lines,count,bytes,Bytes{},partial}

# Remaining budgets decrease, so the scan examines each retained line once.
def collect(+direction: Direction, lines: List<&2,String>, room: Nat, +budget: Nat, selection: Selection) -> Selection:
  match lines room selection:
    case Nil{} _ value: value
    case _ 0n value: value
    case +line <> rest 1n+room Selection{+chosen,+count,+used,+cause,+partial}:
      +cost = byteLength(line) + Bool.pick(Nat,List.is_empty(&2,String,chosen),0n,1n)
      Bool.pick(Unit -> Selection,Nat.is_le(cost,budget),
        unused => collect(direction,rest,room,budget - cost,Selection{line <> chosen,1n+count,used + cost,cause,partial}),
        unused => overflow(direction,line,budget,Selection{chosen,count,used,cause,partial}))(Unit{})

def ordered(direction: Direction, lines: List<&2,String>) -> List<&2,String>:
  match direction:
    case Head{}: List.reverse(&2,String,lines)
    case Tail{}: lines

def scanOrder(direction: Direction, lines: List<&2,String>) -> List<&2,String>:
  match direction:
    case Head{}: lines
    case Tail{}: List.reverse(&2,String,lines)

def result(direction: Direction, totalLines: Nat, totalBytes: Nat, +maxLines: Nat, maxBytes: Nat, selection: Selection) -> TruncationResult:
  match selection:
    case Selection{lines,+count,bytes,cause,partial}:
      TruncationResult{String.join(ordered(direction,lines),"\n"),True{},Some{Bool.pick(Limit,Nat.is_ge(count,maxLines),Lines{},cause)},totalLines,totalBytes,count,bytes,partial,False{},maxLines,maxBytes}

def firstTooLarge(direction: Direction, lines: List<&2,String>, budget: Nat) -> Bool:
  match direction lines:
    case Head{} first <> _: Nat.is_gt(byteLength(first),budget)
    case _ _: False{}

def truncated(oversized: Bool, +direction: Direction, lines: List<&2,String>, totalLines: Nat, totalBytes: Nat, +maxLines: Nat, +maxBytes: Nat) -> TruncationResult:
  match oversized:
    case True{}: TruncationResult{"",True{},Some{Bytes{}},totalLines,totalBytes,0n,0n,False{},True{},maxLines,maxBytes}
    case False{}:
      result(direction,totalLines,totalBytes,maxLines,maxBytes,collect(direction,scanOrder(direction,lines),maxLines,maxBytes,Selection{Nil{},0n,0n,Lines{},False{}}))

def truncateWithin(fits: Bool, +direction: Direction, content: String, +lines: List<&2,String>, +totalLines: Nat, +totalBytes: Nat, +maxLines: Nat, +maxBytes: Nat) -> TruncationResult:
  match fits:
    case True{}: TruncationResult{content,False{},None{},totalLines,totalBytes,totalLines,totalBytes,False{},False{},maxLines,maxBytes}
    case False{}: truncated(firstTooLarge(direction,lines,maxBytes),direction,lines,totalLines,totalBytes,maxLines,maxBytes)

def truncate(direction: Direction, +content: String, options: TruncationOptions) -> TruncationResult:
  match options:
    case TruncationOptions{lineOption,byteOption}:
      +maxLines = Maybe.default(&2,Nat,lineOption,DEFAULT_MAX_LINES())
      +maxBytes = Maybe.default(&2,Nat,byteOption,DEFAULT_MAX_BYTES())
      +lines = splitLinesForCounting(content)
      +totalLines = countLines(lines,0n)
      +totalBytes = byteLength(content)
      truncateWithin(Nat.is_le(totalLines,maxLines) && Nat.is_le(totalBytes,maxBytes),direction,content,lines,totalLines,totalBytes,maxLines,maxBytes)

def truncateHead(content: String, options: TruncationOptions) -> TruncationResult: truncate(Head{},content,options)
def truncateTail(content: String, options: TruncationOptions) -> TruncationResult: truncate(Tail{},content,options)

def lineResult(value: Text.Cut) -> LineResult:
  match value:
    case Text.Cut{text,0n}: LineResult{text,False{}}
    case Text.Cut{text,1n+_}: LineResult{text ++ "... [truncated]",True{}}

# Retain Pi's UTF-16 budget, but never manufacture an isolated surrogate by
# cutting a native character in half. Text.take already specifies this policy.
def truncateLine(line: String, maxChars: Maybe<&2,Nat>) -> LineResult: lineResult(Text.take(line,Maybe.default(&2,Nat,maxChars,GREP_MAX_LINE_LENGTH())))

def fixedSize(bytes: Nat, +unit: Nat, suffix: String) -> String:
  +tenths = Nat.div(bytes * 10n + Nat.div(unit,2n),unit)
  Nat.show(Nat.div(tenths,10n)) ++ "." ++ Nat.show(Nat.mod(tenths,10n)) ++ suffix

def sizeUnit(small: Bool, kilo: Bool, bytes: Nat) -> String:
  match small kilo:
    case True{} _: Nat.show(bytes) ++ "B"
    case False{} True{}: fixedSize(bytes,1024n,"KB")
    case False{} False{}: fixedSize(bytes,1048576n,"MB")

def formatSize(+bytes: Nat) -> String: sizeUnit(Nat.is_lt(bytes,1024n),Nat.is_lt(bytes,1048576n),bytes)
