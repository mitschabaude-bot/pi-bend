import Base
import ../laws/tool-truncate.bend as Laws
import ../packages/coding-agent/src/core/tools/truncate.bend as T

def Laws.fitting_text_is_preserved(direction, content, maxLines, maxBytes, fits):
  Equal.cong(Bool,T.TruncationResult,
    accepted => T.truncateWithin(accepted,direction,content,T.splitLinesForCounting(content),T.countLines(T.splitLinesForCounting(content),0n),T.byteLength(content),maxLines,maxBytes),
    Nat.is_le(T.countLines(T.splitLinesForCounting(content),0n),maxLines) && Nat.is_le(T.byteLength(content),maxBytes),True{},fits)
