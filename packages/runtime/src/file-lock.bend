import Base
import ./abort.bend as Abort
import ./deadline.bend as Deadline
import ./deferred.bend as Deferred
import ./serial-resource.bend as Serial
import ./filesystem.bend as FS
import ./posix-path.bend as Path
import ./date.bend as Date
import ./f64.bend as F
import ./u64.bend as W

# proper-lockfile's directory/mtime protocol. The affine owner must be released;
# borrowed handles may be used only while that owner remains alive.
type Options is Data:
  Options{staleMilliseconds: U32, updateMilliseconds: U32, attempts: Nat, retryMilliseconds: U32, realpath: Bool}
type Compromise is Data:
  Missing{}
  Modified{}
  UpdateFailed{code: U32, message: String}
type Error is Data:
  Locked{path: String}
  Cancelled{}
  InvalidOptions{}
  System{operation: String, path: String, code: U32, message: String}
  PathError{cause: FS.Error}
  Compromised{path: String, cause: Compromise}
  CleanupFailed{cause: Error, cleanup: Error}
type Precision is Data: Seconds{} Milliseconds{}
type Lease is Data:
  Lease{path: String, options: Options, modified: F64, lastUpdate: F64, precision: Precision, failure: Maybe<&2,Error>}
type Owner is Type:
  Owner{resource: Serial.Owner<Lease>, stop: Abort.AbortController<Unit>, worker: Chan(Unit)}
type Handle is Data:
  Handle{resource: Serial.Handle<Lease>}

def defaults() -> Options: Options{10000,5000,1n,20,True{}}
def valid(options: Options) -> Bool:
  match options:
    case Options{+stale,+update,count,_,_}: U32.is_ge(stale,2000) && U32.is_ge(update,1000) && U32.is_le(update,U32.div(stale,2)) && Nat.is_gt(count,0n)
def interval(options: Options) -> U32:
  match options:
    case Options{_,update,_,_,_}: update

def retryDelay(options: Options) -> U32:
  match options:
    case Options{_,_,_,milliseconds,_}: milliseconds

def system(-A: Data, operation: String, path: String, result: Result<&1,&1,U32 & String,A>) -> Result<&2,&2,Error,A>:
  match result:
    case Fail{(code,message)}: Fail{System{operation,path,code,message}}
    case Done{value}: Done{value}

def modifiedValue(value: U32 & U32 & U32) -> F64:
  match value:
    case (high,(low,nanos)):
      # Node's Stats.mtime is new Date(Math.round(seconds*1000+ns/1e6)).
      raw = F.add(F.multiply(Date.fromMilliseconds(W.U64{high,low}),F.fromU32(1000)),F.divide(F.fromU32(nanos),F.fromU32(1000000)))
      F64.floor(F.add(raw,F.divide(F.fromU32(1),F.fromU32(2))))
def modifiedResult(path: String, value: Result<&1,&1,U32 & String,U32 & U32 & U32>) -> Result<&2,&2,Error,F64>:
  match value:
    case Fail{(code,message)}: Fail{System{"stat",path,code,message}}
    case Done{value}: Done{modifiedValue(value)}
def modified(+path: String) -> IO(Result<&2,&2,Error,F64>):
  do IO<Result<&2,&2,Error,F64>>:
    value : Result<&1,&1,U32 & String,U32 & U32 & U32> <- File.modified_time(path)
    return modifiedResult(path,value)
def timeWords(+time: F64) -> W.U64:
  Bool.pick(W.U64,F64.is_lt(time,F.fromU32(0)),W.subtract(W.zero(),F.candidate(F.decode(F.negate(time)))),F.candidate(F.decode(time)))
def touchWords(+path: String, time: W.U64) -> IO(Result<&2,&2,Error,Unit>):
  match time:
    case W.U64{high,low}:
      do IO<Result<&2,&2,Error,Unit>>:
        value : Result<&1,&1,U32 & String,Unit> <- File.set_times_milliseconds(path,high,low)
        return system(Unit,"utimes",path,value)
def touch(path: String, time: F64) -> IO(Result<&2,&2,Error,Unit>): touchWords(path,timeWords(time))
def remove(+path: String) -> IO(Result<&2,&2,Error,Unit>):
  do IO<Result<&2,&2,Error,Unit>>:
    value : Result<&1,&1,U32 & String,Unit> <- Directory.remove(path)
    return system(Unit,"rmdir",path,value)
def missing(error: Error) -> Bool:
  match error:
    case System{_,_,2,_}: True{}
    case _: False{}
