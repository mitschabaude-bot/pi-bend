import Base
import ./loopback-fetch.bend as Network
import ../packages/ai/src/api/openai-codex-sessions.bend as Sessions
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/http-message.bend as H
import ../packages/runtime/src/http-exchange.bend as HTTP
import ../packages/runtime/src/websocket-client.bend as Client
import ../packages/runtime/src/websocket.bend as WS
import ../packages/runtime/src/f64.bend as F

def opened(runtime: Fetch.Runtime, controller: Abort.AbortController<Deadline.Cause<Unit>>, result: Result<&2, &1, String, Client.Connection<Deadline.Cause<Unit>>>) -> IO(Sessions.Entry<Unit>):
  match result:
    case Fail{message}:
      do IO<Sessions.Entry<Unit>>:
        Abort.dispose(Deadline.Cause<Unit>, controller)
        Fetch.dispose(runtime)
        IO.die(Sessions.Entry<Unit>, 1, message)
    case Done{connection}: IO.pure(Sessions.Entry<Unit>, Sessions.Entry{connection, controller, runtime, F.fromU32(0), F.fromU32(300000), None{}})

def borrowed(url: String, pair: Fetch.Runtime & Client.Config) -> IO(Sessions.Entry<Unit>):
  match pair:
    case (runtime, config):
      do IO<Sessions.Entry<Unit>>:
        +controller : Abort.AbortController<Deadline.Cause<Unit>> <- Abort.new(Deadline.Cause<Unit>)
        connection : Result<&2, &1, String, Client.Connection<Deadline.Cause<Unit>>> <- Client.connect(~Deadline.Cause<Unit>, config, url, H.new(), Abort.signal(Deadline.Cause<Unit>, controller))
        opened(runtime, controller, connection)

def initialized(url: String, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Sessions.Entry<Unit>):
  match result:
    case Fail{_}: IO.die(Sessions.Entry<Unit>, 1, "resolver initialization failed")
    case Done{runtime}: borrowed(url, Client.borrow(runtime, HTTP.NoTLS{}, Network.urlContext()))

def fresh(url: String) -> IO(Sessions.Entry<Unit>):
  do IO<Sessions.Entry<Unit>>:
    result : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(), Network.networkOptions())
    initialized(url, result)

def acquired(url: String, checkout: Sessions.Checkout<Unit>) -> IO(Sessions.Entry<Unit> & Maybe<&2, Sessions.Reservation> & Bool):
  match checkout:
    case Sessions.Reused{ticket, entry}: IO.pure(Sessions.Entry<Unit> & Maybe<&2, Sessions.Reservation> & Bool, (entry, Some{ticket}, True{}))
    case Sessions.Fresh{ticket}:
      do IO<Sessions.Entry<Unit> & Maybe<&2, Sessions.Reservation> & Bool>:
        entry : Sessions.Entry<Unit> <- fresh(url)
        return (entry, ticket, False{})

def sent(result: Client.Connection<Deadline.Cause<Unit>> & Result<&2, &2, String, Unit>) -> IO(Client.Connection<Deadline.Cause<Unit>>):
  match result:
    case (connection, Done{_}): IO.pure(Client.Connection<Deadline.Cause<Unit>>, connection)
    case (connection, Fail{message}):
      do IO<Client.Connection<Deadline.Cause<Unit>>>:
        Client.dispose(Deadline.Cause<Unit>, connection)
        IO.die(Client.Connection<Deadline.Cause<Unit>>, 1, message)

def received(controller: Abort.AbortController<Deadline.Cause<Unit>>, runtime: Fetch.Runtime, created: F64, expires: F64, continuation: Maybe<&2, Sessions.CachedWebSocketContinuationState>, pair: Client.Connection<Deadline.Cause<Unit>> & Result<&2, &2, String, WS.Message>) -> IO(Sessions.Entry<Unit> & Bool):
  match pair:
    case (connection, Done{WS.TextMessage{message}}):
      do IO<Sessions.Entry<Unit> & Bool>:
        IO.print("text|" ++ message)
        return (Sessions.Entry{connection, controller, runtime, created, expires, continuation}, True{})
    case (connection, Fail{message}):
      do IO<Sessions.Entry<Unit> & Bool>:
        IO.print("error|" ++ message)
        return (Sessions.Entry{connection, controller, runtime, created, expires, continuation}, False{})
    case (connection, _): IO.pure(Sessions.Entry<Unit> & Bool, (Sessions.Entry{connection, controller, runtime, created, expires, continuation}, False{}))

def linkedRequest(pool: Sessions.Pool<Unit>, ticket: Maybe<&2, Sessions.Reservation>, payload: String, entry: Sessions.Entry<Unit>, pair: Deadline.Scope<Unit> & Abort.AbortSignal<Deadline.Cause<Unit>>) -> IO(Sessions.Entry<Unit> & Bool):
  match entry pair:
    case Sessions.Entry{connection, +controller, runtime, created, expires, continuation} Tuple{scope, signal}:
      do IO<Sessions.Entry<Unit> & Bool>:
        Sessions.track(Unit, pool, ticket, controller)
        link : Abort.Link<Deadline.Cause<Unit>> <- Abort.link(Deadline.Cause<Unit>, signal, controller)
        sending : Client.Connection<Deadline.Cause<Unit>> & Result<&2, &2, String, Unit> <- Client.sendText(~Deadline.Cause<Unit>, connection, payload)
        active : Client.Connection<Deadline.Cause<Unit>> <- sent(sending)
        pair : Client.Connection<Deadline.Cause<Unit>> & Result<&2, &2, String, WS.Message> <- Client.recv(~Deadline.Cause<Unit>, active)
        Abort.unlink(Deadline.Cause<Unit>, link)
        ignored : Maybe<&2, Abort.AbortReason<Deadline.Cause<Unit>>> <- Deadline.close(Unit, scope)
        received(controller, runtime, created, expires, continuation, pair)

