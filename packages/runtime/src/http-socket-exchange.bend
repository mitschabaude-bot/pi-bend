import Base
import ./abort.bend as A
import ./abortable-socket.bend as Transport
import ./socket-interrupt.bend as Interrupt
import ./socket-upload.bend as Upload
import ./http-buffered-request.bend as Request
import ./http-buffered-framing.bend as Framing
import ./http-request-head.bend as Head
import ./http-socket-source.bend as Source
import ./http-response-reader.bend as Reader
import ./http-response-stream.bend as Stream

# A dedicated connected cleartext socket exchange. Connection establishment,
# TLS, pooling and URL preparation belong to higher transport layers. This
# upload task runs concurrently with response reads and is joined on release.
type StartError<-Reason: Data> is Data:
  InvalidReadSize{}
  SocketFailure{error: Transport.Error<Reason>}
  WriteFailure{error: Transport.Error<Reason>, cleanup: Maybe<&2, Interrupt.Error>}
  SourceFailure{error: Source.Error<Reason>}

type ReadError<-Reason: Data> is Data:
  ResponseFailure{error: Reader.ReadError<Source.Error<Reason>>}
  DisposalFailure{error: Source.Error<Reason>}
  ResponseWithDisposal{error: Reader.ReadError<Source.Error<Reason>>, disposal: Source.Error<Reason>}

type Exchange<-Reason: Data> is Type:
  Open{owner: Source.Owner<Reason>, cursor: Reader.Cursor<Source.Error<Reason>>}
  Closed{}

type Next<-Reason: Data> is Type:
  Next{exchange: Exchange<Reason>, result: Result<&2, &2, ReadError<Reason>, Maybe<&2, Stream.Event>>}

def opened(-Reason: Data, method: String, limits: Stream.Limits, pair: Source.Owner<Reason> & Reader.Source<Source.Error<Reason>>) -> Exchange<Reason>:
  match pair:
    case (owner, source): Open{owner, Reader.create(Source.Error<Reason>, source, method, limits)}

def adopted(-Reason: Data, method: String, limits: Stream.Limits, result: Result<&2, &1, Source.Error<Reason>, Source.Owner<Reason>>) -> Result<&2, &1, StartError<Reason>, Exchange<Reason>>:
  match result:
    case Fail{error}: Fail{SourceFailure{error}}
    case Done{owner}: Done{opened(Reason, method, limits, Source.borrow(Reason, owner))}

def cleanupError(result: Result<&2, &2, Interrupt.Error, Unit>) -> Maybe<&2, Interrupt.Error>:
  match result:
    case Done{_}: None{}
    case Fail{error}: Some{error}

def uploading(~Reason: Data, method: String, maximum: U32, limits: Stream.Limits, pair: Transport.Owner<Reason> & Result<&2, &1, Transport.Error<Reason>, Upload.Owner<Reason>>) -> IO(Result<&2, &1, StartError<Reason>, Exchange<Reason>>):
  match pair:
    case (owner, Fail{error}):
      do IO<Result<&2, &1, StartError<Reason>, Exchange<Reason>>>:
        cleanup : Result<&2, &2, Interrupt.Error, Unit> <- Transport.close(Reason, owner)
        return Fail{WriteFailure{error, cleanupError(cleanup)}}
    case (owner, Done{upload}):
      do IO<Result<&2, &1, StartError<Reason>, Exchange<Reason>>>:
        source : Source.Owner<Reason> <- Source.adoptLease(~Reason, maximum, Source.Lease{owner, Some{upload}})
        return Done{opened(Reason, method, limits, Source.borrow(Reason, source))}

def connected(~Reason: Data, request: Request.Prepared, maximum: U32, limits: Stream.Limits, result: Result<&2, &1, Transport.Error<Reason>, Transport.Owner<Reason>>) -> IO(Result<&2, &1, StartError<Reason>, Exchange<Reason>>):
  match request result:
    case _ Fail{error}: IO.pure(Result<&2, &1, StartError<Reason>, Exchange<Reason>>, Fail{SocketFailure{error}})
    case Request.Prepared{Head.Head{method, head}, body} Done{owner}:
      do IO<Result<&2, &1, StartError<Reason>, Exchange<Reason>>>:
        result : Transport.Owner<Reason> & Result<&2, &1, Transport.Error<Reason>, Upload.Owner<Reason>> <- Upload.start(Reason, owner, head, Framing.wireBody(body))
        uploading(~Reason, method, maximum, limits, result)

