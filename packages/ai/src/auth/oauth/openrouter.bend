import Base
import ./browser.bend as Browser
import ./oauth-http.bend as H
import ./oauth-page.bend as Page
import ../types.bend as Auth
import ../../api/credential-http.bend as Http
import ../../utils/json.bend as Wire
import ../../utils/uuid.bend as Uuid
import ../../utils/provider-env.bend as ProviderEnv
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/deferred.bend as Deferred
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/date.bend as Date
import ../../../../runtime/src/fetch.bend as Fetch
import ../../../../runtime/src/http-message.bend as Headers
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/ref.bend as Ref
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/string.bend as Strings
import ../../../../runtime/src/text.bend as Text
import ../../../../runtime/src/timer.bend as Timer
import ../../../../runtime/src/url.bend as URL
import ../../../../runtime/src/utf8.bend as Utf8
import ../types.bend as AuthTypes
import ../../types.bend as T

# pi-mono auth/oauth/openrouter.ts: the OpenRouter OAuth PKCE flow.
# OpenRouter exchanges an authorization code for a permanent, user-controlled
# API key. The callback is served by a one-shot loopback server on its own
# port, raced against a manual prompt so remote/headless sessions can paste
# the redirect URL. Upstream binds port 0 and reads the ephemeral port back;
# the native listener cannot report its bound port (docs/bend-issues.md
# BEND-062), so the server binds a random port of the dynamic range, retrying
# on collisions.

def AUTHORIZE_URL() -> String: "https://openrouter.ai/auth"
def TOKEN_URL() -> String: "https://openrouter.ai/api/v1/auth/keys"
def LOGIN_TIMEOUT_MS() -> U32: 300000
def TOKEN_EXCHANGE_TIMEOUT_MS() -> U32: 30000
# Number.MAX_SAFE_INTEGER
def PERMANENT_EXPIRY() -> F64: F.subtract(F.multiply(F.fromU32(2097152), F.multiply(F.fromU32(2147483648), F.fromU32(2))), F.fromU32(1))

def Json() -> Data: Maybe<&2, V.Value>
def Outcome() -> Data: Result<&2, &2, String, Maybe<&2, Auth.Credential>>

