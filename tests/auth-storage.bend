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
import ../packages/runtime/src/f64.bend as F

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

def run(values: List<String>) -> IO(Unit):
  match values:
    case operation <> location <> rest:
      do IO<Unit>:
        owner : Storage.AuthStorageOwner <- open(location)
        withStorage(Storage.borrow(owner), operation <> rest)
    case _: IO.die(Unit, 2, "usage: <operation> <path> ...")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    run(values)
