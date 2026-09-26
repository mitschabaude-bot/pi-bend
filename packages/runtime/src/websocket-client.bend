import Base
import ./websocket.bend as WS
import ./abort.bend as Abort
import ./base64.bend as Base64
import ./callback.bend as C
import ./connection-driver.bend as Driver
import ./dns-resolver.bend as DNS
import ./fetch.bend as Fetch
import ./http-exchange.bend as HTTP
import ./http-message.bend as H
import ./socket.bend as Net
import ./tls-socket.bend as TLS
import ./tls13-client.bend as TLSClient
import ./url.bend as URL
import ./utf8.bend as UTF8

# A native duplex connection, independent of HTTP response-body framing and
# fetch keep-alive pools. The caller owns the signal, resolver and TLS policy;
# they remain alive until the connection is disposed.
type Config is Data:
  Config{resolver: DNS.Resolver, hosts: Fetch.HostsResult(), options: HTTP.Options, security: HTTP.Security, url: URL.Context}
type Wire<-Reason: Data> is Type:
  Plain{socket: Net.Owner<Reason>}
  Secure{connection: TLS.Connection<Reason>, writer: TLS.Writer<Reason>}
type Connection<-Reason: Data> is Type:
  Connection{wire: Wire<Reason>, decoder: WS.Decoder, pending: List<&2, U32>, readSize: U32}

def withResolver(+hosts: Fetch.HostsResult(), +options: HTTP.Options, pools: List<&2, C.Callback<Unit, Unit>>, security: HTTP.Security, url: URL.Context, pair: DNS.Owner & DNS.Resolver) -> Fetch.Runtime & Config:
  match pair:
    case (owner, resolver): (Fetch.Runtime{owner, hosts, options, pools}, Config{resolver, hosts, options, security, url})

def borrow(runtime: Fetch.Runtime, security: HTTP.Security, url: URL.Context) -> Fetch.Runtime & Config:
  match runtime:
    case Fetch.Runtime{owner, hosts, options, pools}: withResolver(hosts, options, pools, security, url, DNS.borrow(owner))

def closeWire(-Reason: Data, wire: Wire<Reason>) -> IO(Unit):
  match wire:
    case Plain{socket}:
      do IO<Unit>:
        ignored : Result<&2, &2, Net.InterruptError, Unit> <- Net.close(Reason, socket)
        return Unit{}
    case Secure{connection, _}:
      do IO<Unit>:
        ignored : Result<&2, &2, TLS.Error<Reason>, Unit> <- TLS.dispose(Reason, connection)
        return Unit{}

def dispose(-Reason: Data, connection: Connection<Reason>) -> IO(Unit):
  match connection:
    case Connection{wire, _, _, _}: closeWire(Reason, wire)

def outcome(-E: Data, -A: Data, message: String, result: Result<&2, &2, E, A>) -> Result<&2, &2, String, A>:
  match result:
    case Fail{_}: Fail{message}
    case Done{value}: Done{value}

def plainSent(-Reason: Data, pair: Net.Owner<Reason> & Result<&2, &2, Net.Error<Reason>, Unit>) -> Wire<Reason> & Result<&2, &2, String, Unit>:
  match pair:
    case (socket, result): (Plain{socket}, outcome(Net.Error<Reason>, Unit, "WebSocket send failed", result))

def sendWire(-Reason: Data, wire: Wire<Reason>, bytes: List<&2, U32>) -> IO(Wire<Reason> & Result<&2, &2, String, Unit>):
  match wire:
    case Plain{socket}:
      do IO<Wire<Reason> & Result<&2, &2, String, Unit>>:
        sent : Net.Owner<Reason> & Result<&2, &2, Net.Error<Reason>, Unit> <- Net.sendSocket(Reason, socket, bytes)
        return plainSent(Reason, sent)
    case Secure{connection, +writer}:
      do IO<Wire<Reason> & Result<&2, &2, String, Unit>>:
        result : Result<&2, &2, TLS.Error<Reason>, Unit> <- TLS.send(Reason, writer, bytes)
        return (Secure{connection, writer}, outcome(TLS.Error<Reason>, Unit, "WebSocket send failed", result))

def plainRead(-Reason: Data, pair: Net.Owner<Reason> & Result<&2, &2, Net.Error<Reason>, List<&2, U32>>) -> Wire<Reason> & Result<&2, &2, String, List<&2, U32>>:
  match pair:
    case (socket, result): (Plain{socket}, outcome(Net.Error<Reason>, List<&2, U32>, "WebSocket read failed", result))
