import Base
import ./dns-message.bend as Id
import ./resolver-config.bend as Configuration
import ./dns-transport.bend as Source
import ./abort.bend as Abort
import ./hosts.bend as Hosts
import ./deadline.bend as Deadline
import ./socket.bend as Endpoint
import ./socket.bend as Connect
import ./random.bend as Index
import ./network-interface.bend as Interface
import ./url.bend as IPv4
import ./url.bend as IPv6
import ./io-pair.bend as Parallel
import ./socket.bend as SocketIO
import ./socket.bend as DatagramIO
import ./datagram-peer.bend as Peer
import ./ipv6-scope.bend as IPv6Scope
import ./file-fold.bend as Fold
import ./utf8.bend as UTF8
import ./json.bend as Quote

type Address is Data:
  V4{value: IPv4.Address, ttl: U32}
  V6{value: IPv6.Ipv6Address, ttl: U32}

type Selection is Data:
  Selection{canonical: Id.Name, addresses: List<&2, Address>}

# Retain only traversed alias owners. The terminal name remains eligible for
# a follow-up query when its address data was absent from this response.
type History is Data:
  History{names: Map<&2, Bool>}

type Trace is Data:
  Trace{selection: Selection, history: History}

def newHistory() -> History:
  History{Map.new(&2, Bool)}

type Error is Data:
  InvalidName{error: Id.DomainNameError}
  InvalidRecord{error: Id.RecordError}
  InvalidExtension{error: Id.EdnsResponseError}
  UnsupportedType{}
  ResponseCode{code: U32}
  AliasLoop{}
  ConflictingAlias{}

type Index is Data:
  Index{records: Map<&2, List<&2, Id.Record>>}

type Node is Data:
  Node{alias: Maybe<&2, Id.Name>, addresses: List<&2, Address>, hasAddress: Bool}

type Step is Data:
  Follow{target: Id.Name}
  Complete{result: Result<&2, &2, Error, Selection>}

type Advance is Data:
  Advance{seen: Map<&2, Bool>, state: Step}

# Length octets are at most 63, so ASCII folding of an encoded name only
# changes label bytes. Length prefixes preserve binary label boundaries.
def keyBytes(bytes: List<&2, U32>, reversed: String) -> String:
  match bytes:
    case Nil{}: String.reverse(reversed)
    case byte <> rest: keyBytes(rest, SCon{Chr{Id.fold(byte)}, reversed})

def encodedKey(result: Result<&2, &2, Id.DomainNameError, List<&2, U32>>) -> Result<&2, &2, Error, String>:
  match result:
    case Fail{error}: Fail{InvalidName{error}}
    case Done{bytes}: Done{keyBytes(bytes, SNil{})}

def nameKey(name: Id.Name) -> Result<&2, &2, Error, String>:
  encodedKey(Id.encodeName(name))

def addFound(key: String, record: Id.Record, pair: Map<&2, List<&2, Id.Record>> & List<&2, Id.Record>) -> Index:
  match pair:
    case (records, previous): Index{Map.set(&2, List<&2, Id.Record>, records, key, record <> previous)}

def addKey(index: Index, record: Id.Record, result: Result<&2, &2, Error, String>) -> Result<&2, &2, Error, Index>:
  match index result:
    case Index{records} Fail{error}: Fail{error}
    case Index{records} Done{+key}: Done{addFound(key, record, Map.get(List<&2, Id.Record>, Nil{}, records, key))}

def add(index: Index, record: Id.Record) -> Result<&2, &2, Error, Index>:
  match record:
    case Id.Record{+name, kind, 1, ttl, start, length}: addKey(index, Id.Record{name, kind, 1, ttl, start, length}, nameKey(name))
    case _: Done{index}

def indexed(records: List<&2, Id.Record>, result: Result<&2, &2, Error, Index>) -> Result<&2, &2, Error, Index>:
  match records result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case record <> rest Done{index}: indexed(rest, add(index, record))

def aliasChecked(equal: Bool, alias: Id.Name, addresses: List<&2, Address>, hasAddress: Bool) -> Result<&2, &2, Error, Node>:
  match equal:
    case True{}: Done{Node{Some{alias}, addresses, hasAddress}}
    case False{}: Fail{ConflictingAlias{}}

def addAlias(target: Id.Name, node: Node) -> Result<&2, &2, Error, Node>:
  match node:
    case Node{None{}, addresses, hasAddress}: Done{Node{Some{target}, addresses, hasAddress}}
    case Node{Some{+previous}, addresses, hasAddress}: aliasChecked(Id.sameName(previous, target), previous, addresses, hasAddress)

def addressValue(wanted: U32, ttl: U32, node: Node, value: Id.Value) -> Result<&2, &2, Error, Node>:
  match wanted node value:
    case 1 Node{alias, addresses, _} Id.A{address}: Done{Node{alias, V4{address, ttl} <> addresses, True{}}}
    case 28 Node{alias, addresses, _} Id.AAAA{address}: Done{Node{alias, V6{address, ttl} <> addresses, True{}}}
    case _ node _: Done{node}

def decoded(wanted: U32, ttl: U32, node: Node, result: Result<&2, &2, Id.RecordError, Id.Value>) -> Result<&2, &2, Error, Node>:
  match result:
    case Fail{error}: Fail{InvalidRecord{error}}
    case Done{Id.CNAME{target}}: addAlias(target, node)
    case Done{value}: addressValue(wanted, ttl, node, value)

def otherAddress(node: Node) -> Result<&2, &2, Error, Node>:
  match node:
    case Node{alias, addresses, _}: Done{Node{alias, addresses, True{}}}

def relevant(selected: Bool, address: Bool, wanted: U32, packet: Id.Packet, ttl: U32, record: Id.Record, node: Node) -> Result<&2, &2, Error, Node>:
  match selected address:
    case True{} _: decoded(wanted, ttl, node, Id.decodeRecord(packet, record))
    case False{} True{}: otherAddress(node)
    case False{} False{}: Done{node}

def inspect(+wanted: U32, packet: Id.Packet, node: Node, record: Id.Record) -> Result<&2, &2, Error, Node>:
  match record:
    case Id.Record{name, +kind, class, +ttl, start, length}: relevant(U32.is_eq(kind, wanted) || U32.is_eq(kind, 5), U32.is_eq(kind, 1) || U32.is_eq(kind, 28), wanted, packet, ttl, Id.Record{name, kind, class, ttl, start, length}, node)

def scan(records: List<&2, Id.Record>, +wanted: U32, +packet: Id.Packet, result: Result<&2, &2, Error, Node>) -> Result<&2, &2, Error, Node>:
  match records result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case record <> rest Done{node}: scan(rest, wanted, packet, inspect(wanted, packet, node, record))

def nodeResult(current: Id.Name, value: Result<&2, &2, Error, Node>) -> Step:
  match value:
    case Fail{error}: Complete{Fail{error}}
    case Done{Node{None{}, addresses, _}}: Complete{Done{Selection{current, List.reverse(&2, Address, addresses)}}}
    case Done{Node{Some{target}, _, False{}}}: Follow{target}
    case Done{Node{Some{_}, _, True{}}}: Complete{Fail{ConflictingAlias{}}}

def found(current: Id.Name, wanted: U32, packet: Id.Packet, pair: Map<&2, List<&2, Id.Record>> & List<&2, Id.Record>) -> Step:
  match pair:
    case (_, records): nodeResult(current, scan(List.reverse(&2, Id.Record, records), wanted, packet, Done{Node{None{}, Nil{}, False{}}}))

def selectNode(index: Index, current: Id.Name, wanted: U32, packet: Id.Packet, key: String) -> Step:
  match index:
    case Index{records}: found(current, wanted, packet, Map.get(List<&2, Id.Record>, Nil{}, records, key))

def advanced(key: String, seen: Map<&2, Bool>, state: Step) -> Advance:
  match state:
    case Follow{target}: Advance{Map.set(&2, Bool, seen, key, True{}), Follow{target}}
    case Complete{result}: Advance{seen, Complete{result}}

def visited(index: Index, current: Id.Name, wanted: U32, packet: Id.Packet, +key: String, pair: Map<&2, Bool> & Bool) -> Advance:
  match pair:
    case (seen, True{}): Advance{seen, Complete{Fail{AliasLoop{}}}}
    case (seen, False{}): advanced(key, seen, selectNode(index, current, wanted, packet, key))

def locate(index: Index, current: Id.Name, wanted: U32, packet: Id.Packet, seen: Map<&2, Bool>, result: Result<&2, &2, Error, String>) -> Advance:
  match result:
    case Fail{error}: Advance{seen, Complete{Fail{error}}}
    case Done{+key}: visited(index, current, wanted, packet, key, Map.get(Bool, False{}, seen, key))

def traced(seen: Map<&2, Bool>, result: Result<&2, &2, Error, Selection>) -> Result<&2, &2, Error, Trace>:
  match result:
    case Fail{error}: Fail{error}
    case Done{selection}: Done{Trace{selection, History{seen}}}

# Every alias hop requires an answer record. Structural fuel is the answer
# count plus one, not an arbitrary alias-depth limit. The visited index detects
# cycles immediately instead of repeatedly scanning a duplicate CNAME RRset.
def walk(fuel: Nat, +index: Index, +packet: Id.Packet, +wanted: U32, progress: Advance) -> Result<&2, &2, Error, Trace>:
  match fuel progress:
    case _ Advance{seen, Complete{result}}: traced(seen, result)
    case Zero{} Advance{_, Follow{_}}: Fail{AliasLoop{}}
    case Succ{rest} Advance{seen, Follow{+current}}: walk(rest, index, packet, wanted, locate(index, current, wanted, packet, seen, nameKey(current)))

def prepared(history: History, fuel: Nat, packet: Id.Packet, wanted: U32, name: Id.Name, result: Result<&2, &2, Error, Index>) -> Result<&2, &2, Error, Trace>:
  match history result:
    case _ Fail{error}: Fail{error}
    case History{seen} Done{index}: walk(fuel, index, packet, wanted, Advance{seen, Follow{name}})

def chooseRecords(history: History, valid: Bool, wanted: U32, name: Id.Name, packet: Id.Packet, +answers: List<&2, Id.Record>) -> Result<&2, &2, Error, Trace>:
  match valid:
    case False{}: Fail{UnsupportedType{}}
    case True{}: prepared(history, Succ{List.length(&2, Id.Record, answers)}, packet, wanted, name, indexed(answers, Done{Index{Map.new(&2, List<&2, Id.Record>)}}))

def selectResponse(history: History, code: U32, +wanted: U32, name: Id.Name, packet: Id.Packet, answers: List<&2, Id.Record>) -> Result<&2, &2, Error, Trace>:
  match code:
    case 0: chooseRecords(history, U32.is_eq(wanted, 1) || U32.is_eq(wanted, 28), wanted, name, packet, answers)
    case code: Fail{ResponseCode{code}}

def selectExtension(history: History, wanted: U32, name: Id.Name, message: Id.Message, extension: Result<&2, &2, Id.EdnsResponseError, Maybe<&2, Id.Response>>) -> Result<&2, &2, Error, Trace>:
  match message extension:
    case _ Fail{error}: Fail{InvalidExtension{error}}
    case Id.Message{packet, header, _, answers, _, _} Done{value}: selectResponse(history, Id.responseCode(header, value), wanted, name, packet, answers)

# Input is a matched, complete response. Only IN answer records contribute;
# authority/additional data is never promoted to address answers. Empty output
# is not proof of a cacheable negative answer. TTLs remain raw wire values;
# normalization, negative/alias caching and follow-up queries are separate.
def selectWithHistory(history: History, +wanted: U32, name: Id.Name, +message: Id.Message) -> Result<&2, &2, Error, Trace>:
  selectExtension(history, wanted, name, message, Id.inspect(message))


