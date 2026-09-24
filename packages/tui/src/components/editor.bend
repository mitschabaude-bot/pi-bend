import Base
import ../utils.bend as U
import ../autocomplete.bend as AC
import ./select-list.bend as Select
import ../tui.bend as Tui
import ../keybindings.bend as KB
import ../keys.bend as Keys
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/deferred.bend as D
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/timer.bend as Sleep
import ../word-navigation.bend as Word
import ../kill-ring.bend as Kill
import ../undo-stack.bend as Undo
import ../../../runtime/src/grapheme.bend as Grapheme
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/text.bend as Text

# Offsets are Unicode scalar positions, never UTF-16 code-unit positions.
type TextChunk is Data:
  TextChunk{text: String,startIndex: Nat,endIndex: Nat}
type Segment is Data:
  Segment{text: String,index: Nat,atomic: Bool}
type WrapOpportunity is Data:
  WrapOpportunity{index: Nat,width: Nat,prefix: String,suffix: String}
type Wrapping is Data:
  Wrapping{start: Nat,width: Nat,reversed: String,opportunity: Maybe<&2,WrapOpportunity>,chunks: List<&2,TextChunk>}

def prepend(text: String,reversed: String) -> String:
  match text:
    case SNil{}: reversed
    case SCon{char,rest}: prepend(rest,SCon{char,reversed})
def indexed(parts: List<&2,String>,+index: Nat,reversed: List<&2,Segment>) -> List<&2,Segment>:
  match parts:
    case Nil{}: List.reverse(&2,Segment,reversed)
    case +part <> rest: indexed(rest,index + String.length(part),Segment{part,index,False{}} <> reversed)
def segmentText(value: Segment) -> String:
  match value:
    case Segment{text,_,_}: text
def opportunityFits(opportunity: Maybe<&2,WrapOpportunity>,width: Nat,added: Nat,maximum: Nat) -> Bool:
  match opportunity:
    case None{}: False{}
    case Some{WrapOpportunity{_,prefixWidth,_,_}}: Nat.is_le(width - prefixWidth + added,maximum)
def breakAtOpportunity(state: Wrapping) -> Wrapping:
  match state:
    case Wrapping{start,width,_,Some{WrapOpportunity{+index,prefixWidth,prefix,suffix}},chunks}:
      Wrapping{index,width - prefixWidth,suffix,None{},TextChunk{String.reverse(prefix),start,index} <> chunks}
    case state: state
def breakBefore(state: Wrapping,+index: Nat) -> Wrapping:
  match state:
    case Wrapping{start,_,reversed,_,chunks}: Wrapping{index,0n,"",None{},TextChunk{String.reverse(reversed),start,index} <> chunks}
def clearOpportunity(state: Wrapping) -> Wrapping:
  match state:
    case Wrapping{start,width,reversed,_,chunks}: Wrapping{start,width,reversed,None{},chunks}
def beforeSegment(+state: Wrapping,+index: Nat,+added: Nat,+maximum: Nat) -> Wrapping:
  match state:
    case Wrapping{start,width,_,opportunity,_}:
      Bool.pick(Unit -> Wrapping,Nat.is_gt(width + added,maximum),
        _ => Bool.pick(Unit -> Wrapping,opportunityFits(opportunity,width,added,maximum),
          _ => breakAtOpportunity(state),
          _ => Bool.pick(Unit -> Wrapping,Nat.is_lt(start,index),_ => breakBefore(state,index),_ => clearOpportunity(state))(Unit{}))(Unit{}),
        _ => state)(Unit{})
def extendedOpportunity(value: Maybe<&2,WrapOpportunity>,text: String) -> Maybe<&2,WrapOpportunity>:
  match value:
    case None{}: None{}
    case Some{WrapOpportunity{index,width,prefix,suffix}}: Some{WrapOpportunity{index,width,prefix,prepend(text,suffix)}}
def wrapBoundary(current: Segment,next: List<&2,Segment>) -> Bool:
  match current next:
    case Segment{+text,_,+atomic} Segment{+following,_,+nextAtomic} <> _:
      +space = Bool.not(atomic) && Word.whitespace(text)
      +nextSpace = Word.whitespace(following)
      (space && (nextAtomic || Bool.not(nextSpace))) || (Bool.not(space) && Bool.not(nextSpace) && ((Bool.not(atomic) && U.cjkBreak(text)) || (Bool.not(nextAtomic) && U.cjkBreak(following))))
    case _ _: False{}
def addSegment(state: Wrapping,+text: String,+end: Nat,+boundary: Bool) -> Wrapping:
  match state:
    case Wrapping{start,width,reversed,opportunity,chunks}:
      +newWidth = width + U.visibleWidth(text)
      +newReversed = prepend(text,reversed)
      Wrapping{start,newWidth,newReversed,Bool.pick(Unit -> Maybe<&2,WrapOpportunity>,boundary,
        _ => Some{WrapOpportunity{end,newWidth,newReversed,""}},
        _ => extendedOpportunity(opportunity,text))(Unit{}),chunks}
def finishWrap(state: Wrapping,end: Nat) -> List<&2,TextChunk>:
  match state:
    case Wrapping{start,_,reversed,_,chunks}: List.reverse(&2,TextChunk,TextChunk{String.reverse(reversed),start,end} <> chunks)
def wrapSegments(parts: List<&2,Segment>,+maximum: Nat,+end: Nat,state: Wrapping) -> List<&2,TextChunk>:
  match parts:
    case Nil{}: finishWrap(state,end)
    case Segment{+text,+index,+atomic} <> +rest:
      wrapSegments(rest,maximum,end,addSegment(beforeSegment(state,index,U.visibleWidth(text),maximum),text,index + String.length(text),wrapBoundary(Segment{text,index,atomic},rest)))

# A single grapheme wider than the viewport stays intact. Upstream recursively
# wraps that same grapheme forever; breaking a Unicode cluster is not a repair.
def wordWrapLine(+line: String,+maxWidth: Nat) -> List<&2,TextChunk>:
  Bool.pick(Unit -> List<&2,TextChunk>,String.is_empty(line) || Nat.is_eq(maxWidth,0n),
    _ => TextChunk{"",0n,0n} <> Nil{},
    _ => Bool.pick(Unit -> List<&2,TextChunk>,Nat.is_le(U.visibleWidth(line),maxWidth),
      _ => TextChunk{line,0n,String.length(line)} <> Nil{},
      _ => wrapSegments(indexed(Grapheme.segments(line),0n,Nil{}),maxWidth,String.length(line),Wrapping{0n,0n,"",None{},Nil{}}))(Unit{}))(Unit{})

# Only syntactically valid markers whose IDs occur in the paste registry are
# atomic. Literal marker-looking text otherwise retains ordinary graphemes.
type Paste is Data: Paste{id: Nat,text: String}
type Marker is Data: Marker{id: Nat,text: String,rest: String}
type Digits is Data: Digits{value: Nat,text: String,rest: String}
def decimalEnd(rest: String,value: Nat,+reversed: String) -> Maybe<&2,Digits>:
  Bool.pick(Maybe<&2,Digits>,String.is_empty(reversed),None{},Some{Digits{value,String.reverse(reversed),rest}})
def decimal(text: String,+value: Nat,+reversed: String) -> Maybe<&2,Digits>:
  match text:
    case SCon{Chr{+point},+rest}:
      Bool.pick(Unit -> Maybe<&2,Digits>,U32.is_ge(point,48) && U32.is_le(point,57),
        _ => decimal(rest,value * 10n + U32.to_nat((point - 48 : U32)),SCon{Chr{point},reversed}),
        _ => decimalEnd(SCon{Chr{point},rest},value,reversed))(Unit{})
    case SNil{}: decimalEnd("",value,reversed)
def markerClose(id: Nat,prefix: String,remaining: Maybe<&2,String>) -> Maybe<&2,Marker>:
  match remaining:
    case Some{rest}: Some{Marker{id,prefix,rest}}
    case None{}: None{}
def markerCount(id: Nat,prefix: String,+suffix: String,value: Maybe<&2,Digits>) -> Maybe<&2,Marker>:
  match value:
    case None{}: None{}
    case Some{Digits{_,digits,rest}}: markerClose(id,prefix ++ digits ++ suffix,Word.consume(suffix,rest))
def markerSuffix(id: Nat,+prefix: String,rest: String) -> Maybe<&2,Marker>:
  match rest:
    case SCon{']',rest}: Some{Marker{id,prefix ++ "]",rest}}
    case SCon{' ',SCon{'+',rest}}: markerCount(id,prefix ++ " +"," lines]",decimal(rest,0n,""))
    case SCon{' ',rest}: markerCount(id,prefix ++ " "," chars]",decimal(rest,0n,""))
    case _: None{}
def markerId(value: Maybe<&2,Digits>) -> Maybe<&2,Marker>:
  match value:
    case None{}: None{}
    case Some{Digits{id,digits,rest}}: markerSuffix(id,"[paste #" ++ digits,rest)
def markerDigits(value: Maybe<&2,String>) -> Maybe<&2,Marker>:
  match value:
    case None{}: None{}
    case Some{text}: markerId(decimal(text,0n,""))
def marker(text: String) -> Maybe<&2,Marker>: markerDigits(Word.consume("[paste #",text))
def pasteAt(pastes: List<&2,Paste>,+id: Nat) -> Maybe<&2,String>:
  match pastes:
    case Nil{}: None{}
    case Paste{key,+value} <> +rest: Bool.pick(Unit -> Maybe<&2,String>,Nat.is_eq(key,id),_ => Some{value},_ => pasteAt(rest,id))(Unit{})
def validMarker(value: Maybe<&2,Marker>,pastes: List<&2,Paste>) -> Maybe<&2,Marker>:
  match value:
    case None{}: None{}
    case Some{Marker{+id,+text,+rest}}: Bool.pick(Maybe<&2,Marker>,Maybe.is_none(&2,String,pasteAt(pastes,id)),None{},Some{Marker{id,text,rest}})
def skipSegments(parts: List<&2,Segment>,+end: Nat) -> List<&2,Segment>:
  match parts:
    case Nil{}: Nil{}
    case Segment{+text,+index,+atomic} <> +rest: Bool.pick(Unit -> List<&2,Segment>,Nat.is_lt(index,end),_ => skipSegments(rest,end),_ => Segment{text,index,atomic} <> rest)(Unit{})
type MergeStep is Data: MergeStep{text: String,parts: List<&2,Segment>,reversed: List<&2,Segment>}
def mergeMarker(value: Maybe<&2,Marker>,text: String,parts: List<&2,Segment>,reversed: List<&2,Segment>) -> MergeStep:
  match value parts:
    case _ Nil{}: MergeStep{text,Nil{},reversed}
    case Some{Marker{_,+value,restText}} Segment{_,+index,_} <> rest:
      MergeStep{restText,skipSegments(rest,index + String.length(value)),Segment{value,index,True{}} <> reversed}
    case None{} Segment{+value,index,atomic} <> rest:
      MergeStep{String.drop(text,String.length(value)),rest,Segment{value,index,atomic} <> reversed}
@unsafe
def mergeMarkers(state: MergeStep,+pastes: List<&2,Paste>) -> List<&2,Segment>:
  match state:
    case MergeStep{_,Nil{},reversed}: List.reverse(&2,Segment,reversed)
    case MergeStep{+text,parts,reversed}: mergeMarkers(mergeMarker(validMarker(marker(text),pastes),text,parts,reversed),pastes)
def segmentWithMarkers(+text: String,pastes: List<&2,Paste>) -> List<&2,Segment>:
  mergeMarkers(MergeStep{text,indexed(Grapheme.segments(text),0n,Nil{}),Nil{}},pastes)

def atomicChunks(parts: List<&2,TextChunk>,+offset: Nat,state: Wrapping) -> Wrapping:
  match parts state:
    case Nil{} state: state
    case TextChunk{+text,start,_} <> Nil{} Wrapping{_,_,_,_,chunks}: Wrapping{offset + start,U.visibleWidth(text),String.reverse(text),None{},chunks}
    case TextChunk{text,start,+end} <> rest Wrapping{_,_,_,_,chunks}: atomicChunks(rest,offset,Wrapping{offset + end,0n,"",None{},TextChunk{text,offset + start,offset + end} <> chunks})
def wrapAtomicSegments(parts: List<&2,Segment>,+maximum: Nat,+end: Nat,state: Wrapping) -> List<&2,TextChunk>:
  match parts:
    case Nil{}: finishWrap(state,end)
    case Segment{+text,+index,+atomic} <> +rest:
      +prepared = beforeSegment(state,index,U.visibleWidth(text),maximum)
      Bool.pick(Unit -> List<&2,TextChunk>,atomic && Nat.is_gt(U.visibleWidth(text),maximum),
        _ => wrapAtomicSegments(rest,maximum,end,atomicChunks(wordWrapLine(text,maximum),index,prepared)),
        _ => wrapAtomicSegments(rest,maximum,end,addSegment(prepared,text,index + String.length(text),wrapBoundary(Segment{text,index,atomic},rest))))(Unit{})

def wordWrapLineWithMarkers(+line: String,+maximum: Nat,pastes: List<&2,Paste>) -> List<&2,TextChunk>:
  Bool.pick(Unit -> List<&2,TextChunk>,String.is_empty(line) || Nat.is_eq(maximum,0n),
    _ => TextChunk{"",0n,0n} <> Nil{},
    _ => wrapAtomicSegments(segmentWithMarkers(line,pastes),maximum,String.length(line),Wrapping{0n,0n,"",None{},Nil{}}))(Unit{})

# Editing snapshots include the registry, so undo restores marker identity and
# content together. Coordinates remain scalar offsets into immutable lines.
type EditorState is Data: EditorState{lines: List<&2,String>,cursorLine: Nat,cursorCol: Nat}
type EditorSnapshot is Data: EditorSnapshot{state: EditorState,pastes: List<&2,Paste>,pasteCounter: Nat}
type LastAction is Data: NoAction{} KillAction{} YankAction{} TypeWord{}
type Editing is Data:
  Editing{snapshot: EditorSnapshot,killRing: Kill.KillRing,lastAction: LastAction,undoStack: Undo.UndoStack<EditorSnapshot>,preferredVisualCol: Maybe<&2,Nat>,snappedFromCursorCol: Maybe<&2,Nat>}
def emptyState() -> EditorState: EditorState{[""],0n,0n}
def emptySnapshot() -> EditorSnapshot: EditorSnapshot{emptyState(),Nil{},0n}
def createEditing() -> Editing: Editing{emptySnapshot(),Kill.create(),NoAction{},Undo.create(EditorSnapshot),None{},None{}}
def takePrefix(text: String,count: Nat,reversed: String) -> String:
  match text count:
    case SCon{char,rest} Succ{count}: takePrefix(rest,count,SCon{char,reversed})
    case _ _: String.reverse(reversed)
def normalizeScan(text: String,reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'\r',SCon{'\n',rest}}: normalizeScan(rest,SCon{'\n',reversed})
    case SCon{'\r',rest}: normalizeScan(rest,SCon{'\n',reversed})
    case SCon{'\t',rest}: normalizeScan(rest,"    " ++ reversed)
    case SCon{char,rest}: normalizeScan(rest,SCon{char,reversed})
def normalizeText(text: String) -> String: normalizeScan(text,"")
def stateText(state: EditorState) -> String:
  match state:
    case EditorState{lines,_,_}: String.join(lines,"\n")
def textAt(lines: List<&2,String>,index: Nat) -> String:
  match lines index:
    case line <> _ Zero{}: line
    case _ <> rest Succ{index}: textAt(rest,index)
    case Nil{} _: ""
def lastLine(lines: List<&2,String>,previous: String) -> String:
  match lines:
    case Nil{}: previous
    case line <> rest: lastLine(rest,line)
def fromLines(+lines: List<&2,String>,+start: Bool) -> EditorState:
  EditorState{lines,Bool.pick(Nat,start,0n,List.length(&2,String,lines) - 1n),Bool.pick(Nat,start,0n,String.length(lastLine(lines,"")))}
def fromText(text: String,start: Bool) -> EditorState: fromLines(Strings.split(text,'\n'),start)
def cursorOffset(lines: List<&2,String>,line: Nat,column: Nat,offset: Nat) -> Nat:
  match lines line:
    case _ Zero{}: offset + column
    case text <> rest Succ{line}: cursorOffset(rest,line,column,offset + String.length(text) + 1n)
    case Nil{} _: offset + column
def stateOffset(state: EditorState) -> Nat:
  match state:
    case EditorState{lines,line,column}: cursorOffset(lines,line,column,0n)
