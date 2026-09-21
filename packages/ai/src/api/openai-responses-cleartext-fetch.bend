import Base
import ./openai-responses-fetch.bend as Fetch
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/http-buffered-request.bend as Request
import ../../../runtime/src/http-buffered-body.bend as Body
import ../../../runtime/src/http-resolved-exchange.bend as HTTP
import ../../../runtime/src/http-exchange-plan.bend as Plan
import ../../../runtime/src/http-exchange-response.bend as Reader
import ../../../runtime/src/http-socket-exchange.bend as Exchange
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-response-progress.bend as Progress
import ../../../runtime/src/http-connect.bend as Connect
import ../../../runtime/src/connection-driver.bend as Driver
import ../../../runtime/src/dns-resolver.bend as Resolver
import ../../../runtime/src/hosts.bend as Hosts
import ../../../runtime/src/hosts-file.bend as File
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C

# Resolver ownership stays with the caller until all callback calls and
# returned responses have retired. HTTPS is rejected by the exchange plan.
type Context<-SourceError: Data> is Data:
  Context{resolver: Resolver.Resolver, hosts: Result<&2, &2, SourceError, List<&2, Hosts.Entry<File.Address>>>, options: HTTP.Options}

type Error<-Reason: Data, -SourceError: Data> is Data:
  InvalidRequest{cause: Request.URLRequestError}
  Rejected{cause: Plan.Error}
  Unresolved{resolution: Connect.Resolution(Deadline.Cause<Reason>, SourceError)}
  ExchangeFailure{resolution: Connect.Resolution(Deadline.Cause<Reason>, SourceError), attempts: List<&2, Driver.Entry<Deadline.Cause<Reason>>>, cause: HTTP.Error<Deadline.Cause<Reason>>}
  HeaderFailure{resolution: Connect.Resolution(Deadline.Cause<Reason>, SourceError), attempts: List<&2, Driver.Entry<Deadline.Cause<Reason>>>, cause: Progress.Error<Exchange.ReadError<Deadline.Cause<Reason>>>}

def headed(-Reason: Data, -SourceError: Data, resolution: Connect.Resolution(Deadline.Cause<Reason>, SourceError), attempts: List<&2, Driver.Entry<Deadline.Cause<Reason>>>, result: Result<&2, &1, Progress.Error<Exchange.ReadError<Deadline.Cause<Reason>>>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>) -> Result<&2, &1, Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>:
  match result:
    case Fail{cause}: Fail{HeaderFailure{resolution, attempts, cause}}
    case Done{response}: Done{response}

def resolved(-Reason: Data, -SourceError: Data, acquireHeaders: Exchange.Exchange<Deadline.Cause<Reason>> -> IO(Result<&2, &1, Progress.Error<Exchange.ReadError<Deadline.Cause<Reason>>>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>), report: HTTP.Report<Deadline.Cause<Reason>, SourceError>) -> IO(Result<&2, &1, Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>):
  match report:
    case HTTP.Rejected{cause}: IO.pure(Result<&2, &1, Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>, Fail{Rejected{cause}})
    case HTTP.Unresolved{resolution}: IO.pure(Result<&2, &1, Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>, Fail{Unresolved{resolution}})
    case HTTP.Attempted{resolution, attempts, Fail{cause}}: IO.pure(Result<&2, &1, Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>, Fail{ExchangeFailure{resolution, attempts, cause}})
    case HTTP.Attempted{resolution, attempts, Done{exchange}}:
      do IO<Result<&2, &1, Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>>:
        result : Result<&2, &1, Progress.Error<Exchange.ReadError<Deadline.Cause<Reason>>>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>> <- acquireHeaders(exchange)
        return headed(Reason, SourceError, resolution, attempts, result)

def prepared(~Reason: Data, ~SourceError: Data, context: Context<SourceError>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Result<&2, &2, Request.URLRequestError, Request.URLPrepared>) -> IO(Result<&2, &1, Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>):
  match context request:
    case _ Fail{cause}: IO.pure(Result<&2, &1, Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>, Fail{InvalidRequest{cause}})
    case Context{resolver, hosts, options} Done{request}:
      do IO<Result<&2, &1, Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>>:
        report : HTTP.Report<Deadline.Cause<Reason>, SourceError> <- HTTP.start(~Deadline.Cause<Reason>, ~SourceError, resolver, signal, hosts, options, request)
        resolved(Reason, SourceError, exchange => Reader.start(~Deadline.Cause<Reason>, exchange), report)

# Acquire through final headers, leaving the body unread. Header acquisition
# failure already closes the exchange before the enclosing fetch scope retires.
def invoke(~Reason: Data, ~SourceError: Data, context: Context<SourceError>, input: Fetch.Input<Reason>) -> IO(Result<&2, &1, Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>):
  match input:
    case Fetch.Input{url, method, headers, body, signal}:
      prepared(~Reason, ~SourceError, context, signal, Request.prepareURL(url, method, headers, Body.Text{body}))

def create(~Reason: Data, ~SourceError: Data, context: Context<SourceError>) -> IO(C.Callback<Fetch.Input<Reason>, Result<&2, &1, Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>>):
  C.create(~Context<SourceError>, ~Fetch.Input<Reason>, ~Result<&2, &1, Error<Reason, SourceError>, Response.Response<Exchange.Exchange<Deadline.Cause<Reason>>>>, ~(invoke(~Reason, ~SourceError)), context)
