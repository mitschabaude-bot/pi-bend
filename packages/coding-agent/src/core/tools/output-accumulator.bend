import Base
import ./truncate.bend as Truncate
import ../../../../runtime/src/utf8.bend as Utf8
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/serial-resource.bend as Serial
import ../../../../runtime/src/deferred.bend as Deferred
import ../../../../runtime/src/callback.bend as Callback

# Output decoding is immutable. Only the spill file is affine; every operation
# returns ownership even when it fails, so callers can always close it.
type OutputAccumulatorOptions is Data:
  OutputAccumulatorOptions{maxLines: Maybe<&2,Nat>, maxBytes: Maybe<&2,Nat>, tempFilePrefix: Maybe<&2,String>}
type OutputSnapshot is Data:
  OutputSnapshot{content: String, truncation: Truncate.TruncationResult, fullOutputPath: Maybe<&2,String>}
type Error is Data:
  Finished{}
  Closed{}
  InvalidByte{value: U32}
  System{operation: String, code: U32, message: String}
  WriteAndClose{writeCode: U32, writeMessage: String, closeCode: U32, closeMessage: String}

type Limits is Data: Limits{lines: Nat, bytes: Nat, rolling: Nat, prefix: String, automaticSpill: Bool}
type Counts is Data: Counts{raw: Nat, decoded: Nat, completedLines: Nat, lastLineBytes: Nat, openLine: Bool}
type Tail is Data: Tail{reversed: String, bytes: Nat, lineBoundary: Bool}
type State is Data:
  State{limits: Limits, decoder: Utf8.Decoder, counts: Counts, tail: Tail, finished: Bool, closed: Bool, path: Maybe<&2,String>, failure: Maybe<&2,Error>}
type Storage is Type:
  Memory{chunks: List<&2,List<&2,U32>>}
  Spilling{file: File}
  Retired{}
type OutputAccumulator is Type: OutputAccumulator{state: State, storage: Storage}
type Outcome<-A: Data> is Type: Outcome{accumulator: OutputAccumulator, result: Result<&2,&2,Error,A>}

def defaults() -> OutputAccumulatorOptions: OutputAccumulatorOptions{None{},None{},None{}}
def createWithDecoder(options: OutputAccumulatorOptions, decoder: Utf8.Decoder, automaticSpill: Bool) -> OutputAccumulator:
  match options:
    case OutputAccumulatorOptions{lines,bytes,prefix}:
      +maximum = Maybe.default(&2,Nat,bytes,Truncate.DEFAULT_MAX_BYTES())
      OutputAccumulator{State{Limits{Maybe.default(&2,Nat,lines,Truncate.DEFAULT_MAX_LINES()),maximum,Nat.max(2n * maximum,1n),Maybe.default(&2,String,prefix,"pi-output"),automaticSpill},decoder,Counts{0n,0n,0n,0n,False{}},Tail{"",0n,True{}},False{},False{},None{},None{}},Memory{Nil{}}}

def create(options: OutputAccumulatorOptions) -> OutputAccumulator: createWithDecoder(options,Utf8.create(),True{})

# Use when bytes encode text already decoded by the caller. An initial U+FEFF
# is then text, not a new byte-order mark; replacement decoding is unchanged.
# Explicit spilling lets a caller use its original-byte threshold, then request
# snapshot(True) only when a successful/cancelled result needs a full file.
def createPreservingBom(options: OutputAccumulatorOptions, automaticSpill: Bool) -> OutputAccumulator:
  createWithDecoder(options,Utf8.Decoder{Utf8.Ready{},True{}},automaticSpill)

def totalLines(counts: Counts) -> Nat:
  match counts:
    case Counts{_,_,completed,_,open}: completed + Bool.pick(Nat,open,1n,0n)

def lastLineBytes(state: State) -> Nat:
  match state:
    case State{_,_,Counts{_,_,_,last,_},_,_,_,_,_}: last

def getLastLineBytes(accumulator: OutputAccumulator) -> OutputAccumulator & Nat:
  match accumulator:
    case OutputAccumulator{+state,storage}: (OutputAccumulator{state,storage},lastLineBytes(state))

def usedRaw(bytes: List<&2,U32>, count: Nat) -> Result<&2,&2,Error,Nat>:
  match bytes:
    case Nil{}: Done{count}
    case +byte <> rest: Bool.pick(Unit -> Result<&2,&2,Error,Nat>,U32.is_le(byte,255),_ => usedRaw(rest,1n + count),_ => Fail{InvalidByte{byte}})(Unit{})

