import Base
import ../text.bend as Text
import ../string.bend as Strings
import ../case-map.bend as CaseMap
import ../ecma-regex.bend as Re
import ../unicode-17-category.bend as Category
import ./tokens.bend as T
import ./rules.bend as Rules
import ./helpers.bend as H

# marked 18.0.11's Tokenizer (src/Tokenizer.ts): each method reads a token
# at the start of the source. Methods that lex nested content (blockquote,
# list, links, emphasis, strikethrough) return what they matched; the lexer
# (lexer.bend) lexes the content and builds their tokens, since only one
# function may recurse through another here. Sources are Unicode scalars.

# Sources and captures
# --------------------

def takeReversed(codes: List<&2,U32>,count: Nat,reversed: List<&2,U32>) -> List<&2,U32>:
  match codes count:
    case _ Zero{}: reversed
    case Nil{} Succ{_}: reversed
    case scalar <> rest Succ{more}: takeReversed(rest,more,scalar <> reversed)
def take(codes: List<&2,U32>,count: Nat) -> List<&2,U32>: List.reverse(&2,U32,takeReversed(codes,count,Nil{}))
def drop(codes: List<&2,U32>,count: Nat) -> List<&2,U32>: List.drop(&2,U32,codes,count)
def textOf(codes: List<&2,U32>) -> String: Re.fromCodes(codes)
# The text of scalars `start` to `end`.
def slice(codes: List<&2,U32>,+start: Nat,end: Nat) -> String: Re.reversedText(takeReversed(drop(codes,start),end - start,Nil{}),SNil{})
# Fuel for loops that consume at least one scalar per step: more steps than
# any source in memory has scalars (counting the source instead costs a pass
# over the rest of the document per block).
def unbounded() -> Nat: 4294967295n
# A text's length in scalars (the lexer's `raw.length`).
def lengthFrom(text: String,+count: Nat) -> Nat:
  match text:
    case SNil{}: count
    case SCon{_,rest}: lengthFrom(rest,count + 1n)
def lengthOf(text: String) -> Nat: lengthFrom(text,0n)
def codesLength(codes: List<&2,U32>,+count: Nat) -> Nat:
  match codes:
    case Nil{}: count
    case _ <> rest: codesLength(rest,count + 1n)
def startsWith(codes: List<&2,U32>,+char: Char) -> Bool:
  match codes:
    case scalar <> _: U32.is_eq(scalar,Char.to_u32(char))
    case Nil{}: False{}

# A match at the start of `input` (every rule the lexer runs this way is
# anchored with `^`).
type Cap is Data: Cap{input: List<&2,U32>,found: Re.Match}
def cap(input: List<&2,U32>,found: Maybe<&2,Re.Match>) -> Maybe<&2,Cap>:
  match found:
    case Some{value}: Some{Cap{input,value}}
    case None{}: None{}
def capFound(+src: List<&2,U32>,value: Maybe<&2,Re.Found>) -> Maybe<&2,Cap>:
  match value:
    case Some{Re.Found{result,_}}: Some{Cap{src,result}}
    case None{}: None{}
def exec(rule: Rules.Search,+src: List<&2,U32>) -> Maybe<&2,Cap>:
  match rule: case Rules.Search{regex,start}: capFound(src,Re.attemptAt(regex,start,src,Re.cursorAt(src)))
def test(+rule: Rules.Search,+src: List<&2,U32>) -> Bool: Maybe.is_some(&2,Cap,exec(rule,src))
# A rule of the grammar at the start of `src`, tried where its first scalar
# may begin a match.
def blockOpened(opens: Bool,rules: Rules.Block,rule: Rules.BlockRule,+src: List<&2,U32>) -> Maybe<&2,Cap>:
  match opens:
    case True{}: exec(Rules.blockSearch(rules,rule),src)
    case False{}: None{}