def selectionOnly(result: Result<&2, &2, Error, Trace>) -> Result<&2, &2, Error, Selection>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Trace{selection, _}}: Done{selection}

def select(wanted: U32, name: Id.Name, message: Id.Message) -> Result<&2, &2, Error, Selection>:
  selectionOnly(selectWithHistory(newHistory(), wanted, name, message))

type AddressLookupError<-Reason: Data> is Data:
  Aborted{reason: Abort.AbortReason<Deadline.Cause<Reason>>}
  Transport{error: Source.Error<Reason>}
  InvalidReadSize{}
  NoServers{}
  AddressLookupUnsupportedType{}
  UnsupportedClass{}
  Identifier{error: Id.IdError}
  Exchange{error: Source.TcpQueryError<Reason>}
  AddressLookupSelection{error: Error}
  Truncated{header: Id.Header}
  Cleanup{report: Source.Completed<Reason>}

type Report<-Reason: Data> is Data:
  Report{result: Result<&2, &2, AddressLookupError<Reason>, Selection>, deadline: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>}

type Progress<-Reason: Data> is Data:
  Again{name: Id.Name, history: History}
  Finished{result: Result<&2, &2, AddressLookupError<Reason>, Selection>}

def empty(-Reason: Data, same: Bool, name: Id.Name, history: History) -> Progress<Reason>:
  match same:
    case True{}: Finished{Done{Selection{name, Nil{}}}}
    case False{}: Again{name, history}

def selected(-Reason: Data, previous: Id.Name, value: Result<&2, &2, Error, Trace>) -> Progress<Reason>:
  match value:
    case Fail{error}: Finished{Fail{AddressLookupSelection{error}}}
    case Done{Trace{Selection{+name, Nil{}}, history}}: empty(Reason, Id.sameName(previous, name), name, history)
    case Done{Trace{selection, _}}: Finished{Done{selection}}

def replied(-Reason: Data, +name: Id.Name, kind: U32, history: History, result: Result<&2, &2, Source.TcpQueryError<Reason>, Source.Reply>) -> Progress<Reason>:
  match result:
    case Fail{error}: Finished{Fail{Exchange{error}}}
    case Done{Source.TcpQueryTruncated{header}}: Finished{Fail{Truncated{header}}}
    case Done{Source.TcpQueryAnswer{message}}: selected(Reason, name, selectWithHistory(history, kind, name, message))

def completed(-Reason: Data, name: Id.Name, kind: U32, history: History, value: Source.Completed<Reason>) -> Progress<Reason>:
  match value:
    case Source.Completed{result, Done{_}}: replied(Reason, name, kind, history, result)
    case Source.Completed{result, Fail{error}}: Finished{Fail{Cleanup{Source.Completed{result, Fail{error}}}}}

def resolved(-Reason: Data, name: Id.Name, kind: U32, history: History, result: Result<&2, &2, Source.TcpServersError<Reason>, Source.Reply>) -> Progress<Reason>:
  match result:
    case Done{reply}: replied(Reason, name, kind, history, Done{reply})
    case Fail{Source.NoServers{}}: Finished{Fail{NoServers{}}}
    case Fail{Source.Failed{report}}: completed(Reason, name, kind, history, report)

def exchanged(-Reason: Data, name: Id.Name, kind: U32, history: History, result: Result<&2, &2, Source.ExchangeSourceError<Reason>, Source.Reply>) -> Progress<Reason>:
  match result:
    case Done{reply}: replied(Reason, name, kind, history, Done{reply})
    case Fail{Source.TcpError{error}}: resolved(Reason, name, kind, history, Fail{error})
    case Fail{Source.TransportError{error}}: Finished{Fail{Transport{error}}}

def cancelled(-Reason: Data, source: Source.Source, why: Abort.AbortReason<Deadline.Cause<Reason>>) -> Progress<Reason>:
  match source:
    case Source.TcpSource{_}: Finished{Fail{Exchange{Source.TcpQueryConnection{Connect.Aborted{why}}}}}
    case Source.Configured{_, _}: Finished{Fail{Aborted{why}}}

# Observe cancellation again after entropy, before committing a rotation step.
def route(-Reason: Data, source: Source.Source, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, id: U32, queryOptions: Id.QueryOptions, +kind: U32, +name: Id.Name, history: History, maximum: U32, check: Result<&2, &2, Abort.AbortReason<Deadline.Cause<Reason>>, Unit>) -> IO(Progress<Reason>):
  match check:
    case Fail{why}: IO.pure(Progress<Reason>, cancelled(Reason, source, why))
    case Done{_}:
      do IO<Progress<Reason>>:
        result : Result<&2, &2, Source.ExchangeSourceError<Reason>, Source.Reply> <- Source.exchangeRequestExchangeSource(Reason, source, signal, Id.createQuery(queryOptions, id, Id.Question{name, kind, 1}), maximum)
        return exchanged(Reason, name, kind, history, result)

def identified(-Reason: Data, source: Source.Source, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, queryOptions: Id.QueryOptions, +kind: U32, +name: Id.Name, history: History, maximum: U32, value: Result<&2, &2, Id.IdError, U32>) -> IO(Progress<Reason>):
  match value:
    case Fail{error}: IO.pure(Progress<Reason>, Finished{Fail{Identifier{error}}})
    case Done{id}:
      do IO<Progress<Reason>>:
        check : Result<&2, &2, Abort.AbortReason<Deadline.Cause<Reason>>, Unit> <- Abort.throwIfAborted(Deadline.Cause<Reason>, signal)
        route(Reason, source, signal, id, queryOptions, kind, name, history, maximum, check)

# Inspect the retained abort reason before drawing an ID. After the draw,
# identified checks again before selecting servers; connect also checks.
def ready(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, environment: Environment, source: Source.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, queryOptions: Id.QueryOptions, kind: U32, name: Id.Name, history: History, maximum: U32, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> IO(Progress<Reason>):
  match reason:
    case Some{why}: IO.pure(Progress<Reason>, cancelled(Reason, source, why))
    case None{}:
      do IO<Progress<Reason>>:
        value : Result<&2, &2, Id.IdError, U32> <- draw(environment)
        identified(Reason, source, signal, queryOptions, kind, name, history, maximum, value)

# Each follow-up draws a new ID for its question. Server failover and reset
# recovery reuse that ID under the same deadline. The environment is borrowed;
# its owner disposes resources after this call. Static injection needs no mutable callback registry.
@unsafe def drive(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, +environment: Environment, +source: Source.Source, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +queryOptions: Id.QueryOptions, +kind: U32, +maximum: U32, progress: Progress<Reason>) -> IO(Result<&2, &2, AddressLookupError<Reason>, Selection>):
  match progress:
    case Finished{result}: IO.pure(Result<&2, &2, AddressLookupError<Reason>, Selection>, result)
    case Again{name, history}:
      do IO<Result<&2, &2, AddressLookupError<Reason>, Selection>>:
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Abort.reason(Deadline.Cause<Reason>, signal)
        next : Progress<Reason> <- ready(~Environment, ~draw, Reason, environment, source, signal, queryOptions, kind, name, history, maximum, reason)
        drive(~Environment, ~draw, Reason, environment, source, signal, queryOptions, kind, maximum, next)

# Execute one name and its alias follow-ups under a caller-owned deadline.
# Validation precedes entropy/network effects. This function neither resets the
# deadline nor retires its signal, allowing an enclosing search to reuse it.
def exchangeChecked(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, valid: Bool, available: Bool, environment: Environment, source: Source.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, queryOptions: Id.QueryOptions, kind: U32, name: Id.Name, maximum: U32) -> IO(Result<&2, &2, AddressLookupError<Reason>, Selection>):
  match valid available maximum:
    case False{} _ _: IO.pure(Result<&2, &2, AddressLookupError<Reason>, Selection>, Fail{AddressLookupUnsupportedType{}})
    case True{} _ 0: IO.pure(Result<&2, &2, AddressLookupError<Reason>, Selection>, Fail{InvalidReadSize{}})
    case True{} False{} _: IO.pure(Result<&2, &2, AddressLookupError<Reason>, Selection>, Fail{NoServers{}})
    case True{} True{} size: drive(~Environment, ~draw, Reason, environment, source, signal, queryOptions, kind, size, Again{name, newHistory()})

# Use a caller-reserved identifier for the first question. Alias follow-ups
# still draw fresh identifiers through the supplied environment.
def exchangeIdentifiedChecked(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, valid: Bool, available: Bool, readable: Bool, environment: Environment, source: Source.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, queryOptions: Id.QueryOptions, id: U32, kind: U32, name: Id.Name, +maximum: U32) -> IO(Result<&2, &2, AddressLookupError<Reason>, Selection>):
  match valid available readable:
    case False{} _ _: IO.pure(Result<&2, &2, AddressLookupError<Reason>, Selection>, Fail{AddressLookupUnsupportedType{}})
    case True{} _ False{}: IO.pure(Result<&2, &2, AddressLookupError<Reason>, Selection>, Fail{InvalidReadSize{}})
    case True{} False{} True{}: IO.pure(Result<&2, &2, AddressLookupError<Reason>, Selection>, Fail{NoServers{}})
    case True{} True{} True{}:
      +sharedEnvironment = environment
      +sharedSource = source
      +sharedSignal = signal
      +sharedOptions = queryOptions
      +sharedKind = kind
      +sharedMaximum = maximum
      do IO<Result<&2, &2, AddressLookupError<Reason>, Selection>>:
        first : Progress<Reason> <- identified(Reason, sharedSource, sharedSignal, sharedOptions, sharedKind, name, newHistory(), sharedMaximum, Done{id})
        drive(~Environment, ~draw, Reason, sharedEnvironment, sharedSource, sharedSignal, sharedOptions, sharedKind, sharedMaximum, first)

def exchangeRequestWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, environment: Environment, +source: Source.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Id.Request, +maximum: U32) -> IO(Result<&2, &2, AddressLookupError<Reason>, Selection>):
  match request:
    case Id.Request{id, flags, Id.Question{name, +kind, 1}, extension}:
      exchangeIdentifiedChecked(~Environment, ~draw, Reason, U32.is_eq(kind, 1) || U32.is_eq(kind, 28), Source.available(source), U32.is_ne(maximum, 0), environment, source, signal, Id.QueryOptions{flags, extension}, id, kind, name, maximum)
    case _: IO.pure(Result<&2, &2, AddressLookupError<Reason>, Selection>, Fail{UnsupportedClass{}})

def exchangeTransportOptionsWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, environment: Environment, +source: Source.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, queryOptions: Id.QueryOptions, +kind: U32, name: Id.Name, maximum: U32) -> IO(Result<&2, &2, AddressLookupError<Reason>, Selection>):
  exchangeChecked(~Environment, ~draw, Reason, U32.is_eq(kind, 1) || U32.is_eq(kind, 28), Source.available(source), environment, source, signal, queryOptions, kind, name, maximum)

def exchangeSourceOptionsWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, environment: Environment, source: Source.ServerSource<Source.Server>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, queryOptions: Id.QueryOptions, kind: U32, name: Id.Name, maximum: U32) -> IO(Result<&2, &2, AddressLookupError<Reason>, Selection>):
  exchangeTransportOptionsWith(~Environment, ~draw, Reason, environment, Source.TcpSource{source}, signal, queryOptions, kind, name, maximum)

def exchangeSourceWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, environment: Environment, source: Source.ServerSource<Source.Server>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, kind: U32, name: Id.Name, maximum: U32) -> IO(Result<&2, &2, AddressLookupError<Reason>, Selection>):
  exchangeSourceOptionsWith(~Environment, ~draw, Reason, environment, source, signal, Id.defaults(), kind, name, maximum)

