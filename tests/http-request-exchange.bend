import Base
import ../packages/runtime/src/url-search-params.bend as Params
import ../packages/runtime/src/url-form.bend as Form
import ../packages/runtime/src/http-buffered-request.bend as Request
import ../packages/runtime/src/http-buffered-body.bend as Body
import ../packages/runtime/src/http-header.bend as H
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/http-socket-exchange.bend as Exchange
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/http-response-stream.bend as Response
import ../packages/runtime/src/http-chunked-body.bend as Chunked
import ./tcp-bytes-probe.bend as Probe

def cleanup(result: Result<&2, &2, Exchange.ReadError<String>, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "exchange cleanup failed")

def close(exchange: Exchange.Exchange<String>) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, Exchange.ReadError<String>, Unit> <- Exchange.close(String, exchange)
    cleanup(result)

def opened(result: Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>>) -> IO(Exchange.Exchange<String>):
  match result:
    case Done{exchange}: IO.pure(Exchange.Exchange<String>, exchange)
    case Fail{_}: IO.die(Exchange.Exchange<String>, 1, "exchange start failed")

def accumulated(value: Response.Event, body: List<&2, U32>) -> List<&2, U32>:
  match value:
    case Response.BodyData{bytes}: List.append(&2, U32, body, bytes)
    case _: body

def finished(exchange: Exchange.Exchange<String>, body: List<&2, U32>) -> IO(Unit):
  match body:
    case 79 <> 75 <> Nil{}: close(exchange)
    case _:
      do IO<Unit>:
        close(exchange)
        IO.die(Unit, 1, "wrong exchange response")

def loop(fuel: Nat, next: Exchange.Next<String>, body: List<&2, U32>) -> IO(Unit):
  match fuel next:
    case _ Exchange.Next{exchange, Done{None{}}}: finished(exchange, body)
    case Succ{rest} Exchange.Next{exchange, Done{Some{event}}}:
      do IO<Unit>:
        next : Exchange.Next<String> <- Exchange.next(String, exchange)
        loop(rest, next, accumulated(event, body))
    case _ Exchange.Next{exchange, _}:
      do IO<Unit>:
        close(exchange)
        IO.die(Unit, 1, "exchange reader failed")

def prepared(socket: Socket, signal: A.AbortSignal<String>, request: Result<&2, &2, Request.RequestError, Request.Prepared>) -> IO(Unit):
  match request:
    case Fail{_}:
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "request preparation failed")
    case Done{value}:
      do IO<Unit>:
        started : Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>> <- Exchange.start(~String, socket, signal, value, 7, Response.Limits{4096n, 65536n, 100n, 8n, Chunked.Limits{1024n, 1024n, 16384n, 100n}})
        exchange : Exchange.Exchange<String> <- opened(started)
        next : Exchange.Next<String> <- Exchange.next(String, exchange)
        loop(128n, next, Nil{})

def requestHeaders(port: U32, chunked: Bool, form: Bool) -> Headers.Headers:
  +host = Headers.appendField(Headers.new(), H.Header{"host", "127.0.0.1:" ++ U32.show(port)})
  json = Bool.pick(Headers.Headers, form, host, Headers.appendField(host, H.Header{"content-type", "application/json"}))
  +fields = Headers.appendField(json, H.Header{"x-byte", "\u{ff}"})
  Bool.pick(Headers.Headers, chunked, Headers.appendField(fields, H.Header{"content-length", "0"}), fields)

def input(form: Bool) -> Body.Input:
  match form:
    case False{}: Body.Text{"{\"text\":\"hé🙂\"}"}
    case True{}: Body.SearchParams{Params.fromEntries(Form.Entry{"scope", "openid email"} <> Form.Entry{"scope", "offline_access"} <> Form.Entry{"state", "hé🙂+&=%"} <> Form.Entry{"", ""} <> Nil{})}

def request(socket: Socket, signal: A.AbortSignal<String>, port: U32, +chunked: Bool, +form: Bool) -> IO(Unit):
  prepared(socket, signal, Request.prepare(Bool.pick(String, chunked, "delete", "post"), "/v1/responses?x=%C3%A9", requestHeaders(port, chunked, form), input(form)))

def cases(count: Nat, +port: U32, +chunked: Bool, +form: Bool) -> IO(Unit):
  match count:
    case Zero{}: IO.print("PASS request exchange")
    case Succ{rest}:
      do IO<Unit>:
        +controller : A.AbortController<String> <- A.new(String)
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
        request(socket, A.signal(String, controller), port, chunked, form)
        A.dispose(String, controller)
        cases(rest, port, Bool.not(chunked), Bool.pick(Bool, chunked, Bool.not(form), form))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(24n, Probe.port(args), False{}, False{})
