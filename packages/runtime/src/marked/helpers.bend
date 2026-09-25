import Base
import ../string.bend as Strings
import ../text.bend as Text
import ../ecma-regex.bend as Re
import ../unicode-17-category.bend as Category

# marked 18.0.11's helpers (src/helpers.ts) that the lexer uses, and the
# fixed expressions of rules.ts's `other` as functions over the same text.
# Strings are sequences of Unicode scalars (JavaScript counts UTF-16 code
# units; lengths only ever meet other lengths of the same text).

def isChar(+char: Char,code: U32) -> Bool: U32.is_eq(Char.to_u32(char),code)
def isSpaceOrTab(+char: Char) -> Bool: Char.is_eq(char,' ') || Char.is_eq(char,'\t')
# JavaScript's `\s`.
def isSpace(+char: Char) -> Bool: Re.isSpaceCode(Char.to_u32(char))
def isLineTerminator(+char: Char) -> Bool: Re.isLineTerminator(Char.to_u32(char))
def lastChar(text: String) -> Maybe<&2,Char>: String.get(String.reverse(text),0n)
def endsWithChar(text: String,char: Char) -> Bool: String.ends_with(text,SCon{char,SNil{}})
def startsWithChar(text: String,+char: Char) -> Bool:
  match text:
    case SCon{first,_}: Char.is_eq(first,char)
    case SNil{}: False{}