def scoped(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, environment: Environment, source: Source.ServerSource<Source.Server>, queryOptions: Id.QueryOptions, kind: U32, name: Id.Name, maximum: U32, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Report<Reason>):
  match pair:
    case (scope, signal):
      do IO<Report<Reason>>:
        result : Result<&2, &2, AddressLookupError<Reason>, Selection> <- exchangeSourceOptionsWith(~Environment, ~draw, Reason, environment, source, signal, queryOptions, kind, name, maximum)
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Report{result, reason}

def startAddressLookup(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, valid: Bool, available: Bool, environment: Environment, source: Source.ServerSource<Source.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, queryOptions: Id.QueryOptions, kind: U32, name: Id.Name, maximum: U32) -> IO(Report<Reason>):
  match valid available maximum:
    case False{} _ _: IO.pure(Report<Reason>, Report{Fail{AddressLookupUnsupportedType{}}, None{}})
    case True{} _ 0: IO.pure(Report<Reason>, Report{Fail{InvalidReadSize{}}, None{}})
    case True{} False{} _: IO.pure(Report<Reason>, Report{Fail{NoServers{}}, None{}})
    case True{} True{} size:
      do IO<Report<Reason>>:
        scope : Deadline.Scope<Reason> <- Deadline.create(Reason, milliseconds, parent)
        scoped(~Environment, ~draw, Reason, environment, source, queryOptions, kind, name, size, Deadline.borrow(Reason, scope))

def exchangeServersWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, environment: Environment, servers: List<&2, Source.Server>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, kind: U32, name: Id.Name, maximum: U32) -> IO(Result<&2, &2, AddressLookupError<Reason>, Selection>):
  exchangeSourceWith(~Environment, ~draw, Reason, environment, Source.Fixed{servers}, signal, kind, name, maximum)

# The caller owns the selection source and retains it across lookup calls.
def lookupSourceOptionsWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, environment: Environment, +source: Source.ServerSource<Source.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, queryOptions: Id.QueryOptions, +kind: U32, name: Id.Name, maximum: U32) -> IO(Report<Reason>):
  startAddressLookup(~Environment, ~draw, Reason, U32.is_eq(kind, 1) || U32.is_eq(kind, 28), Source.availableServerSource(Source.Server, source), environment, source, milliseconds, parent, queryOptions, kind, name, maximum)

def lookupSourceWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, environment: Environment, source: Source.ServerSource<Source.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, name: Id.Name, maximum: U32) -> IO(Report<Reason>):
  lookupSourceOptionsWith(~Environment, ~draw, Reason, environment, source, milliseconds, parent, Id.defaults(), kind, name, maximum)

def exchangeWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, environment: Environment, address: Connect.Address, port: U32, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, kind: U32, name: Id.Name, maximum: U32) -> IO(Result<&2, &2, AddressLookupError<Reason>, Selection>):
  exchangeServersWith(~Environment, ~draw, Reason, environment, Source.Server{address, port} <> Nil{}, signal, kind, name, maximum)

# The injected source runs once per question, not per retry. It must return promptly;
# arbitrary user effects cannot be force-cancelled by the enclosing deadline.
def lookupWithAddressLookup(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, environment: Environment, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, +kind: U32, name: Id.Name, maximum: U32) -> IO(Report<Reason>):
  lookupSourceWith(~Environment, ~draw, Reason, environment, Source.Fixed{Source.Server{address, port} <> Nil{}}, milliseconds, parent, kind, name, maximum)

# Preserve the deterministic entry point. Dedicated connections isolate delayed
# replies even when a caller reuses the same ID across alias follow-ups.
def lookupAddress(-Reason: Data, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, id: U32, kind: U32, name: Id.Name, maximum: U32) -> IO(Report<Reason>):
  lookupWithAddressLookup(~U32, ~Id.fixed, Reason, id, address, port, milliseconds, parent, kind, name, maximum)

# OS entropy is the normal resolver source. Each draw is independent; random
# IDs can legitimately repeat. No uniqueness or reply-authentication guarantee.
def lookupRandom(-Reason: Data, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, name: Id.Name, maximum: U32) -> IO(Report<Reason>):
  lookupWithAddressLookup(~Unit, ~Id.random, Reason, Unit{}, address, port, milliseconds, parent, kind, name, maximum)

# The supplied order is reused for each alias question. Rotation/configuration
# policy belongs to the caller; all attempts share this one owned deadline.
def lookupServersWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, environment: Environment, servers: List<&2, Source.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, +kind: U32, name: Id.Name, maximum: U32) -> IO(Report<Reason>):
  lookupSourceWith(~Environment, ~draw, Reason, environment, Source.Fixed{servers}, milliseconds, parent, kind, name, maximum)

def lookupServersRandom(-Reason: Data, servers: List<&2, Source.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, name: Id.Name, maximum: U32) -> IO(Report<Reason>):
  lookupServersWith(~Unit, ~Id.random, Reason, Unit{}, servers, milliseconds, parent, kind, name, maximum)

def lookupSourceRandom(-Reason: Data, source: Source.ServerSource<Source.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, name: Id.Name, maximum: U32) -> IO(Report<Reason>):
  lookupSourceWith(~Unit, ~Id.random, Reason, Unit{}, source, milliseconds, parent, kind, name, maximum)

# The context borrows the ID environment, server selector and deadline signal.
# Each candidate closes its exchanges before returning.
type Context<-Environment: Data, -Reason: Data> is Data:
  Context{environment: Environment, source: Source.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Id.QueryOptions, kind: U32, maximum: U32}

type AddressSearchReport<-Reason: Data> is Data:
  AddressSearchReport{result: Result<&2, &2, Id.SearchRunError<AddressLookupError<Reason>>, Selection>, deadline: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>}

def responseCode(code: U32) -> Id.Cause:
  match code:
    case 2: Id.ServerFailure{}
    case 3: Id.Missing{}
    case _: Id.Unrecoverable{}

# Pure answer classification. The effectful completion adapter below handles
# platform socket codes; all remaining typed failures pass through intact.
def addressSearchOutcome(-Reason: Data, result: Result<&2, &2, AddressLookupError<Reason>, Selection>) -> Id.Outcome<AddressLookupError<Reason>, Selection>:
  match result:
    case Done{Selection{_, Nil{}}}: Id.SearchRunFailed{Id.EmptyAnswer{}}
    case Done{selection}: Id.Answer{selection}
    case Fail{AddressLookupSelection{ResponseCode{code}}}: Id.SearchRunFailed{responseCode(code)}
    case Fail{error}: Id.SearchHalt{error}

def socketCause(refused: Bool) -> Id.Cause:
  match refused:
    case True{}: Id.ConnectionRefused{}
    case False{}: Id.TemporaryFailure{}

def socketFailure(-Reason: Data, code: U32) -> IO(Id.Outcome<AddressLookupError<Reason>, Selection>):
  do IO<Id.Outcome<AddressLookupError<Reason>, Selection>>:
    refused : Bool <- Socket.isConnectionRefused(code)
    return Id.SearchRunFailed{socketCause(refused)}

# Only network failures enter search precedence. Abort variants and cleanup
# reports must never be classified by errno (even if they contain one).
def exchangeFailure(-Reason: Data, original: AddressLookupError<Reason>, error: Source.TcpQueryError<Reason>) -> IO(Id.Outcome<AddressLookupError<Reason>, Selection>):
  match error:
    case Source.TcpQueryConnection{Connect.SocketError{code, _}}: socketFailure(Reason, code)
    case Source.Terminated{Source.TcpSessionTransport{Source.Transport{_, SocketIO.SocketError{code, _}}}}: socketFailure(Reason, code)
    case Source.Terminated{Source.EndOfStream{}}: IO.pure(Id.Outcome<AddressLookupError<Reason>, Selection>, Id.SearchRunFailed{Id.TemporaryFailure{}})
    case Source.Terminated{Source.TcpSessionTransport{Source.Framing{Id.IncompleteFrame{}}}}: IO.pure(Id.Outcome<AddressLookupError<Reason>, Selection>, Id.SearchRunFailed{Id.TemporaryFailure{}})
    case _: IO.pure(Id.Outcome<AddressLookupError<Reason>, Selection>, Id.SearchHalt{original})

# A failed UDP report keeps both its primary failure and the reason observed
# while retiring its scope. Parent/default aborts override search continuation.
def datagramFailure(-Reason: Data, original: AddressLookupError<Reason>, failure: Source.UdpServersFailure<Reason>) -> IO(Id.Outcome<AddressLookupError<Reason>, Selection>):
  match failure:
    case Source.UdpServersRejected{_, Source.ServerFailure{}}: IO.pure(Id.Outcome<AddressLookupError<Reason>, Selection>, Id.SearchRunFailed{Id.ServerFailure{}})
    case Source.UdpServersRejected{_, _}: IO.pure(Id.Outcome<AddressLookupError<Reason>, Selection>, Id.SearchRunFailed{Id.TemporaryFailure{}})
    case Source.Exchange{Source.UdpQueryTransport{DatagramIO.DatagramSocketError{code, _}}}: socketFailure(Reason, code)
    case Source.Exchange{Source.Opening{Peer.Association{code, _}}}: socketFailure(Reason, code)
    case Source.Exchange{Source.Aborted{Abort.Supplied{Deadline.Expired{}}}}: IO.pure(Id.Outcome<AddressLookupError<Reason>, Selection>, Id.SearchRunFailed{Id.TemporaryFailure{}})
    case Source.Exchange{Source.UdpQueryTransport{DatagramIO.DatagramAborted{Abort.Supplied{Deadline.Expired{}}}}}: IO.pure(Id.Outcome<AddressLookupError<Reason>, Selection>, Id.SearchRunFailed{Id.TemporaryFailure{}})
    case _: IO.pure(Id.Outcome<AddressLookupError<Reason>, Selection>, Id.SearchHalt{original})

def datagramCompleted(-Reason: Data, original: AddressLookupError<Reason>, report: Source.UdpServersReport<Reason>) -> IO(Id.Outcome<AddressLookupError<Reason>, Selection>):
  match report:
    case Source.UdpServersReport{_, _, Source.ParentAborted{_}}: IO.pure(Id.Outcome<AddressLookupError<Reason>, Selection>, Id.SearchHalt{original})
    case Source.UdpServersReport{_, _, Source.UnexpectedDefaultAbort{}}: IO.pure(Id.Outcome<AddressLookupError<Reason>, Selection>, Id.SearchHalt{original})
    case Source.UdpServersReport{_, failure, _}: datagramFailure(Reason, original, failure)

# Only a clean TCP failure can be classified. Preserve the complete original
# native error for every halt, including a failure during stream cleanup.
def streamCompleted(-Reason: Data, original: AddressLookupError<Reason>, report: Source.Completed<Reason>) -> IO(Id.Outcome<AddressLookupError<Reason>, Selection>):
  match report:
    case Source.Completed{Fail{error}, Done{_}}: exchangeFailure(Reason, original, error)
    case _: IO.pure(Id.Outcome<AddressLookupError<Reason>, Selection>, Id.SearchHalt{original})

def completedAddressSearch(-Reason: Data, result: Result<&2, &2, AddressLookupError<Reason>, Selection>) -> IO(Id.Outcome<AddressLookupError<Reason>, Selection>):
  match result:
    case Fail{Transport{Source.Datagram{Source.UdpServersFailed{+report}}}}: datagramCompleted(Reason, Transport{Source.Datagram{Source.UdpServersFailed{report}}}, report)
    case Fail{Transport{Source.Stream{Source.Failed{+report}}}}: streamCompleted(Reason, Transport{Source.Stream{Source.Failed{report}}}, report)
    case Fail{Exchange{+error}}: exchangeFailure(Reason, Exchange{error}, error)
    case other: IO.pure(Id.Outcome<AddressLookupError<Reason>, Selection>, addressSearchOutcome(Reason, other))

