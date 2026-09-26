import Base
import ../types.bend as Auth
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/base64.bend as Base64
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/deferred.bend as Deferred
import ../../../../runtime/src/sha256.bend as SHA
import ../../../../runtime/src/string.bend as Strings
import ../../../../runtime/src/text.bend as Text
import ../../../../runtime/src/url.bend as URL
import ../../../../runtime/src/utf8.bend as Utf8

# Shared native browser authorization: secure PKCE, state validation and a
# callback/manual-input race. Workers own their sockets and are joined before
# the cancellation controllers or answer are disposed.
def CodeResult() -> Data: Result<&2,&2,String,String>
type PKCE is Data: PKCE{verifier: String, challenge: String}
type CallbackConfig is Data:
  CallbackConfig{redirectUri: String, path: String, state: String}
def removePadding(reversed: String) -> String:
  match reversed:
    case SCon{'=',rest}: removePadding(rest)
    case _: String.reverse(reversed)
def unpadded(text: String) -> String: removePadding(String.reverse(text))
def urlAlphabet(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'+',rest}: SCon{'-',urlAlphabet(rest)}
    case SCon{'/',rest}: SCon{'_',urlAlphabet(rest)}
    case SCon{first,rest}: SCon{first,urlAlphabet(rest)}
def encodedBase64(result: Result<&2,&2,Base64.Error,String>) -> Result<&2,&2,String,String>:
  match result:
    case Fail{_}: Fail{"Could not encode OAuth verifier"}
    case Done{value}: Done{urlAlphabet(unpadded(value))}
def base64url(bytes: List<&2,U32>) -> Result<&2,&2,String,String>: encodedBase64(Base64.encode(bytes))
def hashedChallenge(result: Result<&2,&2,SHA.Error,SHA.Digest>) -> Result<&2,&2,String,String>:
  match result:
    case Fail{_}: Fail{"Could not hash OAuth verifier"}
    case Done{digest}: base64url(SHA.toBytes(digest))
def challenge(verifier: String) -> Result<&2,&2,String,String>: hashedChallenge(SHA.digest(Utf8.encode(verifier)))

def readRandom(pair: File & Result<&1,&1,U32 & String,List<&2,U32>>, +count: U32) -> IO(Result<&2,&2,String,List<&2,U32>>):
  match pair:
    case (file,Fail{_}):
      do IO<Result<&2,&2,String,List<&2,U32>>>:
        File.close(file)
        return Fail{"Could not obtain secure OAuth randomness"}
    case (file,Done{+bytes}):
      do IO<Result<&2,&2,String,List<&2,U32>>>:
        File.close(file)
        return Bool.pick(Result<&2,&2,String,List<&2,U32>>,Nat.is_eq(List.length(&2,U32,bytes),U32.to_nat(count)),Done{bytes},Fail{"OAuth randomness was incomplete"})
def openedRandom(opened: Result<&1,&1,U32 & String,File>, +count: U32) -> IO(Result<&2,&2,String,List<&2,U32>>):
  match opened:
    case Fail{_}: IO.pure(Result<&2,&2,String,List<&2,U32>>,Fail{"Could not open secure OAuth randomness"})
    case Done{file}:
      do IO<Result<&2,&2,String,List<&2,U32>>>:
        pair : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,count)
        readRandom(pair,count)
def randomBytes(+count: U32) -> IO(Result<&2,&2,String,List<&2,U32>>):
  do IO<Result<&2,&2,String,List<&2,U32>>>:
    opened : Result<&1,&1,U32 & String,File> <- File.open("/dev/urandom","r")
    openedRandom(opened,count)
def pkceChallenge(verifier: String, hashed: CodeResult()) -> Result<&2,&2,String,PKCE>:
  match hashed:
    case Fail{error}: Fail{error}
    case Done{hash}: Done{PKCE{verifier,hash}}
def pkceEncoded(encoded: CodeResult()) -> Result<&2,&2,String,PKCE>:
  match encoded:
    case Fail{error}: Fail{error}
    case Done{+verifier}: pkceChallenge(verifier,challenge(verifier))
