import Base
import ./callback.bend as C
import ./http-response-stream.bend as Stream
import ./http-head.bend as Head

# An acquired byte-source lease. The cursor owns its release obligation, while
# callback handles remain borrowed from their external owner. The source owner
# must grant this lease to only one cursor, and keep its callbacks alive until
# the cursor has closed. This interface does not itself interrupt blocked reads.
type ReleaseReason is Data:
  MessageComplete{rest: List<&2, U32>}
  CleanEOF{}
  ResetEOF{}
  DecodeFailure{}
  ReadFailure{}
  EarlyClose{}

type Release is Data:
  Release{reason: ReleaseReason, head: Maybe<&2, Head.ResponseHead>}

# A reset remains distinct from EOF and ordinary failure until HTTP framing
# decides whether it can terminate this response. Preserve its original error.
type ReadResult<-E: Data> is Data:
  Bytes{bytes: List<&2, U32>}
  End{}
  Failed{error: E}
  Reset{error: E}

type Source<-E: Data> is Data:
  Source{next: C.Callback<Unit, Result<&2, &2, E, Maybe<&2, List<&2, U32>>>>, release: C.Callback<Release, Result<&2, &2, E, Unit>>}
  TransportSource{next: C.Callback<Unit, ReadResult<E>>, release: C.Callback<Release, Result<&2, &2, E, Unit>>}

type PrimaryError<-E: Data> is Data:
  SourceError{error: E}
  DecodeError{error: Stream.ReadError}

type ReadError<-E: Data> is Data:
  PrimaryFailure{error: PrimaryError<E>}
  ReleaseFailure{error: E}
  FailureWithRelease{primary: PrimaryError<E>, release: E}

type Position<-E: Data> is Data:
  Live{reader: Stream.Reader, pending: List<&2, Stream.Event>, head: Maybe<&2, Head.ResponseHead>}
  Drained{pending: List<&2, Stream.Event>, outcome: Result<&2, &2, ReadError<E>, Unit>}
  Closed{}

type Cursor<-E: Data> is Type:
  Cursor{source: Source<E>, position: Position<E>}

type Next<-E: Data> is Type:
  Next{cursor: Cursor<E>, result: Result<&2, &2, ReadError<E>, Maybe<&2, Stream.Event>>}

type CloseResult<-E: Data> is Type:
  CloseResult{cursor: Cursor<E>, result: Result<&2, &2, ReadError<E>, Unit>}

type Decision<-E: Data> is Data:
  Available{position: Position<E>, result: Result<&2, &2, ReadError<E>, Maybe<&2, Stream.Event>>}
  Pull{reader: Stream.Reader, head: Maybe<&2, Head.ResponseHead>}
  ReleaseSource{request: Release, pending: List<&2, Stream.Event>, primary: Maybe<&2, PrimaryError<E>>}

def create(-E: Data, source: Source<E>, method: String, limits: Stream.Limits) -> Cursor<E>:
  Cursor{source, Live{Stream.new(method, limits), Nil{}, None{}}}

def ended(-E: Data, outcome: Result<&2, &2, ReadError<E>, Unit>) -> Decision<E>:
  match outcome:
    case Done{_}: Available{Closed{}, Done{None{}}}
    case Fail{error}: Available{Closed{}, Fail{error}}

def decide(-E: Data, position: Position<E>) -> Decision<E>:
  match position:
    case Live{reader, Nil{}, head}: Pull{reader, head}
    case Live{reader, first <> rest, head}: Available{Live{reader, rest, head}, Done{Some{first}}}
    case Drained{Nil{}, outcome}: ended(E, outcome)
    case Drained{first <> rest, outcome}: Available{Drained{rest, outcome}, Done{Some{first}}}
    case Closed{}: Available{Closed{}, Done{None{}}}

def finalHead(events: List<&2, Stream.Event>, previous: Maybe<&2, Head.ResponseHead>) -> Maybe<&2, Head.ResponseHead>:
  match events:
    case Nil{}: previous
    case Stream.FinalHead{head, _} <> rest: finalHead(rest, Some{head})
    case _ <> rest: finalHead(rest, previous)

def withoutCompletion(events: List<&2, Stream.Event>) -> List<&2, Stream.Event>:
  match events:
    case Nil{}: Nil{}
    case Stream.Completed{_} <> rest: withoutCompletion(rest)
    case head <> rest: head <> withoutCompletion(rest)

def completionReason(ending: Maybe<&2, ReleaseReason>, rest: List<&2, U32>) -> ReleaseReason:
  match ending:
    case Some{reason}: reason
    case None{}: MessageComplete{rest}

def decoded(-E: Data, result: Stream.ReadResult, previous: Maybe<&2, Head.ResponseHead>, ending: Maybe<&2, ReleaseReason>) -> Decision<E>:
  match result:
    case Stream.More{reader, +events}: decide(E, Live{reader, events, finalHead(events, previous)})
    case Stream.Complete{+events, rest}: ReleaseSource{Release{completionReason(ending, rest), finalHead(events, previous)}, events, None{}}
    case Stream.Failed{error, +events}: ReleaseSource{Release{DecodeFailure{}, finalHead(events, previous)}, events, Some{DecodeError{error}}}