def keepTail(text: String, +room: Nat, +kept: String, +bytes: Nat, +boundary: Bool) -> Tail:
  match text:
    case SNil{}: Tail{String.reverse(kept),bytes,boundary}
    case SCon{+char,+rest}:
      +width = Truncate.scalarWidth(Char.to_u32(char))
      Bool.pick(Unit -> Tail,Nat.is_le(width,room),_ => keepTail(rest,room - width,SCon{char,kept},width + bytes,boundary),
        _ => Tail{String.reverse(kept),bytes,Nat.is_eq(room,0n) && Char.is_eq(char,'\n')})(Unit{})

def trimmed(+rolling: Nat, tail: Tail) -> Tail:
  match tail:
    case Tail{+text,+bytes,+boundary}:
      Bool.pick(Unit -> Tail,Nat.is_gt(bytes,rolling * 2n),_ => keepTail(text,rolling,"",0n,boundary),_ => Tail{text,bytes,boundary})(Unit{})

def decodedText(text: String, counts: Counts, tail: Tail) -> Counts & Tail:
  match text counts tail:
    case SNil{} counts tail: (counts,tail)
    case SCon{+char,rest} Counts{raw,decoded,completed,last,open} Tail{reversed,bytes,boundary}:
      +width = Truncate.scalarWidth(Char.to_u32(char))
      +newline = Char.is_eq(char,'\n')
      decodedText(rest,Counts{raw,decoded + width,completed + Bool.pick(Nat,newline,1n,0n),Bool.pick(Nat,newline,0n,last + width),Bool.not(newline)},Tail{SCon{char,reversed},bytes + width,boundary})

def decodedState(limits: Limits, decoder: Utf8.Decoder, finished: Bool, closed: Bool, path: Maybe<&2,String>, failure: Maybe<&2,Error>, value: Counts & Tail) -> State:
  match limits value:
    case Limits{+lines,+bytes,+rolling,+prefix,automatic} Tuple{counts,tail}:
      State{Limits{lines,bytes,rolling,prefix,automatic},decoder,counts,trimmed(rolling,tail),finished,closed,path,failure}

def acceptDecoded(state: State, rawSize: Nat, decoded: Utf8.Decoded) -> State:
  match state decoded:
    case State{limits,_,Counts{raw,count,completed,last,open},tail,finished,closed,path,failure} Utf8.Decoded{decoder,text}:
      decodedState(limits,decoder,finished,closed,path,failure,decodedText(text,Counts{raw + rawSize,count,completed,last,open},tail))

def appendState(+bytes: List<&2,U32>, size: Nat, state: State) -> State:
  match state:
    case State{limits,+decoder,counts,tail,finished,closed,path,failure}:
      acceptDecoded(State{limits,decoder,counts,tail,finished,closed,path,failure},size,Utf8.decode(decoder,bytes))

def finishState(state: State) -> State:
  match state:
    case State{limits,+decoder,counts,tail,finished,closed,path,failure}:
      acceptDecoded(State{limits,decoder,counts,tail,True{},closed,path,failure},0n,Utf8.finish(decoder))

def exceeds(+bytes: Nat, lines: Nat, counts: Counts) -> Bool:
  match counts:
    case Counts{raw,decoded,completed,_,open}: Nat.is_gt(raw,bytes) || Nat.is_gt(decoded,bytes) || Nat.is_gt(completed + Bool.pick(Nat,open,1n,0n),lines)

def shouldUseTempFile(state: State) -> Bool:
  match state:
    case State{Limits{lines,+bytes,_,_,automatic},_,+counts,_,_,_,_,_}:
      automatic && exceeds(bytes,lines,counts)

def afterNewline(text: String, fallback: String) -> String:
  match text:
    case SNil{}: fallback
    case SCon{'\n',rest}: rest
    case SCon{_,rest}: afterNewline(rest,fallback)

def snapshotText(tail: Tail) -> String:
  match tail:
    case Tail{reversed,_,boundary}:
      +text = String.reverse(reversed)
      Bool.pick(String,boundary,text,afterNewline(text,text))

