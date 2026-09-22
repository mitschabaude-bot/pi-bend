import Base

# Pure consumers retain their state on every return, including I/O failure.
# Stop permits bounded readers/parsers to finish without reading the whole file.
type Control<-State: Type> is Type:
  Continue{state: State}
  Stop{state: State}

type Completion is Data:
  EndOfFile{}
  Stopped{}

type Error is Data:
  InvalidReadSize{}
  Open{code: U32, message: String}
  Read{code: U32, message: String}
  Close{code: U32, message: String}
  ReadAndClose{readCode: U32, readMessage: String, closeCode: U32, closeMessage: String}

type Outcome<-State: Type> is Type:
  Outcome{state: State, result: Result<&2, &2, Error, Completion>}

def closed(result: Result<&2, &2, Error, Completion>, close: Result<&1, &1, U32 & String, Unit>) -> Result<&2, &2, Error, Completion>:
  match result close:
    case value Done{Unit{}}: value
    case Fail{Read{rc, rm}} Fail{(cc, cm)}: Fail{ReadAndClose{rc, rm, cc, cm}}
    case Fail{error} Fail{_}: Fail{error}
    case Done{_} Fail{(code, message)}: Fail{Close{code, message}}

def completed(-State: Type, state: State, result: Result<&2, &2, Error, Completion>, file: File) -> IO(Outcome<State>):
  do IO<Outcome<State>>:
    close : Result<&1, &1, U32 & String, Unit> <- File.close_checked(file)
    return Outcome{state, closed(result, close)}

type Progress<-State: Type> is Type:
  ReadMore{file: File, state: State}
  Finished{file: File, state: State, result: Result<&2, &2, Error, Completion>}

def consumed(-State: Type, file: File, control: Control<State>) -> Progress<State>:
  match control:
    case Continue{state}: ReadMore{file, state}
    case Stop{state}: Finished{file, state, Done{Stopped{}}}

# A zero-byte successful read is EOF. Short nonempty reads still reach the
# consumer and are followed by another read. The primitive owns error details.
def received(~State: Type, ~consume: State -> List<&2, U32> -> Control<State>, state: State, pair: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> Progress<State>:
  match pair:
    case Tuple{file, Fail{(code, message)}}: Finished{file, state, Fail{Read{code, message}}}
    case Tuple{file, Done{Nil{}}}: Finished{file, state, Done{EndOfFile{}}}
    case Tuple{file, Done{bytes}}: consumed(State, file, consume(state, bytes))

@unsafe def drive(~State: Type, ~consume: State -> List<&2, U32> -> Control<State>, +maximum: U32, progress: Progress<State>) -> IO(Outcome<State>):
  match progress:
    case Finished{file, state, result}: completed(State, state, result, file)
    case ReadMore{file, state}:
      do IO<Outcome<State>>:
        pair : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, maximum)
        drive(~State, ~consume, maximum, received(~State, ~consume, state, pair))

def opened(~State: Type, ~consume: State -> List<&2, U32> -> Control<State>, maximum: U32, state: State, result: Result<&1, &1, U32 & String, File>) -> IO(Outcome<State>):
  match result:
    case Fail{(code, message)}: IO.pure(Outcome<State>, Outcome{state, Fail{Open{code, message}}})
    case Done{file}: drive(~State, ~consume, maximum, ReadMore{file, state})

def checked(~State: Type, ~consume: State -> List<&2, U32> -> Control<State>, path: String, maximum: U32, state: State) -> IO(Outcome<State>):
  match maximum:
    case 0: IO.pure(Outcome<State>, Outcome{state, Fail{InvalidReadSize{}}})
    case size:
      do IO<Outcome<State>>:
        result : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
        opened(~State, ~consume, size, state, result)

def read(~State: Type, ~consume: State -> List<&2, U32> -> Control<State>, path: String, maximum: U32, state: State) -> IO(Outcome<State>):
  checked(~State, ~consume, path, maximum, state)