def removeMissing(result: Result<&2,&2,Error,Unit>) -> Result<&2,&2,Error,Unit>:
  match result:
    case Fail{System{_,_,2,_}}: Done{Unit{}}
    case other: other

def secondCeiling(time: F64) -> F64: F.multiply(F64.ceil(F.divide(time,F.fromU32(1000))),F.fromU32(1000))
def precisionTime(precision: Precision, time: F64) -> F64:
  match precision:
    case Seconds{}: secondCeiling(time)
    case Milliseconds{}: time

def probeResult(path: String, options: Options, now: F64, result: Result<&2,&2,Error,F64>) -> Result<&2,&2,Error,Lease>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{+time}: Done{Lease{path,options,time,now,Bool.pick(Precision,F64.is_eq(F.remainder(time,F.fromU32(1000)),F.fromU32(0)),Seconds{},Milliseconds{}),None{}}}
def probeTouched(+path: String, options: Options, result: Result<&2,&2,Error,Unit>) -> IO(Result<&2,&2,Error,Lease>):
  match result:
    case Fail{cause}: IO.pure(Result<&2,&2,Error,Lease>,Fail{cause})
    case Done{_}:
      do IO<Result<&2,&2,Error,Lease>>:
        time : Result<&2,&2,Error,F64> <- modified(path)
        now : F64 <- Date.now()
        return probeResult(path,options,now,time)
def cleanupError(cause: Error, cleanup: Result<&2,&2,Error,Unit>) -> Error:
  match cleanup:
    case Done{_}: cause
    case Fail{other}: CleanupFailed{cause,other}
def probeCleaned(+path: String, result: Result<&2,&2,Error,Lease>) -> IO(Result<&2,&2,Error,Lease>):
  match result:
    case Done{lease}: IO.pure(Result<&2,&2,Error,Lease>,Done{lease})
    case Fail{cause}:
      do IO<Result<&2,&2,Error,Lease>>:
        cleanup : Result<&2,&2,Error,Unit> <- remove(path)
        return Fail{cleanupError(cause,removeMissing(cleanup))}
def probe(+path: String, options: Options) -> IO(Result<&2,&2,Error,Lease>):
  do IO<Result<&2,&2,Error,Lease>>:
    now : F64 <- Date.now()
    touched : Result<&2,&2,Error,Unit> <- touch(path,F.add(secondCeiling(now),F.fromU32(5)))
    result : Result<&2,&2,Error,Lease> <- probeTouched(path,options,touched)
    probeCleaned(path,result)

def stale(time: F64, now: F64, options: Options) -> Bool:
  match options:
    case Options{timeout,_,_,_,_}: F64.is_lt(time,F.subtract(now,F.fromU32(timeout)))

# At most one stale removal per acquisition attempt, as in proper-lockfile.
def created(+path: String, options: Options, result: Result<&1,&1,U32 & String,Unit>) -> IO(Result<&2,&2,Error,Lease>):
  match result:
    case Done{_}: probe(path,options)
    case Fail{(17,_)}: IO.pure(Result<&2,&2,Error,Lease>,Fail{Locked{path}})
    case Fail{(code,message)}: IO.pure(Result<&2,&2,Error,Lease>,Fail{System{"mkdir",path,code,message}})
def createOnce(+path: String, options: Options) -> IO(Result<&2,&2,Error,Lease>):
  do IO<Result<&2,&2,Error,Lease>>:
    result : Result<&1,&1,U32 & String,Unit> <- Directory.create(path)
    created(path,options,result)
def removedStale(path: String, options: Options, result: Result<&2,&2,Error,Unit>) -> IO(Result<&2,&2,Error,Lease>):
  match result:
    case Fail{cause}: IO.pure(Result<&2,&2,Error,Lease>,Fail{cause})
    case Done{_}: createOnce(path,options)
def existing(+path: String, +options: Options, result: Result<&2,&2,Error,F64>) -> IO(Result<&2,&2,Error,Lease>):
  match result:
    case Fail{System{_,_,2,_}}: createOnce(path,options)
    case Fail{cause}: IO.pure(Result<&2,&2,Error,Lease>,Fail{cause})
    case Done{time}:
      do IO<Result<&2,&2,Error,Lease>>:
        now : F64 <- Date.now()
        Bool.pick(Unit -> IO(Result<&2,&2,Error,Lease>),stale(time,now,options),_ =>
          do IO<Result<&2,&2,Error,Lease>>:
            removed : Result<&2,&2,Error,Unit> <- remove(path)
            removedStale(path,options,removeMissing(removed)),
          _ => IO.pure(Result<&2,&2,Error,Lease>,Fail{Locked{path}}))(Unit{})
