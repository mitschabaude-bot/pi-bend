import Base
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/http-exchange.bend as HTTP
import ../packages/runtime/src/http-message.bend as Message
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/tls-socket.bend as TLS
import ../packages/runtime/src/tls13-client.bend as Client
import ../packages/runtime/src/x509.bend as X509
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/dns-resolver.bend as DNS
import ../packages/runtime/src/connection-driver.bend as Connect
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/test/utf8-runner.bend as Decimal
import ./tls13-client.bend as Session
import ./aes128-gcm.bend as Bytes
import ./socket-writer.bend as Check

type Authorizer is Data:
  Authorizer{certificate: List<&2, U32>, expected: String, reject: Bool, calls: Ref.Ref<U32>}

def verifier(reject: Bool, certificate: List<&2, U32>) -> Client.Authorization:
  match reject:
    case True{}: Client.Authorization{chain => Fail{X509.NoTrustedPath{}}}
    case False{}: Client.Authorization{chain => Session.pin(certificate, chain)}

def authorize(context: Authorizer, host: URL.Host) -> IO(Client.Authorization):
  match context:
    case Authorizer{certificate, expected, reject, calls}:
      do IO<Client.Authorization>:
        Check.require(String.eq(URL.serializeHost(host), expected), "authorizer received the wrong host")
        count : U32 <- Ref.modify(U32, U32, calls, +count => ((count + 1 : U32), count))
        return verifier(reject, certificate)

def initialized(result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Fetch.Runtime):
  match result:
    case Done{runtime}: IO.pure(Fetch.Runtime, runtime)
    case Fail{_}: IO.die(Fetch.Runtime, 1, "fetch initialization failed")

def consumed(result: Result<&2, &2, Response.TextError<HTTP.ReadError<Deadline.Cause<String>>>, String>) -> IO(Unit):
  match result:
    case Done{text}: Check.require(String.eq(text, "hello"), "wrong fetched body")
    case Fail{_}: IO.die(Unit, 1, "fetch body failed")

def response(result: Fetch.Result_(String), mode: String) -> IO(Unit):
  match result:
    case Fail{Fetch.Rejected{Message.TLSRequired{}}}: Check.require(String.eq(mode, "disabled"), "unexpected TLS rejection")
    case Fail{Fetch.ExchangeFailure{_, _, HTTP.ResolvedExchangeFailure{HTTP.TLSStartFailure{TLS.Protocol{Client.HandshakeFailure{_}}}}}}:
      Check.require(String.eq(mode, "denied"), "unexpected authorization failure")
    case Fail{Fetch.ExchangeFailure{_, _, HTTP.ResolvedExchangeConnectionFailure{Connect.Exhausted{}}}}:
      Check.require(String.eq(mode, "unreachable"), "unexpected connection failure")
    case Fail{_}: IO.die(Unit, 1, "fetch failed")
    case Done{Response.Response{metadata, body}}:
      do IO<Unit>:
        Check.require(U32.is_eq(Response.statusResponseMetadata(metadata), 200), "wrong HTTP status")
        result : Result<&2, &2, Response.TextError<HTTP.ReadError<Deadline.Cause<String>>>, String> <- HTTP.text(~Deadline.Cause<String>, 64n, body)
        consumed(result)

def scheme(plain: Bool) -> URL.Scheme:
  match plain:
    case True{}: URL.Http{}
    case False{}: URL.Https{}

def host(numeric: Bool) -> URL.Host:
  match numeric:
    case True{}: URL.IPv4{URL.Address{2130706433}}
    case False{}: URL.Domain{"tls.test"}

def security(disabled: Bool, factory: C.Callback<URL.Host, Client.Authorization>) -> HTTP.Security:
  match disabled:
    case True{}: HTTP.NoTLS{}
    case False{}: HTTP.WithTLS{factory, TLS.defaults()}

def runFetch(pair: Fetch.Runtime & Fetch.Fetch(String), port: U32, +mode: String) -> IO(Unit):
  match pair:
    case (runtime, +fetch):
      do IO<Unit>:
        +controller : Abort.AbortController<Deadline.Cause<String>> <- Abort.new(Deadline.Cause<String>)
        result : Fetch.Result_(String) <- C.call(Fetch.Input<String>, Fetch.Result_(String), fetch, Fetch.Input{URL.URL{scheme(String.eq(mode, "plain")), "", "", Some{host(String.eq(mode, "numeric"))}, Some{port}, URL.Hierarchical{"" <> Nil{}}, Some{""}, None{}}, "GET", Message.new(), Message.Absent{}, Abort.signal(Deadline.Cause<String>, controller)})
        response(result, mode)
        Fetch.retire(String, fetch)
        Fetch.dispose(runtime)
        Abort.dispose(Deadline.Cause<String>, controller)

def run(port: U32, certificate: List<&2, U32>, resolverPath: String, hostsPath: String, +mode: String) -> IO(Unit):
  do IO<Unit>:
    +calls : Ref.Ref<U32> <- Ref.new(U32, 0)
    +factory : C.Callback<URL.Host, Client.Authorization> <- C.create(~Authorizer, ~URL.Host, ~Client.Authorization, ~authorize, Authorizer{certificate, URL.serializeHost(host(String.eq(mode, "numeric"))), String.eq(mode, "denied"), calls})
    created : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.Files{resolverPath, hostsPath, 4096, 65536n, 2000, 65535}, HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 5000, 7, Response.Limits{4096n, 65536n, 100n, 8n, Message.Limits{1024n, 1024n, 16384n, 100n}}})
    runtime : Fetch.Runtime <- initialized(created)
    pair : Fetch.Runtime & Fetch.Fetch(String) <- Fetch.callbackWithSecurity(~String, runtime, security(String.eq(mode, "disabled"), factory))
    runFetch(pair, port, mode)
    C.dispose(URL.Host, Client.Authorization, factory)
    count : U32 <- Ref.dispose(U32, calls)
    Check.require(U32.is_eq(count, Bool.pick(U32, String.eq(mode, "plain") || String.eq(mode, "disabled") || String.eq(mode, "unreachable"), 0, 1)), "wrong authorizer call count")
    IO.print("PASS")

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case port <> certificate <> resolverPath <> hostsPath <> mode <> Nil{}: run(Decimal.decimal(port, 0), Bytes.bytes(certificate), resolverPath, hostsPath, mode)
    case _: IO.die(Unit, 1, "expected port certificate resolver hosts mode")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