def snapshotResult(+counts: Counts, path: Maybe<&2,String>, result: Truncate.TruncationResult) -> OutputSnapshot:
  match counts result:
    case Counts{_,+decoded,+completed,_,+open} Truncate.TruncationResult{+content,_,cause,_,_,outLines,outBytes,partial,first,+maxLines,+maxBytes}:
      +lines = completed + Bool.pick(Nat,open,1n,0n)
      +truncated = Nat.is_gt(lines,maxLines) || Nat.is_gt(decoded,maxBytes)
      +by = {Bool.pick(Maybe<&2,Truncate.Limit>,truncated,Maybe.or(&2,Truncate.Limit,cause,Some{Bool.pick(Truncate.Limit,Nat.is_gt(decoded,maxBytes),Truncate.Bytes{},Truncate.Lines{})}),None{}) : Maybe<&2,Truncate.Limit>}
      OutputSnapshot{content,Truncate.TruncationResult{content,truncated,by,lines,decoded,outLines,outBytes,partial,first,maxLines,maxBytes},path}

def peek(state: State) -> OutputSnapshot:
  match state:
    case State{Limits{lines,bytes,_,_,_},_,counts,tail,_,_,path,_}:
      snapshotResult(counts,path,Truncate.truncateTail(snapshotText(tail),Truncate.TruncationOptions{Some{lines},Some{bytes}}))

def failed(state: State, cause: Error) -> State:
  match state:
    case State{limits,decoder,counts,tail,finished,closed,path,_}: State{limits,decoder,counts,tail,finished,closed,path,Some{cause}}

def named(state: State, path: String) -> State:
  match state:
    case State{limits,decoder,counts,tail,finished,closed,_,failure}: State{limits,decoder,counts,tail,finished,closed,Some{path},failure}

def retired(state: State) -> State:
  match state:
    case State{limits,decoder,counts,tail,finished,_,path,failure}: State{limits,decoder,counts,tail,finished,True{},path,failure}

def status(state: State) -> Result<&2,&2,Error,Unit>:
  match state:
    case State{_,_,_,_,_,_,_,None{}}: Done{Unit{}}
    case State{_,_,_,_,_,_,_,Some{cause}}: Fail{cause}

def appendable(state: State) -> Result<&2,&2,Error,Unit>:
  match state:
    case State{_,_,_,_,finished,closed,_,failure}:
      Bool.pick(Result<&2,&2,Error,Unit>,finished,Fail{Finished{}},Bool.pick(Result<&2,&2,Error,Unit>,closed,Fail{Closed{}},Maybe.default(&2,Result<&2,&2,Error,Unit>,Maybe.map(&2,Error,Result<&2,&2,Error,Unit>,cause => Fail{cause},failure),Done{Unit{}})))

def hexDigit(+value: U32) -> Char: Chr{Bool.pick(U32,U32.is_lt(value,10),(48 + value : U32),(87 + value : U32))}
def hex(bytes: List<&2,U32>, reversed: String) -> String:
  match bytes:
    case Nil{}: String.reverse(reversed)
    case +byte <> rest: hex(rest,SCon{hexDigit((byte % 16 : U32)),SCon{hexDigit((byte / 16 : U32)),reversed}})

def tempName(directory: String, prefix: String, bytes: Result<&1,&1,U32 & String,List<&2,U32>>) -> Result<&2,&2,Error,String>:
  match bytes:
    case Fail{(code,message)}: Fail{System{"entropy",code,message}}
    case Done{bytes}: Done{FS.child(directory,prefix ++ "-" ++ hex(bytes,"") ++ ".log")}

def environmentValue(value: Result<&1,&1,U32 & String,String>) -> Maybe<&2,String>:
  match value:
    case Done{""}: None{}
    case Done{value}: Some{value}
    case Fail{_}: None{}

def tempDirectory(names: List<&2,String>, previous: Maybe<&2,String>) -> IO(String):
  match names previous:
    case _ Some{value}: IO.pure(String,value)
    case Nil{} None{}: IO.pure(String,"/tmp")
    case name <> rest None{}:
      do IO<String>:
        value : Result<&1,&1,U32 & String,String> <- IO.get_env(name)
        tempDirectory(rest,environmentValue(value))

def newTempPath(prefix: String) -> IO(Result<&2,&2,Error,String>):
  do IO<Result<&2,&2,Error,String>>:
    directory : String <- tempDirectory("TMPDIR" <> "TMP" <> "TEMP" <> Nil{},None{})
    bytes : Result<&1,&1,U32 & String,List<&2,U32>> <- Entropy.bytes(8)
    return tempName(directory,prefix,bytes)

def written(state: State, result: File & Result<&1,&1,U32 & String,Unit>) -> Outcome<Unit>:
  match result:
    case Tuple{file,Done{Unit{}}}: Outcome{OutputAccumulator{state,Spilling{file}},Done{Unit{}}}
    case Tuple{file,Fail{(code,message)}}:
      +cause = {System{"write",code,message} : Error}
      Outcome{OutputAccumulator{failed(state,cause),Spilling{file}},Fail{cause}}

