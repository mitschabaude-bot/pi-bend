import Base
import ../../runtime/src/case-fold.bend as Fold
import ../../runtime/src/grapheme.bend as Grapheme
import ../../runtime/src/text.bend as Text
import ./utils.bend as Utils
import ./tui.bend as Tui

# Search rendered transcript text, then map each match back to visible columns.
# ASCII runs share one span; graphemes with nontrivial display widths have their
# own spans. The index is immutable and reuses its corpus until lines change.
type Segment is Data: Segment{row: Nat,startCol: Nat,endCol: Nat}
type Styles is Data: Styles{foreground: String,background: String}
type Match is Data: Match{segments: List<&2,Segment>}
type Span is Data: Span{start: Nat,end: Nat,row: Nat,startCol: Nat,endCol: Nat,linear: Bool}
type Corpus is Data: Corpus{text: String,spans: List<&2,Span>}
type Building is Data: Building{chunks: List<&2,String>,spans: List<&2,Span>,length: Nat,pending: Bool}
type Index is Data: Index{source: Maybe<&2,List<&2,String>>,corpus: Maybe<&2,Corpus>,query: Maybe<&2,String>,matches: List<&2,Match>}
type SearchResult is Data: SearchResult{matches: List<&2,Match>,changed: Bool}

def empty() -> Building: Building{Nil{},Nil{},0n,False{}}
def index() -> Index: Index{None{},None{},None{},Nil{}}
def separator(builder: Building) -> Building:
  match builder:
    case Building{chunks,spans,length,False{}}: Building{chunks,spans,length,False{}}
    case Building{chunks,spans,length,True{}}: Building{" " <> chunks,spans,length + 1n,False{}}
def pending(builder: Building) -> Building:
  match builder:
    case Building{chunks,spans,0n,_}: Building{chunks,spans,0n,False{}}
    case Building{chunks,spans,length,_}: Building{chunks,spans,length,True{}}
def appendSeparated(builder: Building,+text: String,row: Nat,startCol: Nat,endCol: Nat,linear: Bool) -> Building:
  match builder:
    case Building{chunks,spans,+length,_}:
      +end = length + String.length(text)
      Building{text <> chunks,Span{length,end,row,startCol,endCol,linear} <> spans,end,False{}}
def append(builder: Building,text: String,row: Nat,startCol: Nat,endCol: Nat,linear: Bool) -> Building:
  appendSeparated(separator(builder),text,row,startCol,endCol,linear)
def flushed(reversed: String,row: Nat,startCol: Nat,endCol: Nat,builder: Building) -> Building:
  match reversed:
    case SNil{}: builder
    case _: append(builder,String.reverse(reversed),row,startCol,endCol,True{})