def locate(parts: List<&2,String>,+offset: Nat,+line: Nat) -> Nat & Nat:
  match parts:
    case Nil{}: (line,0n)
    case +text <> Nil{}: (line,Nat.min(offset,String.length(text)))
    case +text <> +rest: Bool.pick(Unit -> Nat & Nat,Nat.is_le(offset,String.length(text)),_ => (line,offset),_ => locate(rest,offset - String.length(text) - 1n,line + 1n))(Unit{})
def located(lines: List<&2,String>,position: Nat & Nat) -> EditorState:
  match position:
    case Tuple{line,column}: EditorState{lines,line,column}
def atOffset(+lines: List<&2,String>,offset: Nat) -> EditorState: located(lines,locate(lines,offset,0n))
def stateAtText(+text: String,offset: Nat) -> EditorState: atOffset(Strings.split(text,'\n'),offset)
def editingText(value: Editing) -> String:
  match value:
    case Editing{EditorSnapshot{state,_,_},_,_,_,_,_}: stateText(state)
def pushUndoSnapshot(value: Editing) -> Editing:
  match value:
    case Editing{+snapshot,ring,action,stack,preferred,snapped}: Editing{snapshot,ring,action,Undo.push(EditorSnapshot,snapshot,stack),preferred,snapped}
def changed(value: Editing,state: EditorState,action: LastAction) -> Editing:
  match value:
    case Editing{EditorSnapshot{_,pastes,count},ring,_,stack,_,_}: Editing{EditorSnapshot{state,pastes,count},ring,action,stack,None{},None{}}
def insertInternal(+value: Editing,+text: String,action: LastAction) -> Editing:
  match value:
    case Editing{EditorSnapshot{+state,_,_},_,_,_,_,_}:
      +offset = stateOffset(state)
      +document = stateText(state)
      +normalized = normalizeText(text)
      changed(value,stateAtText(takePrefix(document,offset,"") ++ normalized ++ String.drop(document,offset),offset + String.length(normalized)),action)
def setEditingText(+value: Editing,text: String) -> Editing:
  match value:
    case Editing{_,ring,_,stack,_,_}: Editing{EditorSnapshot{fromText(text,False{}),Nil{},0n},ring,NoAction{},stack,None{},None{}}
def setTextEdit(+value: Editing,text: String) -> Editing:
  +normalized = normalizeText(text)
  setEditingText(Bool.pick(Unit -> Editing,Strings.equal(editingText(value),normalized),_ => value,_ => pushUndoSnapshot(value))(Unit{}),normalized)
def insertTextEdit(+value: Editing,+text: String) -> Editing:
  Bool.pick(Unit -> Editing,String.is_empty(text),_ => value,_ => insertInternal(pushUndoSnapshot(value),text,NoAction{}))(Unit{})
def isWord(action: LastAction) -> Bool:
  match action:
    case TypeWord{}: True{}
    case _: False{}
def isKill(action: LastAction) -> Bool:
  match action:
    case KillAction{}: True{}
    case _: False{}
def isYank(action: LastAction) -> Bool:
  match action:
    case YankAction{}: True{}
    case _: False{}
def insertCharacter(+value: Editing,+text: String) -> Editing:
  match value:
    case Editing{_,_,action,_,_,_}: insertInternal(Bool.pick(Unit -> Editing,Word.whitespace(text) || Bool.not(isWord(action)),_ => pushUndoSnapshot(value),_ => value)(Unit{}),text,TypeWord{})
def restored(value: Editing,result: Undo.UndoStack<EditorSnapshot> & Maybe<&2,EditorSnapshot>) -> Editing:
  match value result:
    case Editing{_,ring,_,_,_,_} Tuple{stack,Some{snapshot}}: Editing{snapshot,ring,NoAction{},stack,None{},None{}}
    case value Tuple{_,None{}}: value
def undoEdit(+value: Editing) -> Editing:
  match value:
    case Editing{_,_,_,stack,_,_}: restored(value,Undo.pop(EditorSnapshot,stack))
def moveTo(+value: Editing,line: Nat,column: Nat) -> Editing:
  match value:
    case Editing{EditorSnapshot{EditorState{lines,_,_},_,_},_,_,_,_,_}: changed(value,EditorState{lines,line,column},NoAction{})
def eraseRange(+value: Editing,+from: Nat,+until: Nat) -> Editing:
  +document = editingText(value)
  changed(pushUndoSnapshot(value),stateAtText(takePrefix(document,from,"") ++ String.drop(document,until),from),NoAction{})
def killRange(value: Editing,+from: Nat,+until: Nat,prepend: Bool) -> Editing:
  match value:
    case Editing{EditorSnapshot{+state,+pastes,+count},ring,action,stack,_,_}:
      +document = stateText(state)
      Editing{EditorSnapshot{stateAtText(takePrefix(document,from,"") ++ String.drop(document,until),from),pastes,count},Kill.push(takePrefix(String.drop(document,from),until - from,""),Kill.PushOptions{prepend,isKill(action)},ring),KillAction{},Undo.push(EditorSnapshot,EditorSnapshot{state,pastes,count},stack),None{},None{}}
def segmentEnd(part: Segment) -> Nat:
  match part:
    case Segment{text,index,_}: index + String.length(text)
def previousSegment(parts: List<&2,Segment>,previous: Nat) -> Nat:
  match parts:
    case Nil{}: previous
    case Segment{_,index,_} <> rest: previousSegment(rest,index)
def nextSegment(parts: List<&2,Segment>,fallback: Nat) -> Nat:
  match parts:
    case Nil{}: fallback
    case part <> _: segmentEnd(part)
def resetAction(value: Editing) -> Editing:
  match value:
    case Editing{snapshot,ring,_,stack,preferred,snapped}: Editing{snapshot,ring,NoAction{},stack,preferred,snapped}
def moveHorizontal(+value: Editing,backward: Bool) -> Editing:
  match value:
    case Editing{EditorSnapshot{EditorState{+lines,+line,+column},+pastes,_},_,_,_,_,_}:
      +text = textAt(lines,line)
      Bool.pick(Unit -> Editing,backward,
        _ => Bool.pick(Unit -> Editing,Nat.is_gt(column,0n),
          _ => moveTo(value,line,previousSegment(segmentWithMarkers(takePrefix(text,column,""),pastes),column - 1n)),
          _ => Bool.pick(Unit -> Editing,Nat.is_gt(line,0n),_ => moveTo(value,line - 1n,String.length(textAt(lines,line - 1n))),_ => resetAction(value))(Unit{}))(Unit{}),
        _ => Bool.pick(Unit -> Editing,Nat.is_lt(column,String.length(text)),
          _ => moveTo(value,line,column + nextSegment(segmentWithMarkers(String.drop(text,column),pastes),1n)),
          _ => Bool.pick(Unit -> Editing,Nat.is_lt(line + 1n,List.length(&2,String,lines)),_ => moveTo(value,line + 1n,0n),_ => resetAction(value))(Unit{}))(Unit{}))(Unit{})
def deleteMoved(+value: Editing,+old: Nat,moved: Editing) -> Editing:
  match moved:
    case Editing{EditorSnapshot{state,_,_},_,_,_,_,_}:
      +target = stateOffset(state)
      Bool.pick(Unit -> Editing,Nat.is_eq(old,target),_ => resetAction(value),_ => eraseRange(value,Nat.min(old,target),Nat.max(old,target)))(Unit{})

def deleteHorizontal(+value: Editing,backward: Bool) -> Editing:
  match value:
    case Editing{EditorSnapshot{state,_,_},_,_,_,_,_}:
      +old = stateOffset(state)
      +moved = moveHorizontal(value,backward)
      deleteMoved(value,old,moved)

def replaceMarkerStep(value: Maybe<&2,Marker>,+id: Nat,content: String,text: String) -> String & String:
  match value text:
    case Some{Marker{found,+matched,+rest}} text:
      Bool.pick(String & String,Nat.is_eq(found,id),(content,rest),(matched,rest))
    case _ SCon{char,rest}: (SCon{char,""},rest)
    case _ SNil{}: ("","")
type ReplaceScan is Data: ReplaceScan{text: String,reversed: String}
def replaceNextParts(value: String & String,reversed: String) -> ReplaceScan:
  match value:
    case Tuple{text,rest}: ReplaceScan{rest,prepend(text,reversed)}
def replaceNext(state: ReplaceScan,id: Nat,content: String) -> ReplaceScan:
  match state:
    case ReplaceScan{+text,reversed}: replaceNextParts(replaceMarkerStep(marker(text),id,content,text),reversed)
@unsafe
def replaceMarkerScan(state: ReplaceScan,+id: Nat,+content: String) -> String:
  match state:
    case ReplaceScan{SNil{},reversed}: String.reverse(reversed)
    case state: replaceMarkerScan(replaceNext(state,id,content),id,content)
def expandPasteMarkers(pastes: List<&2,Paste>,text: String) -> String:
  match pastes:
    case Nil{}: text
    case Paste{id,content} <> rest: expandPasteMarkers(rest,replaceMarkerScan(ReplaceScan{text,""},id,content))
def expandedEditingText(value: Editing) -> String:
  match value:
    case Editing{EditorSnapshot{state,pastes,_},_,_,_,_,_}: expandPasteMarkers(pastes,stateText(state))
type DecodedControl is Data: DecodedControl{char: Char,rest: String}
def decodedControlEnd(char: Char,rest: Maybe<&2,String>) -> Maybe<&2,DecodedControl>:
  match rest:
    case None{}: None{}
    case Some{rest}: Some{DecodedControl{char,rest}}
def decodedControl(value: Maybe<&2,Digits>) -> Maybe<&2,DecodedControl>:
  match value:
    case None{}: None{}
    case Some{Digits{+number,_,rest}}:
      +point = U32.from_nat(number)
      Bool.pick(Unit -> Maybe<&2,DecodedControl>,(Nat.is_ge(number,97n) && Nat.is_le(number,122n)) || (Nat.is_ge(number,65n) && Nat.is_le(number,90n)),
        _ => decodedControlEnd(Chr{Bool.pick(U32,U32.is_ge(point,97),(point - 96 : U32),(point - 64 : U32))},Word.consume(";5u",rest)),
        _ => None{})(Unit{})
def decodeStart(value: Maybe<&2,String>) -> Maybe<&2,DecodedControl>:
  match value:
    case None{}: None{}
    case Some{rest}: decodedControl(decimal(rest,0n,""))
def decodeStep(value: Maybe<&2,DecodedControl>,text: String,reversed: String) -> ReplaceScan:
  match value text:
    case Some{DecodedControl{char,rest}} _: ReplaceScan{rest,SCon{char,reversed}}
    case None{} SCon{char,rest}: ReplaceScan{rest,SCon{char,reversed}}
    case None{} SNil{}: ReplaceScan{"",reversed}
@unsafe
def decodePaste(state: ReplaceScan) -> String:
  match state:
    case ReplaceScan{SNil{},reversed}: String.reverse(reversed)
    case ReplaceScan{+text,reversed}: decodePaste(decodeStep(decodeStart(Word.consume("\u{1b}[",text)),text,reversed))
def filterPaste(text: String,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,rest}: filterPaste(rest,Bool.pick(String,Char.is_eq(char,'\n') || U32.is_ge(Char.to_u32(char),32),SCon{char,reversed},reversed))
def asciiWord(char: Char) -> Bool:
  +point = Char.to_u32(char)
  (U32.is_ge(point,65) && U32.is_le(point,90)) || (U32.is_ge(point,97) && U32.is_le(point,122)) || (U32.is_ge(point,48) && U32.is_le(point,57)) || U32.is_eq(point,95)
def pasteSpace(text: String,before: String) -> String:
  match text before:
    case SCon{+char,+rest} SCon{previous,_}: Bool.pick(String,(Char.is_eq(char,'/') || Char.is_eq(char,'~') || Char.is_eq(char,'.')) && asciiWord(previous)," " ++ SCon{char,rest},SCon{char,rest})
    case text _: text
def pasteStored(value: Editing,+text: String,+lines: Nat,+size: Nat) -> Editing:
  match value:
    case Editing{EditorSnapshot{state,pastes,count},ring,action,stack,preferred,snapped}:
      +id = count + 1n
      +label = Bool.pick(String,Nat.is_gt(lines,10n)," +" ++ Nat.show(lines) ++ " lines"," " ++ Nat.show(size) ++ " chars")
      insertInternal(Editing{EditorSnapshot{state,List.append(&2,Paste,pastes,Paste{id,text} <> Nil{}),id},ring,action,stack,preferred,snapped},"[paste #" ++ Nat.show(id) ++ label ++ "]",NoAction{})
def pasteCleaned(+value: Editing,+text: String) -> Editing:
  +lines = List.length(&2,String,Strings.split(text,'\n'))
  +size = String.length(text)
  Bool.pick(Unit -> Editing,Nat.is_gt(lines,10n) || Nat.is_gt(size,1000n),_ => pasteStored(value,text,lines,size),_ => insertInternal(value,text,NoAction{}))(Unit{})
def handlePasteEdit(+value: Editing,text: String) -> Editing:
  match value:
    case Editing{EditorSnapshot{EditorState{lines,line,column},_,_},_,_,_,_,_}:
      pasteCleaned(pushUndoSnapshot(value),pasteSpace(filterPaste(normalizeText(decodePaste(ReplaceScan{text,""})),""),String.reverse(takePrefix(textAt(lines,line),column,""))))

def yankEdit(+value: Editing) -> Editing:
  match value:
    case Editing{_,ring,_,_,_,_}:
      +text = Maybe.default(&2,String,Kill.peek(ring),"")
      Bool.pick(Unit -> Editing,String.is_empty(text),_ => value,_ => insertInternal(pushUndoSnapshot(value),text,YankAction{}))(Unit{})
def resetRing(value: Editing,ring: Kill.KillRing) -> Editing:
  match value:
    case Editing{snapshot,_,action,stack,preferred,snapped}: Editing{snapshot,ring,action,stack,preferred,snapped}
def yankPopEdit(+value: Editing) -> Editing:
  match value:
    case Editing{EditorSnapshot{+state,_,_},+ring,action,_,_,_}:
      +old = Maybe.default(&2,String,Kill.peek(ring),"")
      +rotated = Kill.rotate(ring)
      +text = Maybe.default(&2,String,Kill.peek(rotated),"")
      +end = stateOffset(state)
      +start = end - String.length(old)
      +document = stateText(state)
      Bool.pick(Unit -> Editing,isYank(action) && Nat.is_gt(Kill.length(ring),1n),
        _ => changed(resetRing(pushUndoSnapshot(value),rotated),stateAtText(takePrefix(document,start,"") ++ text ++ String.drop(document,end),start + String.length(text)),YankAction{}),
        _ => value)(Unit{})
def lineBoundary(+value: Editing,start: Bool) -> Editing:
  match value:
    case Editing{EditorSnapshot{EditorState{lines,+line,_},_,_},_,_,_,_,_}: moveTo(value,line,Bool.pick(Nat,start,0n,String.length(textAt(lines,line))))
def killLine(+value: Editing,+start: Bool) -> Editing:
  match value:
    case Editing{EditorSnapshot{EditorState{+lines,+line,+column},_,_},_,_,_,_,_}:
      +offset = cursorOffset(lines,line,column,0n)
      +length = String.length(textAt(lines,line))
      Bool.pick(Unit -> Editing,start,
        _ => Bool.pick(Unit -> Editing,Nat.is_gt(column,0n),_ => killRange(value,offset - column,offset,True{}),_ => Bool.pick(Unit -> Editing,Nat.is_gt(line,0n),_ => killRange(value,offset - 1n,offset,True{}),_ => value)(Unit{}))(Unit{}),
        _ => Bool.pick(Unit -> Editing,Nat.is_lt(column,length),_ => killRange(value,offset,offset + length - column,False{}),_ => Bool.pick(Unit -> Editing,Nat.is_lt(line + 1n,List.length(&2,String,lines)),_ => killRange(value,offset,offset + 1n,False{}),_ => value)(Unit{}))(Unit{}))(Unit{})

type LayoutLine is Data: LayoutLine{text: String,logicalLine: Nat,startCol: Nat,length: Nat,cursorPos: Maybe<&2,Nat>,last: Bool}
def layoutChunks(chunks: List<&2,TextChunk>,+line: Nat,+current: Bool,+column: Nat,reversed: List<&2,LayoutLine>) -> List<&2,LayoutLine>:
  match chunks:
    case Nil{}: reversed
    case TextChunk{+text,+start,+end} <> +rest:
      +last = List.is_empty(&2,TextChunk,rest)
      +here = current && Nat.is_ge(column,start) && (last || Nat.is_lt(column,end))
      layoutChunks(rest,line,current,column,LayoutLine{text,line,start,end - start,Bool.pick(Maybe<&2,Nat>,here,Some{Nat.min(column - start,String.length(text))},None{}),last} <> reversed)