def attemptCreated(+path: String, options: Options, result: Result<&1,&1,U32 & String,Unit>) -> IO(Result<&2,&2,Error,Lease>):
  match result:
    case Fail{(17,_)}:
      do IO<Result<&2,&2,Error,Lease>>:
        time : Result<&2,&2,Error,F64> <- modified(path)
        existing(path,options,time)
    case other: created(path,options,other)
def attempt(+path: String, options: Options) -> IO(Result<&2,&2,Error,Lease>):
  do IO<Result<&2,&2,Error,Lease>>:
    result : Result<&1,&1,U32 & String,Unit> <- Directory.create(path)
    attemptCreated(path,options,result)

def cancelled(signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(Bool):
  match signal:
    case None{}: IO.pure(Bool,False{})
    case Some{signal}: Abort.aborted(Unit,signal)
def delayScope(pair: Deadline.Scope<Unit> & Abort.AbortSignal<Deadline.Cause<Unit>>) -> IO(Unit):
  match pair:
    case (scope,Abort.AbortSignal{settlement}):
      do IO<Unit>:
        elapsed : Abort.AbortReason<Deadline.Cause<Unit>> <- Deferred.result(Abort.AbortReason<Deadline.Cause<Unit>>,settlement)
        reason : Maybe<&2,Abort.AbortReason<Deadline.Cause<Unit>>> <- Deadline.close(Unit,scope)
        return Unit{}
def delay(milliseconds: U32, signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(Unit):
  match signal:
    case None{}: IO.sleep(milliseconds)
    case Some{signal}:
      do IO<Unit>:
        scope : Deadline.Scope<Unit> <- Deadline.create(Unit,milliseconds,signal)
        delayScope(Deadline.borrow(Unit,scope))

def setFailure(lease: Lease, cause: Error) -> Lease:
  match lease:
    case Lease{path,options,mtime,last,precision,_}: Lease{path,options,mtime,last,precision,Some{cause}}
def verifyResult(+lease: Lease, result: Result<&2,&2,Error,F64>) -> Lease & Result<&2,&2,Error,Unit>:
  match lease result:
    case Lease{_,_,_,_,_,Some{+cause}} _: (lease,Fail{cause})
    case Lease{+path,_,_,_,_,_} Fail{System{_,_,2,_}}:
      +cause = {Compromised{path,Missing{}} : Error}
      (setFailure(lease,cause),Fail{cause})
    case _ Fail{cause}: (lease,Fail{cause})
    case Lease{+path,_,time,_,_,_} Done{found}:
      +cause = {Compromised{path,Modified{}} : Error}
      Bool.pick(Lease & Result<&2,&2,Error,Unit>,F64.is_eq(time,found),(lease,Done{Unit{}}),(setFailure(lease,cause),Fail{cause}))
def verify(+lease: Lease) -> IO(Lease & Result<&2,&2,Error,Unit>):
  match lease:
    case Lease{_,_,_,_,_,Some{+cause}}: IO.pure(Lease & Result<&2,&2,Error,Unit>,(lease,Fail{cause}))
    case Lease{path,_,_,_,_,None{}}:
      do IO<Lease & Result<&2,&2,Error,Unit>>:
        result : Result<&2,&2,Error,F64> <- modified(path)
        return verifyResult(lease,result)
def check(handle: Handle) -> IO(Result<&2,&2,Error,Unit>):
  match handle:
    case Handle{resource}: Serial.run(Lease,Result<&2,&2,Error,Unit>,resource,lease => verify(lease))

def updateFailure(+lease: Lease, error: Error, now: F64) -> Lease & Maybe<&2,U32>:
  match lease error:
    case Lease{path,+options,_,last,_,_} System{_,_,+code,+message}:
      +cause = {Compromised{path,Bool.pick(Compromise,U32.is_eq(code,2),Missing{},UpdateFailed{code,message})} : Error}
      Bool.pick(Lease & Maybe<&2,U32>,U32.is_eq(code,2) || stale(last,now,options),(setFailure(lease,cause),None{}),(lease,Some{1000}))
    case _ +cause: (setFailure(lease,cause),None{})
def updated(+lease: Lease, time: F64, now: F64, result: Result<&2,&2,Error,Unit>) -> Lease & Maybe<&2,U32>:
  match lease result:
    case _ Fail{cause}: updateFailure(lease,cause,now)
    case Lease{path,+options,_,_,precision,_} Done{_}: (Lease{path,options,time,now,precision,None{}},Some{interval(options)})
def heartbeatRead(+lease: Lease, result: Result<&2,&2,Error,F64>) -> IO(Lease & Maybe<&2,U32>):
  match lease result:
    case Lease{_,_,_,_,_,Some{_}} _: IO.pure(Lease & Maybe<&2,U32>,(lease,None{}))
    case _ Fail{cause}:
      do IO<Lease & Maybe<&2,U32>>:
        now : F64 <- Date.now()
        return updateFailure(lease,cause,now)
    case Lease{+path,_,expected,_,precision,_} Done{found}:
      Bool.pick(Unit -> IO(Lease & Maybe<&2,U32>),F64.is_eq(expected,found),_ =>
        do IO<Lease & Maybe<&2,U32>>:
          now : F64 <- Date.now()
          +time : F64 <- IO.pure(F64,precisionTime(precision,now))
          result : Result<&2,&2,Error,Unit> <- touch(path,time)
          now : F64 <- Date.now()
          return updated(lease,time,now,result),
        _ => IO.pure(Lease & Maybe<&2,U32>,(setFailure(lease,Compromised{path,Modified{}}),None{})))(Unit{})
def heartbeat(+lease: Lease) -> IO(Lease & Maybe<&2,U32>):
  match lease:
    case Lease{path,_,_,_,_,_}:
      do IO<Lease & Maybe<&2,U32>>:
        result : Result<&2,&2,Error,F64> <- modified(path)
        heartbeatRead(lease,result)

# This is the only unbounded loop: the owner cancels its sleep and joins it.
@unsafe def worker(+resource: Serial.Handle<Lease>, +stop: Abort.AbortSignal<Unit>, next: Maybe<&2,U32>) -> IO(Unit):
  match next:
    case None{}: IO.pure(Unit,Unit{})
    case Some{milliseconds}:
      do IO<Unit>:
        delay(milliseconds,Some{stop})
        stopping : Bool <- Abort.aborted(Unit,stop)
        next : Maybe<&2,U32> <- Bool.pick(Unit -> IO(Maybe<&2,U32>),stopping,_ => IO.pure(Maybe<&2,U32>,None{}),_ => Serial.run(Lease,Maybe<&2,U32>,resource,lease => heartbeat(lease)))(Unit{})
        worker(resource,stop,next)

def startOwner(options: Options, +stop: Abort.AbortController<Unit>, pair: Serial.Owner<Lease> & Serial.Handle<Lease>) -> IO(Owner):
  match pair:
    case (owner,handle):
      do IO<Owner>:
        task : Chan(Unit) <- IO.fork(Unit,worker(handle,Abort.signal(Unit,stop),Some{interval(options)}))
        return Owner{owner,stop,task}
def own(+lease: Lease) -> IO(Owner):
  match lease:
    case Lease{_,options,_,_,_,_}:
      do IO<Owner>:
        stop : Abort.AbortController<Unit> <- Abort.new(Unit)
        owner : Serial.Owner<Lease> <- Serial.create(Lease,lease)
        startOwner(options,stop,Serial.borrow(Lease,owner))
def borrowed(stop: Abort.AbortController<Unit>, task: Chan(Unit), pair: Serial.Owner<Lease> & Serial.Handle<Lease>) -> Owner & Handle:
  match pair:
    case (owner,handle): (Owner{owner,stop,task},Handle{handle})
def borrow(owner: Owner) -> Owner & Handle:
  match owner:
    case Owner{resource,stop,task}: borrowed(stop,task,Serial.borrow(Lease,resource))
def releaseVerified(pair: Lease & Result<&2,&2,Error,Unit>) -> IO(Result<&2,&2,Error,Unit>):
  match pair:
    case (_,Fail{cause}): IO.pure(Result<&2,&2,Error,Unit>,Fail{cause})
    case (Lease{path,_,_,_,_,_},Done{_}): remove(path)
def releaseLease(lease: Lease) -> IO(Result<&2,&2,Error,Unit>):
  do IO<Result<&2,&2,Error,Unit>>:
    result : Lease & Result<&2,&2,Error,Unit> <- verify(lease)
    releaseVerified(result)
def release(owner: Owner) -> IO(Result<&2,&2,Error,Unit>):
  match owner:
    case Owner{resource,+stop,task}:
      do IO<Result<&2,&2,Error,Unit>>:
        stopped : Bool <- Abort.abort(Unit,stop,None{})
        IO.join(Unit,task)
        Abort.dispose(Unit,stop)
        lease : Lease <- Serial.retire(Lease,resource)
        releaseLease(lease)

def accepted(result: Result<&2,&2,Error,Lease>, wasCancelled: Bool) -> IO(Result<&2,&1,Error,Owner>):
  match result wasCancelled:
    case Fail{Locked{_}} True{}: IO.pure(Result<&2,&1,Error,Owner>,Fail{Cancelled{}})
    case Fail{cause} _: IO.pure(Result<&2,&1,Error,Owner>,Fail{cause})
    case Done{lease} True{}:
      do IO<Result<&2,&1,Error,Owner>>:
        cleanup : Result<&2,&2,Error,Unit> <- releaseLease(lease)
        return Fail{cleanupError(Cancelled{},cleanup)}
    case Done{lease} False{}:
      do IO<Result<&2,&1,Error,Owner>>:
        owner : Owner <- own(lease)
        return Done{owner}
def retryable(result: Result<&2,&2,Error,Lease>) -> Bool:
  match result:
    case Fail{Locked{_}}: True{}
    case _: False{}
def attempts(count: Nat, +path: String, +options: Options, +signal: Maybe<&2,Abort.AbortSignal<Unit>>, previous: Result<&2,&2,Error,Lease>) -> IO(Result<&2,&1,Error,Owner>):
  match count:
    case 0n:
      do IO<Result<&2,&1,Error,Owner>>:
        stopped : Bool <- cancelled(signal)
        accepted(previous,stopped)
    case 1n+(+count):
      do IO<Result<&2,&1,Error,Owner>>:
        stopped : Bool <- cancelled(signal)
        Bool.pick(Unit -> IO(Result<&2,&1,Error,Owner>),stopped,_ => accepted(previous,True{}),_ =>
          do IO<Result<&2,&1,Error,Owner>>:
            +result : Result<&2,&2,Error,Lease> <- attempt(path,options)
            +stopped : Bool <- cancelled(signal)
            Bool.pick(Unit -> IO(Result<&2,&1,Error,Owner>),retryable(result) && Nat.is_gt(count,0n) && Bool.not(stopped),_ =>
              do IO<Result<&2,&1,Error,Owner>>:
                delay(retryDelay(options),signal)
                attempts(count,path,options,signal,result),
              _ => accepted(result,stopped))(Unit{}))(Unit{})

def canonicalResolved(base: Result<&2,&2,FS.Error,String>, +path: String) -> Result<&2,&2,Error,String>:
  match base:
    case Fail{cause}: Fail{PathError{cause}}
    case Done{cwd}: Done{Maybe.default(&2,String,Path.resolve(cwd,path),path)}
def canonicalResult(value: Result<&2,&2,FS.Error,String>) -> Result<&2,&2,Error,String>:
  match value:
    case Fail{cause}: Fail{PathError{cause}}
    case Done{path}: Done{path}
def canonical(+path: String, realpath: Bool) -> IO(Result<&2,&2,Error,String>):
  match realpath:
    case True{}:
      do IO<Result<&2,&2,Error,String>>:
        result : Result<&2,&2,FS.Error,String> <- FS.realpath(path)
        return canonicalResult(result)
    case False{}:
      do IO<Result<&2,&2,Error,String>>:
        cwd : Result<&2,&2,FS.Error,String> <- FS.cwd()
        return canonicalResolved(cwd,path)
def acquireCanonical(+options: Options, signal: Maybe<&2,Abort.AbortSignal<Unit>>, result: Result<&2,&2,Error,String>) -> IO(Result<&2,&1,Error,Owner>):
  match options result:
    case _ Fail{cause}: IO.pure(Result<&2,&1,Error,Owner>,Fail{cause})
    case Options{_,_,count,_,_} Done{path}:
      +lockPath = path ++ ".lock"
      attempts(count,lockPath,options,signal,Fail{Locked{lockPath}})
def acquire(path: String, +options: Options, +signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(Result<&2,&1,Error,Owner>):
  match options:
    case Options{_,_,_,_,realpath}:
      Bool.pick(Unit -> IO(Result<&2,&1,Error,Owner>),valid(options),_ =>
        do IO<Result<&2,&1,Error,Owner>>:
          stopped : Bool <- cancelled(signal)
          resolved : Result<&2,&2,Error,String> <- Bool.pick(IO(Result<&2,&2,Error,String>),stopped,IO.pure(Result<&2,&2,Error,String>,Fail{Cancelled{}}),canonical(path,realpath))
          acquireCanonical(options,signal,resolved),
        _ => IO.pure(Result<&2,&1,Error,Owner>,Fail{InvalidOptions{}}))(Unit{})
