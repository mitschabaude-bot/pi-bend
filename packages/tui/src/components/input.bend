import Base
import ../utils.bend as U
import ../keys.bend as Keys
import ../keybindings.bend as KB
import ../tui.bend as Tui
import ../kill-ring.bend as Kill
import ../undo-stack.bend as Undo
import ../word-navigation.bend as Word
import ../../../runtime/src/grapheme.bend as Grapheme
import ../../../runtime/src/callback.bend as C

type InputState is Data: InputState{value: String,cursor: Nat}
type LastAction is Data: NoAction{} KillAction{} YankAction{} TypeWord{}
type Editing is Data:
  Editing{value: String,cursor: Nat,killRing: Kill.KillRing,lastAction: LastAction,undoStack: Undo.UndoStack<InputState>}
type InputOptions is Data:
  InputOptions{prompt: Maybe<&2,String>,placeholder: Maybe<&2,String>,placeholderStyle: Maybe<&2,C.Callback<String,String>>}
type Input is Data:
  Input{editing: Editing,options: InputOptions,renderedStartColumn: Nat,focused: Bool,pasteBuffer: String,isInPaste: Bool,onSubmit: Maybe<&2,C.Callback<String,Unit>>,onEscape: Maybe<&2,C.Callback<Unit,Unit>>}

def new(options: Maybe<&2,InputOptions>) -> Input:
  Input{Editing{"",0n,Kill.create(),NoAction{},Undo.create(InputState)},Maybe.default(&2,InputOptions,options,InputOptions{None{},None{},None{}}),0n,False{},"",False{},None{},None{}}
def getValue(state: Input) -> String:
  match state:
    case Input{Editing{value,_,_,_,_},_,_,_,_,_,_,_}: value
def getCursor(state: Input) -> Nat:
  match state:
    case Input{Editing{_,cursor,_,_,_},_,_,_,_,_,_,_}: cursor
def setValue(state: Input,+value: String) -> Input:
  match state:
    case Input{Editing{_,cursor,ring,action,undo},options,start,focused,paste,pasting,submit,escape}: Input{Editing{value,Nat.min(cursor,String.length(value)),ring,action,undo},options,start,focused,paste,pasting,submit,escape}
def setFocused(state: Input,focused: Bool) -> Input:
  match state:
    case Input{editing,options,start,_,paste,pasting,submit,escape}: Input{editing,options,start,focused,paste,pasting,submit,escape}
def setCallbacks(state: Input,onSubmit: Maybe<&2,C.Callback<String,Unit>>,onEscape: Maybe<&2,C.Callback<Unit,Unit>>) -> Input:
  match state:
    case Input{editing,options,start,focused,paste,pasting,_,_}: Input{editing,options,start,focused,paste,pasting,onSubmit,onEscape}
def invalidate(state: Input) -> Input: state

def editing(state: Input,value: Editing) -> Input:
  match state:
    case Input{_,options,start,focused,paste,pasting,submit,escape}: Input{value,options,start,focused,paste,pasting,submit,escape}
def changed(state: Editing,value: String,cursor: Nat,action: LastAction) -> Editing:
  match state:
    case Editing{_,_,ring,_,undo}: Editing{value,cursor,ring,action,undo}
def pushUndo(state: Editing) -> Editing:
  match state:
    case Editing{+value,+cursor,ring,action,undo}: Editing{value,cursor,ring,action,Undo.push(InputState,InputState{value,cursor},undo)}
def restore(state: Editing,popped: Undo.UndoStack<InputState> & Maybe<&2,InputState>) -> Editing:
  match state popped:
    case Editing{_,_,ring,_,_} Tuple{undo,Some{InputState{value,cursor}}}: Editing{value,cursor,ring,NoAction{},undo}
    case state Tuple{_,None{}}: state
def undoEdit(+state: Editing) -> Editing:
  match state:
    case Editing{_,_,_,_,stack}: restore(state,Undo.pop(InputState,stack))
def isKill(action: LastAction) -> Bool:
  match action:
    case KillAction{}: True{}
    case _: False{}
def isYank(action: LastAction) -> Bool:
  match action:
    case YankAction{}: True{}
    case _: False{}