def released(pool: Sessions.Pool<Unit>, ticket: Maybe<&2, Sessions.Reservation>, reused: Bool, now: F64, pair: Sessions.Entry<Unit> & Bool) -> IO(Unit):
  match pair:
    case (entry, keep):
      do IO<Unit>:
        Sessions.release(Unit, pool, ticket, entry, keep, now)
        IO.print(Bool.pick(String, reused, "reused", "fresh"))

def requestWith(+pool: Sessions.Pool<Unit>, parent: Abort.AbortSignal<Unit>, payload: String, now: F64, acquired: Sessions.Entry<Unit> & Maybe<&2, Sessions.Reservation> & Bool) -> IO(Unit):
  match acquired:
    case (entry, +ticket, reused):
      do IO<Unit>:
        scope : Deadline.Scope<Unit> <- Deadline.follow(Unit, parent)
        pair : Sessions.Entry<Unit> & Bool <- linkedRequest(pool, ticket, payload, entry, Deadline.borrow(Unit, scope))
        released(pool, ticket, reused, now, pair)

def request(+pool: Sessions.Pool<Unit>, url: String, session: String, account: String, +now: U32, parent: Abort.AbortSignal<Unit>, payload: String) -> IO(Unit):
  do IO<Unit>:
    checkout : Sessions.Checkout<Unit> <- Sessions.take(Unit, pool, session, account, F.fromU32(now))
    value : Sessions.Entry<Unit> & Maybe<&2, Sessions.Reservation> & Bool <- acquired(url, checkout)
    requestWith(pool, parent, payload, F.fromU32(now), value)

def abortAfter(+controller: Abort.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(100)
    won : Bool <- Abort.abort(Unit, controller, None{})
    return Unit{}

def discardHeld(pool: Sessions.Pool<Unit>, held: Sessions.Checkout<Unit>) -> IO(Unit):
  match held:
    case Sessions.Reused{ticket, entry}: Sessions.release(Unit, pool, Some{ticket}, entry, True{}, F.fromU32(1))
    case _: IO.die(Unit, 1, "expected an existing connection")

def secondStep(+pool: Sessions.Pool<Unit>, +url: String, mode: String, +parent: Abort.AbortSignal<Unit>) -> IO(Unit):
  match mode:
    case "replacement":
      do IO<Unit>:
        held : Sessions.Checkout<Unit> <- Sessions.take(Unit, pool, "session", "account", F.fromU32(1))
        Sessions.clear(Unit, pool, Some{"session"})
        request(pool, url, "session", "account", 1, parent, "second")
        discardHeld(pool, held)
        request(pool, url, "session", "account", 1, parent, "third")
    case "busy":
      do IO<Unit>:
        held : Sessions.Checkout<Unit> <- Sessions.take(Unit, pool, "session", "account", F.fromU32(1))
        request(pool, url, "session", "account", 1, parent, "second")
        original : Sessions.Entry<Unit> & Maybe<&2, Sessions.Reservation> & Bool <- acquired(url, held)
        requestWith(pool, parent, "third", F.fromU32(1), original)
    case +other: request(pool, url, "session", Bool.pick(String, String.eq(other, "account"), "other", "account"), Bool.pick(U32, String.eq(other, "expired"), 300000, Bool.pick(U32, String.eq(other, "age"), 30, 1)), parent, "second")

def run(+url: String, +mode: String) -> IO(Unit):
  do IO<Unit>:
    +pool : Sessions.Pool<Unit> <- Sessions.create(Unit, Bool.pick(Sessions.Policy, String.eq(mode, "age"), Sessions.Policy{300000, 30}, Sessions.defaults()))
    +first : Abort.AbortController<Unit> <- Abort.new(Unit)
    request(pool, url, "session", "account", 0, Abort.signal(Unit, first), "first")
    won : Bool <- Abort.abort(Unit, first, None{})
    Abort.dispose(Unit, first)
    +second : Abort.AbortController<Unit> <- Abort.new(Unit)
    worker : Chan(Unit) <- IO.fork(Unit, Bool.pick(Unit -> IO(Unit), String.eq(mode, "cancel"), _ => abortAfter(second), _ => IO.pure(Unit, Unit{}))(Unit{}))
    secondStep(pool, url, mode, Abort.signal(Unit, second))
    IO.join(Unit, worker)
    Abort.dispose(Unit, second)
    Sessions.dispose(Unit, pool)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case url <> mode <> Nil{}: run(url, mode)
    case _: IO.die(Unit, 1, "usage: openai-codex-sessions <ws-url> <mode>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