def writeChunks(chunks: List<&2,List<&2,U32>>, previous: Outcome<Unit>) -> IO(Outcome<Unit>):
  match chunks previous:
    case _ Outcome{accumulator,Fail{cause}}: IO.pure(Outcome<Unit>,Outcome{accumulator,Fail{cause}})
    case Nil{} outcome: IO.pure(Outcome<Unit>,outcome)
    case bytes <> rest Outcome{OutputAccumulator{state,Spilling{file}},Done{Unit{}}}:
      do IO<Outcome<Unit>>:
        result : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,bytes)
        writeChunks(rest,written(state,result))
    case _ Outcome{accumulator,_}: IO.pure(Outcome<Unit>,Outcome{accumulator,Fail{Closed{}}})

def opened(state: State, chunks: List<&2,List<&2,U32>>, path: String, result: Result<&1,&1,U32 & String,File>) -> IO(Outcome<Unit>):
  match result:
    case Fail{(code,message)}:
      +cause = {System{"open",code,message} : Error}
      IO.pure(Outcome<Unit>,Outcome{OutputAccumulator{failed(state,cause),Memory{chunks}},Fail{cause}})
    case Done{file}: writeChunks(List.reverse(&2,List<&2,U32>,chunks),Outcome{OutputAccumulator{named(state,path),Spilling{file}},Done{Unit{}}})

def openNamed(state: State, chunks: List<&2,List<&2,U32>>, path: Result<&2,&2,Error,String>) -> IO(Outcome<Unit>):
  match path:
    case Fail{+cause}: IO.pure(Outcome<Unit>,Outcome{OutputAccumulator{failed(state,cause),Memory{chunks}},Fail{cause}})
    case Done{+path}:
      do IO<Outcome<Unit>>:
        result : Result<&1,&1,U32 & String,File> <- File.open_mode(path,"wx",384)
        opened(state,chunks,path,result)

def prefixOf(state: State) -> String:
  match state:
    case State{Limits{_,_,_,prefix,_},_,_,_,_,_,_,_}: prefix

def ensureChecked(+state: State, storage: Storage, checked: Result<&2,&2,Error,Unit>) -> IO(Outcome<Unit>):
  match storage checked:
    case storage Fail{cause}: IO.pure(Outcome<Unit>,Outcome{OutputAccumulator{state,storage},Fail{cause}})
    case Memory{chunks} Done{Unit{}}:
      do IO<Outcome<Unit>>:
        name : Result<&2,&2,Error,String> <- newTempPath(prefixOf(state))
        openNamed(state,chunks,name)
    case storage Done{Unit{}}: IO.pure(Outcome<Unit>,Outcome{OutputAccumulator{state,storage},Done{Unit{}}})

def ensureTempFile(accumulator: OutputAccumulator) -> IO(Outcome<Unit>):
  match accumulator:
    case OutputAccumulator{+state,storage}: ensureChecked(state,storage,status(state))

def appendStorage(+bytes: List<&2,U32>, +state: State, storage: Storage) -> IO(Outcome<Unit>):
  match storage:
    case Memory{+chunks}:
      pending = {Memory{Bool.pick(List<&2,List<&2,U32>>,List.is_empty(&2,U32,bytes),chunks,bytes <> chunks)} : Storage}
      Bool.pick(Storage -> IO(Outcome<Unit>),shouldUseTempFile(state),storage => ensureTempFile(OutputAccumulator{state,storage}),storage => IO.pure(Outcome<Unit>,Outcome{OutputAccumulator{state,storage},Done{Unit{}}}))(pending)
    case Spilling{file}:
      do IO<Outcome<Unit>>:
        result : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,bytes)
        return written(state,result)
    case Retired{}: IO.pure(Outcome<Unit>,Outcome{OutputAccumulator{state,Retired{}},Fail{Closed{}}})

def appendValid(+bytes: List<&2,U32>, accumulator: OutputAccumulator, checked: Result<&2,&2,Error,Nat>) -> IO(Outcome<Unit>):
  match accumulator checked:
    case accumulator Fail{cause}: IO.pure(Outcome<Unit>,Outcome{accumulator,Fail{cause}})
    case OutputAccumulator{state,storage} Done{size}: appendStorage(bytes,appendState(bytes,size,state),storage)

