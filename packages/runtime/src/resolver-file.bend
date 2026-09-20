import Base
import ./file-fold.bend as FileFold
import ./resolver-config.bend as Config
import ./resolver-settings.bend as Settings

# Decoding policy is supplied explicitly. This layer never substitutes missing
# files, decodes a partial read, or applies an incomplete configuration.
type Error<-DecodeError: Data> is Data:
  File{error: FileFold.Error}
  TooLarge{}
  Decode{error: DecodeError}

type State is Data:
  State{remaining: Nat, reversed: List<&2, U32>, overflow: Bool}

def consumed(bytes: List<&2, U32>, state: State) -> State:
  match bytes state:
    case Nil{} previous: previous
    case _ State{_, reversed, True{}}: State{0n, reversed, True{}}
    case _ <> _ State{0n, reversed, False{}}: State{0n, reversed, True{}}
    case byte <> rest State{1n+remaining, reversed, False{}}: consumed(rest, State{remaining, byte <> reversed, False{}})

def control(state: State) -> FileFold.Control<State>:
  match state:
    case State{remaining, reversed, False{}}: FileFold.Continue{State{remaining, reversed, False{}}}
    case State{remaining, reversed, True{}}: FileFold.Stop{State{remaining, reversed, True{}}}

def consume(state: State, bytes: List<&2, U32>) -> FileFold.Control<State>:
  control(consumed(bytes, state))

def decoded(-DecodeError: Data, result: Result<&2, &2, DecodeError, String>) -> Result<&2, &2, Error<DecodeError>, List<&2, Config.Entry>>:
  match result:
    case Fail{error}: Fail{Decode{error}}
    case Done{text}: Done{Config.parse(text)}

def completed(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, outcome: FileFold.Outcome<State>) -> Result<&2, &2, Error<DecodeError>, List<&2, Config.Entry>>:
  match outcome:
    case FileFold.Outcome{_, Fail{error}}: Fail{File{error}}
    case FileFold.Outcome{State{_, _, True{}}, Done{_}}: Fail{TooLarge{}}
    case FileFold.Outcome{State{_, reversed, False{}}, Done{_}}: decoded(DecodeError, decode(List.reverse(&2, U32, reversed)))

# Limit counts source bytes, including comments and newlines. Exactly the limit
# is permitted; one extra byte stops reading and closes the file before decode.
def readWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, Error<DecodeError>, List<&2, Config.Entry>>):
  do IO<Result<&2, &2, Error<DecodeError>, List<&2, Config.Entry>>>:
    outcome : FileFold.Outcome<State> <- FileFold.read(~State, ~consume, path, chunkSize, State{byteLimit, Nil{}, False{}})
    return completed(~DecodeError, ~decode, outcome)

def configured(-DecodeError: Data, overrides: Settings.Overrides, result: Result<&2, &2, Error<DecodeError>, List<&2, Config.Entry>>) -> Result<&2, &2, Error<DecodeError>, Settings.Settings>:
  match result:
    case Fail{error}: Fail{error}
    case Done{entries}: Done{Settings.configure(entries, overrides)}

def loadWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat, overrides: Settings.Overrides) -> IO(Result<&2, &2, Error<DecodeError>, Settings.Settings>):
  do IO<Result<&2, &2, Error<DecodeError>, Settings.Settings>>:
    entries : Result<&2, &2, Error<DecodeError>, List<&2, Config.Entry>> <- readWith(~DecodeError, ~decode, path, chunkSize, byteLimit)
    return configured(DecodeError, overrides, entries)