def secureRead(-Reason: Data, writer: TLS.Writer<Reason>, pair: TLS.Connection<Reason> & Result<&2, &2, TLS.Error<Reason>, List<&2, U32>>) -> Wire<Reason> & Result<&2, &2, String, List<&2, U32>>:
  match pair:
    case (connection, result): (Secure{connection, writer}, outcome(TLS.Error<Reason>, List<&2, U32>, "WebSocket read failed", result))

def readWire(-Reason: Data, wire: Wire<Reason>, maximum: U32) -> IO(Wire<Reason> & Result<&2, &2, String, List<&2, U32>>):
  match wire:
    case Plain{socket}:
      do IO<Wire<Reason> & Result<&2, &2, String, List<&2, U32>>>:
        result : Net.Owner<Reason> & Result<&2, &2, Net.Error<Reason>, List<&2, U32>> <- Net.recvSocket(Reason, socket, maximum)
        return plainRead(Reason, result)
    case Secure{connection, writer}:
      do IO<Wire<Reason> & Result<&2, &2, String, List<&2, U32>>>:
        result : TLS.Connection<Reason> & Result<&2, &2, TLS.Error<Reason>, List<&2, U32>> <- TLS.recv(Reason, connection, maximum)
        return secureRead(Reason, writer, result)

# Upgrade parsing has its own cursor so 101 is never treated as a fetch body.
def failedUpgrade(-Reason: Data, wire: Wire<Reason>, error: String) -> IO(Result<&2, &1, String, Connection<Reason>>):
  do IO<Result<&2, &1, String, Connection<Reason>>>:
    closeWire(Reason, wire)
    return Fail{error}

def acceptedUpgrade(-Reason: Data, wire: Wire<Reason>, size: U32, pending: List<&2, U32>, result: Result<&2, &2, String, Unit>) -> IO(Result<&2, &1, String, Connection<Reason>>):
  match result:
    case Fail{error}: failedUpgrade(Reason, wire, error)
    case Done{_}: IO.pure(Result<&2, &1, String, Connection<Reason>>, Done{Connection{wire, WS.new(16777216n), pending, size}})

type UpgradeState<-Reason: Data> is Type:
  ReadingUpgrade{wire: Wire<Reason>, head: H.HeadReadResult}
  UpgradeFailed{wire: Wire<Reason>, error: String}

def upgradeReceived(-Reason: Data, reader: H.HeadReader, received: Wire<Reason> & Result<&2, &2, String, List<&2, U32>>) -> UpgradeState<Reason>:
  match received:
    case (wire, Fail{error}): UpgradeFailed{wire, error}
    case (wire, Done{Nil{}}): UpgradeFailed{wire, "WebSocket closed during upgrade"}
    case (wire, Done{bytes}): ReadingUpgrade{wire, H.readHead(reader, bytes)}

@unsafe
def readUpgrade(-Reason: Data, +key: String, +size: U32, state: UpgradeState<Reason>) -> IO(Result<&2, &1, String, Connection<Reason>>):
  match state:
    case UpgradeFailed{wire, error}: failedUpgrade(Reason, wire, error)
    case ReadingUpgrade{wire, H.HeadFailed{_}}: failedUpgrade(Reason, wire, "Invalid WebSocket response headers")
    case ReadingUpgrade{wire, H.HeadComplete{+head, rest}}: acceptedUpgrade(Reason, wire, size, rest, WS.handshake(head, key))
    case ReadingUpgrade{wire, H.HeadMore{reader}}:
      do IO<Result<&2, &1, String, Connection<Reason>>>:
        received : Wire<Reason> & Result<&2, &2, String, List<&2, U32>> <- readWire(Reason, wire, size)
        readUpgrade(Reason, key, size, upgradeReceived(Reason, reader, received))

def sentUpgrade(-Reason: Data, key: String, size: U32, pair: Wire<Reason> & Result<&2, &2, String, Unit>) -> IO(Result<&2, &1, String, Connection<Reason>>):
  match pair:
    case (wire, Fail{error}): failedUpgrade(Reason, wire, error)
    case (wire, Done{_}): readUpgrade(Reason, key, size, ReadingUpgrade{wire, H.HeadMore{H.newHead(8192n, 65536n, 100n)}})