def addressSearchRequest(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, context: Context<Environment, Reason>, request: Id.SearchRunRequest) -> IO(Id.Outcome<AddressLookupError<Reason>, Selection>):
  match context request:
    case Context{environment, source, signal, queryOptions, kind, maximum} Id.SearchRunRequest{_, name}:
      do IO<Id.Outcome<AddressLookupError<Reason>, Selection>>:
        result : Result<&2, &2, AddressLookupError<Reason>, Selection> <- exchangeTransportOptionsWith(~Environment, ~draw, Reason, environment, source, signal, queryOptions, kind, name, maximum)
        completedAddressSearch(Reason, result)

def scopedOptions(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, source: Source.Source, queryOptions: Id.QueryOptions, kind: U32, maximum: U32, cursor: Id.SearchCursor, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(AddressSearchReport<Reason>):
  match pair:
    case (scope, signal):
      do IO<AddressSearchReport<Reason>>:
        result : Result<&2, &2, Id.SearchRunError<AddressLookupError<Reason>>, Selection> <- Id.runSearch(~Context<Environment, Reason>, ~AddressLookupError<Reason>, ~Selection, ~addressSearchRequest(~Environment, ~draw, ~Reason), Context{environment, source, signal, queryOptions, kind, maximum}, cursor)
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return AddressSearchReport{result, reason}

def startOptions(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, valid: Bool, available: Bool, environment: Environment, source: Source.Source, milliseconds: U32, parent: Abort.AbortSignal<Reason>, queryOptions: Id.QueryOptions, kind: U32, maximum: U32, cursor: Id.SearchCursor) -> IO(AddressSearchReport<Reason>):
  match valid available maximum:
    case False{} _ _: IO.pure(AddressSearchReport<Reason>, AddressSearchReport{Fail{Id.Halted{AddressLookupUnsupportedType{}}}, None{}})
    case True{} _ 0: IO.pure(AddressSearchReport<Reason>, AddressSearchReport{Fail{Id.Halted{InvalidReadSize{}}}, None{}})
    case True{} False{} _: IO.pure(AddressSearchReport<Reason>, AddressSearchReport{Fail{Id.Halted{NoServers{}}}, None{}})
    case True{} True{} size:
      do IO<AddressSearchReport<Reason>>:
        scope : Deadline.Scope<Reason> <- Deadline.create(Reason, milliseconds, parent)
        scopedOptions(~Environment, ~draw, ~Reason, environment, source, queryOptions, kind, size, cursor, Deadline.borrow(Reason, scope))

# One total deadline spans candidates, server attempts and alias follow-ups.
# The source must return promptly; arbitrary user IO cannot be force-cancelled.
def searchTransportOptionsWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, +source: Source.Source, milliseconds: U32, parent: Abort.AbortSignal<Reason>, queryOptions: Id.QueryOptions, +kind: U32, maximum: U32, cursor: Id.SearchCursor) -> IO(AddressSearchReport<Reason>):
  startOptions(~Environment, ~draw, ~Reason, U32.is_eq(kind, 1) || U32.is_eq(kind, 28), Source.available(source), environment, source, milliseconds, parent, queryOptions, kind, maximum, cursor)

def searchSourceOptionsWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, +source: Source.ServerSource<Source.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, queryOptions: Id.QueryOptions, +kind: U32, maximum: U32, cursor: Id.SearchCursor) -> IO(AddressSearchReport<Reason>):
  searchTransportOptionsWith(~Environment, ~draw, ~Reason, environment, Source.TcpSource{source}, milliseconds, parent, queryOptions, kind, maximum, cursor)

def scopedAddressSearch(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, source: Source.ServerSource<Source.Server>, kind: U32, maximum: U32, cursor: Id.SearchCursor, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(AddressSearchReport<Reason>):
  scopedOptions(~Environment, ~draw, ~Reason, environment, Source.TcpSource{source}, Id.defaults(), kind, maximum, cursor, pair)

def startAddressSearch(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, valid: Bool, available: Bool, environment: Environment, source: Source.ServerSource<Source.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, maximum: U32, cursor: Id.SearchCursor) -> IO(AddressSearchReport<Reason>):
  startOptions(~Environment, ~draw, ~Reason, valid, available, environment, Source.TcpSource{source}, milliseconds, parent, Id.defaults(), kind, maximum, cursor)

def searchSourceWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, +source: Source.ServerSource<Source.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, +kind: U32, maximum: U32, cursor: Id.SearchCursor) -> IO(AddressSearchReport<Reason>):
  searchSourceOptionsWith(~Environment, ~draw, ~Reason, environment, source, milliseconds, parent, Id.defaults(), kind, maximum, cursor)

def searchSourceRandom(~Reason: Data, source: Source.ServerSource<Source.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, maximum: U32, cursor: Id.SearchCursor) -> IO(AddressSearchReport<Reason>):
  searchSourceWith(~Unit, ~Id.random, ~Reason, Unit{}, source, milliseconds, parent, kind, maximum, cursor)

# One total deadline spans candidates and all alias follow-ups. As in address
# lookup, the injected source must return promptly; arbitrary IO is not killed.
def searchServersWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, servers: List<&2, Source.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, maximum: U32, cursor: Id.SearchCursor) -> IO(AddressSearchReport<Reason>):
  searchSourceWith(~Environment, ~draw, ~Reason, environment, Source.Fixed{servers}, milliseconds, parent, kind, maximum, cursor)

def searchServersRandom(~Reason: Data, servers: List<&2, Source.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, maximum: U32, cursor: Id.SearchCursor) -> IO(AddressSearchReport<Reason>):
  searchSourceRandom(~Reason, Source.Fixed{servers}, milliseconds, parent, kind, maximum, cursor)

def searchWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, +kind: U32, maximum: U32, cursor: Id.SearchCursor) -> IO(AddressSearchReport<Reason>):
  searchServersWith(~Environment, ~draw, ~Reason, environment, Source.Server{address, port} <> Nil{}, milliseconds, parent, kind, maximum, cursor)

def searchRandom(~Reason: Data, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, maximum: U32, cursor: Id.SearchCursor) -> IO(AddressSearchReport<Reason>):
  searchWith(~Unit, ~Id.random, ~Reason, Unit{}, address, port, milliseconds, parent, kind, maximum, cursor)

# Resolved server ownership and the total deadline remain explicit. This layer
# consumes search/request policy, not timeout/attempt scheduling or reload.
def plannedAddressSearch(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, source: Source.ServerSource<Source.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, maximum: U32, plan: Configuration.Plan) -> IO(AddressSearchReport<Reason>):
  match plan:
    case Configuration.Plan{queryOptions, cursor}: searchSourceOptionsWith(~Environment, ~draw, ~Reason, environment, source, milliseconds, parent, queryOptions, kind, maximum, cursor)

def searchConfiguredWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, source: Source.ServerSource<Source.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, maximum: U32, configuration: Configuration.Configuration, name: Id.Name, dots: U32, absolute: Bool) -> IO(AddressSearchReport<Reason>):
  plannedAddressSearch(~Environment, ~draw, ~Reason, environment, source, milliseconds, parent, kind, maximum, Configuration.plan(configuration, name, dots, absolute))

# Own only rotation state. Immutable validated settings are retained across
# borrows; every lookup derives search and wire policy from the same options.
type Owner is Type:
  Owner{config: Configuration.Config<Endpoint.Endpoint>, selector: Source.Owner<Configuration.Attempt<Endpoint.Endpoint>>}

type Resolver is Data:
  Resolver{config: Configuration.Config<Endpoint.Endpoint>, source: Source.ServerSource<Configuration.Attempt<Endpoint.Endpoint>>}

type Replacement is Type:
  Updated{owner: Owner}
  Unchanged{error: Index.Error, owner: Owner}

def initialized(config: Configuration.Config<Endpoint.Endpoint>, result: Result<&2, &1, Index.Error, Source.Owner<Configuration.Attempt<Endpoint.Endpoint>>>) -> Result<&2, &1, Index.Error, Owner>:
  match result:
    case Fail{error}: Fail{error}
    case Done{selector}: Done{Owner{config, selector}}

def configured(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Index.Error, U32>), environment: Environment, config: Configuration.Config<Endpoint.Endpoint>, servers: List<&2, Configuration.Attempt<Endpoint.Endpoint>>, rotate: Bool) -> IO(Result<&2, &1, Index.Error, Owner>):
  match rotate:
    case False{}:
      do IO<Result<&2, &1, Index.Error, Owner>>:
        selector : Source.Owner<Configuration.Attempt<Endpoint.Endpoint>> <- Source.create(Configuration.Attempt<Endpoint.Endpoint>, servers)
        return Done{Owner{config, selector}}
    case True{}:
      do IO<Result<&2, &1, Index.Error, Owner>>:
        selector : Result<&2, &1, Index.Error, Source.Owner<Configuration.Attempt<Endpoint.Endpoint>>> <- Source.createWith(~Environment, ~draw, Configuration.Attempt<Endpoint.Endpoint>, environment, servers)
        return initialized(config, selector)

def createWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Index.Error, U32>), environment: Environment, config: Configuration.Config<Endpoint.Endpoint>) -> IO(Result<&2, &1, Index.Error, Owner>):
  match config:
    case Configuration.Config{Configuration.TransportPrepared{+queryOptions, +servers}, domains, milliseconds, maximum}:
      configured(~Environment, ~draw, environment, Configuration.Config{Configuration.TransportPrepared{queryOptions, servers}, domains, milliseconds, maximum}, servers, Configuration.enabled(Configuration.Rotate{}, queryOptions))

def create(config: Configuration.Config<Endpoint.Endpoint>) -> IO(Result<&2, &1, Index.Error, Owner>):
  createWith(~Unit, ~Index.randomWord, Unit{}, config)

def borrowed(+config: Configuration.Config<Endpoint.Endpoint>, pair: Source.Owner<Configuration.Attempt<Endpoint.Endpoint>> & Source.ServerSource<Configuration.Attempt<Endpoint.Endpoint>>) -> Owner & Resolver:
  match pair:
    case (selector, source): (Owner{config, selector}, Resolver{config, source})

def borrow(owner: Owner) -> Owner & Resolver:
  match owner:
    case Owner{+config, selector}: borrowed(config, Source.borrow(Configuration.Attempt<Endpoint.Endpoint>, Configuration.rotating(Endpoint.Endpoint, config), selector))

# Finish all borrowed operations before close or replacement. Configuration
# snapshots are immutable; a replacement never mutates an active snapshot.
def close(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{_, selector}: Source.close(Configuration.Attempt<Endpoint.Endpoint>, selector)

def replaced(previous: Owner, result: Result<&2, &1, Index.Error, Owner>) -> IO(Replacement):
  match result:
    case Fail{error}: IO.pure(Replacement, Unchanged{error, previous})
    case Done{next}:
      do IO<Replacement>:
        close(previous)
        return Updated{next}

# Construction failure returns the still-usable previous owner. On success,
# retire the previous selector only after its replacement has been created.
def replaceWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Index.Error, U32>), environment: Environment, previous: Owner, config: Configuration.Config<Endpoint.Endpoint>) -> IO(Replacement):
  do IO<Replacement>:
    next : Result<&2, &1, Index.Error, Owner> <- createWith(~Environment, ~draw, environment, config)
    replaced(previous, next)

def replace(previous: Owner, config: Configuration.Config<Endpoint.Endpoint>) -> IO(Replacement):
  replaceWith(~Unit, ~Index.randomWord, Unit{}, previous, config)