def appendChecked(+bytes: List<&2,U32>, accumulator: OutputAccumulator, checked: Result<&2,&2,Error,Unit>) -> IO(Outcome<Unit>):
  match checked:
    case Fail{cause}: IO.pure(Outcome<Unit>,Outcome{accumulator,Fail{cause}})
    case Done{Unit{}}: appendValid(bytes,accumulator,usedRaw(bytes,0n))

def append(bytes: List<&2,U32>, accumulator: OutputAccumulator) -> IO(Outcome<Unit>):
  match accumulator:
    case OutputAccumulator{+state,storage}: appendChecked(bytes,OutputAccumulator{state,storage},appendable(state))

def finishReady(state: State, storage: Storage) -> IO(Outcome<Unit>):
  +done = finishState(state)
  Bool.pick(Storage -> IO(Outcome<Unit>),shouldUseTempFile(done),storage => ensureTempFile(OutputAccumulator{done,storage}),storage => IO.pure(Outcome<Unit>,Outcome{OutputAccumulator{done,storage},Done{Unit{}}}))(storage)

def finish(accumulator: OutputAccumulator) -> IO(Outcome<Unit>):
  match accumulator:
    case OutputAccumulator{State{+limits,+decoder,+counts,+tail,+finished,+closed,+path,+failure},storage}:
      +state = {State{limits,decoder,counts,tail,finished,closed,path,failure} : State}
      Bool.pick(Storage -> IO(Outcome<Unit>),finished,storage => IO.pure(Outcome<Unit>,Outcome{OutputAccumulator{state,storage},status(state)}),
        storage => Bool.pick(Storage -> IO(Outcome<Unit>),closed || Maybe.is_some(&2,Error,failure),storage => IO.pure(Outcome<Unit>,Outcome{OutputAccumulator{state,storage},appendable(state)}),storage => finishReady(state,storage))(storage))(storage)

def snapshotOutcome(outcome: Outcome<Unit>) -> Outcome<OutputSnapshot>:
  match outcome:
    case Outcome{accumulator,Fail{cause}}: Outcome{accumulator,Fail{cause}}
    case Outcome{OutputAccumulator{+state,storage},Done{Unit{}}}: Outcome{OutputAccumulator{state,storage},Done{peek(state)}}

def snapshotNeedsFile(snapshot: OutputSnapshot, persist: Bool) -> Bool:
  match snapshot:
    case OutputSnapshot{_,Truncate.TruncationResult{_,truncated,_,_,_,_,_,_,_,_,_},_}: persist && truncated

def snapshot(+persistIfTruncated: Bool, accumulator: OutputAccumulator) -> IO(Outcome<OutputSnapshot>):
  match accumulator:
    case OutputAccumulator{+state,storage}:
      Bool.pick(Storage -> IO(Outcome<OutputSnapshot>),snapshotNeedsFile(peek(state),persistIfTruncated),
        storage => do IO<Outcome<OutputSnapshot>>:
          result : Outcome<Unit> <- ensureTempFile(OutputAccumulator{state,storage})
          return snapshotOutcome(result),
        storage => IO.pure(Outcome<OutputSnapshot>,Outcome{OutputAccumulator{state,storage},Done{peek(state)}}))(storage)

def closeResult(previous: Maybe<&2,Error>, close: Result<&1,&1,U32 & String,Unit>) -> Result<&2,&2,Error,Unit>:
  match previous close:
    case _ Done{Unit{}}: Done{Unit{}}
    case Some{System{"write",wc,wm}} Fail{(cc,cm)}: Fail{WriteAndClose{wc,wm,cc,cm}}
    case _ Fail{(code,message)}: Fail{System{"close",code,message}}

def closeTempFile(accumulator: OutputAccumulator) -> IO(Outcome<Unit>):
  match accumulator:
    case OutputAccumulator{State{limits,decoder,counts,tail,finished,closed,path,+failure},Spilling{file}}:
      do IO<Outcome<Unit>>:
        result : Result<&1,&1,U32 & String,Unit> <- File.close_checked(file)
        return Outcome{OutputAccumulator{State{limits,decoder,counts,tail,finished,True{},path,failure},Retired{}},closeResult(failure,result)}
    case OutputAccumulator{state,_}: IO.pure(Outcome<Unit>,Outcome{OutputAccumulator{retired(state),Retired{}},Done{Unit{}}})

# A single publisher owns callback sequencing. Producers only change the
# accumulator and settle its current wake while holding the serial resource.
type StreamState is Type:
  StreamState{accumulator: OutputAccumulator, accepting: Bool, dirty: Bool, wake: Maybe<&2,Deferred.Deferred<Unit>>, timer: Maybe<&2,TimerCancel>}