def upgrade(-Reason: Data, wire: Wire<Reason>, key: String, size: U32, request: H.BufferedRequestPrepared) -> IO(Result<&2, &1, String, Connection<Reason>>):
  match request:
    case H.BufferedRequestPrepared{H.Head{_, bytes}, _}:
      do IO<Result<&2, &1, String, Connection<Reason>>>:
        sent : Wire<Reason> & Result<&2, &2, String, Unit> <- sendWire(Reason, wire, bytes)
        sentUpgrade(Reason, key, size, sent)

def secureWire(-Reason: Data, pair: TLS.Connection<Reason> & TLS.Writer<Reason>) -> Wire<Reason>:
  match pair:
    case (connection, writer): Secure{connection, writer}

def secured(-Reason: Data, key: String, size: U32, request: H.BufferedRequestPrepared, result: Result<&2, &1, TLS.Error<Reason>, TLS.Connection<Reason>>) -> IO(Result<&2, &1, String, Connection<Reason>>):
  match result:
    case Fail{_}: IO.pure(Result<&2, &1, String, Connection<Reason>>, Fail{"WebSocket TLS handshake failed"})
    case Done{connection}: upgrade(Reason, secureWire(Reason, TLS.borrowWriter(Reason, connection)), key, size, request)

def handshaking(-Reason: Data, key: String, size: U32, request: H.BufferedRequestPrepared, initial: Result<&2, &1, TLS.Error<Reason>, TLS.Connection<Reason>>) -> IO(Result<&2, &1, String, Connection<Reason>>):
  match initial:
    case Fail{_}: IO.pure(Result<&2, &1, String, Connection<Reason>>, Fail{"WebSocket TLS handshake failed"})
    case Done{connection}:
      do IO<Result<&2, &1, String, Connection<Reason>>>:
        authenticated : Result<&2, &1, TLS.Error<Reason>, TLS.Connection<Reason>> <- TLS.awaitHandshake(Reason, connection)
        secured(Reason, key, size, request, authenticated)

def adopted(-Reason: Data, protocol: HTTP.Protocol, key: String, size: U32, request: H.BufferedRequestPrepared, result: Result<&2, &1, Net.Error<Reason>, Net.Owner<Reason>>) -> IO(Result<&2, &1, String, Connection<Reason>>):
  match result protocol:
    case Fail{_} _: IO.pure(Result<&2, &1, String, Connection<Reason>>, Fail{"WebSocket connection failed"})
    case Done{owner} HTTP.Cleartext{}: upgrade(Reason, Plain{owner}, key, size, request)
    case Done{owner} HTTP.Encrypted{+host, authorize, options}:
      do IO<Result<&2, &1, String, Connection<Reason>>>:
        authorization : TLSClient.Authorization <- C.call(URL.Host, TLSClient.Authorization, authorize, host)
        initial : Result<&2, &1, TLS.Error<Reason>, TLS.Connection<Reason>> <- TLS.start(Reason, owner, HTTP.serverName(host), authorization, options)
        handshaking(Reason, key, size, request, initial)

def opened(~Reason: Data, signal: Abort.AbortSignal<Reason>, protocol: HTTP.Protocol, key: String, size: U32, request: H.BufferedRequestPrepared, report: Driver.PlanReport<HTTP.Resolution(Reason, Fetch.SourceError()), Reason, Socket>) -> IO(Result<&2, &1, String, Connection<Reason>>):
  match report:
    case Driver.Unresolved{_}: IO.pure(Result<&2, &1, String, Connection<Reason>>, Fail{"WebSocket DNS lookup failed"})
    case Driver.Attempted{_, Driver.Report{Fail{_}, _}}: IO.pure(Result<&2, &1, String, Connection<Reason>>, Fail{"WebSocket connection failed"})
    case Driver.Attempted{_, Driver.Report{Done{socket}, _}}:
      do IO<Result<&2, &1, String, Connection<Reason>>>:
        result : Result<&2, &1, Net.Error<Reason>, Net.Owner<Reason>> <- Net.create(Reason, socket, signal)
        adopted(Reason, protocol, key, size, request, result)

def connectProtocol(~Reason: Data, +signal: Abort.AbortSignal<Reason>, config: Config, key: String, host: URL.Host, port: U32, request: H.BufferedRequestPrepared, protocol: Result<&2, &2, H.ExchangePlanError, HTTP.Protocol>) -> IO(Result<&2, &1, String, Connection<Reason>>):
  match config protocol:
    case _ Fail{_}: IO.pure(Result<&2, &1, String, Connection<Reason>>, Fail{"WebSocket TLS policy required"})
    case Config{resolver, hosts, HTTP.Options{priority, preference, duration, size, _}, _, _} Done{protocol}:
      do IO<Result<&2, &1, String, Connection<Reason>>>:
        report : Driver.PlanReport<HTTP.Resolution(Reason, Fetch.SourceError()), Reason, Socket> <- HTTP.open(~Reason, ~(Fetch.SourceError()), resolver, signal, priority, preference, Driver.Options{port, duration}, host, hosts)
        opened(~Reason, signal, protocol, key, size, request, report)

