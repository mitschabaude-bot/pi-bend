import Base
import ../packages/runtime/src/ipv6-connect.bend as Connect
import ../packages/runtime/src/url-ipv6.bend as IPv6
import ../packages/runtime/src/url-record.bend as URL
import ../packages/runtime/src/url-scheme.bend as Scheme
import ../packages/runtime/src/url-host.bend as Host
import ../packages/runtime/src/http-url.bend as Endpoint
import ../packages/runtime/src/http-buffered-request.bend as Request
import ../packages/runtime/src/http-buffered-body.bend as Body
import ../packages/runtime/src/http-header.bend as Header
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/abort.bend as Abort
import ./http-request-exchange.bend as ExchangeTest
import ./tcp-bytes-probe.bend as Probe

# Connect using the typed endpoint returned by request preparation, then reuse
# the full exchange/response-reader test consumer (which owns socket cleanup).
def prepared(result: Result<&2, &2, Request.URLRequestError, Request.URLPrepared>, signal: Abort.AbortSignal<String>) -> IO(Unit):
  match result:
    case Done{Request.URLPrepared{Endpoint.Endpoint{Endpoint.Plaintext{}, Host.IPv6{address}, port, _, _}, request}}:
      do IO<Unit>:
        socket : Socket <- IO.try(Socket, Connect.connect(address, port, 0))
        ExchangeTest.prepared(socket, signal, Done{request})
    case _: IO.die(Unit, 1, "expected a prepared plaintext IPv6 endpoint")

def fields(chunked: Bool) -> Headers.Headers:
  host = Headers.appendField(Headers.new(), Header.Header{"host", "override.invalid"})
  content = Headers.appendField(host, Header.Header{"content-type", "application/json"})
  +headers = Headers.appendField(content, Header.Header{"x-byte", "\u{ff}"})
  Bool.pick(Headers.Headers, chunked, Headers.appendField(headers, Header.Header{"content-length", "0"}), headers)

def url(port: U32, emptyQuery: Bool) -> URL.URL:
  URL.URL{Scheme.Http{}, "", "", Some{Host.IPv6{IPv6.Address{0, 0, 0, 1}}}, Some{port}, URL.Hierarchical{"v1" <> "responses" <> Nil{}}, Some{Bool.pick(String, emptyQuery, "", "x=%C3%A9")}, Some{"ignored"}}

def cases(count: Nat, +port: U32, +chunked: Bool, +emptyQuery: Bool) -> IO(Unit):
  match count:
    case Zero{}: IO.print("PASS IPv6 HTTP exchange")
    case Succ{rest}:
      do IO<Unit>:
        +controller : Abort.AbortController<String> <- Abort.new(String)
        prepared(Request.prepareURL(url(port, emptyQuery), Bool.pick(String, chunked, "delete", "post"), fields(chunked), Body.Text{"{\"text\":\"hé🙂\"}"}), Abort.signal(String, controller))
        Abort.dispose(String, controller)
        cases(rest, port, Bool.not(chunked), Bool.pick(Bool, chunked, Bool.not(emptyQuery), emptyQuery))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(24n, Probe.port(args), False{}, False{})
