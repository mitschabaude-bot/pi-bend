import Base
import ../../../runtime/src/http-abort-classification.bend as Classify
import ../../../runtime/src/http-response-progress.bend as Progress
import ../../../runtime/src/http-socket-exchange.bend as Exchange
import ../../../runtime/src/http-response-reader.bend as Reader
import ../../../runtime/src/http-socket-source.bend as Source
import ../../../runtime/src/abortable-socket.bend as Socket
import ../../../runtime/src/socket-upload.bend as Upload
import ./openai-sse-reader.bend as SSE

def TransportError(-Reason: Data) -> Data:
  Progress.Error<Exchange.ReadError<Reason>>

def socketAbort(-Reason: Data, error: Socket.Error<Reason>) -> Bool:
  match error:
    case Socket.Aborted{_}: True{}
    case Socket.SocketError{_, _}: False{}

def uploadAbort(-Reason: Data, error: Upload.Error<Reason>) -> Bool:
  match error:
    case Upload.WriteFailure{cause, None{}}: socketAbort(Reason, cause)
    case _: False{}

def sourceAbort(-Reason: Data, error: Source.Error<Reason>) -> Bool:
  match error:
    case Source.SocketFailure{cause}: socketAbort(Reason, cause)
    case Source.UploadFailure{cause}: uploadAbort(Reason, cause)
    case _: False{}

def readerAbort(-Reason: Data, error: Reader.ReadError<Source.Error<Reason>>) -> Bool:
  match error:
    case Reader.PrimaryFailure{Reader.SourceError{cause}}: sourceAbort(Reason, cause)
    case Reader.ReleaseFailure{cause}: sourceAbort(Reason, cause)
    case _: False{}

def exchangeAbort(-Reason: Data, error: Exchange.ReadError<Reason>) -> Bool:
  match error:
    case Exchange.ResponseFailure{cause}: readerAbort(Reason, cause)
    case Exchange.DisposalFailure{cause}: sourceAbort(Reason, cause)
    case Exchange.ResponseWithDisposal{_, _}: False{}

def classified(-Reason: Data, aborted: Bool, error: TransportError(Reason)) -> SSE.ReadError<TransportError(Reason)>:
  match aborted:
    case True{}: SSE.Aborted{}
    case False{}: SSE.Failure{error}

def classify(-Reason: Data, error: TransportError(Reason)) -> SSE.ReadError<TransportError(Reason)>:
  +cause = error
  classified(Reason, Classify.standalone(Exchange.ReadError<Reason>, exchangeAbort(Reason), cause), cause)