def pkceBytes(bytes: Result<&2,&2,String,List<&2,U32>>) -> Result<&2,&2,String,PKCE>:
  match bytes:
    case Fail{error}: Fail{error}
    case Done{values}: pkceEncoded(base64url(values))
def generatePKCE() -> IO(Result<&2,&2,String,PKCE>):
  do IO<Result<&2,&2,String,PKCE>>:
    bytes : Result<&2,&2,String,List<&2,U32>> <- randomBytes(32)
    return pkceBytes(bytes)
def codeWithState(+code: String, state: Maybe<&2,String>, verifier: String) -> Result<&2,&2,String,String>:
  match state:
    case Some{received}:
      Bool.pick(Result<&2,&2,String,String>,String.eq(received,verifier) && Bool.not(String.is_empty(code)),Done{code},Fail{"OAuth state mismatch or missing authorization code"})
    case None{}:
      Bool.pick(Result<&2,&2,String,String>,String.is_empty(code),Fail{"Missing authorization code"},Done{code})
def queryValue(code: Maybe<&2,String>, state: Maybe<&2,String>, verifier: String) -> Result<&2,&2,String,String>:
  match code state:
    case Some{value} Some{received}: codeWithState(value,Some{received},verifier)
    case _ _: Fail{"OAuth callback needs a code and state"}
def queryCode(+params: URL.URLSearchParams, verifier: String) -> Result<&2,&2,String,String>:
  queryValue(URL.get(params,"code"),URL.get(params,"state"),verifier)
def manualQueryValue(code: Maybe<&2,String>, received: Maybe<&2,String>, state: String) -> CodeResult():
  match code:
    case None{}: Fail{"Missing authorization code"}
    case Some{code}: codeWithState(code,received,state)
def manualQuery(+params: URL.URLSearchParams, state: String) -> CodeResult():
  manualQueryValue(URL.get(params,"code"),URL.get(params,"state"),state)
def manualParts(parts: List<&2,String>, +value: String, config: CallbackConfig) -> CodeResult():
  match parts config:
    case code <> state <> Nil{} CallbackConfig{_,_,expected}: codeWithState(code,Some{state},expected)
    case _ <> _ <> _ <> _ _: Fail{"Malformed authorization code"}
    case _ CallbackConfig{+redirect,_,+expected}:
      +prefix = redirect ++ "?"
      Bool.pick(Unit -> CodeResult(),String.starts_with(value,prefix),_ => manualQuery(URL.parseSearchParams(String.drop(value,String.length(prefix))),expected),_ => Bool.pick(Unit -> CodeResult(),String.starts_with(value,"http://") || String.starts_with(value,"https://"),_ => Fail{"Unexpected OAuth redirect URL"},_ => Bool.pick(Unit -> CodeResult(),String.starts_with(value,"code="),_ => manualQuery(URL.parseSearchParams(value),expected),_ => codeWithState(value,None{},expected))(Unit{}))(Unit{}))(Unit{})
def authorizationInput(input: String, config: CallbackConfig) -> CodeResult():
  +value = Text.trim(input)
  manualParts(Strings.split(value,'#'),value,config)
def callbackLineParts(parts: List<&2,String>) -> Maybe<&2,String>:
  match parts:
    case first <> _ <> _: Some{Text.trim(first)}
    case _: None{}
def callbackLineText(value: Result<&2,&2,Utf8.Error,String>) -> Maybe<&2,String>:
  match value:
    case Fail{_}: None{}
    case Done{text}: callbackLineParts(Strings.split(text,'\n'))
def callbackLine(bytes: List<&2,U32>) -> Maybe<&2,String>:
  callbackLineText(Utf8.decodeStrict(bytes))
