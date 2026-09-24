import Base
import ./utils.bend as Layout
import ./terminal-image.bend as Image
import ../../runtime/src/f64.bend as F
import ../../runtime/src/u64.bend as Word

# Zero-width hardware cursor marker shared by focused input components.
def CURSOR_MARKER() -> String: "\u{1b}_pi:c\u{7}"

type OverlayAnchor is Data:
  Center{} TopLeft{} TopRight{} BottomLeft{} BottomRight{}
  TopCenter{} BottomCenter{} LeftCenter{} RightCenter{}
type SizeValue is Data:
  Cells{value: Nat}
  Percent{value: F64}
type Offset is Data:
  Forward{cells: Nat}
  Backward{cells: Nat}

type TuiMouseEventType is Data:
  MousePress{} MouseRelease{} MouseMove{} MouseDrag{} MouseClick{} MouseWheel{}
type TuiMouseButton is Data:
  MouseLeft{} MouseMiddle{} MouseRight{} NoButton{}
# Coordinates stay signed when captured input is retargeted outside a component.
type TuiMouseEvent is Data:
  TuiMouseEvent{eventType: TuiMouseEventType,button: TuiMouseButton,x: Offset,y: Offset,screenX: Offset,screenY: Offset,width: Nat,height: Nat,shift: Bool,alt: Bool,ctrl: Bool,wheelDelta: Maybe<&2,Offset>,clickCount: Maybe<&2,Nat>}
type TuiMouseEventResult is Data:
  TuiMouseEventResult{handled: Bool,capture: Bool,focus: Bool,render: Maybe<&2,Bool>}

type OverlayMargin is Data:
  OverlayMargin{top: Nat,right: Nat,bottom: Nat,left: Nat}
type OverlayGeometry is Data:
  OverlayGeometry{width: Maybe<&2,SizeValue>,minWidth: Nat,maxHeight: Maybe<&2,SizeValue>,anchor: OverlayAnchor,offsetX: Offset,offsetY: Offset,row: Maybe<&2,SizeValue>,col: Maybe<&2,SizeValue>,margin: OverlayMargin}
type OverlayLayout is Data:
  OverlayLayout{width: Nat,row: Nat,col: Nat,maxHeight: Maybe<&2,Nat>}
type LayoutError is Data:
  InvalidPercentage{}
  UnrepresentablePosition{}

def defaultOverlayGeometry() -> OverlayGeometry:
  OverlayGeometry{None{},0n,None{},Center{},Forward{0n},Forward{0n},None{},None{},OverlayMargin{0n,0n,0n,0n}}
def dimension(+value: Nat) -> F64:
  F.fromU64(Word.U64{U32.from_nat(value / (65536n * 65536n)),U32.from_nat(value % (65536n * 65536n))})
def floor(value: F64) -> F64: F.negate(F.ceil(F.negate(value)))
def validSize(value: Maybe<&2,SizeValue>) -> Bool:
  match value:
    case Some{Percent{+percent}}: F.isFinite(F.decode(percent)) && F.isAtLeast(F.compare(percent,F.fromU32(0)))
    case _: True{}
def resolveSize(value: Maybe<&2,SizeValue>,reference: F64) -> Maybe<&2,F64>:
  match value:
    case None{}: None{}
    case Some{Cells{count}}: Some{dimension(count)}
    case Some{Percent{percent}}: Some{floor(F.divide(F.multiply(reference,percent),F.fromU32(100)))}
def heightLimit(value: Maybe<&2,F64>,available: F64) -> Maybe<&2,F64>:
  match value:
    case None{}: None{}
    case Some{height}: Some{F.maximum(F.fromU32(1),F.minimum(height,available))}
def rowAnchor(anchor: OverlayAnchor) -> F64:
  match anchor:
    case TopLeft{}: F.fromU32(0)
    case TopCenter{}: F.fromU32(0)
    case TopRight{}: F.fromU32(0)
    case BottomLeft{}: F.fromU32(1)
    case BottomCenter{}: F.fromU32(1)
    case BottomRight{}: F.fromU32(1)
    case _: F.divide(F.fromU32(1),F.fromU32(2))
def colAnchor(anchor: OverlayAnchor) -> F64:
  match anchor:
    case TopLeft{}: F.fromU32(0)
    case LeftCenter{}: F.fromU32(0)
    case BottomLeft{}: F.fromU32(0)
    case TopRight{}: F.fromU32(1)
    case RightCenter{}: F.fromU32(1)
    case BottomRight{}: F.fromU32(1)
    case _: F.divide(F.fromU32(1),F.fromU32(2))
def position(value: Maybe<&2,SizeValue>,anchor: F64,+remaining: F64,margin: F64) -> F64:
  match value:
    case None{}: F.add(margin,floor(F.multiply(remaining,anchor)))
    case Some{Cells{count}}: dimension(count)
    case Some{Percent{percent}}: F.add(margin,floor(F.multiply(F.maximum(F.fromU32(0),remaining),F.divide(percent,F.fromU32(100)))))