# Takes ownership on every path. The read-size guard precedes any request IO.
# Writes share the connection-wide AbortSignal observation with response reads.
def start(~Reason: Data, socket: Socket, signal: A.AbortSignal<Reason>, request: Request.Prepared, maximum: U32, limits: Stream.Limits) -> IO(Result<&2, &1, StartError<Reason>, Exchange<Reason>>):
  match maximum:
    case 0:
      do IO<Result<&2, &1, StartError<Reason>, Exchange<Reason>>>:
        Socket.close(socket)
        return Fail{InvalidReadSize{}}
    case size:
      do IO<Result<&2, &1, StartError<Reason>, Exchange<Reason>>>:
        result : Result<&2, &1, Transport.Error<Reason>, Transport.Owner<Reason>> <- Transport.create(Reason, socket, signal)
        connected(~Reason, request, size, limits, result)

def outcome(-Reason: Data, primary: Result<&2, &2, Reader.ReadError<Source.Error<Reason>>, Unit>, disposal: Result<&2, &2, Source.Error<Reason>, Unit>) -> Result<&2, &2, ReadError<Reason>, Unit>:
  match primary disposal:
    case Done{_} Done{_}: Done{Unit{}}
    case Fail{error} Done{_}: Fail{ResponseFailure{error}}
    case Done{_} Fail{error}: Fail{DisposalFailure{error}}
    case Fail{error} Fail{disposal}: Fail{ResponseWithDisposal{error, disposal}}

def ended(-Reason: Data, result: Result<&2, &2, ReadError<Reason>, Unit>) -> Next<Reason>:
  match result:
    case Done{_}: Next{Closed{}, Done{None{}}}
    case Fail{error}: Next{Closed{}, Fail{error}}

def finish(-Reason: Data, owner: Source.Owner<Reason>, result: Result<&2, &2, Reader.ReadError<Source.Error<Reason>>, Unit>) -> IO(Next<Reason>):
  do IO<Next<Reason>>:
    disposed : Result<&2, &2, Source.Error<Reason>, Unit> <- Source.dispose(Reason, owner)
    return ended(Reason, outcome(Reason, result, disposed))

def read(-Reason: Data, owner: Source.Owner<Reason>, result: Reader.Next<Source.Error<Reason>>) -> IO(Next<Reason>):
  match result:
    case Reader.Next{_, Fail{error}}: finish(Reason, owner, Fail{error})
    case Reader.Next{_, Done{None{}}}: finish(Reason, owner, Done{Unit{}})
    case Reader.Next{cursor, Done{Some{event}}}: IO.pure(Next<Reason>, Next{Open{owner, cursor}, Done{Some{event}}})

# EOF/errors retire callback factories as well as the socket. Early consumers
# must close explicitly; merely dropping an affine Bend value is not disposal.
def next(-Reason: Data, exchange: Exchange<Reason>) -> IO(Next<Reason>):
  match exchange:
    case Closed{}: IO.pure(Next<Reason>, Next{Closed{}, Done{None{}}})
    case Open{owner, cursor}:
      do IO<Next<Reason>>:
        result : Reader.Next<Source.Error<Reason>> <- Reader.next(Source.Error<Reason>, cursor)
        read(Reason, owner, result)

def closed(-Reason: Data, owner: Source.Owner<Reason>, result: Reader.CloseResult<Source.Error<Reason>>) -> IO(Result<&2, &2, ReadError<Reason>, Unit>):
  match result:
    case Reader.CloseResult{_, primary}:
      do IO<Result<&2, &2, ReadError<Reason>, Unit>>:
        disposal : Result<&2, &2, Source.Error<Reason>, Unit> <- Source.dispose(Reason, owner)
        return outcome(Reason, primary, disposal)

def close(-Reason: Data, exchange: Exchange<Reason>) -> IO(Result<&2, &2, ReadError<Reason>, Unit>):
  match exchange:
    case Closed{}: IO.pure(Result<&2, &2, ReadError<Reason>, Unit>, Done{Unit{}})
    case Open{owner, cursor}:
      do IO<Result<&2, &2, ReadError<Reason>, Unit>>:
        result : Reader.CloseResult<Source.Error<Reason>> <- Reader.close(Source.Error<Reason>, cursor)
        closed(Reason, owner, result)
