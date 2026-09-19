import Base
import ./http-body.bend as Body
import ./http-head.bend as Head
import ./http-header.bend as H
import ./http-status.bend as Status

# HTTP connection tokens control whether a reset may finish the parser.
# This policy never converts arbitrary transport errors or aborts into EOF.
type Connection is Data:
  Connection{close: Bool, keepAlive: Bool}

def token(value: String, state: Connection) -> Connection:
  match value state:
    case "close" Connection{_, keepAlive}: Connection{True{}, keepAlive}
    case "keep-alive" Connection{close, _}: Connection{close, True{}}
    case _ previous: previous

def tokens(values: List<&2, String>, state: Connection) -> Connection:
  match values:
    case Nil{}: state
    case value <> rest: tokens(rest, token(H.lowercase(H.trim(value)), state))

def field(name: String, value: String, state: Connection) -> Connection:
  match name:
    case "connection": tokens(String.split(value, ','), state)
    case _: state

def fields(values: List<&2, H.Header>, state: Connection) -> Connection:
  match values:
    case Nil{}: state
    case H.Header{name, value} <> rest: fields(rest, field(H.lowercase(name), value, state))

def persistent(modern: Bool, state: Connection) -> Bool:
  match state:
    case Connection{close, keepAlive}: Bool.pick(Bool, modern, Bool.not(close), keepAlive)

# EOF-delimited framing is nonpersistent even with a keep-alive field. For
# self-delimited bodies, HTTP/1.1 defaults to persistence; older versions opt in.
def allowsReset(framing: Body.Framing, head: Head.ResponseHead) -> Bool:
  match framing head:
    case Body.UntilClose{} _: True{}
    case _ Head.ResponseHead{Status.StatusLine{major, minor, _, _}, values}:
      Bool.not(persistent(U32.is_gt(major, 0) && U32.is_gt(minor, 0), fields(values, Connection{False{}, False{}})))