def shifted(value: F64,offset: Offset) -> F64:
  match offset:
    case Forward{cells}: F.add(value,dimension(cells))
    case Backward{cells}: F.subtract(value,dimension(cells))
def convertedHeight(value: Result<&2,&2,F.Error,Nat>) -> Result<&2,&2,LayoutError,Maybe<&2,Nat>>:
  match value:
    case Done{count}: Done{Some{count}}
    case Fail{_}: Fail{UnrepresentablePosition{}}
def naturalHeight(value: Maybe<&2,F64>) -> Result<&2,&2,LayoutError,Maybe<&2,Nat>>:
  match value:
    case None{}: Done{None{}}
    case Some{height}: convertedHeight(F.convert(height))
def convertedLayout(width: Result<&2,&2,F.Error,Nat>,row: Result<&2,&2,F.Error,Nat>,col: Result<&2,&2,F.Error,Nat>,maximum: Result<&2,&2,LayoutError,Maybe<&2,Nat>>) -> Result<&2,&2,LayoutError,OverlayLayout>:
  match width row col maximum:
    case Done{width} Done{row} Done{col} Done{maximum}: Done{OverlayLayout{width,row,col,maximum}}
    case _ _ _ _: Fail{UnrepresentablePosition{}}

# Keep signed intermediate anchor coordinates until the final clamp. Clamping
# earlier changes oversized-overlay behavior when a positive offset is added.
def resolvedGeometry(options: OverlayGeometry,+overlayHeight: Nat,termWidth: Nat,termHeight: Nat) -> Result<&2,&2,LayoutError,OverlayLayout>:
  match options:
    case OverlayGeometry{requestedWidth,minWidth,requestedHeight,+anchor,offsetX,offsetY,requestedRow,requestedCol,OverlayMargin{top,right,bottom,left}}:
      +termWidth = dimension(termWidth)
      +termHeight = dimension(termHeight)
      +top = dimension(top)
      +right = dimension(right)
      +bottom = dimension(bottom)
      +left = dimension(left)
      +availableWidth = F.maximum(F.fromU32(1),F.subtract(F.subtract(termWidth,left),right))
      +availableHeight = F.maximum(F.fromU32(1),F.subtract(F.subtract(termHeight,top),bottom))
      desiredWidth = Maybe.default(&2,F64,resolveSize(requestedWidth,termWidth),F.minimum(F.fromU32(80),availableWidth))
      minimumWidth = F.maximum(desiredWidth,dimension(minWidth))
      +width = F.maximum(F.fromU32(1),F.minimum(minimumWidth,availableWidth))
      +maximum = heightLimit(resolveSize(requestedHeight,termHeight),availableHeight)
      +height = F.minimum(dimension(overlayHeight),Maybe.default(&2,F64,maximum,dimension(overlayHeight)))
      anchoredRow = position(requestedRow,rowAnchor(anchor),F.subtract(availableHeight,height),top)
      anchoredCol = position(requestedCol,colAnchor(anchor),F.subtract(availableWidth,width),left)
      lastRow = F.subtract(F.subtract(termHeight,bottom),height)
      lastCol = F.subtract(F.subtract(termWidth,right),width)
      row = F.maximum(top,F.minimum(shifted(anchoredRow,offsetY),lastRow))
      col = F.maximum(left,F.minimum(shifted(anchoredCol,offsetX),lastCol))
      convertedLayout(F.convert(width),F.convert(row),F.convert(col),naturalHeight(maximum))
def resolveOverlayLayout(+options: OverlayGeometry,overlayHeight: Nat,termWidth: Nat,termHeight: Nat) -> Result<&2,&2,LayoutError,OverlayLayout>:
  match options:
    case OverlayGeometry{width,_,height,_,_,_,row,col,_}:
      Bool.pick(Unit -> Result<&2,&2,LayoutError,OverlayLayout>,validSize(width) && validSize(height) && validSize(row) && validSize(col),
        _ => resolvedGeometry(options,overlayHeight,termWidth,termHeight),
        _ => Fail{InvalidPercentage{}})(Unit{})

def segmentReset() -> String: "\u{1b}[0m\u{1b}]8;;\u{7}"

def composed(base: Layout.Segments,overlay: Layout.WidthResult,+startCol: Nat,+overlayWidth: Nat,+totalWidth: Nat) -> String:
  match base overlay:
    case Layout.Segments{before,+beforeWidth,after,+afterWidth} Layout.WidthResult{text,+width}:
      +beforePad = startCol - beforeWidth
      +overlayPad = overlayWidth - width
      +afterTarget = totalWidth - (beforeWidth + beforePad) - (width + overlayPad)
      +result = before ++ Layout.spaces(beforePad,"") ++ segmentReset() ++ text ++ Layout.spaces(overlayPad,"") ++ segmentReset() ++ after ++ Layout.spaces(afterTarget - afterWidth,"")
      Bool.pick(Unit -> String,Nat.is_le(Layout.visibleWidth(result),totalWidth),
        _ => result,
        _ => Layout.sliceByColumn(result,0n,totalWidth,True{}))(Unit{})