def isWord(action: LastAction) -> Bool:
  match action:
    case TypeWord{}: True{}
    case _: False{}
# Cursor slices use a tail-recursive accumulator, including long pasted lines.
def prefix(text: String,count: Nat,reversed: String) -> String:
  match text count:
    case SCon{char,rest} Succ{count}: prefix(rest,count,SCon{char,reversed})
    case _ _: String.reverse(reversed)
def insertCharacter(+state: Editing,+char: String) -> Editing:
  match state:
    case Editing{+value,+cursor,_,action,_}:
      changed(Bool.pick(Editing,Word.whitespace(char) || Bool.not(isWord(action)),pushUndo(state),state),prefix(value,cursor,"") ++ char ++ String.drop(value,cursor),cursor + String.length(char),TypeWord{})
def firstCluster(text: String) -> String:
  Maybe.default(&1,String,Maybe.map(&1,String & String,String,pair => Pair.fst(String,String,pair),Grapheme.next(text))," ")
def lastLength(parts: List<&2,String>,length: Nat) -> Nat:
  match parts:
    case Nil{}: length
    case part <> rest: lastLength(rest,String.length(part))
def previous(+value: String,+cursor: Nat) -> Nat:
  cursor - lastLength(Grapheme.segments(prefix(value,cursor,"")),1n)
def following(+value: String,+cursor: Nat) -> Nat:
  Nat.min(String.length(value),cursor + String.length(firstCluster(String.drop(value,cursor))))
def move(+state: Editing,cursor: Nat) -> Editing:
  match state:
    case Editing{value,_,_,_,_}: changed(state,value,cursor,NoAction{})
def erase(+state: Editing,+from: Nat,+until: Nat) -> Editing:
  match state:
    case Editing{+value,_,_,_,_}: changed(pushUndo(state),prefix(value,from,"") ++ String.drop(value,until),from,NoAction{})
def kill(+state: Editing,+from: Nat,+until: Nat,prepend: Bool) -> Editing:
  match state:
    case Editing{+value,+cursor,ring,action,undo}:
      Editing{prefix(value,from,"") ++ String.drop(value,until),from,Kill.push(prefix(String.drop(value,from),until - from,""),Kill.PushOptions{prepend,isKill(action)},ring),KillAction{},Undo.push(InputState,InputState{value,cursor},undo)}
def yank(+state: Editing) -> Editing:
  match state:
    case Editing{+value,+cursor,+ring,_,_}:
      +text = Maybe.default(&2,String,Kill.peek(ring),"")
      Bool.pick(Unit -> Editing,String.eq(text,""),_ => state,_ => changed(pushUndo(state),prefix(value,cursor,"") ++ text ++ String.drop(value,cursor),cursor + String.length(text),YankAction{}))(Unit{})
def yankPop(+state: Editing) -> Editing:
  match state:
    case Editing{+value,+cursor,+ring,action,undo}:
      +start = cursor - String.length(Maybe.default(&2,String,Kill.peek(ring),""))
      +rotated = Kill.rotate(ring)
      +text = Maybe.default(&2,String,Kill.peek(rotated),"")
      Bool.pick(Unit -> Editing,isYank(action) && Nat.is_gt(Kill.length(ring),1n),
        _ => Editing{prefix(value,start,"") ++ text ++ String.drop(value,cursor),start + String.length(text),rotated,YankAction{},Undo.push(InputState,InputState{value,cursor},undo)},
        _ => state)(Unit{})

type Command is Data:
  Escape{} UndoEdit{} Submit{} Backspace{} ForwardDelete{}
  KillWordBackward{} KillWordForward{} KillStart{} KillEnd{}
  Yank{} YankPop{} Left{} Right{} Home{} End{} WordLeft{} WordRight{} Insert{}
