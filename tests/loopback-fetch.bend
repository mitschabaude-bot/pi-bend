import Base
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/connection-driver.bend as Connect
import ../packages/runtime/src/dns-resolver.bend as DNS
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/http-exchange.bend as HTTP
import ../packages/runtime/src/http-message.bend as Headers
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/url.bend as URL

# Test-only fetch for library code that addresses a public service: requests
# whose URL starts with `from` go to `loopback` (a local test server) instead,
# and each request is logged as "METHOD URL" followed by its headers, one
# "name: value" per tab-separated field, in Fetch's sorted lowercase order.

def urlContext() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def networkOptions() -> HTTP.Options:
  HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Headers.Limits{8192n, 8192n, 65536n, 100n}}}

def Log() -> Data: Ref.Ref<List<&2, String>>

type Redirect is Data:
  Redirect{inner: Fetch.Fetch(Unit), from: String, loopback: String, log: Log()}

def target(+url: String, +from: String, +loopback: String) -> String:
  Bool.pick(String, String.starts_with(url, from), loopback ++ String.drop(url, String.length(from)), url)

def headerFields(entries: List<&2, Headers.Header>) -> String:
  match entries:
    case Nil{}: ""
    case Headers.Header{name, value} <> rest: "\t" ++ name ++ ": " ++ value ++ headerFields(rest)

def rewritten(parsed: Result<&2, &2, URL.Error, URL.URL>, input: Fetch.Input<Unit>) -> Maybe<&2, Fetch.Input<Unit>>:
  match parsed input:
    case Done{url} Fetch.Input{_, method, headers, body, signal}: Some{Fetch.Input{url, method, headers, body, signal}}
    case _ _: None{}

def forward(inner: Fetch.Fetch(Unit), input: Maybe<&2, Fetch.Input<Unit>>) -> IO(Fetch.Result_(Unit)):
  match input:
    case Some{value}: C.call(Fetch.Input<Unit>, Fetch.Result_(Unit), inner, value)
    case None{}: IO.pure(Fetch.Result_(Unit), Fail{Fetch.InvalidRequest{Headers.BufferedRequestHeaderError{Headers.InvalidName{}}}})

def redirected(redirect: Redirect, input: Fetch.Input<Unit>) -> IO(Fetch.Result_(Unit)):
  match redirect input:
    case Redirect{inner, from, loopback, log} Fetch.Input{+url, +method, +headers, body, signal}:
      +original = URL.serialize(url, False{})
      +line = method ++ " " ++ original ++ headerFields(Headers.entries(headers))
      do IO<Fetch.Result_(Unit)>:
        Ref.modify(List<&2, String>, Unit, log, list => (List.append(&2, String, list, [line]), Unit{}))
        forward(inner, rewritten(URL.parse(urlContext(), target(original, from, loopback)), Fetch.Input{url, method, headers, body, signal}))

def requests(log: Log()) -> IO(List<&2, String>): Ref.read(List<&2, String>, log)

# A redirecting fetch over `inner`, with its own empty request log.
def redirecting(inner: Fetch.Fetch(Unit), from: String, loopback: String) -> IO(Fetch.Fetch(Unit) & Log()):
  do IO<Fetch.Fetch(Unit) & Log()>:
    +log : Log() <- Ref.new(List<&2, String>, Nil{})
    fetch : Fetch.Fetch(Unit) <- C.create(~Redirect, ~(Fetch.Input<Unit>), ~(Fetch.Result_(Unit)), ~redirected, Redirect{inner, from, loopback, log})
    return (fetch, log)

def retired(fetch: Fetch.Fetch(Unit)) -> IO(Unit): C.dispose(Fetch.Input<Unit>, Fetch.Result_(Unit), fetch)

def borrowed(action: Fetch.Fetch(Unit) -> IO(Unit), pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (owned, +inner):
      do IO<Unit>:
        action(inner)
        Fetch.retire(Unit, inner)
        Fetch.dispose(owned)

def initialized(action: Fetch.Fetch(Unit) -> IO(Unit), result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "network initialization failed")
    case Done{runtime}:
      do IO<Unit>:
        pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit, runtime)
        borrowed(action, pair)

# Runs `action` with the native network fetch, then retires it.
def withNetwork(action: Fetch.Fetch(Unit) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(), networkOptions())
    initialized(action, runtime)
