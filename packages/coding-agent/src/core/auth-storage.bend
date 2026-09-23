import Base
import ../../../ai/src/auth/types.bend as Auth
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/utils/json.bend as Render
import ../../../ai/src/utils/schema-json.bend as SchemaJson
import ../../../runtime/src/json.bend as Json
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/serial-resource.bend as Serial
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/abort.bend as Abort
import ./resolve-config-value.bend as ConfigValue
import ../../../runtime/src/file-lock.bend as Lock
import ../../../runtime/src/random.bend as Random
import ../../../runtime/src/date.bend as Date

# CredentialStore implementation backed by auth.json. Provider auth
# orchestration belongs to the model runtime and pi-ai auth resolution.

def AuthStorageData() -> Data: R.Record<Auth.Credential>
def Outcome(-A: Data) -> Data: Result<&2, &2, String, A>

# auth.json shape
# ---------------

def textField(value: Maybe<&2, V.Value>) -> Result<&2, &2, Unit, Maybe<&2, String>>:
  match value:
    case None{}: Done{None{}}
    case Some{V.Text{value}}: Done{Some{value}}
    case Some{_}: Fail{Unit{}}

def stringField(fields: R.Record<V.Value>, +key: String) -> Result<&2, &2, Unit, Maybe<&2, String>>:
  textField(R.get(V.Value, fields, key))

def envEntries(entries: List<&2, R.Property<V.Value>>, reversed: List<&2, R.Property<String>>) -> Result<&2, &2, Unit, Ai.ProviderEnv()>:
  match entries:
    case Nil{}: Done{R.Record{List.reverse(&2, R.Property<String>, reversed)}}
    case R.Property{key, V.Text{value}} <> rest: envEntries(rest, R.Property{key, value} <> reversed)
    case _ <> _: Fail{Unit{}}

def envField(value: Maybe<&2, V.Value>) -> Result<&2, &2, Unit, Maybe<&2, Ai.ProviderEnv()>>:
  match value:
    case None{}: Done{None{}}
    case Some{V.ObjectValue{R.Record{entries}}}: Result.map(&2, &2, Unit, Ai.ProviderEnv(), Maybe<&2, Ai.ProviderEnv()>, env => Some{env}, envEntries(entries, Nil{}))
    case Some{_}: Fail{Unit{}}

def apiKeyCredential(key: Result<&2, &2, Unit, Maybe<&2, String>>, env: Result<&2, &2, Unit, Maybe<&2, Ai.ProviderEnv()>>) -> Result<&2, &2, Unit, Auth.Credential>:
  match key env:
    case Done{key} Done{env}: Done{Auth.ApiKeyCredential{key, env}}
    case _ _: Fail{Unit{}}

def finiteNumber(value: Maybe<&2, V.Value>) -> Result<&2, &2, Unit, F64>:
  match value:
    case Some{V.Number{+number}}: Bool.pick(Result<&2, &2, Unit, F64>, F.isFinite(F.decode(number)), Done{number}, Fail{Unit{}})
    case _: Fail{Unit{}}

def requiredString(value: Result<&2, &2, Unit, Maybe<&2, String>>) -> Result<&2, &2, Unit, String>:
  match value:
    case Done{Some{text}}: Done{text}
    case _: Fail{Unit{}}

def reserved(+key: String) -> Bool:
  String.eq(key, "type") || String.eq(key, "access") || String.eq(key, "refresh") || String.eq(key, "expires")

# Members beyond the canonical OAuth fields (such as accountId) round-trip untouched.
def extraFields(entries: List<&2, R.Property<V.Value>>, +reversed: List<&2, R.Property<V.Value>>) -> R.Record<V.Value>:
  match entries:
    case Nil{}: R.Record{List.reverse(&2, R.Property<V.Value>, reversed)}
    case R.Property{+key, value} <> rest: extraFields(rest, Bool.pick(List<&2, R.Property<V.Value>>, reserved(key), reversed, R.Property{key, value} <> reversed))

def oauthCredential(refresh: Result<&2, &2, Unit, String>, access: Result<&2, &2, Unit, String>, expires: Result<&2, &2, Unit, F64>, extra: R.Record<V.Value>) -> Result<&2, &2, Unit, Auth.Credential>:
  match refresh access expires:
    case Done{refresh} Done{access} Done{expires}: Done{Auth.OAuthCredential{refresh, access, expires, extra}}
    case _ _ _: Fail{Unit{}}

def apiKeyFields(+fields: R.Record<V.Value>) -> Result<&2, &2, Unit, Auth.Credential>:
  apiKeyCredential(stringField(fields, "key"), envField(R.get(V.Value, fields, "env")))