def layoutLines(lines: List<&2,String>,+index: Nat,+current: Nat,+column: Nat,+width: Nat,+pastes: List<&2,Paste>,reversed: List<&2,LayoutLine>) -> List<&2,LayoutLine>:
  match lines:
    case Nil{}: List.reverse(&2,LayoutLine,reversed)
    case text <> rest: layoutLines(rest,index + 1n,current,column,width,pastes,layoutChunks(wordWrapLineWithMarkers(text,width,pastes),index,Nat.is_eq(index,current),column,reversed))
def layoutText(value: Editing,width: Nat) -> List<&2,LayoutLine>:
  match value:
    case Editing{EditorSnapshot{EditorState{lines,line,column},pastes,_},_,_,_,_,_}: layoutLines(lines,0n,line,column,width,pastes,Nil{})
def layoutAt(lines: List<&2,LayoutLine>,index: Nat) -> Maybe<&2,LayoutLine>:
  match lines index:
    case head <> _ Zero{}: Some{head}
    case _ <> rest Succ{index}: layoutAt(rest,index)
    case Nil{} _: None{}
def cursorLayoutIndex(lines: List<&2,LayoutLine>,+index: Nat) -> Nat:
  match lines:
    case Nil{}: 0n
    case LayoutLine{_,_,_,_,Some{_},_} <> _: index
    case _ <> rest: cursorLayoutIndex(rest,index + 1n)
def findVisualLineAt(lines: List<&2,LayoutLine>,+line: Nat,+column: Nat,+index: Nat) -> Nat:
  match lines:
    case Nil{}: 0n
    case LayoutLine{_,logical,+start,length,_,last} <> +rest:
      Bool.pick(Unit -> Nat,Nat.is_eq(logical,line) && Nat.is_ge(column,start) && (last || Nat.is_lt(column,start + length)),_ => index,_ => findVisualLineAt(rest,line,column,index + 1n))(Unit{})
def snapColumn(parts: List<&2,Segment>,+column: Nat) -> Nat:
  match parts:
    case Nil{}: column
    case Segment{+text,+index,atomic} <> +rest:
      Bool.pick(Unit -> Nat,atomic && Nat.is_gt(column,index) && Nat.is_lt(column,index + String.length(text)),_ => index,_ => snapColumn(rest,column))(Unit{})
def unclampedColumn(+current: Nat,+target: Nat) -> Nat & Maybe<&2,Nat>:
  Bool.pick(Nat & Maybe<&2,Nat>,Nat.is_lt(target,current),(target,Some{current}),(current,None{}))
def stickyColumn(+current: Nat,+sourceMax: Nat,+targetMax: Nat,preferred: Maybe<&2,Nat>) -> Nat & Maybe<&2,Nat>:
  match preferred:
    case None{}: unclampedColumn(current,targetMax)
    case Some{+preferred}:
      Bool.pick(Unit -> Nat & Maybe<&2,Nat>,Nat.is_lt(current,sourceMax),
        _ => unclampedColumn(current,targetMax),
        _ => Bool.pick(Nat & Maybe<&2,Nat>,Nat.is_lt(targetMax,current) || Nat.is_lt(targetMax,preferred),(targetMax,Some{preferred}),(preferred,None{})))(Unit{})
def utf16Length(text: String) -> Nat:
  match text:
    case SNil{}: 0n
    case SCon{Chr{point},rest}: Bool.pick(Nat,U32.is_gt(point,65535),2n,1n) + utf16Length(rest)
def scalarAtUtf16(text: String,+units: Nat) -> Nat:
  match text:
    case SNil{}: 0n
    case SCon{Chr{point},rest}:
      +size = Bool.pick(Nat,U32.is_gt(point,65535),2n,1n)
      Bool.pick(Unit -> Nat,Nat.is_lt(units,size),_ => 0n,_ => 1n + scalarAtUtf16(rest,units - size))(Unit{})
def applyVertical(value: Editing,+line: Nat,+start: Nat,+chunk: String,movement: Nat & Maybe<&2,Nat>) -> Editing:
  match value movement:
    case Editing{EditorSnapshot{EditorState{+lines,_,_},+pastes,count},ring,_,stack,_,_} Tuple{column,preferred}:
      +target = Nat.min(start + scalarAtUtf16(chunk,column),String.length(textAt(lines,line)))
      +snapped = snapColumn(segmentWithMarkers(textAt(lines,line),pastes),target)
      Editing{EditorSnapshot{EditorState{lines,line,snapped},pastes,count},ring,NoAction{},stack,preferred,Bool.pick(Maybe<&2,Nat>,Nat.is_eq(target,snapped),None{},Some{target})}
def moveVisualTarget(+value: Editing,current: Nat,target: Maybe<&2,LayoutLine>,source: Maybe<&2,LayoutLine>) -> Editing:
  match value target source:
    case Editing{_,_,_,_,preferred,_} Some{LayoutLine{+chunk,line,start,_,_,last}} Some{LayoutLine{sourceChunk,_,_,_,_,sourceLast}}:
      +length = utf16Length(chunk)
      +sourceLength = utf16Length(sourceChunk)
      applyVertical(value,line,start,chunk,stickyColumn(current,Bool.pick(Nat,sourceLast,sourceLength,sourceLength - 1n),Bool.pick(Nat,last,length,length - 1n),preferred))
    case _ _ _: resetAction(value)
def resolvedVisualColumn(value: Maybe<&2,LayoutLine>,column: Nat) -> Nat:
  match value:
    case None{}: column
    case Some{LayoutLine{text,_,start,_,_,_}}: utf16Length(takePrefix(text,column - start,""))
def moveVertical(+value: Editing,+width: Nat,+up: Bool,+count: Nat) -> Editing:
  match value:
    case Editing{EditorSnapshot{EditorState{_,+line,+column},_,_},_,_,_,_,snapped}:
      +map = layoutText(value,width)
      +current = cursorLayoutIndex(map,0n)
      +target = Bool.pick(Nat,up,current - count,Nat.min(current + count,List.length(&2,LayoutLine,map) - 1n))
      +original = Maybe.default(&2,Nat,snapped,column)
      +source = findVisualLineAt(map,line,original,0n)
      moveVisualTarget(value,resolvedVisualColumn(layoutAt(map,source),original),layoutAt(map,target),layoutAt(map,current))

def repeat(count: Nat,+char: Char,reversed: String) -> String:
  match count:
    case Zero{}: reversed
    case Succ{count}: repeat(count,char,SCon{char,reversed})
def scrollBorder(direction: String,+hidden: Nat,+width: Nat) -> String:
  +label = " " ++ direction ++ " " ++ Nat.show(hidden) ++ " more "
  +labelWidth = U.visibleWidth(label)
  +indicator = "───" ++ label
  +indicatorWidth = U.visibleWidth(indicator)
  +dots = takePrefix("...",width,"")
  +left = Nat.div(width - labelWidth,2n)
  Bool.pick(Unit -> String,Nat.is_le(labelWidth + 2n,width),
    _ => repeat(left,'─',"") ++ label ++ repeat(width - left - labelWidth,'─',""),
    _ => Bool.pick(Unit -> String,Nat.is_le(indicatorWidth,width),
      _ => indicator ++ repeat(width - indicatorWidth,'─',""),
      _ => U.sliceByColumn(indicator,0n,width - U.visibleWidth(dots),True{}) ++ dots)(Unit{}))(Unit{})
def firstSegment(parts: List<&2,Segment>) -> String:
  match parts:
    case Nil{}: ""
    case Segment{text,_,_} <> _: text
def displayCursor(+text: String,column: Maybe<&2,Nat>,focused: Bool,pastes: List<&2,Paste>) -> String & Nat:
  match column:
    case None{}: (text,U.visibleWidth(text))
    case Some{+column}:
      +after = String.drop(text,column)
      +first = firstSegment(segmentWithMarkers(after,pastes))
      +marker = Bool.pick(String,focused,"\u{1b}_pi:c\u{7}","")
      (takePrefix(text,column,"") ++ marker ++ "\u{1b}[7m" ++ Bool.pick(String,String.is_empty(after)," ",first) ++ "\u{1b}[0m" ++ String.drop(after,String.length(first)),U.visibleWidth(text) + Bool.pick(Nat,String.is_empty(after),1n,0n))
def padDisplay(pair: String & Nat,+padding: Nat,+content: Nat) -> String:
  match pair:
    case Tuple{text,+width}: repeat(padding,' ',"") ++ text ++ repeat(content - width,' ',"") ++ repeat(Bool.pick(Nat,Nat.is_gt(width,content) && Nat.is_gt(padding,0n),padding - 1n,padding),' ' ,"")
def displayLines(parts: List<&2,LayoutLine>,+padding: Nat,+content: Nat,+focused: Bool,+pastes: List<&2,Paste>,reversed: List<&2,String>) -> List<&2,String>:
  match parts:
    case Nil{}: List.reverse(&2,String,reversed)
    case LayoutLine{text,_,_,_,column,_} <> rest: displayLines(rest,padding,content,focused,pastes,padDisplay(displayCursor(text,column,focused,pastes),padding,content) <> reversed)

def lastSegment(parts: List<&2,Segment>,previous: Maybe<&2,Segment>) -> Maybe<&2,Segment>:
  match parts:
    case Nil{}: previous
    case part <> rest: lastSegment(rest,Some{part})
def segmentMarker(value: Maybe<&2,Segment>) -> Maybe<&2,Marker>:
  match value:
    case None{}: None{}
    case Some{Segment{text,_,_}}: marker(text)
def shiftedPastes(pastes: List<&2,Paste>,+removed: Nat,+reversed: List<&2,Paste>) -> List<&2,Paste>:
  match pastes:
    case Nil{}: List.reverse(&2,Paste,reversed)
    case Paste{+id,+text} <> +rest:
      Bool.pick(Unit -> List<&2,Paste>,Nat.is_eq(id,removed),_ => shiftedPastes(rest,removed,reversed),_ => shiftedPastes(rest,removed,Paste{Bool.pick(Nat,Nat.is_gt(id,removed),id - 1n,id),text} <> reversed))(Unit{})
def renumberedMarker(id: Nat,original: String,parsed: Maybe<&2,Digits>) -> String:
  match parsed:
    case None{}: original
    case Some{Digits{_,_,suffix}}: "[paste #" ++ Nat.show(id) ++ suffix
def renumberStep(value: Maybe<&2,Marker>,+removed: Nat,text: String,reversed: String) -> ReplaceScan:
  match value text:
    case Some{Marker{+id,+matched,rest}} _: ReplaceScan{rest,prepend(Bool.pick(Unit -> String,Nat.is_gt(id,removed),_ => renumberedMarker(id - 1n,matched,decimal(String.drop(matched,8n),0n,"")),_ => matched)(Unit{}),reversed)}
    case None{} SCon{char,rest}: ReplaceScan{rest,SCon{char,reversed}}
    case None{} SNil{}: ReplaceScan{"",reversed}
@unsafe
def renumberScan(state: ReplaceScan,+removed: Nat) -> String:
  match state:
    case ReplaceScan{SNil{},reversed}: String.reverse(reversed)
    case ReplaceScan{+text,reversed}: renumberScan(renumberStep(marker(text),removed,text,reversed),removed)
def renumberLines(lines: List<&2,String>,+removed: Nat) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case text <> rest: renumberScan(ReplaceScan{text,""},removed) <> renumberLines(rest,removed)
def removePaste(value: Editing,removed: Maybe<&2,Marker>) -> Editing:
  match value removed:
    case Editing{EditorSnapshot{EditorState{lines,line,column},pastes,count},ring,action,stack,preferred,snapped} Some{Marker{+id,_,_}}:
      Editing{EditorSnapshot{EditorState{renumberLines(lines,id),line,column},shiftedPastes(pastes,id,Nil{}),count - 1n},ring,action,stack,preferred,snapped}
    case value None{}: value
def handleBackspaceEdit(+value: Editing) -> Editing:
  match value:
    case Editing{EditorSnapshot{EditorState{lines,line,column},pastes,_},_,_,_,_,_}:
      removePaste(deleteHorizontal(value,True{}),segmentMarker(lastSegment(segmentWithMarkers(takePrefix(textAt(lines,line),column,""),pastes),None{})))

# The coordinator owns only synchronization and outstanding request lifetimes.
# Immutable editor snapshots and provider/theme callbacks remain caller-owned.
# Advance one runtime lineage; dispose the final value before its callbacks.
type AutocompleteRequestOptions is Data: AutocompleteRequestOptions{force: Bool,explicitTab: Bool}
type AutocompleteContext is Data: AutocompleteContext{generation: Nat,snapshot: EditorState}
type AutocompleteEvent is Data:
  AutocompleteEvent{generation: Nat,snapshot: EditorState,options: AutocompleteRequestOptions,result: AC.ResultOf(Maybe<&2,AC.AutocompleteSuggestions>)}
type AutocompleteWork is Data: AutocompleteWork{controller: Abort.AbortController<Unit>,done: D.Deferred<Unit>}
type AutocompleteRuntime is Data:
  AutocompleteRuntime{current: Ref.Ref<AutocompleteContext>,completed: Ref.Ref<List<&2,AutocompleteEvent>>,latest: Maybe<&2,AutocompleteWork>}
def createAutocompleteRuntime(state: EditorState) -> IO(AutocompleteRuntime):
  do IO<AutocompleteRuntime>:
    current : Ref.Ref<AutocompleteContext> <- Ref.new(AutocompleteContext,AutocompleteContext{0n,state})
    completed : Ref.Ref<List<&2,AutocompleteEvent>> <- Ref.new(List<&2,AutocompleteEvent>,Nil{})
    return AutocompleteRuntime{current,completed,None{}}
