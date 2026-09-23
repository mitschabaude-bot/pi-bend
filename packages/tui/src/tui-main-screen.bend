import Base
import ../../runtime/src/string.bend as Strings
import ./terminal-image.bend as Image
import ./utils.bend as Layout
import ./tui.bend as Tui

# A plan retains shared source strings and compact repetition. Pulling an effect
# materializes at most one 1 Mi UTF-16-unit write, without splitting a scalar.
type Operation is Data: Text{value: String} Repeat{count: Nat,value: String} Flush{} CursorVisibility{visible: Bool}
type Stream is Data: Stream{operations: List<&2,Operation>,work: Nat}
type Effect is Data: Write{value: String} Visibility{visible: Bool}
type Batch is Data: Batch{effect: Effect,rest: Stream}
type Buffer is Data: Buffer{reversed: String,units: Nat}
type Filled is Data: Filled{buffer: Buffer,rest: String}
def operationWork(value: Operation) -> Nat:
  match value:
    case Repeat{count,_}: count * 2n + 1n
    case _: 1n
def streamWork(values: List<&2,Operation>,count: Nat) -> Nat:
  match values:
    case Nil{}: count
    case value <> rest: streamWork(rest,count + operationWork(value))
def stream(+values: List<&2,Operation>) -> Stream: Stream{values,streamWork(values,0n)}
def scalarUnits(char: Char) -> Nat:
  match char:
    case Chr{code}: Bool.pick(Nat,U32.is_gt(code,65535),2n,1n)
def fill(text: String,buffer: Buffer) -> Filled:
  match text buffer:
    case SNil{} buffer: Filled{buffer,""}
    case SCon{+char,+rest} Buffer{+reversed,+units}:
      +size = scalarUnits(char)
      Bool.pick(Unit -> Filled,Nat.is_le(units + size,1048576n),
        _ => fill(rest,Buffer{SCon{char,reversed},units + size}),_ => Filled{Buffer{reversed,units},SCon{char,rest}})(Unit{})
type Pull is Data: Again{stream: Stream,buffer: Buffer} Yield{batch: Maybe<&2,Batch>}
def emit(buffer: Buffer,rest: Stream) -> Pull:
  match buffer:
    case Buffer{SNil{},_}: Again{rest,Buffer{"",0n}}
    case Buffer{reversed,_}: Yield{Some{Batch{Write{String.reverse(reversed)},rest}}}
def filled(value: Filled,+rest: List<&2,Operation>,+work: Nat) -> Pull:
  match value:
    case Filled{Buffer{+reversed,+units},SNil{}}:
      Bool.pick(Pull,Nat.is_eq(units,1048576n),Yield{Some{Batch{Write{String.reverse(reversed)},Stream{rest,work - 1n}}}},Again{Stream{rest,work - 1n},Buffer{reversed,units}})
    case Filled{buffer,text}: emit(buffer,Stream{Text{text} <> rest,work})
def pullStep(value: Stream,buffer: Buffer) -> Pull:
  match value buffer:
    case Stream{Nil{},_} Buffer{SNil{},_}: Yield{None{}}
    case Stream{Nil{},_} buffer: emit(buffer,Stream{Nil{},0n})
    case Stream{Text{text} <> rest,work} buffer: filled(fill(text,buffer),rest,work)
    case Stream{Repeat{Zero{},_} <> rest,work} buffer: Again{Stream{rest,work - 1n},buffer}
    case Stream{Repeat{Succ{count},+text} <> rest,work} buffer: Again{Stream{Text{text} <> Repeat{count,text} <> rest,work - 1n},buffer}
    case Stream{Flush{} <> rest,work} buffer: emit(buffer,Stream{rest,work - 1n})
    case Stream{CursorVisibility{visible} <> rest,work} Buffer{SNil{},_}: Yield{Some{Batch{Visibility{visible},Stream{rest,work - 1n}}}}
    case Stream{CursorVisibility{visible} <> rest,work} buffer: emit(buffer,Stream{CursorVisibility{visible} <> rest,work})
def pull(fuel: Nat,value: Pull) -> Maybe<&2,Batch>:
  match fuel value:
    case _ Yield{batch}: batch
    case Succ{left} Again{rest,buffer}: pull(left,pullStep(rest,buffer))
    case Zero{} _: None{}
def nextEffect(value: Stream) -> Maybe<&2,Batch>:
  match value:
    case Stream{operations,+work}: pull(Succ{work},Again{Stream{operations,work},Buffer{"",0n}})

# None dimensions represent an invalidated render, replacing the JS -1 sentinel.
type TuiMainScreenRenderState is Data:
  TuiMainScreenRenderState{previousLines: List<&2,String>,previousWidth: Maybe<&2,Nat>,previousHeight: Maybe<&2,Nat>,cursorRow: Nat,hardwareCursorRow: Nat,maxLinesRendered: Nat,previousViewportTop: Nat}