type Binding is Data: Binding{action: String,command: Command}
def bindings() -> List<&2,Binding>:
  Binding{"tui.select.cancel",Escape{}} <> Binding{"tui.editor.undo",UndoEdit{}} <> Binding{"tui.input.submit",Submit{}} <>
  Binding{"tui.editor.deleteCharBackward",Backspace{}} <> Binding{"tui.editor.deleteCharForward",ForwardDelete{}} <>
  Binding{"tui.editor.deleteWordBackward",KillWordBackward{}} <> Binding{"tui.editor.deleteWordForward",KillWordForward{}} <>
  Binding{"tui.editor.deleteToLineStart",KillStart{}} <> Binding{"tui.editor.deleteToLineEnd",KillEnd{}} <>
  Binding{"tui.editor.yank",Yank{}} <> Binding{"tui.editor.yankPop",YankPop{}} <>
  Binding{"tui.editor.cursorLeft",Left{}} <> Binding{"tui.editor.cursorRight",Right{}} <>
  Binding{"tui.editor.cursorLineStart",Home{}} <> Binding{"tui.editor.cursorLineEnd",End{}} <>
  Binding{"tui.editor.cursorWordLeft",WordLeft{}} <> Binding{"tui.editor.cursorWordRight",WordRight{}} <> Nil{}
def command(entries: List<&2,Binding>,+manager: KB.KeybindingsManager,+context: Keys.Context,+data: String) -> Command:
  match entries:
    case Nil{}: Insert{}
    case Binding{+action,selected} <> rest:
      Bool.pick(Unit -> Command,KB.matches(manager,context,data,action) || (String.eq(action,"tui.input.submit") && String.eq(data,"\n")),_ => selected,_ => command(rest,manager,context,data))(Unit{})
def control(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{+code},+rest}: Bool.pick(Unit -> Bool,U32.is_lt(code,32) || U32.is_eq(code,127) || (U32.is_ge(code,128) && U32.is_le(code,159)),_ => True{},_ => control(rest))(Unit{})
def printable(+state: Editing,data: String,decoded: Maybe<&2,String>) -> Editing:
  match decoded:
    case Some{value}: insertCharacter(state,value)
    case None{}:
      +data = {data: String}
      Bool.pick(Unit -> Editing,control(data),_ => state,_ => insertCharacter(state,data))(Unit{})
def wordMoved(+state: Editing,remove: Bool,+backward: Bool,result: Word.ResultOf(Nat)) -> Word.ResultOf(Editing):
  match state result:
    case Editing{_,cursor,_,_,_} Done{+target}:
      Done{Bool.pick(Editing,remove,kill(state,Nat.min(cursor,target),Nat.max(cursor,target),backward),move(state,target))}
    case _ Fail{error}: Fail{error}
def wordEdit(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),~isAtomic: Context -> String -> Bool,+context: Context,+state: Editing,remove: Bool,+backward: Bool) -> Word.ResultOf(Editing):
  match state:
    case Editing{+value,+cursor,_,_,_}:
      Bool.pick(Unit -> Word.ResultOf(Editing),Bool.pick(Bool,backward,Nat.is_eq(cursor,0n),Nat.is_ge(cursor,String.length(value))),
        _ => Done{state},
        _ => wordMoved(state,remove,backward,Bool.pick(Unit -> Word.ResultOf(Nat),backward,
          _ => Word.findWordBackwardChecked(~Context,~segment,~isAtomic,context,value,cursor),
          _ => Word.findWordForwardChecked(~Context,~segment,~isAtomic,context,value,cursor))(Unit{})))(Unit{})
