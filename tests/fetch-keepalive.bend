import Base
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/http-exchange.bend as HTTP
import ../packages/runtime/src/http-message.bend as Message
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/dns-resolver.bend as DNS
import ../packages/runtime/src/connection-driver.bend as Connect
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties

# Sequential plaintext fetches through one runtime: <url> <count> <pause ms>.
# Each line reports the status and body; tests/fetch_keepalive_check.py
# counts the server's connections.

def natOf(text: String, +value: Nat) -> Nat:
  match text:
    case SNil{}: value
    case SCon{Chr{code}, rest}: natOf(rest, value * 10n + U32.to_nat((code - 48 : U32)))

def urlContext() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def options() -> HTTP.Options:
  HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Message.Limits{8192n, 8192n, 65536n, 100n}}}

def Signal() -> Data: Abort.AbortSignal<Deadline.Cause<Unit>>

def bodyText(result: Result<&2, &2, Response.TextError<HTTP.ReadError<Deadline.Cause<Unit>>>, String>) -> String:
  match result:
    case Done{text}: text
    case Fail{_}: "<body error>"

def printed(result: Fetch.Result_(Unit)) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("fetch failed")
    case Done{Response.Response{metadata, body}}:
      do IO<Unit>:
        text : Result<&2, &2, Response.TextError<HTTP.ReadError<Deadline.Cause<Unit>>>, String> <- HTTP.text(~Deadline.Cause<Unit>, 65536n, body)
        IO.print(U32.show(Response.metadataStatus(metadata)) ++ " " ++ bodyText(text))

def requests(count: Nat, +fetch: Fetch.Fetch(Unit), +url: URL.URL, +signal: Signal(), +pause: U32) -> IO(Unit):
  match count:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+rest:
      do IO<Unit>:
        result : Fetch.Result_(Unit) <- C.call(Fetch.Input<Unit>, Fetch.Result_(Unit), fetch, Fetch.Input{url, "GET", Message.new(), Message.Absent{}, signal})
        printed(result)
        IO.sleep(pause)
        requests(rest, fetch, url, signal, pause)

def withFetch(count: Nat, url: URL.URL, pause: U32, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (runtime, +fetch):
      do IO<Unit>:
        +controller : Abort.AbortController<Deadline.Cause<Unit>> <- Abort.new(Deadline.Cause<Unit>)
        requests(count, fetch, url, Abort.signal(Deadline.Cause<Unit>, controller), pause)
        Fetch.retire(Unit, fetch)
        Fetch.dispose(runtime)
        Abort.dispose(Deadline.Cause<Unit>, controller)

def started(count: Nat, url: URL.URL, pause: U32, runtime: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Unit):
  match runtime:
    case Fail{_}: IO.die(Unit, 1, "no runtime")
    case Done{value}:
      do IO<Unit>:
        pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit, value)
        withFetch(count, url, pause, pair)

def parsed(count: Nat, pause: U32, url: Result<&2, &2, URL.Error, URL.URL>) -> IO(Unit):
  match url:
    case Fail{_}: IO.die(Unit, 1, "bad url")
    case Done{value}:
      do IO<Unit>:
        runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(), options())
        started(count, value, pause, runtime)

def run(args: List<String>) -> IO(Unit):
  match args:
    case url <> count <> pause <> Nil{}: parsed(natOf(count, 0n), U32.from_nat(natOf(pause, 0n)), URL.parse(urlContext(), url))
    case _: IO.die(Unit, 1, "usage: fetch-keepalive <url> <count> <pause ms>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
