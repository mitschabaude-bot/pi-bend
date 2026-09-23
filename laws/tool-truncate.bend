import Base
import ../packages/coding-agent/src/core/tools/truncate.bend as T

# Any text within both limits survives exactly, including terminal newlines,
# with complete and accurate metadata. This covers both public truncators.
law fitting_text_is_preserved:
  for +direction: T.Direction
  for +content: String
  for +maxLines: Nat
  for +maxBytes: Nat
  for fits: {Nat.is_le(T.countLines(T.splitLinesForCounting(content),0n),maxLines) && Nat.is_le(T.byteLength(content),maxBytes) == True{} : Bool}
  {T.truncate(direction,content,T.TruncationOptions{Some{maxLines},Some{maxBytes}}) == T.TruncationResult{content,False{},None{},T.countLines(T.splitLinesForCounting(content),0n),T.byteLength(content),T.countLines(T.splitLinesForCounting(content),0n),T.byteLength(content),False{},False{},maxLines,maxBytes} : T.TruncationResult}
