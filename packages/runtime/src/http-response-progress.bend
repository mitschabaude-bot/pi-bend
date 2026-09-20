import Base
import ./http-response-stream.bend as Stream
import ./http-response-metadata.bend as Metadata
import ./http-header.bend as Header

type PrimaryError<-E: Data> is Data:
  TransportFailure{error: E}
  MissingHead{}
  MissingCompletion{}
  UnexpectedEvent{event: Stream.Event}

type Error<-E: Data> is Data:
  PrimaryFailure{error: PrimaryError<E>}
  CleanupFailure{error: E}
  FailureWithCleanup{primary: PrimaryError<E>, cleanup: E}

type HeadDecision<-E: Data> is Data:
  SeekHead{}
  Ready{metadata: Metadata.Metadata}
  HeadFailure{error: PrimaryError<E>}

type BodyDecision<-E: Data> is Data:
  ReadMore{}
  Chunk{bytes: List<&2, U32>}
  Complete{trailers: List<&2, Header.Header>}
  BodyFailure{error: PrimaryError<E>}

def head(-E: Data, result: Result<&2, &2, E, Maybe<&2, Stream.Event>>) -> HeadDecision<E>:
  match result:
    case Fail{error}: HeadFailure{TransportFailure{error}}
    case Done{None{}}: HeadFailure{MissingHead{}}
    case Done{Some{Stream.InformationalHead{_}}}: SeekHead{}
    case Done{Some{Stream.FinalHead{value, expose}}}: Ready{Metadata.fromHead(value, expose)}
    case Done{Some{event}}: HeadFailure{UnexpectedEvent{event}}

def body(-E: Data, expose: Bool, result: Result<&2, &2, E, Maybe<&2, Stream.Event>>) -> BodyDecision<E>:
  match expose result:
    case _ Fail{error}: BodyFailure{TransportFailure{error}}
    case _ Done{None{}}: BodyFailure{MissingCompletion{}}
    case True{} Done{Some{Stream.BodyData{first <> rest}}}: Chunk{first <> rest}
    case _ Done{Some{Stream.BodyData{_}}}: ReadMore{}
    case _ Done{Some{Stream.Completed{fields}}}: Complete{fields}
    case _ Done{Some{event}}: BodyFailure{UnexpectedEvent{event}}

# Cleanup always runs, and cannot overwrite the original read/protocol error.
def outcome(-E: Data, primary: Maybe<&2, PrimaryError<E>>, cleanup: Result<&2, &2, E, Unit>) -> Result<&2, &2, Error<E>, Unit>:
  match primary cleanup:
    case None{} Done{_}: Done{Unit{}}
    case Some{error} Done{_}: Fail{PrimaryFailure{error}}
    case None{} Fail{error}: Fail{CleanupFailure{error}}
    case Some{error} Fail{cleanup}: Fail{FailureWithCleanup{error, cleanup}}
