import Base
import ./openai-sse-reader.bend as SSE
import ./openai-responses-reader.bend as Reader
import ./openai-responses-stream.bend as Stream
import ../../../runtime/src/http-body-source.bend as Source
import ../../../runtime/src/sse-reader.bend as Bytes
import ./openai-responses-stream-pricing.bend as Pricing
import ../types.bend as Types
import ../../../runtime/src/schema-value.bend as Value
import ../../../runtime/src/callback.bend as Callback

# Hooks are borrowed from the provider. This owner retires the provider reader
# before its HTTP byte-source callbacks, including an entirely unread body.
type Owner<-State: Type, -Transport: Data, -E: Data> is Type:
  Owner{source: Source.Owner<State, SSE.ReadError<Transport>>, reader: Reader.Owner<Transport, E>}

type CloseError<-Transport: Data> is Data:
  ReaderFailure{error: Reader.Error<Transport>}
  BodyFailure{error: SSE.ReadError<Transport>}
  BothFailures{reader: Reader.Error<Transport>, body: SSE.ReadError<Transport>}

def acquired(~State: Type, ~Transport: Data, ~E: Data, ~map: Reader.Error<Transport> -> E, hooks: SSE.Hooks<Transport>, synthesize: Bool, pair: Source.Owner<State, SSE.ReadError<Transport>> & Bytes.Source<SSE.ReadError<Transport>>) -> IO(Owner<State, Transport, E>):
  match pair:
    case (source, bytes):
      do IO<Owner<State, Transport, E>>:
        reader : Reader.Owner<Transport, E> <- Reader.create(~Transport, ~E, ~map, SSE.create(Transport, bytes, hooks, synthesize))
        return Owner{source, reader}

# Consume a source created by the generic HTTP body-source adapter. Its read
# and close callbacks already encode the concrete transport/cancellation scope.
def fromSource(~State: Type, ~Transport: Data, ~E: Data, ~map: Reader.Error<Transport> -> E, source: Source.Owner<State, SSE.ReadError<Transport>>, hooks: SSE.Hooks<Transport>, synthesize: Bool) -> IO(Owner<State, Transport, E>):
  acquired(~State, ~Transport, ~E, ~map, hooks, synthesize, Source.borrow(State, SSE.ReadError<Transport>, source))

def borrowed(-State: Type, -Transport: Data, -E: Data, source: Source.Owner<State, SSE.ReadError<Transport>>, pair: Reader.Owner<Transport, E> & Stream.Reader<E>) -> Owner<State, Transport, E> & Stream.Reader<E>:
  match pair:
    case (reader, handle): (Owner{source, reader}, handle)

def borrow(-State: Type, -Transport: Data, -E: Data, owner: Owner<State, Transport, E>) -> Owner<State, Transport, E> & Stream.Reader<E>:
  match owner:
    case Owner{source, reader}: borrowed(State, Transport, E, source, Reader.borrow(Transport, E, reader))

def outcome(-Transport: Data, reader: Result<&2, &2, Reader.Error<Transport>, Unit>, body: Result<&2, &2, SSE.ReadError<Transport>, Unit>) -> Result<&2, &2, CloseError<Transport>, Unit>:
  match reader body:
    case Done{_} Done{_}: Done{Unit{}}
    case Fail{error} Done{_}: Fail{ReaderFailure{error}}
    case Done{_} Fail{error}: Fail{BodyFailure{error}}
    case Fail{first} Fail{second}: Fail{BothFailures{first, second}}

def dispose(-State: Type, -Transport: Data, -E: Data, owner: Owner<State, Transport, E>) -> IO(Result<&2, &2, CloseError<Transport>, Unit>):
  match owner:
    case Owner{source, reader}:
      do IO<Result<&2, &2, CloseError<Transport>, Unit>>:
        first : Result<&2, &2, Reader.Error<Transport>, Unit> <- Reader.dispose(Transport, E, reader)
        second : Result<&2, &2, SSE.ReadError<Transport>, Unit> <- Source.dispose(State, SSE.ReadError<Transport>, source)
        return outcome(Transport, first, second)

type Processed<-Transport: Data, -G: Data, -E: Data> is Data:
  Processed{result: Stream.RunResult<G, E>, disposal: Result<&2, &2, CloseError<Transport>, Unit>}

def processBorrowed(-State: Type, -Transport: Data, -G: Data, -E: Data, -J: Data, output: Types.AssistantMessage<Value.Value, G>, sink: Callback.Callback<Types.AssistantMessageEvent<Value.Value, G>, Result<&2, &2, E, Unit>>, model: Types.Model<J>, options: Pricing.OpenAIResponsesStreamOptions<E>, pair: Owner<State, Transport, E> & Stream.Reader<E>) -> IO(Processed<Transport, G, E>):
  match pair:
    case (owner, reader):
      do IO<Processed<Transport, G, E>>:
        result : Stream.RunResult<G, E> <- Stream.processResponsesStream(G, E, J, reader, output, sink, model, options)
        cleanup : Result<&2, &2, CloseError<Transport>, Unit> <- dispose(State, Transport, E, owner)
        return Processed{result, cleanup}

# Own the entire processing lifetime. Keep the processor's partial output and
# primary result even if subsequent owner disposal fails. Sink/pricing/abort
# callbacks and the parent signal remain borrowed until this operation returns.
def process(-State: Type, -Transport: Data, -G: Data, -E: Data, -J: Data, owner: Owner<State, Transport, E>, output: Types.AssistantMessage<Value.Value, G>, sink: Callback.Callback<Types.AssistantMessageEvent<Value.Value, G>, Result<&2, &2, E, Unit>>, model: Types.Model<J>, options: Pricing.OpenAIResponsesStreamOptions<E>) -> IO(Processed<Transport, G, E>):
  processBorrowed(State, Transport, G, E, J, output, sink, model, options, borrow(State, Transport, E, owner))
