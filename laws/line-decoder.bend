import Base
import ../packages/runtime/src/line-decoder.bend as Line

# Continue collection while retaining the already-emitted lines in the result.
def continueWith(result: Line.Decoded, bytes: List<&2, U32>) -> Line.Decoded:
  Line.collect(bytes, result, Nil{})

law empty_chunk:
  for +decoder: Line.LineDecoder
  {Line.decode(decoder, Nil{}) == Line.Decoded{decoder, Nil{}} : Line.Decoded}

law chunk_composition:
  for +decoder: Line.LineDecoder
  for +first: List<&2, U32>
  for +second: List<&2, U32>
  {continueWith(Line.decode(decoder, first), second) == Line.decode(decoder, List.append(&2, U32, first, second)) : Line.Decoded}

def withPrefix(lines: List<&2, String>, result: Line.Decoded) -> Line.Decoded:
  match result:
    case Line.Decoded{decoder, emitted}: Line.Decoded{decoder, List.append(&2, String, lines, emitted)}

# Continuing collection is exactly independent decode plus chronological output.
law continuation_output:
  for +decoder: Line.LineDecoder
  for +lines: List<&2, String>
  for +bytes: List<&2, U32>
  {continueWith(Line.Decoded{decoder, lines}, bytes) == withPrefix(lines, Line.decode(decoder, bytes)) : Line.Decoded}
