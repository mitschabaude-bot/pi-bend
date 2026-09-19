import Base
import ./abort.bend as Abort
import ./abortable-connect.bend as Connect
import ./http-buffered-request.bend as Request
import ./http-socket-exchange.bend as Exchange
import ./http-response-stream.bend as Response

# Numeric cleartext transport. Address selection, TLS and URL preparation are
# caller responsibilities; request authority is independent of its chosen IP.
type Error<-Reason: Data> is Data:
  ConnectionFailure{error: Connect.Error<Reason>}
  ExchangeFailure{error: Exchange.StartError<Reason>}

def started(-Reason: Data, result: Result<&2, &1, Exchange.StartError<Reason>, Exchange.Exchange<Reason>>) -> Result<&2, &1, Error<Reason>, Exchange.Exchange<Reason>>:
  match result:
    case Fail{error}: Fail{ExchangeFailure{error}}
    case Done{exchange}: Done{exchange}

def connected(~Reason: Data, signal: Abort.AbortSignal<Reason>, request: Request.Prepared, maximum: U32, limits: Response.Limits, result: Result<&2, &1, Connect.Error<Reason>, Socket>) -> IO(Result<&2, &1, Error<Reason>, Exchange.Exchange<Reason>>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &1, Error<Reason>, Exchange.Exchange<Reason>>, Fail{ConnectionFailure{error}})
    case Done{socket}:
      do IO<Result<&2, &1, Error<Reason>, Exchange.Exchange<Reason>>>:
        result : Result<&2, &1, Exchange.StartError<Reason>, Exchange.Exchange<Reason>> <- Exchange.start(~Reason, socket, signal, request, maximum, limits)
        return started(Reason, result)

# The same retained signal spans connect, upload and response reads. Socket
# adoption rechecks it, including abort between connect and watcher handoff.
# On success callers consume or close the exchange before disposing the signal.
def start(~Reason: Data, address: Connect.Address, port: U32, +signal: Abort.AbortSignal<Reason>, request: Request.Prepared, maximum: U32, limits: Response.Limits) -> IO(Result<&2, &1, Error<Reason>, Exchange.Exchange<Reason>>):
  match maximum:
    case 0: IO.pure(Result<&2, &1, Error<Reason>, Exchange.Exchange<Reason>>, Fail{ExchangeFailure{Exchange.InvalidReadSize{}}})
    case size:
      do IO<Result<&2, &1, Error<Reason>, Exchange.Exchange<Reason>>>:
        result : Result<&2, &1, Connect.Error<Reason>, Socket> <- Connect.connect(Reason, address, port, signal)
        connected(~Reason, signal, request, size, limits, result)
