import Base
import ./abort.bend as Abort
import ./deadline.bend as Deadline
import ./dns-query.bend as Request
import ./dns-tcp-query.bend as Reply
import ./dns-tcp-servers.bend as TCP
import ./dns-transport.bend as Transport
import ./dns-udp-plan.bend as Plan
import ./dns-server-source.bend as Selector
import ./socket-endpoint.bend as Endpoint
import ./resolver-options.bend as Options

# Both sources borrow an existing rotation owner. Selection happens inside
# exchange, after the lookup has drawn an ID and rechecked cancellation.
type Source is Data:
  TcpSource{source: Selector.Source<TCP.Server>}
  Configured{source: Selector.Source<Plan.Attempt<Endpoint.Endpoint>>, options: Options.Options}

type Error<-Reason: Data> is Data:
  TcpError{error: TCP.Error<Reason>}
  TransportError{error: Transport.Error<Reason>}

def available(source: Source) -> Bool:
  match source:
    case TcpSource{selector}: Selector.available(TCP.Server, selector)
    case Configured{selector, _}: Selector.available(Plan.Attempt<Endpoint.Endpoint>, selector)

def tcp(-Reason: Data, value: Result<&2, &2, TCP.Error<Reason>, Reply.Reply>) -> Result<&2, &2, Error<Reason>, Reply.Reply>:
  match value:
    case Done{reply}: Done{reply}
    case Fail{error}: Fail{TcpError{error}}

def native(-Reason: Data, value: Result<&2, &2, Transport.Error<Reason>, Reply.Reply>) -> Result<&2, &2, Error<Reason>, Reply.Reply>:
  match value:
    case Done{reply}: Done{reply}
    case Fail{error}: Fail{TransportError{error}}

def attempts(options: Options.Options) -> Nat:
  match options:
    case Options.Options{_, _, count, _}: U32.to_nat(count)

def exchangeRequest(-Reason: Data, source: Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Request.Request, maximum: U32) -> IO(Result<&2, &2, Error<Reason>, Reply.Reply>):
  match source:
    case TcpSource{selector}:
      do IO<Result<&2, &2, Error<Reason>, Reply.Reply>>:
        servers : List<&2, TCP.Server> <- Selector.choose(TCP.Server, selector)
        result : Result<&2, &2, TCP.Error<Reason>, Reply.Reply> <- TCP.exchangeRequest(Reason, servers, signal, request, maximum)
        return tcp(Reason, result)
    case Configured{selector, +options}:
      do IO<Result<&2, &2, Error<Reason>, Reply.Reply>>:
        servers : List<&2, Plan.Attempt<Endpoint.Endpoint>> <- Selector.choose(Plan.Attempt<Endpoint.Endpoint>, selector)
        result : Result<&2, &2, Transport.Error<Reason>, Reply.Reply> <- Transport.exchangeWith(Reason, Options.enabled(Options.UseTcp{}, options), attempts(options), servers, signal, request, maximum)
        return native(Reason, result)