def oauthFields(+entries: List<&2, R.Property<V.Value>>) -> Result<&2, &2, Unit, Auth.Credential>:
  oauthCredential(requiredString(stringField(R.Record{entries}, "refresh")), requiredString(stringField(R.Record{entries}, "access")), finiteNumber(R.get(V.Value, R.Record{entries}, "expires")), extraFields(entries, Nil{}))

def typedCredential(kind: Maybe<&2, V.Value>, fields: R.Record<V.Value>) -> Result<&2, &2, Unit, Auth.Credential>:
  match kind fields:
    case Some{V.Text{"api_key"}} fields: apiKeyFields(fields)
    case Some{V.Text{"oauth"}} R.Record{entries}: oauthFields(entries)
    case _ _: Fail{Unit{}}

def credentialOf(value: V.Value) -> Result<&2, &2, Unit, Auth.Credential>:
  match value:
    case V.ObjectValue{+fields}: typedCredential(R.get(V.Value, fields, "type"), fields)
    case _: Fail{Unit{}}

def invalidCredential(providerId: String) -> String:
  "Invalid auth.json credential for provider \"" ++ providerId ++ "\""

def entryOutcome(providerId: String, credential: Result<&2, &2, Unit, Auth.Credential>, reversed: List<&2, R.Property<Auth.Credential>>) -> Outcome(List<&2, R.Property<Auth.Credential>>):
  match credential:
    case Fail{_}: Fail{invalidCredential(providerId)}
    case Done{credential}: Done{R.Property{providerId, credential} <> reversed}

def credentialEntries(entries: List<&2, R.Property<V.Value>>, reversed: Outcome(List<&2, R.Property<Auth.Credential>>)) -> Outcome(AuthStorageData()):
  match entries reversed:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{reversed}: Done{R.Record{List.reverse(&2, R.Property<Auth.Credential>, reversed)}}
    case R.Property{+providerId, value} <> rest Done{reversed}: credentialEntries(rest, entryOutcome(providerId, credentialOf(value), reversed))

def parsedData(value: Result<&2, &2, Json.ParseError, V.Value>) -> Outcome(AuthStorageData()):
  match value:
    case Fail{_}: Fail{"Failed to read auth.json: invalid JSON"}
    case Done{V.ObjectValue{R.Record{entries}}}: credentialEntries(entries, Done{Nil{}})
    case Done{_}: Fail{"Invalid auth.json: expected an object"}

def stripBom(text: String) -> String:
  match text:
    case SCon{'\u{FEFF}', rest}: rest
    case other: other

# Missing storage is an empty store; malformed storage is an error and is
# never overwritten.
def parseStorageData(content: Maybe<&2, String>) -> Outcome(AuthStorageData()):
  match content:
    case None{}: Done{R.new(Auth.Credential)}
    case Some{text}: parsedData(Json.parse(stripBom(text)))

