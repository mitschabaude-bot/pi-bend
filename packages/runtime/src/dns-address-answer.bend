import Base
import ./dns-name.bend as Name
import ./dns-message.bend as Message
import ./dns-record.bend as Record
import ./dns-response.bend as Response
import ./dns-edns-response.bend as Edns
import ./url-ipv4.bend as IPv4
import ./url-ipv6.bend as IPv6

type Address is Data:
  V4{value: IPv4.Address, ttl: U32}
  V6{value: IPv6.Address, ttl: U32}

type Selection is Data:
  Selection{canonical: Name.Name, addresses: List<&2, Address>}

# Retain only traversed alias owners. The terminal name remains eligible for
# a follow-up query when its address data was absent from this response.
type History is Data:
  History{names: Map<&2, Bool>}

type Trace is Data:
  Trace{selection: Selection, history: History}

def newHistory() -> History:
  History{Map.new(&2, Bool)}

type Error is Data:
  InvalidName{error: Name.Error}
  InvalidRecord{error: Record.Error}
  InvalidExtension{error: Edns.Error}
  UnsupportedType{}
  ResponseCode{code: U32}
  AliasLoop{}
  ConflictingAlias{}

type Index is Data:
  Index{records: Map<&2, List<&2, Message.Record>>}

type Node is Data:
  Node{alias: Maybe<&2, Name.Name>, addresses: List<&2, Address>, hasAddress: Bool}

type Step is Data:
  Follow{target: Name.Name}
  Complete{result: Result<&2, &2, Error, Selection>}

type Advance is Data:
  Advance{seen: Map<&2, Bool>, state: Step}

# Length octets are at most 63, so ASCII folding of an encoded name only
# changes label bytes. Length prefixes preserve binary label boundaries.
def keyBytes(bytes: List<&2, U32>, reversed: String) -> String:
  match bytes:
    case Nil{}: String.reverse(reversed)
    case byte <> rest: keyBytes(rest, SCon{Chr{Response.fold(byte)}, reversed})

def encodedKey(result: Result<&2, &2, Name.Error, List<&2, U32>>) -> Result<&2, &2, Error, String>:
  match result:
    case Fail{error}: Fail{InvalidName{error}}
    case Done{bytes}: Done{keyBytes(bytes, SNil{})}

def nameKey(name: Name.Name) -> Result<&2, &2, Error, String>:
  encodedKey(Name.encode(name))

def addFound(key: String, record: Message.Record, pair: Map<&2, List<&2, Message.Record>> & List<&2, Message.Record>) -> Index:
  match pair:
    case (records, previous): Index{Map.set(&2, List<&2, Message.Record>, records, key, record <> previous)}

def addKey(index: Index, record: Message.Record, result: Result<&2, &2, Error, String>) -> Result<&2, &2, Error, Index>:
  match index result:
    case Index{records} Fail{error}: Fail{error}
    case Index{records} Done{+key}: Done{addFound(key, record, Map.get(List<&2, Message.Record>, Nil{}, records, key))}

def add(index: Index, record: Message.Record) -> Result<&2, &2, Error, Index>:
  match record:
    case Message.Record{+name, kind, 1, ttl, start, length}: addKey(index, Message.Record{name, kind, 1, ttl, start, length}, nameKey(name))
    case _: Done{index}

def indexed(records: List<&2, Message.Record>, result: Result<&2, &2, Error, Index>) -> Result<&2, &2, Error, Index>:
  match records result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case record <> rest Done{index}: indexed(rest, add(index, record))

def aliasChecked(equal: Bool, alias: Name.Name, addresses: List<&2, Address>, hasAddress: Bool) -> Result<&2, &2, Error, Node>:
  match equal:
    case True{}: Done{Node{Some{alias}, addresses, hasAddress}}
    case False{}: Fail{ConflictingAlias{}}

def addAlias(target: Name.Name, node: Node) -> Result<&2, &2, Error, Node>:
  match node:
    case Node{None{}, addresses, hasAddress}: Done{Node{Some{target}, addresses, hasAddress}}
    case Node{Some{+previous}, addresses, hasAddress}: aliasChecked(Response.sameName(previous, target), previous, addresses, hasAddress)

def addressValue(wanted: U32, ttl: U32, node: Node, value: Record.Value) -> Result<&2, &2, Error, Node>:
  match wanted node value:
    case 1 Node{alias, addresses, _} Record.A{address}: Done{Node{alias, V4{address, ttl} <> addresses, True{}}}
    case 28 Node{alias, addresses, _} Record.AAAA{address}: Done{Node{alias, V6{address, ttl} <> addresses, True{}}}
    case _ node _: Done{node}

def decoded(wanted: U32, ttl: U32, node: Node, result: Result<&2, &2, Record.Error, Record.Value>) -> Result<&2, &2, Error, Node>:
  match result:
    case Fail{error}: Fail{InvalidRecord{error}}
    case Done{Record.CNAME{target}}: addAlias(target, node)
    case Done{value}: addressValue(wanted, ttl, node, value)

def otherAddress(node: Node) -> Result<&2, &2, Error, Node>:
  match node:
    case Node{alias, addresses, _}: Done{Node{alias, addresses, True{}}}

def relevant(selected: Bool, address: Bool, wanted: U32, packet: Name.Packet, ttl: U32, record: Message.Record, node: Node) -> Result<&2, &2, Error, Node>:
  match selected address:
    case True{} _: decoded(wanted, ttl, node, Record.decode(packet, record))
    case False{} True{}: otherAddress(node)
    case False{} False{}: Done{node}

