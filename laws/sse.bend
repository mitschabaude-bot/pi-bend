import Base
import ../packages/runtime/src/sse.bend as Line
import ../packages/runtime/src/sse.bend as SSE

# Line decoder

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

# Pending buffers store bytes in reverse order. Flush emits each pending line
# once; an empty reading buffer is not itself an unfinished line.
def pendingLines(pending: Line.Pending) -> List<&2, String>:
  match pending:
    case Line.Reading{Nil{}}: Nil{}
    case Line.Reading{head <> tail}: Line.lineText(head <> tail) <> Nil{}
    case Line.AfterCarriageReturn{before, Nil{}}: Line.lineText(before) <> Nil{}
    case Line.AfterCarriageReturn{before, head <> tail}: Line.lineText(before) <> Line.lineText(head <> tail) <> Nil{}

law flush_result:
  for +pending: Line.Pending
  {Line.flush(Line.LineDecoder{pending}) == Line.Decoded{Line.create(), pendingLines(pending)} : Line.Decoded}

def lineDecoderOf(result: Line.Decoded) -> Line.LineDecoder:
  match result:
    case Line.Decoded{decoder, _}: decoder

law repeated_flush:
  for decoder: Line.LineDecoder
  {Line.flush(lineDecoderOf(Line.flush(decoder))) == Line.Decoded{Line.create(), Nil{}} : Line.Decoded}


# Sse decoder

type Buffers is Data:
  Buffers{data: List<&2, String>, raw: List<&2, String>}

def decoderOf(result: SSE.DecoderDecoded) -> SSE.SSEDecoder:
  match result:
    case SSE.DecoderDecoded{decoder, _}: decoder

def buffers(decoder: SSE.SSEDecoder) -> Buffers:
  match decoder:
    case SSE.SSEDecoder{_, data, raw}: Buffers{data, raw}

def eventOf(result: SSE.DecoderDecoded) -> Maybe<&2, SSE.ServerSentEvent>:
  match result:
    case SSE.DecoderDecoded{_, event}: event

# Every blank block clears pending data and diagnostics, including empty blocks.
law blank_clears_buffers:
  for decoder: SSE.SSEDecoder
  {buffers(decoderOf(SSE.blank(decoder))) == Buffers{Nil{}, Nil{}} : Buffers}

# A second blank block cannot emit the event from the previous block again.
law repeated_blank:
  for decoder: SSE.SSEDecoder
  {eventOf(SSE.blank(decoderOf(SSE.blank(decoder)))) == None{} : Maybe<&2, SSE.ServerSentEvent>}