def editCommand(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),~isAtomic: Context -> String -> Bool,context: Context,+state: Editing,data: String,selected: Command) -> Word.ResultOf(Editing):
  match state selected:
    case _ UndoEdit{}: Done{undoEdit(state)}
    case Editing{+value,+cursor,_,_,_} Backspace{}: Done{Bool.pick(Unit -> Editing,Nat.is_gt(cursor,0n),_ => erase(state,previous(value,cursor),cursor),_ => move(state,cursor))(Unit{})}
    case Editing{+value,+cursor,_,_,_} ForwardDelete{}: Done{Bool.pick(Unit -> Editing,Nat.is_lt(cursor,String.length(value)),_ => erase(state,cursor,following(value,cursor)),_ => move(state,cursor))(Unit{})}
    case _ KillWordBackward{}: wordEdit(~Context,~segment,~isAtomic,context,state,True{},True{})
    case _ KillWordForward{}: wordEdit(~Context,~segment,~isAtomic,context,state,True{},False{})
    case Editing{_,+cursor,_,_,_} KillStart{}: Done{Bool.pick(Unit -> Editing,Nat.is_eq(cursor,0n),_ => state,_ => kill(state,0n,cursor,True{}))(Unit{})}
    case Editing{+value,+cursor,_,_,_} KillEnd{}: Done{Bool.pick(Unit -> Editing,Nat.is_ge(cursor,String.length(value)),_ => state,_ => kill(state,cursor,String.length(value),False{}))(Unit{})}
    case _ Yank{}: Done{yank(state)}
    case _ YankPop{}: Done{yankPop(state)}
    case Editing{value,cursor,_,_,_} Left{}: Done{move(state,previous(value,cursor))}
    case Editing{value,cursor,_,_,_} Right{}: Done{move(state,following(value,cursor))}
    case _ Home{}: Done{move(state,0n)}
    case Editing{value,_,_,_,_} End{}: Done{move(state,String.length(value))}
    case _ WordLeft{}: wordEdit(~Context,~segment,~isAtomic,context,state,False{},True{})
    case _ WordRight{}: wordEdit(~Context,~segment,~isAtomic,context,state,False{},False{})
    case _ Insert{}:
      +data = {data: String}
      Done{printable(state,data,Keys.decodeKittyPrintable(data))}
    case _ _: Done{state}

def escaped(callback: Maybe<&2,C.Callback<Unit,Unit>>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: C.call(Unit,Unit,callback,Unit{})
def submitted(callback: Maybe<&2,C.Callback<String,Unit>>,value: String) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: C.call(String,Unit,callback,value)
def execute(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),~isAtomic: Context -> String -> Bool,context: Context,+state: Input,data: String,selected: Command) -> IO(Word.ResultOf(Input)):
  match state selected:
    case Input{_,_,_,_,_,_,_,callback} Escape{}:
      do IO<Word.ResultOf(Input)>:
        escaped(callback)
        return Done{state}
    case Input{Editing{value,_,_,_,_},_,_,_,_,_,callback,_} Submit{}:
      do IO<Word.ResultOf(Input)>:
        submitted(callback,value)
        return Done{state}
    case Input{editor,_,_,_,_,_,_,_} selected:
      IO.pure(Word.ResultOf(Input),Result.map(&2,&2,Word.Error,Editing,Input,edited => editing(state,edited),editCommand(~Context,~segment,~isAtomic,context,editor,data,selected)))

# Paste parsing retains an incomplete end marker across input chunks.
type Split is Data: Split{before: String,after: String}
def splitAtMarker(text: String,+marker: String,+reversed: String) -> Maybe<&2,Split>:
  match text:
    case SNil{}: None{}
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Maybe<&2,Split>,String.starts_with(SCon{char,rest},marker),_ => Some{Split{String.reverse(reversed),String.drop(SCon{char,rest},String.length(marker))}},_ => splitAtMarker(rest,marker,SCon{char,reversed}))(Unit{})
def cleanPaste(text: String,reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'\r',rest}: cleanPaste(rest,reversed)
    case SCon{'\n',rest}: cleanPaste(rest,reversed)
    case SCon{'\t',rest}: cleanPaste(rest,"    " ++ reversed)
    case SCon{char,rest}: cleanPaste(rest,SCon{char,reversed})
def pasteText(+state: Editing,pasted: String) -> Editing:
  match state:
    case Editing{+value,+cursor,_,_,_}:
      +clean = cleanPaste(pasted,"")
      changed(pushUndo(state),prefix(value,cursor,"") ++ clean ++ String.drop(value,cursor),cursor + String.length(clean),NoAction{})
type Prepared is Data: Ready{state: Input,data: String} Waiting{state: Input} Pasted{state: Input,remaining: String}
def pasteFinished(state: Input,split: Maybe<&2,Split>,buffer: String) -> Prepared:
  match state split:
    case Input{editor,options,start,focused,_,_,submit,escape} Some{Split{before,after}}: Pasted{Input{pasteText(editor,before),options,start,focused,"",False{},submit,escape},after}
    case Input{editor,options,start,focused,_,_,submit,escape} None{}: Waiting{Input{editor,options,start,focused,buffer,True{},submit,escape}}
