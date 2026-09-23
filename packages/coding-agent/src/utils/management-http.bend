import Base
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-exchange.bend as Exchange
import ../../../runtime/src/http-message.bend as Message
import ../../../runtime/src/url.bend as URL

# Management requests (version checks, catalogs, downloads) with a bounded
# immediate retry, as upstream's fetchWithRetry. Model requests are retried by
# their semantic caller instead and must not use this.

def Transport() -> Type: Fetch.Transport(Unit)
def Scoped() -> Type: Response.State<Unit, Transport()>
def ReadError() -> Data: Exchange.ReadError<Deadline.Cause<Unit>>

# Node's fetch follows up to 20 redirects unless asked to return them.
type Redirect is Data:
  Follow{}
  Manual{}

type Request is Data:
  Request{url: URL.URL, headers: Message.Headers, redirect: Redirect}

# timeoutMs is the budget shared by all attempts and the response body.
# Upstream's optional per-attempt timeout serves only the remote catalog,
# which is not ported.
type FetchRetryOptions is Data:
  FetchRetryOptions{maxRetries: Maybe<&2,Nat>, retryOnStatus: Maybe<&2,Bool>, timeoutMs: U32}

type Error is Data:
  TimedOut{}
  RedirectLimit{}
  InvalidRedirect{location: String}
  FetchFailed{cause: Fetch.Error<Unit>}

def errorMessage(error: Error) -> String:
  match error:
    case TimedOut{}: "The operation was aborted due to timeout"
    case RedirectLimit{}: "fetch failed: redirect count exceeded"
    case InvalidRedirect{location}: "fetch failed: invalid redirect location " ++ location
    case FetchFailed{_}: "fetch failed"

def Outcome() -> Type: Result<&2,&1,Error,Response.Response<Transport()>>

def retryableStatus(code: U32) -> Bool:
  match code:
    case 408: True{}
    case 425: True{}
    case 429: True{}
    case 500: True{}
    case 502: True{}
    case 503: True{}
    case 504: True{}
    case _: False{}

def redirectStatus(code: U32) -> Bool:
  match code:
    case 301: True{}
    case 302: True{}
    case 303: True{}
    case 307: True{}
    case 308: True{}
    case _: False{}

def statusOf(response: Response.Response<Transport()>) -> Response.Response<Transport()> & U32:
  match response:
    case Response.Response{+metadata,body}: (Response.Response{metadata,body},Response.metadataStatus(metadata))

def locationOf(response: Response.Response<Transport()>) -> Response.Response<Transport()> & Maybe<&2,String>:
  match response:
    case Response.Response{+metadata,body}: (Response.Response{metadata,body},Result.default(&2,&2,Message.HeaderSyntaxError,Maybe<&2,String>,Message.get(Response.headers(metadata),"location"),None{}))

# A discarded body is released; its cleanup outcome is not the caller's.
def discard(response: Response.Response<Transport()>) -> IO(Unit):
  match response:
    case Response.Response{_,body}:
      do IO<Unit>:
        next : Response.Next<ReadError(),Transport()> <- Response.closeWith(ReadError(),Transport(),Exchange.closeSocketExchange(Deadline.Cause<Unit>),body)
        return Unit{}

def fetched(result: Fetch.Result_(Unit)) -> Outcome():
  match result:
    case Fail{cause}: Fail{FetchFailed{cause}}
    case Done{response}: Done{response}

def dispatch(fetch: Fetch.Fetch(Unit),signal: Fetch.Signal(Unit),url: URL.URL,headers: Message.Headers) -> IO(Outcome()):
  do IO<Outcome()>:
    result : Fetch.Result_(Unit) <- C.call(Fetch.Input<Unit>,Fetch.Result_(Unit),fetch,Fetch.Input{url,"GET",headers,Message.Absent{},signal})
    return fetched(result)

type Hop is Type:
  Final{response: Response.Response<Transport()>}
  Redirected{url: URL.URL}
  Failed{error: Error}

def resolved(+location: String,result: Result<&2,&2,URL.ResolveError,URL.URL>) -> Hop:
  match result:
    case Fail{_}: Failed{InvalidRedirect{location}}
    case Done{url}: Redirected{url}

def hop(context: URL.Context,base: URL.URL,response: Response.Response<Transport()> & Maybe<&2,String>) -> IO(Hop):
  match response:
    case (response,None{}): IO.pure(Hop,Final{response})
    case (response,Some{+location}):
      do IO<Hop>:
        discard(response)
        return resolved(location,URL.parseResolve(context,base,location))

def redirectedBy(moved: Bool,context: URL.Context,base: URL.URL,response: Response.Response<Transport()>) -> IO(Hop):
  match moved:
    case True{}: hop(context,base,locationOf(response))
    case False{}: IO.pure(Hop,Final{response})

def redirected(context: URL.Context,base: URL.URL,redirect: Redirect,pair: Response.Response<Transport()> & U32) -> IO(Hop):
  match redirect pair:
    case Follow{} Tuple{response,code}: redirectedBy(redirectStatus(code),context,base,response)
    case Manual{} Tuple{response,_}: IO.pure(Hop,Final{response})

def stepped(context: URL.Context,base: URL.URL,redirect: Redirect,result: Outcome()) -> IO(Hop):
  match result:
    case Fail{error}: IO.pure(Hop,Failed{error})
    case Done{response}: redirected(context,base,redirect,statusOf(response))

def continued(step: Hop,next: URL.URL -> IO(Outcome())) -> IO(Outcome()):
  match step:
    case Final{response}: IO.pure(Outcome(),Done{response})
    case Failed{error}: IO.pure(Outcome(),Fail{error})
    case Redirected{url}: next(url)