def reset(-E: Data, allowed: Bool, reader: Stream.Reader, head: Maybe<&2, Head.ResponseHead>, error: E) -> Decision<E>:
  match allowed:
    case True{}: decoded(E, Stream.finish(reader), head, Some{ResetEOF{}})
    case False{}: ReleaseSource{Release{ReadFailure{}, head}, Nil{}, Some{SourceError{error}}}

def received(-E: Data, +reader: Stream.Reader, head: Maybe<&2, Head.ResponseHead>, result: ReadResult<E>) -> Decision<E>:
  match result:
    case Failed{error}: ReleaseSource{Release{ReadFailure{}, head}, Nil{}, Some{SourceError{error}}}
    case Reset{error}: reset(E, Stream.permitsResetEOF(reader), reader, head, error)
    case End{}: decoded(E, Stream.finish(reader), head, Some{CleanEOF{}})
    case Bytes{bytes}: decoded(E, Stream.read(reader, bytes), head, None{})

def outcome(-E: Data, primary: Maybe<&2, PrimaryError<E>>, released: Result<&2, &2, E, Unit>) -> Result<&2, &2, ReadError<E>, Unit>:
  match primary released:
    case None{} Done{_}: Done{Unit{}}
    case None{} Fail{error}: Fail{ReleaseFailure{error}}
    case Some{error} Done{_}: Fail{PrimaryFailure{error}}
    case Some{primary} Fail{error}: Fail{FailureWithRelease{primary, error}}

def settled(-E: Data, pending: List<&2, Stream.Event>, result: Result<&2, &2, ReadError<E>, Unit>) -> Decision<E>:
  match result:
    case Done{_}: decide(E, Drained{pending, Done{Unit{}}})
    case Fail{error}: decide(E, Drained{withoutCompletion(pending), Fail{error}})

def fromResult(-E: Data, result: Result<&2, &2, E, Maybe<&2, List<&2, U32>>>) -> ReadResult<E>:
  match result:
    case Fail{error}: Failed{error}
    case Done{None{}}: End{}
    case Done{Some{bytes}}: Bytes{bytes}

def readSource(-E: Data, source: Source<E>) -> IO(ReadResult<E>):
  match source:
    case Source{next, _}:
      do IO<ReadResult<E>>:
        result : Result<&2, &2, E, Maybe<&2, List<&2, U32>>> <- C.call(Unit, Result<&2, &2, E, Maybe<&2, List<&2, U32>>>, next, Unit{})
        return fromResult(E, result)
    case TransportSource{next, _}: C.call(Unit, ReadResult<E>, next, Unit{})

def releaseSource(-E: Data, source: Source<E>, request: Release) -> IO(Result<&2, &2, E, Unit>):
  match source:
    case Source{_, release}: C.call(Release, Result<&2, &2, E, Unit>, release, request)
    case TransportSource{_, release}: C.call(Release, Result<&2, &2, E, Unit>, release, request)

# The source controls progress; an empty byte chunk may require another read.
@unsafe def drive(-E: Data, +source: Source<E>, decision: Decision<E>) -> IO(Next<E>):
  match decision:
    case Available{position, result}: IO.pure(Next<E>, Next{Cursor{source, position}, result})
    case Pull{reader, head}:
      do IO<Next<E>>:
        result : ReadResult<E> <- readSource(E, source)
        drive(E, source, received(E, reader, head, result))
    case ReleaseSource{request, pending, primary}:
      do IO<Next<E>>:
        result : Result<&2, &2, E, Unit> <- releaseSource(E, source, request)
        drive(E, source, settled(E, pending, outcome(E, primary, result)))

def next(-E: Data, cursor: Cursor<E>) -> IO(Next<E>):
  match cursor:
    case Cursor{source, position}: drive(E, source, decide(E, position))

def closed(-E: Data, source: Source<E>, result: Result<&2, &2, E, Unit>) -> CloseResult<E>:
  CloseResult{Cursor{source, Closed{}}, outcome(E, None{}, result)}

# Release callbacks must relinquish the lease even when they report an error.
# A failed release is not retried against a potentially retired/reused resource.
def close(-E: Data, cursor: Cursor<E>) -> IO(CloseResult<E>):
  match cursor:
    case Cursor{+source, Live{_, _, head}}:
      do IO<CloseResult<E>>:
        result : Result<&2, &2, E, Unit> <- releaseSource(E, source, Release{EarlyClose{}, head})
        return closed(E, source, result)
    case Cursor{source, Drained{_, result}}: IO.pure(CloseResult<E>, CloseResult{Cursor{source, Closed{}}, result})
    case Cursor{source, Closed{}}: IO.pure(CloseResult<E>, CloseResult{Cursor{source, Closed{}}, Done{Unit{}}})
