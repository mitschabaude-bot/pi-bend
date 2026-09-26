import Base
import ./loopback-fetch.bend as Network
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/base64.bend as Base64
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/date.bend as Date
import ../packages/runtime/src/tls-socket.bend as TLS
import ../packages/runtime/src/tls13-client.bend as TLSClient
import ../packages/runtime/src/tls-trust.bend as Trust
import ../packages/runtime/src/u64.bend as Word
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/x509.bend as X509
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/http-exchange.bend as HTTP
import ../packages/runtime/src/http-message.bend as H
import ../packages/runtime/src/websocket.bend as WS
import ../packages/runtime/src/websocket-client.bend as Client

def sendChecked(pair: Client.Connection<Unit> & Result<&2, &2, String, Unit>) -> IO(Client.Connection<Unit>):
  match pair:
    case (connection, Done{_}): IO.pure(Client.Connection<Unit>, connection)
    case (connection, Fail{error}):
      do IO<Client.Connection<Unit>>:
        Client.dispose(Unit, connection)
        IO.die(Client.Connection<Unit>, 1, error)

def advance(+payload: String, count: Nat, connection: Client.Connection<Unit>) -> IO(Maybe<&1, Client.Connection<Unit> & Result<&2, &2, String, WS.Message>>):
  match count:
    case 1n:
      do IO<Maybe<&1, Client.Connection<Unit> & Result<&2, &2, String, WS.Message>>>:
        Client.dispose(Unit, connection)
        return None{}
    case 0n:
      do IO<Maybe<&1, Client.Connection<Unit> & Result<&2, &2, String, WS.Message>>>:
        received : Client.Connection<Unit> & Result<&2, &2, String, WS.Message> <- Client.recv(~Unit, connection)
        return Some{received}
    case _:
      do IO<Maybe<&1, Client.Connection<Unit> & Result<&2, &2, String, WS.Message>>>:
        sent : Client.Connection<Unit> & Result<&2, &2, String, Unit> <- Client.sendText(~Unit, connection, payload)
        next : Client.Connection<Unit> <- sendChecked(sent)
        received : Client.Connection<Unit> & Result<&2, &2, String, WS.Message> <- Client.recv(~Unit, next)
        return Some{received}

@unsafe
def message(+payload: String, +count: Nat, pair: Maybe<&1, Client.Connection<Unit> & Result<&2, &2, String, WS.Message>>) -> IO(Unit):
  match pair:
    case None{}: IO.pure(Unit, Unit{})
    case Some{(connection, Fail{error})}:
      do IO<Unit>:
        IO.print("error|" ++ error)
        Client.dispose(Unit, connection)
    case Some{(connection, Done{WS.Ping{bytes}})}:
      do IO<Unit>:
        sent : Client.Connection<Unit> & Result<&2, &2, String, Unit> <- Client.sendPong(~Unit, connection, bytes)
        next : Client.Connection<Unit> <- sendChecked(sent)
        received : Client.Connection<Unit> & Result<&2, &2, String, WS.Message> <- Client.recv(~Unit, next)
        message(payload, count, Some{received})
    case Some{(connection, Done{WS.Pong{_}})}:
      do IO<Unit>:
        received : Client.Connection<Unit> & Result<&2, &2, String, WS.Message> <- Client.recv(~Unit, connection)
        message(payload, count, Some{received})
    case Some{(connection, Done{WS.TextMessage{value}})}:
      do IO<Unit>:
        IO.print(value)
        next : Maybe<&1, Client.Connection<Unit> & Result<&2, &2, String, WS.Message>> <- advance(payload, count, connection)
        message(payload, count - 1n, next)
    case Some{(connection, Done{WS.BinaryMessage{bytes}})}:
      do IO<Unit>:
        IO.print("binary|" ++ Nat.show(List.length(&2, U32, bytes)))
        next : Maybe<&1, Client.Connection<Unit> & Result<&2, &2, String, WS.Message>> <- advance(payload, count, connection)
        message(payload, count - 1n, next)
    case Some{(connection, Done{WS.CloseMessage{code, reason}})}:
      do IO<Unit>:
        IO.print("close|" ++ Maybe.default(&2, String, Maybe.map(&2, U32, String, U32.show, code), "-") ++ "|" ++ reason)
        Client.dispose(Unit, connection)