def prepared(~Reason: Data, signal: Abort.AbortSignal<Reason>, +config: Config, key: String, result: Result<&2, &2, H.URLRequestError, H.URLPrepared>) -> IO(Result<&2, &1, String, Connection<Reason>>):
  match config result:
    case _ Fail{_}: IO.pure(Result<&2, &1, String, Connection<Reason>>, Fail{"Invalid WebSocket URL or headers"})
    case Config{_, _, _, security, _} Done{H.URLPrepared{H.Endpoint{transport, +host, port, _, _}, request}}: connectProtocol(~Reason, signal, config, key, host, port, request, HTTP.protocol(security, transport, host))

def headerFields(+key: String, headers: H.Headers) -> Result<&2, &2, H.HeaderSyntaxError, H.Headers>:
  Result.bind(&2, &2, H.HeaderSyntaxError, H.Headers, H.Headers, H.set(headers, "Upgrade", "websocket"),
    headers => Result.bind(&2, &2, H.HeaderSyntaxError, H.Headers, H.Headers, H.set(headers, "Connection", "Upgrade"),
      headers => Result.bind(&2, &2, H.HeaderSyntaxError, H.Headers, H.Headers, H.set(headers, "Sec-WebSocket-Key", key),
        headers => H.set(headers, "Sec-WebSocket-Version", "13"))))

def httpURL(value: String) -> Result<&2, &2, String, String>:
  match value:
    case SCon{'w', SCon{'s', SCon{':', rest}}}: Done{"http:" ++ rest}
    case SCon{'w', SCon{'s', SCon{'s', SCon{':', rest}}}}: Done{"https:" ++ rest}
    case _: Fail{"Invalid WebSocket URL scheme"}

def parsedURL(~Reason: Data, signal: Abort.AbortSignal<Reason>, config: Config, key: String, fields: H.Headers, parsed: Result<&2, &2, URL.Error, URL.URL>) -> IO(Result<&2, &1, String, Connection<Reason>>):
  match parsed:
    case Fail{_}: IO.pure(Result<&2, &1, String, Connection<Reason>>, Fail{"Invalid WebSocket URL"})
    case Done{url}: prepared(~Reason, signal, config, key, H.prepareURL(url, "GET", fields, H.Absent{}))

def requestReady(~Reason: Data, signal: Abort.AbortSignal<Reason>, +config: Config, +key: String, headers: Result<&2, &2, H.HeaderSyntaxError, H.Headers>, url: Result<&2, &2, String, String>) -> IO(Result<&2, &1, String, Connection<Reason>>):
  match config headers url:
    case _ Fail{_} _: IO.pure(Result<&2, &1, String, Connection<Reason>>, Fail{"Invalid WebSocket request headers"})
    case _ _ Fail{error}: IO.pure(Result<&2, &1, String, Connection<Reason>>, Fail{error})
    case Config{_, _, HTTP.Options{_, _, _, 0, _}, _, _} _ _: IO.pure(Result<&2, &1, String, Connection<Reason>>, Fail{"Invalid WebSocket read size"})
    case Config{_, _, _, _, context} Done{fields} Done{address}:
      parsedURL(~Reason, signal, config, key, fields, URL.parse(context, address))

def connectEntropy(~Reason: Data, config: Config, url: String, headers: H.Headers, signal: Abort.AbortSignal<Reason>, bytes: Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Result<&2, &1, String, Connection<Reason>>):
  match bytes:
    case Fail{_}: IO.pure(Result<&2, &1, String, Connection<Reason>>, Fail{"WebSocket entropy unavailable"})
    case Done{bytes}:
      +key = Base64.encoded(bytes, "")
      requestReady(~Reason, signal, config, key, headerFields(key, headers), httpURL(url))

def connect(~Reason: Data, config: Config, url: String, headers: H.Headers, signal: Abort.AbortSignal<Reason>) -> IO(Result<&2, &1, String, Connection<Reason>>):
  do IO<Result<&2, &1, String, Connection<Reason>>>:
    bytes : Result<&1, &1, U32 & String, List<&2, U32>> <- Entropy.bytes(16)
    connectEntropy(~Reason, config, url, headers, signal, bytes)

