import Base
import ../packages/coding-agent/src/core/auth-storage.bend as Storage
import ../packages/coding-agent/src/core/runtime-credentials.bend as Runtime
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/filesystem.bend as FS

# Fixture for auth-storage and runtime-credentials. Every command opens the
# storage at <path> ("memory:<json>" for in-memory storage), performs one
# operation and prints a JSON result line:
#   read <path> <provider>            credential or null
#   list <path>                       [{providerId,type}]
#   modify <path> <provider> <json>   post-write credential ("unchanged" leaves it)
#   delete <path> <provider>          "ok"
#   runtime <path> <script>           RuntimeCredentials overlay script (see below)
# Errors print as {"error": message}.

def line(value: V.Value) -> String:
  Maybe.default(&2, String, Render.stringify(SchemaJson.toJson(value)), "null")

def credentialValue(credential: Maybe<&2, Auth.Credential>) -> V.Value:
  match credential:
    case None{}: V.Null{}
    case Some{value}: Storage.credentialValue(value)

def errorValue(message: String) -> V.Value:
  V.ObjectValue{R.Record{[R.Property{"error", V.Text{message}}]}}

def outcome(-A: Data, render: A -> V.Value, result: Result<&2, &2, String, A>) -> String:
  match result:
    case Fail{message}: line(errorValue(message))
    case Done{value}: line(render(value))

def infoValue(info: Auth.CredentialInfo) -> V.Value:
  match info:
    case Auth.CredentialInfo{providerId, kind}: V.ObjectValue{R.Record{[R.Property{"providerId", V.Text{providerId}}, R.Property{"type", V.Text{Auth.typeName(kind)}}]}}

def infoList(infos: List<&2, Auth.CredentialInfo>) -> List<&2, V.Value>:
  match infos:
    case Nil{}: Nil{}
    case info <> rest: infoValue(info) <> infoList(rest)

def infoValues(infos: List<&2, Auth.CredentialInfo>) -> V.Value:
  V.ArrayValue{infoList(infos)}

def unitValue(value: Unit) -> V.Value: V.Text{"ok"}

# Storage selection: a file path, or memory:<json> for an in-memory store.
def parsedMemory(result: Result<&2, &2, String, R.Record<Auth.Credential>>) -> IO(Storage.AuthStorageOwner):
  match result:
    case Fail{message}: IO.die(Storage.AuthStorageOwner, 2, "memory storage: " ++ message)
    case Done{data}: Storage.inMemory(data)

def open(location: String) -> IO(Storage.AuthStorageOwner):
  match location:
    case SCon{'m', SCon{'e', SCon{'m', SCon{'o', SCon{'r', SCon{'y', SCon{':', json}}}}}}}: parsedMemory(Storage.parseStorageData(Some{json}))
    case path: Storage.create(path)

# The modification callback returns the parsed credential, or None for "unchanged".
def update(next: Maybe<&2, Auth.Credential>, current: Maybe<&2, Auth.Credential>) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{next})

def parsedCredential(json: String) -> Result<&2, &2, String, Maybe<&2, Auth.Credential>>:
  match json:
    case "unchanged": Done{None{}}
    case text: Result.map(&2, &2, String, R.Record<Auth.Credential>, Maybe<&2, Auth.Credential>, data => R.get(Auth.Credential, data, "value"), Storage.parseStorageData(Some{"{\"value\":" ++ text ++ "}"}))

def modifyWith(storage: Storage.AuthStorage, providerId: String, parsed: Result<&2, &2, String, Maybe<&2, Auth.Credential>>) -> IO(String):
  match parsed:
    case Fail{message}: IO.pure(String, line(errorValue("fixture: " ++ message)))
    case Done{next}:
      do IO<String>:
        +callback : Auth.Modification() <- C.create(~Maybe<&2, Auth.Credential>, ~Maybe<&2, Auth.Credential>, ~(Auth.StoreResult(Maybe<&2, Auth.Credential>)), ~update, next)
        result : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Storage.modify(storage, providerId, callback, None{})
        C.dispose(Maybe<&2, Auth.Credential>, Auth.StoreResult(Maybe<&2, Auth.Credential>), callback)
        return outcome(Maybe<&2, Auth.Credential>, credentialValue, result)

