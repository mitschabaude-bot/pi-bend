import Base
import ./openai-http-errors.bend as Errors
import ./openai-sse-reader.bend as SSE
import ./openai-responses-reader.bend as Reader
import ./openai-responses-stream.bend as Stream
import ./openai-body-responses-reader.bend as Body
import ../../../runtime/src/http-exchange-response.bend as HTTP
import ../../../runtime/src/http-socket-exchange.bend as Exchange
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-body-source.bend as Source
import ./openai-responses-stream-pricing.bend as Pricing
import ../types.bend as Types
import ../../../runtime/src/schema-value.bend as Value
import ../../../runtime/src/callback.bend as Callback

# Preserve the concrete HTTP entry points while sharing the provider reader's
# complete processing and disposal lifetime with other affine body transports.
type Owner<-Reason: Data, -E: Data> is Type:
  Owner{inner: Body.Owner<Exchange.Exchange<Reason>, Errors.TransportError(Reason), E>}

type CloseError<-Reason: Data> is Data:
  ReaderFailure{error: Reader.Error<Errors.TransportError(Reason)>}
  BodyFailure{error: SSE.ReadError<Errors.TransportError(Reason)>}
  BothFailures{reader: Reader.Error<Errors.TransportError(Reason)>, body: SSE.ReadError<Errors.TransportError(Reason)>}

def closeResult(-Reason: Data, result: Result<&2, &2, Body.CloseError<Errors.TransportError(Reason)>, Unit>) -> Result<&2, &2, CloseError<Reason>, Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{Body.ReaderFailure{cause}}: Fail{ReaderFailure{cause}}
    case Fail{Body.BodyFailure{cause}}: Fail{BodyFailure{cause}}
    case Fail{Body.BothFailures{first, second}}: Fail{BothFailures{first, second}}

def create(~Reason: Data, ~E: Data, ~map: Reader.Error<Errors.TransportError(Reason)> -> E, body: Response.Body<Exchange.Exchange<Reason>>, hooks: SSE.Hooks<Errors.TransportError(Reason)>, synthesize: Bool) -> IO(Owner<Reason, E>):
  do IO<Owner<Reason, E>>:
    source : Source.Owner<Exchange.Exchange<Reason>, SSE.ReadError<Errors.TransportError(Reason)>> <- HTTP.source(~Reason, ~SSE.ReadError<Errors.TransportError(Reason)>, ~(Errors.classify(Reason)), body)
    inner : Body.Owner<Exchange.Exchange<Reason>, Errors.TransportError(Reason), E> <- Body.fromSource(~Exchange.Exchange<Reason>, ~Errors.TransportError(Reason), ~E, ~map, source, hooks, synthesize)
    return Owner{inner}

def borrowed(-Reason: Data, -E: Data, pair: Body.Owner<Exchange.Exchange<Reason>, Errors.TransportError(Reason), E> & Stream.Reader<E>) -> Owner<Reason, E> & Stream.Reader<E>:
  match pair:
    case (inner, handle): (Owner{inner}, handle)

def borrow(-Reason: Data, -E: Data, owner: Owner<Reason, E>) -> Owner<Reason, E> & Stream.Reader<E>:
  match owner:
    case Owner{inner}: borrowed(Reason, E, Body.borrow(Exchange.Exchange<Reason>, Errors.TransportError(Reason), E, inner))

def outcome(-Reason: Data, reader: Result<&2, &2, Reader.Error<Errors.TransportError(Reason)>, Unit>, body: Result<&2, &2, SSE.ReadError<Errors.TransportError(Reason)>, Unit>) -> Result<&2, &2, CloseError<Reason>, Unit>:
  closeResult(Reason, Body.outcome(Errors.TransportError(Reason), reader, body))

def dispose(-Reason: Data, -E: Data, owner: Owner<Reason, E>) -> IO(Result<&2, &2, CloseError<Reason>, Unit>):
  match owner:
    case Owner{inner}:
      do IO<Result<&2, &2, CloseError<Reason>, Unit>>:
        result : Result<&2, &2, Body.CloseError<Errors.TransportError(Reason)>, Unit> <- Body.dispose(Exchange.Exchange<Reason>, Errors.TransportError(Reason), E, inner)
        return closeResult(Reason, result)

type Processed<-Reason: Data, -G: Data, -E: Data> is Data:
  Processed{result: Stream.RunResult<G, E>, disposal: Result<&2, &2, CloseError<Reason>, Unit>}

def completed(-Reason: Data, -G: Data, -E: Data, value: Body.Processed<Errors.TransportError(Reason), G, E>) -> Processed<Reason, G, E>:
  match value:
    case Body.Processed{result, disposal}: Processed{result, closeResult(Reason, disposal)}

def process(-Reason: Data, -G: Data, -E: Data, -J: Data, owner: Owner<Reason, E>, output: Types.AssistantMessage<Value.Value, G>, sink: Callback.Callback<Types.AssistantMessageEvent<Value.Value, G>, Result<&2, &2, E, Unit>>, model: Types.Model<J>, options: Pricing.OpenAIResponsesStreamOptions<E>) -> IO(Processed<Reason, G, E>):
  match owner:
    case Owner{inner}:
      do IO<Processed<Reason, G, E>>:
        result : Body.Processed<Errors.TransportError(Reason), G, E> <- Body.process(Exchange.Exchange<Reason>, Errors.TransportError(Reason), G, E, J, inner, output, sink, model, options)
        return completed(Reason, G, E, result)
