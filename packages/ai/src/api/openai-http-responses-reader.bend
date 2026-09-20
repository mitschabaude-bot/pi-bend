import Base
import ./openai-http-errors.bend as Errors
import ./openai-sse-reader.bend as SSE
import ./openai-responses-reader.bend as Reader
import ./openai-responses-stream.bend as Stream
import ../../../runtime/src/http-exchange-response.bend as HTTP
import ../../../runtime/src/http-socket-exchange.bend as Exchange
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-body-source.bend as Source
import ../../../runtime/src/sse-reader.bend as Bytes
import ./openai-responses-stream-pricing.bend as Pricing
import ../types.bend as Types
import ../../../runtime/src/schema-value.bend as Value
import ../../../runtime/src/callback.bend as Callback

# Hooks are borrowed from the provider. This owner retires the provider reader
# before its HTTP byte-source callbacks, including an entirely unread body.
type Owner<-Reason: Data, -E: Data> is Type:
  Owner{source: Source.Owner<Exchange.Exchange<Reason>, SSE.ReadError<Errors.TransportError(Reason)>>, reader: Reader.Owner<Errors.TransportError(Reason), E>}

type CloseError<-Reason: Data> is Data:
  ReaderFailure{error: Reader.Error<Errors.TransportError(Reason)>}
  BodyFailure{error: SSE.ReadError<Errors.TransportError(Reason)>}
  BothFailures{reader: Reader.Error<Errors.TransportError(Reason)>, body: SSE.ReadError<Errors.TransportError(Reason)>}

def acquired(~Reason: Data, ~E: Data, ~map: Reader.Error<Errors.TransportError(Reason)> -> E, hooks: SSE.Hooks<Errors.TransportError(Reason)>, synthesize: Bool, pair: Source.Owner<Exchange.Exchange<Reason>, SSE.ReadError<Errors.TransportError(Reason)>> & Bytes.Source<SSE.ReadError<Errors.TransportError(Reason)>>) -> IO(Owner<Reason, E>):
  match pair:
    case (source, bytes):
      do IO<Owner<Reason, E>>:
        reader : Reader.Owner<Errors.TransportError(Reason), E> <- Reader.create(~Errors.TransportError(Reason), ~E, ~map, SSE.create(Errors.TransportError(Reason), bytes, hooks, synthesize))
        return Owner{source, reader}

def create(~Reason: Data, ~E: Data, ~map: Reader.Error<Errors.TransportError(Reason)> -> E, body: Response.Body<Exchange.Exchange<Reason>>, hooks: SSE.Hooks<Errors.TransportError(Reason)>, synthesize: Bool) -> IO(Owner<Reason, E>):
  do IO<Owner<Reason, E>>:
    source : Source.Owner<Exchange.Exchange<Reason>, SSE.ReadError<Errors.TransportError(Reason)>> <- HTTP.source(~Reason, ~SSE.ReadError<Errors.TransportError(Reason)>, ~(Errors.classify(Reason)), body)
    acquired(~Reason, ~E, ~map, hooks, synthesize, Source.borrow(Exchange.Exchange<Reason>, SSE.ReadError<Errors.TransportError(Reason)>, source))

def borrowed(-Reason: Data, -E: Data, source: Source.Owner<Exchange.Exchange<Reason>, SSE.ReadError<Errors.TransportError(Reason)>>, pair: Reader.Owner<Errors.TransportError(Reason), E> & Stream.Reader<E>) -> Owner<Reason, E> & Stream.Reader<E>:
  match pair:
    case (reader, handle): (Owner{source, reader}, handle)

def borrow(-Reason: Data, -E: Data, owner: Owner<Reason, E>) -> Owner<Reason, E> & Stream.Reader<E>:
  match owner:
    case Owner{source, reader}: borrowed(Reason, E, source, Reader.borrow(Errors.TransportError(Reason), E, reader))

def outcome(-Reason: Data, reader: Result<&2, &2, Reader.Error<Errors.TransportError(Reason)>, Unit>, body: Result<&2, &2, SSE.ReadError<Errors.TransportError(Reason)>, Unit>) -> Result<&2, &2, CloseError<Reason>, Unit>:
  match reader body:
    case Done{_} Done{_}: Done{Unit{}}
    case Fail{error} Done{_}: Fail{ReaderFailure{error}}
    case Done{_} Fail{error}: Fail{BodyFailure{error}}
    case Fail{first} Fail{second}: Fail{BothFailures{first, second}}

def dispose(-Reason: Data, -E: Data, owner: Owner<Reason, E>) -> IO(Result<&2, &2, CloseError<Reason>, Unit>):
  match owner:
    case Owner{source, reader}:
      do IO<Result<&2, &2, CloseError<Reason>, Unit>>:
        first : Result<&2, &2, Reader.Error<Errors.TransportError(Reason)>, Unit> <- Reader.dispose(Errors.TransportError(Reason), E, reader)
        second : Result<&2, &2, SSE.ReadError<Errors.TransportError(Reason)>, Unit> <- Source.dispose(Exchange.Exchange<Reason>, SSE.ReadError<Errors.TransportError(Reason)>, source)
        return outcome(Reason, first, second)

type Processed<-Reason: Data, -G: Data, -E: Data> is Data:
  Processed{result: Stream.RunResult<G, E>, disposal: Result<&2, &2, CloseError<Reason>, Unit>}

def processBorrowed(-Reason: Data, -G: Data, -E: Data, -J: Data, output: Types.AssistantMessage<Value.Value, G>, sink: Callback.Callback<Types.AssistantMessageEvent<Value.Value, G>, Result<&2, &2, E, Unit>>, model: Types.Model<J>, options: Pricing.OpenAIResponsesStreamOptions<E>, pair: Owner<Reason, E> & Stream.Reader<E>) -> IO(Processed<Reason, G, E>):
  match pair:
    case (owner, reader):
      do IO<Processed<Reason, G, E>>:
        result : Stream.RunResult<G, E> <- Stream.processResponsesStream(G, E, J, reader, output, sink, model, options)
        cleanup : Result<&2, &2, CloseError<Reason>, Unit> <- dispose(Reason, E, owner)
        return Processed{result, cleanup}

# Own the entire processing lifetime. Keep the processor's partial output and
# primary result even if subsequent owner disposal fails. Sink/pricing/abort
# callbacks and the parent signal remain borrowed until this operation returns.
def process(-Reason: Data, -G: Data, -E: Data, -J: Data, owner: Owner<Reason, E>, output: Types.AssistantMessage<Value.Value, G>, sink: Callback.Callback<Types.AssistantMessageEvent<Value.Value, G>, Result<&2, &2, E, Unit>>, model: Types.Model<J>, options: Pricing.OpenAIResponsesStreamOptions<E>) -> IO(Processed<Reason, G, E>):
  processBorrowed(Reason, G, E, J, output, sink, model, options, borrow(Reason, E, owner))
