import Base
import ../laws/sse-decoder.bend as Laws
import ../packages/runtime/src/sse-decoder.bend as SSE

def Laws.blank_clears_buffers(decoder):
  match decoder:
    case SSE.SSEDecoder{None{}, Nil{}, _}: {==}
    case SSE.SSEDecoder{None{}, _ <> _, _}: {==}
    case SSE.SSEDecoder{Some{SNil{}}, Nil{}, _}: {==}
    case SSE.SSEDecoder{Some{SCon{_, _}}, Nil{}, _}: {==}
    case SSE.SSEDecoder{Some{SNil{}}, _ <> _, _}: {==}
    case SSE.SSEDecoder{Some{SCon{_, _}}, _ <> _, _}: {==}

def Laws.repeated_blank(decoder):
  match decoder:
    case SSE.SSEDecoder{None{}, Nil{}, _}: {==}
    case SSE.SSEDecoder{None{}, _ <> _, _}: {==}
    case SSE.SSEDecoder{Some{SNil{}}, Nil{}, _}: {==}
    case SSE.SSEDecoder{Some{SCon{_, _}}, Nil{}, _}: {==}
    case SSE.SSEDecoder{Some{SNil{}}, _ <> _, _}: {==}
    case SSE.SSEDecoder{Some{SCon{_, _}}, _ <> _, _}: {==}