# Wide graphemes intersecting an overlay boundary are replaced by padding;
# independent SGR/OSC resets keep styles and hyperlinks within each segment.
def fullLineResult(sliced: Layout.WidthResult,+width: Nat) -> String:
  match sliced:
    case Layout.WidthResult{text,used}:
      segmentReset() ++ text ++ Layout.spaces(width - used,"") ++ segmentReset()
def fullLine(overlayLine: String,+width: Nat) -> String:
  fullLineResult(Layout.sliceWithWidth(overlayLine,0n,width,True{}),width)
def compositeTuiLine(+baseLine: String,+overlayLine: String,+startCol: Nat,+overlayWidth: Nat,+totalWidth: Nat) -> String:
  Bool.pick(Unit -> String,Image.isImageLine(baseLine),_ => baseLine,
    _ => Bool.pick(Unit -> String,String.is_empty(baseLine) && Nat.is_eq(startCol,0n) && Nat.is_eq(overlayWidth,totalWidth),
      _ => fullLine(overlayLine,totalWidth),
      _ => composed(Layout.extractSegments(baseLine,startCol,startCol + overlayWidth,totalWidth - startCol - overlayWidth,True{}),Layout.sliceWithWidth(overlayLine,0n,overlayWidth,True{}),startCol,overlayWidth,totalWidth))(Unit{}))(Unit{})

# Final frame preparation keeps image payloads untouched and extracts only the
# lowest visible cursor marker, retaining markers outside the displayed viewport.
type CursorPosition is Data: CursorPosition{row: Nat,col: Nat}
type CursorFrame is Data: CursorFrame{lines: List<&2,String>,cursor: Maybe<&2,CursorPosition>}
type Marker is Data: Marker{before: String,after: String}
# The marker starts with ESC, so only an ESC position is compared; `found`
# says whether the marker starts at `text`.
def markerAt(+text: String) -> Bool:
  match text:
    case SCon{Chr{27},_}: String.starts_with(text,CURSOR_MARKER())
    case _: False{}
def markerScan(text: String,found: Bool,+reversed: String) -> Maybe<&2,Marker>:
  match text found:
    case text True{}: Some{Marker{String.reverse(reversed),String.drop(text,7n)}}
    case SNil{} False{}: None{}
    case SCon{char,+rest} False{}: markerScan(rest,markerAt(rest),SCon{char,reversed})
def marker(+text: String,reversed: String) -> Maybe<&2,Marker>: markerScan(text,markerAt(text),reversed)
type CursorSearch is Data:
  Searching{reversed: List<&2,String>,suffix: List<&2,String>,height: Nat,row: Nat}
  CursorFound{frame: CursorFrame}
def cursorLine(found: Maybe<&2,Marker>,row: Nat,line: String,remaining: List<&2,String>,suffix: List<&2,String>,height: Nat) -> CursorSearch:
  match found:
    case Some{Marker{+before,after}}: CursorFound{CursorFrame{List.append(&2,String,List.reverse(&2,String,remaining),(before ++ after) <> suffix),Some{CursorPosition{row,Layout.visibleWidth(before)}}}}
    case None{}: Searching{remaining,line <> suffix,height,row}
def cursorStep(search: CursorSearch) -> CursorSearch:
  match search:
    case Searching{Nil{},suffix,_,_}: CursorFound{CursorFrame{suffix,None{}}}
    case Searching{remaining,suffix,Zero{},_}: CursorFound{CursorFrame{List.append(&2,String,List.reverse(&2,String,remaining),suffix),None{}}}
    case Searching{+line <> remaining,suffix,Succ{left},row}: cursorLine(marker(line,""),row - 1n,line,remaining,suffix,left)
    case result: result
def cursorScan(fuel: Nat,search: CursorSearch) -> CursorFrame:
  match fuel search:
    case _ CursorFound{frame}: frame
    case Zero{} Searching{remaining,suffix,_,_}: CursorFrame{List.append(&2,String,List.reverse(&2,String,remaining),suffix),None{}}
    case Succ{left} searching: cursorScan(left,cursorStep(searching))
def extractCursorPosition(+lines: List<&2,String>,height: Nat) -> CursorFrame:
  +length = List.length(&2,String,lines)
  cursorScan(Succ{length},Searching{List.reverse(&2,String,lines),Nil{},height,length})
def resetLines(lines: List<&2,String>,reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: List.reverse(&2,String,reversed)
    case +line <> rest:
      resetLines(rest,Bool.pick(Unit -> String,Image.isImageLine(line),_ => line,_ => Layout.normalizeTerminalOutput(line) ++ segmentReset())(Unit{}) <> reversed)
def applyLineResets(lines: List<&2,String>) -> List<&2,String>: resetLines(lines,Nil{})