def bufferPaste(+state: Input,+data: String) -> Prepared:
  match state:
    case Input{_,_,_,_,buffer,pasting,_,_}:
      +combined = buffer ++ data
      Bool.pick(Unit -> Prepared,pasting,_ => pasteFinished(state,splitAtMarker(combined,"\u{1b}[201~",""),combined),_ => Ready{state,data})(Unit{})
def startPaste(state: Input,data: String,split: Maybe<&2,Split>) -> Prepared:
  match state split:
    case Input{editor,options,start,focused,_,_,submit,escape} Some{Split{before,after}}: bufferPaste(Input{editor,options,start,focused,"",True{},submit,escape},before ++ after)
    case state None{}: bufferPaste(state,data)
# Every recursive step consumes a complete six-character paste terminator; the
# suffix is not a structural subterm after buffered chunks are concatenated.
@unsafe def inputLoop(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),~isAtomic: Context -> String -> Bool,+context: Context,+manager: KB.KeybindingsManager,+keyboard: Keys.Context,prepared: Prepared) -> IO(Word.ResultOf(Input)):
  match prepared:
    case Waiting{state}: IO.pure(Word.ResultOf(Input),Done{state})
    case Ready{state,+data}: execute(~Context,~segment,~isAtomic,context,state,data,command(bindings(),manager,keyboard,data))
    case Pasted{+state,+remaining}:
      Bool.pick(Unit -> IO(Word.ResultOf(Input)),String.eq(remaining,""),_ => IO.pure(Word.ResultOf(Input),Done{state}),_ => inputLoop(~Context,~segment,~isAtomic,context,manager,keyboard,startPaste(state,remaining,splitAtMarker(remaining,"\u{1b}[200~",""))))(Unit{})
def handleInput(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),~isAtomic: Context -> String -> Bool,context: Context,state: Input,manager: KB.KeybindingsManager,keyboard: Keys.Context,+data: String) -> IO(Word.ResultOf(Input)):
  inputLoop(~Context,~segment,~isAtomic,context,manager,keyboard,startPaste(state,data,splitAtMarker(data,"\u{1b}[200~","")))

type InputWindow is Data: InputWindow{text: String,cursor: Nat,startColumn: Nat}
def scrolled(+value: String,+cursor: Nat,+available: Nat,+total: Nat) -> InputWindow:
  +scrollWidth = available - Bool.pick(Nat,Nat.is_eq(cursor,String.length(value)),1n,0n)
  +cursorColumn = U.visibleWidth(prefix(value,cursor,""))
  +half = scrollWidth / 2n
  +start = Bool.pick(Nat,Nat.is_lt(cursorColumn,half),0n,Bool.pick(Nat,Nat.is_gt(cursorColumn,total - half),total - scrollWidth,cursorColumn - half))
  Bool.pick(Unit -> InputWindow,Nat.is_gt(scrollWidth,0n),
    _ => InputWindow{U.sliceByColumn(value,start,scrollWidth,True{}),String.length(U.sliceByColumn(value,start,cursorColumn - start,True{})),start},
    _ => InputWindow{"",0n,0n})(Unit{})
def visibleInputWindow(+value: String,+cursor: Nat,+available: Nat) -> InputWindow:
  +total = U.visibleWidth(value)
  Bool.pick(Unit -> InputWindow,Nat.is_lt(total,available),_ => InputWindow{value,cursor,0n},_ => scrolled(value,cursor,available,total))(Unit{})
def cursorMarker(focused: Bool) -> String:
  Bool.pick(String,focused,Tui.CURSOR_MARKER(),"")
def renderedAt(state: Input,start: Nat) -> Input:
  match state:
    case Input{editor,options,_,focused,paste,pasting,submit,escape}: Input{editor,options,start,focused,paste,pasting,submit,escape}
