import Base
import ./utils.bend as Layout
import ./terminal-image.bend as Image

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
def compositeTuiLine(+baseLine: String,overlayLine: String,+startCol: Nat,+overlayWidth: Nat,+totalWidth: Nat) -> String:
  Bool.pick(Unit -> String,Image.isImageLine(baseLine),_ => baseLine,
    _ => composed(Layout.extractSegments(baseLine,startCol,startCol + overlayWidth,totalWidth - startCol - overlayWidth,True{}),Layout.sliceWithWidth(overlayLine,0n,overlayWidth,True{}),startCol,overlayWidth,totalWidth))(Unit{})