# (`first`: the first scalar of `src`, which the lexer reads once for every
# tokenizer it tries there.)
def blockExecAt(+rules: Rules.Block,+rule: Rules.BlockRule,first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,Cap>: blockOpened(Rules.blockOpens(rules,rule,first),rules,rule,src)
def blockExec(+rules: Rules.Block,+rule: Rules.BlockRule,+src: List<&2,U32>) -> Maybe<&2,Cap>: blockExecAt(rules,rule,List.head(&2,U32,src),src)
def inlineOpened(opens: Bool,rules: Rules.Inline,rule: Rules.InlineRule,+src: List<&2,U32>) -> Maybe<&2,Cap>:
  match opens:
    case True{}: exec(Rules.inlineSearch(rules,rule),src)
    case False{}: None{}
def inlineExecAt(+rules: Rules.Inline,+rule: Rules.InlineRule,first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,Cap>: inlineOpened(Rules.inlineOpens(rules,rule,first),rules,rule,src)
def inlineExec(+rules: Rules.Inline,+rule: Rules.InlineRule,+src: List<&2,U32>) -> Maybe<&2,Cap>: inlineExecAt(rules,rule,List.head(&2,U32,src),src)
def flatSpan(value: Maybe<&2,Maybe<&2,Re.Span>>) -> Maybe<&2,Re.Span>:
  match value:
    case Some{span}: span
    case None{}: None{}
def spanAt(found: Re.Match,index: Nat) -> Maybe<&2,Re.Span>:
  match found index:
    case Re.Match{start,end,_} Zero{}: Some{Re.Span{start,end}}
    case Re.Match{_,_,captures} Succ{number}: flatSpan(List.get(&2,Maybe<&2,Re.Span>,captures,number))
def spanText(input: List<&2,U32>,span: Maybe<&2,Re.Span>) -> Maybe<&2,String>:
  match span:
    case Some{Re.Span{start,end}}: Some{slice(input,start,end)}
    case None{}: None{}
# `cap[index]`: None when the group did not participate.
def capGroup(value: Cap,index: Nat) -> Maybe<&2,String>:
  match value: case Cap{input,found}: spanText(input,spanAt(found,index))
# `cap[index] || ""` for a group that always participates, or when
# undefined and "" read the same.
def capText(value: Cap,index: Nat) -> String: Maybe.default(&2,String,capGroup(value,index),"")
def capWhole(value: Cap) -> String: capText(value,0n)
def matchEnd(value: Cap) -> Nat:
  match value: case Cap{_,Re.Match{_,end,_}}: end
# JavaScript truthiness of an optional string.
def truthy(value: Maybe<&2,String>) -> Bool:
  match value:
    case Some{SCon{_,_}}: True{}
    case _: False{}


# The first line of a source (`src.split("\n", 1)[0]`).
def lineReversed(codes: List<&2,U32>,+reversed: List<&2,U32>) -> List<&2,U32>:
  match codes:
    case Nil{}: reversed
    case +scalar <> rest: Bool.pick(Unit -> List<&2,U32>,U32.is_eq(scalar,10),_ => reversed,_ => lineReversed(rest,scalar <> reversed))(Unit{})
def firstLine(codes: List<&2,U32>) -> String: Re.reversedText(lineReversed(codes,Nil{}),SNil{})
def firstTextLine(text: String) -> String: firstLine(Re.codes(text))
# The first line of a source, the source after it and whether a newline ended
# the line (one pass).
type Split is Data: Split{line: String,rest: List<&2,U32>,newline: Bool}
def splitReversed(codes: List<&2,U32>,+reversed: List<&2,U32>) -> Split:
  match codes:
    case Nil{}: Split{Re.reversedText(reversed,SNil{}),Nil{},False{}}
    case 10 <> rest: Split{Re.reversedText(reversed,SNil{}),rest,True{}}
    case +scalar <> rest: splitReversed(rest,scalar <> reversed)
def splitLine(codes: List<&2,U32>) -> Split: splitReversed(codes,Nil{})
# The index of the first character other than a space (`search(/[^ ]/)`).
def nonSpaceFrom(text: String,+index: Nat) -> Maybe<&2,Nat>:
  match text:
    case SNil{}: None{}
    case SCon{+char,rest}: Bool.pick(Unit -> Maybe<&2,Nat>,Char.is_eq(char,' '),_ => nonSpaceFrom(rest,index + 1n),_ => Some{index})(Unit{})
def nonSpace(text: String) -> Maybe<&2,Nat>: nonSpaceFrom(text,0n)
def atLeast(position: Maybe<&2,Nat>,+count: Nat) -> Bool:
  match position:
    case Some{index}: Nat.is_ge(index,count)
    case None{}: False{}
# JavaScript's `.replace(/\s+/g, " ")`.
def collapseScan(text: String,+inSpace: Bool,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,+rest}:
      Bool.pick(Unit -> String,H.isSpace(char),
        _ => collapseScan(rest,True{},Bool.pick(String,inSpace,reversed,SCon{' ',reversed})),
        _ => collapseScan(rest,False{},SCon{char,reversed}))(Unit{})
def collapseSpace(text: String) -> String: collapseScan(text,False{},"")
# other.tabCharGlobal → four spaces.
def tabsExpanded(text: String) -> String: Strings.replaceAll(text,"\t","    ")

# Block tokenizers
# ----------------

type Titled is Data: Titled{raw: String,depth: Nat,text: String}
type Texted is Data: Texted{raw: String,text: String}

def spaceOf(-X: Data,found: Maybe<&2,Cap>) -> Maybe<&2,T.Token<X>>:
  match found:
    case Some{+value}: Bool.pick(Unit -> Maybe<&2,T.Token<X>>,Nat.is_gt(matchEnd(value),0n),_ => Some{T.Space{capWhole(value)}},_ => None{})(Unit{})
    case None{}: None{}
def space(-X: Data,+rules: Rules.Block,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,T.Token<X>>: spaceOf(X,blockExecAt(rules,Rules.BlockNewline{},first,src))

def indentedCode(-X: Data,+raw: String) -> T.Token<X>: T.Code{raw,Some{"indented"},None{},H.codeRemoveIndent(raw)}
def codeOf(-X: Data,found: Maybe<&2,Cap>) -> Maybe<&2,T.Token<X>>:
  match found:
    case Some{value}: Some{indentedCode(X,H.trimTrailingBlankLines(capWhole(value)))}
    case None{}: None{}
def code(-X: Data,+rules: Rules.Block,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,T.Token<X>>: codeOf(X,blockExecAt(rules,Rules.BlockCode{},first,src))

# indentCodeCompensation: a fence indented by N whitespace characters takes
# up to N of them off each line of its code.
def leadingSpace(text: String,+count: Nat) -> Nat:
  match text:
    case SNil{}: count
    case SCon{+char,rest}: Bool.pick(Unit -> Nat,H.isSpace(char),_ => leadingSpace(rest,count + 1n),_ => count)(Unit{})
def fenceIndent(+raw: String) -> Nat:
  +count = leadingSpace(raw,0n)
  Bool.pick(Nat,Nat.is_gt(count,0n) && String.starts_with(String.drop(raw,count),"```"),count,0n)
def compensated(lines: List<&2,String>,+indent: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: List.reverse(&2,String,reversed)
    case +line <> rest:
      +own = leadingSpace(line,0n)
      compensated(rest,indent,Bool.pick(String,Nat.is_gt(own,0n) && Nat.is_ge(own,indent),String.drop(line,indent),line) <> reversed)
def indentCodeCompensation(+raw: String,+text: String) -> String:
  +indent = fenceIndent(raw)
  Bool.pick(Unit -> String,Nat.is_eq(indent,0n),_ => text,_ => H.joinLines(compensated(H.linesOf(text),indent,Nil{})))(Unit{})
def fencesOf(-X: Data,found: Maybe<&2,Cap>) -> Maybe<&2,T.Token<X>>:
  match found:
    case Some{+value}:
      +raw = capWhole(value)
      Some{T.Code{raw,None{},Some{H.unescapePunctuation(Text.trim(capText(value,2n)))},indentCodeCompensation(raw,capText(value,3n))}}
    case None{}: None{}
def fences(-X: Data,+rules: Rules.Block,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,T.Token<X>>: fencesOf(X,blockExecAt(rules,Rules.BlockFences{},first,src))

# Trailing #s go when a space precedes them (or nothing does).
def closingHashes(+text: String) -> String:
  +trimmed = H.rtrim(text,'#')
  Bool.pick(Unit -> String,H.endsWithChar(text,'#') && (String.is_empty(trimmed) || H.endsWithChar(trimmed,' ')),_ => Text.trim(trimmed),_ => text)(Unit{})
def headingOf(found: Maybe<&2,Cap>) -> Maybe<&2,Titled>:
  match found:
    case Some{+value}: Some{Titled{H.rtrim(capWhole(value),'\n'),String.length(capText(value,1n)),closingHashes(Text.trim(capText(value,2n)))}}
    case None{}: None{}
def heading(+rules: Rules.Block,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,Titled>: headingOf(blockExecAt(rules,Rules.BlockHeading{},first,src))

def hrOf(-X: Data,found: Maybe<&2,Cap>) -> Maybe<&2,T.Token<X>>:
  match found:
    case Some{value}: Some{T.Hr{H.rtrim(capWhole(value),'\n')}}
    case None{}: None{}
def hr(-X: Data,+rules: Rules.Block,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,T.Token<X>>: hrOf(X,blockExecAt(rules,Rules.BlockHr{},first,src))

# The blockquote's match; the lexer splits and lexes it.
def blockquoteOf(found: Maybe<&2,Cap>) -> Maybe<&2,String>:
  match found:
    case Some{value}: Some{capWhole(value)}
    case None{}: None{}
def blockquote(+rules: Rules.Block,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,String>: blockquoteOf(blockExecAt(rules,Rules.BlockBlockquote{},first,src))

def isPreTag(name: Maybe<&2,String>) -> Bool:
  match name:
    case Some{+name}: String.eq(name,"pre") || String.eq(name,"script") || String.eq(name,"style")
    case None{}: False{}
def htmlOf(-X: Data,found: Maybe<&2,Cap>) -> Maybe<&2,T.Token<X>>:
  match found:
    case Some{+value}:
      +raw = H.trimTrailingBlankLines(capWhole(value))
      Some{T.HTML{raw,isPreTag(capGroup(value,1n)),raw,True{}}}
    case None{}: None{}
def html(-X: Data,+rules: Rules.Block,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,T.Token<X>>: htmlOf(X,blockExecAt(rules,Rules.BlockHtml{},first,src))

def hasLineTerminator(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{+char,rest}: Bool.pick(Unit -> Bool,H.isLineTerminator(char),_ => True{},_ => hasLineTerminator(rest))(Unit{})
# other.hrefBrackets, `/^<(.*)>$/` → "$1".
def hrefBrackets(+text: String) -> String:
  Bool.pick(Unit -> String,H.startsWithChar(text,'<') && H.endsWithChar(text,'>') && Nat.is_ge(String.length(text),2n) && Bool.not(hasLineTerminator(text)),
    _ => H.inner(text,1n,1n),_ => text)(Unit{})
def definitionTitle(title: Maybe<&2,String>) -> Maybe<&2,String>:
  match title:
    case Some{+text}: Bool.pick(Unit -> Maybe<&2,String>,String.is_empty(text),_ => Some{text},_ => Some{H.unescapePunctuation(H.inner(text,1n,1n))})(Unit{})
    case None{}: None{}
def definitionOf(-X: Data,found: Maybe<&2,Cap>) -> Maybe<&2,T.Token<X>>:
  match found:
    case Some{+value}: Some{T.Def{H.rtrim(capWhole(value),'\n'),collapseSpace(CaseMap.lower(capText(value,1n))),H.unescapePunctuation(hrefBrackets(capText(value,2n))),definitionTitle(capGroup(value,3n))}}
    case None{}: None{}
def definition(-X: Data,+rules: Rules.Block,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,T.Token<X>>: definitionOf(X,blockExecAt(rules,Rules.BlockDefinition{},first,src))

# Tables: the lexer queues each cell's inline source.
type TableDraft is Data: TableDraft{raw: String,align: List<&2,Maybe<&2,T.Align>>,header: List<&2,String>,rows: List<&2,List<&2,String>>}
# other.tableAlignChars, `/^\||\| *$/g` → "".
def trailingPipe(+text: String) -> String:
  +rest = H.dropWhileChar(String.reverse(text),' ')
  Bool.pick(Unit -> String,H.startsWithChar(rest,'|'),_ => String.reverse(String.drop(rest,1n)),_ => text)(Unit{})
def alignChars(text: String) -> String:
  match text:
    case SCon{'|',rest}: trailingPipe(rest)
    case text: trailingPipe(text)
def afterDashes(text: String) -> Maybe<&2,String>:
  match text:
    case SCon{'-',rest}: Some{H.dropWhileChar(rest,'-')}
    case _: None{}
def spacesOnly(text: String) -> Bool: String.is_empty(H.dropWhileChar(text,' '))
def colonThenSpaces(text: String) -> Bool:
  match text:
    case SCon{':',rest}: spacesOnly(rest)
    case _: False{}
def dashesThen(after: Maybe<&2,String>,colon: Bool) -> Bool:
  match after colon:
    case Some{rest} True{}: colonThenSpaces(rest)
    case Some{rest} False{}: spacesOnly(rest)
    case None{} _: False{}
# other.tableAlignRight `^ *-+: *$`, tableAlignCenter `^ *:-+: *$`,
# tableAlignLeft `^ *:-+ *$`.
def alignOf(cell: String) -> Maybe<&2,T.Align>:
  +text = H.dropWhileChar(cell,' ')
  +colon = H.startsWithChar(text,':')
  Bool.pick(Unit -> Maybe<&2,T.Align>,dashesThen(afterDashes(text),True{}),_ => Some{T.AlignRight{}},
    _ => Bool.pick(Unit -> Maybe<&2,T.Align>,colon && dashesThen(afterDashes(String.drop(text,1n)),True{}),_ => Some{T.AlignCenter{}},
    _ => Bool.pick(Unit -> Maybe<&2,T.Align>,colon && dashesThen(afterDashes(String.drop(text,1n)),False{}),_ => Some{T.AlignLeft{}},_ => None{})(Unit{}))(Unit{}))(Unit{})
def aligns(cells: List<&2,String>,reversed: List<&2,Maybe<&2,T.Align>>) -> List<&2,Maybe<&2,T.Align>>:
  match cells:
    case Nil{}: List.reverse(&2,Maybe<&2,T.Align>,reversed)
    case cell <> rest: aligns(rest,alignOf(cell) <> reversed)
# other.tableRowBlankLine, `/\n[ \t]*$/` → "".
def rowBlankLine(+text: String) -> String:
  +rest = H.dropSpaceOrTab(String.reverse(text))
  Bool.pick(Unit -> String,H.startsWithChar(rest,'\n'),_ => String.reverse(String.drop(rest,1n)),_ => text)(Unit{})
def rowCells(rows: List<&2,String>,+count: Nat,reversed: List<&2,List<&2,String>>) -> List<&2,List<&2,String>>:
  match rows:
    case Nil{}: List.reverse(&2,List<&2,String>,reversed)
    case row <> rest: rowCells(rest,count,H.splitCells(row,Some{count}) <> reversed)
def tableRows(cells: Maybe<&2,String>) -> List<&2,String>:
  match cells:
    case Some{+text}: Bool.pick(Unit -> List<&2,String>,Text.blank(text),_ => Nil{},_ => H.linesOf(rowBlankLine(text)))(Unit{})
    case None{}: Nil{}
def tableBuilt(+raw: String,+headers: List<&2,String>,+alignCells: List<&2,String>,rows: List<&2,String>) -> Maybe<&2,TableDraft>:
  +count = List.length(&2,String,headers)
  Bool.pick(Unit -> Maybe<&2,TableDraft>,Nat.is_eq(count,List.length(&2,String,alignCells)),
    _ => Some{TableDraft{raw,aligns(alignCells,Nil{}),headers,rowCells(rows,count,Nil{})}},_ => None{})(Unit{})
def tableOf(found: Maybe<&2,Cap>) -> Maybe<&2,TableDraft>:
  match found:
    case Some{+value}:
      +delimiter = capText(value,2n)
      Bool.pick(Unit -> Maybe<&2,TableDraft>,String.contains(delimiter,":") || String.contains(delimiter,"|"),
        _ => tableBuilt(H.rtrim(capWhole(value),'\n'),H.splitCells(capText(value,1n),None{}),Strings.split(alignChars(delimiter),'|'),tableRows(capGroup(value,3n))),
        _ => None{})(Unit{})
    case None{}: None{}
def table(+rules: Rules.Block,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,TableDraft>: tableOf(blockExecAt(rules,Rules.BlockTable{},first,src))

def lheadingOf(found: Maybe<&2,Cap>) -> Maybe<&2,Titled>:
  match found:
    case Some{+value}: Some{Titled{H.rtrim(capWhole(value),'\n'),Bool.pick(Nat,H.startsWithChar(capText(value,2n),'='),1n,2n),Text.trim(capText(value,1n))}}
    case None{}: None{}
def underlineRunOf(+text: String,+char: Char) -> Bool:
  +after = H.dropWhileChar(text,char)
  Nat.is_lt(String.length(after),String.length(text)) && String.is_empty(H.dropWhileChar(after,' '))
# A setext heading needs a later line of at most three spaces, a run of `=`
# or `-` and spaces, before the first blank line: without one the rule is
# not tried (the expression cannot match).
def underlineLine(+line: String) -> Bool:
  +text = H.dropWhileChar(line,' ')
  Nat.is_le(String.length(line) - String.length(text),3n) && (underlineRunOf(text,'=') || underlineRunOf(text,'-'))
# A line of the paragraph was read (`split`) and a newline ended it; is the
# next line an underline (1), a blank line that stops the paragraph (2), or
# neither (0)?
type Ahead is Data: Ahead{verdict: U32,rest: List<&2,U32>}
def nextVerdict(+next: Split) -> U32:
  match next:
    case Split{+line,_,+newline}: Bool.pick(U32,underlineLine(line),1,Bool.pick(U32,Text.blank(line) && newline,2,0))
def aheadOf(split: Split) -> Ahead:
  match split:
    case Split{_,+rest,True{}}: Ahead{nextVerdict(splitLine(rest)),rest}
    case Split{_,_,False{}}: Ahead{2,Nil{}}
# `codes` starts a line of the paragraph (`ahead`: what follows that line).
def underlineAhead(fuel: Nat,ahead: Ahead) -> Bool:
  match fuel ahead:
    case Zero{} _: False{}
    case _ Ahead{1,_}: True{}
    case _ Ahead{2,_}: False{}
    case Succ{more} Ahead{_,rest}: underlineAhead(more,aheadOf(splitLine(rest)))
def lheadingIf(ahead: Bool,+rules: Rules.Block,first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,Titled>:
  match ahead:
    case True{}: lheadingOf(blockExecAt(rules,Rules.BlockLheading{},first,src))
    case False{}: None{}
def lheading(+rules: Rules.Block,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,Titled>: lheadingIf(underlineAhead(unbounded(),aheadOf(splitLine(src))),rules,first,src)

def paragraphText(+text: String) -> String: Bool.pick(Unit -> String,H.endsWithChar(text,'\n'),_ => H.dropEnd(text,1n),_ => text)(Unit{})
def paragraphOf(found: Maybe<&2,Cap>) -> Maybe<&2,Texted>:
  match found:
    case Some{+value}: Some{Texted{capWhole(value),paragraphText(capText(value,1n))}}
    case None{}: None{}
def paragraph(+rules: Rules.Block,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,Texted>: paragraphOf(blockExecAt(rules,Rules.BlockParagraph{},first,src))

def textOfFound(found: Maybe<&2,Cap>) -> Maybe<&2,Texted>:
  match found:
    case Some{+value}: Some{Texted{capWhole(value),capWhole(value)}}
    case None{}: None{}
def blockText(+rules: Rules.Block,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,Texted>: textOfFound(blockExecAt(rules,Rules.BlockText{},first,src))

# Lists
# -----
# The list tokenizer's item collection; the lexer then lexes each item's
# text as blocks and finishes the list (looseness, task checkboxes).

type ItemDraft is Data: ItemDraft{raw: String,task: Bool,text: String}
type ListDraft is Data: ListDraft{raw: String,ordered: Bool,start: Maybe<&2,Nat>,loose: Bool,items: List<&2,ItemDraft>}

# The rest of a line after leading spaces, when there are at most `limit`
# of them (` {0,n}`).
def indented(line: String,limit: Nat) -> Maybe<&2,String>:
  match line limit:
    case SCon{' ',rest} Succ{more}: indented(rest,more)
    case SCon{' ',_} Zero{}: None{}
    case line _: Some{line}
def restStarts(rest: Maybe<&2,String>,+prefix: String) -> Bool:
  match rest:
    case Some{text}: String.starts_with(text,prefix)
    case None{}: False{}
# other.fencesBeginRegex(n), `^ {0,n}(?:```|~~~)`.
def fencesBegin(+limit: Nat,+line: String) -> Bool: restStarts(indented(line,limit),"```") || restStarts(indented(line,limit),"~~~")
# other.headingBeginRegex(n), `^ {0,n}#`.
def headingBegin(+limit: Nat,+line: String) -> Bool: restStarts(indented(line,limit),"#")
# other.blockquoteBeginRegex(n), `^ {0,n}>`.
def blockquoteBegin(+limit: Nat,+line: String) -> Bool: restStarts(indented(line,limit),">")
def isAsciiLetter(+char: Char) -> Bool: (Char.is_upper(char) || Char.is_lower(char)) && U32.is_lt(Char.to_u32(char),128)
# `.*>`: a '>' before any line terminator.
def closesTag(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{+char,rest}: Bool.pick(Unit -> Bool,Char.is_eq(char,'>'),_ => True{},_ => Bool.pick(Unit -> Bool,H.isLineTerminator(char),_ => False{},_ => closesTag(rest))(Unit{}))(Unit{})
def tagOpening(text: String) -> Bool:
  match text:
    case SCon{+char,+after}: (isAsciiLetter(char) && closesTag(after)) || (Char.is_eq(char,'!') && String.starts_with(after,"--"))
    case SNil{}: False{}
def htmlOpening(rest: Maybe<&2,String>) -> Bool:
  match rest:
    case Some{SCon{'<',after}}: tagOpening(after)
    case _: False{}
# other.htmlBeginRegex(n), `^ {0,n}<(?:[a-z].*>|!--)` (case-insensitive).
def htmlBegin(+limit: Nat,+line: String) -> Bool: htmlOpening(indented(line,limit))
# One to nine digits and what follows them.
def digitsThen(text: String,+count: Nat) -> Maybe<&2,String>:
  match text:
    case SCon{+char,+rest}: Bool.pick(Unit -> Maybe<&2,String>,Char.is_digit(char),_ => digitsThen(rest,count + 1n),_ => Bool.pick(Maybe<&2,String>,Nat.is_gt(count,0n) && Nat.is_le(count,9n),Some{SCon{char,rest}},None{}))(Unit{})
    case SNil{}: Bool.pick(Maybe<&2,String>,Nat.is_gt(count,0n) && Nat.is_le(count,9n),Some{SNil{}},None{})
# The rest of a line after a bullet: nothing, or a space or tab first.
def bulletEnd(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{+char,_}: H.isSpaceOrTab(char)
def orderedEnd(rest: Maybe<&2,String>) -> Bool:
  match rest:
    case Some{SCon{+char,after}}: (Char.is_eq(char,'.') || Char.is_eq(char,')')) && bulletEnd(after)
    case _: False{}
def bulletStart(text: String) -> Bool:
  match text:
    case SCon{+char,+after}: ((Char.is_eq(char,'*') || Char.is_eq(char,'+') || Char.is_eq(char,'-')) && bulletEnd(after)) || orderedEnd(digitsThen(SCon{char,after},0n))
    case SNil{}: False{}
def bulletAfter(rest: Maybe<&2,String>) -> Bool:
  match rest:
    case Some{text}: bulletStart(text)
    case None{}: False{}
# other.nextBulletRegex(n),
# `^ {0,n}(?:[*+-]|\d{1,9}[.)])((?:[ \t][^\n]*)?(?:\n|$))`, on a line.
def nextBullet(+limit: Nat,+line: String) -> Bool: bulletAfter(indented(line,limit))
# A run of at least three `char`s, each followed by spaces, to the end.
def ruleOf(text: String,+char: Char,+count: Nat) -> Bool:
  match text:
    case SNil{}: Nat.is_ge(count,3n)
    case SCon{+next,+rest}: Bool.pick(Unit -> Bool,Char.is_eq(next,char),_ => ruleOf(rest,char,count + 1n),_ => Bool.pick(Unit -> Bool,Char.is_eq(next,' '),_ => ruleOf(rest,char,count),_ => False{})(Unit{}))(Unit{})
def ruleStart(text: String) -> Bool:
  match text:
    case SCon{+char,+after}: (Char.is_eq(char,'-') || Char.is_eq(char,'_') || Char.is_eq(char,'*')) && ruleOf(SCon{char,after},char,0n)
    case SNil{}: False{}
def ruleAfter(rest: Maybe<&2,String>) -> Bool:
  match rest:
    case Some{text}: ruleStart(text)
    case None{}: False{}
# other.hrRegex(n), `^ {0,n}((?:- *){3,}|(?:_ *){3,}|(?:\* *){3,})(?:\n+|$)`, on a
# line.
def hrBegin(+limit: Nat,+line: String) -> Bool: ruleAfter(indented(line,limit))

def isTaskMark(+mark: Char) -> Bool: Char.is_eq(mark,' ') || Char.is_eq(mark,'x') || Char.is_eq(mark,'X')
# `[ ]`, `[x]` or `[X]` and at least one space: the text after the spaces.
def taskBox(text: String) -> Maybe<&2,String>:
  match text:
    case SCon{'[',SCon{+mark,SCon{']',SCon{' ',rest}}}}: Bool.pick(Maybe<&2,String>,isTaskMark(mark),Some{H.dropWhileChar(rest,' ')},None{})
    case _: None{}
def taskAfter(rest: Maybe<&2,String>) -> Bool:
  match rest:
    case Some{SCon{+char,_}}: Bool.not(H.isSpace(char))
    case _: False{}
# other.listIsTask, `/^\[[ xX]\] +\S/`.
def listIsTask(+text: String) -> Bool: taskAfter(taskBox(text))
# other.listReplaceTask, `/^\[[ xX]\] +/` → "".
def listReplaceTask(+text: String) -> String: Maybe.default(&2,String,taskBox(text),text)
def boxAt(text: String) -> Bool:
  match text:
    case SCon{+mark,SCon{']',_}}: isTaskMark(mark)
    case _: False{}
# other.listTaskCheckbox, `/\[[ xX]\]/`: the first checkbox's mark.
def checkbox(text: String) -> Maybe<&2,Char>:
  match text:
    case SNil{}: None{}
    case SCon{+char,+rest}: Bool.pick(Unit -> Maybe<&2,Char>,Char.is_eq(char,'[') && boxAt(rest),_ => String.get(rest,0n),_ => checkbox(rest))(Unit{})
# other.doubleBlankLine, `/\n[ \t]*\n[ \t]*$/`.
def endsBlank(+reversed: String) -> Maybe<&2,String>:
  +rest = H.dropSpaceOrTab(reversed)
  Bool.pick(Unit -> Maybe<&2,String>,H.startsWithChar(rest,'\n'),_ => Some{String.drop(rest,1n)},_ => None{})(Unit{})
def endsBlankAgain(rest: Maybe<&2,String>) -> Bool:
  match rest:
    case Some{text}: Maybe.is_some(&2,String,endsBlank(text))
    case None{}: False{}
def doubleBlankLine(text: String) -> Bool: endsBlankAgain(endsBlank(String.reverse(text)))

# The item being collected: raw and content pieces (reversed), the last line
# read (tabs expanded, dedented) and whether that line was blank.
type Item is Data: Item{raw: List<&2,String>,contents: List<&2,String>,line: String,blank: Bool}
type Continued is Data: Continued{item: Item,src: List<&2,U32>}
# Whether a line that is not indented enough ends the item; otherwise it
# continues the item's paragraph.
# (`rest`: the line after at most `limit` spaces.)
def interrupts(+rest: Maybe<&2,String>) -> Bool: restStarts(rest,"```") || restStarts(rest,"~~~") || restStarts(rest,"#") || ruleAfter(rest)
def unindentedEnds(+limit: Nat,item: Item) -> Bool:
  match item:
    case Item{_,_,+line,blank}: blank || atLeast(nonSpace(tabsExpanded(line)),4n) || interrupts(indented(line,limit))
def endsAfter(+rest: Maybe<&2,String>) -> Bool: interrupts(rest) || htmlOpening(rest) || restStarts(rest,">") || bulletAfter(rest)
def lineEnds(+limit: Nat,+line: String) -> Bool: endsAfter(indented(line,limit))
def appended(item: Item,+rawLine: String,+withoutTabs: String,+indent: Nat,content: String) -> Item:
  match item:
    case Item{raw,contents,_,_}: Item{"\n" <> rawLine <> raw,content <> "\n" <> contents,String.drop(withoutTabs,indent),Text.blank(rawLine)}
# The item's next line: where the item ends, or the line (as read, with tabs
# expanded, and as it joins the item's content) and the source after it.
type LineStep is Data:
  ItemEnds{}
  ItemLine{rawLine: String,withoutTabs: String,content: String,next: List<&2,U32>}
def lineKept(ends: Bool,+rawLine: String,+withoutTabs: String,+content: String,next: List<&2,U32>) -> LineStep:
  match ends:
    case True{}: ItemEnds{}
    case False{}: ItemLine{rawLine,withoutTabs,content,next}
# An indented or blank line continues the item; another continues its
# paragraph unless the item's last line was blank or starts a block.
def lineIndented(indented: Bool,+limit: Nat,+indent: Nat,item: Item,+rawLine: String,+withoutTabs: String,next: List<&2,U32>) -> LineStep:
  match indented:
    case True{}: ItemLine{rawLine,withoutTabs,String.drop(withoutTabs,indent),next}
    case False{}: lineKept(unindentedEnds(limit,item),rawLine,withoutTabs,rawLine,next)
def lineRead(ends: Bool,+limit: Nat,+indent: Nat,item: Item,+rawLine: String,+withoutTabs: String,next: List<&2,U32>) -> LineStep:
  match ends:
    case True{}: ItemEnds{}
    case False{}: lineIndented(atLeast(nonSpace(withoutTabs),indent) || Text.blank(rawLine),limit,indent,item,rawLine,withoutTabs,next)
def lineSplit(+limit: Nat,+indent: Nat,item: Item,split: Split) -> LineStep:
  match split: case Split{+rawLine,next,_}: lineRead(lineEnds(limit,rawLine),limit,indent,item,rawLine,tabsExpanded(rawLine),next)
def lineStep(+limit: Nat,+indent: Nat,item: Item,src: List<&2,U32>) -> LineStep:
  match src:
    case Nil{}: ItemEnds{}
    case src: lineSplit(limit,indent,item,splitLine(src))
# The item's following lines (`step`: the next one).
def itemLines(fuel: Nat,step: LineStep,+limit: Nat,+indent: Nat,+item: Item,src: List<&2,U32>) -> Continued:
  match fuel step:
    case Zero{} _: Continued{item,src}
    case _ ItemEnds{}: Continued{item,src}
    case Succ{more} ItemLine{rawLine,withoutTabs,content,+next}:
      +grown = appended(item,rawLine,withoutTabs,indent,content)
      itemLines(more,lineStep(limit,indent,grown,next),limit,indent,grown,next)

# An item's first line: the column its content starts at and that content.
type Opening is Data: Opening{indent: Nat,contents: String}
def opening(+line: String,+marker: Nat) -> Opening:
  +position = Maybe.default(&2,Nat,nonSpace(line),0n)
  Bool.pick(Unit -> Opening,Text.blank(line),_ => Opening{marker + 1n,""},
    _ => Bool.pick(Unit -> Opening,Nat.is_gt(position,4n),_ => Opening{marker + 1n,String.drop(line,1n)},_ => Opening{position + marker,String.drop(line,position)})(Unit{}))(Unit{})
def openingIndent(value: Opening) -> Nat:
  match value: case Opening{indent,_}: indent
def openingContents(value: Opening) -> String:
  match value: case Opening{_,contents}: contents
# One item from its bullet line (`raw`, the marker's width and the line after
# it): the item and the source after it.
def itemsFirst(+limit: Nat,+indent: Nat,+item: Item,+src: List<&2,U32>) -> Continued: itemLines(unbounded(),lineStep(limit,indent,item,src),limit,indent,item,src)
def itemOpened(blank: Bool,+raw: String,+line: String,+first: Opening,split: Split,+src: List<&2,U32>) -> Continued:
  match blank split:
    case True{} Split{nextLine,rest,_}: Continued{Item{"\n" <> nextLine <> raw <> Nil{},openingContents(first) <> Nil{},line,True{}},rest}
    case False{} _: itemsFirst(Nat.min(3n,openingIndent(first) - 1n),openingIndent(first),Item{raw <> Nil{},openingContents(first) <> Nil{},line,Text.blank(line)},src)
def splitBlank(+split: Split) -> Bool:
  match split: case Split{line,_,_}: H.blankLine(line)
def itemFrom(+raw: String,+marker: Nat,+line: String,+src: List<&2,U32>) -> Continued:
  +next = splitLine(src)
  itemOpened(Text.blank(line) && splitBlank(next),raw,line,opening(line,marker),next,src)

# One collected item and the source after it.
type Step is Data: Step{raw: String,text: String,src: List<&2,U32>}
def stepped(value: Continued) -> Step:
  match value: case Continued{Item{raw,contents,_,_},src}: Step{H.concatReversed(raw,""),H.concatReversed(contents,""),src}
# other.listItemRegex(bull), `^( {0,3}BULL)((?:[\t ][^\n]*)?(?:\n|$))`
# for the list's bullet: a given `*`, `+` or `-`, or one to nine digits and
# a given `.` or `)`. The match is the bullet with its indentation (the
# marker's width) and the rest of the line with its newline.
type Bullet is Data:
  Unordered{mark: U32}
  Ordered{delimiter: U32}
type ItemStart is Data: ItemStart{marker: Nat,rest: String}
def digitRun(codes: List<&2,U32>,+count: Nat) -> Nat:
  match codes:
    case +scalar <> rest: Bool.pick(Unit -> Nat,U32.is_ge(scalar,48) && U32.is_le(scalar,57),_ => digitRun(rest,count + 1n),_ => count)(Unit{})
    case Nil{}: count
def bulletLength(bullet: Bullet,+codes: List<&2,U32>) -> Maybe<&2,Nat>:
  match bullet:
    case Unordered{+mark}: Bool.pick(Maybe<&2,Nat>,Maybe.default(&2,Bool,Maybe.map(&2,U32,Bool,scalar => U32.is_eq(scalar,mark),List.head(&2,U32,codes)),False{}),Some{1n},None{})
    case Ordered{+delimiter}:
      +digits = digitRun(codes,0n)
      Bool.pick(Maybe<&2,Nat>,Nat.is_ge(digits,1n) && Nat.is_le(digits,9n) && U32.is_eq(Maybe.default(&2,U32,List.get(&2,U32,codes,digits),0),delimiter),Some{digits + 1n},None{})
def lineWithNewline(split: Split) -> String:
  match split:
    case Split{line,_,True{}}: line ++ "\n"
    case Split{line,_,False{}}: line
# `(?:[\t ][^\n]*)?(?:\n|$)` after the bullet.
def bulletRest(+codes: List<&2,U32>) -> Maybe<&2,String>:
  match codes:
    case Nil{}: Some{""}
    case +scalar <> rest:
      Bool.pick(Unit -> Maybe<&2,String>,U32.is_eq(scalar,9) || U32.is_eq(scalar,32),_ => Some{lineWithNewline(splitLine(codes))},
        _ => Bool.pick(Maybe<&2,String>,U32.is_eq(scalar,10),Some{"\n"},None{}))(Unit{})
def itemStarted(+indent: Nat,length: Maybe<&2,Nat>,+after: List<&2,U32>) -> Maybe<&2,ItemStart>:
  match length:
    case Some{+bullet}: Maybe.map(&2,String,ItemStart,rest => ItemStart{indent + bullet,rest},bulletRest(drop(after,bullet)))
    case None{}: None{}
def spaceCount(codes: List<&2,U32>,limit: Nat,+count: Nat) -> Nat:
  match codes limit:
    case _ Zero{}: count
    case +scalar <> rest Succ{more}: Bool.pick(Unit -> Nat,U32.is_eq(scalar,32),_ => spaceCount(rest,more,count + 1n),_ => count)(Unit{})
    case Nil{} _: count
def itemStart(+bullet: Bullet,+src: List<&2,U32>) -> Maybe<&2,ItemStart>:
  +indent = spaceCount(src,4n,0n)
  Bool.pick(Unit -> Maybe<&2,ItemStart>,Nat.is_le(indent,3n),_ => itemStarted(indent,bulletLength(bullet,drop(src,indent)),drop(src,indent)),_ => None{})(Unit{})
def stepOf(found: Maybe<&2,ItemStart>,+src: List<&2,U32>) -> Maybe<&2,Step>:
  match found:
    case Some{ItemStart{+marker,+rest}}:
      +raw = slice(src,0n,marker) ++ rest
      Some{stepped(itemFrom(raw,marker,H.expandTabs(firstTextLine(rest),marker,""),drop(src,String.length(raw))))}
    case None{}: None{}
# The item at `src`, unless there is no bullet or the line is a rule.
def stepAt(+rules: Rules.Block,+bullet: Bullet,+src: List<&2,U32>) -> Maybe<&2,Step>:
  Bool.pick(Unit -> Maybe<&2,Step>,Maybe.is_some(&2,Cap,blockExec(rules,Rules.BlockHr{},src)),_ => None{},_ => stepOf(itemStart(bullet,src),src))(Unit{})

# Items (reversed), whether the list is loose and whether the previous item
# ended with a blank line.
type Collected is Data: Collected{items: List<&2,ItemDraft>,loose: Bool,endsWithBlankLine: Bool}
def collectedItem(collected: Collected,+raw: String,+text: String) -> Collected:
  match collected:
    case Collected{items,+loose,+ends}: Collected{ItemDraft{raw,listIsTask(text),text} <> items,loose || ends,ends || (Bool.not(loose) && doubleBlankLine(raw))}
def itemsFrom(fuel: Nat,+rules: Rules.Block,+bullet: Bullet,collected: Collected,next: Maybe<&2,Step>) -> Collected:
  match fuel next:
    case _ None{}: collected
    case Zero{} _: collected
    case Succ{more} Some{Step{raw,text,src}}: itemsFrom(more,rules,bullet,collectedItem(collected,raw,text),stepAt(rules,bullet,src))

def itemRawOf(item: ItemDraft) -> String:
  match item: case ItemDraft{raw,_,_}: raw
def rawsReversed(items: List<&2,ItemDraft>,text: String) -> String:
  match items:
    case Nil{}: text
    case item <> rest: rawsReversed(rest,itemRawOf(item) ++ text)
def trimmedLast(item: ItemDraft) -> ItemDraft:
  match item: case ItemDraft{raw,task,text}: ItemDraft{Text.trimEnd(raw),task,Text.trimEnd(text)}
def trimmedHead(items: List<&2,ItemDraft>) -> List<&2,ItemDraft>:
  match items:
    case last <> earlier: trimmedLast(last) <> earlier
    case Nil{}: Nil{}
def listFinished(collected: Collected,ordered: Bool,start: Maybe<&2,Nat>) -> Maybe<&2,ListDraft>:
  match collected:
    case Collected{Nil{},_,_}: None{}
    case Collected{+items,loose,_}: Some{ListDraft{Text.trimEnd(rawsReversed(items,"")),ordered,start,loose,List.reverse(&2,ItemDraft,trimmedHead(items))}}
# The bullet's last character: its mark, or an ordered list's delimiter.
def lastScalar(+text: String) -> U32: Maybe.default(&2,U32,Maybe.map(&2,Char,U32,Char.to_u32,H.lastChar(text)),0)
def listWith(+rules: Rules.Block,+src: List<&2,U32>,+bull: String) -> Maybe<&2,ListDraft>:
  +ordered = Nat.is_gt(String.length(bull),1n)
  +bullet = Bool.pick(Bullet,ordered,Ordered{lastScalar(bull)},Unordered{lastScalar(bull)})
  listFinished(itemsFrom(unbounded(),rules,bullet,Collected{Nil{},False{},False{}},stepAt(rules,bullet,src)),ordered,Bool.pick(Maybe<&2,Nat>,ordered,Nat.read(H.dropEnd(bull,1n)),None{}))
def listOf(+rules: Rules.Block,+src: List<&2,U32>,found: Maybe<&2,Cap>) -> Maybe<&2,ListDraft>:
  match found:
    case Some{value}: listWith(rules,src,Text.trim(capText(value,1n)))
    case None{}: None{}
def list(+rules: Rules.Block,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,ListDraft>: listOf(rules,src,blockExecAt(rules,Rules.BlockList{},first,src))

# Inline tokenizers
# -----------------

def escapeOf(-X: Data,found: Maybe<&2,Cap>) -> Maybe<&2,T.Token<X>>:
  match found:
    case Some{+value}: Some{T.Escape{capWhole(value),capText(value,1n)}}
    case None{}: None{}
def escape(-X: Data,+rules: Rules.Inline,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,T.Token<X>>: escapeOf(X,inlineExecAt(rules,Rules.InlineEscape{},first,src))

# An inline tag's text; the lexer tracks the link and raw-block state it
# opens or closes.
def wholeOf(found: Maybe<&2,Cap>) -> Maybe<&2,String>:
  match found:
    case Some{value}: Some{capWhole(value)}
    case None{}: None{}
def tag(+rules: Rules.Inline,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,String>: wholeOf(inlineExecAt(rules,Rules.InlineTag{},first,src))
def startsWithFolded(+text: String,+prefix: String) -> Bool: String.starts_with(Text.asciiLower(String.take(text,String.length(prefix))),prefix)
def spaceFirst(text: String) -> Bool:
  match text:
    case SCon{+char,_}: H.isSpace(char)
    case SNil{}: False{}
def tagName(+rest: String,+name: String) -> Bool:
  +after = String.drop(rest,String.length(name))
  startsWithFolded(rest,name) && (H.startsWithChar(after,'>') || spaceFirst(after))
def preScriptName(+rest: String) -> Bool: tagName(rest,"pre") || tagName(rest,"code") || tagName(rest,"kbd") || tagName(rest,"script")
# other.startATag `/^<a /i`, endATag `/^<\/a>/i`, startPreScriptTag
# `/^<(pre|code|kbd|script)(\s|>)/i`, endPreScriptTag.
def startATag(+text: String) -> Bool: startsWithFolded(text,"<a ")
def endATag(+text: String) -> Bool: startsWithFolded(text,"</a>")
def startPreScriptTag(+text: String) -> Bool: H.startsWithChar(text,'<') && preScriptName(String.drop(text,1n))
def endPreScriptTag(+text: String) -> Bool: startsWithFolded(text,"</") && preScriptName(String.drop(text,2n))

# A link or image before its text is lexed (outputLink's input).
type LinkMatch is Data: LinkMatch{raw: String,href: String,title: Maybe<&2,String>,label: String,isImage: Bool}
def nonEmpty(+text: String) -> Maybe<&2,String>: Bool.pick(Maybe<&2,String>,String.is_empty(text),None{},Some{text})
# `href`, `title` (cap[3]) and the rest of link(); `raw` may have been cut
# at the closing parenthesis.
def linkBuilt(+raw: String,label: String,+href: String,title: Maybe<&2,String>) -> LinkMatch:
  +trimmed = Text.trim(href)
  LinkMatch{raw,H.unescapePunctuation(Bool.pick(String,H.startsWithChar(trimmed,'<'),H.inner(trimmed,1n,1n),trimmed)),Maybe.map(&2,String,String,H.unescapePunctuation,nonEmpty(Maybe.default(&2,String,Maybe.map(&2,String,String,value => H.inner(value,1n,1n),title),""))),label,H.startsWithChar(raw,'!')}
def angleClosed(+target: String) -> Bool:
  +body = H.dropEnd(target,1n)
  H.endsWithChar(target,'>') && Bool.not(Nat.is_eq(Nat.mod(String.length(target) - String.length(H.rtrim(body,'\\')),2n),0n))
def linkCut(bracket: H.Bracket,+raw: String,+label: String,+href: String,title: Maybe<&2,String>) -> Maybe<&2,LinkMatch>:
  match bracket:
    case H.Unbalanced{}: None{}
    case H.Unclosed{}: Some{linkBuilt(raw,label,href,title)}
    case H.ClosesAt{+index}: Some{linkBuilt(Text.trim(String.take(raw,Bool.pick(Nat,H.startsWithChar(raw,'!'),5n,4n) + String.length(label) + index)),label,String.take(href,index),Some{""})}
def linkOf(found: Maybe<&2,Cap>) -> Maybe<&2,LinkMatch>:
  match found:
    case Some{+value}:
      +href = capText(value,2n)
      +trimmed = Text.trim(href)
      Bool.pick(Unit -> Maybe<&2,LinkMatch>,H.startsWithChar(trimmed,'<'),
        _ => Bool.pick(Unit -> Maybe<&2,LinkMatch>,angleClosed(trimmed),_ => Some{linkBuilt(capWhole(value),capText(value,1n),href,capGroup(value,3n))},_ => None{})(Unit{}),
        _ => linkCut(H.findClosingBracket(href),capWhole(value),capText(value,1n),href,capGroup(value,3n)))(Unit{})
    case None{}: None{}
def link(+rules: Rules.Inline,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,LinkMatch>: linkOf(inlineExecAt(rules,Rules.InlineLink{},first,src))

# A reference that names no definition is its first character as text.
type RefStep is Data:
  RefText{raw: String}
  RefLink{link: LinkMatch}
def definitionFor(links: List<&2,T.LinkDefinition>,+label: String) -> Maybe<&2,T.LinkDefinition>:
  match links:
    case Nil{}: None{}
    case T.LinkDefinition{+name,+href,+title} <> rest: Bool.pick(Unit -> Maybe<&2,T.LinkDefinition>,String.eq(name,label),_ => Some{T.LinkDefinition{name,href,title}},_ => definitionFor(rest,label))(Unit{})
def hasDefinition(links: List<&2,T.LinkDefinition>,+label: String) -> Bool:
  match links:
    case Nil{}: False{}
    case T.LinkDefinition{+name,_,_} <> rest: Bool.pick(Unit -> Bool,String.eq(name,label),_ => True{},_ => hasDefinition(rest,label))(Unit{})
def refFound(entry: Maybe<&2,T.LinkDefinition>,+raw: String,label: String) -> RefStep:
  match entry:
    case None{}: RefText{String.take(raw,1n)}
    case Some{T.LinkDefinition{_,href,title}}: RefLink{LinkMatch{raw,href,nonEmpty(Maybe.default(&2,String,title,"")),label,H.startsWithChar(raw,'!')}}
def reflinkOf(links: List<&2,T.LinkDefinition>,found: Maybe<&2,Cap>) -> Maybe<&2,RefStep>:
  match found:
    case Some{+value}:
      +name = Bool.pick(String,truthy(capGroup(value,2n)),capText(value,2n),capText(value,1n))
      Some{refFound(definitionFor(links,CaseMap.lower(collapseSpace(name))),capWhole(value),capText(value,1n))}
    case None{}: None{}
# reflink(src, links): `reflink` or else `nolink`.
def nolinkUnless(found: Maybe<&2,Cap>,+rules: Rules.Inline,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,Cap>:
  match found:
    case Some{value}: Some{value}
    case None{}: inlineExecAt(rules,Rules.InlineNolink{},first,src)
def reflink(+rules: Rules.Inline,links: List<&2,T.LinkDefinition>,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,RefStep>:
  reflinkOf(links,nolinkUnless(inlineExecAt(rules,Rules.InlineReflink{},first,src),rules,first,src))

# other.outputLinkReplace, `/\\([\[\]])/g` → "$1".
def bracketsScan(text: String,+pending: Bool,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(Bool.pick(String,pending,SCon{'\\',reversed},reversed))
    case SCon{+char,+rest}:
      Bool.pick(Unit -> String,pending,
        _ => Bool.pick(Unit -> String,Char.is_eq(char,'[') || Char.is_eq(char,']'),_ => bracketsScan(rest,False{},SCon{char,reversed}),
          _ => bracketsScan(rest,Char.is_eq(char,'\\'),Bool.pick(String,Char.is_eq(char,'\\'),SCon{'\\',reversed},SCon{char,SCon{'\\',reversed}})))(Unit{}),
        _ => Bool.pick(Unit -> String,Char.is_eq(char,'\\'),_ => bracketsScan(rest,True{},reversed),_ => bracketsScan(rest,False{},SCon{char,reversed}))(Unit{}))(Unit{})
def outputLinkText(text: String) -> String: bracketsScan(text,False{},"")

# Masking
# -------
# inlineTokens scans emphasis and strikethrough delimiters in a copy of the
# source where reference links, escaped punctuation, links, code spans and
# tags are masked, keeping every length.

def searchOn(+search: Rules.Search,+input: List<&2,U32>,+cursor: Re.Cursor) -> Maybe<&2,Re.Found>:
  match search: case Rules.Search{regex,start}: Re.search(regex,start,input,cursor)
# All non-overlapping matches (String#matchAll).
def matchesFrom(+fuel: Nat,+search: Rules.Search,+input: List<&2,U32>,+found: Maybe<&2,Re.Found>,+reversed: List<&2,Re.Match>) -> List<&2,Re.Match>:
  match fuel found:
    case _ None{}: List.reverse(&2,Re.Match,reversed)
    case Zero{} _: List.reverse(&2,Re.Match,reversed)
    case Succ{more} Some{Re.Found{Re.Match{+start,+end,captures},+cursor}}:
      matchesFrom(more,search,input,searchOn(search,input,Bool.pick(Unit -> Re.Cursor,Nat.is_eq(start,end),_ => Maybe.default(&2,Re.Cursor,Re.advance(cursor),cursor),_ => cursor)(Unit{})),Re.Match{start,end,captures} <> reversed)
def allMatches(+search: Rules.Search,+input: List<&2,U32>) -> List<&2,Re.Match>:
  matchesFrom(List.length(&2,U32,input) + 1n,search,input,searchOn(search,input,Re.cursorAt(input)),Nil{})
def matchStart(+found: Re.Match) -> Nat:
  match found: case Re.Match{start,_,_}: start
def matchCodes(+input: List<&2,U32>,+found: Re.Match) -> List<&2,U32>:
  match found: case Re.Match{start,end,_}: take(drop(input,start),end - start)
def containsCode(+codes: List<&2,U32>,+scalar: U32) -> Bool:
  match codes:
    case Nil{}: False{}
    case +first <> rest: Bool.pick(Unit -> Bool,U32.is_eq(first,scalar),_ => True{},_ => containsCode(rest,scalar))(Unit{})
def lastIndexFrom(+codes: List<&2,U32>,+scalar: U32,+index: Nat,+found: Nat) -> Nat:
  match codes:
    case Nil{}: found
    case +first <> rest: lastIndexFrom(rest,scalar,index + 1n,Bool.pick(Nat,U32.is_eq(first,scalar),index,found))
# `lastIndexOf("[")` in a match that contains one.
def lastBracket(+codes: List<&2,U32>) -> Nat: lastIndexFrom(codes,91,0n,0n)
def repeatA(+count: Nat,+codes: List<&2,U32>) -> List<&2,U32>:
  match count:
    case Zero{}: codes
    case Succ{more}: repeatA(more,97 <> codes)
# "[" + "a" repeated + "]" over `length` scalars.
def bracketMask(+length: Nat) -> List<&2,U32>: 91 <> repeatA(length - 2n,[93])
# Whether a link (not an image) sits among a text's links, code spans and
# tags.
def linkSpan(+rules: Rules.Inline,+text: List<&2,U32>,matches: List<&2,Re.Match>) -> Bool:
  match matches:
    case Nil{}: False{}
    case +found <> rest:
      Bool.pick(Unit -> Bool,Maybe.is_some(&2,Cap,inlineExec(rules,Rules.InlineLink{},matchCodes(text,found))) && Bool.not(U32.is_eq(Maybe.default(&2,U32,List.get(&2,U32,text,matchStart(found) - 1n),0),33) && Nat.is_gt(matchStart(found),0n)),
        _ => True{},_ => linkSpan(rules,text,rest))(Unit{})
def keyOf(+codes: List<&2,U32>,+refStart: Nat) -> String: slice(codes,refStart + 1n,List.length(&2,U32,codes) - 1n)
# linkInText's reference part: a reference to a definition whose text holds
# no link is a link.
@unsafe def linkInRefs(+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+text: List<&2,U32>,+matches: List<&2,Re.Match>) -> Bool:
  match matches:
    case Nil{}: False{}
    case +found <> rest:
      +codes = matchCodes(text,found)
      +refStart = lastBracket(codes)
      +inner = drop(take(codes,refStart - 1n),1n)
      Bool.pick(Unit -> Bool,startsWith(codes,'!') || Bool.not(hasDefinition(links,keyOf(codes,refStart))),_ => linkInRefs(rules,links,text,rest),
        _ => Bool.pick(Unit -> Bool,Nat.is_gt(refStart,1n) && containsCode(inner,91) && (linkSpan(rules,inner,allMatches(Rules.inlineSearch(rules,Rules.InlineBlockSkip{}),inner)) || linkInRefs(rules,links,inner,allMatches(Rules.inlineSearch(rules,Rules.InlineReflinkSearch{}),inner))),
          _ => linkInRefs(rules,links,text,rest),_ => True{})(Unit{}))(Unit{})
# linkInText(text): does this link text hold a link already?
def linkInText(+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+text: List<&2,U32>) -> Bool:
  containsCode(text,91) && (linkSpan(rules,text,allMatches(Rules.inlineSearch(rules,Rules.InlineBlockSkip{}),text)) || linkInRefs(rules,links,text,allMatches(Rules.inlineSearch(rules,Rules.InlineReflinkSearch{}),text)))
def prependReversed(+codes: List<&2,U32>,+reversed: List<&2,U32>) -> List<&2,U32>:
  match codes:
    case Nil{}: reversed
    case scalar <> rest: prependReversed(rest,scalar <> reversed)
# Reference links to definitions are masked; a candidate whose text holds a
# link keeps its text, with the references in it masked.
@unsafe def maskedRefs(+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+input: List<&2,U32>,+matches: List<&2,Re.Match>,+position: Nat,+reversed: List<&2,U32>) -> List<&2,U32>:
  match matches:
    case Nil{}: List.reverse(&2,U32,prependReversed(drop(input,position),reversed))
    case Re.Match{+start,+end,_} <> rest:
      +codes = take(drop(input,start),end - start)
      +length = end - start
      +refStart = lastBracket(codes)
      +text = drop(take(codes,refStart - 1n),1n)
      +before = prependReversed(take(drop(input,position),start - position),reversed)
      Bool.pick(Unit -> List<&2,U32>,Bool.not(hasDefinition(links,keyOf(codes,refStart))),_ => maskedRefs(rules,links,input,rest,end,prependReversed(codes,before)),
        _ => Bool.pick(Unit -> List<&2,U32>,Nat.is_gt(refStart,1n) && Bool.not(startsWith(codes,'!')) && linkInText(rules,links,text),
          _ => maskedRefs(rules,links,input,rest,end,prependReversed(93 <> repeatA(length - refStart - 2n,[93]),prependReversed(91 <> 93 <> Nil{},prependReversed(maskedRefs(rules,links,text,allMatches(Rules.inlineSearch(rules,Rules.InlineReflinkSearch{}),text),0n,Nil{}),91 <> before)))),
          _ => maskedRefs(rules,links,input,rest,end,prependReversed(bracketMask(length),before)))(Unit{}))(Unit{})
# anyPunctuation, `/\\([\p{P}\p{S}])/gu` → "++". `step` is 1 where such
# an escape starts, 2 at its escaped character and 0 elsewhere.
def escapeAt(codes: List<&2,U32>) -> Bool:
  match codes:
    case 92 <> +scalar <> _: H.isPunctuationOrSymbol(scalar)
    case _: False{}
def nextStep(+step: U32,rest: List<&2,U32>) -> U32:
  match step:
    case 1: 2
    case _: Bool.pick(U32,escapeAt(rest),1,0)
def punctuationMasked(codes: List<&2,U32>,+step: U32,+reversed: List<&2,U32>) -> List<&2,U32>:
  match codes:
    case Nil{}: List.reverse(&2,U32,reversed)
    case +scalar <> +rest: punctuationMasked(rest,nextStep(step,rest),Bool.pick(U32,U32.is_eq(step,0),scalar,43) <> reversed)
def bracketsMasked(+input: List<&2,U32>,+matches: List<&2,Re.Match>,+position: Nat,+reversed: List<&2,U32>) -> List<&2,U32>:
  match matches:
    case Nil{}: List.reverse(&2,U32,prependReversed(drop(input,position),reversed))
    case Re.Match{+start,+end,_} <> rest: bracketsMasked(input,rest,end,prependReversed(bracketMask(end - start),prependReversed(take(drop(input,position),start - position),reversed)))
def blocksMasked(+rules: Rules.Inline,+input: List<&2,U32>) -> List<&2,U32>: bracketsMasked(input,allMatches(Rules.inlineSearch(rules,Rules.InlineBlockSkip{}),input),0n,Nil{})
# Reference links are masked only when the document defines some (as
# upstream, which searches for them only then).
def referencesMasked(search: Bool,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+src: List<&2,U32>) -> List<&2,U32>:
  match search:
    case True{}: maskedRefs(rules,links,src,allMatches(Rules.inlineSearch(rules,Rules.InlineReflinkSearch{}),src),0n,Nil{})
    case False{}: src
def maskedSource(+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+src: List<&2,U32>) -> List<&2,U32>:
  +references = referencesMasked(Bool.not(List.is_empty(&2,T.LinkDefinition,links)) && containsCode(src,91),rules,links,src)
  blocksMasked(rules,punctuationMasked(references,Bool.pick(U32,escapeAt(references),1,0),Nil{}))

# The masked source of an inlineTokens run, computed when a delimiter scan
# first reads it (most runs have no emphasis or strikethrough to scan): until
# then the run's source from its start, the reference definitions and how
# far the run has advanced. Lengths are kept, so the masked source there is
# the whole masked source without its first `offset` scalars.
type Masking is Data:
  Unmasked{source: List<&2,U32>,links: List<&2,T.LinkDefinition>,offset: Nat}
  Masked{codes: List<&2,U32>}
def maskedCodes(+rules: Rules.Inline,masking: Masking) -> List<&2,U32>:
  match masking:
    case Unmasked{source,links,offset}: drop(maskedSource(rules,links,source),offset)
    case Masked{codes}: codes
# The masking after a token of `length` scalars.
def maskingAdvanced(masking: Masking,+length: Nat) -> Masking:
  match masking:
    case Unmasked{source,links,offset}: Unmasked{source,links,offset + length}
    case Masked{codes}: Masked{drop(codes,length)}
# Whether an emStrong opener may start `src`.
def opensEmphasis(+rules: Rules.Inline,first: Maybe<&2,U32>) -> Bool: Rules.inlineOpens(rules,Rules.InlineEmStrongLDelim{},first)
# The masking with its source computed when `needed`.
def maskingFor(+rules: Rules.Inline,needed: Bool,masking: Masking) -> Masking:
  match needed:
    case True{}: Masked{maskedCodes(rules,masking)}
    case False{}: masking

# Emphasis and strikethrough
# --------------------------
# The previous character is JavaScript's `raw.slice(-1)`: one UTF-16 code
# unit, so after an astral character it is a lone surrogate (neither
# punctuation nor alphanumeric), represented by U+DC00.

type Emphasis is Data: Emphasis{strong: Bool,raw: String,text: String}
type Delimited is Data: Delimited{raw: String,text: String}
def previousOf(+scalar: U32) -> U32: Bool.pick(U32,U32.is_ge(scalar,65536),56320,scalar)
# other.unicodeAlphaNumeric, `/[\p{L}\p{N}]/u`.
def alphaNumeric(previous: Maybe<&2,U32>) -> Bool:
  match previous:
    case Some{+scalar}: Category.isLetter(scalar) || Category.isNumber(scalar)
    case None{}: False{}
# inline.punctuation, `/^((?![*_])[\s\p{P}\p{S}])/u`.
def punctuation(previous: Maybe<&2,U32>) -> Bool:
  match previous:
    case Some{+scalar}: Bool.not(U32.is_eq(scalar,42) || U32.is_eq(scalar,95)) && (Re.isSpaceCode(scalar) || H.isPunctuationOrSymbol(scalar))
    case None{}: False{}
def spanLength(span: Maybe<&2,Re.Span>) -> Nat:
  match span:
    case Some{Re.Span{start,end}}: end - start
    case None{}: 0n
def firstSpan(spans: List<&2,Maybe<&2,Re.Span>>) -> Maybe<&2,Re.Span>:
  match spans:
    case Nil{}: None{}
    case Some{span} <> _: Some{span}
    case None{} <> rest: firstSpan(rest)
def isSomeSpan(value: Maybe<&2,Maybe<&2,Re.Span>>) -> Bool:
  match value:
    case Some{Some{_}}: True{}
    case _: False{}
def spanIn(spans: List<&2,Maybe<&2,Re.Span>>,index: Nat) -> Bool: isSomeSpan(List.get(&2,Maybe<&2,Re.Span>,spans,index))

# The closing-delimiter scan of emStrong and del over the masked source
# after the opening run: `delimTotal`, `midDelimTotal` and the next match.
type Scan is Data:
  Scanning{delimTotal: Nat,middle: Nat,found: Maybe<&2,Re.Found>}
  Finished{result: Maybe<&2,Emphasis>}
# What stays fixed during a scan: the source, the opening run's length,
# whether it is a mid-run opener, whether this is strikethrough (which only
# pairs runs of the opening's length), the closing expression and the input.
type Opener is Data: Opener{src: List<&2,U32>,length: Nat,midRun: Bool,strike: Bool,closing: Rules.Search,input: List<&2,U32>}
def resumed(opener: Opener,+delimTotal: Nat,+middle: Nat,cursor: Re.Cursor) -> Scan:
  match opener:
    case Opener{_,_,_,_,Rules.Search{regex,start},input}: Scanning{delimTotal,middle,Re.search(regex,start,input,cursor)}
# A closing run of `size` delimiters found at `index` ends the span.
def closed(opener: Opener,+index: Nat,+size: Nat) -> Scan:
  match opener:
    case Opener{+src,+length,_,strike,_,_}:
      +raw = slice(src,0n,length + index + 1n + size)
      Finished{Some{Bool.pick(Unit -> Emphasis,strike,_ => Emphasis{False{},raw,H.inner(raw,length,length)},
        _ => Bool.pick(Unit -> Emphasis,Nat.is_eq(Nat.mod(Nat.min(length,size),2n),1n),_ => Emphasis{False{},raw,H.inner(raw,1n,1n)},_ => Emphasis{True{},raw,H.inner(raw,2n,2n)})(Unit{}))(Unit{})}}
def opensMore(+spans: List<&2,Maybe<&2,Re.Span>>) -> Bool: spanIn(spans,2n) || spanIn(spans,3n)
def eitherWay(+spans: List<&2,Maybe<&2,Re.Span>>) -> Bool: spanIn(spans,4n) || spanIn(spans,5n)
def openerLength(opener: Opener) -> Nat:
  match opener: case Opener{_,length,_,_,_,_}: length
def openerStrike(opener: Opener) -> Bool:
  match opener: case Opener{_,_,_,strike,_,_}: strike
def openerMidRun(opener: Opener) -> Bool:
  match opener: case Opener{_,_,midRun,_,_,_}: midRun
# One closing-expression match (emStrong's and del's loop bodies).
def delimiterStep(+opener: Opener,+delimTotal: Nat,+middle: Nat,found: Re.Found) -> Scan:
  match found:
    case Re.Found{Re.Match{index,_,+spans},+cursor}:
      +run = firstSpan(spans)
      +size = spanLength(run)
      +length = openerLength(opener)
      Bool.pick(Unit -> Scan,Maybe.is_none(&2,Re.Span,run) || (openerStrike(opener) && Bool.not(Nat.is_eq(size,length))),_ => resumed(opener,delimTotal,middle,cursor),
        _ => Bool.pick(Unit -> Scan,opensMore(spans),_ => resumed(opener,delimTotal + size,middle,cursor),
        _ => Bool.pick(Unit -> Scan,Bool.not(openerStrike(opener)) && eitherWay(spans) && Bool.not(Nat.is_eq(Nat.mod(length,3n),0n)) && Nat.is_eq(Nat.mod(length + size,3n),0n),_ => resumed(opener,delimTotal,middle + size,cursor),
        _ => Bool.pick(Unit -> Scan,Bool.not(openerStrike(opener)) && eitherWay(spans) && openerMidRun(opener),_ => Finished{None{}},
        _ => Bool.pick(Unit -> Scan,Nat.is_gt(delimTotal,size),_ => resumed(opener,delimTotal - size,middle,cursor),
        _ => closed(opener,index,Nat.min(size,delimTotal + middle)))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def scanned(fuel: Nat,+opener: Opener,scan: Scan) -> Maybe<&2,Emphasis>:
  match fuel scan:
    case _ Finished{result}: result
    case _ Scanning{_,_,None{}}: None{}
    case Zero{} _: None{}
    case Succ{more} Scanning{delimTotal,middle,Some{found}}: scanned(more,opener,delimiterStep(opener,delimTotal,middle,found))
def scanFrom(+opener: Opener) -> Maybe<&2,Emphasis>:
  match opener:
    case Opener{_,+length,_,_,Rules.Search{regex,start},+input}: scanned(List.length(&2,U32,input) + 1n,opener,Scanning{length,0n,Re.search(regex,start,input,Re.cursorAt(input))})

def emStrongOpened(+rules: Rules.Inline,+src: List<&2,U32>,+masked: Masking,+previous: Maybe<&2,U32>,+value: Cap) -> Maybe<&2,Emphasis>:
  +run = capWhole(value)
  +length = String.length(run) - 1n
  +asterisk = H.startsWithChar(run,'*')
  +next = truthy(capGroup(value,1n)) || truthy(capGroup(value,3n))
  Bool.pick(Unit -> Maybe<&2,Emphasis>,Bool.not(truthy(capGroup(value,1n)) || truthy(capGroup(value,2n)) || truthy(capGroup(value,3n)) || truthy(capGroup(value,4n))) || (truthy(capGroup(value,4n)) && alphaNumeric(previous)),_ => None{},
    _ => Bool.pick(Unit -> Maybe<&2,Emphasis>,Bool.not(next) || Maybe.is_none(&2,U32,previous) || punctuation(previous),
      _ => scanFrom(Opener{src,length,Maybe.default(&2,Bool,Maybe.map(&2,U32,Bool,scalar => U32.is_eq(scalar,Bool.pick(U32,asterisk,42,95)),previous),False{}),False{},Rules.inlineSearch(rules,Bool.pick(Rules.InlineRule,asterisk,Rules.InlineEmStrongRDelimAst{},Rules.InlineEmStrongRDelimUnd{})),drop(maskedCodes(rules,masked),length)}),
      _ => None{})(Unit{}))(Unit{})
def emStrongOf(+rules: Rules.Inline,+src: List<&2,U32>,+masked: Masking,+previous: Maybe<&2,U32>,found: Maybe<&2,Cap>) -> Maybe<&2,Emphasis>:
  match found:
    case Some{value}: emStrongOpened(rules,src,masked,previous,value)
    case None{}: None{}
# emStrong(src, maskedSrc, prevChar): an em or strong span, before its text
# is lexed.
def emStrong(+rules: Rules.Inline,+first: Maybe<&2,U32>,+src: List<&2,U32>,+masked: Masking,+previous: Maybe<&2,U32>) -> Maybe<&2,Emphasis>:
  emStrongOf(rules,src,masked,previous,inlineExecAt(rules,Rules.InlineEmStrongLDelim{},first,src))

def delimited(value: Maybe<&2,Emphasis>) -> Maybe<&2,Delimited>:
  match value:
    case Some{Emphasis{_,raw,text}}: Some{Delimited{raw,text}}
    case None{}: None{}
def delOpened(+rules: Rules.Inline,+src: List<&2,U32>,+masked: Masking,+previous: Maybe<&2,U32>,+value: Cap) -> Maybe<&2,Delimited>:
  +length = String.length(capWhole(value)) - 1n
  Bool.pick(Unit -> Maybe<&2,Delimited>,Bool.not(truthy(capGroup(value,1n))) || Maybe.is_none(&2,U32,previous) || punctuation(previous),
    _ => delimited(scanFrom(Opener{src,length,False{},True{},Rules.inlineSearch(rules,Rules.InlineDelRDelim{}),drop(maskedCodes(rules,masked),length)})),_ => None{})(Unit{})
def delOf(+rules: Rules.Inline,+src: List<&2,U32>,+masked: Masking,+previous: Maybe<&2,U32>,found: Maybe<&2,Cap>) -> Maybe<&2,Delimited>:
  match found:
    case Some{value}: delOpened(rules,src,masked,previous,value)
    case None{}: None{}
# marked's del(src, maskedSrc, prevChar): a `~` or `~~` span before its text
# is lexed.
def del(+rules: Rules.Inline,+src: List<&2,U32>,+masked: Masking,+previous: Maybe<&2,U32>) -> Maybe<&2,Delimited>:
  delOf(rules,src,masked,previous,inlineExec(rules,Rules.InlineDelLDelim{},src))

# Other inline tokens
# -------------------

# Code spans: newlines read as spaces; one space goes from each end when both
# have one and the text is not only spaces.
def codespanText(+text: String) -> String:
  Bool.pick(Unit -> String,Maybe.is_some(&2,Nat,nonSpace(text)) && H.startsWithChar(text,' ') && H.endsWithChar(text,' '),_ => H.inner(text,1n,1n),_ => text)(Unit{})
def codespanOf(-X: Data,found: Maybe<&2,Cap>) -> Maybe<&2,T.Token<X>>:
  match found:
    case Some{+value}: Some{T.Codespan{capWhole(value),codespanText(Strings.replaceAll(capText(value,2n),"\n"," "))}}
    case None{}: None{}
def codespan(-X: Data,+rules: Rules.Inline,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,T.Token<X>>: codespanOf(X,inlineExecAt(rules,Rules.InlineCode{},first,src))

def brOf(-X: Data,found: Maybe<&2,Cap>) -> Maybe<&2,T.Token<X>>:
  match found:
    case Some{value}: Some{T.Br{capWhole(value)}}
    case None{}: None{}
def br(-X: Data,+rules: Rules.Inline,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,T.Token<X>>: brOf(X,inlineExecAt(rules,Rules.InlineBr{},first,src))

def isAt(value: Maybe<&2,String>) -> Bool:
  match value:
    case Some{text}: String.eq(text,"@")
    case None{}: False{}
def autolinked(-X: Data,+raw: String,+text: String,+href: String) -> T.Token<X>: T.Link{raw,href,None{},text,[T.Text{text,text,Nil{},False{}}]}
def autolinkOf(-X: Data,found: Maybe<&2,Cap>) -> Maybe<&2,T.Token<X>>:
  match found:
    case Some{+value}:
      +text = capText(value,1n)
      Some{autolinked(X,capWhole(value),text,Bool.pick(String,isAt(capGroup(value,2n)),"mailto:" ++ text,text))}
    case None{}: None{}
def autolink(-X: Data,+rules: Rules.Inline,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,T.Token<X>>: autolinkOf(X,inlineExecAt(rules,Rules.InlineAutolink{},first,src))

# `cap[0] = _backpedal.exec(cap[0])?.[0] ?? ""` until it no longer changes.
def foundText(codes: List<&2,U32>,found: Re.Found) -> String:
  match found: case Re.Found{Re.Match{start,end,_},_}: slice(codes,start,end)
def backpedalOnce(+search: Rules.Search,+text: String) -> String:
  match search:
    case Rules.Search{regex,start}:
      +codes = Re.codes(text)
      Maybe.default(&2,String,Maybe.map(&2,Re.Found,String,found => foundText(codes,found),Re.search(regex,start,codes,Re.cursorAt(codes))),"")
def backpedaled(fuel: Nat,+search: Rules.Search,+text: String,+next: String) -> String:
  match fuel:
    case Zero{}: next
    case Succ{more}: Bool.pick(Unit -> String,String.eq(text,next),_ => next,_ => backpedaled(more,search,next,backpedalOnce(search,next)))(Unit{})
def urlBacked(-X: Data,+text: String,www: Bool) -> Maybe<&2,T.Token<X>>: Some{autolinked(X,text,text,Bool.pick(String,www,"http://" ++ text,text))}
def urlOf(-X: Data,+rules: Rules.Inline,found: Maybe<&2,Cap>) -> Maybe<&2,T.Token<X>>:
  match found:
    case Some{+value}:
      +raw = capWhole(value)
      Bool.pick(Unit -> Maybe<&2,T.Token<X>>,isAt(capGroup(value,2n)),_ => Some{autolinked(X,raw,raw,"mailto:" ++ raw)},
        _ => urlBacked(X,backpedaled(String.length(raw) + 1n,Rules.inlineSearch(rules,Rules.InlineBackpedal{}),raw,backpedalOnce(Rules.inlineSearch(rules,Rules.InlineBackpedal{}),raw)),String.eq(capText(value,1n),"www.")))(Unit{})
    case None{}: None{}
def url(-X: Data,+rules: Rules.Inline,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,T.Token<X>>: urlOf(X,rules,inlineExecAt(rules,Rules.InlineUrl{},first,src))

# The text run
# ------------
# GFM's inline `text` rule is the lexer's hottest expression: every run of
# plain text is scanned with it, trying several lookaheads per character.
# Without `breaks` it is matched by the function below, which follows the
# expression step by step (tests/marked_lexer_check.py compares it with the
# expression on its inputs):
#
#   ^(`+|~+|[^`~])(?:(?=[`~])|(?= {2,}\n)|(?=EMAIL+@)|[\s\S]*?(?:(?=STOP|$)
#     |[^ ](?= {2,}\n)|[^EMAIL](?=EMAIL+@)))
#
# with EMAIL = [a-zA-Z0-9.!#$%&'*+\/=?_`{\|}~-] and STOP = [\\<!\[`*~_]|\b_
# |[hH][tT][tT][pP][sS]?|[fF][tT][pP]:\/\/|www\. (the protocol alternative
# stops at any "http", as the expression reads).
def emailPunctuation(scalar: U32) -> Bool:
  match scalar:
    case 33: True{}
    case 35: True{}
    case 36: True{}
    case 37: True{}
    case 38: True{}
    case 39: True{}
    case 42: True{}
    case 43: True{}
    case 45: True{}
    case 46: True{}
    case 47: True{}
    case 61: True{}
    case 63: True{}
    case 95: True{}
    case 96: True{}
    case 123: True{}
    case 124: True{}
    case 125: True{}
    case 126: True{}
    case _: False{}
def isEmailCode(+scalar: U32) -> Bool:
  (U32.is_ge(scalar,97) && U32.is_le(scalar,122)) || (U32.is_ge(scalar,65) && U32.is_le(scalar,90)) || (U32.is_ge(scalar,48) && U32.is_le(scalar,57)) || emailPunctuation(scalar)
# `(?=EMAIL+@)` (`email`: the next scalar is an EMAIL one; `count` of them read).
def headEmail(codes: List<&2,U32>) -> Bool:
  match codes:
    case +scalar <> _: isEmailCode(scalar)
    case Nil{}: False{}
def emailAhead(codes: List<&2,U32>,email: Bool,+count: Nat) -> Bool:
  match email codes:
    case True{} _ <> +rest: emailAhead(rest,headEmail(rest),count + 1n)
    case False{} 64 <> _: Nat.is_gt(count,0n)
    case _ _: False{}
# `(?= {2,}\n)`
def breakAhead(codes: List<&2,U32>,+count: Nat) -> Bool:
  match codes:
    case 32 <> rest: breakAhead(rest,count + 1n)
    case 10 <> _: Nat.is_ge(count,2n)
    case _: False{}
# STOP at the start of `codes`: `[\\<!\[`*~_]`, "http" and "ftp://" in either
# case, or "www." (read as patterns, so the source is not taken).
def pAhead(codes: List<&2,U32>) -> Bool:
  match codes:
    case 112 <> _: True{}
    case 80 <> _: True{}
    case _: False{}
def tpAhead(codes: List<&2,U32>) -> Bool:
  match codes:
    case 116 <> rest: pAhead(rest)
    case 84 <> rest: pAhead(rest)
    case _: False{}
def ttpAhead(codes: List<&2,U32>) -> Bool:
  match codes:
    case 116 <> rest: tpAhead(rest)
    case 84 <> rest: tpAhead(rest)
    case _: False{}
def slashesAhead(codes: List<&2,U32>) -> Bool:
  match codes:
    case 58 <> 47 <> 47 <> _: True{}
    case _: False{}
def ftpAhead(codes: List<&2,U32>) -> Bool:
  match codes:
    case 116 <> 112 <> rest: slashesAhead(rest)
    case 116 <> 80 <> rest: slashesAhead(rest)
    case 84 <> 112 <> rest: slashesAhead(rest)
    case 84 <> 80 <> rest: slashesAhead(rest)
    case _: False{}
def stopAhead(codes: List<&2,U32>) -> Bool:
  match codes:
    case 92 <> _: True{}
    case 60 <> _: True{}
    case 33 <> _: True{}
    case 91 <> _: True{}
    case 96 <> _: True{}
    case 42 <> _: True{}
    case 126 <> _: True{}
    case 95 <> _: True{}
    case 104 <> rest: ttpAhead(rest)
    case 72 <> rest: ttpAhead(rest)
    case 102 <> rest: ftpAhead(rest)
    case 70 <> rest: ftpAhead(rest)
    case 119 <> 119 <> 119 <> 46 <> _: True{}
    case _: False{}
# `[^ ](?= {2,}\n)` and `[^EMAIL](?=EMAIL+@)` at a character.
def breakAfter(+scalar: U32,rest: List<&2,U32>) -> Bool: Bool.not(U32.is_eq(scalar,32)) && breakAhead(rest,0n)
def emailAfterIf(email: Bool,+rest: List<&2,U32>) -> Bool:
  match email:
    case True{}: False{}
    case False{}: emailAhead(rest,headEmail(rest),0n)
def emailAfter(+scalar: U32,+rest: List<&2,U32>) -> Bool: emailAfterIf(isEmailCode(scalar),rest)
# `[\s\S]*?(?:(?=STOP|$)|[^ ](?= {2,}\n)|[^EMAIL](?=EMAIL+@))`: the length
# of the lazy run and the alternative's character. `action` is what the run
# does at the next scalar: 1 stop before it, 2 take it and stop, 0 take it
# and go on.
def afterAction(stop: Bool,+scalar: U32,+rest: List<&2,U32>) -> U32:
  match stop:
    case True{}: 1
    case False{}: Bool.pick(U32,breakAfter(scalar,rest) || emailAfter(scalar,rest),2,0)
def textAction(+codes: List<&2,U32>) -> U32:
  match codes:
    case Nil{}: 1
    case +scalar <> +rest: afterAction(stopAhead(codes),scalar,rest)
def textRun(codes: List<&2,U32>,action: U32,+length: Nat) -> Nat:
  match action codes:
    case 1 _: length
    case 2 _: length + 1n
    case _ Nil{}: length
    case _ _ <> +rest: textRun(rest,textAction(rest),length + 1n)
def runOf(codes: List<&2,U32>,+scalar: U32,+count: Nat) -> Nat:
  match codes:
    case +next <> rest: Bool.pick(Unit -> Nat,U32.is_eq(next,scalar),_ => runOf(rest,scalar,count + 1n),_ => count)(Unit{})
    case Nil{}: count
# `(`+|~+|[^`~])` then the rest.
def textAfterIf(stop: Bool,+first: Nat,+rest: List<&2,U32>) -> Nat:
  match stop:
    case True{}: first
    case False{}: first + textRun(rest,textAction(rest),0n)
def textAfter(+first: Nat,+rest: List<&2,U32>) -> Nat:
  textAfterIf(startsWith(rest,'`') || startsWith(rest,'~') || breakAhead(rest,0n) || emailAhead(rest,headEmail(rest),0n),first,rest)
def textLength(+src: List<&2,U32>) -> Maybe<&2,Nat>:
  match src:
    case Nil{}: None{}
    case +scalar <> _:
      +first = Bool.pick(Nat,U32.is_eq(scalar,96) || U32.is_eq(scalar,126),runOf(src,scalar,0n),1n)
      Some{textAfter(first,drop(src,first))}
def textOfLength(+src: List<&2,U32>,length: Maybe<&2,Nat>) -> Maybe<&2,String>:
  match length:
    case Some{+count}: Some{slice(src,0n,count)}
    case None{}: None{}
# The text run; the lexer merges it into a preceding text token.
def textWith(breaks: Bool,+rules: Rules.Inline,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,String>:
  match breaks:
    case True{}: wholeOf(inlineExecAt(rules,Rules.InlineText{},first,src))
    case False{}: textOfLength(src,textLength(src))
def inlineText(+rules: Rules.Inline,+first: Maybe<&2,U32>,+src: List<&2,U32>) -> Maybe<&2,String>: textWith(Rules.inlineBreaks(rules),rules,first,src)