# Runtime overlay script: a comma-separated list of steps
#   set:<provider>=<key> | remove:<provider> | read:<provider> | list | delete:<provider> | has:<provider>
def steps(text: String, reversed: String, done: List<&2, String>) -> List<&2, String>:
  match text:
    case SNil{}: List.reverse(&2, String, String.reverse(reversed) <> done)
    case SCon{',', rest}: steps(rest, "", String.reverse(reversed) <> done)
    case SCon{c, rest}: steps(rest, SCon{c, reversed}, done)

def keyValue(text: String, reversed: String) -> String & String:
  match text:
    case SNil{}: (String.reverse(reversed), "")
    case SCon{'=', rest}: (String.reverse(reversed), rest)
    case SCon{c, rest}: keyValue(rest, SCon{c, reversed})

def runtimeSet(credentials: Runtime.RuntimeCredentials, pair: String & String) -> IO(String):
  match pair:
    case Tuple{providerId, key}:
      do IO<String>:
        Runtime.setRuntimeApiKey(credentials, providerId, key)
        return line(V.Text{"ok"})

def runtimeStep(credentials: Runtime.RuntimeCredentials, step: String) -> IO(String):
  match step:
    case SCon{'s', SCon{'e', SCon{'t', SCon{':', rest}}}}: runtimeSet(credentials, keyValue(rest, ""))
    case SCon{'r', SCon{'e', SCon{'m', SCon{'o', SCon{'v', SCon{'e', SCon{':', providerId}}}}}}}:
      do IO<String>:
        Runtime.removeRuntimeApiKey(credentials, providerId)
        return line(V.Text{"ok"})
    case SCon{'r', SCon{'e', SCon{'a', SCon{'d', SCon{':', providerId}}}}}:
      do IO<String>:
        result : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Runtime.read(credentials, providerId, None{})
        return outcome(Maybe<&2, Auth.Credential>, credentialValue, result)
    case SCon{'h', SCon{'a', SCon{'s', SCon{':', providerId}}}}:
      do IO<String>:
        present : Bool <- Runtime.hasRuntimeApiKey(credentials, providerId)
        return Bool.pick(String, present, "true", "false")
    case SCon{'d', SCon{'e', SCon{'l', SCon{'e', SCon{'t', SCon{'e', SCon{':', providerId}}}}}}}:
      do IO<String>:
        result : Auth.StoreResult(Unit) <- Runtime.delete(credentials, providerId, None{})
        return outcome(Unit, unitValue, result)
    case "list":
      do IO<String>:
        result : Auth.StoreResult(List<&2, Auth.CredentialInfo>) <- Runtime.list(credentials, None{})
        return outcome(List<&2, Auth.CredentialInfo>, infoValues, result)
    case other: IO.pure(String, line(errorValue("fixture: unknown step " ++ other)))