# Rotation survives across calls; each search owns one deadline spanning all
# its candidate, alias and server attempts. The supplied parent stays borrowed.
def planned(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, source: Source.ServerSource<Configuration.Attempt<Endpoint.Endpoint>>, config: Configuration.Config<Endpoint.Endpoint>, parent: Abort.AbortSignal<Reason>, kind: U32, plan: Configuration.Plan) -> IO(AddressSearchReport<Reason>):
  match config plan:
    case Configuration.Config{Configuration.TransportPrepared{queryOptions, _}, _, milliseconds, maximum} Configuration.Plan{request, cursor}: searchTransportOptionsWith(~Environment, ~draw, ~Reason, environment, Source.Configured{source, queryOptions}, milliseconds, parent, request, kind, maximum, cursor)

def lookupWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, resolver: Resolver, parent: Abort.AbortSignal<Reason>, kind: U32, name: Id.Name, dots: U32, absolute: Bool) -> IO(AddressSearchReport<Reason>):
  match resolver:
    case Resolver{+config, source}:
      planned(~Environment, ~draw, ~Reason, environment, source, config, parent, kind, Configuration.plan(Configuration.search(Endpoint.Endpoint, config), name, dots, absolute))

def lookup(~Reason: Data, resolver: Resolver, parent: Abort.AbortSignal<Reason>, kind: U32, name: Id.Name, dots: U32, absolute: Bool) -> IO(AddressSearchReport<Reason>):
  lookupWith(~Unit, ~Id.random, ~Reason, Unit{}, resolver, parent, kind, name, dots, absolute)

type PairSetupError<-Reason: Data> is Data:
  PairSetupInvalidReadSize{}
  PairSetupNoServers{}
  PairSetupAborted{reason: Abort.AbortReason<Deadline.Cause<Reason>>}
  PairSetupIdentifier{family: Id.Family, error: Id.IdError}
  Encoding{error: Id.PairQueriesError}

type Prepared is Data:
  Prepared{queries: Id.Queries, source: Source.Source}

def validated(-Reason: Data, source: Source.Source, value: Result<&2, &2, Id.PairQueriesError, Id.Queries>) -> IO(Result<&2, &2, PairSetupError<Reason>, Prepared>):
  match value:
    case Fail{error}: IO.pure(Result<&2, &2, PairSetupError<Reason>, Prepared>, Fail{Encoding{error}})
    case Done{queries}:
      do IO<Result<&2, &2, PairSetupError<Reason>, Prepared>>:
        snapshot : Source.Source <- Source.snapshot(source)
        return Done{Prepared{queries, snapshot}}

def committed(-Reason: Data, source: Source.Source, queries: Id.Queries, check: Result<&2, &2, Abort.AbortReason<Deadline.Cause<Reason>>, Unit>) -> IO(Result<&2, &2, PairSetupError<Reason>, Prepared>):
  match check:
    case Fail{reason}: IO.pure(Result<&2, &2, PairSetupError<Reason>, Prepared>, Fail{PairSetupAborted{reason}})
    case Done{_}: validated(Reason, source, Id.validate(queries))

def second(-Reason: Data, source: Source.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, queryOptions: Id.QueryOptions, name: Id.Name, id4: U32, result: Result<&2, &2, Id.IdError, U32>) -> IO(Result<&2, &2, PairSetupError<Reason>, Prepared>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, PairSetupError<Reason>, Prepared>, Fail{PairSetupIdentifier{Id.IPv6{}, error}})
    case Done{id6}:
      do IO<Result<&2, &2, PairSetupError<Reason>, Prepared>>:
        check : Result<&2, &2, Abort.AbortReason<Deadline.Cause<Reason>>, Unit> <- Abort.throwIfAborted(Deadline.Cause<Reason>, signal)
        committed(Reason, source, Id.create(queryOptions, id4, id6, name), check)

def nextPairSetup(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, environment: Environment, source: Source.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, queryOptions: Id.QueryOptions, name: Id.Name, id4: U32, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> IO(Result<&2, &2, PairSetupError<Reason>, Prepared>):
  match reason:
    case Some{why}: IO.pure(Result<&2, &2, PairSetupError<Reason>, Prepared>, Fail{PairSetupAborted{why}})
    case None{}:
      do IO<Result<&2, &2, PairSetupError<Reason>, Prepared>>:
        result : Result<&2, &2, Id.IdError, U32> <- draw(environment)
        second(Reason, source, signal, queryOptions, name, id4, result)

def firstPairSetup(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, environment: Environment, source: Source.Source, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, queryOptions: Id.QueryOptions, name: Id.Name, result: Result<&2, &2, Id.IdError, U32>) -> IO(Result<&2, &2, PairSetupError<Reason>, Prepared>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, PairSetupError<Reason>, Prepared>, Fail{PairSetupIdentifier{Id.IPv4{}, error}})
    case Done{id4}:
      do IO<Result<&2, &2, PairSetupError<Reason>, Prepared>>:
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Abort.reason(Deadline.Cause<Reason>, signal)
        nextPairSetup(~Environment, ~draw, Reason, environment, source, signal, queryOptions, name, id4, reason)

def readyPairSetup(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, +environment: Environment, source: Source.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, queryOptions: Id.QueryOptions, name: Id.Name, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> IO(Result<&2, &2, PairSetupError<Reason>, Prepared>):
  match reason:
    case Some{why}: IO.pure(Result<&2, &2, PairSetupError<Reason>, Prepared>, Fail{PairSetupAborted{why}})
    case None{}:
      do IO<Result<&2, &2, PairSetupError<Reason>, Prepared>>:
        result : Result<&2, &2, Id.IdError, U32> <- draw(environment)
        firstPairSetup(~Environment, ~draw, Reason, environment, source, signal, queryOptions, name, result)

def checked(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, available: Bool, maximum: U32, environment: Environment, source: Source.Source, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, queryOptions: Id.QueryOptions, name: Id.Name) -> IO(Result<&2, &2, PairSetupError<Reason>, Prepared>):
  match available maximum:
    case _ 0: IO.pure(Result<&2, &2, PairSetupError<Reason>, Prepared>, Fail{PairSetupInvalidReadSize{}})
    case False{} _: IO.pure(Result<&2, &2, PairSetupError<Reason>, Prepared>, Fail{PairSetupNoServers{}})
    case True{} _:
      do IO<Result<&2, &2, PairSetupError<Reason>, Prepared>>:
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Abort.reason(Deadline.Cause<Reason>, signal)
        readyPairSetup(~Environment, ~draw, Reason, environment, source, signal, queryOptions, name, reason)

# Reserve IDs in family order, checking the retained abort state before each
# draw and before the single rotation commit. IDs may repeat: dedicated query
# connections/sockets and question matching provide transaction isolation.
def prepareWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, environment: Environment, +source: Source.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, queryOptions: Id.QueryOptions, name: Id.Name, maximum: U32) -> IO(Result<&2, &2, PairSetupError<Reason>, Prepared>):
  checked(~Environment, ~draw, Reason, Source.available(source), maximum, environment, source, signal, queryOptions, name)

type Reports<-Reason: Data> is Data:
  Reports{ipv4: Result<&2, &2, AddressLookupError<Reason>, Selection>, ipv6: Result<&2, &2, AddressLookupError<Reason>, Selection>}

def addressPairReports(-Reason: Data, pair: Result<&2, &2, AddressLookupError<Reason>, Selection> & Result<&2, &2, AddressLookupError<Reason>, Selection>) -> Reports<Reason>:
  match pair:
    case (ipv4, ipv6): Reports{ipv4, ipv6}

def execute(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, +environment: Environment, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +maximum: U32, setup: Result<&2, &2, PairSetupError<Reason>, Prepared>) -> IO(Result<&2, &2, PairSetupError<Reason>, Reports<Reason>>):
  match setup:
    case Fail{error}: IO.pure(Result<&2, &2, PairSetupError<Reason>, Reports<Reason>>, Fail{error})
    case Done{Prepared{Id.Queries{ipv4, ipv6}, +source}}:
      do IO<Result<&2, &2, PairSetupError<Reason>, Reports<Reason>>>:
        pair : Result<&2, &2, AddressLookupError<Reason>, Selection> & Result<&2, &2, AddressLookupError<Reason>, Selection> <- Parallel.both(Result<&2, &2, AddressLookupError<Reason>, Selection>, Result<&2, &2, AddressLookupError<Reason>, Selection>, exchangeRequestWith(~Environment, ~draw, Reason, environment, source, signal, ipv4, maximum), exchangeRequestWith(~Environment, ~draw, Reason, environment, source, signal, ipv6, maximum))
        return Done{addressPairReports(Reason, pair)}

# One candidate, one selected server order and one borrowed total deadline.
# Separate native exchanges isolate the two transactions. Each owns its retry,
# TCP fallback and alias work; both settle and close before this call returns.
# Setup failure is distinct from a started query's report; no sibling outcome
# is fabricated for a question that never started. Merge/search policy is external.
def exchangeWithAddressPair(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), -Reason: Data, +environment: Environment, source: Source.Source, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, queryOptions: Id.QueryOptions, name: Id.Name, +maximum: U32) -> IO(Result<&2, &2, PairSetupError<Reason>, Reports<Reason>>):
  do IO<Result<&2, &2, PairSetupError<Reason>, Reports<Reason>>>:
    setup : Result<&2, &2, PairSetupError<Reason>, Prepared> <- prepareWith(~Environment, ~draw, Reason, environment, source, signal, queryOptions, name, maximum)
    execute(~Environment, ~draw, Reason, environment, signal, maximum, setup)

# Keep a complete report beside its classification. A protocol response is
# distinct from absence of a response; code zero means a valid empty answer.
type Disposition is Data:
  Answer{}
  Reply{code: U32}
  Unavailable{cause: Id.Cause}
  Terminal{}

type Classified<-Report: Data> is Data:
  Classified{report: Report, disposition: Disposition}

type PairResultReports<-Report: Data> is Data:
  PairResultReports{ipv4: Classified<Report>, ipv6: Classified<Report>}

# The caller chooses precedence explicitly; receipt-order compatibility and
# deterministic family ordering can both use the same pure merge kernel.
type Priority is Data:
  IPv4First{}
  IPv6First{}

type Decision is Data:
  Accepted{}
  Failed{cause: Id.Cause}
  Stopped{}

def response(code: U32) -> Id.Cause:
  match code:
    case 0: Id.EmptyAnswer{}
    case 2: Id.ServerFailure{}
    case 3: Id.Missing{}
    case _: Id.Unrecoverable{}

# With two negative DNS replies, prefer the first error unless it is NOERROR.
# A real reply also takes precedence over an unavailable sibling response.
def replies(+ipv4: U32, ipv6: U32) -> Id.Cause:
  response(Bool.pick(U32, U32.is_eq(ipv4, 0), ipv6, ipv4))

# Malformed data, cancellation, entropy and cleanup failures are terminal.
# A usable address can coexist with an ordinary DNS or network failure.
def decide(ipv4: Disposition, ipv6: Disposition) -> Decision:
  match ipv4 ipv6:
    case Terminal{} _: Stopped{}
    case _ Terminal{}: Stopped{}
    case Answer{} _: Accepted{}
    case _ Answer{}: Accepted{}
    case Reply{a} Reply{b}: Failed{replies(a, b)}
    case Reply{code} Unavailable{_}: Failed{response(code)}
    case Unavailable{_} Reply{code}: Failed{response(code)}
    case Unavailable{cause} Unavailable{_}: Failed{cause}

def prioritized(priority: Priority, ipv4: Disposition, ipv6: Disposition) -> Decision:
  match priority:
    case IPv4First{}: decide(ipv4, ipv6)
    case IPv6First{}: decide(ipv6, ipv4)

