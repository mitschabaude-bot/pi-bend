import Base
import ./file-fold.bend as FileFold


# Retain at most the caller's byte budget. Overflow is sticky across chunks.
type State is Data:
  State{remaining: Nat, reversed: List<&2, U32>, overflow: Bool}

def consumed(bytes: List<&2, U32>, state: State) -> State:
  match bytes state:
    case Nil{} previous: previous
    case _ State{_, reversed, True{}}: State{0n, reversed, True{}}
    case _ <> _ State{0n, reversed, False{}}: State{0n, reversed, True{}}
    case byte <> rest State{1n+remaining, reversed, False{}}: consumed(rest, State{remaining, byte <> reversed, False{}})

type Error is Data:
  LimitExceeded{}

def create(limit: Nat) -> State:
  State{limit, Nil{}, False{}}

# An exceeded budget is an error, never a successful truncated body.
def finish(state: State) -> Result<&2, &2, Error, List<&2, U32>>:
  match state:
    case State{_, _, True{}}: Fail{LimitExceeded{}}
    case State{_, reversed, False{}}: Done{List.reverse(&2, U32, reversed)}


# Decode only a complete, bounded read after file ownership has been retired.
type FileError<-DecodeError: Data> is Data:
  File{error: FileFold.Error}
  TooLarge{}
  Decode{error: DecodeError}

def control(state: State) -> FileFold.Control<State>:
  match state:
    case State{remaining, reversed, False{}}: FileFold.Continue{State{remaining, reversed, False{}}}
    case State{remaining, reversed, True{}}: FileFold.Stop{State{remaining, reversed, True{}}}

def consume(state: State, bytes: List<&2, U32>) -> FileFold.Control<State>:
  control(consumed(bytes, state))

def decoded(-DecodeError: Data, result: Result<&2, &2, DecodeError, String>) -> Result<&2, &2, FileError<DecodeError>, String>:
  match result:
    case Fail{error}: Fail{Decode{error}}
    case Done{text}: Done{text}

def completed(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, outcome: FileFold.Outcome<State>) -> Result<&2, &2, FileError<DecodeError>, String>:
  match outcome:
    case FileFold.Outcome{_, Fail{error}}: Fail{File{error}}
    case FileFold.Outcome{State{_, _, True{}}, Done{_}}: Fail{TooLarge{}}
    case FileFold.Outcome{State{_, reversed, False{}}, Done{_}}: decoded(DecodeError, decode(List.reverse(&2, U32, reversed)))

# Source-byte limits include comments and newlines. An exact fit succeeds;
# overflow stops the fold and closes its file before any decoder is called.
def readWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, FileError<DecodeError>, String>):
  do IO<Result<&2, &2, FileError<DecodeError>, String>>:
    outcome : FileFold.Outcome<State> <- FileFold.read(~State, ~consume, path, chunkSize, State{byteLimit, Nil{}, False{}})
    return completed(~DecodeError, ~decode, outcome)