def dropWhileChar(text: String,+char: Char) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{+first,+rest}: Bool.pick(Unit -> String,Char.is_eq(first,char),_ => dropWhileChar(rest,char),_ => SCon{first,rest})(Unit{})
def dropSpaceOrTab(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{+first,+rest}: Bool.pick(Unit -> String,isSpaceOrTab(first),_ => dropSpaceOrTab(rest),_ => SCon{first,rest})(Unit{})
def repeatChar(+char: Char,count: Nat,text: String) -> String:
  match count:
    case Zero{}: text
    case Succ{more}: repeatChar(char,more,SCon{char,text})
def linesOf(text: String) -> List<&2,String>: Strings.split(text,'\n')
# The pieces of `reversed`, last first, joined before `text`.
def concatReversed(reversed: List<&2,String>,text: String) -> String:
  match reversed:
    case Nil{}: text
    case piece <> rest: concatReversed(rest,piece ++ text)
def joinLines(lines: List<&2,String>) -> String: String.join(lines,"\n")
# `text.slice(0, -count)`.
def dropEnd(+text: String,count: Nat) -> String: String.take(text,String.length(text) - count)
# `text.slice(start, -end)`.
def inner(text: String,start: Nat,end: Nat) -> String: dropEnd(String.drop(text,start),end)

# rtrim(str, c): `str` without its trailing run of `c`.
def rtrim(text: String,+char: Char) -> String: String.reverse(dropWhileChar(String.reverse(text),char))

# other.blankLine, `/^[ \t]*$/`.
def blankLine(text: String) -> Bool: String.is_empty(dropSpaceOrTab(text))

# trimTrailingBlankLines(str): trailing blank lines go, unless there is at
# most one.
def blankCount(reversed: List<&2,String>,+count: Nat) -> Nat:
  match reversed:
    case Nil{}: count
    case +line <> rest: Bool.pick(Unit -> Nat,blankLine(line),_ => blankCount(rest,count + 1n),_ => count)(Unit{})
def trimTrailingBlankLines(+text: String) -> String:
  +all = linesOf(text)
  +trailing = blankCount(List.reverse(&2,String,all),0n)
  Bool.pick(Unit -> String,Nat.is_le(trailing,1n),_ => text,_ => joinLines(List.take(&2,String,all,List.length(&2,String,all) - trailing)))(Unit{})

# expandTabs(line, indent): tabs advance to the next multiple of four
# columns, counting from `indent`.
def expandTabs(text: String,+column: Nat,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,+rest}:
      +added = 4n - Nat.mod(column,4n)
      Bool.pick(Unit -> String,Char.is_eq(char,'\t'),_ => expandTabs(rest,column + added,repeatChar(' ',added,reversed)),_ => expandTabs(rest,column + 1n,SCon{char,reversed}))(Unit{})

# findClosingBracket(str, "()"): the index of the parenthesis closing the
# text's first unclosed level, skipping escaped characters.
type Bracket is Data:
  # -1: no closing parenthesis, or none that closes an outer level.
  Unclosed{}
  # -2: more opening than closing parentheses.
  Unbalanced{}
  ClosesAt{index: Nat}
# `escaped`: the previous character is a backslash, so this one is skipped.
def closingScan(text: String,+escaped: Bool,+level: Nat,+index: Nat) -> Bracket:
  match text:
    case SNil{}: Bool.pick(Bracket,Nat.is_gt(level,0n),Unbalanced{},Unclosed{})
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Bracket,escaped,_ => closingScan(rest,False{},level,index + 1n),
        _ => Bool.pick(Unit -> Bracket,Char.is_eq(char,'\\'),_ => closingScan(rest,True{},level,index + 1n),
        _ => Bool.pick(Unit -> Bracket,Char.is_eq(char,'('),_ => closingScan(rest,False{},level + 1n,index + 1n),
        _ => Bool.pick(Unit -> Bracket,Char.is_eq(char,')'),
          _ => Bool.pick(Unit -> Bracket,Nat.is_eq(level,0n),_ => ClosesAt{index},_ => closingScan(rest,False{},level - 1n,index + 1n))(Unit{}),
          _ => closingScan(rest,False{},level,index + 1n))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def findClosingBracket(+text: String) -> Bracket:
  Bool.pick(Unit -> Bracket,String.contains(text,")"),_ => closingScan(text,False{},0n,0n),_ => Unclosed{})(Unit{})

# splitCells(tableRow, count)
# ---------------------------
# Every pipe not escaped by an odd run of backslashes gets a space before
# it; the row splits at " |"; an empty first or last cell goes; `count`
# truncates or pads; cells are trimmed and `\|` becomes `|`.
def pipesSpaced(text: String,+escaped: Bool,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,+rest}:
      Bool.pick(Unit -> String,Char.is_eq(char,'|') && Bool.not(escaped),_ => pipesSpaced(rest,False{},SCon{'|',SCon{' ',reversed}}),
        _ => pipesSpaced(rest,Char.is_eq(char,'\\') && Bool.not(escaped),SCon{char,reversed}))(Unit{})
# `row.split(" |")`; `current` is the piece so far, reversed.
def splitPipes(text: String,+current: String,+pieces: List<&2,String>) -> List<&2,String>:
  match text:
    case SNil{}: List.reverse(&2,String,String.reverse(current) <> pieces)
    case SCon{+char,+rest}:
      Bool.pick(Unit -> List<&2,String>,Char.is_eq(char,'|') && startsWithChar(current,' '),
        _ => splitPipes(rest,"",String.reverse(String.drop(current,1n)) <> pieces),
        _ => splitPipes(rest,SCon{char,current},pieces))(Unit{})
def withoutBlankFirst(cells: List<&2,String>) -> List<&2,String>:
  match cells:
    case +first <> +rest: Bool.pick(List<&2,String>,Text.blank(first),rest,first <> rest)
    case Nil{}: Nil{}
def withoutBlankLast(+cells: List<&2,String>) -> List<&2,String>:
  List.reverse(&2,String,withoutBlankFirst(List.reverse(&2,String,cells)))
def fitted(+cells: List<&2,String>,count: Maybe<&2,Nat>) -> List<&2,String>:
  match count:
    case None{}: cells
    case Some{+count}:
      +length = List.length(&2,String,cells)
      Bool.pick(Unit -> List<&2,String>,Nat.is_gt(length,count),_ => List.take(&2,String,cells,count),_ => List.append(&2,String,cells,List.replicate(String,count - length,"")))(Unit{})
def trimmedCells(cells: List<&2,String>,reversed: List<&2,String>) -> List<&2,String>:
  match cells:
    case Nil{}: List.reverse(&2,String,reversed)
    case cell <> rest: trimmedCells(rest,Strings.replaceAll(Text.trim(cell),"\\|","|") <> reversed)
def splitCells(tableRow: String,count: Maybe<&2,Nat>) -> List<&2,String>:
  trimmedCells(fitted(withoutBlankLast(withoutBlankFirst(splitPipes(pipesSpaced(tableRow,False{},""),"",Nil{}))),count),Nil{})

# rules.ts `other`
# ----------------

# Lines with the line terminator ending each (multiline `^` also follows
# \r, U+2028 and U+2029).
type Line is Data: Line{text: String,terminator: Maybe<&2,Char>}
def splitLines(text: String,+current: String,+reversed: List<&2,Line>) -> List<&2,Line>:
  match text:
    case SNil{}: List.reverse(&2,Line,Line{String.reverse(current),None{}} <> reversed)
    case SCon{+char,+rest}:
      Bool.pick(Unit -> List<&2,Line>,isLineTerminator(char),_ => splitLines(rest,"",Line{String.reverse(current),Some{char}} <> reversed),_ => splitLines(rest,SCon{char,current},reversed))(Unit{})
def joinedLine(line: Line) -> String:
  match line:
    case Line{text,None{}}: text
    case Line{text,Some{char}}: text ++ SCon{char,SNil{}}

def indentSpaces(count: Nat,line: String) -> String:
  match count line:
    case Succ{more} SCon{' ',rest}: indentSpaces(more,rest)
    case _ line: line
# `^(?: {1,4}| {0,3}\t)`: up to four spaces, else a tab.
def indentRemoved(line: String) -> String:
  match line:
    case SCon{' ',_}: indentSpaces(4n,line)
    case SCon{'\t',rest}: rest
    case _: line
def indentsRemoved(lines: List<&2,Line>,reversed: List<&2,String>) -> String:
  match lines:
    case Nil{}: concatReversed(reversed,"")
    case Line{text,terminator} <> rest: indentsRemoved(rest,joinedLine(Line{indentRemoved(text),terminator}) <> reversed)
# other.codeRemoveIndent, `/^(?: {1,4}| {0,3}\t)/gm` → "".
def codeRemoveIndent(text: String) -> String: indentsRemoved(splitLines(text,"",Nil{}),Nil{})

# `[ \t]?` after a quote marker.
def quoteMarkerSpace(text: String) -> String:
  match text:
    case SCon{+char,+rest}: Bool.pick(String,isSpaceOrTab(char),rest,SCon{char,rest})
    case SNil{}: SNil{}
def afterMarker(line: String,rest: String) -> String:
  match rest:
    case SCon{'>',after}: quoteMarkerSpace(after)
    case _: line
# `^ {0,3}>[ \t]?`
def quoteMarkerRemoved(+line: String) -> String:
  afterMarker(line,String.drop(line,Nat.min(3n,String.length(line) - String.length(dropWhileChar(line,' ')))))
def quoteMarkersJoined(lines: List<&2,Line>,reversed: List<&2,String>) -> String:
  match lines:
    case Nil{}: concatReversed(reversed,"")
    case Line{text,terminator} <> rest: quoteMarkersJoined(rest,joinedLine(Line{quoteMarkerRemoved(text),terminator}) <> reversed)
# other.blockquoteSetextReplace2, `/^ {0,3}>[ \t]?/gm` → "".
def quoteMarkersRemoved(text: String) -> String: quoteMarkersJoined(splitLines(text,"",Nil{}),Nil{})

# other.blockquoteSetextReplace, `/\n {0,3}((?:=+|-+) *)(?=\n|$)/g` →
# "\n    $1": a line after the first that is a setext underline gets four
# spaces of indentation instead of its own (at most three).
def underlineRun(+text: String,+char: Char) -> Bool:
  +rest = dropWhileChar(text,char)
  Nat.is_lt(String.length(rest),String.length(text)) && String.is_empty(dropWhileChar(rest,' '))
def setextUnderline(+line: String) -> Maybe<&2,String>:
  +marker = dropWhileChar(line,' ')
  Bool.pick(Unit -> Maybe<&2,String>,Nat.is_le(String.length(line) - String.length(marker),3n) && (underlineRun(marker,'=') || underlineRun(marker,'-')),_ => Some{marker},_ => None{})(Unit{})
def indentedUnderline(+line: String) -> String: Maybe.default(&2,String,Maybe.map(&2,String,String,marker => "    " ++ marker,setextUnderline(line)),line)
def indentedUnderlines(lines: List<&2,String>,reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: List.reverse(&2,String,reversed)
    case line <> rest: indentedUnderlines(rest,indentedUnderline(line) <> reversed)
def underlinesAfterFirst(lines: List<&2,String>) -> String:
  match lines:
    case first <> rest: joinLines(first <> indentedUnderlines(rest,Nil{}))
    case Nil{}: ""
def blockquoteSetextReplace(text: String) -> String: underlinesAfterFirst(linesOf(text))
# other.blockquoteStart, `/^ {0,3}>/`.
def blockquoteStart(+line: String) -> Bool:
  +rest = dropWhileChar(line,' ')
  Nat.is_le(String.length(line) - String.length(rest),3n) && startsWithChar(rest,'>')

# `.replace(anyPunctuation, "$1")`, `/\\([\p{P}\p{S}])/gu`: a backslash
# before punctuation or a symbol goes.
def isPunctuationOrSymbol(+code: U32) -> Bool: Category.isPunctuation(code) || Category.isSymbol(code)
# `pending`: the previous character is a backslash no match took.
def unescapeScan(text: String,+pending: Bool,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(Bool.pick(String,pending,SCon{'\\',reversed},reversed))
    case SCon{+char,+rest}:
      Bool.pick(Unit -> String,pending,
        _ => Bool.pick(Unit -> String,isPunctuationOrSymbol(Char.to_u32(char)),_ => unescapeScan(rest,False{},SCon{char,reversed}),_ => unescapeScan(rest,False{},SCon{char,SCon{'\\',reversed}}))(Unit{}),
        _ => Bool.pick(Unit -> String,Char.is_eq(char,'\\'),_ => unescapeScan(rest,True{},reversed),_ => unescapeScan(rest,False{},SCon{char,reversed}))(Unit{}))(Unit{})
def unescapePunctuation(text: String) -> String: unescapeScan(text,False{},"")