def abortWork(value: Maybe<&2,AutocompleteWork>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{AutocompleteWork{controller,_}}:
      do IO<Unit>:
        aborted : Bool <- Abort.abort(Unit,controller,None{})
        return Unit{}
def retireWork(value: Maybe<&2,AutocompleteWork>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{AutocompleteWork{controller,+done}}:
      do IO<Unit>:
        D.result(Unit,done)
        Abort.dispose(Unit,controller)
        D.dispose(Unit,done)
def sameState(left: EditorState,right: EditorState) -> Bool:
  match left right:
    case EditorState{leftLines,leftLine,leftColumn} EditorState{rightLines,rightLine,rightColumn}:
      Nat.is_eq(leftLine,rightLine) && Nat.is_eq(leftColumn,rightColumn) && Strings.equal(String.join(leftLines,"\n"),String.join(rightLines,"\n"))
def requestCurrent(value: AutocompleteContext,generation: Nat,snapshot: EditorState) -> Bool:
  match value:
    case AutocompleteContext{current,state}: Nat.is_eq(current,generation) && sameState(state,snapshot)
def invokeRender(value: Maybe<&2,C.Callback<Unit,Unit>>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: C.call(Unit,Unit,callback,Unit{})
def publishAutocomplete(ready: Bool,completed: Ref.Ref<List<&2,AutocompleteEvent>>,event: AutocompleteEvent,render: Maybe<&2,C.Callback<Unit,Unit>>) -> IO(Unit):
  match ready:
    case False{}: IO.pure(Unit,Unit{})
    case True{}:
      do IO<Unit>:
        saved : Unit <- Ref.modify(List<&2,AutocompleteEvent>,Unit,completed,events => (event <> events,Unit{}))
        invokeRender(render)
def finishSuggestions(+current: Ref.Ref<AutocompleteContext>,completed: Ref.Ref<List<&2,AutocompleteEvent>>,+generation: Nat,+snapshot: EditorState,options: AutocompleteRequestOptions,signal: Abort.AbortSignal<Unit>,render: Maybe<&2,C.Callback<Unit,Unit>>,result: AC.ResultOf(Maybe<&2,AC.AutocompleteSuggestions>)) -> IO(Unit):
  do IO<Unit>:
    live : AutocompleteContext <- Ref.read(AutocompleteContext,current)
    aborted : Bool <- Abort.aborted(Unit,signal)
    publishAutocomplete(Bool.not(aborted) && requestCurrent(live,generation,snapshot),completed,AutocompleteEvent{generation,snapshot,options,result},render)
def runSuggestions(provider: AC.AutocompleteProvider,+snapshot: EditorState,+options: AutocompleteRequestOptions,+signal: Abort.AbortSignal<Unit>) -> IO(AC.ResultOf(Maybe<&2,AC.AutocompleteSuggestions>)):
  match provider snapshot options:
    case AC.AutocompleteProvider{callback,_,_,_} EditorState{lines,line,column} AutocompleteRequestOptions{force,_}: C.call(AC.SuggestionRequest,AC.ResultOf(Maybe<&2,AC.AutocompleteSuggestions>),callback,AC.SuggestionRequest{lines,line,column,AC.Options{Some{signal},force}})
def startedAutocomplete(context: AutocompleteContext,+generation: Nat,+current: Ref.Ref<AutocompleteContext>,completed: Ref.Ref<List<&2,AutocompleteEvent>>,provider: AC.AutocompleteProvider,+options: AutocompleteRequestOptions,+signal: Abort.AbortSignal<Unit>,render: Maybe<&2,C.Callback<Unit,Unit>>) -> IO(Unit):
  match context:
    case AutocompleteContext{live,+snapshot}:
      Bool.pick(Unit -> IO(Unit),Nat.is_eq(live,generation),
        _ => do IO<Unit>:
          result : AC.ResultOf(Maybe<&2,AC.AutocompleteSuggestions>) <- runSuggestions(provider,snapshot,options,signal)
          finishSuggestions(current,completed,generation,snapshot,options,signal,render,result),
        _ => IO.pure(Unit,Unit{}))(Unit{})
def autocompleteAfterDelay(waited: Result<&2,&2,Abort.AbortReason<Unit>,Unit>,generation: Nat,+current: Ref.Ref<AutocompleteContext>,completed: Ref.Ref<List<&2,AutocompleteEvent>>,provider: AC.AutocompleteProvider,options: AutocompleteRequestOptions,signal: Abort.AbortSignal<Unit>,render: Maybe<&2,C.Callback<Unit,Unit>>) -> IO(Unit):
  match waited:
    case Fail{_}: IO.pure(Unit,Unit{})
    case Done{_}:
      do IO<Unit>:
        context : AutocompleteContext <- Ref.read(AutocompleteContext,current)
        startedAutocomplete(context,generation,current,completed,provider,options,signal,render)
def waitDebounce(milliseconds: U32,signal: Abort.AbortSignal<Unit>) -> IO(Result<&2,&2,Abort.AbortReason<Unit>,Unit>):
  match milliseconds:
    case 0: Abort.throwIfAborted(Unit,signal)
    case milliseconds: Sleep.sleep(Unit,milliseconds,signal)
def autocompleteWorker(previous: Maybe<&2,AutocompleteWork>,done: D.Deferred<Unit>,generation: Nat,current: Ref.Ref<AutocompleteContext>,completed: Ref.Ref<List<&2,AutocompleteEvent>>,provider: AC.AutocompleteProvider,options: AutocompleteRequestOptions,+signal: Abort.AbortSignal<Unit>,milliseconds: U32,render: Maybe<&2,C.Callback<Unit,Unit>>) -> IO(Unit):
  do IO<Unit>:
    waited : Result<&2,&2,Abort.AbortReason<Unit>,Unit> <- waitDebounce(milliseconds,signal)
    retireWork(previous)
    autocompleteAfterDelay(waited,generation,current,completed,provider,options,signal,render)
    settled : Bool <- D.resolve(Unit,done,Unit{})
    return Unit{}
def nextContext(context: AutocompleteContext,state: EditorState) -> AutocompleteContext & Nat:
  match context:
    case AutocompleteContext{+generation,_}: (AutocompleteContext{generation + 1n,state},generation + 1n)
def keepGeneration(context: AutocompleteContext,state: EditorState) -> AutocompleteContext & Unit:
  match context:
    case AutocompleteContext{generation,_}: (AutocompleteContext{generation,state},Unit{})
def synchronizeAutocomplete(runtime: AutocompleteRuntime,state: EditorState) -> IO(Unit):
  match runtime:
    case AutocompleteRuntime{current,_,_}:
      do IO<Unit>:
        changed : Unit <- Ref.modify(AutocompleteContext,Unit,current,context => keepGeneration(context,state))
        return Unit{}
def cancelAutocompleteRequest(runtime: AutocompleteRuntime,state: EditorState) -> IO(Unit):
  match runtime:
    case AutocompleteRuntime{current,_,latest}:
      do IO<Unit>:
        generation : Nat <- Ref.modify(AutocompleteContext,Nat,current,context => nextContext(context,state))
        abortWork(latest)
def requestAutocomplete(runtime: AutocompleteRuntime,state: EditorState,provider: AC.AutocompleteProvider,options: AutocompleteRequestOptions,milliseconds: U32,render: Maybe<&2,C.Callback<Unit,Unit>>) -> IO(AutocompleteRuntime):
  match runtime:
    case AutocompleteRuntime{+current,+completed,+latest}:
      do IO<AutocompleteRuntime>:
        generation : Nat <- Ref.modify(AutocompleteContext,Nat,current,context => nextContext(context,state))
        abortWork(latest)
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        +done : D.Deferred<Unit> <- D.new(Unit)
        IO.spawn(Unit,autocompleteWorker(latest,done,generation,current,completed,provider,options,Abort.signal(Unit,controller),milliseconds,render))
        return AutocompleteRuntime{current,completed,Some{AutocompleteWork{controller,done}}}
def takeAutocompleteEvents(runtime: AutocompleteRuntime) -> IO(List<&2,AutocompleteEvent>):
  match runtime:
    case AutocompleteRuntime{_,completed,_}: Ref.modify(List<&2,AutocompleteEvent>,List<&2,AutocompleteEvent>,completed,events => (Nil{},List.reverse(&2,AutocompleteEvent,events)))
def disposeAutocompleteRuntime(runtime: AutocompleteRuntime) -> IO(Unit):
  match runtime:
    case AutocompleteRuntime{current,completed,+latest}:
      do IO<Unit>:
        abortWork(latest)
        retireWork(latest)
        context : AutocompleteContext <- Ref.dispose(AutocompleteContext,current)
        events : List<&2,AutocompleteEvent> <- Ref.dispose(List<&2,AutocompleteEvent>,completed)
        return Unit{}

type EditorTheme is Data: EditorTheme{borderColor: C.Callback<String,String>,selectList: Select.SelectListTheme}
type EditorOptions is Data: EditorOptions{paddingX: Nat,autocompleteMaxVisible: Nat}
type EditorAction is Data:
  Interrupt{text: String}
  Clear{}
  Exit{}
  FollowUp{text: String}
  Dequeue{text: String}
  ExpandTools{}
  ToggleThinking{}
type EditorCallbacks is Data:
  EditorCallbacks{onChange: Maybe<&2,C.Callback<String,Unit>>,onSubmit: Maybe<&2,C.Callback<String,Unit>>,requestRender: Maybe<&2,C.Callback<Unit,Unit>>,onAction: Maybe<&2,C.Callback<EditorAction,Unit>>}
type EditorSettings is Data: EditorSettings{theme: EditorTheme,options: EditorOptions,callbacks: EditorCallbacks,focused: Bool,disableSubmit: Bool}
type Geometry is Data: Geometry{lastWidth: Nat,renderedVisibleLineCount: Nat,renderedAutocompleteHeight: Nat,scrollOffset: Nat}
type History is Data: History{entries: List<&2,String>,index: Maybe<&2,Nat>,draft: Maybe<&2,EditorState>}
type AutocompleteUi is Data: AutocompleteUi{list: Select.SelectList,prefix: String,force: Bool}
type AutocompleteState is Data:
  AutocompleteState{provider: Maybe<&2,AC.AutocompleteProvider>,runtime: AutocompleteRuntime,ui: Maybe<&2,AutocompleteUi>}
type PasteInput is Data: PasteInput{buffer: String,inside: Bool}
type Editor is Data:
  Editor{editing: Editing,history: History,geometry: Geometry,settings: EditorSettings,autocomplete: AutocompleteState,pasteInput: PasteInput,jumpMode: Maybe<&2,Bool>}
def defaultOptions() -> EditorOptions: EditorOptions{0n,5n}
def checkedOptions(options: EditorOptions) -> EditorOptions:
  match options:
    case EditorOptions{padding,maximum}: EditorOptions{padding,Nat.max(3n,Nat.min(20n,maximum))}
def new(theme: EditorTheme,options: Maybe<&2,EditorOptions>) -> IO(Editor):
  do IO<Editor>:
    runtime : AutocompleteRuntime <- createAutocompleteRuntime(emptyState())
    return Editor{createEditing(),History{Nil{},None{},None{}},Geometry{80n,1n,0n,0n},EditorSettings{theme,checkedOptions(Maybe.default(&2,EditorOptions,options,defaultOptions())),EditorCallbacks{None{},None{},None{},None{}},False{},False{}},AutocompleteState{None{},runtime,None{}},PasteInput{"",False{}},None{}}
def getText(value: Editor) -> String:
  match value:
    case Editor{editing,_,_,_,_,_,_}: editingText(editing)
def getExpandedText(value: Editor) -> String:
  match value:
    case Editor{editing,_,_,_,_,_,_}: expandedEditingText(editing)
def getLines(value: Editor) -> List<&2,String>:
  match value:
    case Editor{Editing{EditorSnapshot{EditorState{lines,_,_},_,_},_,_,_,_,_},_,_,_,_,_,_}: lines
def getCursor(value: Editor) -> Nat & Nat:
  match value:
    case Editor{Editing{EditorSnapshot{EditorState{_,line,column},_,_},_,_,_,_,_},_,_,_,_,_,_}: (line,column)
def getPaddingX(value: Editor) -> Nat:
  match value:
    case Editor{_,_,_,EditorSettings{_,EditorOptions{padding,_},_,_,_},_,_,_}: padding
def getAutocompleteMaxVisible(value: Editor) -> Nat:
  match value:
    case Editor{_,_,_,EditorSettings{_,EditorOptions{_,maximum},_,_,_},_,_,_}: maximum
def setCallbacks(value: Editor,callbacks: EditorCallbacks) -> Editor:
  match value:
    case Editor{editing,history,geometry,EditorSettings{theme,options,_,focused,disabled},autocomplete,paste,jump}: Editor{editing,history,geometry,EditorSettings{theme,options,callbacks,focused,disabled},autocomplete,paste,jump}
def setFocused(value: Editor,focused: Bool) -> Editor:
  match value:
    case Editor{editing,history,geometry,EditorSettings{theme,options,callbacks,_,disabled},autocomplete,paste,jump}: Editor{editing,history,geometry,EditorSettings{theme,options,callbacks,focused,disabled},autocomplete,paste,jump}
def setDisableSubmit(value: Editor,disabled: Bool) -> Editor:
  match value:
    case Editor{editing,history,geometry,EditorSettings{theme,options,callbacks,focused,_},autocomplete,paste,jump}: Editor{editing,history,geometry,EditorSettings{theme,options,callbacks,focused,disabled},autocomplete,paste,jump}
def invalidate(value: Editor) -> Editor: value
def editingState(value: Editing) -> EditorState:
  match value:
    case Editing{EditorSnapshot{state,_,_},_,_,_,_,_}: state
def changedCallback(value: Maybe<&2,C.Callback<String,Unit>>,text: String) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: C.call(String,Unit,callback,text)
def clearBrowsing(value: History) -> History:
  match value:
    case History{entries,_,_}: History{entries,None{},None{}}
def replaceEditing(value: Editor,editing: Editing,leaveHistory: Bool,resetScroll: Bool) -> Editor:
  match value:
    case Editor{_,+history,Geometry{width,visible,height,+scroll},settings,autocomplete,paste,jump}: Editor{editing,Bool.pick(History,leaveHistory,clearBrowsing(history),history),Geometry{width,visible,height,Bool.pick(Nat,resetScroll,0n,scroll)},settings,autocomplete,paste,jump}
def clearAutocompleteUi(value: Editor) -> Editor:
  match value:
    case Editor{editing,history,geometry,settings,AutocompleteState{provider,runtime,_},paste,jump}: Editor{editing,history,geometry,settings,AutocompleteState{provider,runtime,None{}},paste,jump}
def cancelAutocomplete(+value: Editor) -> IO(Editor):
  match value:
    case Editor{editing,_,_,_,AutocompleteState{_,runtime,_},_,_}:
      do IO<Editor>:
        cancelAutocompleteRequest(runtime,editingState(editing))
        return clearAutocompleteUi(value)
def notifyChange(+value: Editor) -> IO(Editor):
  match value:
    case Editor{+editing,_,_,EditorSettings{_,_,EditorCallbacks{change,_,_,_},_,_},AutocompleteState{_,runtime,_},_,_}:
      do IO<Editor>:
        synchronizeAutocomplete(runtime,editingState(editing))
        changedCallback(change,editingText(editing))
        return value
def setText(+value: Editor,text: String) -> IO(Editor):
  match value:
    case Editor{editing,_,_,_,_,_,_}:
      do IO<Editor>:
        next : Editor <- cancelAutocomplete(replaceEditing(value,setTextEdit(editing,text),True{},True{}))
        notifyChange(next)
def insertTextAtCursor(+value: Editor,+text: String) -> IO(Editor):
  match value:
    case Editor{editing,_,_,_,_,_,_}:
      Bool.pick(Unit -> IO(Editor),String.is_empty(text),_ => IO.pure(Editor,value),_ => do IO<Editor>:
        next : Editor <- cancelAutocomplete(replaceEditing(value,insertTextEdit(editing,text),True{},False{}))
        notifyChange(next))(Unit{})
def dispose(value: Editor) -> IO(Unit):
  match value:
    case Editor{_,_,_,_,AutocompleteState{_,runtime,_},_,_}: disposeAutocompleteRuntime(runtime)
def settingsOptions(value: Editor,options: EditorOptions) -> Editor:
  match value:
    case Editor{editing,history,geometry,EditorSettings{theme,_,callbacks,focused,disabled},autocomplete,paste,jump}: Editor{editing,history,geometry,EditorSettings{theme,options,callbacks,focused,disabled},autocomplete,paste,jump}
def requestRender(+value: Editor) -> IO(Editor):
  match value:
    case Editor{_,_,_,EditorSettings{_,_,EditorCallbacks{_,_,render,_},_,_},_,_,_}:
      do IO<Editor>:
        invokeRender(render)
        return value
def setPaddingX(+value: Editor,+padding: Nat) -> IO(Editor):
  Bool.pick(Unit -> IO(Editor),Nat.is_eq(getPaddingX(value),padding),_ => IO.pure(Editor,value),_ => requestRender(settingsOptions(value,EditorOptions{padding,getAutocompleteMaxVisible(value)})))(Unit{})
def setAutocompleteMaxVisible(+value: Editor,maximum: Nat) -> IO(Editor):
  +maximum = Nat.max(3n,Nat.min(20n,maximum))
  Bool.pick(Unit -> IO(Editor),Nat.is_eq(getAutocompleteMaxVisible(value),maximum),_ => IO.pure(Editor,value),_ => requestRender(settingsOptions(value,EditorOptions{getPaddingX(value),maximum})))(Unit{})
def withProvider(value: Editor,provider: AC.AutocompleteProvider) -> Editor:
  match value:
    case Editor{editing,history,geometry,settings,AutocompleteState{_,runtime,_},paste,jump}: Editor{editing,history,geometry,settings,AutocompleteState{Some{provider},runtime,None{}},paste,jump}
def setAutocompleteProvider(value: Editor,provider: AC.AutocompleteProvider) -> IO(Editor):
  do IO<Editor>:
    +value : Editor <- cancelAutocomplete(value)
    return withProvider(value,provider)
def isShowingAutocomplete(value: Editor) -> Bool:
  match value:
    case Editor{_,_,_,_,AutocompleteState{_,_,ui},_,_}: Bool.not(Maybe.is_none(&2,AutocompleteUi,ui))

type RenderPlan is Data: RenderPlan{lines: List<&2,String>,top: String,bottom: String,geometry: Geometry,padding: Nat,contentWidth: Nat}
def scrollForCursor(+cursor: Nat,+scroll: Nat,+maximum: Nat,+total: Nat) -> Nat:
  Nat.min(Bool.pick(Nat,Nat.is_lt(cursor,scroll),cursor,Bool.pick(Nat,Nat.is_ge(cursor,scroll + maximum),cursor - maximum + 1n,scroll)),total - maximum)
def renderPlan(editing: Editing,options: EditorOptions,geometry: Geometry,+focused: Bool,+width: Nat,rows: Nat) -> RenderPlan:
  match editing options geometry:
    case Editing{EditorSnapshot{EditorState{lines,line,column},+pastes,_},_,_,_,_,_} EditorOptions{padding,_} Geometry{_,_,_,scroll}:
      +padding = Nat.min(padding,(width - 1n) / 2n)
      +content = Nat.max(1n,width - padding * 2n)
      +layoutWidth = Nat.max(1n,content - Bool.pick(Nat,Nat.is_eq(padding,0n),1n,0n))
      +maximum = Nat.max(5n,rows * 3n / 10n)
      +layout = layoutLines(lines,0n,line,column,layoutWidth,pastes,Nil{})
      +total = List.length(&2,LayoutLine,layout)
      +scroll = scrollForCursor(cursorLayoutIndex(layout,0n),scroll,maximum,total)
      +visible = List.take(&2,LayoutLine,List.drop(&2,LayoutLine,layout,scroll),maximum)
      +count = List.length(&2,LayoutLine,visible)
      +below = total - scroll - count
      RenderPlan{displayLines(visible,padding,content,focused,pastes,Nil{}),Bool.pick(Unit -> String,Nat.is_gt(scroll,0n),_ => scrollBorder("↑",scroll,width),_ => repeat(width,'─',""))(Unit{}),Bool.pick(Unit -> String,Nat.is_gt(below,0n),_ => scrollBorder("↓",below,width),_ => repeat(width,'─',""))(Unit{}),Geometry{layoutWidth,count,0n,scroll},padding,content}
def autocompleteLines(value: Maybe<&2,AutocompleteUi>,width: Nat) -> IO(List<&2,String>):
  match value:
    case None{}: IO.pure(List<&2,String>,Nil{})
    case Some{AutocompleteUi{list,_,_}}: Select.render(list,width)
def padAutocomplete(lines: List<&2,String>,+padding: Nat,+width: Nat) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case +line <> rest: (repeat(padding,' ',"") ++ line ++ repeat(width - U.visibleWidth(line) + padding,' ',"")) <> padAutocomplete(rest,padding,width)
def rendered(value: Editor,geometry: Geometry,height: Nat) -> Editor:
  match value geometry:
    case Editor{editing,history,_,settings,autocomplete,paste,jump} Geometry{width,visible,_,scroll}: Editor{editing,history,Geometry{width,visible,height,scroll},settings,autocomplete,paste,jump}
def paintPlan(+value: Editor,plan: RenderPlan,+border: C.Callback<String,String>,ui: Maybe<&2,AutocompleteUi>) -> IO(Editor & List<&2,String>):
  match plan:
    case RenderPlan{lines,top,bottom,geometry,+padding,+content}:
      do IO<Editor & List<&2,String>>:
        top : String <- C.call(String,String,border,top)
        bottom : String <- C.call(String,String,border,bottom)
        +extra : List<&2,String> <- autocompleteLines(ui,content)
        return (rendered(value,geometry,List.length(&2,String,extra)),top <> List.append(&2,String,lines,bottom <> padAutocomplete(extra,padding,content)))
def render(+value: Editor,width: Nat,terminalRows: Nat) -> IO(Editor & List<&2,String>):
  match value:
    case Editor{editing,_,geometry,EditorSettings{EditorTheme{border,_},options,_,focused,_},AutocompleteState{_,_,ui},_,_}: paintPlan(value,renderPlan(editing,options,geometry,focused,width,terminalRows),border,ui)

def historyAdded(value: History,+text: String) -> History:
  match value:
    case History{+entries,index,draft}:
      +same = Strings.equal(text,textAt(entries,0n))
      History{Bool.pick(List<&2,String>,String.is_empty(text) || same,entries,List.take(&2,String,text <> entries,100n)),index,draft}
def addToHistory(value: Editor,text: String) -> Editor:
  match value:
    case Editor{editing,history,geometry,settings,autocomplete,paste,jump}: Editor{editing,historyAdded(history,Text.trim(text)),geometry,settings,autocomplete,paste,jump}
def browsing(value: Editor,history: History) -> Editor:
  match value:
    case Editor{editing,_,geometry,settings,autocomplete,paste,jump}: Editor{editing,history,geometry,settings,autocomplete,paste,jump}
def historyDestination(index: Maybe<&2,Nat>,up: Bool) -> Maybe<&2,Nat>:
  match index up:
    case None{} True{}: Some{0n}
    case Some{index} True{}: Some{index + 1n}
    case Some{Zero{}} False{}: None{}
    case Some{Succ{index}} False{}: Some{index}
    case None{} False{}: None{}
def historyValid(index: Maybe<&2,Nat>,length: Nat) -> Bool:
  match index:
    case None{}: True{}
    case Some{index}: Nat.is_lt(index,length)
def historyState(entries: List<&2,String>,target: Maybe<&2,Nat>,draft: Maybe<&2,EditorState>,up: Bool) -> EditorState:
  match target:
    case None{}: Maybe.default(&2,EditorState,draft,emptyState())
    case Some{index}: fromText(textAt(entries,index),up)
def historyStep(+value: Editor,+up: Bool) -> IO(Editor):
  match value:
    case Editor{+editing,History{+entries,+index,+draft},_,_,_,_,_}:
      +target = historyDestination(index,up)
      +entering = Maybe.is_none(&2,Nat,index)
      +saved = Bool.pick(Maybe<&2,EditorState>,entering,Some{editingState(editing)},draft)
      Bool.pick(Unit -> IO(Editor),List.is_empty(&2,String,entries) || (entering && Bool.not(up)) || Bool.not(historyValid(target,List.length(&2,String,entries))),
        _ => IO.pure(Editor,replaceEditing(value,resetAction(editing),False{},False{})),
        _ => notifyChange(browsing(replaceEditing(value,changed(Bool.pick(Editing,entering,pushUndoSnapshot(editing),editing),historyState(entries,target,saved,up),NoAction{}),False{},True{}),History{entries,target,Bool.pick(Maybe<&2,EditorState>,Maybe.is_none(&2,Nat,target),None{},saved)})))(Unit{})

type WordContext<-Context: Data> is Data: WordContext{context: Context,pastes: List<&2,Paste>}
type WordPiece is Data: WordPiece{text: String,index: Nat,isWordLike: Bool}
def wordPieces(parts: List<&2,Word.Segment>,+index: Nat,reversed: List<&2,WordPiece>) -> List<&2,WordPiece>:
  match parts:
    case Nil{}: List.reverse(&2,WordPiece,reversed)
    case Word.Segment{+text,word} <> rest: wordPieces(rest,index + String.length(text),WordPiece{text,index,word} <> reversed)
def skipWords(parts: List<&2,WordPiece>,+until: Nat) -> List<&2,WordPiece>:
  match parts:
    case Nil{}: Nil{}
    case WordPiece{+text,+index,+word} <> +rest: Bool.pick(Unit -> List<&2,WordPiece>,Nat.is_lt(index,until),_ => skipWords(rest,until),_ => WordPiece{text,index,word} <> rest)(Unit{})
type WordMerge is Data: WordMerge{text: String,parts: List<&2,WordPiece>,reversed: List<&2,Word.Segment>}
def mergeWordMarker(value: Maybe<&2,Marker>,text: String,parts: List<&2,WordPiece>,reversed: List<&2,Word.Segment>) -> WordMerge:
  match value parts:
    case _ Nil{}: WordMerge{text,Nil{},reversed}
    case Some{Marker{_,+value,restText}} WordPiece{_,+index,_} <> rest: WordMerge{restText,skipWords(rest,index + String.length(value)),Word.Segment{value,False{}} <> reversed}
    case None{} WordPiece{+value,_,word} <> rest: WordMerge{String.drop(text,String.length(value)),rest,Word.Segment{value,word} <> reversed}
@unsafe
def mergeWords(state: WordMerge,+pastes: List<&2,Paste>) -> List<&2,Word.Segment>:
  match state:
    case WordMerge{_,Nil{},reversed}: List.reverse(&2,Word.Segment,reversed)
    case WordMerge{+text,parts,reversed}: mergeWords(mergeWordMarker(validMarker(marker(text),pastes),text,parts,reversed),pastes)
def mergedWords(result: Word.ResultOf(List<&2,Word.Segment>),text: String,pastes: List<&2,Paste>) -> Word.ResultOf(List<&2,Word.Segment>):
  match result:
    case Fail{error}: Fail{error}
    case Done{parts}: Done{mergeWords(WordMerge{text,wordPieces(parts,0n,Nil{}),Nil{}},pastes)}
def editorWordSegmentsImpl(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),context: WordContext<Context>,+text: String) -> Word.ResultOf(List<&2,Word.Segment>):
  match context:
    case WordContext{context,pastes}: mergedWords(segment(context,text),text,pastes)
def editorWordSegments(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),context: WordContext<Context>,text: String) -> Word.ResultOf(List<&2,Word.Segment>):
  editorWordSegmentsImpl(~Context,~segment,context,text)
def atomicWord(~Context: Data,context: WordContext<Context>,text: String) -> Bool:
  Bool.not(Maybe.is_none(&2,Marker,marker(text)))
def wordResult(+value: Editing,+backward: Bool,remove: Bool,result: Word.ResultOf(Nat)) -> Word.ResultOf(Editing):
  match value result:
    case _ Fail{error}: Fail{error}
    case Editing{EditorSnapshot{EditorState{+lines,+line,+column},_,_},_,_,_,_,_} Done{+target}:
      +start = cursorOffset(lines,line,Nat.min(column,target),0n)
      +end = cursorOffset(lines,line,Nat.max(column,target),0n)
      Done{Bool.pick(Editing,remove,killRange(value,start,end,backward),moveTo(value,line,target))}
def wordEdit(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),+context: Context,+value: Editing,+backward: Bool,+remove: Bool) -> Word.ResultOf(Editing):
  match value:
    case Editing{EditorSnapshot{EditorState{+lines,+line,+column},+pastes,_},_,_,_,_,_}:
      +text = textAt(lines,line)
      Bool.pick(Unit -> Word.ResultOf(Editing),Bool.pick(Bool,backward,Nat.is_eq(column,0n),Nat.is_ge(column,String.length(text))),
        _ => Done{Bool.pick(Editing,remove,killLine(value,backward),moveHorizontal(value,backward))},
        _ => wordResult(value,backward,remove,Bool.pick(Unit -> Word.ResultOf(Nat),backward,
          _ => Word.findWordBackwardChecked(~WordContext<Context>,~editorWordSegments(~Context,~segment),~atomicWord(~Context),WordContext{context,pastes},text,column),
          _ => Word.findWordForwardChecked(~WordContext<Context>,~editorWordSegments(~Context,~segment),~atomicWord(~Context),WordContext{context,pastes},text,column))(Unit{})))(Unit{})