def normalLine(state: Input,prompt: String,available: Nat,focused: Bool,window: InputWindow) -> Input & List<&2,String>:
  match window:
    case InputWindow{+value,+cursor,start}:
      +atCursor = firstCluster(String.drop(value,cursor))
      +line = prefix(value,cursor,"") ++ cursorMarker(focused) ++ "\u{1b}[7m" ++ atCursor ++ "\u{1b}[27m" ++ String.drop(value,cursor + String.length(atCursor))
      (renderedAt(state,start),(prompt ++ U.padResult(line,U.visibleWidth(line),available,True{})) <> Nil{})
def style(callback: Maybe<&2,C.Callback<String,String>>,text: String) -> IO(String):
  match callback:
    case None{}: IO.pure(String,text)
    case Some{callback}: C.call(String,String,callback,text)
def placeholderLine(state: Input,prompt: String,+available: Nat,+focused: Bool,placeholder: String,+callback: Maybe<&2,C.Callback<String,String>>) -> IO(Input & List<&2,String>):
  +text = U.truncateToWidth(placeholder,available,"",False{})
  +atCursor = firstCluster(text)
  do IO<Input & List<&2,String>>:
    +first : String <- style(callback,atCursor)
    +rest : String <- style(callback,String.drop(text,String.length(atCursor)))
    return (state,(prompt ++ U.padResult(cursorMarker(focused) ++ "\u{1b}[7m" ++ first ++ "\u{1b}[27m" ++ rest,U.visibleWidth(cursorMarker(focused) ++ "\u{1b}[7m" ++ first ++ "\u{1b}[27m" ++ rest),available,True{})) <> Nil{})
def render(+state: Input,+width: Nat) -> IO(Input & List<&2,String>):
  match state:
    case Input{Editing{+value,cursor,_,_,_},InputOptions{prompt,placeholder,callback},_,+focused,_,_,_,_}:
      +prompt = Maybe.default(&2,String,prompt,"> ")
      +placeholder = Maybe.default(&2,String,placeholder,"")
      +available = width - U.visibleWidth(prompt)
      Bool.pick(Unit -> IO(Input & List<&2,String>),Nat.is_eq(available,0n),
        _ => IO.pure(Input & List<&2,String>,(state,U.truncateToWidth(prompt,width,"",False{}) <> Nil{})),
        _ => Bool.pick(Unit -> IO(Input & List<&2,String>),String.eq(value,"") && Bool.not(String.eq(placeholder,"")),
          _ => placeholderLine(state,prompt,available,focused,placeholder,callback),
          _ => IO.pure(Input & List<&2,String>,normalLine(state,prompt,available,focused,visibleInputWindow(value,cursor,available))))(Unit{}))(Unit{})

def mouseCursor(parts: List<&2,String>,+target: Nat,column: Nat,+index: Nat) -> Nat:
  match parts:
    case Nil{}: index
    case +part <> rest:
      +next = column + U.visibleWidth(part)
      Bool.pick(Unit -> Nat,Nat.is_lt(target,next),_ => index,_ => mouseCursor(rest,target,next,index + String.length(part)))(Unit{})
def localColumn(value: Tui.Offset) -> Nat:
  match value:
    case Tui.Forward{value}: value - 2n
    case Tui.Backward{_}: 0n
def firstRow(value: Tui.Offset) -> Bool:
  match value:
    case Tui.Forward{Zero{}}: True{}
    case Tui.Backward{Zero{}}: True{}
    case _: False{}
def handleMouse(+state: Input,event: Tui.TuiMouseEvent) -> Input & Maybe<&2,Tui.TuiMouseEventResult>:
  match state event:
    case Input{+editor,_,start,_,_,_,_,_} Tui.TuiMouseEvent{Tui.MousePress{},Tui.MouseLeft{},x,y,_,_,_,_,_,_,_,_,_}:
      Bool.pick(Unit -> Input & Maybe<&2,Tui.TuiMouseEventResult>,firstRow(y),
        _ => (editing(state,move(editor,mouseCursor(Grapheme.segments(getValue(state)),start + localColumn(x),0n,0n))),Some{Tui.TuiMouseEventResult{True{},False{},True{},None{}}}),
        _ => (state,None{}))(Unit{})
    case _ _: (state,None{})