def inspect(+wanted: U32, packet: Name.Packet, node: Node, record: Message.Record) -> Result<&2, &2, Error, Node>:
  match record:
    case Message.Record{name, +kind, class, +ttl, start, length}: relevant(U32.is_eq(kind, wanted) || U32.is_eq(kind, 5), U32.is_eq(kind, 1) || U32.is_eq(kind, 28), wanted, packet, ttl, Message.Record{name, kind, class, ttl, start, length}, node)

def scan(records: List<&2, Message.Record>, +wanted: U32, +packet: Name.Packet, result: Result<&2, &2, Error, Node>) -> Result<&2, &2, Error, Node>:
  match records result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case record <> rest Done{node}: scan(rest, wanted, packet, inspect(wanted, packet, node, record))

def nodeResult(current: Name.Name, value: Result<&2, &2, Error, Node>) -> Step:
  match value:
    case Fail{error}: Complete{Fail{error}}
    case Done{Node{None{}, addresses, _}}: Complete{Done{Selection{current, List.reverse(&2, Address, addresses)}}}
    case Done{Node{Some{target}, _, False{}}}: Follow{target}
    case Done{Node{Some{_}, _, True{}}}: Complete{Fail{ConflictingAlias{}}}

def found(current: Name.Name, wanted: U32, packet: Name.Packet, pair: Map<&2, List<&2, Message.Record>> & List<&2, Message.Record>) -> Step:
  match pair:
    case (_, records): nodeResult(current, scan(List.reverse(&2, Message.Record, records), wanted, packet, Done{Node{None{}, Nil{}, False{}}}))

def selectNode(index: Index, current: Name.Name, wanted: U32, packet: Name.Packet, key: String) -> Step:
  match index:
    case Index{records}: found(current, wanted, packet, Map.get(List<&2, Message.Record>, Nil{}, records, key))

def advanced(key: String, seen: Map<&2, Bool>, state: Step) -> Advance:
  match state:
    case Follow{target}: Advance{Map.set(&2, Bool, seen, key, True{}), Follow{target}}
    case Complete{result}: Advance{seen, Complete{result}}

def visited(index: Index, current: Name.Name, wanted: U32, packet: Name.Packet, +key: String, pair: Map<&2, Bool> & Bool) -> Advance:
  match pair:
    case (seen, True{}): Advance{seen, Complete{Fail{AliasLoop{}}}}
    case (seen, False{}): advanced(key, seen, selectNode(index, current, wanted, packet, key))

def locate(index: Index, current: Name.Name, wanted: U32, packet: Name.Packet, seen: Map<&2, Bool>, result: Result<&2, &2, Error, String>) -> Advance:
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
def walk(fuel: Nat, +index: Index, +packet: Name.Packet, +wanted: U32, progress: Advance) -> Result<&2, &2, Error, Trace>:
  match fuel progress:
    case _ Advance{seen, Complete{result}}: traced(seen, result)
    case Zero{} Advance{_, Follow{_}}: Fail{AliasLoop{}}
    case Succ{rest} Advance{seen, Follow{+current}}: walk(rest, index, packet, wanted, locate(index, current, wanted, packet, seen, nameKey(current)))

def prepared(history: History, fuel: Nat, packet: Name.Packet, wanted: U32, name: Name.Name, result: Result<&2, &2, Error, Index>) -> Result<&2, &2, Error, Trace>:
  match history result:
    case _ Fail{error}: Fail{error}
    case History{seen} Done{index}: walk(fuel, index, packet, wanted, Advance{seen, Follow{name}})

def chooseRecords(history: History, valid: Bool, wanted: U32, name: Name.Name, packet: Name.Packet, +answers: List<&2, Message.Record>) -> Result<&2, &2, Error, Trace>:
  match valid:
    case False{}: Fail{UnsupportedType{}}
    case True{}: prepared(history, Succ{List.length(&2, Message.Record, answers)}, packet, wanted, name, indexed(answers, Done{Index{Map.new(&2, List<&2, Message.Record>)}}))

def selectResponse(history: History, code: U32, +wanted: U32, name: Name.Name, packet: Name.Packet, answers: List<&2, Message.Record>) -> Result<&2, &2, Error, Trace>:
  match code:
    case 0: chooseRecords(history, U32.is_eq(wanted, 1) || U32.is_eq(wanted, 28), wanted, name, packet, answers)
    case code: Fail{ResponseCode{code}}

def selectExtension(history: History, wanted: U32, name: Name.Name, message: Message.Message, extension: Result<&2, &2, Edns.Error, Maybe<&2, Edns.Response>>) -> Result<&2, &2, Error, Trace>:
  match message extension:
    case _ Fail{error}: Fail{InvalidExtension{error}}
    case Message.Message{packet, header, _, answers, _, _} Done{value}: selectResponse(history, Edns.responseCode(header, value), wanted, name, packet, answers)

# Input is a matched, complete response. Only IN answer records contribute;
# authority/additional data is never promoted to address answers. Empty output
# is not proof of a cacheable negative answer. TTLs remain raw wire values;
# normalization, negative/alias caching and follow-up queries are separate.
def selectWithHistory(history: History, +wanted: U32, name: Name.Name, +message: Message.Message) -> Result<&2, &2, Error, Trace>:
  selectExtension(history, wanted, name, message, Edns.inspect(message))


def selectionOnly(result: Result<&2, &2, Error, Trace>) -> Result<&2, &2, Error, Selection>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Trace{selection, _}}: Done{selection}

def select(wanted: U32, name: Name.Name, message: Message.Message) -> Result<&2, &2, Error, Selection>:
  selectionOnly(selectWithHistory(newHistory(), wanted, name, message))
