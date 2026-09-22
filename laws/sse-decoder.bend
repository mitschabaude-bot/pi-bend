import Base
import ../packages/runtime/src/sse.bend as SSE

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