type Error is Data: WordError{cause: Word.Error} CompletionError{cause: AC.Error} InvalidCompletion{}
def ResultOf(-A: Data) -> Data: Result<&2,&2,Error,A>
def stateBefore(state: EditorState) -> String:
  match state:
    case EditorState{lines,line,column}: takePrefix(textAt(lines,line),column,"")
def symbolIn(chars: List<&2,Char>,+wanted: Char) -> Bool:
  match chars:
    case Nil{}: False{}
    case char <> +rest: Bool.pick(Unit -> Bool,Char.is_eq(char,wanted),_ => True{},_ => symbolIn(rest,wanted))(Unit{})
def triggerCharacters(chars: List<&2,Char>,+result: List<&2,Char>) -> List<&2,Char>:
  match chars:
    case Nil{}: result
    case +char <> rest: triggerCharacters(rest,Bool.pick(List<&2,Char>,Char.is_eq(char,'/') || Word.whitespace(SCon{char,""}) || symbolIn(result,char),result,List.append(&2,Char,result,[char])))
def providerTriggers(provider: Maybe<&2,AC.AutocompleteProvider>) -> List<&2,Char>:
  match provider:
    case None{}: ['@','#']
    case Some{AC.AutocompleteProvider{_,_,_,chars}}: triggerCharacters(chars,['@','#'])
def tokenTail(text: String) -> Bool: Bool.not(Word.whitespace(text))
def debounceTail(char: Char,+text: String) -> Bool:
  match char text:
    case '@' SCon{'"',rest}: Bool.not(String.contains(rest,"\""))
    case _ text: tokenTail(text)
def symbolContext(text: String,+chars: List<&2,Char>,+boundary: Bool,+debounce: Bool) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Bool,boundary && symbolIn(chars,char) && Bool.pick(Bool,debounce,debounceTail(char,rest),tokenTail(rest)),
        _ => True{},
        _ => symbolContext(rest,chars,Bool.pick(Bool,debounce,Char.is_eq(char,' ') || Char.is_eq(char,'\t'),Word.whitespace(SCon{char,""})),debounce))(Unit{})
def slashContext(state: EditorState) -> Bool:
  match state:
    case EditorState{lines,+line,column}: Nat.is_eq(line,0n) && AC.starts(Text.trimStart(takePrefix(textAt(lines,line),column,"")),"/")
def autocompleteDelay(value: Editor,options: AutocompleteRequestOptions) -> U32:
  match value options:
    case Editor{editing,_,_,_,AutocompleteState{provider,_,_},_,_} AutocompleteRequestOptions{force,tab}: Bool.pick(U32,Bool.not(force || tab) && symbolContext(stateBefore(editingState(editing)),providerTriggers(provider),True{},True{}),20,0)
def setRuntime(value: Editor,runtime: AutocompleteRuntime) -> Editor:
  match value:
    case Editor{editing,history,geometry,settings,AutocompleteState{provider,_,ui},paste,jump}: Editor{editing,history,geometry,settings,AutocompleteState{provider,runtime,ui},paste,jump}
def shouldForce(provider: AC.AutocompleteProvider,state: EditorState,options: AutocompleteRequestOptions) -> IO(AC.ResultOf(Bool)):
  match provider state options:
    case AC.AutocompleteProvider{_,_,Some{callback},_} EditorState{lines,line,column} AutocompleteRequestOptions{True{},_}: C.call(AC.CursorRequest,AC.ResultOf(Bool),callback,AC.CursorRequest{lines,line,column})
    case _ _ _: IO.pure(AC.ResultOf(Bool),Done{True{}})
def startAllowed(+value: Editor,+provider: AC.AutocompleteProvider,+options: AutocompleteRequestOptions,allowed: AC.ResultOf(Bool)) -> IO(ResultOf(Editor)):
  match value allowed:
    case _ Fail{error}: IO.pure(ResultOf(Editor),Fail{CompletionError{error}})
    case _ Done{False{}}: IO.pure(ResultOf(Editor),Done{value})
    case Editor{editing,_,_,EditorSettings{_,_,EditorCallbacks{_,_,redraw,_},_,_},AutocompleteState{_,runtime,_},_,_} Done{True{}}:
      do IO<ResultOf(Editor)>:
        runtime : AutocompleteRuntime <- requestAutocomplete(runtime,editingState(editing),provider,options,autocompleteDelay(value,options),redraw)
        return Done{setRuntime(value,runtime)}
def triggerAutocomplete(+value: Editor,+options: AutocompleteRequestOptions) -> IO(ResultOf(Editor)):
  match value:
    case Editor{_,_,_,_,AutocompleteState{None{},_,_},_,_}: IO.pure(ResultOf(Editor),Done{value})
    case Editor{editing,_,_,_,AutocompleteState{Some{+provider},_,_},_,_}:
      do IO<ResultOf(Editor)>:
        allowed : AC.ResultOf(Bool) <- shouldForce(provider,editingState(editing),options)
        startAllowed(value,provider,options,allowed)
def updateAutocomplete(+value: Editor) -> IO(ResultOf(Editor)):
  match value:
    case Editor{_,_,_,_,AutocompleteState{_,_,Some{AutocompleteUi{_,_,force}}},_,_}: triggerAutocomplete(value,AutocompleteRequestOptions{force,False{}})
    case _: IO.pure(ResultOf(Editor),Done{value})
def tabCompletion(+value: Editor) -> IO(ResultOf(Editor)):
  match value:
    case Editor{editing,_,_,_,_,_,_}:
      +state = editingState(editing)
      triggerAutocomplete(value,AutocompleteRequestOptions{Bool.not(slashContext(state) && Bool.not(String.contains(Text.trimStart(stateBefore(state))," "))),True{}})
def selectedItems(items: List<&2,AC.AutocompleteItem>) -> List<&2,Select.SelectItem>:
  match items:
    case Nil{}: Nil{}
    case AC.AutocompleteItem{value,label,description} <> rest: Select.SelectItem{value,label,description} <> selectedItems(rest)