def ascii(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{char,rest}:
      +code = Char.to_u32(char)
      U32.is_ge(code,32) && U32.is_le(code,126) && ascii(rest)
def scanAscii(text: String,+row: Nat,+column: Nat,+reversed: String,startCol: Nat,builder: Building) -> Building:
  match text:
    case SNil{}: flushed(reversed,row,startCol,column,builder)
    case SCon{' ',rest}:
      +next = pending(flushed(reversed,row,startCol,column,builder))
      scanAscii(rest,row,column + 1n,"",column + 1n,next)
    case SCon{char,rest}:
      +start = Bool.pick(Nat,String.is_empty(reversed),column,startCol)
      scanAscii(rest,row,column + 1n,SCon{char,reversed},start,builder)
def whitespace(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{char,rest}: Text.whitespace(Char.to_u32(char)) && whitespace(rest)
def scanGraphemeChoice(isSpace: Bool,segment: String,row: Nat,+column: Nat,width: Nat,builder: Building) -> Building:
  match isSpace:
    case True{}: pending(builder)
    case False{}: append(builder,segment,row,column,column + width,False{})
def scanGrapheme(+segment: String,row: Nat,column: Nat,width: Nat,builder: Building) -> Building:
  scanGraphemeChoice(whitespace(segment),segment,row,column,width,builder)
def scanGraphemes(segments: List<&2,String>,+row: Nat,+column: Nat,builder: Building) -> Building:
  match segments:
    case Nil{}: builder
    case +segment <> rest:
      +width = Utils.visibleWidth(segment)
      +next = scanGrapheme(segment,row,column,width,builder)
      scanGraphemes(rest,row,column + width,next)
def scanTextChoice(isAscii: Bool,text: String,row: Nat,builder: Building) -> Building:
  match isAscii:
    case True{}: scanAscii(text,row,0n,"",0n,builder)
    case False{}: scanGraphemes(Grapheme.segments(text),row,0n,builder)
def scanText(+text: String,row: Nat,builder: Building) -> Building:
  scanTextChoice(ascii(text),text,row,builder)
def scanLine(line: String,row: Nat,builder: Building) -> Building:
  +text = Utils.stripTerminalSequences(line)
  +next = scanText(text,row,builder)
  pending(next)
def scanLines(lines: List<&2,String>,+row: Nat,builder: Building) -> Building:
  match lines:
    case Nil{}: builder
    case line <> rest: scanLines(rest,row + 1n,scanLine(line,row,builder))
def built(builder: Building) -> Corpus:
  match builder:
    case Building{chunks,spans,_,_}: Corpus{String.join(List.reverse(&2,String,chunks),""),List.reverse(&2,Span,spans)}
def corpus(lines: List<&2,String>) -> Corpus: built(scanLines(lines,0n,empty()))

# Rendered whitespace collapses to one separator, including across rows.
def queryStep(text: String,+reversed: String,pendingSpace: Bool) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,+rest}:
      Bool.pick(Unit -> String,Text.whitespace(Char.to_u32(char)),
        _ => queryStep(rest,reversed,Bool.not(String.is_empty(reversed))),
        _ => queryStep(rest,SCon{char,Bool.pick(String,pendingSpace,SCon{' ',reversed},reversed)},False{}))(Unit{})
def normalizeQuery(text: String) -> String: queryStep(text,"",False{})
def foldedPrefix(text: String,query: String) -> Bool:
  match text query:
    case _ SNil{}: True{}
    case SCon{char,rest} SCon{wanted,more}: Fold.equal(char,wanted) && foldedPrefix(rest,more)
    case _ _: False{}
def appendSegment(+reversed: List<&2,Segment>,+row: Nat,+startCol: Nat,+endCol: Nat) -> List<&2,Segment>:
  match reversed:
    case Segment{lastRow,first,last} <> rest:
      Bool.pick(List<&2,Segment>,Nat.is_eq(lastRow,row) && Nat.is_le(startCol,last),Segment{row,first,Nat.max(last,endCol)} <> rest,Segment{row,startCol,endCol} <> reversed)
    case Nil{}: Segment{row,startCol,endCol} <> Nil{}
def segmentsIn(spans: List<&2,Span>,+start: Nat,+end: Nat,+reversed: List<&2,Segment>) -> List<&2,Segment>:
  match spans:
    case Nil{}: List.reverse(&2,Segment,reversed)
    case Span{+spanStart,+spanEnd,row,+colStart,colEnd,+linear} <> +rest:
      Bool.pick(Unit -> List<&2,Segment>,Nat.is_ge(spanStart,end),
        _ => List.reverse(&2,Segment,reversed),
        _ => Bool.pick(Unit -> List<&2,Segment>,Nat.is_le(spanEnd,start),
          _ => segmentsIn(rest,start,end,reversed),
          _ =>
            +left = Bool.pick(Nat,linear,colStart + Nat.max(start,spanStart) - spanStart,colStart)
            +right = Bool.pick(Nat,linear,colStart + Nat.min(end,spanEnd) - spanStart,colEnd)
            segmentsIn(rest,start,end,appendSegment(reversed,row,left,right)))(Unit{}))(Unit{})
def retainedMatch(segments: List<&2,Segment>,matches: List<&2,Match>) -> List<&2,Match>:
  match segments:
    case Nil{}: matches
    case _: Match{segments} <> matches
def recordMatch(found: Bool,spans: List<&2,Span>,+offset: Nat,length: Nat,reversed: List<&2,Match>) -> List<&2,Match>:
  match found:
    case False{}: reversed
    case True{}: retainedMatch(segmentsIn(spans,offset,offset + length,Nil{}),reversed)
def advanceSpans(spans: List<&2,Span>,+offset: Nat) -> List<&2,Span>:
  match spans:
    case Nil{}: Nil{}
    case Span{start,+end,row,left,right,linear} <> +rest:
      Bool.pick(Unit -> List<&2,Span>,Nat.is_le(end,offset),_ => advanceSpans(rest,offset),_ => Span{start,end,row,left,right,linear} <> rest)(Unit{})
def findIn(text: String,+query: String,+queryLength: Nat,+offset: Nat,+nextAllowed: Nat,+spans: List<&2,Span>,reversed: List<&2,Match>) -> List<&2,Match>:
  match text:
    case SNil{}: List.reverse(&2,Match,reversed)
    case SCon{char,+rest}:
      +active = advanceSpans(spans,offset)
      +found = Nat.is_ge(offset,nextAllowed) && foldedPrefix(SCon{char,rest},query)
      +matches = recordMatch(found,active,offset,queryLength,reversed)
      +allowed = Bool.pick(Nat,found,offset + queryLength,nextAllowed)
      findIn(rest,query,queryLength,offset + 1n,allowed,active,matches)
def find(source: Corpus,query: String) -> List<&2,Match>:
  match source query:
    case _ SNil{}: Nil{}
    case Corpus{text,spans} +query: findIn(text,query,String.length(query),0n,0n,spans,Nil{})
def findMatches(lines: List<&2,String>,query: String) -> List<&2,Match>:
  find(corpus(lines),normalizeQuery(query))

def sameLines(left: List<&2,String>,right: List<&2,String>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> more b <> rest: String.eq(a,b) && sameLines(more,rest)
    case _ _: False{}
def sourceChanged(old: Maybe<&2,List<&2,String>>,lines: List<&2,String>) -> Bool:
  match old:
    case None{}: True{}
    case Some{previous}: Bool.not(sameLines(previous,lines))
def chosenCorpus(changed: Bool,old: Maybe<&2,Corpus>,lines: List<&2,String>) -> Corpus:
  match changed old:
    case False{} Some{value}: value
    case _ _: corpus(lines)
def chosenMatches(changed: Bool,old: List<&2,Match>,source: Corpus,query: String) -> List<&2,Match>:
  match changed:
    case False{}: old
    case True{}: find(source,query)
def updated(previous: Index,+lines: List<&2,String>,+query: String) -> Index & SearchResult:
  match previous:
    case Index{oldSource,oldCorpus,oldQuery,oldMatches}:
      +changedSource = sourceChanged(oldSource,lines)
      +normalized = normalizeQuery(query)
      +changedQuery = Maybe.default(&2,Bool,Maybe.map(&2,String,Bool,value => Bool.not(String.eq(value,normalized)),oldQuery),True{})
      +nextCorpus = chosenCorpus(changedSource,oldCorpus,lines)
      +changed = changedSource || changedQuery
      +matches = chosenMatches(changed,oldMatches,nextCorpus,normalized)
      (Index{Some{lines},Some{nextCorpus},Some{normalized},matches},SearchResult{matches,changed})
def search(index: Index,lines: List<&2,String>,query: String) -> Index & SearchResult: updated(index,lines,query)
# The three-row search box is rendered as ordinary terminal lines, so the
# fullscreen renderer can composite it without a second mutable component.
def rule(count: Nat,reversed: String) -> String:
  match count:
    case Zero{}: reversed
    case Succ{left}: rule(left,"─" ++ reversed)
def resultLabel(query: String,selected: Maybe<&2,Nat>,count: Nat) -> String:
  match query selected count:
    case SNil{} _ _: ""
    case _ _ Zero{}: "No matches"
    case _ Some{position} _: Nat.show(position + 1n) ++ "/" ++ Nat.show(count)
    case _ None{} _: ""
def inputText(query: String,width: Nat) -> String:
  match query:
    case SNil{}: Utils.truncateToWidth(" \u{1b}[7m\u{1b}[2mF\u{1b}[22m\u{1b}[27m\u{1b}[2mind in transcript\u{1b}[22m",width,"",False{})
    case _: Utils.truncateToWidth(" " ++ query ++ Tui.CURSOR_MARKER() ++ "\u{1b}[7m \u{1b}[27m",width,"",False{})
def searchLines(+query: String,selected: Maybe<&2,Nat>,count: Nat,+width: Nat,previousKey: String,nextKey: String) -> List<&2,String>:
  +safe = Nat.max(1n,width)
  +inner = safe - 2n
  +label = resultLabel(query,selected,count)
  +labelText = Bool.pick(String,String.is_empty(label),"","\u{1b}[2m " ++ label ++ " \u{1b}[22m")
  +labelWidth = Utils.visibleWidth(labelText)
  +fieldWidth = inner - labelWidth
  +field = inputText(query,fieldWidth)
  +content = field ++ Utils.spaces(fieldWidth - Utils.visibleWidth(field),"") ++ labelText
  +previous = "↑ " ++ previousKey
  +next = "↓ " ++ nextKey
  +controls = previous ++ " · " ++ next
  +controlText = Bool.pick(String,Nat.is_le(Utils.visibleWidth(controls) + 3n,inner),controls,"↑ ↓")
  +show = Nat.is_le(Utils.visibleWidth(controlText) + 3n,inner)
  +bottom = Bool.pick(String,show,
    "└" ++ rule(inner - Utils.visibleWidth(controlText) - 3n,"") ++ " " ++ controlText ++ " ─┘",
    "└" ++ rule(inner,"") ++ "┘")
  Bool.pick(List<&2,String>,Nat.is_eq(safe,1n),["┌","│","└"],["┌" ++ rule(inner,"") ++ "┐","│" ++ content ++ "│",bottom])

type Selection is Data: Query{} Next{} Previous{} Retain{}
type Session is Data:
  Session{query: String,index: Index,matches: List<&2,Match>,selected: Maybe<&2,Nat>,anchor: Nat,selection: Selection}
type Refreshed is Data: Refreshed{session: Session,target: Maybe<&2,Nat>}
def open(top: Nat) -> Session: Session{"",index(),Nil{},None{},top,Retain{}}
def queryText(state: Session) -> String:
  match state: case Session{value,_,_,_,_,_}: value
def selectedMatch(matches: List<&2,Match>,position: Nat) -> Maybe<&2,Match>:
  match matches position:
    case value <> _ Zero{}: Some{value}
    case _ <> rest Succ{left}: selectedMatch(rest,left)
    case _ _: None{}
def firstRow(value: Match) -> Nat:
  match value:
    case Match{Segment{row,_,_} <> _}: row
    case _: 0n
def selectedRowValue(found: Maybe<&2,Match>,fallback: Nat) -> Nat:
  match found:
    case Some{value}: firstRow(value)
    case None{}: fallback
def selectedRow(matches: List<&2,Match>,selected: Maybe<&2,Nat>,fallback: Nat) -> Nat:
  match selected:
    case None{}: fallback
    case Some{position}: selectedRowValue(selectedMatch(matches,position),fallback)
def withQuery(state: Session,value: String,top: Nat) -> Session:
  match state:
    case Session{_,idx,+matches,+selected,_,_}:
      Session{value,idx,matches,selected,selectedRow(matches,selected,top),Query{}}
def navigate(state: Session,direction: Selection) -> Session:
  match state:
    case Session{query,idx,matches,selected,anchor,_}: Session{query,idx,matches,selected,anchor,direction}
def anchorIndex(matches: List<&2,Match>,+anchor: Nat,+position: Nat) -> Nat:
  match matches:
    case Nil{}: 0n
    case value <> rest:
      Bool.pick(Unit -> Nat,Nat.is_ge(firstRow(value),anchor),_ => position,_ => anchorIndex(rest,anchor,position + 1n))(Unit{})
def selectedNonEmpty(mode: Selection,old: Maybe<&2,Nat>,matches: List<&2,Match>,anchor: Nat,last: Nat) -> Maybe<&2,Nat>:
  match mode old:
    case Query{} _: Some{Nat.min(anchorIndex(matches,anchor,0n),last)}
    case Next{} None{}: Some{0n}
    case Next{} Some{+current}: Some{Bool.pick(Nat,Nat.is_ge(current,last),0n,current + 1n)}
    case Previous{} None{}: Some{last}
    case Previous{} Some{+current}: Some{Bool.pick(Nat,Nat.is_eq(current,0n),last,current - 1n)}
    case Retain{} None{}: Some{0n}
    case Retain{} Some{current}: Some{Nat.min(current,last)}
def selectedCount(count: Nat,mode: Selection,old: Maybe<&2,Nat>,matches: List<&2,Match>,anchor: Nat) -> Maybe<&2,Nat>:
  match count:
    case Zero{}: None{}
    case Succ{last}: selectedNonEmpty(mode,old,matches,anchor,last)
def selectedIndex(mode: Selection,old: Maybe<&2,Nat>,+matches: List<&2,Match>,anchor: Nat) -> Maybe<&2,Nat>:
  selectedCount(List.length(&2,Match,matches),mode,old,matches,anchor)
def selectedTarget(found: Maybe<&2,Match>,+top: Nat,+rows: Nat) -> Maybe<&2,Nat>:
  match found:
    case None{}: None{}
    case Some{value}:
      +row = firstRow(value)
      Some{Bool.pick(Nat,Nat.is_lt(row,top) || Nat.is_ge(row,top + rows),row - rows / 3n,top)}
def scrollTarget(mode: Selection,selected: Maybe<&2,Nat>,matches: List<&2,Match>,top: Nat,rows: Nat) -> Maybe<&2,Nat>:
  match mode selected:
    case Retain{} _: None{}
    case _ None{}: None{}
    case _ Some{position}: selectedTarget(selectedMatch(matches,position),top,rows)
def refreshFound(pair: Index & SearchResult,query: String,selected: Maybe<&2,Nat>,+anchor: Nat,+mode: Selection,top: Nat,rows: Nat) -> Refreshed:
  match pair:
    case (nextIndex,SearchResult{+matches,_}):
      +next = selectedIndex(mode,selected,matches,anchor)
      Refreshed{Session{query,nextIndex,matches,next,anchor,Retain{}},scrollTarget(mode,next,matches,top,rows)}
def refreshQuery(+query: String,idx: Index,selected: Maybe<&2,Nat>,anchor: Nat,mode: Selection,lines: List<&2,String>,top: Nat,rows: Nat) -> Refreshed:
  match query:
    case SNil{}: Refreshed{Session{"",idx,Nil{},None{},anchor,Retain{}},None{}}
    case _: refreshFound(search(idx,lines,query),query,selected,anchor,mode,top,rows)
def refreshed(state: Session,lines: List<&2,String>,top: Nat,rows: Nat) -> Refreshed:
  match state:
    case Session{query,idx,_,selected,anchor,mode}: refreshQuery(query,idx,selected,anchor,mode,lines,top,rows)
