import Base
import ./http-body-consume.bend as Consume
import ./http-body-buffer.bend as Buffer
import ./schema-value.bend as Value
import ./http-socket-exchange.bend as Exchange
import ./http-response.bend as Response
import ./http-response-stream.bend as Stream
import ./http-response-progress.bend as Progress
import ./http-body-source.bend as Source

def unpack(-Reason: Data, result: Exchange.Next<Reason>) -> Exchange.Exchange<Reason> & Result<&2, &2, Exchange.ReadError<Reason>, Maybe<&2, Stream.Event>>:
  match result:
    case Exchange.Next{exchange, result}: (exchange, result)

def read(-Reason: Data, exchange: Exchange.Exchange<Reason>) -> IO(Exchange.Exchange<Reason> & Result<&2, &2, Exchange.ReadError<Reason>, Maybe<&2, Stream.Event>>):
  do IO<Exchange.Exchange<Reason> & Result<&2, &2, Exchange.ReadError<Reason>, Maybe<&2, Stream.Event>>>:
    result : Exchange.Next<Reason> <- Exchange.next(Reason, exchange)
    return unpack(Reason, result)

def start(~Reason: Data, exchange: Exchange.Exchange<Reason>) -> IO(Result<&2, &1, Progress.Error<Exchange.ReadError<Reason>>, Response.Response<Exchange.Exchange<Reason>>>):
  Response.startWith(~(Exchange.ReadError<Reason>), ~(Exchange.Exchange<Reason>), ~(read(Reason)), ~(Exchange.close(Reason)), exchange)

def next(~Reason: Data, body: Response.Body<Exchange.Exchange<Reason>>) -> IO(Response.Next<Exchange.ReadError<Reason>, Exchange.Exchange<Reason>>):
  Response.nextWith(~(Exchange.ReadError<Reason>), ~(Exchange.Exchange<Reason>), ~(read(Reason)), ~(Exchange.close(Reason)), body)

def close(-Reason: Data, body: Response.Body<Exchange.Exchange<Reason>>) -> IO(Response.Next<Exchange.ReadError<Reason>, Exchange.Exchange<Reason>>):
  Response.closeWith(Exchange.ReadError<Reason>, Exchange.Exchange<Reason>, Exchange.close(Reason), body)

def source(~Reason: Data, ~E: Data, ~map: Progress.Error<Exchange.ReadError<Reason>> -> E, body: Response.Body<Exchange.Exchange<Reason>>) -> IO(Source.Owner<Exchange.Exchange<Reason>, E>):
  Source.create(~Exchange.ReadError<Reason>, ~Exchange.Exchange<Reason>, ~E, ~map, ~(read(Reason)), ~(Exchange.close(Reason)), body)

# Consume and retire the owned body under an explicit caller byte budget.
def bytes(~Reason: Data, limit: Nat, body: Response.Body<Exchange.Exchange<Reason>>) -> IO(Result<&2, &2, Buffer.Error<Exchange.ReadError<Reason>>, List<&2, U32>>):
  Consume.bytesWith(~(Exchange.ReadError<Reason>), ~(Exchange.Exchange<Reason>), ~(read(Reason)), ~(Exchange.close(Reason)), limit, body)

def text(~Reason: Data, limit: Nat, body: Response.Body<Exchange.Exchange<Reason>>) -> IO(Result<&2, &2, Consume.TextError<Exchange.ReadError<Reason>>, String>):
  Consume.textWith(~(Exchange.ReadError<Reason>), ~(Exchange.Exchange<Reason>), ~(read(Reason)), ~(Exchange.close(Reason)), limit, body)

def json(~Reason: Data, limit: Nat, body: Response.Body<Exchange.Exchange<Reason>>) -> IO(Result<&2, &2, Consume.JSONError<Exchange.ReadError<Reason>>, Value.Value>):
  Consume.jsonWith(~(Exchange.ReadError<Reason>), ~(Exchange.Exchange<Reason>), ~(read(Reason)), ~(Exchange.close(Reason)), limit, body)