def deliver(-Report: Data, reports: PairResultReports<Report>, decision: Decision) -> Id.Outcome<PairResultReports<Report>, PairResultReports<Report>>:
  match decision:
    case Accepted{}: Id.Answer{reports}
    case Failed{cause}: Id.SearchRunFailed{cause}
    case Stopped{}: Id.SearchHalt{reports}

# Successful and terminal outcomes retain both reports, in family order.
def merge(-Report: Data, priority: Priority, ipv4: Classified<Report>, ipv6: Classified<Report>) -> Id.Outcome<PairResultReports<Report>, PairResultReports<Report>>:
  match ipv4 ipv6:
    case Classified{a, +da} Classified{b, +db}: deliver(Report, PairResultReports{Classified{a, da}, Classified{b, db}}, prioritized(priority, da, db))

# Reuse the native classifier's abort/cleanup/OS-error checks first. Refine
# only its nonterminal failures using the original report, before discarding
# distinctions needed to merge A and AAAA responses.
# Exhausted UDP rejections stay unavailable, as the transport policy did not
# accept them as replies. Their RCODE/header remain in the original report.
def disposition(-Reason: Data, original: Result<&2, &2, AddressLookupError<Reason>, Selection>, outcome: Id.Outcome<AddressLookupError<Reason>, Selection>) -> Disposition:
  match original outcome:
    case _ Id.SearchHalt{_}: Terminal{}
    case _ Id.Answer{_}: Answer{}
    case Fail{AddressLookupSelection{ResponseCode{code}}} Id.SearchRunFailed{_}: Reply{code}
    case _ Id.SearchRunFailed{Id.EmptyAnswer{}}: Reply{0}
    case _ Id.SearchRunFailed{cause}: Unavailable{cause}

def classify(~Reason: Data, +original: Result<&2, &2, AddressLookupError<Reason>, Selection>) -> IO(Classified<Result<&2, &2, AddressLookupError<Reason>, Selection>>):
  do IO<Classified<Result<&2, &2, AddressLookupError<Reason>, Selection>>>:
    outcome : Id.Outcome<AddressLookupError<Reason>, Selection> <- completedAddressSearch(Reason, original)
    return Classified{original, disposition(Reason, original, outcome)}

# Explicit TCP configuration with resolved endpoints and typed search entries.
# Invalid domains remain candidate failures. OS loading, IPv6 interface
# resolution and resolver-option interpretation are separate boundaries.
type Config is Data:
  Config{servers: List<&2, Source.Server>, domains: List<&2, Id.Domain>, policy: Id.Policy, request: Id.QueryOptions, milliseconds: U32, maximum: U32, rotate: Bool}

# Assemble the already-validated search/request settings and resolved endpoints.
# The deadline is supplied by the caller; timeout/attempt scheduling is separate.
def fromSearch(servers: List<&2, Source.Server>, milliseconds: U32, maximum: U32, configuration: Configuration.Configuration) -> Config:
  match configuration:
    case Configuration.Configuration{+queryOptions, Configuration.Report{+domains, issues}}:
      Config{servers, domains, Configuration.policy(queryOptions), Configuration.requestOptions(Configuration.Configuration{queryOptions, Configuration.Report{domains, issues}}), milliseconds, maximum, Configuration.enabled(Configuration.Rotate{}, queryOptions)}

type TcpResolverOwner is Type:
  TcpResolverOwner{config: Config, selector: Source.Owner<Source.Server>}

type TcpResolver is Data:
  TcpResolver{source: Source.ServerSource<Source.Server>, domains: List<&2, Id.Domain>, policy: Id.Policy, request: Id.QueryOptions, milliseconds: U32, maximum: U32}

type TcpResolverReplacement is Type:
  TcpResolverUpdated{owner: TcpResolverOwner}
  TcpResolverUnchanged{error: Index.Error, owner: TcpResolverOwner}

def initializedTcpResolver(config: Config, result: Result<&2, &1, Index.Error, Source.Owner<Source.Server>>) -> Result<&2, &1, Index.Error, TcpResolverOwner>:
  match result:
    case Fail{error}: Fail{error}
    case Done{selector}: Done{TcpResolverOwner{config, selector}}

def configuredTcpResolver(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Index.Error, U32>), environment: Environment, config: Config, servers: List<&2, Source.Server>, rotate: Bool) -> IO(Result<&2, &1, Index.Error, TcpResolverOwner>):
  match rotate:
    case False{}:
      do IO<Result<&2, &1, Index.Error, TcpResolverOwner>>:
        selector : Source.Owner<Source.Server> <- Source.create(Source.Server, servers)
        return Done{TcpResolverOwner{config, selector}}
    case True{}:
      do IO<Result<&2, &1, Index.Error, TcpResolverOwner>>:
        selector : Result<&2, &1, Index.Error, Source.Owner<Source.Server>> <- Source.createWith(~Environment, ~draw, Source.Server, environment, servers)
        return initializedTcpResolver(config, selector)

def createWithTcpResolver(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Index.Error, U32>), environment: Environment, config: Config) -> IO(Result<&2, &1, Index.Error, TcpResolverOwner>):
  match config:
    case Config{+servers, domains, policy, request, milliseconds, maximum, +rotate}:
      configuredTcpResolver(~Environment, ~draw, environment, Config{servers, domains, policy, request, milliseconds, maximum, rotate}, servers, rotate)

def createTcpResolver(config: Config) -> IO(Result<&2, &1, Index.Error, TcpResolverOwner>):
  createWithTcpResolver(~Unit, ~Index.randomWord, Unit{}, config)

def borrowedTcpResolver(config: Config, pair: Source.Owner<Source.Server> & Source.ServerSource<Source.Server>) -> TcpResolverOwner & TcpResolver:
  match config pair:
    case Config{servers, +domains, +policy, +request, +milliseconds, +maximum, rotate} Tuple{selector, source}:
      (TcpResolverOwner{Config{servers, domains, policy, request, milliseconds, maximum, rotate}, selector}, TcpResolver{source, domains, policy, request, milliseconds, maximum})

def borrowTcpResolver(owner: TcpResolverOwner) -> TcpResolverOwner & TcpResolver:
  match owner:
    case TcpResolverOwner{Config{servers, domains, policy, request, milliseconds, maximum, +rotate}, selector}:
      borrowedTcpResolver(Config{servers, domains, policy, request, milliseconds, maximum, rotate}, Source.borrow(Source.Server, rotate, selector))

# Finish all borrowed operations before close or replacement. Configuration
# snapshots are immutable; a replacement never mutates an active snapshot.
def closeTcpResolver(owner: TcpResolverOwner) -> IO(Unit):
  match owner:
    case TcpResolverOwner{_, selector}: Source.close(Source.Server, selector)

def replacedTcpResolver(previous: TcpResolverOwner, result: Result<&2, &1, Index.Error, TcpResolverOwner>) -> IO(TcpResolverReplacement):
  match result:
    case Fail{error}: IO.pure(TcpResolverReplacement, TcpResolverUnchanged{error, previous})
    case Done{next}:
      do IO<TcpResolverReplacement>:
        closeTcpResolver(previous)
        return TcpResolverUpdated{next}

# Construction failure returns the still-usable previous owner. On success,
# retire the previous selector only after its replacement has been created.
def replaceWithTcpResolver(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Index.Error, U32>), environment: Environment, previous: TcpResolverOwner, config: Config) -> IO(TcpResolverReplacement):
  do IO<TcpResolverReplacement>:
    next : Result<&2, &1, Index.Error, TcpResolverOwner> <- createWithTcpResolver(~Environment, ~draw, environment, config)
    replacedTcpResolver(previous, next)

def replaceTcpResolver(previous: TcpResolverOwner, config: Config) -> IO(TcpResolverReplacement):
  replaceWithTcpResolver(~Unit, ~Index.randomWord, Unit{}, previous, config)

# Rotation survives across calls; each search owns one deadline spanning all
# its candidate, alias and server attempts. The supplied parent stays borrowed.
def lookupWithTcpResolver(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, resolver: TcpResolver, parent: Abort.AbortSignal<Reason>, kind: U32, name: Id.Name, dots: U32, absolute: Bool) -> IO(AddressSearchReport<Reason>):
  match resolver:
    case TcpResolver{source, domains, policy, request, milliseconds, maximum}:
      searchSourceOptionsWith(~Environment, ~draw, ~Reason, environment, source, milliseconds, parent, request, kind, maximum, Id.startDomains(name, dots, absolute, domains, policy))

def lookupTcpResolver(~Reason: Data, resolver: TcpResolver, parent: Abort.AbortSignal<Reason>, kind: U32, name: Id.Name, dots: U32, absolute: Bool) -> IO(AddressSearchReport<Reason>):
  lookupWithTcpResolver(~Unit, ~Id.random, ~Reason, Unit{}, resolver, parent, kind, name, dots, absolute)

# This entry point resolves one address family. A combined-family operation
# requires its own scheduling/deadline policy, not an implicit sequential pair.
type Family is Data:
  IPv4{}
  IPv6{}

def hostsFamily(family: Family) -> Hosts.Family:
  match family:
    case IPv4{}: Hosts.IPv4Only{}
    case IPv6{}: Hosts.IPv6Only{}

def recordType(family: Family) -> U32:
  match family:
    case IPv4{}: 1
    case IPv6{}: 28

type DNS<-Reason: Data> is Data:
  HostsResolverInvalidName{error: Id.PresentationError}
  Completed{report: AddressSearchReport<Reason>}

def network(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, resolver: Resolver, parent: Abort.AbortSignal<Reason>, family: Family, input: Result<&2, &2, Id.PresentationError, Id.Input>) -> IO(DNS<Reason>):
  match input:
    case Fail{error}: IO.pure(DNS<Reason>, HostsResolverInvalidName{error})
    case Done{Id.Input{name, dots, absolute}}:
      do IO<DNS<Reason>>:
        report : AddressSearchReport<Reason> <- lookupWith(~Environment, ~draw, ~Reason, environment, resolver, parent, recordType(family), name, dots, absolute)
        return Completed{report}

def executeHostsResolver(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, ~Error: Data, environment: Environment, resolver: Resolver, parent: Abort.AbortSignal<Reason>, family: Family, plan: Hosts.Plan<Error>) -> IO(Hosts.Report<Error, DNS<Reason>>):
  match plan:
    case Hosts.SourceFailure{error}: IO.pure(Hosts.Report<Error, DNS<Reason>>, Hosts.FailedSource{error})
    case Hosts.Local{first, rest}: IO.pure(Hosts.Report<Error, DNS<Reason>>, Hosts.FromHosts{first, rest})
    case Hosts.Query{_, text}:
      do IO<Hosts.Report<Error, DNS<Reason>>>:
        report : DNS<Reason> <- network(~Environment, ~draw, ~Reason, environment, resolver, parent, family, Id.prepare(text))
        return Hosts.FromNetwork{report}

# Borrow the existing resolver and parent signal. Local hits and source errors
# do not parse DNS text, draw identifiers, rotate servers or create deadlines.
def lookupWithHostsResolver(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, ~Error: Data, environment: Environment, resolver: Resolver, parent: Abort.AbortSignal<Reason>, +family: Family, name: String, source: Result<&2, &2, Error, List<&2, Hosts.Entry<Hosts.Address>>>) -> IO(Hosts.Report<Error, DNS<Reason>>):
  executeHostsResolver(~Environment, ~draw, ~Reason, ~Error, environment, resolver, parent, family, Hosts.plan(Error, hostsFamily(family), name, source))