def runtimeSteps(+credentials: Runtime.RuntimeCredentials, values: List<&2, String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case step <> rest:
      do IO<Unit>:
        result : String <- runtimeStep(credentials, step)
        IO.print(result)
        runtimeSteps(credentials, rest)

def runtimeScript(storage: Storage.AuthStorage, script: String) -> IO(Unit):
  do IO<Unit>:
    +store : Auth.CredentialStore <- Storage.store(storage)
    +credentials : Runtime.RuntimeCredentials <- Runtime.create(store)
    runtimeSteps(credentials, steps(script, "", Nil{}))
    Runtime.dispose(credentials)
    Auth.disposeStore(store)

# RuntimeCredentials forwards the caller's signal to every persistent-store
# operation. Each probe aborts its original controller inside the store
# callback; the received signal must observe that same cancellation.
type SignalProbe is Data:
  SignalProbe{label: String, controller: Abort.AbortController<Unit>, seen: Ref.Ref<List<&2, String>>}

def observedSignal(signal: Auth.Signal()) -> IO(Bool):
  match signal:
    case None{}: IO.pure(Bool, False{})
    case Some{value}: Abort.aborted(Unit, value)

def recordSignal(probe: SignalProbe, signal: Auth.Signal()) -> IO(Unit):
  match probe:
    case SignalProbe{label, controller, seen}:
      do IO<Unit>:
        _ : Bool <- Abort.abort(Unit, controller, None{})
        linked : Bool <- observedSignal(signal)
        Ref.modify(List<&2, String>, Unit, seen, previous => (List.append(&2, String, previous, (label ++ ":" ++ Bool.pick(String, linked, "true", "false")) <> Nil{}), Unit{}))

def probedRead(probe: SignalProbe, request: Auth.Request) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match request:
    case Auth.Request{_, signal}:
      do IO<Auth.StoreResult(Maybe<&2, Auth.Credential>)>:
        recordSignal(probe, signal)
        return Done{None{}}

def probedList(probe: SignalProbe, signal: Auth.Signal()) -> IO(Auth.StoreResult(List<&2, Auth.CredentialInfo>)):
  do IO<Auth.StoreResult(List<&2, Auth.CredentialInfo>)>:
    recordSignal(probe, signal)
    return Done{Nil{}}

def probedModify(probe: SignalProbe, request: Auth.Modify) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match request:
    case Auth.Modify{_, _, signal}:
      do IO<Auth.StoreResult(Maybe<&2, Auth.Credential>)>:
        recordSignal(probe, signal)
        return Done{None{}}

def probedDelete(probe: SignalProbe, request: Auth.Request) -> IO(Auth.StoreResult(Unit)):
  match request:
    case Auth.Request{_, signal}:
      do IO<Auth.StoreResult(Unit)>:
        recordSignal(probe, signal)
        return Fail{"cancelled"}

def textList(values: List<&2, String>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: V.Text{value} <> textList(rest)

def runtimeContracts() -> IO(Unit):
  do IO<Unit>:
    +seen : Ref.Ref<List<&2, String>> <- Ref.new(List<&2, String>, Nil{})
    +readController : Abort.AbortController<Unit> <- Abort.new(Unit)
    +listController : Abort.AbortController<Unit> <- Abort.new(Unit)
    +modifyController : Abort.AbortController<Unit> <- Abort.new(Unit)
    +deleteController : Abort.AbortController<Unit> <- Abort.new(Unit)
    +reader : C.Callback<Auth.Request, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~SignalProbe, ~Auth.Request, ~(Auth.StoreResult(Maybe<&2, Auth.Credential>)), ~probedRead, SignalProbe{"read", readController, seen})
    +lister : C.Callback<Auth.Signal(), Auth.StoreResult(List<&2, Auth.CredentialInfo>)> <- C.create(~SignalProbe, ~(Auth.Signal()), ~(Auth.StoreResult(List<&2, Auth.CredentialInfo>)), ~probedList, SignalProbe{"list", listController, seen})
    +modifier : C.Callback<Auth.Modify, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~SignalProbe, ~Auth.Modify, ~(Auth.StoreResult(Maybe<&2, Auth.Credential>)), ~probedModify, SignalProbe{"modify", modifyController, seen})
    +deleter : C.Callback<Auth.Request, Auth.StoreResult(Unit)> <- C.create(~SignalProbe, ~Auth.Request, ~(Auth.StoreResult(Unit)), ~probedDelete, SignalProbe{"delete", deleteController, seen})
    +store : Auth.CredentialStore = Auth.CredentialStore{reader, lister, modifier, deleter}
    +credentials : Runtime.RuntimeCredentials <- Runtime.create(store)
    Runtime.setRuntimeApiKey(credentials, "anthropic", "runtime-key")
    _ : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Runtime.read(credentials, "missing", Some{Abort.signal(Unit, readController)})
    _ : Auth.StoreResult(List<&2, Auth.CredentialInfo>) <- Runtime.list(credentials, Some{Abort.signal(Unit, listController)})
    +unchanged : Auth.Modification() <- C.create(~Maybe<&2, Auth.Credential>, ~Maybe<&2, Auth.Credential>, ~(Auth.StoreResult(Maybe<&2, Auth.Credential>)), ~update, None{})
    _ : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Runtime.modify(credentials, "missing", unchanged, Some{Abort.signal(Unit, modifyController)})
    deleteResult : Auth.StoreResult(Unit) <- Runtime.delete(credentials, "anthropic", Some{Abort.signal(Unit, deleteController)})
    preserved : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Runtime.read(credentials, "anthropic", None{})
    observations : List<&2, String> <- Ref.read(List<&2, String>, seen)
    IO.print(line(V.ArrayValue{textList(observations)}))
    IO.print(outcome(Unit, unitValue, deleteResult))
    IO.print(outcome(Maybe<&2, Auth.Credential>, credentialValue, preserved))
    C.dispose(Maybe<&2, Auth.Credential>, Auth.StoreResult(Maybe<&2, Auth.Credential>), unchanged)
    Runtime.dispose(credentials)
    Auth.disposeStore(store)
    _ : List<&2, String> <- Ref.dispose(List<&2, String>, seen)
    Abort.dispose(Unit, readController)
    Abort.dispose(Unit, listController)
    Abort.dispose(Unit, modifyController)
    Abort.dispose(Unit, deleteController)