def bestMatch(items: List<&2,AC.AutocompleteItem>,+prefix: String,+index: Nat,+first: Maybe<&2,Nat>) -> Maybe<&2,Nat>:
  match items:
    case Nil{}: first
    case AC.AutocompleteItem{+value,_,_} <> +rest:
      Bool.pick(Unit -> Maybe<&2,Nat>,Strings.equal(value,prefix),_ => Some{index},_ => bestMatch(rest,prefix,index + 1n,Bool.pick(Maybe<&2,Nat>,Maybe.is_none(&2,Nat,first) && AC.starts(value,prefix),Some{index},first)))(Unit{})
def autocompleteList(+items: List<&2,AC.AutocompleteItem>,+prefix: String,maximum: Nat,theme: Select.SelectListTheme) -> Select.SelectList:
  +layout = Bool.pick(Maybe<&2,Select.SelectListLayoutOptions>,AC.starts(prefix,"/"),Some{Select.SelectListLayoutOptions{Some{12n},Some{32n},None{}}},None{})
  Select.setSelectedIndex(Select.new(selectedItems(items),maximum,theme,layout),Bool.pick(Nat,String.is_empty(prefix),0n,Maybe.default(&2,Nat,bestMatch(items,prefix,0n,None{}),0n)))
def applyAutocompleteSuggestions(value: Editor,suggestions: AC.AutocompleteSuggestions,force: Bool) -> Editor:
  match value suggestions:
    case Editor{editing,history,geometry,EditorSettings{EditorTheme{border,+listTheme},EditorOptions{padding,+maximum},callbacks,focused,disabled},AutocompleteState{provider,runtime,_},paste,jump} AC.AutocompleteSuggestions{items,+prefix}:
      Editor{editing,history,geometry,EditorSettings{EditorTheme{border,listTheme},EditorOptions{padding,maximum},callbacks,focused,disabled},AutocompleteState{provider,runtime,Some{AutocompleteUi{autocompleteList(items,prefix,maximum,listTheme),prefix,force}}},paste,jump}
def validCursor(value: AC.ResultOf(AC.LineParts)) -> Bool:
  match value:
    case Fail{_}: False{}
    case Done{_}: True{}
def validCompletion(value: AC.Completion) -> Bool:
  match value:
    case AC.Completion{lines,line,column}:
      match lines:
        case Nil{}: False{}
        case lines: validCursor(AC.view(lines,line,column))
def completedEditing(+value: Editor,result: AC.ResultOf(AC.Completion)) -> ResultOf(Editor):
  match value result:
    case _ Fail{error}: Fail{CompletionError{error}}
    case Editor{editing,_,_,_,_,_,_} Done{AC.Completion{+lines,+line,+column}}:
      Bool.pick(ResultOf(Editor),validCompletion(AC.Completion{lines,line,column}),Done{replaceEditing(value,changed(pushUndoSnapshot(editing),EditorState{lines,line,column},NoAction{}),False{},False{})},Fail{InvalidCompletion{}})
def completeItem(+value: Editor,item: AC.AutocompleteItem,prefix: String) -> IO(ResultOf(Editor)):
  match value:
    case Editor{_,_,_,_,AutocompleteState{None{},_,_},_,_}: IO.pure(ResultOf(Editor),Done{value})
    case Editor{Editing{EditorSnapshot{EditorState{lines,line,column},_,_},_,_,_,_,_},_,_,_,AutocompleteState{Some{AC.AutocompleteProvider{_,callback,_,_}},_,_},_,_}:
      do IO<ResultOf(Editor)>:
        result : AC.ResultOf(AC.Completion) <- C.call(AC.CompletionRequest,AC.ResultOf(AC.Completion),callback,AC.CompletionRequest{lines,line,column,item,prefix})
        return completedEditing(value,result)

def changedAndRendered(result: ResultOf(Editor)) -> IO(ResultOf(Editor)):
  match result:
    case Fail{error}: IO.pure(ResultOf(Editor),Fail{error})
    case Done{value}:
      do IO<ResultOf(Editor)>:
        +value : Editor <- notifyChange(value)
        +value : Editor <- requestRender(value)
        return Done{value}
def eventSuggestions(value: Editor,options: AutocompleteRequestOptions,result: AC.ResultOf(Maybe<&2,AC.AutocompleteSuggestions>)) -> IO(ResultOf(Editor)):
  match options result:
    case _ Fail{error}: IO.pure(ResultOf(Editor),Fail{CompletionError{error}})
    case _ Done{None{}}:
      do IO<ResultOf(Editor)>:
        +value : Editor <- cancelAutocomplete(value)
        +value : Editor <- requestRender(value)
        return Done{value}
    case _ Done{Some{AC.AutocompleteSuggestions{Nil{},_}}}:
      do IO<ResultOf(Editor)>:
        +value : Editor <- cancelAutocomplete(value)
        +value : Editor <- requestRender(value)
        return Done{value}
    case AutocompleteRequestOptions{True{},True{}} Done{Some{AC.AutocompleteSuggestions{item <> Nil{},prefix}}}:
      do IO<ResultOf(Editor)>:
        result : ResultOf(Editor) <- completeItem(value,item,prefix)
        changedAndRendered(result)
    case AutocompleteRequestOptions{force,_} Done{Some{suggestions}}:
      do IO<ResultOf(Editor)>:
        +value : Editor <- requestRender(applyAutocompleteSuggestions(value,suggestions,force))
        return Done{value}
def eventIfCurrent(+value: Editor,event: AutocompleteEvent,context: AutocompleteContext) -> IO(ResultOf(Editor)):
  match value event:
    case Editor{editing,_,_,_,_,_,_} AutocompleteEvent{generation,+snapshot,options,result}:
      Bool.pick(Unit -> IO(ResultOf(Editor)),requestCurrent(context,generation,snapshot) && sameState(snapshot,editingState(editing)),_ => eventSuggestions(value,options,result),_ => IO.pure(ResultOf(Editor),Done{value}))(Unit{})
def applyAutocompleteEvent(+value: Editor,event: AutocompleteEvent) -> IO(ResultOf(Editor)):
  match value:
    case Editor{_,_,_,_,AutocompleteState{_,AutocompleteRuntime{current,_,_},_},_,_}:
      do IO<ResultOf(Editor)>:
        context : AutocompleteContext <- Ref.read(AutocompleteContext,current)
        eventIfCurrent(value,event,context)
@unsafe
def applyAutocompleteEvents(events: List<&2,AutocompleteEvent>,result: ResultOf(Editor)) -> IO(ResultOf(Editor)):
  match events result:
    case _ Fail{error}: IO.pure(ResultOf(Editor),Fail{error})
    case Nil{} Done{value}: IO.pure(ResultOf(Editor),Done{value})
    case event <> rest Done{value}:
      do IO<ResultOf(Editor)>:
        result : ResultOf(Editor) <- applyAutocompleteEvent(value,event)
        applyAutocompleteEvents(rest,result)
def pollAutocomplete(+value: Editor) -> IO(ResultOf(Editor)):
  match value:
    case Editor{_,_,_,_,AutocompleteState{_,runtime,_},_,_}:
      do IO<ResultOf(Editor)>:
        events : List<&2,AutocompleteEvent> <- takeAutocompleteEvents(runtime)
        applyAutocompleteEvents(events,Done{value})
def setAutocompleteList(value: Editor,list: Select.SelectList) -> Editor:
  match value:
    case Editor{editing,history,geometry,settings,AutocompleteState{provider,runtime,Some{AutocompleteUi{_,prefix,force}}},paste,jump}: Editor{editing,history,geometry,settings,AutocompleteState{provider,runtime,Some{AutocompleteUi{list,prefix,force}}},paste,jump}
    case value: value
def autocompleteInput(+value: Editor,manager: KB.KeybindingsManager,keyboard: Keys.Context,data: String) -> IO(Editor):
  match value:
    case Editor{_,_,_,_,AutocompleteState{_,_,None{}},_,_}: IO.pure(Editor,value)
    case Editor{_,_,_,_,AutocompleteState{_,_,Some{AutocompleteUi{list,_,_}}},_,_}:
      do IO<Editor>:
        list : Select.SelectList <- Select.handleInput(list,manager,keyboard,data)
        return setAutocompleteList(value,list)
def selectedAutocomplete(value: Editor,item: Maybe<&2,Select.SelectItem>,prefix: String) -> IO(ResultOf(Editor)):
  match item:
    case None{}: IO.pure(ResultOf(Editor),Done{value})
    case Some{Select.SelectItem{item,label,desc}}: completeItem(value,AC.AutocompleteItem{item,label,desc},prefix)
def selectAutocomplete(+value: Editor) -> IO(ResultOf(Editor)):
  match value:
    case Editor{_,_,_,_,AutocompleteState{_,_,Some{AutocompleteUi{list,prefix,_}}},_,_}: selectedAutocomplete(value,Select.getSelectedItem(list),prefix)
    case _: IO.pure(ResultOf(Editor),Done{value})