type State is Data: State{render: TuiMainScreenRenderState,previousKittyImageIds: List<&2,U32>,fullRedrawCount: Nat}
type Frame is Data: Frame{lines: List<&2,String>,cursor: Maybe<&2,Tui.CursorPosition>,width: Nat,height: Nat}
type Options is Data: Options{termux: Bool,clearOnShrink: Bool,hasOverlayEntries: Bool,showHardwareCursor: Bool,stopped: Bool}
type RedrawReason is Data: FirstRender{} WidthChanged{} HeightChanged{} ClearOnShrink{} DeletedAboveViewport{} ExcessDeletion{} ChangedAboveViewport{} KittyWouldScroll{}
type RenderError is Data: InvalidDimensions{} LineTooWide{index: Nat,actual: Nat,limit: Nat}
type Plan is Data: Plan{state: State,output: Stream,redrawReason: Maybe<&2,RedrawReason>}
def initial() -> State: State{TuiMainScreenRenderState{Nil{},Some{0n},Some{0n},0n,0n,0n,0n},Nil{},0n}
def defaultOptions() -> Options: Options{False{},False{},False{},False{},False{}}
def captureRenderState(state: State) -> TuiMainScreenRenderState:
  match state:
    case State{snapshot,_,_}: snapshot
def blankImages(lines: List<&2,String>,reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: List.reverse(&2,String,reversed)
    case +line <> rest: blankImages(rest,Bool.pick(String,Image.isImageLine(line),"",line) <> reversed)
def restoreRenderState(state: State,snapshot: TuiMainScreenRenderState) -> State:
  match state snapshot:
    case State{_,_,count} TuiMainScreenRenderState{lines,width,height,cursor,hardware,maximum,top}:
      State{TuiMainScreenRenderState{blankImages(lines,Nil{}),width,height,cursor,hardware,maximum,top},Nil{},count}
def resetRenderState(state: State) -> State:
  match state:
    case State{_,ids,count}: State{TuiMainScreenRenderState{Nil{},None{},None{},0n,0n,0n,0n},ids,count}
def movement(+target: Nat,+current: Nat) -> String:
  Bool.pick(String,Nat.is_gt(target,current),"\u{1b}[" ++ Nat.show(target - current) ++ "B",Bool.pick(String,Nat.is_lt(target,current),"\u{1b}[" ++ Nat.show(current - target) ++ "A",""))
def emptyStrings(values: List<&2,String>) -> Bool:
  match values:
    case Nil{}: True{}
    case _: False{}
def emptyIds(values: List<&2,U32>) -> Bool:
  match values:
    case Nil{}: True{}
    case _: False{}
def beforeTerminalStop(state: State,+preserveScreen: Bool) -> Stream:
  match state:
    case State{TuiMainScreenRenderState{+lines,_,_,_,hardware,_,_},_,_}:
      stream(Bool.pick(List<&2,Operation>,preserveScreen || emptyStrings(lines),Nil{},Text{" "} <> Flush{} <> Text{movement(List.length(&2,String,lines),hardware)} <> Flush{} <> Text{"\r\n"} <> Flush{} <> Nil{}))

# IDs retain first-occurrence order, matching Kitty deletion order in a frame.
def containsId(values: List<&2,U32>,+id: U32) -> Bool:
  match values:
    case Nil{}: False{}
    case old <> +rest: Bool.pick(Unit -> Bool,U32.is_eq(old,id),_ => True{},_ => containsId(rest,id))(Unit{})
def addIds(values: List<&2,U32>,+reversed: List<&2,U32>) -> List<&2,U32>:
  match values:
    case Nil{}: reversed
    case +id <> rest: addIds(rest,Bool.pick(List<&2,U32>,containsId(reversed,id),reversed,id <> reversed))
type Header is Data: Header{ids: List<&2,U32>,rows: Nat}
def headerNumber(fields: List<&2,String>) -> Maybe<&2,U32>:
  match fields:
    case _ <> value <> _: Image.decimal(value,0,False{})
    case _: None{}
def headerField(+key: String,value: Maybe<&2,U32>,header: Header) -> Header:
  match value header:
    case Some{+number} Header{+ids,+rows}:
      Bool.pick(Header,U32.is_gt(number,0),Bool.pick(Header,Strings.equal(key,"i"),Header{number <> ids,rows},Bool.pick(Header,Strings.equal(key,"r"),Header{ids,U32.to_nat(number)},Header{ids,rows})),Header{ids,rows})
    case _ header: header
def headerFields(+fields: List<&2,String>,header: Header) -> Header:
  match fields:
    case key <> _: headerField(key,headerNumber(fields),header)
    case Nil{}: header
def headerControls(controls: List<&2,String>,header: Header) -> Header:
  match controls:
    case Nil{}:
      match header:
        case Header{ids,rows}: Header{List.reverse(&2,U32,ids),rows}
    case control <> rest: headerControls(rest,headerFields(Strings.split(control,'='),header))
def parsedHeader(value: Maybe<&2,Image.KittyHeader>) -> Header:
  match value:
    case None{}: Header{Nil{},1n}
    case Some{Image.KittyHeader{_,controls,_}}: headerControls(Strings.split(controls,','),Header{Nil{},1n})
type Row is Data: Row{text: String,width: Nat,image: Bool,ids: List<&2,U32>,requestedRows: Nat}
def rowHeader(+text: String,+image: Bool,header: Header) -> Row:
  match header:
    case Header{ids,rows}: Row{text,Bool.pick(Unit -> Nat,image,_ => 0n,_ => Layout.visibleWidth(text))(Unit{}),image,ids,rows}
def prepareRows(lines: List<&2,String>,reversed: List<&2,Row>) -> List<&2,Row>:
  match lines:
    case Nil{}: List.reverse(&2,Row,reversed)
    case +text <> rest: prepareRows(rest,rowHeader(text,Image.isImageLine(text),parsedHeader(Image.findKitty(text,""))) <> reversed)
def allIds(rows: List<&2,Row>,reversed: List<&2,U32>) -> List<&2,U32>:
  match rows:
    case Nil{}: List.reverse(&2,U32,reversed)
    case Row{_,_,_,ids,_} <> rest: allIds(rest,addIds(ids,reversed))
def reserved(left: Nat,rows: List<&2,Row>,count: Nat) -> Nat:
  match left rows:
    case Succ{left} Row{_,Zero{},False{},_,_} <> rest: reserved(left,rest,Succ{count})
    case _ _: count

def at(rows: List<&2,Row>,index: Nat) -> Maybe<&2,Row>:
  match rows index:
    case Nil{} _: None{}
    case row <> _ Zero{}: Some{row}
    case _ <> rest Succ{index}: at(rest,index)
def rowText(value: Maybe<&2,Row>) -> String:
  match value:
    case Some{Row{text,_,_,_,_}}: text
    case None{}: ""
def textAt(rows: List<&2,Row>,index: Nat) -> String: rowText(at(rows,index))
def rowCount(rows: List<&2,Row>) -> Nat: List.length(&2,Row,rows)
def max(a: Nat,b: Nat) -> Nat: Nat.max(a,b)
def min(a: Nat,b: Nat) -> Nat: Nat.min(a,b)
def maybeChanged(previous: List<&2,Row>,current: List<&2,Row>,+index: Nat) -> Bool:
  Bool.not(Strings.equal(textAt(previous,index),textAt(current,index)))
type Changed is Data: Changed{first: Maybe<&2,Nat>,last: Nat}
def changedValue(value: Changed,+index: Nat,different: Bool) -> Changed:
  match value:
    case Changed{None{},last}: Bool.pick(Changed,different,Changed{Some{index},index},Changed{None{},last})
    case Changed{+first,last}: Bool.pick(Changed,different,Changed{first,index},Changed{first,last})
def changed(left: Nat,+index: Nat,+previous: List<&2,Row>,+current: List<&2,Row>,value: Changed) -> Changed:
  match left:
    case Zero{}: value
    case Succ{left}:
      +different = maybeChanged(previous,current,index)
      +next = changedValue(value,index,different)
      changed(left,Succ{index},previous,current,next)
def reservedFound(found: Maybe<&2,Row>,+rows: List<&2,Row>,+index: Nat,maxIndex: Nat) -> Nat:
  match found:
    case Some{Row{_,_,_,_,+requested}}:
      Bool.pick(Nat,Nat.is_le(requested,1n),1n,1n + reserved(min(requested - 1n,min(maxIndex - index,rowCount(rows) - index - 1n)),List.drop(&2,Row,rows,Succ{index}),0n))
    case None{}: 1n
def reservedRows(+rows: List<&2,Row>,+index: Nat,maxIndex: Nat) -> Nat: reservedFound(at(rows,index),rows,index,maxIndex)
def rowHasIds(found: Maybe<&2,Row>) -> Bool:
  match found:
    case Some{Row{_,_,_,ids,_}}: Bool.not(emptyIds(ids))
    case None{}: False{}
def expandFor(left: Nat,+rows: List<&2,Row>,+index: Nat,+originalFirst: Nat,+originalLast: Nat,expanded: Changed) -> Changed:
  match left expanded:
    case Zero{} _: expanded
    case Succ{left} Changed{Some{+first},+last}:
      +blockEnd = index + reservedRows(rows,index,rowCount(rows) - 1n) - 1n
      +hasIds = rowHasIds(at(rows,index))
      +overlaps = Nat.is_ge(index,originalFirst) || (Nat.is_le(index,originalLast) && Nat.is_ge(blockEnd,originalFirst))
      +next = Bool.pick(Changed,hasIds && overlaps,Changed{Some{min(first,index)},max(last,blockEnd)},Changed{Some{first},last})
      expandFor(left,rows,Succ{index},originalFirst,originalLast,next)
    case _ _: expanded
def appendedRange(base: Changed,appended: Bool,oldCount: Nat,+newCount: Nat) -> Changed:
  match base:
    case Changed{None{},last}: Bool.pick(Changed,appended,Changed{Some{oldCount},newCount - 1n},Changed{None{},last})
    case Changed{+first,last}: Bool.pick(Changed,appended,Changed{first,newCount - 1n},Changed{first,last})
def expandRange(value: Changed,previous: List<&2,Row>,current: List<&2,Row>,oldCount: Nat,newCount: Nat) -> Changed:
  match value:
    case Changed{Some{+first},+last}: expandFor(newCount,current,0n,first,last,expandFor(oldCount,previous,0n,first,last,Changed{Some{first},last}))
    case _: value
def changedRange(+previous: List<&2,Row>,+current: List<&2,Row>) -> Changed:
  +oldCount = rowCount(previous)
  +newCount = rowCount(current)
  +base = changed(max(oldCount,newCount),0n,previous,current,Changed{None{},0n})
  +appended = Nat.is_gt(newCount,oldCount)
  expandRange(appendedRange(base,appended,oldCount,newCount),previous,current,oldCount,newCount)

def deleteIds(ids: List<&2,U32>,reversed: List<&2,Operation>) -> List<&2,Operation>:
  match ids:
    case Nil{}: reversed
    case id <> rest:
      deleteIds(rest,Text{"\u{1b}_Ga=d,d=I,i=" ++ U32.show(id) ++ ",q=2\u{1b}\\"} <> reversed)
def idsInRange(rows: List<&2,Row>,+index: Nat,+last: Nat,+reversed: List<&2,U32>) -> List<&2,U32>:
  match rows:
    case Nil{}: List.reverse(&2,U32,reversed)
    case Row{_,_,_,ids,_} <> rest:
      +next = Bool.pick(List<&2,U32>,Nat.is_le(index,last),addIds(ids,reversed),reversed)
      idsInRange(rest,Succ{index},last,next)
def oldRangeIds(rows: List<&2,Row>,+first: Nat,last: Nat) -> List<&2,U32>:
  idsInRange(List.drop(&2,Row,rows,first),first,last,Nil{})
def appendText(value: String,reversed: List<&2,Operation>) -> List<&2,Operation>: Text{value} <> reversed
def appendMove(target: Nat,current: Nat,+reversed: List<&2,Operation>) -> List<&2,Operation>:
  +value = movement(target,current)
  Bool.pick(List<&2,Operation>,Strings.equal(value,""),reversed,Text{value} <> reversed)
def appendRepeat(+count: Nat,value: String,+reversed: List<&2,Operation>) -> List<&2,Operation>:
  Bool.pick(List<&2,Operation>,Nat.is_eq(count,0n),reversed,Repeat{count,value} <> reversed)
def writeLine(row: Row,+rows: List<&2,Row>,+index: Nat,end: Nat,+height: Nat,+full: Bool,+reversed: List<&2,Operation>) -> List<&2,Operation>:
  match row:
    case Row{+text,_,True{},_,_}:
      +count = reservedRows(rows,index,end)
      Bool.pick(List<&2,Operation>,Nat.is_gt(count,1n) && (Bool.not(full) || Nat.is_le(count,height)),
        appendText("\u{1b}[" ++ Nat.show(count - 1n) ++ "B",appendText(text,appendText("\u{1b}[" ++ Nat.show(count - 1n) ++ "A",appendRepeat(count - 1n,Bool.pick(String,full,"\r\n","\r\n\u{1b}[2K"),Bool.pick(List<&2,Operation>,full,reversed,appendText("\u{1b}[2K",reversed)))))),
        appendText(text,Bool.pick(List<&2,Operation>,full,reversed,appendText("\u{1b}[2K",reversed))))
    case Row{text,_,_,_,_}: appendText(text,Bool.pick(List<&2,Operation>,full,reversed,appendText("\u{1b}[2K",reversed)))
type LinesOutput is Data: LinesOutput{reversed: List<&2,Operation>,finalRow: Nat,kittyScroll: Bool,error: Maybe<&2,RenderError>}
@unsafe def outputLines(rows: List<&2,Row>,+index: Nat,+end: Nat,+height: Nat,+viewportTop: Nat,+full: Bool,+first: Nat,+reversed: List<&2,Operation>) -> LinesOutput:
  match rows:
    case Nil{}: LinesOutput{reversed,Bool.pick(Nat,Nat.is_eq(index,0n),0n,index - 1n),False{},None{}}
    case Row{+text,+width,+image,+ids,+requested} <> +rest:
      +count = Bool.pick(Nat,image,reservedRows(Row{text,width,image,ids,requested} <> rest,0n,end - index),1n)
      +scroll = Bool.not(full) && image && Nat.is_gt(count,1n) && (Nat.is_lt(index,viewportTop) || Nat.is_gt(index - viewportTop + count,height))
      +separator = Bool.pick(List<&2,Operation>,Nat.is_gt(index,first),appendText("\r\n",reversed),reversed)
      +written = writeLine(Row{text,width,image,ids,requested},Row{text,width,image,ids,requested} <> rest,0n,end - index,height,full,separator)
      +skip = Bool.pick(Nat,image && Nat.is_gt(count,1n) && (Bool.not(full) || Nat.is_le(count,height)),count,1n)
      Bool.pick(Unit -> LinesOutput,Nat.is_gt(index,end) || scroll,
        _ => LinesOutput{reversed,index - 1n,Bool.not(Nat.is_gt(index,end)),None{}},
        _ => outputLines(List.drop(&2,Row,Row{text,width,image,ids,requested} <> rest,skip),index + skip,end,height,viewportTop,full,first,written))(Unit{})
def finishFull(body: LinesOutput) -> List<&2,Operation>:
  match body:
    case LinesOutput{reversed,_,_,_}: List.reverse(&2,Operation,Flush{} <> appendText("\u{1b}[?2026l",reversed))
def fullOutput(+rows: List<&2,Row>,height: Nat,+clear: Bool,oldIds: List<&2,U32>) -> List<&2,Operation>:
  +begin = {Text{"\u{1b}[?2026h"} <> Nil{}: List<&2,Operation>}
  +deleted = Bool.pick(List<&2,Operation>,clear,deleteIds(oldIds,begin),begin)
  +cleared = Bool.pick(List<&2,Operation>,clear,appendText("\u{1b}[2J\u{1b}[H\u{1b}[3J",deleted),deleted)
  +length = rowCount(rows)
  finishFull(outputLines(rows,0n,length - 1n,height,0n,True{},0n,cleared))
def cursorOutput(cursor: Maybe<&2,Tui.CursorPosition>,+length: Nat,hardware: Nat,show: Bool,+reversed: List<&2,Operation>) -> List<&2,Operation>:
  match cursor:
    case None{}: CursorVisibility{False{}} <> reversed
    case Some{Tui.CursorPosition{row,col}}:
      Bool.pick(Unit -> List<&2,Operation>,Nat.is_eq(length,0n),
        _ => CursorVisibility{False{}} <> reversed,
        _ => CursorVisibility{show} <> Flush{} <> appendText("\u{1b}[" ++ Nat.show(col + 1n) ++ "G",appendMove(min(row,length - 1n),hardware,reversed)))(Unit{})
def cursorHardware(cursor: Maybe<&2,Tui.CursorPosition>,+length: Nat,hardware: Nat) -> Nat:
  match cursor:
    case Some{Tui.CursorPosition{row,_}}: Bool.pick(Nat,Nat.is_gt(length,0n),min(row,length - 1n),hardware)
    case None{}: hardware
def rowTexts(rows: List<&2,Row>,reversed: List<&2,String>) -> List<&2,String>:
  match rows:
    case Nil{}: List.reverse(&2,String,reversed)
    case Row{text,_,_,_,_} <> rest: rowTexts(rest,text <> reversed)

def committed(state: State,+rows: List<&2,Row>,width: Nat,height: Nat,cursorRow: Nat,hardware: Nat,maximum: Nat,top: Nat,redraw: Bool) -> State:
  match state:
    case State{_,_,count}: State{TuiMainScreenRenderState{rowTexts(rows,Nil{}),Some{width},Some{height},cursorRow,hardware,maximum,top},allIds(rows,Nil{}),count + Bool.pick(Nat,redraw,1n,0n)}

def finish(reversed: List<&2,Operation>) -> Stream: stream(List.reverse(&2,Operation,reversed))
def fullPlan(+state: State,+rows: List<&2,Row>,+cursor: Maybe<&2,Tui.CursorPosition>,+width: Nat,+height: Nat,+options: Options,+clear: Bool,+reason: RedrawReason) -> Plan:
  match state options:
    case State{TuiMainScreenRenderState{_,_,_,_,_,maximum,_},oldIds,_} Options{_,_,_,show,_}:
      +length = rowCount(rows)
      +last = Bool.pick(Nat,Nat.is_eq(length,0n),0n,length - 1n)
      +top = max(height,length) - height
      +body = fullOutput(rows,height,clear,oldIds)
      +hardware = cursorHardware(cursor,length,last)
      +output = finish(cursorOutput(cursor,length,last,show,List.reverse(&2,Operation,body)))
      Plan{committed(state,rows,width,height,last,hardware,Bool.pick(Nat,clear,length,max(maximum,length)),top,True{}),output,Some{reason}}
def fullReason(+state: State,+rows: List<&2,Row>,+cursor: Maybe<&2,Tui.CursorPosition>,+width: Nat,+height: Nat,+options: Options,+reason: RedrawReason) -> Plan:
  fullPlan(state,rows,cursor,width,height,options,True{},reason)
def oldDimension(+value: Maybe<&2,Nat>,+current: Nat) -> Bool:
  match value:
    case Some{Zero{}}: False{}
    case Some{old}: Bool.not(Nat.is_eq(old,current))
    case None{}: True{}
def previousHeightValue(+value: Maybe<&2,Nat>,+current: Nat) -> Nat:
  match value:
    case Some{+old}: Bool.pick(Nat,Nat.is_gt(old,0n),old,current)
    case None{}: current
def previousTop(+snapshot: TuiMainScreenRenderState,+height: Nat,+heightChanged: Bool) -> Nat:
  match snapshot:
    case TuiMainScreenRenderState{_,_,+old,_,_,_,+top}:
      +buffer = Bool.pick(Nat,Nat.is_gt(previousHeightValue(old,height),0n),top + previousHeightValue(old,height),height)
      Bool.pick(Nat,heightChanged,buffer - min(buffer,height),top)
def wideInRange(+rows: List<&2,Row>,+index: Nat,+end: Nat,+width: Nat) -> Maybe<&2,RenderError>:
  match rows:
    case Nil{}: None{}
    case Row{_,+actual,image,_,_} <> rest:
      Bool.pick(Unit -> Maybe<&2,RenderError>,Nat.is_gt(index,end),
        _ => None{},
        _ => Bool.pick(Unit -> Maybe<&2,RenderError>,Bool.not(image) && Nat.is_gt(actual,width),
          _ => Some{LineTooWide{index,actual,width}},
          _ => wideInRange(rest,Succ{index},end,width))(Unit{}))(Unit{})
def changedPreflight(+rows: List<&2,Row>,+first: Nat,+last: Nat,+width: Nat) -> Maybe<&2,RenderError>:
  wideInRange(List.drop(&2,Row,rows,first),first,last,width)
def noChange(+state: State,+rows: List<&2,Row>,+cursor: Maybe<&2,Tui.CursorPosition>,+height: Nat,+top: Nat,+show: Bool) -> Plan:
  match state:
    case State{TuiMainScreenRenderState{lines,width,_,cursorRow,+hardware,maximum,_},ids,count}:
      +length = rowCount(rows)
      +nextHardware = cursorHardware(cursor,length,hardware)
      +output = finish(cursorOutput(cursor,length,hardware,show,Nil{}))
      Plan{State{TuiMainScreenRenderState{lines,width,Some{height},cursorRow,nextHardware,maximum,top},ids,count},output,None{}}
def deletedOutput(+state: State,+old: List<&2,Row>,+rows: List<&2,Row>,+cursor: Maybe<&2,Tui.CursorPosition>,+width: Nat,+height: Nat,+top: Nat,+first: Nat,+last: Nat,+target: Nat,+extra: Nat,+hardware: Nat,+maximum: Nat,+show: Bool) -> Plan:
  +begin = {Text{"\u{1b}[?2026h"} <> Nil{}: List<&2,Operation>}
  +deleted = deleteIds(oldRangeIds(old,first,last),begin)
  +moved = appendMove(target + top,hardware + top,deleted)
  +atColumn = appendText("\r",moved)
  +offset = Bool.pick(Nat,Nat.is_eq(rowCount(rows),0n),0n,1n)
  +down = Bool.pick(List<&2,Operation>,Nat.is_gt(extra,0n) && Nat.is_gt(offset,0n),appendText("\u{1b}[1B",atColumn),atColumn)
  +cleared = appendText("\r\u{1b}[2K",appendRepeat(extra - min(extra,1n),"\r\u{1b}[2K\u{1b}[1B",down))
  +back = appendMove(0n,extra - min(extra,1n) + offset,cleared)
  +end = {Flush{} <> appendText("\u{1b}[?2026l",back): List<&2,Operation>}
  +length = rowCount(rows)
  +positioned = cursorOutput(cursor,length,target,show,end)
  Plan{committed(state,rows,width,height,target,cursorHardware(cursor,length,target),maximum,top,False{}),finish(positioned),None{}}

def deleted(+state: State,+old: List<&2,Row>,+rows: List<&2,Row>,+cursor: Maybe<&2,Tui.CursorPosition>,+width: Nat,+height: Nat,+options: Options,+top: Nat,+first: Nat,+last: Nat) -> Plan:
  match state options:
    case State{TuiMainScreenRenderState{_,_,_,_,hardware,maximum,_},_,_} Options{_,_,_,show,_}:
      +length = rowCount(rows)
      +extra = rowCount(old) - length
      +target = Bool.pick(Nat,Nat.is_eq(length,0n),0n,length - 1n)
      Bool.pick(Unit -> Plan,Nat.is_lt(target,top),
        _ => fullReason(state,rows,cursor,width,height,options,DeletedAboveViewport{}),
        _ => Bool.pick(Unit -> Plan,Nat.is_gt(extra,height),
          _ => fullReason(state,rows,cursor,width,height,options,ExcessDeletion{}),
          _ => deletedOutput(state,old,rows,cursor,width,height,top,first,last,target,extra,hardware,maximum,show))(Unit{}))(Unit{})
def differentialOutput(+state: State,+old: List<&2,Row>,+rows: List<&2,Row>,+cursor: Maybe<&2,Tui.CursorPosition>,+width: Nat,+height: Nat,+top: Nat,+first: Nat,+last: Nat,+moveTarget: Nat,+scroll: Nat,+appendStart: Bool,+hardware: Nat,+maximum: Nat,+show: Bool,+written: List<&2,Operation>,+renderEnd: Nat) -> Plan:
  +begin = {Text{"\u{1b}[?2026h"} <> Nil{}: List<&2,Operation>}
  +deleted = deleteIds(oldRangeIds(old,first,last),begin)
  +screenRow = min(height - 1n,hardware - min(hardware,top))
  +bottomMove = Bool.pick(List<&2,Operation>,Nat.is_gt(scroll,0n),appendMove(height - 1n,screenRow,deleted),deleted)
  +scrolled = appendRepeat(scroll,"\r\n",bottomMove)
  +nextHardware = Bool.pick(Nat,Nat.is_gt(scroll,0n),moveTarget,hardware)
  +moved = appendMove(moveTarget + top + scroll,nextHardware + top + scroll,scrolled)
  +column = appendText(Bool.pick(String,appendStart,"\r\n","\r"),moved)
  +body = List.append(&2,Operation,written,column)
  +length = rowCount(rows)
  +extra = rowCount(old) - min(rowCount(old),length)
  +finalRow = Bool.pick(Nat,Nat.is_gt(extra,0n) && Nat.is_lt(renderEnd,length - 1n),length - 1n,renderEnd)
  +down = Bool.pick(List<&2,Operation>,Nat.is_gt(extra,0n) && Nat.is_lt(renderEnd,length - 1n),appendText("\u{1b}[" ++ Nat.show(length - 1n - renderEnd) ++ "B",body),body)
  +cleared = appendRepeat(extra,"\r\n\u{1b}[2K",down)
  +back = Bool.pick(List<&2,Operation>,Nat.is_gt(extra,0n),appendText("\u{1b}[" ++ Nat.show(extra) ++ "A",cleared),cleared)
  +ended = {Flush{} <> appendText("\u{1b}[?2026l",back): List<&2,Operation>}
  +positioned = cursorOutput(cursor,length,finalRow,show,ended)
  +viewport = max(top + scroll,finalRow - min(finalRow,height - 1n))
  Plan{committed(state,rows,width,height,length - 1n,cursorHardware(cursor,length,finalRow),max(maximum,length),viewport,False{}),finish(positioned),None{}}

def changedResult(+body: LinesOutput,+state: State,+old: List<&2,Row>,+rows: List<&2,Row>,+cursor: Maybe<&2,Tui.CursorPosition>,+width: Nat,+height: Nat,+options: Options,+top: Nat,+first: Nat,+last: Nat,+moveTarget: Nat,+scroll: Nat,+appendStart: Bool,+hardware: Nat,+maximum: Nat,+show: Bool) -> Plan:
  match body:
    case LinesOutput{_,_,True{},_}: fullReason(state,rows,cursor,width,height,options,KittyWouldScroll{})
    case LinesOutput{written,renderEnd,False{},_}:
      differentialOutput(state,old,rows,cursor,width,height,top,first,last,moveTarget,scroll,appendStart,hardware,maximum,show,written,renderEnd)
def changedPlan(+state: State,+old: List<&2,Row>,+rows: List<&2,Row>,+cursor: Maybe<&2,Tui.CursorPosition>,+width: Nat,+height: Nat,+options: Options,+top: Nat,+first: Nat,+last: Nat) -> Plan:
  match state options:
    case State{TuiMainScreenRenderState{_,_,_,_,hardware,maximum,_},_,_} Options{_,_,_,show,_}:
      +oldCount = rowCount(old)
      +length = rowCount(rows)
      +appendStart = Nat.is_gt(length,oldCount) && Nat.is_eq(first,oldCount) && Nat.is_gt(first,0n)
      +moveTarget = Bool.pick(Nat,appendStart,first - 1n,first)
      +bottom = top + height - 1n
      +scroll = Bool.pick(Nat,Nat.is_gt(moveTarget,bottom),moveTarget - bottom,0n)
      +nextTop = top + scroll
      +renderEnd = min(last,length - 1n)
      +body = outputLines(List.drop(&2,Row,rows,first),first,renderEnd,height,nextTop,False{},first,Nil{})
      changedResult(body,state,old,rows,cursor,width,height,options,top,first,last,moveTarget,scroll,appendStart,hardware,maximum,show)
def changedRoute(+state: State,+old: List<&2,Row>,+rows: List<&2,Row>,+cursor: Maybe<&2,Tui.CursorPosition>,+width: Nat,+height: Nat,+options: Options,+heightChanged: Bool,+first: Nat,+last: Nat) -> Plan:
  match state:
    case State{snapshot,_,_}:
      +top = previousTop(snapshot,height,heightChanged)
      Bool.pick(Unit -> Plan,Nat.is_ge(first,rowCount(rows)),
        _ => deleted(state,old,rows,cursor,width,height,options,top,first,last),
        _ => Bool.pick(Unit -> Plan,Nat.is_lt(first,top),
          _ => fullReason(state,rows,cursor,width,height,options,ChangedAboveViewport{}),
          _ => changedPlan(state,old,rows,cursor,width,height,options,top,first,last))(Unit{}))(Unit{})
def noChangeFrom(+state: State,+rows: List<&2,Row>,+cursor: Maybe<&2,Tui.CursorPosition>,+height: Nat,+options: Options,+heightChanged: Bool) -> Plan:
  match state options:
    case State{snapshot,_,_} Options{_,_,_,show,_}: noChange(state,rows,cursor,height,previousTop(snapshot,height,heightChanged),show)
def differentialChanged(+changes: Changed,+state: State,+old: List<&2,Row>,+rows: List<&2,Row>,+cursor: Maybe<&2,Tui.CursorPosition>,+width: Nat,+height: Nat,+options: Options,+heightChanged: Bool) -> Plan:
  match changes:
    case Changed{None{},_}: noChangeFrom(state,rows,cursor,height,options,heightChanged)
    case Changed{Some{first},last}: changedRoute(state,old,rows,cursor,width,height,options,heightChanged,first,last)
def differential(+state: State,+old: List<&2,Row>,+rows: List<&2,Row>,+cursor: Maybe<&2,Tui.CursorPosition>,+width: Nat,+height: Nat,+options: Options,+heightChanged: Bool) -> Plan:
  differentialChanged(changedRange(old,rows),state,old,rows,cursor,width,height,options,heightChanged)
def plan(+state: State,+rows: List<&2,Row>,+cursor: Maybe<&2,Tui.CursorPosition>,+width: Nat,+height: Nat,+options: Options) -> Plan:
  match state options:
    case State{TuiMainScreenRenderState{oldLines,oldWidth,oldHeight,_,_,maximum,_},_,_} Options{termux,shrink,overlays,_,_}:
      +old = prepareRows(oldLines,Nil{})
      +widthChanged = oldDimension(oldWidth,width)
      +heightChanged = oldDimension(oldHeight,height)
      Bool.pick(Unit -> Plan,emptyStrings(oldLines) && Bool.not(widthChanged) && Bool.not(heightChanged),
        _ => fullPlan(state,rows,cursor,width,height,options,False{},FirstRender{}),
        _ => Bool.pick(Unit -> Plan,widthChanged,
          _ => fullReason(state,rows,cursor,width,height,options,WidthChanged{}),
          _ => Bool.pick(Unit -> Plan,heightChanged && Bool.not(termux),
            _ => fullReason(state,rows,cursor,width,height,options,HeightChanged{}),
            _ => Bool.pick(Unit -> Plan,shrink && Nat.is_lt(rowCount(rows),maximum) && Bool.not(overlays),
              _ => fullReason(state,rows,cursor,width,height,options,ClearOnShrink{}),
              _ => differential(state,old,rows,cursor,width,height,options,heightChanged))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def previousRows(state: State) -> List<&2,Row>:
  match state:
    case State{TuiMainScreenRenderState{lines,_,_,_,_,_,_},_,_}: prepareRows(lines,Nil{})
def checkedWidth(problem: Maybe<&2,RenderError>,result: Plan) -> Result<&2,&2,RenderError,Plan>:
  match problem:
    case None{}: Done{result}
    case Some{error}: Fail{error}
def checkedChanged(changes: Changed,rows: List<&2,Row>,width: Nat,result: Plan) -> Result<&2,&2,RenderError,Plan>:
  match changes:
    case Changed{None{},_}: Done{result}
    case Changed{Some{first},last}: checkedWidth(changedPreflight(rows,first,last,width),result)
def checkedResult(changes: Changed,rows: List<&2,Row>,width: Nat,result: Plan) -> Result<&2,&2,RenderError,Plan>:
  match result:
    case Plan{_,_,Some{_}}: Done{result}
    case Plan{_,_,None{}}: checkedChanged(changes,rows,width,result)
def checkedPrepared(+state: State,+rows: List<&2,Row>,cursor: Maybe<&2,Tui.CursorPosition>,+width: Nat,height: Nat,options: Options) -> Result<&2,&2,RenderError,Plan>:
  checkedResult(changedRange(previousRows(state),rows),rows,width,plan(state,rows,cursor,width,height,options))
def checkedPlan(+state: State,+frame: Frame,+options: Options) -> Result<&2,&2,RenderError,Plan>:
  match frame options:
    case Frame{lines,cursor,width,height} Options{termux,shrink,overlays,show,stopped}:
      Bool.pick(Unit -> Result<&2,&2,RenderError,Plan>,stopped,
        _ => Done{Plan{state,stream(Nil{}),None{}}},
        _ => Bool.pick(Unit -> Result<&2,&2,RenderError,Plan>,Nat.is_eq(width,0n) || Nat.is_eq(height,0n),
          _ => Fail{InvalidDimensions{}},
          _ => checkedPrepared(state,prepareRows(lines,Nil{}),cursor,width,height,Options{termux,shrink,overlays,show,stopped}))(Unit{}))(Unit{})