def callbackTarget(parts: List<&2,String>,config: CallbackConfig) -> CodeResult():
  match parts config:
    case "GET" <> +target <> "HTTP/1.1" <> Nil{} CallbackConfig{_,+path,+state}:
      +prefix = path ++ "?"
      Bool.pick(Unit -> CodeResult(),String.starts_with(target,prefix),_ => queryCode(URL.parseSearchParams(String.drop(target,String.length(prefix))),state),_ => Fail{"Unexpected OAuth callback route"})(Unit{})
    case _ _: Fail{"Invalid OAuth callback request"}
def callbackCode(line: String,config: CallbackConfig) -> CodeResult():
  callbackTarget(Strings.split(line,' '),config)
def callbackHtml(success: Bool) -> String:
  Bool.pick(String,success,"<!doctype html><title>OAuth login complete</title><p>Authentication completed. You can close this window.</p>","<!doctype html><title>OAuth login failed</title><p>Authentication did not complete. Return to the terminal.</p>")
def callbackResponse(+success: Bool) -> String:
  +body = callbackHtml(success)
  Bool.pick(String,success,"HTTP/1.1 200 OK\r\n","HTTP/1.1 400 Bad Request\r\n") ++ "Content-Type: text/html; charset=utf-8\r\nContent-Length: " ++ Nat.show(List.length(&2,U32,Utf8.encode(body))) ++ "\r\nConnection: close\r\n\r\n" ++ body
def closeCallbackWrite(pair: Socket & Result<&1,&1,U32 & String,Unit>) -> IO(Unit):
  match pair:
    case (socket,_): Socket.close(socket)
def respondCallback(socket: Socket,success: Bool) -> IO(Unit):
  do IO<Unit>:
    pair : Socket & Result<&1,&1,U32 & String,Unit> <- TCP.send(socket,callbackResponse(success))
    closeCallbackWrite(pair)

type CallbackStep is Type:
  Listening{listener: Listener}
  CheckedListener{listener: Listener,answer: Maybe<&2,CodeResult()>,aborted: Bool}
  Accepted{pair: Listener & Result<&1,&1,U32 & String,Socket>}
  Reading{listener: Listener,socket: Socket,bytes: List<&2,U32>}
  CheckedSocket{listener: Listener,socket: Socket,bytes: List<&2,U32>,answer: Maybe<&2,CodeResult()>,aborted: Bool}
  Readable{listener: Listener,pair: Socket & Result<&1,&1,U32 & String,Bool>,bytes: List<&2,U32>}
  Received{listener: Listener,pair: Socket & Result<&1,&1,U32 & String,List<&2,U32>>,bytes: List<&2,U32>}
  Line{listener: Listener,socket: Socket,bytes: List<&2,U32>,line: Maybe<&2,String>}
  LineSize{listener: Listener,socket: Socket,bytes: List<&2,U32>,tooLong: Bool}
  Parsed{listener: Listener,socket: Socket,result: Result<&2,&2,String,String>}

