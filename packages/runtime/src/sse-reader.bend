import Base
import ./callback.bend as Callback
import ./sse-stream.bend as Stream
import ./sse-decoder.bend as SSE

type Chunk is Data:
  Bytes{value: List<&2, U32>}
  Text{value: String}
  EmptyChunk{}

# One acquired input iterator. Callback handles are borrowed; the owner is
# responsible for retiring them after this cursor is no longer used.
type Source<-E: Data> is Data:
  Source{next: Callback.Callback<Unit, Result<&2, &2, E, Maybe<&2, Chunk>>>, close: Callback.Callback<Unit, Result<&2, &2, E, Unit>>}

type Position is Data:
  Fresh{}
  Reading{decoder: Stream.StreamDecoder, pending: List<&2, SSE.ServerSentEvent>}
  Drained{pending: List<&2, SSE.ServerSentEvent>}
  Closed{}

# The cursor is affine: advance/close returns its successor rather than
# sharing a mutable decoder or allowing two calls to race over one cursor.
type Cursor<-E: Data> is Type:
  Cursor{source: Source<E>, position: Position}

type Next<-E: Data> is Type:
  Next{cursor: Cursor<E>, result: Result<&2, &2, E, Maybe<&2, SSE.ServerSentEvent>>}

type CloseResult<-E: Data> is Type:
  CloseResult{cursor: Cursor<E>, result: Result<&2, &2, E, Unit>}

type Decision<-E: Data> is Data:
  Available{position: Position, result: Result<&2, &2, E, Maybe<&2, SSE.ServerSentEvent>>}
  ReadMore{decoder: Stream.StreamDecoder}

def create(-E: Data, source: Source<E>) -> Cursor<E>:
  Cursor{source, Fresh{}}

def decide(-E: Data, position: Position) -> Decision<E>:
  match position:
    case Fresh{}: ReadMore{Stream.create()}
    case Reading{decoder, Nil{}}: ReadMore{decoder}
    case Reading{decoder, head <> tail}: Available{Reading{decoder, tail}, Done{Some{head}}}
    case Drained{head <> tail}: Available{Drained{tail}, Done{Some{head}}}
    case _: Available{Closed{}, Done{None{}}}

def decoded(-E: Data, result: Stream.Decoded) -> Decision<E>:
  match result:
    case Stream.Decoded{decoder, events}: decide(E, Reading{decoder, events})

def received(-E: Data, decoder: Stream.StreamDecoder, result: Result<&2, &2, E, Maybe<&2, Chunk>>) -> Decision<E>:
  match result:
    case Fail{error}: Available{Closed{}, Fail{error}}
    case Done{None{}}: decide(E, Drained{Stream.finish(decoder)})
    case Done{Some{Bytes{bytes}}}: decoded(E, Stream.decode(decoder, bytes))
    case Done{Some{Text{text}}}: decoded(E, Stream.decodeText(decoder, text))
    case Done{Some{EmptyChunk{}}}: ReadMore{decoder}

def read(-E: Data, source: Source<E>) -> IO(Result<&2, &2, E, Maybe<&2, Chunk>>):
  match source:
    case Source{next, _}: Callback.call(Unit, Result<&2, &2, E, Maybe<&2, Chunk>>, next, Unit{})

# An external iterator determines when another event or EOF becomes available.
@unsafe def drive(-E: Data, +source: Source<E>, decision: Decision<E>) -> IO(Next<E>):
  match decision:
    case Available{position, result}: IO.pure(Next<E>, Next{Cursor{source, position}, result})
    case ReadMore{decoder}:
      do IO<Next<E>>:
        result : Result<&2, &2, E, Maybe<&2, Chunk>> <- read(E, source)
        drive(E, source, received(E, decoder, result))

def next(-E: Data, cursor: Cursor<E>) -> IO(Next<E>):
  match cursor:
    case Cursor{source, position}: drive(E, source, decide(E, position))

def closeSource(-E: Data, source: Source<E>) -> IO(Result<&2, &2, E, Unit>):
  match source:
    case Source{_, close}: Callback.call(Unit, Result<&2, &2, E, Unit>, close, Unit{})

# No underlying return on unopened, exhausted or failed iteration. An early
# close of an active input calls return once; its error is returned, and the
# successor cursor is closed even when return failed.
def close(-E: Data, cursor: Cursor<E>) -> IO(CloseResult<E>):
  match cursor:
    case Cursor{+source, Reading{_, _}}:
      do IO<CloseResult<E>>:
        result : Result<&2, &2, E, Unit> <- closeSource(E, source)
        return CloseResult{Cursor{source, Closed{}}, result}
    case Cursor{source, _}: IO.pure(CloseResult<E>, CloseResult{Cursor{source, Closed{}}, Done{Unit{}}})
