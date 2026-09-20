import Base
import ./file-fold.bend as FileFold
import ./bounded-bytes.bend as Bytes

# Decode only a complete, bounded read after file ownership has been retired.
type Error<-DecodeError: Data> is Data:
  File{error: FileFold.Error}
  TooLarge{}
  Decode{error: DecodeError}

def control(state: Bytes.State) -> FileFold.Control<Bytes.State>:
  match state:
    case Bytes.State{remaining, reversed, False{}}: FileFold.Continue{Bytes.State{remaining, reversed, False{}}}
    case Bytes.State{remaining, reversed, True{}}: FileFold.Stop{Bytes.State{remaining, reversed, True{}}}

def consume(state: Bytes.State, bytes: List<&2, U32>) -> FileFold.Control<Bytes.State>:
  control(Bytes.consumed(bytes, state))

def decoded(-DecodeError: Data, result: Result<&2, &2, DecodeError, String>) -> Result<&2, &2, Error<DecodeError>, String>:
  match result:
    case Fail{error}: Fail{Decode{error}}
    case Done{text}: Done{text}

def completed(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, outcome: FileFold.Outcome<Bytes.State>) -> Result<&2, &2, Error<DecodeError>, String>:
  match outcome:
    case FileFold.Outcome{_, Fail{error}}: Fail{File{error}}
    case FileFold.Outcome{Bytes.State{_, _, True{}}, Done{_}}: Fail{TooLarge{}}
    case FileFold.Outcome{Bytes.State{_, reversed, False{}}, Done{_}}: decoded(DecodeError, decode(List.reverse(&2, U32, reversed)))

# Source-byte limits include comments and newlines. An exact fit succeeds;
# overflow stops the fold and closes its file before any decoder is called.
def readWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, Error<DecodeError>, String>):
  do IO<Result<&2, &2, Error<DecodeError>, String>>:
    outcome : FileFold.Outcome<Bytes.State> <- FileFold.read(~Bytes.State, ~consume, path, chunkSize, Bytes.State{byteLimit, Nil{}, False{}})
    return completed(~DecodeError, ~decode, outcome)