# Key exchange
# ------------
def errorMessageOf(error: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match error:
    case Some{V.ObjectValue{fields}}: H.textOf(R.get(V.Value, fields, "message"))
    case _: None{}

def errorDetail(+body: Json()) -> Maybe<&2, String>:
  Maybe.or(&2, String, H.stringField(body, "error_description"), Maybe.or(&2, String, H.stringField(body, "message"), Maybe.or(&2, String, H.stringField(body, "error"), errorMessageOf(H.field(body, "error")))))

def detailSuffix(detail: Maybe<&2, String>) -> String:
  match detail:
    case Some{SCon{c, cs}}: ": " ++ SCon{c, cs}
    case _: ""

def keyOf(key: Maybe<&2, String>) -> Result<&2, &2, String, Auth.Credential>:
  match key:
    case Some{value}: Done{Auth.OAuthCredential{"", value, PERMANENT_EXPIRY(), R.new(V.Value)}}
    case None{}: Fail{"OpenRouter OAuth response carries no \"key\""}

def objectOnly(json: Json()) -> Json():
  match json:
    case Some{V.ObjectValue{fields}}: Some{V.ObjectValue{fields}}
    case _: Some{V.ObjectValue{R.new(V.Value)}}

def exchangeReply(json: Json(), +status: U32, ok: Bool) -> Result<&2, &2, String, Auth.Credential>:
  match ok json:
    case True{} None{}: Fail{"OpenRouter OAuth returned invalid JSON"}
    case False{} _: Fail{"OpenRouter OAuth key exchange failed (HTTP " ++ U32.show(status) ++ ")" ++ detailSuffix(errorDetail(objectOnly(json)))}
    case True{} _: keyOf(H.nonEmptyField(objectOnly(json), "key"))

def exchanged(aborted: Bool, result: Result<&2, &2, Http.Failure, H.Reply>) -> Result<&2, &2, String, Auth.Credential>:
  match result aborted:
    case _ True{}: Fail{"Login cancelled"}
    case Fail{Http.TimedOut{}} _: Fail{"OpenRouter OAuth token exchange timed out"}
    case Fail{failure} _: Fail{H.failureText(failure)}
    case Done{H.Reply{+status, headers, text, +json}} False{}: exchangeReply(json, status, H.ok(H.Reply{status, headers, text, json}))

def exchangeBody(code: String, verifier: String) -> String:
  Maybe.default(&2, String, Wire.stringify(T.JsonObject{R.Record{[R.Property{"code", T.JsonString{code}}, R.Property{"code_verifier", T.JsonString{verifier}}, R.Property{"code_challenge_method", T.JsonString{"S256"}}]}}), "{}")

def exchangeAuthorizationCode(flow: H.Flow, code: String, verifier: String, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Auth.Credential>):
  do IO<Result<&2, &2, String, Auth.Credential>>:
    before : Bool <- Abort.aborted(Unit, signal)
    Bool.pick(Unit -> IO(Result<&2, &2, String, Auth.Credential>), before,
      _ => IO.pure(Result<&2, &2, String, Auth.Credential>, Fail{"Login cancelled"}),
      _ => do IO<Result<&2, &2, String, Auth.Credential>>:
        result : Result<&2, &2, Http.Failure, H.Reply> <- H.send(flow, signal, "POST", TOKEN_URL(), [R.Property{"accept", "application/json"}, R.Property{"content-type", "application/json"}], Headers.Text{exchangeBody(code, verifier)}, TOKEN_EXCHANGE_TIMEOUT_MS())
        aborted : Bool <- Abort.aborted(Unit, signal)
        return exchanged(aborted, result))(Unit{})

# Manual input
# ------------
def firstCode(params: URL.URLSearchParams) -> Maybe<&2, String>: URL.get(params, "code")

def urlCode(parsed: Result<&2, &2, URL.Error, URL.URL>) -> Maybe<&2, Maybe<&2, String>>:
  match parsed:
    case Done{URL.URL{_, _, _, _, _, _, query, _}}: Some{Maybe.bind(&2, String, String, query, text => firstCode(URL.parseSearchParams(text)))}
    case Fail{_}: None{}

def nonEmpty(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: None{}

# A redirect URL's `code`, a query string's `code`, or the input itself.
def parsedInput(context: URL.Context, value: String) -> Maybe<&2, String>:
  match value:
    case SNil{}: None{}
    case +text:
      Maybe.default(&2, Maybe<&2, String>, urlCode(URL.parse(context, text)), Bool.pick(Maybe<&2, String>, String.contains(text, "code="), firstCode(URL.parseSearchParams(text)), Some{text}))

def parseAuthorizationInput(context: URL.Context, input: String) -> Maybe<&2, String>: parsedInput(context, Text.trim(input))

# Callback server
# ---------------
type ServerState is Data:
  ServerState{claimed: Bool, settled: Bool}

type Server is Type:
  Server{callbackUrl: String, path: String, verifier: String, state: Ref.Ref<ServerState>, credential: Deferred.Deferred<Outcome()>, signal: Abort.AbortSignal<Unit>, stop: Ref.Ref<Bool>, worker: Chan(Unit)}

def reasonOf(+status: U32) -> String:
  match status:
    case 200: "OK"
    case 400: "Bad Request"
    case 404: "Not Found"
    case 409: "Conflict"
    case 502: "Bad Gateway"
    case _: ""

def htmlResponse(+status: U32, +html: String) -> String:
  "HTTP/1.1 " ++ U32.show(status) ++ " " ++ reasonOf(status) ++ "\r\ncontent-type: text/html; charset=utf-8\r\ncache-control: no-store\r\ncontent-length: " ++ Nat.show(List.length(&2, U32, Utf8.encode(html))) ++ "\r\nconnection: close\r\n\r\n" ++ html

def closeSent(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (socket, _): Socket.close(socket)

def sendHtml(socket: Socket, +status: U32, html: String) -> IO(Unit):
  do IO<Unit>:
    pair : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send(socket, htmlResponse(status, html))
    closeSent(pair)

def errorPage(message: String, details: Maybe<&2, String>) -> String: Page.oauthErrorHtml(message, details)

# finish: the first settlement wins; later ones are ignored.
def finish(server: ServerState) -> ServerState & Bool:
  match server:
    case ServerState{claimed, settled}: (ServerState{claimed, True{}}, Bool.not(settled))

def resolved(+first: Bool, credential: Deferred.Deferred<Outcome()>, +result: Outcome()) -> IO(Unit):
  match first:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        done : Bool <- Deferred.resolve(Outcome(), credential, result)
        return Unit{}

def settle(state: Ref.Ref<ServerState>, credential: Deferred.Deferred<Outcome()>, +result: Outcome()) -> IO(Unit):
  do IO<Unit>:
    first : Bool <- Ref.modify(ServerState, Bool, state, finish)
    resolved(first, credential, result)

def claim(server: ServerState) -> ServerState & Bool:
  match server:
    case ServerState{+claimed, +settled}: Bool.pick(ServerState & Bool, claimed || settled, (ServerState{claimed, settled}, False{}), (ServerState{True{}, settled}, True{}))

type Request is Data:
  Request{method: String, pathname: String, params: URL.URLSearchParams}

def targetRequest(method: String, parts: List<&2, String>) -> Request:
  match parts:
    case path <> Nil{}: Request{method, path, URL.new()}
    case path <> query <> _: Request{method, path, URL.parseSearchParams(query)}
    case Nil{}: Request{method, "", URL.new()}

def requestParts(parts: List<&2, String>) -> Request:
  match parts:
    case method <> target <> _: targetRequest(method, Strings.split(target, '?'))
    case _: Request{"", "", URL.new()}

def requestOf(line: String) -> Request: requestParts(Strings.split(line, ' '))

type Handling is Data:
  Handling{flow: H.Flow, verifier: String, state: Ref.Ref<ServerState>, credential: Deferred.Deferred<Outcome()>, signal: Abort.AbortSignal<Unit>, path: String}

def exchangedPage(state: Ref.Ref<ServerState>, credential: Deferred.Deferred<Outcome()>, socket: Socket, result: Result<&2, &2, String, Auth.Credential>) -> IO(Unit):
  match result:
    case Done{found}:
      do IO<Unit>:
        sendHtml(socket, 200, Page.oauthSuccessHtml("Signed in to OpenRouter. You may now close this page."))
        settle(state, credential, Done{Some{found}})
    case Fail{+message}:
      do IO<Unit>:
        sendHtml(socket, 502, errorPage("OpenRouter key exchange failed.", Some{message}))
        settle(state, credential, Fail{message})

def claimedCallback(handling: Handling, socket: Socket, +code: String, won: Bool) -> IO(Unit):
  match handling won:
    case _ False{}: sendHtml(socket, 409, errorPage("This OAuth callback has already been used.", None{}))
    case Handling{flow, verifier, state, credential, signal, _} True{}:
      do IO<Unit>:
        result : Result<&2, &2, String, Auth.Credential> <- exchangeAuthorizationCode(flow, code, verifier, signal)
        exchangedPage(state, credential, socket, result)

def handleCallback(handling: Handling, socket: Socket, error: Maybe<&2, String>, description: Maybe<&2, String>, code: Maybe<&2, String>) -> IO(Unit):
  match error code handling:
    case Some{+oauthError} _ Handling{_, _, +state, credential, _, _}:
      +detail = Maybe.default(&2, String, description, oauthError)
      do IO<Unit>:
        sendHtml(socket, 400, errorPage("OpenRouter authorization was denied.", Some{detail}))
        settle(state, credential, Fail{"OpenRouter authorization failed: " ++ detail})
    case None{} Some{SCon{c, cs}} Handling{flow, verifier, +state, credential, signal, path}:
      do IO<Unit>:
        won : Bool <- Ref.modify(ServerState, Bool, state, claim)
        claimedCallback(Handling{flow, verifier, state, credential, signal, path}, socket, SCon{c, cs}, won)
    case None{} _ _: sendHtml(socket, 400, errorPage("OpenRouter returned no authorization code.", None{}))

def isBusy(current: ServerState) -> Bool:
  match current:
    case ServerState{claimed, settled}: claimed || settled

def openCallback(handling: Handling, socket: Socket, +params: URL.URLSearchParams, busy: Bool) -> IO(Unit):
  match busy:
    case True{}: sendHtml(socket, 409, errorPage("This OAuth callback has already been used.", None{}))
    case False{}: handleCallback(handling, socket, URL.get(params, "error"), URL.get(params, "error_description"), URL.get(params, "code"))

# One callback request (upstream's createServer handler).
def routed(handling: Handling, socket: Socket, +params: URL.URLSearchParams, matches: Bool) -> IO(Unit):
  match matches handling:
    case False{} _: sendHtml(socket, 404, errorPage("OAuth callback route not found.", None{}))
    case True{} Handling{flow, verifier, +state, credential, signal, path}:
      do IO<Unit>:
        current : ServerState <- Ref.read(ServerState, state)
        openCallback(Handling{flow, verifier, state, credential, signal, path}, socket, params, isBusy(current))

def pathOf(handling: Handling) -> String:
  match handling:
    case Handling{_, _, _, _, _, path}: path

# One callback request (upstream's createServer handler).
def handleRequest(+handling: Handling, socket: Socket, request: Request) -> IO(Unit):
  match request:
    case Request{+method, +pathname, params}: routed(handling, socket, params, String.eq(method, "GET") && String.eq(pathname, pathOf(handling)))

type Conn is Type:
  Reading{socket: Socket, bytes: List<&2, U32>}
  Got{pair: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, bytes: List<&2, U32>}
  Lined{socket: Socket, bytes: List<&2, U32>, line: Maybe<&2, String>}
  Oversized{socket: Socket, bytes: List<&2, U32>, tooLong: Bool}

# Reads a request line, then handles it; each connection runs in its own task.
@unsafe def connection(handling: Handling, step: Conn) -> IO(Unit):
  match step:
    case Reading{socket, bytes}:
      do IO<Unit>:
        pair : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 4096)
        connection(handling, Got{pair, bytes})
    case Got{(socket, Fail{_}), _}: Socket.close(socket)
    case Got{(socket, Done{Nil{}}), _}: Socket.close(socket)
    case Got{(socket, Done{chunk}), bytes}:
      +joined = List.append(&2, U32, bytes, chunk)
      connection(handling, Lined{socket, joined, Browser.callbackLine(joined)})
    case Lined{socket, _, Some{line}}: handleRequest(handling, socket, requestOf(line))
    case Lined{socket, +bytes, None{}}: connection(handling, Oversized{socket, bytes, Nat.is_gt(List.length(&2, U32, bytes), 8192n)})
    case Oversized{socket, _, True{}}: sendHtml(socket, 400, errorPage("OAuth callback route not found.", None{}))
    case Oversized{socket, bytes, False{}}: connection(handling, Reading{socket, bytes})

type Accepting is Type:
  Listening{listener: Listener}
  Checked{listener: Listener, stopped: Bool, aborted: Bool, now: F64}
  Timed{listener: Listener, expired: Bool}
  Accepted{pair: Listener & Result<&1, &1, U32 & String, Socket>}

def settledOf(state: ServerState) -> Bool:
  match state:
    case ServerState{_, settled}: settled

# The accept loop: stops when the login settles or closes the server, answers
# "Login cancelled" on abort and "OpenRouter OAuth login timed out" after 5 min.
@unsafe def accepting(+handling: Handling, +stop: Ref.Ref<Bool>, +deadline: F64, step: Accepting) -> IO(Unit):
  match step handling:
    case Listening{listener} Handling{_, _, state, _, signal, _}:
      do IO<Unit>:
        stopped : Bool <- Ref.read(Bool, stop)
        current : ServerState <- Ref.read(ServerState, state)
        aborted : Bool <- Abort.aborted(Unit, signal)
        now : F64 <- Date.now()
        accepting(handling, stop, deadline, Checked{listener, stopped || settledOf(current), aborted, now})
    case Checked{listener, True{}, _, _} _: Listener.close(listener)
    case Checked{listener, False{}, True{}, _} Handling{_, _, state, credential, _, _}:
      do IO<Unit>:
        Listener.close(listener)
        settle(state, credential, Fail{"Login cancelled"})
    case Checked{listener, False{}, False{}, now} _:
      accepting(handling, stop, deadline, Timed{listener, F.isGreater(F.compare(now, deadline))})
    case Timed{listener, True{}} Handling{_, _, state, credential, _, _}:
      do IO<Unit>:
        Listener.close(listener)
        settle(state, credential, Fail{"OpenRouter OAuth login timed out"})
    case Timed{listener, False{}} _:
      do IO<Unit>:
        pair : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept_try(listener)
        accepting(handling, stop, deadline, Accepted{pair})
    case Accepted{(listener, Done{socket})} _:
      do IO<Unit>:
        task : Chan(Unit) <- IO.fork(Unit, connection(handling, Reading{socket, Nil{}}))
        accepting(handling, stop, deadline, Listening{listener})
    case Accepted{(listener, Fail{_})} _:
      do IO<Unit>:
        IO.sleep(20)
        accepting(handling, stop, deadline, Listening{listener})

# Binding the callback port
# -------------------------
# A random port of the dynamic range (49152-65535), retried on collisions.
def portOf(bytes: List<&2, U32>) -> U32:
  match bytes:
    case high <> low <> _: (49152 + ((high * 256 + low) % 16384) : U32)
    case _: 49152

def bytesOr(bytes: Result<&2, &2, String, List<&2, U32>>) -> List<&2, U32>:
  match bytes:
    case Done{values}: values
    case Fail{_}: Nil{}

type Binding is Type:
  Try{attempts: Nat}
  Tried{attempts: Nat, port: U32, listened: Result<&1, &1, U32 & String, Listener>}

@unsafe def bindLoop(+host: String, step: Binding) -> IO(Result<&1, &1, String, Listener & U32>):
  match step:
    case Try{0n}: IO.pure(Result<&1, &1, String, Listener & U32>, Fail{"Could not determine the OpenRouter OAuth callback port"})
    case Try{1n+rest}:
      do IO<Result<&1, &1, String, Listener & U32>>:
        bytes : Result<&2, &2, String, List<&2, U32>> <- Browser.randomBytes(2)
        +port : U32 <- IO.pure(U32, portOf(bytesOr(bytes)))
        listened : Result<&1, &1, U32 & String, Listener> <- Browser.listenOn(host, port)
        bindLoop(host, Tried{rest, port, listened})
    case Tried{_, port, Done{listener}}: IO.pure(Result<&1, &1, String, Listener & U32>, Done{(listener, port)})
    case Tried{attempts, _, Fail{_}}: bindLoop(host, Try{attempts})

def callbackHostOf(value: Maybe<&2, String>) -> String:
  match value:
    case Some{SCon{c, cs}}: SCon{c, cs}
    case _: "127.0.0.1"

def startedServer(flow: H.Flow, +host: String, +path: String, +verifier: String, +signal: Abort.AbortSignal<Unit>, bound: Result<&1, &1, String, Listener & U32>) -> IO(Result<&1, &1, String, Server>):
  match bound:
    case Fail{message}: IO.pure(Result<&1, &1, String, Server>, Fail{message})
    case Done{(listener, port)}:
      do IO<Result<&1, &1, String, Server>>:
        +state : Ref.Ref<ServerState> <- Ref.new(ServerState, ServerState{False{}, False{}})
        +credential : Deferred.Deferred<Outcome()> <- Deferred.new(Outcome())
        +stop : Ref.Ref<Bool> <- Ref.new(Bool, False{})
        now : F64 <- Date.now()
        worker : Chan(Unit) <- IO.fork(Unit, accepting(Handling{flow, verifier, state, credential, signal, path}, stop, F.add(now, F.fromU32(LOGIN_TIMEOUT_MS())), Listening{listener}))
        return Done{Server{"http://" ++ host ++ ":" ++ U32.show(port) ++ path, path, verifier, state, credential, signal, stop, worker}}

def startCallbackServer(flow: H.Flow, +path: String, verifier: String, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&1, &1, String, Server>):
  do IO<Result<&1, &1, String, Server>>:
    aborted : Bool <- Abort.aborted(Unit, signal)
    Bool.pick(Unit -> IO(Result<&1, &1, String, Server>), aborted,
      _ => IO.pure(Result<&1, &1, String, Server>, Fail{"Login cancelled"}),
      _ => do IO<Result<&1, &1, String, Server>>:
        configured : Maybe<&2, String> <- ProviderEnv.getProviderEnvValue("PI_OAUTH_CALLBACK_HOST", None{})
        +host : String <- IO.pure(String, callbackHostOf(configured))
        listened : Result<&1, &1, String, Listener & U32> <- bindLoop(host, Try{32n})
        startedServer(flow, host, path, verifier, signal, listened))(Unit{})

# Stop listening without settling the login.
def closeServer(server: Server) -> IO(Unit):
  match server:
    case Server{_, _, _, _, credential, _, stop, worker}:
      do IO<Unit>:
        Ref.write(Bool, stop, True{})
        IO.join(Unit, worker)
        Deferred.dispose(Outcome(), credential)

def claimedOf(state: ServerState) -> Bool:
  match state:
    case ServerState{claimed, _}: claimed

# Hand the login over to manual code entry unless a callback already
# claimed the exchange.
def cancelWait(+state: Ref.Ref<ServerState>, credential: Deferred.Deferred<Outcome()>) -> IO(Unit):
  do IO<Unit>:
    current : ServerState <- Ref.read(ServerState, state)
    Bool.pick(IO(Unit), claimedOf(current), IO.pure(Unit, Unit{}), settle(state, credential, Done{None{}}))

# Login
# -----
type Manual is Type:
  Manual{input: Ref.Ref<Maybe<&2, Result<&2, &2, String, String>>>}

def manualRun(prompt: C.Callback<Auth.AuthPrompt, Result<&2, &2, String, String>>, +placeholder: String, signal: Abort.AbortSignal<Unit>, input: Ref.Ref<Maybe<&2, Result<&2, &2, String, String>>>, state: Ref.Ref<ServerState>, credential: Deferred.Deferred<Outcome()>) -> IO(Unit):
  do IO<Unit>:
    answer : Result<&2, &2, String, String> <- C.call(Auth.AuthPrompt, Result<&2, &2, String, String>, prompt, Auth.ManualCodePrompt{"Complete sign-in in your browser, or paste the authorization code / redirect URL here:", Some{placeholder}, Some{signal}})
    Ref.write(Maybe<&2, Result<&2, &2, String, String>>, input, Some{answer})
    cancelWait(state, credential)

def authorizeUrl(callbackUrl: String, challenge: String) -> String:
  AUTHORIZE_URL() ++ "?" ++ H.formText([R.Property{"callback_url", callbackUrl}, R.Property{"code_challenge", challenge}, R.Property{"code_challenge_method", "S256"}])

def manualError(input: Maybe<&2, Result<&2, &2, String, String>>) -> Maybe<&2, String>:
  match input:
    case Some{Fail{message}}: Some{message}
    case _: None{}

def manualCode(context: URL.Context, input: Maybe<&2, Result<&2, &2, String, String>>) -> Maybe<&2, String>:
  match input:
    case Some{Done{text}}: parseAuthorizationInput(context, text)
    case _: None{}

def manualDecided(flow: H.Flow, notify: C.Callback<Auth.AuthEvent, Unit>, verifier: String, +signal: Abort.AbortSignal<Unit>, error: Maybe<&2, String>, code: Maybe<&2, String>) -> IO(Auth.LoginOutcome()):
  match error code:
    case Some{message} _: IO.pure(Auth.LoginOutcome(), Fail{message})
    case None{} None{}: IO.pure(Auth.LoginOutcome(), Fail{"Missing authorization code"})
    case None{} Some{code}:
      do IO<Auth.LoginOutcome()>:
        C.call(Auth.AuthEvent, Unit, notify, Auth.ProgressEvent{"Exchanging authorization code for an API key..."})
        exchangeAuthorizationCode(flow, code, verifier, signal)

def fromManual(+flow: H.Flow, notify: C.Callback<Auth.AuthEvent, Unit>, verifier: String, +signal: Abort.AbortSignal<Unit>, +input: Maybe<&2, Result<&2, &2, String, String>>) -> IO(Auth.LoginOutcome()):
  manualDecided(flow, notify, verifier, signal, manualError(input), manualCode(H.flowContext(flow), input))

def afterDecided(flow: H.Flow, notify: C.Callback<Auth.AuthEvent, Unit>, verifier: String, +signal: Abort.AbortSignal<Unit>, input: Ref.Ref<Maybe<&2, Result<&2, &2, String, String>>>, error: Maybe<&2, String>, outcome: Outcome()) -> IO(Auth.LoginOutcome()):
  match error outcome:
    case Some{message} _: IO.pure(Auth.LoginOutcome(), Fail{message})
    case None{} Fail{message}: IO.pure(Auth.LoginOutcome(), Fail{message})
    case None{} Done{Some{credential}}: IO.pure(Auth.LoginOutcome(), Done{credential})
    # The prompt stored its answer before handing the login over.
    case None{} Done{None{}}:
      do IO<Auth.LoginOutcome()>:
        answer : Maybe<&2, Result<&2, &2, String, String>> <- Ref.read(Maybe<&2, Result<&2, &2, String, String>>, input)
        fromManual(flow, notify, verifier, signal, answer)

def afterCallback(flow: H.Flow, notify: C.Callback<Auth.AuthEvent, Unit>, verifier: String, +signal: Abort.AbortSignal<Unit>, input: Ref.Ref<Maybe<&2, Result<&2, &2, String, String>>>, before: Maybe<&2, Result<&2, &2, String, String>>, outcome: Outcome()) -> IO(Auth.LoginOutcome()):
  afterDecided(flow, notify, verifier, signal, input, manualError(before), outcome)

def withServer(flow: H.Flow, interaction: Auth.ProviderAuthInteraction, challenge: String, started: Result<&1, &1, String, Server>) -> IO(Auth.LoginOutcome()):
  match started interaction:
    case Fail{message} _: IO.pure(Auth.LoginOutcome(), Fail{message})
    case Done{Server{+callbackUrl, path, +verifier, +state, +credential, loginSignal, stop, worker}} Auth.ProviderAuthInteraction{+signal, prompt, +notify}:
      do IO<Auth.LoginOutcome()>:
        +manualAbort : Abort.AbortController<Unit> <- Abort.new(Unit)
        +input : Ref.Ref<Maybe<&2, Result<&2, &2, String, String>>> <- Ref.new(Maybe<&2, Result<&2, &2, String, String>>, None{})
        C.call(Auth.AuthEvent, Unit, notify, Auth.ProgressEvent{"Listening for OpenRouter OAuth callback on " ++ callbackUrl})
        C.call(Auth.AuthEvent, Unit, notify, Auth.AuthUrlEvent{authorizeUrl(callbackUrl, challenge), Some{"Complete sign-in in your browser. If the browser is on another machine, paste the final redirect URL here."}})
        manual : Chan(Unit) <- IO.fork(Unit, manualRun(prompt, callbackUrl, Abort.signal(Unit, manualAbort), input, state, credential))
        outcome : Outcome() <- Deferred.result(Outcome(), credential)
        before : Maybe<&2, Result<&2, &2, String, String>> <- Ref.read(Maybe<&2, Result<&2, &2, String, String>>, input)
        result : Auth.LoginOutcome() <- afterCallback(flow, notify, verifier, signal, input, before, outcome)
        # upstream aborts the prompt in `finally`; the prompt settles through
        # its signal and is joined before the signal is disposed.
        stopped : Bool <- Abort.abort(Unit, manualAbort, None{})
        IO.join(Unit, manual)
        closeServer(Server{callbackUrl, path, verifier, state, credential, loginSignal, stop, worker})
        Abort.dispose(Unit, manualAbort)
        return result

def withPkce(+flow: H.Flow, interaction: Auth.ProviderAuthInteraction, pkce: Result<&2, &2, String, Browser.PKCE>, id: Result<&2, &2, Uuid.Error, String>) -> IO(Auth.LoginOutcome()):
  match pkce id interaction:
    case Fail{message} _ _: IO.pure(Auth.LoginOutcome(), Fail{message})
    case _ Fail{error} _: IO.pure(Auth.LoginOutcome(), Fail{Uuid.errorMessage(error)})
    case Done{Browser.PKCE{verifier, challenge}} Done{uuid} Auth.ProviderAuthInteraction{+signal, prompt, notify}:
      do IO<Auth.LoginOutcome()>:
        started : Result<&1, &1, String, Server> <- startCallbackServer(flow, "/oauth/callback/" ++ uuid, verifier, signal)
        withServer(flow, Auth.ProviderAuthInteraction{signal, prompt, notify}, challenge, started)

def loginWith(+flow: H.Flow, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  do IO<Auth.LoginOutcome()>:
    pkce : Result<&2, &2, String, Browser.PKCE> <- Browser.generatePKCE()
    id : Result<&2, &2, Uuid.Error, String> <- Uuid.randomUUID()
    withPkce(flow, interaction, pkce, id)

def login(flow: H.Flow, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()): loginWith(flow, interaction)

# The OAuth key is permanent: refresh keeps the credential.
def refresh(unused: Unit, input: Auth.RefreshInput) -> IO(Result<&2, &2, String, Auth.Credential>):
  match input:
    case Auth.RefreshInput{credential, _}: IO.pure(Result<&2, &2, String, Auth.Credential>, Done{credential})

def toAuth(unused: Unit, credential: Auth.Credential) -> IO(Result<&2, &2, String, Auth.ModelAuth>):
  match credential:
    case Auth.OAuthCredential{_, access, _, _}: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Done{Auth.ModelAuth{Some{access}, None{}, None{}}})
    case _: IO.pure(Result<&2, &2, String, Auth.ModelAuth>, Fail{"OpenRouter OAuth requires an OAuth credential"})

def openRouterOAuth(fetch: Fetch.Fetch(Unit), url: URL.Context) -> IO(Auth.OAuthAuth):
  do IO<Auth.OAuthAuth>:
    authenticate : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~H.Flow, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~login, H.Flow{fetch, url})
    refresher : C.Callback<Auth.RefreshInput, Result<&2, &2, String, Auth.Credential>> <- C.create(~Unit, ~Auth.RefreshInput, ~Result<&2, &2, String, Auth.Credential>, ~refresh, Unit{})
    deriver : C.Callback<Auth.Credential, Result<&2, &2, String, Auth.ModelAuth>> <- C.create(~Unit, ~Auth.Credential, ~Result<&2, &2, String, Auth.ModelAuth>, ~toAuth, Unit{})
    return Auth.OAuthAuth{"OpenRouter OAuth", False{}, Some{"Sign in with OpenRouter"}, authenticate, refresher, deriver}