def lookupHostsResolver(~Reason: Data, ~Error: Data, resolver: Resolver, parent: Abort.AbortSignal<Reason>, family: Family, name: String, source: Result<&2, &2, Error, List<&2, Hosts.Entry<Hosts.Address>>>) -> IO(Hosts.Report<Error, DNS<Reason>>):
  lookupWithHostsResolver(~Unit, ~Id.random, ~Reason, ~Error, Unit{}, resolver, parent, family, name, source)

type Failure<-Reason: Data> is Data:
  SetupFailed{error: PairSetupError<Reason>}
  QueryFailed{reports: PairResultReports<Result<&2, &2, AddressLookupError<Reason>, Selection>>}

type PairSearchReport<-Reason: Data> is Data:
  PairSearchReport{result: Result<&2, &2, Id.SearchRunError<Failure<Reason>>, PairResultReports<Result<&2, &2, AddressLookupError<Reason>, Selection>>>, deadline: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>}

type PairSearchContext<-Environment: Data, -Reason: Data> is Data:
  PairSearchContext{environment: Environment, source: Source.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Id.QueryOptions, priority: Priority, maximum: U32}

def merged(-Reason: Data, outcome: Id.Outcome<PairResultReports<Result<&2, &2, AddressLookupError<Reason>, Selection>>, PairResultReports<Result<&2, &2, AddressLookupError<Reason>, Selection>>>) -> Id.Outcome<Failure<Reason>, PairResultReports<Result<&2, &2, AddressLookupError<Reason>, Selection>>>:
  match outcome:
    case Id.Answer{reports}: Id.Answer{reports}
    case Id.SearchRunFailed{cause}: Id.SearchRunFailed{cause}
    case Id.SearchHalt{reports}: Id.SearchHalt{QueryFailed{reports}}

def completedPairSearch(~Reason: Data, priority: Priority, result: Result<&2, &2, PairSetupError<Reason>, Reports<Reason>>) -> IO(Id.Outcome<Failure<Reason>, PairResultReports<Result<&2, &2, AddressLookupError<Reason>, Selection>>>):
  match result:
    case Fail{error}: IO.pure(Id.Outcome<Failure<Reason>, PairResultReports<Result<&2, &2, AddressLookupError<Reason>, Selection>>>, Id.SearchHalt{SetupFailed{error}})
    case Done{Reports{ipv4, ipv6}}:
      do IO<Id.Outcome<Failure<Reason>, PairResultReports<Result<&2, &2, AddressLookupError<Reason>, Selection>>>>:
        a : Classified<Result<&2, &2, AddressLookupError<Reason>, Selection>> <- classify(~Reason, ipv4)
        b : Classified<Result<&2, &2, AddressLookupError<Reason>, Selection>> <- classify(~Reason, ipv6)
        return merged(Reason, merge(Result<&2, &2, AddressLookupError<Reason>, Selection>, priority, a, b))

def pairSearchRequest(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, context: PairSearchContext<Environment, Reason>, request: Id.SearchRunRequest) -> IO(Id.Outcome<Failure<Reason>, PairResultReports<Result<&2, &2, AddressLookupError<Reason>, Selection>>>):
  match context request:
    case PairSearchContext{environment, source, signal, queryOptions, priority, maximum} Id.SearchRunRequest{_, name}:
      do IO<Id.Outcome<Failure<Reason>, PairResultReports<Result<&2, &2, AddressLookupError<Reason>, Selection>>>>:
        result : Result<&2, &2, PairSetupError<Reason>, Reports<Reason>> <- exchangeWithAddressPair(~Environment, ~draw, Reason, environment, source, signal, queryOptions, name, maximum)
        completedPairSearch(~Reason, priority, result)

