import Base
import ../packages/runtime/src/http-request-head.bend as Request
import ../packages/runtime/src/http-header.bend as H
import ../packages/runtime/src/abortable-socket.bend as S
import ../packages/runtime/src/socket-interrupt.bend as I
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/http-response-stream.bend as Response
import ../packages/runtime/src/http-chunked-body.bend as Chunked
import ../packages/runtime/src/http-buffered-body.bend as Body
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/http-buffered-framing.bend as Framing
import ./tcp-bytes-probe.bend as Probe

def cleanup(result: Result<&2, &2, I.Error, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "exchange cleanup failed")

def close(owner: S.Owner<String>) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, I.Error, Unit> <- S.close(String, owner)
    cleanup(result)

def opened(result: Result<&2, &1, S.Error<String>, S.Owner<String>>) -> IO(S.Owner<String>):
  match result:
    case Done{owner}: IO.pure(S.Owner<String>, owner)
    case Fail{_}: IO.die(S.Owner<String>, 1, "exchange adoption failed")

def sent(pair: S.Owner<String> & Result<&2, &2, S.Error<String>, Unit>) -> IO(S.Owner<String>):
  match pair:
    case (owner, Done{_}): IO.pure(S.Owner<String>, owner)
    case (owner, Fail{_}):
      do IO<S.Owner<String>>:
        close(owner)
        IO.die(S.Owner<String>, 1, "exchange send failed")

def payload(events: List<&2, Response.Event>, body: List<&2, U32>) -> List<&2, U32>:
  match events:
    case Nil{}: body
    case Response.BodyData{bytes} <> rest: payload(rest, List.append(&2, U32, body, bytes))
    case _ <> rest: payload(rest, body)

def finished(owner: S.Owner<String>, body: List<&2, U32>, rest: List<&2, U32>) -> IO(Unit):
  match body rest:
    case 79 <> 75 <> Nil{} Nil{}: close(owner)
    case _ _:
      do IO<Unit>:
        close(owner)
        IO.die(Unit, 1, "wrong exchange response")

def decoded(reader: Response.Reader, bytes: List<&2, U32>) -> Response.ReadResult:
  match bytes:
    case Nil{}: Response.finish(reader)
    case head <> rest: Response.read(reader, head <> rest)

def received(reader: Response.Reader, pair: S.Owner<String> & Result<&2, &2, S.Error<String>, List<&2, U32>>) -> IO(S.Owner<String> & Response.ReadResult):
  match pair:
    case (owner, Done{bytes}): IO.pure(S.Owner<String> & Response.ReadResult, (owner, decoded(reader, bytes)))
    case (owner, Fail{_}):
      do IO<S.Owner<String> & Response.ReadResult>:
        close(owner)
        IO.die(S.Owner<String> & Response.ReadResult, 1, "exchange receive failed")

def loop(fuel: Nat, pair: S.Owner<String> & Response.ReadResult, body: List<&2, U32>) -> IO(Unit):
  match fuel pair:
    case _ Tuple{owner, Response.Complete{events, rest}}: finished(owner, payload(events, body), rest)
    case Succ{rest} Tuple{owner, Response.More{reader, events}}:
      do IO<Unit>:
        pair : S.Owner<String> & Result<&2, &2, S.Error<String>, List<&2, U32>> <- S.recv(String, owner, 7)
        next : S.Owner<String> & Response.ReadResult <- received(reader, pair)
        loop(rest, next, payload(events, body))
    case _ Tuple{owner, _}:
      do IO<Unit>:
        close(owner)
        IO.die(Unit, 1, "exchange decoder failed")

def transmit(owner: S.Owner<String>, head: Result<&2, &2, Request.HeadError, Request.Head>, body: List<&2, U32>) -> IO(Unit):
  match head:
    case Fail{_}:
      do IO<Unit>:
        close(owner)
        IO.die(Unit, 1, "exchange request invalid")
    case Done{Request.Head{method, bytes}}:
      do IO<Unit>:
        first : S.Owner<String> & Result<&2, &2, S.Error<String>, Unit> <- S.send(String, owner, bytes)
        owner : S.Owner<String> <- sent(first)
        second : S.Owner<String> & Result<&2, &2, S.Error<String>, Unit> <- S.send(String, owner, body)
        owner : S.Owner<String> <- sent(second)
        loop(128n, (owner, Response.More{Response.new(method, Response.Limits{4096n, 65536n, 100n, 8n, Chunked.Limits{1024n, 1024n, 16384n, 100n}}), Nil{}}), Nil{})

def framed(owner: S.Owner<String>, result: Result<&2, &2, Framing.FramingError, Framing.Prepared>) -> IO(Unit):
  match result:
    case Done{Framing.Prepared{Body.Prepared{method, headers, content}, encoding}}:
      transmit(owner, Request.encode(method, "/v1/responses?x=%C3%A9", Headers.entries(headers)), Framing.wireContent(content, encoding))
    case Fail{_}:
      do IO<Unit>:
        close(owner)
        IO.die(Unit, 1, "exchange framing failed")

def prepared(owner: S.Owner<String>, result: Result<&2, &2, Body.BodyError, Body.Prepared>) -> IO(Unit):
  match result:
    case Done{request}: framed(owner, Framing.prepare(request))
    case Fail{_}:
      do IO<Unit>:
        close(owner)
        IO.die(Unit, 1, "exchange body preparation failed")

def requestHeaders(port: U32, chunked: Bool) -> Headers.Headers:
  host = Headers.appendField(Headers.new(), H.Header{"host", "127.0.0.1:" ++ U32.show(port)})
  json = Headers.appendField(host, H.Header{"content-type", "application/json"})
  +fields = Headers.appendField(json, H.Header{"x-byte", "\u{ff}"})
  Bool.pick(Headers.Headers, chunked, Headers.appendField(fields, H.Header{"content-length", "0"}), fields)

def exchange(owner: S.Owner<String>, port: U32, +chunked: Bool) -> IO(Unit):
  prepared(owner, Body.prepare(Bool.pick(String, chunked, "delete", "post"), requestHeaders(port, chunked), Body.Text{"{\"text\":\"hé🙂\"}"}))

def cases(count: Nat, +port: U32, +chunked: Bool) -> IO(Unit):
  match count:
    case Zero{}: IO.print("PASS request exchange")
    case Succ{rest}:
      do IO<Unit>:
        +controller : A.AbortController<String> <- A.new(String)
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
        created : Result<&2, &1, S.Error<String>, S.Owner<String>> <- S.create(String, socket, A.signal(String, controller))
        owner : S.Owner<String> <- opened(created)
        exchange(owner, port, chunked)
        A.dispose(String, controller)
        cases(rest, port, Bool.not(chunked))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(12n, Probe.port(args), False{})