type StreamHandle is Data: StreamHandle{resource: Serial.Handle<StreamState>}
type StreamOwner is Type: StreamOwner{resource: Serial.Owner<StreamState>, publisher: Maybe<&2,Chan(Unit)>}
type Publication is Data:
  Publication{view: Maybe<&2,OutputSnapshot>, nextWake: Maybe<&2,Deferred.Deferred<Unit>>}

def signalWake(wake: Maybe<&2,Deferred.Deferred<Unit>>) -> IO(Unit):
  match wake:
    case None{}: IO.pure(Unit,Unit{})
    case Some{signal}:
      do IO<Unit>:
        settled : Bool <- Deferred.resolve(Unit,signal,Unit{})
        return Unit{}

def cancelCooldown(timer: Maybe<&2,TimerCancel>) -> IO(Unit):
  match timer:
    case None{}: IO.pure(Unit,Unit{})
    case Some{cancel}:
      do IO<Unit>:
        cancelled : Bool <- Timer.cancel(cancel)
        return Unit{}

def rawCount(state: State) -> Nat:
  match state:
    case State{_,_,Counts{raw,_,_,_,_},_,_,_,_,_}: raw

def decodedCount(state: State) -> Nat:
  match state:
    case State{_,_,Counts{_,decoded,_,_,_},_,_,_,_,_}: decoded

def appendedStream(before: Nat, +dirty: Bool, +wake: Maybe<&2,Deferred.Deferred<Unit>>, timer: Maybe<&2,TimerCancel>, outcome: Outcome<Unit>) -> IO(StreamState & Result<&2,&2,Error,Unit>):
  match outcome:
    case Outcome{OutputAccumulator{+state,storage},result}:
      +changed = Nat.is_gt(rawCount(state),before)
      do IO<StreamState & Result<&2,&2,Error,Unit>>:
        signalWake(Bool.pick(Maybe<&2,Deferred.Deferred<Unit>>,changed,wake,None{}))
        return (StreamState{OutputAccumulator{state,storage},True{},dirty || changed,wake,timer},result)

def appendLocked(bytes: List<&2,U32>, stream: StreamState) -> IO(StreamState & Result<&2,&2,Error,Unit>):
  match stream:
    case StreamState{accumulator,False{},dirty,wake,timer}:
      IO.pure(StreamState & Result<&2,&2,Error,Unit>,(StreamState{accumulator,False{},dirty,wake,timer},Done{Unit{}}))
    case StreamState{OutputAccumulator{+state,storage},True{},dirty,wake,timer}:
      do IO<StreamState & Result<&2,&2,Error,Unit>>:
        outcome : Outcome<Unit> <- append(bytes,OutputAccumulator{state,storage})
        appendedStream(rawCount(state),dirty,wake,timer,outcome)

def appendStream(handle: StreamHandle, bytes: List<&2,U32>) -> IO(Result<&2,&2,Error,Unit>):
  match handle:
    case StreamHandle{resource}: Serial.run(StreamState,Result<&2,&2,Error,Unit>,resource,stream => appendLocked(bytes,stream))

def publication(accumulator: OutputAccumulator, accepting: Bool, dirty: Bool, +wake: Maybe<&2,Deferred.Deferred<Unit>>, timer: Maybe<&2,TimerCancel>) -> StreamState & Publication:
  match accumulator:
    case OutputAccumulator{+state,storage}:
      (StreamState{OutputAccumulator{state,storage},accepting,False{},wake,timer},Publication{Bool.pick(Maybe<&2,OutputSnapshot>,dirty,Some{peek(state)},None{}),wake})

# The worker has consumed the old observation. The lock prevents a producer
# from resolving an old wake after it is replaced and disposed.
def publishLocked(stream: StreamState) -> IO(StreamState & Publication):
  match stream:
    case StreamState{accumulator,+accepting,dirty,Some{old},timer}:
      do IO<StreamState & Publication>:
        Deferred.dispose(Unit,old)
        next : Maybe<&2,Deferred.Deferred<Unit>> <- Bool.pick(Unit -> IO(Maybe<&2,Deferred.Deferred<Unit>>),accepting,
          _ => do IO<Maybe<&2,Deferred.Deferred<Unit>>>:
            signal : Deferred.Deferred<Unit> <- Deferred.new(Unit)
            return Some{signal},_ => IO.pure(Maybe<&2,Deferred.Deferred<Unit>>,None{}))(Unit{})
        return publication(accumulator,accepting,dirty,next,timer)
    case stream: IO.pure(StreamState & Publication,(stream,Publication{None{},None{}}))