@unsafe def callbackRun(step: CallbackStep,+answer: Deferred.Deferred<CodeResult()>,+config: CallbackConfig,+signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  match step:
    case Listening{listener}:
      do IO<Unit>:
        current : Maybe<&2,CodeResult()> <- Deferred.peek(CodeResult(),answer)
        stopped : Bool <- Abort.aborted(Unit,signal)
        callbackRun(CheckedListener{listener,current,stopped},answer,config,signal)
    case CheckedListener{listener,Some{_},_}:
      do IO<Unit>:
        Listener.close(listener)
        return Unit{}
    case CheckedListener{listener,None{},True{}}:
      do IO<Unit>:
        Listener.close(listener)
        settled : Bool <- Deferred.resolve(CodeResult(),answer,Fail{"Login cancelled"})
        return Unit{}
    case CheckedListener{listener,None{},False{}}:
      do IO<Unit>:
        pair : Listener & Result<&1,&1,U32 & String,Socket> <- TCP.accept_try(listener)
        callbackRun(Accepted{pair},answer,config,signal)
    case Accepted{(listener,Fail{(11,_)})}:
      do IO<Unit>:
        IO.sleep(30)
        callbackRun(Listening{listener},answer,config,signal)
    case Accepted{(listener,Fail{_})}:
      do IO<Unit>:
        Listener.close(listener)
        settled : Bool <- Deferred.resolve(CodeResult(),answer,Fail{"Login cancelled"})
        return Unit{}
    case Accepted{(listener,Done{socket})}: callbackRun(Reading{listener,socket,Nil{}},answer,config,signal)
    case Reading{listener,socket,bytes}:
      do IO<Unit>:
        current : Maybe<&2,CodeResult()> <- Deferred.peek(CodeResult(),answer)
        stopped : Bool <- Abort.aborted(Unit,signal)
        callbackRun(CheckedSocket{listener,socket,bytes,current,stopped},answer,config,signal)
    case CheckedSocket{listener,socket,_,Some{_},_}:
      do IO<Unit>:
        Socket.close(socket)
        Listener.close(listener)
        return Unit{}
    case CheckedSocket{listener,socket,_,None{},True{}}:
      do IO<Unit>:
        Socket.close(socket)
        Listener.close(listener)
        settled : Bool <- Deferred.resolve(CodeResult(),answer,Fail{"Login cancelled"})
        return Unit{}
    case CheckedSocket{listener,socket,bytes,None{},False{}}:
      do IO<Unit>:
        pair : Socket & Result<&1,&1,U32 & String,Bool> <- TCP.readable(socket)
        callbackRun(Readable{listener,pair,bytes},answer,config,signal)
    case Readable{listener,(socket,Done{False{}}),bytes}:
      do IO<Unit>:
        IO.sleep(30)
        callbackRun(Reading{listener,socket,bytes},answer,config,signal)
    case Readable{listener,(socket,Fail{_}),_}:
      do IO<Unit>:
        Socket.close(socket)
        callbackRun(Listening{listener},answer,config,signal)
    case Readable{listener,(socket,Done{True{}}),bytes}:
      do IO<Unit>:
        pair : Socket & Result<&1,&1,U32 & String,List<&2,U32>> <- TCP.recv_bytes(socket,4096)
        callbackRun(Received{listener,pair,bytes},answer,config,signal)
    case Received{listener,(socket,Fail{_}),_}:
      do IO<Unit>:
        Socket.close(socket)
        callbackRun(Listening{listener},answer,config,signal)
    case Received{listener,(socket,Done{Nil{}}),_}:
      do IO<Unit>:
        Socket.close(socket)
        callbackRun(Listening{listener},answer,config,signal)
    case Received{listener,(socket,Done{chunk}),bytes}:
      +joined = List.append(&2,U32,bytes,chunk)
      callbackRun(Line{listener,socket,joined,callbackLine(joined)},answer,config,signal)
    case Line{listener,socket,+bytes,None{}}:
      callbackRun(LineSize{listener,socket,bytes,Nat.is_gt(List.length(&2,U32,bytes),8192n)},answer,config,signal)
    case LineSize{listener,socket,_,True{}}:
      do IO<Unit>:
        respondCallback(socket,False{})
        callbackRun(Listening{listener},answer,config,signal)
    case LineSize{listener,socket,bytes,False{}}: callbackRun(Reading{listener,socket,bytes},answer,config,signal)
    case Line{listener,socket,_,Some{line}}: callbackRun(Parsed{listener,socket,callbackCode(line,config)},answer,config,signal)
    case Parsed{listener,socket,Fail{_}}:
      do IO<Unit>:
        respondCallback(socket,False{})
        callbackRun(Listening{listener},answer,config,signal)
    case Parsed{listener,socket,Done{code}}:
      do IO<Unit>:
        respondCallback(socket,True{})
        settled : Bool <- Deferred.resolve(CodeResult(),answer,Done{code})
        Listener.close(listener)
        return Unit{}


def manualResult(answer: Deferred.Deferred<CodeResult()>, config: CallbackConfig, result: CodeResult()) -> IO(Unit):
  match result:
    case Fail{error}:
      do IO<Unit>:
        settled : Bool <- Deferred.resolve(CodeResult(),answer,Fail{error})
        return Unit{}
    case Done{input}:
      do IO<Unit>:
        settled : Bool <- Deferred.resolve(CodeResult(),answer,authorizationInput(input,config))
        return Unit{}
def manualRun(+answer: Deferred.Deferred<CodeResult()>, config: CallbackConfig, prompt: C.Callback<Auth.AuthPrompt,CodeResult()>, signal: Abort.AbortSignal<Unit>, message: String, placeholder: String) -> IO(Unit):
  do IO<Unit>:
    input : CodeResult() <- C.call(Auth.AuthPrompt,CodeResult(),prompt,Auth.ManualCodePrompt{message,Some{placeholder},Some{signal}})
    manualResult(answer,config,input)
def joinServer(worker: Maybe<&1,Chan(Unit)>) -> IO(Unit):
  match worker:
    case None{}: IO.pure(Unit,Unit{})
    case Some{task}: IO.join(Unit,task)
def serverRun(listener: Result<&1,&1,U32 & String,Listener>, answer: Deferred.Deferred<CodeResult()>,config: CallbackConfig,signal: Abort.AbortSignal<Unit>) -> IO(Maybe<&1,Chan(Unit)>):
  match listener:
    case Fail{_}: IO.pure(Maybe<&1,Chan(Unit)>,None{})
    case Done{socket}:
      do IO<Maybe<&1,Chan(Unit)>>:
        worker : Chan(Unit) <- IO.fork(Unit,callbackRun(Listening{socket},answer,config,signal))
        return Some{worker}
def promptCode(+config: CallbackConfig, listener: Result<&1,&1,U32 & String,Listener>, interaction: Auth.ProviderAuthInteraction, url: String, message: String, instructions: String) -> IO(CodeResult()):
  match interaction config:
    case Auth.ProviderAuthInteraction{+parent,prompt,notify} CallbackConfig{+redirect,path,state}:
      do IO<CodeResult()>:
        +answer : Deferred.Deferred<CodeResult()> <- Deferred.new(CodeResult())
        +manualAbort : Abort.AbortController<Unit> <- Abort.new(Unit)
        +serverAbort : Abort.AbortController<Unit> <- Abort.new(Unit)
        manualLink : Abort.Link<Unit> <- Abort.link(Unit,parent,manualAbort)
        serverLink : Abort.Link<Unit> <- Abort.link(Unit,parent,serverAbort)
        worker : Maybe<&1,Chan(Unit)> <- serverRun(listener,answer,CallbackConfig{redirect,path,state},Abort.signal(Unit,serverAbort))
        C.call(Auth.AuthEvent,Unit,notify,Auth.AuthUrlEvent{url,Some{instructions}})
        manual : Chan(Unit) <- IO.fork(Unit,manualRun(answer,config,prompt,Abort.signal(Unit,manualAbort),message,redirect))
        result : CodeResult() <- Deferred.result(CodeResult(),answer)
        stopManual : Bool <- Abort.abort(Unit,manualAbort,None{})
        stopServer : Bool <- Abort.abort(Unit,serverAbort,None{})
        IO.join(Unit,manual)
        joinServer(worker)
        Abort.unlink(Unit,manualLink)
        Abort.unlink(Unit,serverLink)
        Abort.dispose(Unit,manualAbort)
        Abort.dispose(Unit,serverAbort)
        Deferred.dispose(CodeResult(),answer)
        return result

def callbackHost(value: Result<&1,&1,U32 & String,String>) -> String:
  match value:
    case Done{SCon{first,rest}}: SCon{first,rest}
    case _: "127.0.0.1"
def listenCallback(port: U32) -> IO(Result<&1,&1,U32 & String,Listener>):
  do IO<Result<&1,&1,U32 & String,Listener>>:
    host : Result<&1,&1,U32 & String,String> <- IO.get_env("PI_OAUTH_CALLBACK_HOST")
    TCP.listen_host(callbackHost(host),port)
