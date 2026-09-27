import Base
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/http-exchange.bend as HTTP
import ../packages/runtime/src/http-message.bend as Message
import ../packages/runtime/src/http-proxy.bend as Proxy
import ../packages/coding-agent/src/core/http-dispatcher.bend as Dispatcher
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/tls-socket.bend as TLS
import ../packages/runtime/src/tls13-client.bend as Client
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/dns-resolver.bend as DNS
import ../packages/runtime/src/connection-driver.bend as Connect
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/ai/test/anthropic-messages-client.bend as TestClient
import ./tls13-client.bend as Session
import ./aes128-gcm.bend as Bytes

# Native fetch through HTTP proxies (tests/http_proxy_check.py):
# `http-proxy <certificate> <resolver> <hosts> <httpProxy setting|-> <url>...`
# fetches each URL in turn over one runtime built by Fetch.createWithProxy with
# the proxy configuration of the environment and the coding agent's
# `httpProxy` setting, and prints one line per URL: "status <code> <body>",
# "error <proxy message>" for a refused or broken tunnel, "failed" for
# another failure; or "config <message>" when the proxy configuration is
# rejected. TLS origins must present the given certificate. The connection
# options are the coding agent's (core/http-dispatcher.bend).

def pinned(certificate: List<&2, U32>, host: URL.Host) -> IO(Client.Authorization): IO.pure(Client.Authorization, Client.Authorization{chain => Session.pin(certificate, chain)})

def optional(value: String) -> Maybe<&2, String>:
  match value:
    case "-": None{}
    case other: Some{other}

def bodyLine(+status: U32, result: Result<&2, &2, Response.TextError<HTTP.ReadError<Deadline.Cause<Unit>>>, String>) -> String:
  match result:
    case Done{text}: "status " ++ U32.show(status) ++ " " ++ text
    case Fail{_}: "status " ++ U32.show(status) ++ " <unreadable body>"

def tunnelText(error: HTTP.ResolvedExchangeError<Deadline.Cause<Unit>>) -> String:
  match error:
    case HTTP.ResolvedExchangeFailure{HTTP.TunnelFailure{cause}}: "error " ++ Proxy.tunnelMessage(Deadline.Cause<Unit>, cause)
    case _: "failed"

def outcome(result: Fetch.Result_(Unit)) -> IO(String):
  match result:
    case Fail{Fetch.ExchangeFailure{_, _, cause}}: IO.pure(String, tunnelText(cause))
    case Fail{Fetch.ReusedExchangeFailure{cause}}: IO.pure(String, tunnelText(cause))
    case Fail{_}: IO.pure(String, "failed")
    case Done{Response.Response{metadata, body}}:
      do IO<String>:
        +status : U32 <- IO.pure(U32, Response.metadataStatus(metadata))
        text : Result<&2, &2, Response.TextError<HTTP.ReadError<Deadline.Cause<Unit>>>, String> <- HTTP.text(~Deadline.Cause<Unit>, 65536n, body)
        return bodyLine(status, text)

def fetchOne(fetch: Fetch.Fetch(Unit), parsed: Result<&2, &2, URL.Error, URL.URL>) -> IO(Unit):
  match parsed:
    case Fail{_}: IO.print("failed")
    case Done{url}:
      do IO<Unit>:
        +controller : Abort.AbortController<Deadline.Cause<Unit>> <- Abort.new(Deadline.Cause<Unit>)
        result : Fetch.Result_(Unit) <- C.call(Fetch.Input<Unit>, Fetch.Result_(Unit), fetch, Fetch.Input{url, "GET", Message.new(), Message.Absent{}, Abort.signal(Deadline.Cause<Unit>, controller)})
        line : String <- outcome(result)
        IO.print(line)
        Abort.dispose(Deadline.Cause<Unit>, controller)

def fetchAll(+fetch: Fetch.Fetch(Unit), urls: List<String>) -> IO(Unit):
  match urls:
    case Nil{}: IO.pure(Unit, Unit{})
    case url <> rest:
      do IO<Unit>:
        fetchOne(fetch, URL.parse(TestClient.urlContext(), url))
        fetchAll(fetch, rest)

def runWith(pair: Fetch.Runtime & Fetch.Fetch(Unit), urls: List<String>) -> IO(Unit):
  match pair:
    case (runtime, +fetch):
      do IO<Unit>:
        fetchAll(fetch, urls)
        Fetch.retire(Unit, fetch)
        Fetch.dispose(runtime)

def started(result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>, certificate: List<&2, U32>, urls: List<String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "fetch initialization failed")
    case Done{runtime}:
      do IO<Unit>:
        +factory : C.Callback<URL.Host, Client.Authorization> <- C.create(~(List<&2, U32>), ~URL.Host, ~Client.Authorization, ~pinned, certificate)
        pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callbackWithSecurity(~Unit, runtime, HTTP.WithTLS{factory, TLS.defaults()})
        runWith(pair, urls)
        C.dispose(URL.Host, Client.Authorization, factory)


def configured(certificate: List<&2, U32>, resolverPath: String, hostsPath: String, urls: List<String>, config: Result<&2, &2, String, Proxy.Config>) -> IO(Unit):
  match config:
    case Fail{message}: IO.print("config " ++ message)
    case Done{proxies}:
      do IO<Unit>:
        result : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.createWithProxy(Fetch.Files{resolverPath, hostsPath, 4096, 65536n, 2000, 65535}, Dispatcher.httpOptions(), proxies)
        started(result, certificate, urls)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case certificate <> resolverPath <> hostsPath <> setting <> urls:
      do IO<Unit>:
        config : Result<&2, &2, String, Proxy.Config> <- Proxy.fromEnvironmentWith(TestClient.urlContext(), optional(setting))
        configured(Bytes.bytes(certificate), resolverPath, hostsPath, urls, config)
    case _: IO.die(Unit, 1, "expected certificate resolver hosts setting url...")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