def timerStarted(accumulator: OutputAccumulator, accepting: Bool, dirty: Bool, wake: Maybe<&2,Deferred.Deferred<Unit>>, pair: Timer & TimerCancel) -> StreamState & Maybe<&1,Timer>:
  match pair:
    case (owner,cancel): (StreamState{accumulator,accepting,dirty,wake,Some{cancel}},Some{owner})

def cooldownLocked(+delay: Nat, stream: StreamState) -> IO(StreamState & Maybe<&1,Timer>):
  match stream:
    case StreamState{accumulator,True{},+dirty,+wake,timer}:
      Bool.pick(OutputAccumulator -> IO(StreamState & Maybe<&1,Timer>),Nat.is_gt(delay,0n),
        accumulator => do IO<StreamState & Maybe<&1,Timer>>:
          pair : Timer & TimerCancel <- Timer.new(U32.from_nat(delay))
          return timerStarted(accumulator,True{},dirty,wake,pair),
        accumulator => IO.pure(StreamState & Maybe<&1,Timer>,(StreamState{accumulator,True{},dirty,wake,timer},None{})))(accumulator)
    case stream: IO.pure(StreamState & Maybe<&1,Timer>,(stream,None{}))

def clearCooldown(stream: StreamState) -> IO(StreamState & Unit):
  match stream:
    case StreamState{accumulator,accepting,dirty,wake,_}: IO.pure(StreamState & Unit,(StreamState{accumulator,accepting,dirty,wake,None{}},Unit{}))

def closeCooldown(pair: Timer & Bool) -> IO(Unit):
  match pair:
    case (owner,_): Timer.close(owner)

def waitCooldown(resource: Serial.Handle<StreamState>, timer: Maybe<&1,Timer>) -> IO(Unit):
  match timer:
    case None{}: IO.pure(Unit,Unit{})
    case Some{owner}:
      do IO<Unit>:
        result : Timer & Bool <- Timer.wait(owner)
        closeCooldown(result)
        Serial.run(StreamState,Unit,resource,clearCooldown)