def containsAutocompleteLetter(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{char,+rest}: Bool.pick(Unit -> Bool,AC.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_",char),_ => True{},_ => containsAutocompleteLetter(rest))(Unit{})
def isTriggerText(text: String,characters: List<&2,Char>) -> Bool:
  match text:
    case SCon{char,SNil{}}: symbolIn(characters,char)
    case _: False{}
def triggerBoundary(+before: String) -> Bool:
  +prior = takePrefix(before,String.length(before) - 1n,"")
  Nat.is_eq(String.length(before),1n) || AC.ends(prior,' ') || AC.ends(prior,'\t')
def characterTrigger(+value: Editor,+char: String) -> Bool:
  match value:
    case Editor{editing,_,_,_,AutocompleteState{provider,_,_},_,_}:
      +state = editingState(editing)
      +before = stateBefore(state)
      +symbols = providerTriggers(provider)
      Bool.pick(Unit -> Bool,String.eq(char,"/"),
        _ => slashContext(state) && String.eq(Text.trim(before),"/"),
        _ => Bool.pick(Unit -> Bool,isTriggerText(char,symbols),
          _ => triggerBoundary(before),
          _ => containsAutocompleteLetter(char) && (slashContext(state) || symbolContext(before,symbols,True{},False{})))(Unit{}))(Unit{})
def afterTyping(+value: Editor,char: String) -> IO(ResultOf(Editor)):
  Bool.pick(Unit -> IO(ResultOf(Editor)),isShowingAutocomplete(value),_ => updateAutocomplete(value),_ => Bool.pick(Unit -> IO(ResultOf(Editor)),characterTrigger(value,char),_ => triggerAutocomplete(value,AutocompleteRequestOptions{False{},False{}}),_ => IO.pure(ResultOf(Editor),Done{value}))(Unit{}))(Unit{})
def afterDeletion(+value: Editor) -> IO(ResultOf(Editor)):
  match value:
    case Editor{editing,_,_,_,AutocompleteState{provider,_,_},_,_}:
      +state = editingState(editing)
      Bool.pick(Unit -> IO(ResultOf(Editor)),isShowingAutocomplete(value),_ => updateAutocomplete(value),_ => Bool.pick(Unit -> IO(ResultOf(Editor)),slashContext(state) || symbolContext(stateBefore(state),providerTriggers(provider),True{},False{}),_ => triggerAutocomplete(value,AutocompleteRequestOptions{False{},False{}}),_ => IO.pure(ResultOf(Editor),Done{value}))(Unit{}))(Unit{})

def syncEditor(+value: Editor) -> IO(Editor):
  match value:
    case Editor{editing,_,_,_,AutocompleteState{_,runtime,_},_,_}:
      do IO<Editor>:
        synchronizeAutocomplete(runtime,editingState(editing))
        return value
def edited(value: Editor,editing: Editing,leavesHistory: Bool,autocomplete: Bool) -> IO(ResultOf(Editor)):
  do IO<ResultOf(Editor)>:
    +value : Editor <- notifyChange(replaceEditing(value,editing,leavesHistory,False{}))
    Bool.pick(Unit -> IO(ResultOf(Editor)),autocomplete,_ => afterDeletion(value),_ => IO.pure(ResultOf(Editor),Done{value}))(Unit{})
def movedEditor(value: Editor,editing: Editing,autocomplete: Bool) -> IO(ResultOf(Editor)):
  do IO<ResultOf(Editor)>:
    +value : Editor <- syncEditor(replaceEditing(value,editing,False{},False{}))
    Bool.pick(Unit -> IO(ResultOf(Editor)),autocomplete,_ => updateAutocomplete(value),_ => IO.pure(ResultOf(Editor),Done{value}))(Unit{})
def typeText(+value: Editor,+text: String) -> IO(ResultOf(Editor)):
  match value:
    case Editor{editing,_,_,_,_,_,_}:
      do IO<ResultOf(Editor)>:
        +value : Editor <- notifyChange(replaceEditing(value,insertCharacter(editing,text),True{},False{}))
        afterTyping(value,text)
def pasteText(+value: Editor,text: String) -> IO(Editor):
  match value:
    case Editor{editing,_,_,_,_,_,_}:
      do IO<Editor>:
        +value : Editor <- cancelAutocomplete(replaceEditing(value,handlePasteEdit(editing,text),True{},False{}))
        notifyChange(value)
def addNewLine(+value: Editor) -> IO(Editor):
  match value:
    case Editor{editing,_,_,_,_,_,_}:
      do IO<Editor>:
        +value : Editor <- cancelAutocomplete(replaceEditing(value,insertTextEdit(editing,"\n"),True{},False{}))
        notifyChange(value)
def submittedEditing(value: Editing) -> Editing:
  match value:
    case Editing{_,ring,_,_,_,_}: Editing{emptySnapshot(),ring,NoAction{},Undo.create(EditorSnapshot),None{},None{}}
def submitValue(+value: Editor) -> IO(Editor):
  match value:
    case Editor{+editing,_,_,EditorSettings{_,_,EditorCallbacks{_,submit,_,_},_,_},_,_,_}:
      do IO<Editor>:
        +value : Editor <- cancelAutocomplete(replaceEditing(value,submittedEditing(editing),True{},True{}))
        +value : Editor <- notifyChange(value)
        changedCallback(submit,Text.trim(expandedEditingText(editing)))
        return value
def keyMatchParsed(keyboard: Keys.Context,data: String,key: Maybe<&2,Keys.KeyId>) -> Bool:
  match key:
    case None{}: False{}
    case Some{key}: Keys.matchesKey(keyboard,data,key)
def keyMatch(keyboard: Keys.Context,data: String,name: String) -> Bool: keyMatchParsed(keyboard,data,Keys.parseKeyId(name))
def precedingBackslash(value: Editor) -> Bool:
  match value:
    case Editor{editing,_,_,_,_,_,_}: AC.ends(stateBefore(editingState(editing)),'\\')
def newlineSubmits(+value: Editor,+manager: KB.KeybindingsManager,keyboard: Keys.Context,data: String) -> Bool:
  match value:
    case Editor{_,_,_,EditorSettings{_,_,_,_,disabled},_,_,_}: Bool.not(disabled) && keyMatch(keyboard,data,"enter") && KB.contains(KB.getKeys(manager,"tui.input.submit"),"shift+enter") && precedingBackslash(value)
def enterEditor(+value: Editor,newline: Bool) -> IO(ResultOf(Editor)):
  match value:
    case Editor{+editing,_,_,EditorSettings{_,_,_,_,disabled},_,_,_}:
      Bool.pick(Unit -> IO(ResultOf(Editor)),newline,
        _ => do IO<ResultOf(Editor)>:
          +value : Editor <- addNewLine(value)
          return Done{value},
        _ => Bool.pick(Unit -> IO(ResultOf(Editor)),disabled,_ => IO.pure(ResultOf(Editor),Done{value}),
          _ => Bool.pick(Unit -> IO(ResultOf(Editor)),precedingBackslash(value),
            _ => do IO<ResultOf(Editor)>:
              +value : Editor <- notifyChange(replaceEditing(value,handleBackspaceEdit(editing),True{},False{}))
              +value : Editor <- addNewLine(value)
              return Done{value},
            _ => do IO<ResultOf(Editor)>:
              +value : Editor <- submitValue(value)
              return Done{value})(Unit{}))(Unit{}))(Unit{})
def newlineEditor(+value: Editor,manager: KB.KeybindingsManager,keyboard: Keys.Context,data: String) -> IO(ResultOf(Editor)):
  match value:
    case Editor{editing,_,_,_,_,_,_}:
      Bool.pick(Unit -> IO(ResultOf(Editor)),newlineSubmits(value,manager,keyboard,data),
        _ => do IO<ResultOf(Editor)>:
          +value : Editor <- notifyChange(replaceEditing(value,handleBackspaceEdit(editing),True{},False{}))
          +value : Editor <- submitValue(value)
          return Done{value},
        _ => enterEditor(value,True{}))(Unit{})
def wordEdited(+value: Editor,remove: Bool,result: Word.ResultOf(Editing)) -> IO(ResultOf(Editor)):
  match result:
    case Fail{error}: IO.pure(ResultOf(Editor),Fail{WordError{error}})
    case Done{+editing}: Bool.pick(Unit -> IO(ResultOf(Editor)),remove,_ => edited(value,editing,True{},False{}),_ => movedEditor(value,editing,False{}))(Unit{})
def arrowAtEdge(+value: Editor,+editing: Editing,+up: Bool,width: Nat,edge: Bool,browsing: Bool) -> IO(ResultOf(Editor)):
  match editing:
    case Editing{EditorSnapshot{EditorState{_,_,column},_,_},_,_,_,_,_}:
      Bool.pick(Unit -> IO(ResultOf(Editor)),edge,
        _ => Bool.pick(Unit -> IO(ResultOf(Editor)),browsing || (up && Nat.is_eq(column,0n)),
          _ => do IO<ResultOf(Editor)>:
            +value : Editor <- historyStep(value,up)
            return Done{value},
          _ => movedEditor(value,lineBoundary(editing,up),False{}))(Unit{}),
        _ => movedEditor(value,moveVertical(editing,width,up,1n),True{}))(Unit{})
def arrowEditor(+value: Editor,+up: Bool) -> IO(ResultOf(Editor)):
  match value:
    case Editor{+editing,History{_,index,_},Geometry{width,_,_,_},_,_,_,_}:
      +layout = layoutText(editing,width)
      +position = cursorLayoutIndex(layout,0n)
      +edge = Bool.pick(Bool,up,Nat.is_eq(position,0n),Nat.is_eq(position,List.length(&2,LayoutLine,layout) - 1n))
      +browsing = Bool.not(Maybe.is_none(&2,Nat,index))
      arrowAtEdge(value,editing,up,width,edge,browsing)
def setJumpMode(value: Editor,jump: Maybe<&2,Bool>) -> Editor:
  match value:
    case Editor{editing,history,geometry,settings,autocomplete,paste,_}: Editor{editing,history,geometry,settings,autocomplete,paste,jump}
def printable(text: String) -> Bool:
  match text:
    case SCon{Chr{code},_}: U32.is_ge(code,32)
    case SNil{}: False{}
def printableInput(+value: Editor,+data: String,decoded: Maybe<&2,String>) -> IO(ResultOf(Editor)):
  match decoded:
    case Some{text}: typeText(value,text)
    case None{}: Bool.pick(Unit -> IO(ResultOf(Editor)),printable(data),_ => typeText(value,data),_ => IO.pure(ResultOf(Editor),Done{value}))(Unit{})
type Command is Data:
  Copy{} UndoCommand{} TabCommand{} KillStart{} KillEnd{} KillWordBackward{} KillWordForward{}
  BackspaceCommand{} DeleteCommand{} YankCommand{} YankPopCommand{} HistoryPrevious{} HistoryNext{}
  HomeCommand{} EndCommand{} WordLeft{} WordRight{} NewLine{} Submit{} Up{} Down{} Left{} Right{}
  PageUp{} PageDown{} JumpForward{} JumpBackward{} Insert{}
type Binding is Data: Binding{action: String,command: Command}
def bindings() -> List<&2,Binding>:
  [Binding{"tui.input.copy",Copy{}},Binding{"tui.editor.undo",UndoCommand{}},Binding{"tui.input.tab",TabCommand{}},
   Binding{"tui.editor.deleteToLineEnd",KillEnd{}},Binding{"tui.editor.deleteToLineStart",KillStart{}},Binding{"tui.editor.deleteWordBackward",KillWordBackward{}},Binding{"tui.editor.deleteWordForward",KillWordForward{}},Binding{"tui.editor.deleteCharBackward",BackspaceCommand{}},Binding{"tui.editor.deleteCharForward",DeleteCommand{}},Binding{"tui.editor.yank",YankCommand{}},Binding{"tui.editor.yankPop",YankPopCommand{}},Binding{"tui.editor.historyPrevious",HistoryPrevious{}},Binding{"tui.editor.historyNext",HistoryNext{}},Binding{"tui.editor.cursorLineStart",HomeCommand{}},Binding{"tui.editor.cursorLineEnd",EndCommand{}},Binding{"tui.editor.cursorWordLeft",WordLeft{}},Binding{"tui.editor.cursorWordRight",WordRight{}},Binding{"tui.input.newLine",NewLine{}},Binding{"tui.input.submit",Submit{}},Binding{"tui.editor.cursorUp",Up{}},Binding{"tui.editor.cursorDown",Down{}},Binding{"tui.editor.cursorRight",Right{}},Binding{"tui.editor.cursorLeft",Left{}},Binding{"tui.editor.pageUp",PageUp{}},Binding{"tui.editor.pageDown",PageDown{}},Binding{"tui.editor.jumpForward",JumpForward{}},Binding{"tui.editor.jumpBackward",JumpBackward{}}]
def extraBinding(action: String,+keyboard: Keys.Context,+data: String) -> Bool:
  match action:
    case "tui.editor.deleteCharBackward": keyMatch(keyboard,data,"shift+backspace")
    case "tui.editor.deleteCharForward": keyMatch(keyboard,data,"shift+delete")
    case "tui.input.newLine": AC.starts(data,"\n") || String.eq(data,"\u{1b}\r") || String.eq(data,"\u{1b}[13;2~") || (Nat.is_gt(String.length(data),1n) && String.contains(data,"\u{1b}") && String.contains(data,"\r"))
    case _: False{}
def command(entries: List<&2,Binding>,+manager: KB.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> Command:
  match entries:
    case Nil{}: Insert{}
    case Binding{+action,selected} <> rest: Bool.pick(Unit -> Command,KB.matches(manager,keyboard,data,action) || extraBinding(action,keyboard,data),_ => selected,_ => command(rest,manager,keyboard,data))(Unit{})

def doneEditor(action: IO(Editor)) -> IO(ResultOf(Editor)):
  do IO<ResultOf(Editor)>:
    +value : Editor <- action
    return Done{value}
def historyCommand(value: Editor,up: Bool) -> IO(ResultOf(Editor)):
  do IO<ResultOf(Editor)>:
    +value : Editor <- cancelAutocomplete(value)
    +value : Editor <- historyStep(value,up)
    return Done{value}
def executeCommand(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),+context: Context,+value: Editor,manager: KB.KeybindingsManager,+keyboard: Keys.Context,+data: String,+terminalRows: Nat,selected: Command) -> IO(ResultOf(Editor)):
  match value selected:
    case _ Copy{}: IO.pure(ResultOf(Editor),Done{value})
    case Editor{Editing{snapshot,ring,action,+stack,preferred,snapped},_,_,_,_,_,_} UndoCommand{}:
      +editing = {Editing{snapshot,ring,action,stack,preferred,snapped}: Editing}
      Bool.pick(Unit -> IO(ResultOf(Editor)),Nat.is_gt(Undo.length(EditorSnapshot,stack),0n),_ => edited(value,undoEdit(editing),True{},False{}),_ => IO.pure(ResultOf(Editor),Done{replaceEditing(value,editing,True{},False{})}))(Unit{})
    case _ TabCommand{}: tabCompletion(value)
    case Editor{editing,_,_,_,_,_,_} KillStart{}: edited(value,killLine(editing,True{}),True{},False{})
    case Editor{editing,_,_,_,_,_,_} KillEnd{}: edited(value,killLine(editing,False{}),True{},False{})
    case Editor{editing,_,_,_,_,_,_} KillWordBackward{}: wordEdited(value,True{},wordEdit(~Context,~segment,context,editing,True{},True{}))
    case Editor{editing,_,_,_,_,_,_} KillWordForward{}: wordEdited(value,True{},wordEdit(~Context,~segment,context,editing,False{},True{}))
    case Editor{editing,_,_,_,_,_,_} BackspaceCommand{}: edited(value,handleBackspaceEdit(editing),True{},True{})
    case Editor{editing,_,_,_,_,_,_} DeleteCommand{}: edited(value,deleteHorizontal(editing,False{}),True{},True{})
    case Editor{Editing{snapshot,+ring,action,stack,preferred,snapped},_,_,_,_,_,_} YankCommand{}:
      +editing = {Editing{snapshot,ring,action,stack,preferred,snapped}: Editing}
      Bool.pick(Unit -> IO(ResultOf(Editor)),Nat.is_gt(Kill.length(ring),0n),_ => edited(value,yankEdit(editing),True{},False{}),_ => IO.pure(ResultOf(Editor),Done{value}))(Unit{})
    case Editor{Editing{snapshot,+ring,+action,stack,preferred,snapped},_,_,_,_,_,_} YankPopCommand{}:
      +editing = {Editing{snapshot,ring,action,stack,preferred,snapped}: Editing}
      Bool.pick(Unit -> IO(ResultOf(Editor)),isYank(action) && Nat.is_gt(Kill.length(ring),1n),_ => edited(value,yankPopEdit(editing),True{},False{}),_ => IO.pure(ResultOf(Editor),Done{value}))(Unit{})
    case _ HistoryPrevious{}: historyCommand(value,True{})
    case _ HistoryNext{}: historyCommand(value,False{})
    case Editor{editing,_,_,_,_,_,_} HomeCommand{}: movedEditor(value,lineBoundary(editing,True{}),False{})
    case Editor{editing,_,_,_,_,_,_} EndCommand{}: movedEditor(value,lineBoundary(editing,False{}),False{})
    case Editor{editing,_,_,_,_,_,_} WordLeft{}: wordEdited(value,False{},wordEdit(~Context,~segment,context,editing,True{},False{}))
    case Editor{editing,_,_,_,_,_,_} WordRight{}: wordEdited(value,False{},wordEdit(~Context,~segment,context,editing,False{},False{}))
    case _ NewLine{}: newlineEditor(value,manager,keyboard,data)
    case _ Submit{}: enterEditor(value,False{})
    case _ Up{}: arrowEditor(value,True{})
    case _ Down{}: arrowEditor(value,False{})
    case Editor{editing,_,_,_,_,_,_} Left{}: movedEditor(value,moveHorizontal(editing,True{}),True{})
    case Editor{editing,_,_,_,_,_,_} Right{}: movedEditor(value,moveHorizontal(editing,False{}),True{})
    case Editor{editing,_,Geometry{width,_,_,_},_,_,_,_} PageUp{}: movedEditor(value,moveVertical(editing,width,True{},Nat.max(5n,terminalRows * 3n / 10n)),False{})
    case Editor{editing,_,Geometry{width,_,_,_},_,_,_,_} PageDown{}: movedEditor(value,moveVertical(editing,width,False{},Nat.max(5n,terminalRows * 3n / 10n)),False{})
    case _ JumpForward{}: IO.pure(ResultOf(Editor),Done{setJumpMode(value,Some{False{}})})
    case _ JumpBackward{}: IO.pure(ResultOf(Editor),Done{setJumpMode(value,Some{True{}})})
    case _ Insert{}: Bool.pick(Unit -> IO(ResultOf(Editor)),keyMatch(keyboard,data,"shift+space"),_ => typeText(value," "),_ => printableInput(value,data,Keys.decodePrintableKey(data)))(Unit{})
def isSlashPicker(value: Editor) -> Bool:
  match value:
    case Editor{_,_,_,_,AutocompleteState{_,_,Some{AutocompleteUi{_,prefix,_}}},_,_}: AC.starts(prefix,"/")
    case _: False{}
def menuSelected(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),context: Context,result: ResultOf(Editor),manager: KB.KeybindingsManager,keyboard: Keys.Context,data: String,terminalRows: Nat,submit: Bool,selected: Command) -> IO(ResultOf(Editor)):
  match result:
    case Fail{error}: IO.pure(ResultOf(Editor),Fail{error})
    case Done{value}:
      do IO<ResultOf(Editor)>:
        +value : Editor <- cancelAutocomplete(value)
        Bool.pick(Unit -> IO(ResultOf(Editor)),submit,
          _ => executeCommand(~Context,~segment,context,value,manager,keyboard,data,terminalRows,selected),
          _ => doneEditor(notifyChange(value)))(Unit{})
def menuInput(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),+context: Context,+value: Editor,+manager: KB.KeybindingsManager,+keyboard: Keys.Context,+data: String,+terminalRows: Nat,+selected: Command) -> IO(ResultOf(Editor)):
  Bool.pick(Unit -> IO(ResultOf(Editor)),isShowingAutocomplete(value),
    _ => Bool.pick(Unit -> IO(ResultOf(Editor)),KB.matches(manager,keyboard,data,"tui.select.cancel"),
      _ => doneEditor(cancelAutocomplete(value)),
      _ => Bool.pick(Unit -> IO(ResultOf(Editor)),KB.matches(manager,keyboard,data,"tui.select.up") || KB.matches(manager,keyboard,data,"tui.select.down"),
        _ => doneEditor(autocompleteInput(value,manager,keyboard,data)),
        _ => Bool.pick(Unit -> IO(ResultOf(Editor)),KB.matches(manager,keyboard,data,"tui.input.tab") || KB.matches(manager,keyboard,data,"tui.select.confirm"),
          _ => do IO<ResultOf(Editor)>:
            result : ResultOf(Editor) <- selectAutocomplete(value)
            menuSelected(~Context,~segment,context,result,manager,keyboard,data,terminalRows,Bool.not(KB.matches(manager,keyboard,data,"tui.input.tab")) && isSlashPicker(value),selected),
          _ => executeCommand(~Context,~segment,context,value,manager,keyboard,data,terminalRows,selected))(Unit{}))(Unit{}))(Unit{}),
    _ => executeCommand(~Context,~segment,context,value,manager,keyboard,data,terminalRows,selected))(Unit{})
def callEditorAction(callback: Maybe<&2,C.Callback<EditorAction,Unit>>,action: EditorAction) -> IO(Unit):
  match callback:
    case Some{handler}: C.call(EditorAction,Unit,handler,action)
    case None{}: IO.pure(Unit,Unit{})
def editorAction(+value: Editor,action: EditorAction,clear: Bool) -> IO(ResultOf(Editor)):
  match value:
    case Editor{_,_,_,EditorSettings{_,_,EditorCallbacks{_,_,_,callback},_,_},_,_,_}:
      do IO<ResultOf(Editor)>:
        callEditorAction(callback,action)
        +next : Editor <- Bool.pick(Unit -> IO(Editor),clear,_ => setText(value,""),_ => IO.pure(Editor,value))(Unit{})
        return Done{next}
def regularSelected(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),context: Context,value: Editor,manager: KB.KeybindingsManager,keyboard: Keys.Context,data: String,terminalRows: Nat,selected: Command) -> IO(ResultOf(Editor)):
  match selected:
    case Copy{}: IO.pure(ResultOf(Editor),Done{value})
    case UndoCommand{}: executeCommand(~Context,~segment,context,value,manager,keyboard,data,terminalRows,UndoCommand{})
    case selected: menuInput(~Context,~segment,context,value,manager,keyboard,data,terminalRows,selected)
type AppInput is Data: AppInterrupt{} AppClear{} AppExit{} AppFollowUp{} AppDequeue{} AppExpand{} AppToggleThinking{} AppNone{}
def appInput(+manager: KB.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> AppInput:
  Bool.pick(AppInput,KB.matches(manager,keyboard,data,"app.tools.expand"),AppExpand{},
    Bool.pick(AppInput,KB.matches(manager,keyboard,data,"app.thinking.toggle"),AppToggleThinking{},
      Bool.pick(AppInput,KB.matches(manager,keyboard,data,"app.interrupt"),AppInterrupt{},
        Bool.pick(AppInput,KB.matches(manager,keyboard,data,"app.clear"),AppClear{},
          Bool.pick(AppInput,KB.matches(manager,keyboard,data,"app.exit"),AppExit{},
            Bool.pick(AppInput,KB.matches(manager,keyboard,data,"app.message.followUp"),AppFollowUp{},
              Bool.pick(AppInput,KB.matches(manager,keyboard,data,"app.message.dequeue"),AppDequeue{},AppNone{})))))))
def runAppInput(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),context: Context,+value: Editor,manager: KB.KeybindingsManager,keyboard: Keys.Context,data: String,terminalRows: Nat,selected: Command,app: AppInput) -> IO(ResultOf(Editor)):
  match app:
    case AppExpand{}: editorAction(value,ExpandTools{},False{})
    case AppToggleThinking{}: editorAction(value,ToggleThinking{},False{})
    case AppInterrupt{}: editorAction(value,Interrupt{getText(value)},False{})
    case AppClear{}: editorAction(value,Clear{},True{})
    case AppExit{}:
      Bool.pick(Unit -> IO(ResultOf(Editor)),String.is_empty(getText(value)),
        _ => editorAction(value,Exit{},False{}),
        _ => regularSelected(~Context,~segment,context,value,manager,keyboard,data,terminalRows,selected))(Unit{})
    case AppFollowUp{}: editorAction(value,FollowUp{Text.trim(getExpandedText(value))},True{})
    case AppDequeue{}: editorAction(value,Dequeue{getText(value)},False{})
    case AppNone{}: regularSelected(~Context,~segment,context,value,manager,keyboard,data,terminalRows,selected)