# Sending and receiving retain ownership on failure, so callers can always
# dispose the connection. recv exposes control frames for prompt ping replies.
def sent(-Reason: Data, decoder: WS.Decoder, pending: List<&2, U32>, size: U32, pair: Wire<Reason> & Result<&2, &2, String, Unit>) -> Connection<Reason> & Result<&2, &2, String, Unit>:
  match pair:
    case (wire, result): (Connection{wire, decoder, pending, size}, result)

def sendEntropy(~Reason: Data, wire: Wire<Reason>, decoder: WS.Decoder, pending: List<&2, U32>, size: U32, kind: U32, payload: List<&2, U32>, bytes: Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Connection<Reason> & Result<&2, &2, String, Unit>):
  match bytes:
    case Fail{_}: IO.pure(Connection<Reason> & Result<&2, &2, String, Unit>, (Connection{wire, decoder, pending, size}, Fail{"WebSocket entropy unavailable"}))
    case Done{a <> b <> c <> d <> Nil{}}:
      do IO<Connection<Reason> & Result<&2, &2, String, Unit>>:
        result : Wire<Reason> & Result<&2, &2, String, Unit> <- sendWire(Reason, wire, WS.encode(kind, (a * 16777216 + b * 65536 + c * 256 + d : U32), payload))
        return sent(Reason, decoder, pending, size, result)
    case _: IO.pure(Connection<Reason> & Result<&2, &2, String, Unit>, (Connection{wire, decoder, pending, size}, Fail{"Invalid WebSocket entropy size"}))

def send(~Reason: Data, connection: Connection<Reason>, kind: U32, payload: List<&2, U32>) -> IO(Connection<Reason> & Result<&2, &2, String, Unit>):
  match connection:
    case Connection{wire, decoder, pending, size}:
      do IO<Connection<Reason> & Result<&2, &2, String, Unit>>:
        bytes : Result<&1, &1, U32 & String, List<&2, U32>> <- Entropy.bytes(4)
        sendEntropy(~Reason, wire, decoder, pending, size, kind, payload, bytes)

def sendText(~Reason: Data, connection: Connection<Reason>, value: String) -> IO(Connection<Reason> & Result<&2, &2, String, Unit>): send(~Reason, connection, 1, UTF8.encode(value))
def sendPong(~Reason: Data, connection: Connection<Reason>, bytes: List<&2, U32>) -> IO(Connection<Reason> & Result<&2, &2, String, Unit>): send(~Reason, connection, 10, bytes)

def decodedRead(-Reason: Data, decoder: WS.Decoder, pair: Wire<Reason> & Result<&2, &2, String, List<&2, U32>>) -> Wire<Reason> & Result<&2, &2, String, WS.Decoded>:
  match pair:
    case (wire, Fail{error}): (wire, Fail{error})
    case (wire, Done{Nil{}}): (wire, Fail{"WebSocket closed without close frame"})
    case (wire, Done{bytes}): (wire, WS.feed(decoder, bytes))

@unsafe
def receive(-Reason: Data, +size: U32, state: Wire<Reason> & Result<&2, &2, String, WS.Decoded>) -> IO(Connection<Reason> & Result<&2, &2, String, WS.Message>):
  match state:
    case (wire, Fail{error}): IO.pure(Connection<Reason> & Result<&2, &2, String, WS.Message>, (Connection{wire, WS.new(16777216n), Nil{}, size}, Fail{error}))
    case (wire, Done{WS.Decoded{decoder, Some{message}, rest}}): IO.pure(Connection<Reason> & Result<&2, &2, String, WS.Message>, (Connection{wire, decoder, rest, size}, Done{message}))
    case (wire, Done{WS.Decoded{decoder, None{}, _}}):
      do IO<Connection<Reason> & Result<&2, &2, String, WS.Message>>:
        pair : Wire<Reason> & Result<&2, &2, String, List<&2, U32>> <- readWire(Reason, wire, size)
        receive(Reason, size, decodedRead(Reason, decoder, pair))

def recv(~Reason: Data, connection: Connection<Reason>) -> IO(Connection<Reason> & Result<&2, &2, String, WS.Message>):
  match connection:
    case Connection{wire, decoder, pending, size}: receive(Reason, size, (wire, WS.feed(decoder, pending)))