def sendPublication(+resource: Serial.Handle<StreamState>, observer: Callback.Callback<OutputSnapshot,Unit>, value: Maybe<&2,OutputSnapshot>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{view}:
      do IO<Unit>:
        start : Nat <- IO.now()
        Callback.call(OutputSnapshot,Unit,observer,view)
        now : Nat <- IO.now()
        timer : Maybe<&1,Timer> <- Serial.run(StreamState,Maybe<&1,Timer>,resource,stream => cooldownLocked(100n - (now - start),stream))
        waitCooldown(resource,timer)

def nextPublication(+resource: Serial.Handle<StreamState>, wake: Maybe<&2,Deferred.Deferred<Unit>>) -> IO(Maybe<&2,Publication>):
  match wake:
    case None{}: IO.pure(Maybe<&2,Publication>,None{})
    case Some{signal}:
      do IO<Maybe<&2,Publication>>:
        settled : Unit <- Deferred.result(Unit,signal)
        next : Publication <- Serial.run(StreamState,Publication,resource,publishLocked)
        return Some{next}

# Waiting is driven by external appends and finish. One callback may reenter
# appendStream because publication occurs after releasing the serial resource.
@unsafe def publisher(+resource: Serial.Handle<StreamState>, +observer: Callback.Callback<OutputSnapshot,Unit>, next: Maybe<&2,Publication>) -> IO(Unit):
  match next:
    case None{}: IO.pure(Unit,Unit{})
    case Some{Publication{view,wake}}:
      do IO<Unit>:
        sendPublication(resource,observer,view)
        next : Maybe<&2,Publication> <- nextPublication(resource,wake)
        publisher(resource,observer,next)

def startPublisher(observer: Callback.Callback<OutputSnapshot,Unit>, signal: Deferred.Deferred<Unit>, pair: Serial.Owner<StreamState> & Serial.Handle<StreamState>) -> IO(StreamOwner):
  match pair:
    case (owner,handle):
      do IO<StreamOwner>:
        done : Chan(Unit) <- IO.fork(Unit,publisher(handle,observer,Some{Publication{None{},Some{signal}}}))
        return StreamOwner{owner,Some{done}}

def createStream(options: OutputAccumulatorOptions, onSnapshot: Maybe<&2,Callback.Callback<OutputSnapshot,Unit>>) -> IO(StreamOwner):
  match onSnapshot:
    case None{}:
      do IO<StreamOwner>:
        owner : Serial.Owner<StreamState> <- Serial.create(StreamState,StreamState{create(options),True{},False{},None{},None{}})
        return StreamOwner{owner,None{}}
    case Some{observer}:
      do IO<StreamOwner>:
        +wake : Deferred.Deferred<Unit> <- Deferred.new(Unit)
        owner : Serial.Owner<StreamState> <- Serial.create(StreamState,StreamState{create(options),True{},False{},Some{wake},None{}})
        startPublisher(observer,wake,Serial.borrow(StreamState,owner))

def borrowedStream(worker: Maybe<&2,Chan(Unit)>, pair: Serial.Owner<StreamState> & Serial.Handle<StreamState>) -> StreamOwner & StreamHandle:
  match pair:
    case (owner,handle): (StreamOwner{owner,worker},StreamHandle{handle})

def borrowStream(owner: StreamOwner) -> StreamOwner & StreamHandle:
  match owner:
    case StreamOwner{resource,worker}: borrowedStream(worker,Serial.borrow(StreamState,resource))

def finishedStream(before: Nat, +dirty: Bool, +wake: Maybe<&2,Deferred.Deferred<Unit>>, +timer: Maybe<&2,TimerCancel>, outcome: Outcome<Unit>) -> IO(StreamState & Result<&2,&2,Error,Unit>):
  match outcome:
    case Outcome{OutputAccumulator{+state,storage},result}:
      do IO<StreamState & Result<&2,&2,Error,Unit>>:
        signalWake(wake)
        cancelCooldown(timer)
        return (StreamState{OutputAccumulator{state,storage},False{},dirty || Nat.is_gt(decodedCount(state),before),wake,timer},result)

def finishLocked(stream: StreamState) -> IO(StreamState & Result<&2,&2,Error,Unit>):
  match stream:
    case StreamState{OutputAccumulator{+state,storage},_,dirty,wake,timer}:
      do IO<StreamState & Result<&2,&2,Error,Unit>>:
        outcome : Outcome<Unit> <- finish(OutputAccumulator{state,storage})
        finishedStream(decodedCount(state),dirty,wake,timer,outcome)

def joinPublisher(done: Maybe<&2,Chan(Unit)>) -> IO(Unit):
  match done:
    case None{}: IO.pure(Unit,Unit{})
    case Some{channel}: IO.join(Unit,channel)

def streamResult(view: OutputSnapshot, last: Nat, previous: Result<&2,&2,Error,Unit>, closed: Outcome<Unit>) -> Result<&2,&1,Error,OutputSnapshot & Nat>:
  match previous closed:
    case _ Outcome{_,Fail{cause}}: Fail{cause}
    case Fail{cause} Outcome{_,Done{Unit{}}}: Fail{cause}
    case Done{Unit{}} Outcome{_,Done{Unit{}}}: Done{(view,last)}

def closeStream(previous: Result<&2,&2,Error,Unit>, stream: StreamState) -> IO(Result<&2,&1,Error,OutputSnapshot & Nat>):
  match stream:
    case StreamState{OutputAccumulator{+state,storage},_,_,_,_}:
      do IO<Result<&2,&1,Error,OutputSnapshot & Nat>>:
        closed : Outcome<Unit> <- closeTempFile(OutputAccumulator{state,storage})
        return streamResult(peek(state),lastLineBytes(state),previous,closed)

def finishBorrowed(done: Maybe<&2,Chan(Unit)>, pair: Serial.Owner<StreamState> & Serial.Handle<StreamState>) -> IO(Result<&2,&1,Error,OutputSnapshot & Nat>):
  match pair:
    case (owner,handle):
      do IO<Result<&2,&1,Error,OutputSnapshot & Nat>>:
        result : Result<&2,&2,Error,Unit> <- Serial.run(StreamState,Result<&2,&2,Error,Unit>,handle,finishLocked)
        joinPublisher(done)
        stream : StreamState <- Serial.retire(StreamState,owner)
        closeStream(result,stream)

# Stop external producers before finishing; borrowed handles expire on return.
# Reentrant callback appends during final publication see acceptance closed and
# are ignored. The observer remains caller-owned and may now be disposed safely.
def finishStream(owner: StreamOwner) -> IO(Result<&2,&1,Error,OutputSnapshot & Nat>):
  match owner:
    case StreamOwner{resource,done}: finishBorrowed(done,Serial.borrow(StreamState,resource))