def regularInput(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),context: Context,value: Editor,+manager: KB.KeybindingsManager,+keyboard: Keys.Context,+data: String,terminalRows: Nat,selected: Command) -> IO(ResultOf(Editor)):
  runAppInput(~Context,~segment,context,value,manager,keyboard,data,terminalRows,selected,appInput(manager,keyboard,data))

type Position is Data: Position{line: Nat,column: Nat}
def findFirst(text: String,+wanted: String,+index: Nat) -> Maybe<&2,Nat>:
  match text:
    case SNil{}: None{}
    case SCon{+char,+rest}: Bool.pick(Unit -> Maybe<&2,Nat>,AC.starts(SCon{char,rest},wanted),_ => Some{index},_ => findFirst(rest,wanted,index + 1n))(Unit{})
def findLast(text: String,+wanted: String,+index: Nat,+maximum: Nat,+previous: Maybe<&2,Nat>) -> Maybe<&2,Nat>:
  match text:
    case SNil{}: previous
    case SCon{+char,+rest}: Bool.pick(Unit -> Maybe<&2,Nat>,Nat.is_gt(index,maximum),_ => previous,_ => findLast(rest,wanted,index + 1n,maximum,Bool.pick(Maybe<&2,Nat>,AC.starts(SCon{char,rest},wanted),Some{index},previous)))(Unit{})
def chooseJump(found: Maybe<&2,Nat>,line: Nat,backward: Bool,+previous: Maybe<&2,Position>) -> Maybe<&2,Position>:
  match found:
    case None{}: previous
    case Some{column}: Bool.pick(Maybe<&2,Position>,backward || Maybe.is_none(&2,Position,previous),Some{Position{line,column}},previous)
def jumpSearch(lines: List<&2,String>,+current: Nat,+column: Nat,+index: Nat,+backward: Bool,+text: String,previous: Maybe<&2,Position>) -> Maybe<&2,Position>:
  match lines:
    case Nil{}: previous
    case +line <> rest:
      +eligible = Bool.pick(Bool,backward,Nat.is_le(index,current),Nat.is_ge(index,current))
      +from = Bool.pick(Nat,Nat.is_eq(index,current),Bool.pick(Nat,backward,column - 1n,column + 1n),Bool.pick(Nat,backward,String.length(line),0n))
      +found = Bool.pick(Unit -> Maybe<&2,Nat>,eligible,
        _ => Bool.pick(Unit -> Maybe<&2,Nat>,backward,_ => findLast(line,text,0n,from,None{}),_ => findFirst(String.drop(line,from),text,from))(Unit{}),
        _ => None{})(Unit{})
      jumpSearch(rest,current,column,index + 1n,backward,text,chooseJump(found,index,backward,previous))
def jumped(+value: Editing,position: Maybe<&2,Position>) -> Editing:
  match position:
    case None{}: resetAction(value)
    case Some{Position{line,column}}: moveTo(value,line,column)
def jumpEditing(value: Editor,+editing: Editing,text: String,backward: Bool) -> IO(ResultOf(Editor)):
  match editing:
    case Editing{EditorSnapshot{EditorState{lines,line,column},_,_},_,_,_,_,_}: movedEditor(value,jumped(editing,jumpSearch(lines,line,column,0n,backward,text,None{})),False{})
def jumpToChar(+value: Editor,text: String,backward: Bool) -> IO(ResultOf(Editor)):
  match value:
    case Editor{+editing,_,_,_,_,_,_}: jumpEditing(value,editing,text,backward)
type TextSplit is Data: TextSplit{before: String,after: String}
def splitFound(value: Maybe<&2,String>,reversed: String) -> Maybe<&2,TextSplit>:
  match value:
    case None{}: None{}
    case Some{after}: Some{TextSplit{String.reverse(reversed),after}}
def splitFirst(text: String,+needle: String,+reversed: String) -> Maybe<&2,TextSplit>:
  match text:
    case SNil{}: None{}
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Maybe<&2,TextSplit>,AC.starts(SCon{char,rest},needle),_ => splitFound(Word.consume(needle,SCon{char,rest}),reversed),_ => splitFirst(rest,needle,SCon{char,reversed}))(Unit{})
def setPasteInput(value: Editor,buffer: String,inside: Bool) -> Editor:
  match value:
    case Editor{editing,history,geometry,settings,autocomplete,_,jump}: Editor{editing,history,geometry,settings,autocomplete,PasteInput{buffer,inside},jump}
type InputStage is Data:
  Waiting{editor: Editor}
  Regular{editor: Editor,data: String}
  Pasted{editor: Editor,text: String,remaining: String}
  Jumped{editor: Editor,text: String,backward: Bool}
def pasteEnd(value: Editor,+buffer: String,found: Maybe<&2,TextSplit>) -> InputStage:
  match found:
    case None{}: Waiting{setPasteInput(value,buffer,True{})}
    case Some{TextSplit{text,remaining}}: Pasted{setPasteInput(value,"",False{}),text,remaining}
def pasteStarted(+value: Editor,data: String) -> InputStage:
  match value:
    case Editor{_,_,_,_,_,PasteInput{buffer,True{}},_}:
      +combined = buffer ++ data
      pasteEnd(value,combined,splitFirst(combined,"\u{1b}[201~",""))
    case _: Regular{value,data}
def pasteStart(value: Editor,data: String,found: Maybe<&2,TextSplit>) -> InputStage:
  match found:
    case None{}: pasteStarted(value,data)
    case Some{TextSplit{before,after}}: pasteStarted(setPasteInput(value,"",True{}),before ++ after)
def parsePaste(value: Editor,+data: String) -> InputStage: pasteStart(value,data,splitFirst(data,"\u{1b}[200~",""))
def jumpInput(+value: Editor,+data: String,+backward: Bool,decoded: Maybe<&2,String>) -> InputStage:
  match decoded:
    case Some{text}: Jumped{setJumpMode(value,None{}),text,backward}
    case None{}: Bool.pick(Unit -> InputStage,printable(data),_ => Jumped{setJumpMode(value,None{}),data,backward},_ => parsePaste(setJumpMode(value,None{}),data))(Unit{})
def parseInput(+value: Editor,+manager: KB.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> InputStage:
  match value:
    case Editor{_,_,_,_,_,_,None{}}: parsePaste(value,data)
    case Editor{_,_,_,_,_,_,Some{backward}}:
      Bool.pick(Unit -> InputStage,KB.matches(manager,keyboard,data,"tui.editor.jumpForward") || KB.matches(manager,keyboard,data,"tui.editor.jumpBackward"),
        _ => Waiting{setJumpMode(value,None{})},
        _ => jumpInput(value,data,backward,Keys.decodePrintableKey(data)))(Unit{})
@unsafe
def handleInputStage(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),+context: Context,stage: InputStage,+manager: KB.KeybindingsManager,+keyboard: Keys.Context,+terminalRows: Nat) -> IO(ResultOf(Editor)):
  match stage:
    case Waiting{value}: IO.pure(ResultOf(Editor),Done{value})
    case Jumped{value,text,backward}: jumpToChar(value,text,backward)
    case Regular{value,+data}: regularInput(~Context,~segment,context,value,manager,keyboard,data,terminalRows,command(bindings(),manager,keyboard,data))
    case Pasted{+value,+text,+remaining}:
      do IO<ResultOf(Editor)>:
        +value : Editor <- Bool.pick(Unit -> IO(Editor),String.is_empty(text),_ => IO.pure(Editor,value),_ => pasteText(value,text))(Unit{})
        Bool.pick(Unit -> IO(ResultOf(Editor)),String.is_empty(remaining),_ => IO.pure(ResultOf(Editor),Done{value}),_ => handleInputStage(~Context,~segment,context,parseInput(value,manager,keyboard,remaining),manager,keyboard,terminalRows))(Unit{})
def handleInputPolled(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),context: Context,result: ResultOf(Editor),+manager: KB.KeybindingsManager,+keyboard: Keys.Context,data: String,terminalRows: Nat) -> IO(ResultOf(Editor)):
  match result:
    case Fail{error}: IO.pure(ResultOf(Editor),Fail{error})
    case Done{value}: handleInputStage(~Context,~segment,context,parseInput(value,manager,keyboard,data),manager,keyboard,terminalRows)
def handleInput(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),context: Context,value: Editor,manager: KB.KeybindingsManager,keyboard: Keys.Context,data: String,terminalRows: Nat) -> IO(ResultOf(Editor)):
  do IO<ResultOf(Editor)>:
    result : ResultOf(Editor) <- pollAutocomplete(value)
    handleInputPolled(~Context,~segment,context,result,manager,keyboard,data,terminalRows)

type MouseResult is Data: MouseResult{editor: Editor,result: Maybe<&2,Tui.TuiMouseEventResult>}
def focusMouse(result: Maybe<&2,Tui.TuiMouseEventResult>) -> Maybe<&2,Tui.TuiMouseEventResult>:
  match result:
    case None{}: None{}
    case Some{Tui.TuiMouseEventResult{handled,capture,_,redraw}}: Some{Tui.TuiMouseEventResult{handled,capture,True{},redraw}}
def mouseDone(result: ResultOf(Editor),mouse: Maybe<&2,Tui.TuiMouseEventResult>) -> ResultOf(MouseResult):
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: Done{MouseResult{value,mouse}}
def handledMouse() -> Maybe<&2,Tui.TuiMouseEventResult>: Some{Tui.TuiMouseEventResult{True{},False{},True{},None{}}}
def nonnegative(offset: Tui.Offset) -> Nat:
  match offset:
    case Tui.Forward{n}: n
    case Tui.Backward{_}: 0n
def subtractOffset(offset: Tui.Offset,+distance: Nat) -> Tui.Offset:
  match offset:
    case Tui.Forward{+n}: Bool.pick(Tui.Offset,Nat.is_ge(n,distance),Tui.Forward{n - distance},Tui.Backward{distance - n})
    case Tui.Backward{n}: Tui.Backward{n + distance}
def rowIn(offset: Tui.Offset,+start: Nat,+count: Nat) -> Bool:
  match offset:
    case Tui.Forward{+n}: Nat.is_ge(n,start) && Nat.is_lt(n,start + count)
    case Tui.Backward{Zero{}}: Nat.is_eq(start,0n) && Nat.is_gt(count,0n)
    case _: False{}
def clicked(event: Tui.TuiMouseEvent) -> Bool:
  match event:
    case Tui.TuiMouseEvent{Tui.MouseClick{},Tui.MouseLeft{},_,_,_,_,_,_,_,_,_,_,_}: True{}
    case _: False{}
def mouseColumn(parts: List<&2,Segment>,+target: Nat,+visible: Nat,+length: Nat,+last: Bool,previous: Nat) -> Nat:
  match parts:
    case Nil{}: Bool.pick(Nat,last || Nat.is_eq(length,0n),length,previous)
    case Segment{text,+index,_} <> +rest:
      +next = visible + U.visibleWidth(text)
      Bool.pick(Unit -> Nat,Nat.is_lt(target,next),_ => index,_ => mouseColumn(rest,target,next,length,last,index))(Unit{})
def contentMouseLine(+value: Editor,target: Maybe<&2,LayoutLine>,column: Nat) -> IO(ResultOf(MouseResult)):
  match value target:
    case Editor{Editing{EditorSnapshot{state,+pastes,count},ring,action,stack,preferred,snapped},_,_,_,_,_,_} Some{LayoutLine{+text,line,+start,+length,_,last}}:
      editing = {Editing{EditorSnapshot{state,pastes,count},ring,action,stack,preferred,snapped}: Editing}
      do IO<ResultOf(MouseResult)>:
        +value : Editor <- syncEditor(replaceEditing(value,moveTo(editing,line,start + mouseColumn(segmentWithMarkers(text,pastes),column,0n,length,last,0n)),True{},False{}))
        result : ResultOf(Editor) <- updateAutocomplete(value)
        return mouseDone(result,handledMouse())
    case _ None{}: IO.pure(ResultOf(MouseResult),Done{MouseResult{value,handledMouse()}})
def contentMouse(+value: Editor,+event: Tui.TuiMouseEvent) -> IO(ResultOf(MouseResult)):
  match value event:
    case Editor{editing,_,Geometry{width,visible,_,scroll},EditorSettings{_,EditorOptions{padding,_},_,_,_},_,_,_} Tui.TuiMouseEvent{_,_,x,+y,_,_,eventWidth,_,_,_,_,_,_}:
      Bool.pick(Unit -> IO(ResultOf(MouseResult)),clicked(event),
        _ => Bool.pick(Unit -> IO(ResultOf(MouseResult)),rowIn(y,1n,visible),
          _ => contentMouseLine(value,layoutAt(layoutText(editing,width),scroll + nonnegative(y) - 1n),nonnegative(subtractOffset(x,Nat.min(padding,(eventWidth - 1n) / 2n)))),
          _ => IO.pure(ResultOf(MouseResult),Done{MouseResult{value,handledMouse()}}))(Unit{}),
        _ => IO.pure(ResultOf(MouseResult),Done{MouseResult{value,None{}}}))(Unit{})
def mouseSelected(result: ResultOf(Editor),mouse: Maybe<&2,Tui.TuiMouseEventResult>) -> IO(ResultOf(MouseResult)):
  match result:
    case Fail{error}: IO.pure(ResultOf(MouseResult),Fail{error})
    case Done{value}:
      do IO<ResultOf(MouseResult)>:
        +value : Editor <- cancelAutocomplete(value)
        +value : Editor <- notifyChange(value)
        return Done{MouseResult{value,focusMouse(mouse)}}
def menuMouseResult(value: Editor,click: Bool,result: Select.SelectList & Maybe<&2,Tui.TuiMouseEventResult>) -> IO(ResultOf(MouseResult)):
  match result:
    case Tuple{list,+mouse}:
      +value = setAutocompleteList(value,list)
      Bool.pick(Unit -> IO(ResultOf(MouseResult)),click && Bool.not(Maybe.is_none(&2,Tui.TuiMouseEventResult,mouse)),
        _ => do IO<ResultOf(MouseResult)>:
          result : ResultOf(Editor) <- selectAutocomplete(value)
          mouseSelected(result,mouse),
        _ => IO.pure(ResultOf(MouseResult),Done{MouseResult{value,focusMouse(mouse)}}))(Unit{})
def menuMouse(+value: Editor,list: Select.SelectList,+event: Tui.TuiMouseEvent,start: Nat,height: Nat,padding: Nat) -> IO(ResultOf(MouseResult)):
  match event:
    case Tui.TuiMouseEvent{kind,button,x,y,sx,sy,+width,_,shift,alt,ctrl,delta,clickCount}:
      +padding = Nat.min(padding,(width - 1n) / 2n)
      do IO<ResultOf(MouseResult)>:
        result : Select.SelectList & Maybe<&2,Tui.TuiMouseEventResult> <- Select.handleMouse(list,Tui.TuiMouseEvent{kind,button,subtractOffset(x,padding),subtractOffset(y,start),sx,sy,Nat.max(1n,width - padding * 2n),height,shift,alt,ctrl,delta,clickCount})
        menuMouseResult(value,clicked(event),result)
def handleMouse(+value: Editor,+event: Tui.TuiMouseEvent) -> IO(ResultOf(MouseResult)):
  match value event:
    case Editor{_,_,Geometry{_,visible,+height,_},EditorSettings{_,EditorOptions{padding,_},_,_,_},AutocompleteState{_,_,Some{AutocompleteUi{list,_,_}}},_,_} Tui.TuiMouseEvent{_,_,_,y,_,_,_,_,_,_,_,_,_}:
      +start = visible + 2n
      Bool.pick(Unit -> IO(ResultOf(MouseResult)),rowIn(y,start,height),_ => menuMouse(value,list,event,start,height,padding),_ => contentMouse(value,event))(Unit{})
    case _ _: contentMouse(value,event)
