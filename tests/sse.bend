import Base
import ../src/json.bend as J
import ../src/sse.bend as S

def check(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.print("sse: all tests passed")
    case False{}: IO.die(Unit, 1, "SSE split-frame parsing failed")

def inspect(state: S.State) -> IO(Unit):
  match state:
    case S.State{line, data, events}: check(String.eq(J.encode(J.Array{J.reverse(events, J.End{})}), "[{\"type\":\"a\",\"text\":\"😃\"},{\"type\":\"b\"}]"))

def main() -> IO(Unit):
  inspect(S.feed("b\"}\n\ndata: [DONE]\n\n", S.feed("😃\"}\r\n\n: keepalive\n\ndata: {\"type\":\"", S.feed("data: {\"type\":\"a\",\ndata: \"text\":\"", S.empty()))))