def optionalText(key: String, value: Maybe<&2, String>, fields: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match value:
    case None{}: fields
    case Some{text}: R.Property{key, V.Text{text}} <> fields

def envProperties(entries: List<&2, R.Property<String>>) -> List<&2, R.Property<V.Value>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: R.Property{key, V.Text{value}} <> envProperties(rest)

def envValue(env: Ai.ProviderEnv()) -> V.Value:
  match env:
    case R.Record{entries}: V.ObjectValue{R.Record{envProperties(entries)}}

def optionalEnv(env: Maybe<&2, Ai.ProviderEnv()>, fields: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match env:
    case None{}: fields
    case Some{env}: R.Property{"env", envValue(env)} <> fields

def credentialValue(credential: Auth.Credential) -> V.Value:
  match credential:
    case Auth.ApiKeyCredential{key, env}: V.ObjectValue{R.Record{R.Property{"type", V.Text{"api_key"}} <> optionalText("key", key, optionalEnv(env, Nil{}))}}
    case Auth.OAuthCredential{refresh, access, expires, R.Record{extra}}: V.ObjectValue{R.Record{R.Property{"type", V.Text{"oauth"}} <> R.Property{"refresh", V.Text{refresh}} <> R.Property{"access", V.Text{access}} <> R.Property{"expires", V.Number{expires}} <> extra}}

def dataProperties(entries: List<&2, R.Property<Auth.Credential>>) -> List<&2, R.Property<V.Value>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, credential} <> rest: R.Property{key, credentialValue(credential)} <> dataProperties(rest)

def dataValue(data: AuthStorageData()) -> V.Value:
  match data:
    case R.Record{entries}: V.ObjectValue{R.Record{dataProperties(entries)}}

# JSON.stringify(data, null, 2); credentials never hold non-finite numbers.
def serialize(data: AuthStorageData()) -> String:
  Maybe.default(&2, String, Render.stringifyPretty(SchemaJson.toJson(dataValue(data))), "{}")

# Backends
# --------

# The file backend re-reads the file for every operation and writes the whole
# document; the memory backend keeps the serialized document. Transactions
# use a shared directory lease across processes and one serialized resource
# within each process.
type Backend is Data:
  FileBackend{path: String}
  MemoryBackend{content: Maybe<&2, String>}

type Snapshot is Data:
  Snapshot{backend: Backend, data: AuthStorageData()}

def decoded(result: Result<&2, &2, FS.Error, List<&2, U32>>) -> Outcome(Maybe<&2, String>):
  match result:
    case Fail{FS.System{2, _}}: Done{None{}}
    case Fail{_}: Fail{"Failed to read auth.json"}
    case Done{bytes}: Done{Some{Utf8.decodeBytes(bytes)}}

def readContent(backend: Backend) -> IO(Outcome(Maybe<&2, String>)):
  match backend:
    case MemoryBackend{content}: IO.pure(Outcome(Maybe<&2, String>), Done{content})
    case FileBackend{path}:
      do IO<Outcome(Maybe<&2, String>)>:
        bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
        return decoded(bytes)

def writeOutcome(result: Result<&2, &2, FS.Error, Unit>) -> Outcome(Unit):
  match result:
    case Done{Unit{}}: Done{Unit{}}
    case Fail{_}: Fail{"Failed to write auth.json"}

def writtenParent(path: String, content: String, parent: Result<&2, &2, FS.Error, Unit>) -> IO(Outcome(Unit)):
  match parent:
    case Fail{_}: IO.pure(Outcome(Unit), Fail{"Failed to create the auth.json directory"})
    case Done{Unit{}}:
      do IO<Outcome(Unit)>:
        result : Result<&2, &2, FS.Error, Unit> <- FS.writeFileMode(path, content, 384)
        return writeOutcome(result)

def dirname(+path: String) -> String: Path.join(path, "..")

# Created files are private (0600); existing files keep their mode.
def writeContentUnchecked(backend: Backend, +content: String) -> IO(Backend & Outcome(Unit)):
  match backend:
    case MemoryBackend{_}: IO.pure(Backend & Outcome(Unit), (MemoryBackend{Some{content}}, Done{Unit{}}))
    case FileBackend{+path}:
      do IO<Backend & Outcome(Unit)>:
        parent : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(dirname(path))
        result : Outcome(Unit) <- writtenParent(path, content, parent)
        return (FileBackend{path}, result)

def aborted(signal: Auth.Signal()) -> IO(Bool):
  match signal:
    case None{}: IO.pure(Bool, False{})
    case Some{signal}: Abort.aborted(Unit, signal)

def abortedError() -> String: "The operation was aborted"

# A transaction holds the lease across asynchronous credential refresh, then
# checks cancellation and ownership immediately before committing a write.
type Access is Data:
  Access{lease: Maybe<&2,Lock.Handle>, signal: Auth.Signal()}

def lockMessage(error: Lock.Error) -> String:
  match error:
    case Lock.Cancelled{}: abortedError()
    case Lock.Locked{_}: "Auth storage lock is already held"
    case Lock.Compromised{_,_}: "Auth storage lock was compromised"
    case Lock.System{operation,_,_,message}: "Auth storage " ++ operation ++ " failed: " ++ message
    case Lock.PathError{_}: "Invalid auth storage lock path"
    case Lock.InvalidOptions{}: "Invalid auth storage lock options"
    case Lock.CleanupFailed{cause,cleanup}: lockMessage(cause) ++ "; cleanup: " ++ lockMessage(cleanup)

def lockOutcome(result: Result<&2,&2,Lock.Error,Unit>) -> Outcome(Unit):
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{lockMessage(error)}

def checkLease(lease: Maybe<&2,Lock.Handle>) -> IO(Outcome(Unit)):
  match lease:
    case None{}: IO.pure(Outcome(Unit),Done{Unit{}})
    case Some{handle}:
      do IO<Outcome(Unit)>:
        checked : Result<&2,&2,Lock.Error,Unit> <- Lock.check(handle)
        return lockOutcome(checked)

def accessCheck(access: Access) -> IO(Outcome(Unit)):
  match access:
    case Access{+lease,signal}:
      do IO<Outcome(Unit)>:
        cancelled : Bool <- aborted(signal)
        Bool.pick(Unit -> IO(Outcome(Unit)),cancelled,_ => IO.pure(Outcome(Unit),Fail{abortedError()}),_ => checkLease(lease))(Unit{})

# Auth uses a 30-second lease/acquisition deadline and exponential jitter.
# Single-attempt leases keep that policy separate from settings' fixed retry.
def delayedAttempt(+path: String,+signal: Auth.Signal(),remaining: U32,base: U32,draw: Result<&2,&2,Random.Error,Nat>) -> IO(Result<&2,&1,Lock.Error,Lock.Owner>):
  match draw:
    case Fail{_}: IO.pure(Result<&2,&1,Lock.Error,Lock.Owner>,Fail{Lock.System{"random",path,5,"Unable to sample auth lock retry delay"}})
    case Done{offset}:
      do IO<Result<&2,&1,Lock.Error,Lock.Owner>>:
        Lock.delay(U32.min((base + U32.div((U32.from_nat(offset) + 1 : U32),2) : U32),remaining),signal)
        Lock.acquire(path,Lock.Options{30000,15000,1n,0,False{}},signal)

@unsafe def retryAuthLock(+path: String,+signal: Auth.Signal(),+deadline: F64,+base: U32,acquired: Result<&2,&1,Lock.Error,Lock.Owner>) -> IO(Result<&2,&1,String,Lock.Owner>):
  match acquired:
    case Done{owner}: IO.pure(Result<&2,&1,String,Lock.Owner>,Done{owner})
    case Fail{Lock.Locked{_}}:
      do IO<Result<&2,&1,String,Lock.Owner>>:
        +now : F64 <- Date.now()
        Bool.pick(Unit -> IO(Result<&2,&1,String,Lock.Owner>),F64.is_ge(now,deadline),_ => IO.pure(Result<&2,&1,String,Lock.Owner>,Fail{"Auth storage lock is already held"}),_ =>
          do IO<Result<&2,&1,String,Lock.Owner>>:
            random : Result<&2,&2,Random.Error,Nat> <- Random.randomIndex(U32.to_nat((base * 2 : U32)))
            next : Result<&2,&1,Lock.Error,Lock.Owner> <- delayedAttempt(path,signal,F64.to_u32(F.subtract(deadline,now)),base,random)
            retryAuthLock(path,signal,deadline,U32.min((base * 2 : U32),1000),next))(Unit{})
    case Fail{error}: IO.pure(Result<&2,&1,String,Lock.Owner>,Fail{lockMessage(error)})

def acquireAuthLock(+path: String,+signal: Auth.Signal(),+deadline: F64) -> IO(Result<&2,&1,String,Lock.Owner>):
  do IO<Result<&2,&1,String,Lock.Owner>>:
    acquired : Result<&2,&1,Lock.Error,Lock.Owner> <- Lock.acquire(path,Lock.Options{30000,15000,1n,0,False{}},signal)
    retryAuthLock(path,signal,deadline,10,acquired)

def finishedLock(~A: Data,pair: Snapshot & Outcome(A),released: Result<&2,&2,Lock.Error,Unit>) -> Snapshot & Outcome(A):
  match pair released:
    case pair Done{_}: pair
    case (snapshot,Done{_}) Fail{error}: (snapshot,Fail{lockMessage(error)})
    case (snapshot,Fail{error}) Fail{cleanup}: (snapshot,Fail{error ++ "; cleanup: " ++ lockMessage(cleanup)})

def checkedTransaction(~A: Data,snapshot: Snapshot,operation: Access -> Snapshot -> IO(Snapshot & Outcome(A)),access: Access,checked: Outcome(Unit)) -> IO(Snapshot & Outcome(A)):
  match checked:
    case Fail{error}: IO.pure(Snapshot & Outcome(A),(snapshot,Fail{error}))
    case Done{_}: operation(access,snapshot)

def finalChecked(~A: Data,pair: Snapshot & Outcome(A),checked: Outcome(Unit)) -> Snapshot & Outcome(A):
  match pair checked:
    case (snapshot,Done{_}) Fail{error}: (snapshot,Fail{error})
    case pair _: pair

def runAccess(~A: Data,snapshot: Snapshot,operation: Access -> Snapshot -> IO(Snapshot & Outcome(A)),+access: Access) -> IO(Snapshot & Outcome(A)):
  do IO<Snapshot & Outcome(A)>:
    checked : Outcome(Unit) <- accessCheck(access)
    result : Snapshot & Outcome(A) <- checkedTransaction(~A,snapshot,operation,access,checked)
    after : Outcome(Unit) <- accessCheck(access)
    return finalChecked(~A,result,after)

def runOwned(~A: Data,snapshot: Snapshot,signal: Auth.Signal(),operation: Access -> Snapshot -> IO(Snapshot & Outcome(A)),pair: Lock.Owner & Lock.Handle) -> IO(Snapshot & Outcome(A)):
  match pair:
    case (owner,handle):
      do IO<Snapshot & Outcome(A)>:
        result : Snapshot & Outcome(A) <- runAccess(~A,snapshot,operation,Access{Some{handle},signal})
        released : Result<&2,&2,Lock.Error,Unit> <- Lock.release(owner)
        return finishedLock(~A,result,released)

def acquiredLock(~A: Data,snapshot: Snapshot,signal: Auth.Signal(),operation: Access -> Snapshot -> IO(Snapshot & Outcome(A)),acquired: Result<&2,&1,String,Lock.Owner>) -> IO(Snapshot & Outcome(A)):
  match acquired:
    case Fail{error}: IO.pure(Snapshot & Outcome(A),(snapshot,Fail{error}))
    case Done{owner}: runOwned(~A,snapshot,signal,operation,Lock.borrow(owner))

def lockParent(~A: Data,path: String,snapshot: Snapshot,+signal: Auth.Signal(),operation: Access -> Snapshot -> IO(Snapshot & Outcome(A)),parent: Result<&2,&2,FS.Error,Unit>) -> IO(Snapshot & Outcome(A)):
  match parent:
    case Fail{_}: IO.pure(Snapshot & Outcome(A),(snapshot,Fail{"Failed to create the auth.json directory"}))
    case Done{_}:
      do IO<Snapshot & Outcome(A)>:
        now : F64 <- Date.now()
        acquired : Result<&2,&1,String,Lock.Owner> <- acquireAuthLock(path,signal,F.add(now,F.fromU32(30000)))
        acquiredLock(~A,snapshot,signal,operation,acquired)

def transaction(~A: Data,+snapshot: Snapshot,+signal: Auth.Signal(),operation: Access -> Snapshot -> IO(Snapshot & Outcome(A))) -> IO(Snapshot & Outcome(A)):
  match snapshot:
    case Snapshot{MemoryBackend{_},_}: runAccess(~A,snapshot,operation,Access{None{},signal})
    case Snapshot{FileBackend{+path},_}:
      do IO<Snapshot & Outcome(A)>:
        parent : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(dirname(path))
        lockParent(~A,path,snapshot,signal,operation,parent)

def checkedWrite(backend: Backend,content: String,checked: Outcome(Unit)) -> IO(Backend & Outcome(Unit)):
  match checked:
    case Fail{error}: IO.pure(Backend & Outcome(Unit),(backend,Fail{error}))
    case Done{_}: writeContentUnchecked(backend,content)

def writeContent(backend: Backend,content: String,access: Access) -> IO(Backend & Outcome(Unit)):
  do IO<Backend & Outcome(Unit)>:
    checked : Outcome(Unit) <- accessCheck(access)
    checkedWrite(backend,content,checked)

def loaded(content: Outcome(Maybe<&2, String>)) -> Outcome(AuthStorageData()):
  match content:
    case Fail{error}: Fail{error}
    case Done{content}: parseStorageData(content)

def loadData(backend: Backend) -> IO(Outcome(AuthStorageData())):
  do IO<Outcome(AuthStorageData())>:
    content : Outcome(Maybe<&2, String>) <- readContent(backend)
    return loaded(content)

# Storage
# -------

type AuthStorageOwner is Type:
  AuthStorageOwner{resource: Serial.Owner<Snapshot>, resolver: ConfigValue.Resolver}

type AuthStorage is Data:
  AuthStorage{state: Serial.Handle<Snapshot>, resolver: ConfigValue.Resolver}

def createWith(backend: Backend, data: AuthStorageData()) -> IO(AuthStorageOwner):
  do IO<AuthStorageOwner>:
    resource : Serial.Owner<Snapshot> <- Serial.create(Snapshot, Snapshot{backend, data})
    resolver : ConfigValue.Resolver <- ConfigValue.newResolver()
    return AuthStorageOwner{resource, resolver}

def initial(result: Outcome(AuthStorageData())) -> AuthStorageData():
  match result:
    case Done{data}: data
    case Fail{_}: R.new(Auth.Credential)

# File-backed storage; an unreadable file starts from an empty snapshot and
# surfaces its error on the first operation that needs the file.
def create(+path: String) -> IO(AuthStorageOwner):
  do IO<AuthStorageOwner>:
    result : Outcome(AuthStorageData()) <- loadData(FileBackend{path})
    createWith(FileBackend{path}, initial(result))

def inMemory(+data: AuthStorageData()) -> IO(AuthStorageOwner):
  createWith(MemoryBackend{Some{serialize(data)}}, data)

def borrowed(+resolver: ConfigValue.Resolver, pair: Serial.Owner<Snapshot> & Serial.Handle<Snapshot>) -> AuthStorageOwner & AuthStorage:
  match pair:
    case (resource, handle): (AuthStorageOwner{resource, resolver}, AuthStorage{handle, resolver})

def borrow(owner: AuthStorageOwner) -> AuthStorageOwner & AuthStorage:
  match owner:
    case AuthStorageOwner{resource, resolver}: borrowed(resolver, Serial.borrow(Snapshot, resource))

def dispose(owner: AuthStorageOwner) -> IO(Unit):
  match owner:
    case AuthStorageOwner{resource, resolver}:
      do IO<Unit>:
        snapshot : Snapshot <- Serial.retire(Snapshot, resource)
        ConfigValue.disposeResolver(resolver)

# Operations
# ----------


# Reads without a signal retain the last valid snapshot if reloading fails.
# Signalled reads propagate cancellation and reload errors, as upstream does.
def latest(snapshot: Snapshot, reloaded: Outcome(AuthStorageData())) -> Snapshot & Outcome(AuthStorageData()):
  match snapshot reloaded:
    case Snapshot{backend, _} Done{+data}: (Snapshot{backend, data}, Done{data})
    case snapshot Fail{error}: (snapshot,Fail{error})

def reload(access: Access,snapshot: Snapshot) -> IO(Snapshot & Outcome(AuthStorageData())):
  match snapshot:
    case Snapshot{+backend, data}:
      do IO<Snapshot & Outcome(AuthStorageData())>:
        reloaded : Outcome(AuthStorageData()) <- loadData(backend)
        return latest(Snapshot{backend, data}, reloaded)

def fallbackRead(signal: Auth.Signal(),pair: Snapshot & Outcome(AuthStorageData())) -> Snapshot & Outcome(AuthStorageData()):
  match signal pair:
    case None{} Tuple{Snapshot{backend,+data},Fail{_}}: (Snapshot{backend,data},Done{data})
    case _ pair: pair

def readTransaction(+signal: Auth.Signal(),snapshot: Snapshot) -> IO(Snapshot & Outcome(AuthStorageData())):
  do IO<Snapshot & Outcome(AuthStorageData())>:
    result : Snapshot & Outcome(AuthStorageData()) <- transaction(~AuthStorageData(),snapshot,signal,reload)
    return fallbackRead(signal,result)

def readUnlessAborted(signal: Auth.Signal(),cancelled: Bool, state: Serial.Handle<Snapshot>) -> IO(Outcome(AuthStorageData())):
  match cancelled:
    case True{}: IO.pure(Outcome(AuthStorageData()), Fail{abortedError()})
    case False{}: Serial.run(Snapshot, Outcome(AuthStorageData()), state, snapshot => readTransaction(signal,snapshot))

def readLatestData(storage: AuthStorage, +signal: Auth.Signal()) -> IO(Outcome(AuthStorageData())):
  match storage:
    case AuthStorage{state, _}:
      do IO<Outcome(AuthStorageData())>:
        cancelled : Bool <- aborted(signal)
        readUnlessAborted(signal,cancelled, state)

# Stored api-key values may be templates or commands; reads resolve them.
def resolvedKey(credential: Auth.Credential, key: Maybe<&2, String>) -> Auth.Credential:
  match credential:
    case Auth.ApiKeyCredential{_, env}: Auth.ApiKeyCredential{key, env}
    case other: other

def resolveCredential(resolver: ConfigValue.Resolver, credential: Auth.Credential) -> IO(Auth.Credential):
  match credential:
    case Auth.ApiKeyCredential{Some{key}, +env}:
      do IO<Auth.Credential>:
        resolved : Maybe<&2, String> <- ConfigValue.resolveConfigValue(resolver, key, env)
        return Auth.ApiKeyCredential{resolved, env}
    case other: IO.pure(Auth.Credential, other)

def readEntry(resolver: ConfigValue.Resolver, entry: Maybe<&2, Auth.Credential>) -> IO(Outcome(Maybe<&2, Auth.Credential>)):
  match entry:
    case None{}: IO.pure(Outcome(Maybe<&2, Auth.Credential>), Done{None{}})
    case Some{credential}:
      do IO<Outcome(Maybe<&2, Auth.Credential>)>:
        resolved : Auth.Credential <- resolveCredential(resolver, credential)
        return Done{Some{resolved}}

def readResolved(resolver: ConfigValue.Resolver, data: Outcome(AuthStorageData()), providerId: String) -> IO(Outcome(Maybe<&2, Auth.Credential>)):
  match data:
    case Fail{error}: IO.pure(Outcome(Maybe<&2, Auth.Credential>), Fail{error})
    case Done{data}: readEntry(resolver, R.get(Auth.Credential, data, providerId))

def read(storage: AuthStorage, providerId: String, signal: Auth.Signal()) -> IO(Outcome(Maybe<&2, Auth.Credential>)):
  match storage:
    case AuthStorage{state, +resolver}:
      do IO<Outcome(Maybe<&2, Auth.Credential>)>:
        data : Outcome(AuthStorageData()) <- readLatestData(AuthStorage{state, resolver}, signal)
        readResolved(resolver, data, providerId)

def infos(entries: List<&2, R.Property<Auth.Credential>>) -> List<&2, Auth.CredentialInfo>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{providerId, credential} <> rest: Auth.info(providerId, credential) <> infos(rest)

def listed(data: Outcome(AuthStorageData())) -> Outcome(List<&2, Auth.CredentialInfo>):
  match data:
    case Fail{error}: Fail{error}
    case Done{R.Record{entries}}: Done{infos(entries)}

# Metadata only: configured key commands never run while listing.
def list(storage: AuthStorage, signal: Auth.Signal()) -> IO(Outcome(List<&2, Auth.CredentialInfo>)):
  do IO<Outcome(List<&2, Auth.CredentialInfo>)>:
    data : Outcome(AuthStorageData()) <- readLatestData(storage, signal)
    return listed(data)

# Persist merged data and report the post-write credential.
def committed(current: AuthStorageData(), merged: AuthStorageData(), result: Outcome(Maybe<&2, Auth.Credential>), written: Backend & Outcome(Unit)) -> Snapshot & Outcome(Maybe<&2, Auth.Credential>):
  match written:
    case (backend, Done{Unit{}}): (Snapshot{backend, merged}, result)
    case (backend, Fail{error}): (Snapshot{backend, current}, Fail{error})

def applied(access: Access, backend: Backend, +providerId: String, +current: AuthStorageData(), next: Outcome(Maybe<&2, Auth.Credential>)) -> IO(Snapshot & Outcome(Maybe<&2, Auth.Credential>)):
  match next:
    case Fail{error}: IO.pure(Snapshot & Outcome(Maybe<&2, Auth.Credential>), (Snapshot{backend, current}, Fail{error}))
    case Done{None{}}: IO.pure(Snapshot & Outcome(Maybe<&2, Auth.Credential>), (Snapshot{backend, current}, Done{R.get(Auth.Credential, current, providerId)}))
    case Done{Some{+credential}}:
      +merged = R.set(Auth.Credential, current, providerId, credential)
      do IO<Snapshot & Outcome(Maybe<&2, Auth.Credential>)>:
        written : Backend & Outcome(Unit) <- writeContent(backend, serialize(merged), access)
        return committed(current, merged, Done{Some{credential}}, written)

def modifyLoaded(access: Access, +providerId: String, update: Auth.Modification(), snapshot: Snapshot, current: Outcome(AuthStorageData())) -> IO(Snapshot & Outcome(Maybe<&2, Auth.Credential>)):
  match snapshot current:
    case Snapshot{backend, data} Fail{error}: IO.pure(Snapshot & Outcome(Maybe<&2, Auth.Credential>), (Snapshot{backend, data}, Fail{error}))
    case Snapshot{backend, _} Done{+current}:
      do IO<Snapshot & Outcome(Maybe<&2, Auth.Credential>)>:
        next : Outcome(Maybe<&2, Auth.Credential>) <- C.call(Maybe<&2, Auth.Credential>, Outcome(Maybe<&2, Auth.Credential>), update, R.get(Auth.Credential, current, providerId))
        applied(access, backend, providerId, current, next)

def modifySnapshot(access: Access, providerId: String, update: Auth.Modification(), snapshot: Snapshot) -> IO(Snapshot & Outcome(Maybe<&2, Auth.Credential>)):
  match snapshot:
    case Snapshot{+backend, data}:
      do IO<Snapshot & Outcome(Maybe<&2, Auth.Credential>)>:
        current : Outcome(AuthStorageData()) <- loadData(backend)
        modifyLoaded(access, providerId, update, Snapshot{backend, data}, current)

def modifyUnlessAborted(signal: Auth.Signal(), cancelled: Bool, state: Serial.Handle<Snapshot>, providerId: String, update: Auth.Modification()) -> IO(Outcome(Maybe<&2, Auth.Credential>)):
  match cancelled:
    case True{}: IO.pure(Outcome(Maybe<&2, Auth.Credential>), Fail{abortedError()})
    case False{}: Serial.run(Snapshot, Outcome(Maybe<&2, Auth.Credential>), state, snapshot => transaction(~(Maybe<&2,Auth.Credential>),snapshot,signal,access => snapshot => modifySnapshot(access,providerId,update,snapshot)))

# The only write path: a serialized read-modify-write. The function sees the
# current credential; None leaves the entry unchanged and skips the write.
def modify(storage: AuthStorage, providerId: String, update: Auth.Modification(), +signal: Auth.Signal()) -> IO(Outcome(Maybe<&2, Auth.Credential>)):
  match storage:
    case AuthStorage{state, _}:
      do IO<Outcome(Maybe<&2, Auth.Credential>)>:
        cancelled : Bool <- aborted(signal)
        modifyUnlessAborted(signal,cancelled, state, providerId, update)

def deletedWrite(previous: AuthStorageData(), next: AuthStorageData(), written: Backend & Outcome(Unit)) -> Snapshot & Outcome(Unit):
  match written:
    case (backend, Done{Unit{}}): (Snapshot{backend, next}, Done{Unit{}})
    case (backend, Fail{error}): (Snapshot{backend, previous}, Fail{error})

def deleteLoaded(access: Access, +providerId: String, snapshot: Snapshot, current: Outcome(AuthStorageData())) -> IO(Snapshot & Outcome(Unit)):
  match snapshot current:
    case Snapshot{backend, data} Fail{error}: IO.pure(Snapshot & Outcome(Unit), (Snapshot{backend, data}, Fail{error}))
    case Snapshot{backend, data} Done{current}:
      +next = R.remove(Auth.Credential, current, providerId)
      do IO<Snapshot & Outcome(Unit)>:
        written : Backend & Outcome(Unit) <- writeContent(backend, serialize(next), access)
        return deletedWrite(data, next, written)

def deleteSnapshot(access: Access, providerId: String, snapshot: Snapshot) -> IO(Snapshot & Outcome(Unit)):
  match snapshot:
    case Snapshot{+backend, data}:
      do IO<Snapshot & Outcome(Unit)>:
        current : Outcome(AuthStorageData()) <- loadData(backend)
        deleteLoaded(access, providerId, Snapshot{backend, data}, current)

def deleteUnlessAborted(signal: Auth.Signal(), cancelled: Bool, state: Serial.Handle<Snapshot>, providerId: String) -> IO(Outcome(Unit)):
  match cancelled:
    case True{}: IO.pure(Outcome(Unit), Fail{abortedError()})
    case False{}: Serial.run(Snapshot, Outcome(Unit), state, snapshot => transaction(~Unit,snapshot,signal,access => snapshot => deleteSnapshot(access,providerId,snapshot)))

def delete(storage: AuthStorage, providerId: String, +signal: Auth.Signal()) -> IO(Outcome(Unit)):
  match storage:
    case AuthStorage{state, _}:
      do IO<Outcome(Unit)>:
        cancelled : Bool <- aborted(signal)
        deleteUnlessAborted(signal,cancelled, state, providerId)

# CredentialStore view
# --------------------

def readRequest(storage: AuthStorage, request: Auth.Request) -> IO(Outcome(Maybe<&2, Auth.Credential>)):
  match request:
    case Auth.Request{providerId, signal}: read(storage, providerId, signal)

def modifyRequest(storage: AuthStorage, request: Auth.Modify) -> IO(Outcome(Maybe<&2, Auth.Credential>)):
  match request:
    case Auth.Modify{providerId, update, signal}: modify(storage, providerId, update, signal)

def deleteRequest(storage: AuthStorage, request: Auth.Request) -> IO(Outcome(Unit)):
  match request:
    case Auth.Request{providerId, signal}: delete(storage, providerId, signal)

# The store borrows the storage; dispose the store before the storage owner.
def store(+storage: AuthStorage) -> IO(Auth.CredentialStore):
  do IO<Auth.CredentialStore>:
    reader : C.Callback<Auth.Request, Outcome(Maybe<&2, Auth.Credential>)> <- C.create(~AuthStorage, ~Auth.Request, ~(Outcome(Maybe<&2, Auth.Credential>)), ~readRequest, storage)
    lister : C.Callback<Auth.Signal(), Outcome(List<&2, Auth.CredentialInfo>)> <- C.create(~AuthStorage, ~(Auth.Signal()), ~(Outcome(List<&2, Auth.CredentialInfo>)), ~list, storage)
    modifier : C.Callback<Auth.Modify, Outcome(Maybe<&2, Auth.Credential>)> <- C.create(~AuthStorage, ~Auth.Modify, ~(Outcome(Maybe<&2, Auth.Credential>)), ~modifyRequest, storage)
    deleter : C.Callback<Auth.Request, Outcome(Unit)> <- C.create(~AuthStorage, ~Auth.Request, ~(Outcome(Unit)), ~deleteRequest, storage)
    return Auth.CredentialStore{reader, lister, modifier, deleter}

def storedOrNone(result: Outcome(AuthStorageData())) -> Maybe<&2, AuthStorageData()>:
  match result:
    case Done{data}: Some{data}
    case Fail{_}: None{}

# One-off read of a stored credential without a store or key resolution.
def readStoredCredential(providerId: String, path: String) -> IO(Maybe<&2, Auth.Credential>):
  do IO<Maybe<&2, Auth.Credential>>:
    result : Outcome(AuthStorageData()) <- loadData(FileBackend{path})
    return Maybe.bind(&2, AuthStorageData(), Auth.Credential, storedOrNone(result), data => R.get(Auth.Credential, data, providerId))