def operate(storage: Storage.AuthStorage, values: List<String>) -> IO(Unit):
  match values:
    case "read" <> providerId <> Nil{}:
      do IO<Unit>:
        result : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Storage.read(storage, providerId, None{})
        IO.print(outcome(Maybe<&2, Auth.Credential>, credentialValue, result))
    case "list" <> Nil{}:
      do IO<Unit>:
        result : Auth.StoreResult(List<&2, Auth.CredentialInfo>) <- Storage.list(storage, None{})
        IO.print(outcome(List<&2, Auth.CredentialInfo>, infoValues, result))
    case "modify" <> providerId <> json <> Nil{}:
      do IO<Unit>:
        result : String <- modifyWith(storage, providerId, parsedCredential(json))
        IO.print(result)
    case "delete" <> providerId <> Nil{}:
      do IO<Unit>:
        result : Auth.StoreResult(Unit) <- Storage.delete(storage, providerId, None{})
        IO.print(outcome(Unit, unitValue, result))
    case "runtime" <> script <> Nil{}: runtimeScript(storage, script)
    case _: IO.die(Unit, 2, "usage: <operation> <path> ...")

def withStorage(pair: Storage.AuthStorageOwner & Storage.AuthStorage, values: List<String>) -> IO(Unit):
  match pair:
    case Tuple{owner, storage}:
      do IO<Unit>:
        operate(storage, values)
        Storage.dispose(owner)

# One storage reads, the file is replaced behind it, and it reads again: the
# second read observes the edit (upstream readLatestData's file revision).
def rereadWith(pair: Storage.AuthStorageOwner & Storage.AuthStorage, location: String, +providerId: String, json: String) -> IO(Unit):
  match pair:
    case Tuple{owner, +storage}:
      do IO<Unit>:
        first : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Storage.read(storage, providerId, None{})
        IO.print(outcome(Maybe<&2, Auth.Credential>, credentialValue, first))
        again : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Storage.read(storage, providerId, None{})
        IO.print(outcome(Maybe<&2, Auth.Credential>, credentialValue, again))
        written : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(location, json)
        edited : Auth.StoreResult(Maybe<&2, Auth.Credential>) <- Storage.read(storage, providerId, None{})
        IO.print(outcome(Maybe<&2, Auth.Credential>, credentialValue, edited))
        Storage.dispose(owner)

def run(values: List<String>) -> IO(Unit):
  match values:
    case "runtime_contracts" <> Nil{}: runtimeContracts()
    case "reread" <> +location <> providerId <> json <> Nil{}:
      do IO<Unit>:
        owner : Storage.AuthStorageOwner <- open(location)
        rereadWith(Storage.borrow(owner), location, providerId, json)
    case operation <> location <> rest:
      do IO<Unit>:
        owner : Storage.AuthStorageOwner <- open(location)
        withStorage(Storage.borrow(owner), operation <> rest)
    case _: IO.die(Unit, 2, "usage: <operation> <path> ...")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    run(values)