# One attempt: the request and at most 20 redirects, each to a GET.
def follow(fuel: Nat,+fetch: Fetch.Fetch(Unit),+context: URL.Context,+signal: Fetch.Signal(Unit),request: Request) -> IO(Outcome()):
  match fuel request:
    case 0n _: IO.pure(Outcome(),Fail{RedirectLimit{}})
    case 1n+rest Request{+url,+headers,+redirect}:
      do IO<Outcome()>:
        result : Outcome() <- dispatch(fetch,signal,url,headers)
        step : Hop <- stepped(context,url,redirect,result)
        continued(step,next => follow(rest,fetch,context,signal,Request{next,headers,redirect}))

type Decision is Type:
  Return{outcome: Outcome()}
  Again{}

def retrying(retry: Bool,response: Response.Response<Transport()>) -> IO(Decision):
  match retry:
    case True{}:
      do IO<Decision>:
        discard(response)
        return Again{}
    case False{}: IO.pure(Decision,Return{Done{response}})

def statusDecision(retryOnStatus: Bool,canRetry: Bool,pair: Response.Response<Transport()> & U32) -> IO(Decision):
  match pair:
    case Tuple{response,code}: retrying(retryOnStatus && canRetry && retryableStatus(code),response)

def failureDecision(error: Error,expired: Bool,canRetry: Bool) -> Decision:
  match expired canRetry:
    case True{} _: Return{Fail{TimedOut{}}}
    case False{} False{}: Return{Fail{error}}
    case False{} True{}: Again{}

def decided(retryOnStatus: Bool,+canRetry: Bool,signal: Fetch.Signal(Unit),result: Outcome()) -> IO(Decision):
  match result:
    case Done{response}: statusDecision(retryOnStatus,canRetry,statusOf(response))
    case Fail{error}:
      do IO<Decision>:
        expired : Bool <- Abort.aborted(Deadline.Cause<Unit>,signal)
        return failureDecision(error,expired,canRetry)

def settle(decision: Decision,again: Unit -> IO(Outcome())) -> IO(Outcome()):
  match decision:
    case Return{outcome}: IO.pure(Outcome(),outcome)
    case Again{}: again(Unit{})

# A transient status or a transport failure is retried at once while attempts
# remain; the shared deadline ends every attempt.
def attempts(remaining: Nat,+retryOnStatus: Bool,+fetch: Fetch.Fetch(Unit),+context: URL.Context,+signal: Fetch.Signal(Unit),+request: Request) -> IO(Outcome()):
  match remaining:
    case 0n:
      do IO<Outcome()>:
        result : Outcome() <- follow(21n,fetch,context,signal,request)
        decision : Decision <- decided(retryOnStatus,False{},signal,result)
        settle(decision,_ => IO.pure(Outcome(),Fail{TimedOut{}}))
    case 1n+rest:
      do IO<Outcome()>:
        result : Outcome() <- follow(21n,fetch,context,signal,request)
        decision : Decision <- decided(retryOnStatus,True{},signal,result)
        settle(decision,_ => attempts(rest,retryOnStatus,fetch,context,signal,request))

def ScopedOutcome() -> Type: Result<&2,&1,Error,Response.Response<Scoped()>>

def scoped(scope: Deadline.Scope<Unit>,result: Outcome()) -> IO(ScopedOutcome()):
  match result:
    case Fail{error}:
      do IO<ScopedOutcome()>:
        reason : Maybe<&2,Abort.AbortReason<Deadline.Cause<Unit>>> <- Deadline.close(Unit,scope)
        return Fail{error}
    case Done{response}:
      do IO<ScopedOutcome()>:
        attached : Response.Response<Scoped()> <- Response.attach(Unit,Transport(),scope,response)
        return Done{attached}

def run(options: FetchRetryOptions,fetch: Fetch.Fetch(Unit),context: URL.Context,request: Request,pair: Deadline.Scope<Unit> & Fetch.Signal(Unit)) -> IO(ScopedOutcome()):
  match options pair:
    case FetchRetryOptions{maxRetries,retryOnStatus,_} Tuple{scope,signal}:
      do IO<ScopedOutcome()>:
        result : Outcome() <- attempts(Maybe.default(&2,Nat,maxRetries,2n),Maybe.default(&2,Bool,retryOnStatus,True{}),fetch,context,signal,request)
        scoped(scope,result)

# The response keeps the deadline through its body: closing the body ends
# both. The caller's signal ends every attempt, too; it must outlive the body.
def fetchWithRetry(fetch: Fetch.Fetch(Unit),context: URL.Context,request: Request,parent: Abort.AbortSignal<Unit>,+options: FetchRetryOptions) -> IO(ScopedOutcome()):
  match options:
    case FetchRetryOptions{_,_,timeoutMs}:
      do IO<ScopedOutcome()>:
        scope : Deadline.Scope<Unit> <- Deadline.create(Unit,timeoutMs,parent)
        run(options,fetch,context,request,Deadline.borrow(Unit,scope))

# Reading and releasing a body obtained through fetchWithRetry.
def read(state: Scoped()) -> IO(Scoped() & Result<&2,&2,ReadError(),Maybe<&2,Response.StreamEvent>>):
  Response.read(Unit,ReadError(),Transport(),Exchange.read(Deadline.Cause<Unit>),state)

def close(state: Scoped()) -> IO(Result<&2,&2,ReadError(),Unit>):
  Response.closeFetchScope(Unit,ReadError(),Transport(),Exchange.closeSocketExchange(Deadline.Cause<Unit>),state)