def opened(+payload: String, count: Nat, result: Result<&2, &1, String, Client.Connection<Unit>>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("error|" ++ error)
    case Done{connection}:
      do IO<Unit>:
        sent : Client.Connection<Unit> & Result<&2, &2, String, Unit> <- Client.sendText(~Unit, connection, payload)
        next : Client.Connection<Unit> <- sendChecked(sent)
        received : Client.Connection<Unit> & Result<&2, &2, String, WS.Message> <- Client.recv(~Unit, next)
        message(payload, count, Some{received})

def abortAfter(+controller: Abort.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(200)
    aborted : Bool <- Abort.abort(Unit, controller, None{})
    return Unit{}

def exercise(url: String, +mode: String, payload: String, pair: Fetch.Runtime & Client.Config) -> IO(Unit):
  match pair:
    case (runtime, config):
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        watcher : Chan(Unit) <- IO.fork(Unit, Bool.pick(Unit -> IO(Unit), String.eq(mode, "cancel"), _ => abortAfter(controller), _ => IO.pure(Unit, Unit{}))(Unit{}))
        +headers : H.Headers <- IO.pure(H.Headers, Result.default(&2, &2, H.HeaderSyntaxError, H.Headers, H.set(H.new(), "Authorization", "Bearer fixture"), H.new()))
        connection : Result<&2, &1, String, Client.Connection<Unit>> <- Client.connect(~Unit, config, url, headers, Abort.signal(Unit, controller))
        opened(payload, Bool.pick(Nat, String.eq(mode, "reuse"), 2n, Bool.pick(Nat, String.eq(mode, "close"), 0n, 1n)), connection)
        IO.join(Unit, watcher)
        Abort.dispose(Unit, controller)
        Fetch.dispose(runtime)

def verifier(host: URL.Host, now: Word.U64, result: Result<&2, &2, X509.Error, X509.Certificate>) -> TLSClient.Authorization:
  match result:
    case Fail{error}: TLSClient.Authorization{_ => Fail{error}}
    case Done{root}: TLSClient.Authorization{chain => Trust.verifySAN(64n, now, host, chain, [root])}

def authorize(certificate: List<&2, U32>, host: URL.Host) -> IO(TLSClient.Authorization):
  do IO<TLSClient.Authorization>:
    now : U32 & U32 <- IO.unixMilliseconds()
    return verifier(host, Date.words(now), X509.parse(certificate))

def initialized(url: String, mode: String, payload: String, security: HTTP.Security, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "network initialization failed")
    case Done{runtime}: exercise(url, mode, payload, Client.borrow(runtime, security, Network.urlContext()))

def run(url: String, mode: String, payload: String, certificate: String) -> IO(Unit):
  do IO<Unit>:
    +factory : C.Callback<URL.Host, TLSClient.Authorization> <- C.create(~List<&2, U32>, ~URL.Host, ~TLSClient.Authorization, ~authorize, Result.default(&2, &2, Base64.Error, List<&2, U32>, Base64.decode(certificate), Nil{}))
    result : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(), Network.networkOptions())
    initialized(url, mode, payload, HTTP.WithTLS{factory, TLS.defaults()}, result)
    C.dispose(URL.Host, TLSClient.Authorization, factory)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case url <> mode <> payload <> Nil{}: run(url, mode, payload, "")
    case url <> mode <> payload <> certificate <> Nil{}: run(url, mode, payload, certificate)
    case _: IO.die(Unit, 1, "usage: websocket-client <url> <mode> <payload> [root-certificate]")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