def scopedPairSearch(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, source: Source.Source, queryOptions: Id.QueryOptions, priority: Priority, maximum: U32, cursor: Id.SearchCursor, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(PairSearchReport<Reason>):
  match pair:
    case (scope, signal):
      do IO<PairSearchReport<Reason>>:
        result : Result<&2, &2, Id.SearchRunError<Failure<Reason>>, PairResultReports<Result<&2, &2, AddressLookupError<Reason>, Selection>>> <- Id.runSearch(~PairSearchContext<Environment, Reason>, ~Failure<Reason>, ~PairResultReports<Result<&2, &2, AddressLookupError<Reason>, Selection>>, ~pairSearchRequest(~Environment, ~draw, ~Reason), PairSearchContext{environment, source, signal, queryOptions, priority, maximum}, cursor)
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return PairSearchReport{result, reason}

def startPairSearch(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, available: Bool, environment: Environment, source: Source.Source, milliseconds: U32, parent: Abort.AbortSignal<Reason>, queryOptions: Id.QueryOptions, priority: Priority, maximum: U32, cursor: Id.SearchCursor) -> IO(PairSearchReport<Reason>):
  match available maximum:
    case _ 0: IO.pure(PairSearchReport<Reason>, PairSearchReport{Fail{Id.Halted{SetupFailed{PairSetupInvalidReadSize{}}}}, None{}})
    case False{} _: IO.pure(PairSearchReport<Reason>, PairSearchReport{Fail{Id.Halted{SetupFailed{PairSetupNoServers{}}}}, None{}})
    case True{} size:
      do IO<PairSearchReport<Reason>>:
        scope : Deadline.Scope<Reason> <- Deadline.create(Reason, milliseconds, parent)
        scopedPairSearch(~Environment, ~draw, ~Reason, environment, source, queryOptions, priority, size, cursor, Deadline.borrow(Reason, scope))

# Both families finish for a candidate before the shared search cursor advances.
# One owned deadline spans every candidate and alias. Priority is explicit;
# this API does not choose an application default or emulate receipt order.
def searchWithPairSearch(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, +source: Source.Source, milliseconds: U32, parent: Abort.AbortSignal<Reason>, queryOptions: Id.QueryOptions, priority: Priority, maximum: U32, cursor: Id.SearchCursor) -> IO(PairSearchReport<Reason>):
  startPairSearch(~Environment, ~draw, ~Reason, Source.available(source), environment, source, milliseconds, parent, queryOptions, priority, maximum, cursor)

def plannedPairResolver(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, source: Source.ServerSource<Configuration.Attempt<Endpoint.Endpoint>>, config: Configuration.Config<Endpoint.Endpoint>, parent: Abort.AbortSignal<Reason>, priority: Priority, plan: Configuration.Plan) -> IO(PairSearchReport<Reason>):
  match config plan:
    case Configuration.Config{Configuration.TransportPrepared{queryOptions, _}, _, milliseconds, maximum} Configuration.Plan{request, cursor}: searchWithPairSearch(~Environment, ~draw, ~Reason, environment, Source.Configured{source, queryOptions}, milliseconds, parent, request, priority, maximum, cursor)

# Borrow the same persistent owner as single-family lookups. Immutable settings
# supply search, transport, request and deadline policy; rotation state persists
# across calls. Priority remains an explicit caller choice.
def lookupWithPairResolver(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, resolver: Resolver, parent: Abort.AbortSignal<Reason>, priority: Priority, name: Id.Name, dots: U32, absolute: Bool) -> IO(PairSearchReport<Reason>):
  match resolver:
    case Resolver{+config, source}: plannedPairResolver(~Environment, ~draw, ~Reason, environment, source, config, parent, priority, Configuration.plan(Configuration.search(Endpoint.Endpoint, config), name, dots, absolute))

def lookupPairResolver(~Reason: Data, resolver: Resolver, parent: Abort.AbortSignal<Reason>, priority: Priority, name: Id.Name, dots: U32, absolute: Bool) -> IO(PairSearchReport<Reason>):
  lookupWithPairResolver(~Unit, ~Id.random, ~Reason, Unit{}, resolver, parent, priority, name, dots, absolute)

type PairHostsResolverDNS<-Reason: Data> is Data:
  PairHostsResolverInvalidName{error: Id.PresentationError}
  PairHostsResolverCompleted{report: PairSearchReport<Reason>}

def networkPairLookup(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, environment: Environment, resolver: Resolver, parent: Abort.AbortSignal<Reason>, priority: Priority, input: Result<&2, &2, Id.PresentationError, Id.Input>) -> IO(PairHostsResolverDNS<Reason>):
  match input:
    case Fail{error}: IO.pure(PairHostsResolverDNS<Reason>, PairHostsResolverInvalidName{error})
    case Done{Id.Input{name, dots, absolute}}:
      do IO<PairHostsResolverDNS<Reason>>:
        report : PairSearchReport<Reason> <- lookupWithPairResolver(~Environment, ~draw, ~Reason, environment, resolver, parent, priority, name, dots, absolute)
        return PairHostsResolverCompleted{report}

type PairHostsResolverContext<-Environment: Data, -Reason: Data> is Data:
  PairHostsResolverContext{environment: Environment, resolver: Resolver, parent: Abort.AbortSignal<Reason>, priority: Priority}

def requested(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, context: PairHostsResolverContext<Environment, Reason>, family: Hosts.Family, text: String) -> IO(PairHostsResolverDNS<Reason>):
  match context:
    case PairHostsResolverContext{environment, resolver, parent, priority}: networkPairLookup(~Environment, ~draw, ~Reason, environment, resolver, parent, priority, Id.prepare(text))

# Any local family satisfies files-first lookup. Preserve source order and
# duplicates; do not query DNS to fill in an absent family. Only a complete
# local miss starts paired DNS. Source failures and local hits bypass DNS text
# parsing, identifier draws, server rotation and deadline allocation.
def lookupWithPairHostsResolver(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, ~Error: Data, environment: Environment, resolver: Resolver, parent: Abort.AbortSignal<Reason>, priority: Priority, name: String, source: Result<&2, &2, Error, List<&2, Hosts.Entry<Hosts.Address>>>) -> IO(Hosts.Report<Error, PairHostsResolverDNS<Reason>>):
  Hosts.resolveWith(~PairHostsResolverContext<Environment, Reason>, ~Error, ~PairHostsResolverDNS<Reason>, ~requested(~Environment, ~draw, ~Reason), PairHostsResolverContext{environment, resolver, parent, priority}, Hosts.Any{}, name, source)

def lookupPairHostsResolver(~Reason: Data, ~Error: Data, resolver: Resolver, parent: Abort.AbortSignal<Reason>, priority: Priority, name: String, source: Result<&2, &2, Error, List<&2, Hosts.Entry<Hosts.Address>>>) -> IO(Hosts.Report<Error, PairHostsResolverDNS<Reason>>):
  lookupWithPairHostsResolver(~Unit, ~Id.random, ~Reason, ~Error, Unit{}, resolver, parent, priority, name, source)

# Positions refer to the validated Configuration.servers list, starting at zero.
# Invalid source tokens remain in Configuration.diagnostics, not in this list.
type Issue<-LookupError: Data> is Data:
  Issue{position: Nat, error: IPv6Scope.Error<LookupError>}

type ServersReport<-LookupError: Data> is Data:
  ServersReport{servers: List<&2, Source.Server>, issues: List<&2, Issue<LookupError>>}

type Configuration<-LookupError: Data> is Data:
  Configuration{settings: Configuration.Settings, endpoints: ServersReport<LookupError>}

type State<-LookupError: Data> is Data:
  State{position: Nat, servers: List<&2, Source.Server>, issues: List<&2, Issue<LookupError>>}

def serverIssues(-LookupError: Data, position: Nat, failure: Maybe<&2, IPv6Scope.Error<LookupError>>, previous: List<&2, Issue<LookupError>>) -> List<&2, Issue<LookupError>>:
  match failure:
    case None{}: previous
    case Some{error}: Issue{position, error} <> previous

def added(-LookupError: Data, state: State<LookupError>, report: Configuration.ScopeReport<LookupError>) -> State<LookupError>:
  match state report:
    case State{+position, servers, previous} Configuration.ScopeReport{address, failure}:
      State{(position + 1n : Nat), Source.Server{address, 53} <> servers, serverIssues(LookupError, position, failure, previous)}

# Resolve in configuration order. Duplicates remain distinct entries, and an
# invalid scope retains its server with scope zero plus a positional diagnostic.
def collectWith(~LookupError: Data, ~Context: Data, ~lookupAddress: Context -> String -> IO(Result<&2, &2, LookupError, U32>), +context: Context, addresses: List<&2, Configuration.Address>, state: State<LookupError>) -> IO(ServersReport<LookupError>):
  match addresses state:
    case Nil{} State{_, servers, failures}: IO.pure(ServersReport<LookupError>, ServersReport{List.reverse(&2, Source.Server, servers), List.reverse(&2, Issue<LookupError>, failures)})
    case address <> rest previous:
      do IO<ServersReport<LookupError>>:
        report : Configuration.ScopeReport<LookupError> <- Configuration.resolveWithScope(~LookupError, ~Context, ~lookupAddress, context, address)
        collectWith(~LookupError, ~Context, ~lookupAddress, context, rest, added(LookupError, previous, report))

def resolveWith(~LookupError: Data, ~Context: Data, ~lookupAddress: Context -> String -> IO(Result<&2, &2, LookupError, U32>), context: Context, addresses: List<&2, Configuration.Address>) -> IO(ServersReport<LookupError>):
  collectWith(~LookupError, ~Context, ~lookupAddress, context, addresses, State{0n, Nil{}, Nil{}})

# Preserve all source settings for the subsequent search/options/reload policy.
# This phase resolves addresses only; it never applies partial option values.
def prepareWithServers(~LookupError: Data, ~Context: Data, ~lookupAddress: Context -> String -> IO(Result<&2, &2, LookupError, U32>), context: Context, settings: Configuration.Settings) -> IO(Configuration<LookupError>):
  match settings:
    case Configuration.Settings{+servers, search, queryOptions, sortlist, diagnostics}:
      do IO<Configuration<LookupError>>:
        endpoints : ServersReport<LookupError> <- resolveWith(~LookupError, ~Context, ~lookupAddress, context, servers)
        return Configuration{Configuration.Settings{servers, search, queryOptions, sortlist, diagnostics}, endpoints}

# Keep the OS effect separate from the injectable pure scope policy.
def resolve(address: Configuration.Address) -> IO(Configuration.ScopeReport<Interface.Error>):
  Configuration.resolveWithScope(~Interface.Error, ~Unit, ~Interface.lookup, Unit{}, address)

def resolveAll(addresses: List<&2, Configuration.Address>) -> IO(ServersReport<Interface.Error>):
  resolveWith(~Interface.Error, ~Unit, ~Interface.lookup, Unit{}, addresses)

def prepare(settings: Configuration.Settings) -> IO(Configuration<Interface.Error>):
  prepareWithServers(~Interface.Error, ~Unit, ~Interface.lookup, Unit{}, settings)

type SystemServersReport is Data:
  SystemServersReport{configuration: Configuration<Interface.Error>, hostnameFailure: Maybe<&2, Configuration.Failure>, unavailable: Maybe<&2, Configuration.Unavailable>}

def loadedSystemServers(-DecodeError: Data, result: Result<&2, &2, Configuration.LoadError<DecodeError>, Configuration.SystemLinuxReport>) -> IO(Result<&2, &2, Configuration.LoadError<DecodeError>, SystemServersReport>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, Configuration.LoadError<DecodeError>, SystemServersReport>, Fail{error})
    case Done{Configuration.SystemLinuxReport{Configuration.SystemReport{settings, hostnameFailure}, unavailable}}:
      do IO<Result<&2, &2, Configuration.LoadError<DecodeError>, SystemServersReport>>:
        configuration : Configuration<Interface.Error> <- prepare(settings)
        return Done{SystemServersReport{configuration, hostnameFailure, unavailable}}

# Linux file policy, environment/hostname defaults and all interface lookups.
# Search/option interpretation is still a distinct configuration phase.
def loadWithSystemServers(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, Configuration.LoadError<DecodeError>, SystemServersReport>):
  do IO<Result<&2, &2, Configuration.LoadError<DecodeError>, SystemServersReport>>:
    settings : Result<&2, &2, Configuration.LoadError<DecodeError>, Configuration.SystemLinuxReport> <- Configuration.loadWithSystemLinux(~DecodeError, ~decode, path, chunkSize, byteLimit)
    loadedSystemServers(DecodeError, settings)

# Retain the complete source report, including scope, hostname and file
# diagnostics, for the caller's configuration acceptance and reload policy.
type SystemConfigPrepared is Data:
  SystemConfigPrepared{source: SystemServersReport, search: Configuration.Configuration, resolver: Configuration.Config<Endpoint.Endpoint>}

type SystemConfigError<-DecodeError: Data> is Data:
  InvalidTransport{source: SystemServersReport, error: Configuration.Error}
  Loading{error: Configuration.LoadError<DecodeError>}
  InvalidOptions{source: SystemServersReport, diagnostics: List<&2, Configuration.Diagnostic>}

# Preserve numeric IPv6 scope IDs and configured occurrence order.
def endpoint(server: Source.Server) -> Endpoint.Endpoint:
  match server:
    case Source.Server{Connect.V4{ip}, port}: Endpoint.EndpointV4{ip, port}
    case Source.Server{Connect.V6{ip, scope}, port}: Endpoint.EndpointV6{ip, port, scope}

def systemEndpoints(servers: List<&2, Source.Server>) -> List<&2, Endpoint.Endpoint>:
  match servers:
    case Nil{}: Nil{}
    case first <> rest: endpoint(first) <> systemEndpoints(rest)

def configuredSystemConfig(-DecodeError: Data, source: SystemServersReport, search: Configuration.Configuration, result: Result<&2, &2, Configuration.Error, Configuration.Config<Endpoint.Endpoint>>) -> Result<&2, &2, SystemConfigError<DecodeError>, SystemConfigPrepared>:
  match result:
    case Fail{error}: Fail{InvalidTransport{source, error}}
    case Done{resolver}: Done{SystemConfigPrepared{source, search, resolver}}

def checkedSystemConfig(-DecodeError: Data, source: SystemServersReport, servers: List<&2, Source.Server>, milliseconds: U32, maximum: U32, result: Result<&2, &2, List<&2, Configuration.Diagnostic>, Configuration.Configuration>) -> Result<&2, &2, SystemConfigError<DecodeError>, SystemConfigPrepared>:
  match result:
    case Fail{diagnostics}: Fail{InvalidOptions{source, diagnostics}}
    case Done{+search}: configuredSystemConfig(DecodeError, source, search, Configuration.prepareConfiguration(Endpoint.Endpoint, systemEndpoints(servers), milliseconds, maximum, search))

# Strict option and transport-plan acceptance precede owner creation. Other
# diagnostics remain explicit in the complete source report on either outcome.
def prepareSystemConfig(-DecodeError: Data, milliseconds: U32, maximum: U32, source: SystemServersReport) -> Result<&2, &2, SystemConfigError<DecodeError>, SystemConfigPrepared>:
  match source:
    case SystemServersReport{Configuration{+settings, ServersReport{+servers, issues}}, hostname, unavailable}:
      checkedSystemConfig(DecodeError, SystemServersReport{Configuration{settings, ServersReport{servers, issues}}, hostname, unavailable}, servers, milliseconds, maximum, Configuration.fromSettingsStrict(settings))

def loaded(-DecodeError: Data, milliseconds: U32, maximum: U32, result: Result<&2, &2, Configuration.LoadError<DecodeError>, SystemServersReport>) -> Result<&2, &2, SystemConfigError<DecodeError>, SystemConfigPrepared>:
  match result:
    case Fail{error}: Fail{Loading{error}}
    case Done{source}: prepareSystemConfig(DecodeError, milliseconds, maximum, source)

def loadWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat, milliseconds: U32, maximum: U32) -> IO(Result<&2, &2, SystemConfigError<DecodeError>, SystemConfigPrepared>):
  do IO<Result<&2, &2, SystemConfigError<DecodeError>, SystemConfigPrepared>>:
    source : Result<&2, &2, Configuration.LoadError<DecodeError>, SystemServersReport> <- loadWithSystemServers(~DecodeError, ~decode, path, chunkSize, byteLimit)
    return loaded(DecodeError, milliseconds, maximum, source)

# Native configuration diagnostics retain operation, source code and position.
# The typed report remains available separately; formatting does not determine
# whether a configuration is accepted or silently drop invalid options.
def operatingSystem(operation: String, code: U32, message: String) -> String:
  operation ++ " (code " ++ Nat.show(U32.to_nat(code)) ++ "): " ++ message

def file(error: Fold.Error) -> String:
  match error:
    case Fold.InvalidReadSize{}: "Invalid resolver file read size"
    case Fold.Open{code, message}: operatingSystem("Could not open resolver configuration", code, message)
    case Fold.Read{code, message}: operatingSystem("Could not read resolver configuration", code, message)
    case Fold.Close{code, message}: operatingSystem("Could not close resolver configuration", code, message)
    case Fold.ReadAndClose{rc, rm, cc, cm}:
      operatingSystem("Could not read resolver configuration", rc, rm) ++ "; " ++ operatingSystem("Could not close resolver configuration", cc, cm)

def decoding(error: UTF8.Error) -> String:
  match error:
    case UTF8.InvalidByte{offset, value}: "Invalid resolver configuration byte " ++ Nat.show(U32.to_nat(value)) ++ " at offset " ++ Nat.show(offset)
    case UTF8.InvalidSequence{offset, value}: "Invalid resolver configuration UTF-8 sequence at offset " ++ Nat.show(offset) ++ " (byte " ++ Nat.show(U32.to_nat(value)) ++ ")"
    case UTF8.IncompleteSequence{offset}: "Incomplete resolver configuration UTF-8 sequence at offset " ++ Nat.show(offset)

def loading(error: Configuration.LoadError<UTF8.Error>) -> String:
  match error:
    case Configuration.Environment{Configuration.EnvironmentError{variable, code, message}}: operatingSystem("Could not read resolver environment variable " ++ Quote.quote(variable), code, message)
    case Configuration.LoadFile{Configuration.File{cause}}: file(cause)
    case Configuration.LoadFile{Configuration.TooLarge{}}: "Resolver configuration exceeds its byte limit"
    case Configuration.LoadFile{Configuration.Decode{cause}}: decoding(cause)

def transport(error: Configuration.Error) -> String:
  match error:
    case Configuration.NoServers{}: "Resolver configuration has no name servers"
    case Configuration.TooManyServers{}: "Resolver configuration exceeds the supported three name servers"
    case Configuration.InvalidTimeout{seconds}: "Invalid resolver timeout in seconds: " ++ Nat.show(U32.to_nat(seconds))

def option(error: Configuration.Diagnostic) -> String:
  match error:
    case Configuration.Malformed{token}: "Malformed resolver option " ++ Quote.quote(token)
    case Configuration.OptionsUnknown{token}: "Unknown resolver option " ++ Quote.quote(token)

def options(errors: List<&2, Configuration.Diagnostic>) -> List<&2, String>:
  match errors:
    case Nil{}: Nil{}
    case first <> rest: option(first) <> options(rest)

# Keep each invalid option as its own diagnostic instead of flattening an
# arbitrary list with ambiguous separators. Provider presentation can join it.
def messages(error: SystemConfigError<UTF8.Error>) -> List<&2, String>:
  match error:
    case Loading{cause}: loading(cause) <> Nil{}
    case InvalidTransport{_, cause}: transport(cause) <> Nil{}
    case InvalidOptions{_, errors}: options(errors)
