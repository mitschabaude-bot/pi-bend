import Base
import ./ref.bend as Ref
import ./serial-resource.bend as Serial

# Each key has an independent serial resource. The registry owns the queues;
# callers borrow handles until all their operations have finished. Allocating
# a queue holds only the registry lock, never another key's operation lock.
type Entry is Type:
  Entry{key: String, owner: Serial.Owner<Unit>, handle: Serial.Handle<Unit>}

type Registry is Data:
  Registry{entries: Ref.Ref<List<Entry>>}

def create() -> IO(Registry):
  do IO<Registry>:
    entries : Ref.Ref<List<Entry>> <- Ref.new(List<Entry>, Nil{})
    return Registry{entries}

def lookupEntry(entry: Entry, pair: List<Entry> & Maybe<&2, Serial.Handle<Unit>>, +key: String) -> List<Entry> & Maybe<&2, Serial.Handle<Unit>>:
  match entry pair:
    case Entry{+name, owner, +handle} Tuple{rest, found}:
      (Entry{name, owner, handle} <> rest, Bool.pick(Maybe<&2, Serial.Handle<Unit>>, String.eq(name, key), Some{handle}, found))

def lookup(entries: List<Entry>, +key: String) -> List<Entry> & Maybe<&2, Serial.Handle<Unit>>:
  match entries:
    case Nil{}: (Nil{}, None{})
    case entry <> rest: lookupEntry(entry, lookup(rest, key), key)

def newEntry(key: String, rest: List<Entry>, pair: Serial.Owner<Unit> & Serial.Handle<Unit>) -> List<Entry> & Serial.Handle<Unit>:
  match pair:
    case Tuple{owner, +handle}: (Entry{key, owner, handle} <> rest, handle)

def locatedQueue(key: String, pair: List<Entry> & Maybe<&2, Serial.Handle<Unit>>) -> IO(List<Entry> & Serial.Handle<Unit>):
  match pair:
    case Tuple{entries, Some{handle}}: IO.pure(List<Entry> & Serial.Handle<Unit>, (entries, handle))
    case Tuple{entries, None{}}:
      do IO<List<Entry> & Serial.Handle<Unit>>:
        owner : Serial.Owner<Unit> <- Serial.create(Unit, Unit{})
        return newEntry(key, entries, Serial.borrow(Unit, owner))

# Ref.update makes lookup/allocation atomic. Once obtained, a handle schedules
# its whole asynchronous operation through Serial.run independently of lookup.
def queue(registry: Registry, +key: String) -> IO(Serial.Handle<Unit>):
  match registry:
    case Registry{entries}: Ref.update(List<Entry>, Serial.Handle<Unit>, entries, values => locatedQueue(key, lookup(values, key)))

def retire(entries: List<Entry>) -> IO(Unit):
  match entries:
    case Nil{}: IO.pure(Unit, Unit{})
    case Entry{_, owner, _} <> rest:
      do IO<Unit>:
        token : Unit <- Serial.retire(Unit, owner)
        retire(rest)

# Finish admitted operations before disposing the registry. Queue owners are
# retained for reuse and released together; no borrowed handle survives this.
def dispose(registry: Registry) -> IO(Unit):
  match registry:
    case Registry{entries}:
      do IO<Unit>:
        owned : List<Entry> <- Ref.dispose(List<Entry>, entries)
        retire(owned)
