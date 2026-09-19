import Base
import ./dns-name.bend as Name

# Wire structure only. Transaction matching and record-specific interpretation
# belong to the resolver; retain unknown flags, classes and record types.
type Header is Data:
  Header{id: U32, flags: U32, questions: U32, answers: U32, authorities: U32, additional: U32}

type Question is Data:
  Question{name: Name.Name, kind: U32, class: U32}

# RDATA stays a span in the original immutable packet. Compression offsets
# inside CNAME/SOA/etc. remain meaningful; opaque record types stay lossless.
type Record is Data:
  Record{name: Name.Name, kind: U32, class: U32, ttl: U32, start: U32, length: U32}

type Message is Data:
  Message{packet: Name.Packet, header: Header, questions: List<&2, Question>, answers: List<&2, Record>, authorities: List<&2, Record>, additional: List<&2, Record>}

type Parsed<-Item: Data> is Data:
  Parsed{value: Item, next: U32}

type Error is Data:
  NameError{error: Name.Error}
  Truncated{}
  TrailingData{}
  InvalidField{}

def size(packet: Name.Packet) -> U32:
  match packet:
    case Name.Packet{packetSize, _}: packetSize

def available(+packet: Name.Packet, +position: U32, count: U32) -> Bool:
  U32.is_le(position, size(packet)) && U32.is_le(count, (size(packet) - position : U32))

# Call only after validating the containing fixed-size field.
def word(+packet: Name.Packet, +position: U32) -> U32:
  (Name.byte(packet, position) * 256 + Name.byte(packet, (position + 1 : U32)) : U32)

def headerFields(valid: Bool, +packet: Name.Packet) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{Truncated{}}
    case True{}: Done{Header{word(packet, 0), word(packet, 2), word(packet, 4), word(packet, 6), word(packet, 8), word(packet, 10)}}

def header(+packet: Name.Packet) -> Result<&2, &2, Error, Header>:
  headerFields(available(packet, 0, 12), packet)

def questionFields(valid: Bool, +packet: Name.Packet, name: Name.Name, +position: U32) -> Result<&2, &2, Error, Parsed<Question>>:
  match valid:
    case False{}: Fail{Truncated{}}
    case True{}: Done{Parsed{Question{name, word(packet, position), word(packet, (position + 2 : U32))}, (position + 4 : U32)}}

def questionName(+packet: Name.Packet, value: Result<&2, &2, Name.Error, Name.Decoded>) -> Result<&2, &2, Error, Parsed<Question>>:
  match value:
    case Fail{error}: Fail{NameError{error}}
    case Done{Name.Decoded{name, +next}}: questionFields(available(packet, next, 4), packet, name, next)

def question(+packet: Name.Packet, position: U32) -> Result<&2, &2, Error, Parsed<Question>>:
  questionName(packet, Name.decode(packet, position))

def recordData(valid: Bool, name: Name.Name, kind: U32, class: U32, ttl: U32, +start: U32, +length: U32) -> Result<&2, &2, Error, Parsed<Record>>:
  match valid:
    case False{}: Fail{Truncated{}}
    case True{}: Done{Parsed{Record{name, kind, class, ttl, start, length}, (start + length : U32)}}

def recordFields(valid: Bool, +packet: Name.Packet, name: Name.Name, +position: U32) -> Result<&2, &2, Error, Parsed<Record>>:
  match valid:
    case False{}: Fail{Truncated{}}
    case True{}:
      +length = word(packet, (position + 8 : U32))
      +start = (position + 10 : U32)
      recordData(available(packet, start, length), name, word(packet, position), word(packet, (position + 2 : U32)), (word(packet, (position + 4 : U32)) * 65536 + word(packet, (position + 6 : U32)) : U32), start, length)

def recordName(+packet: Name.Packet, value: Result<&2, &2, Name.Error, Name.Decoded>) -> Result<&2, &2, Error, Parsed<Record>>:
  match value:
    case Fail{error}: Fail{NameError{error}}
    case Done{Name.Decoded{name, +next}}: recordFields(available(packet, next, 10), packet, name, next)

def record(+packet: Name.Packet, position: U32) -> Result<&2, &2, Error, Parsed<Record>>:
  recordName(packet, Name.decode(packet, position))

def added(-Item: Data, reversed: List<&2, Item>, value: Result<&2, &2, Error, Parsed<Item>>) -> Result<&2, &2, Error, Parsed<List<&2, Item>>>:
  match value:
    case Fail{error}: Fail{error}
    case Done{Parsed{item, next}}: Done{Parsed{item <> reversed, next}}

# Parser callbacks are pure values. Section counts guide traversal but never
# authorize reading beyond the packet; malformed counts stop at the first error.
def section(~Item: Data, ~parse: (Name.Packet -> U32 -> Result<&2, &2, Error, Parsed<Item>>), count: Nat, +packet: Name.Packet, state: Result<&2, &2, Error, Parsed<List<&2, Item>>>) -> Result<&2, &2, Error, Parsed<List<&2, Item>>>:
  match count state:
    case _ Fail{error}: Fail{error}
    case Zero{} Done{Parsed{reversed, next}}: Done{Parsed{List.reverse(&2, Item, reversed), next}}
    case Succ{rest} Done{Parsed{reversed, next}}: section(~Item, ~parse, rest, packet, added(Item, reversed, parse(packet, next)))

def complete(valid: Bool, packet: Name.Packet, header: Header, questions: List<&2, Question>, answers: List<&2, Record>, authorities: List<&2, Record>, additional: List<&2, Record>) -> Result<&2, &2, Error, Message>:
  match valid:
    case False{}: Fail{TrailingData{}}
    case True{}: Done{Message{packet, header, questions, answers, authorities, additional}}

def additionals(+packet: Name.Packet, header: Header, questions: List<&2, Question>, answers: List<&2, Record>, authorities: List<&2, Record>, result: Result<&2, &2, Error, Parsed<List<&2, Record>>>) -> Result<&2, &2, Error, Message>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Parsed{additional, next}}: complete(U32.is_eq(size(packet), next), packet, header, questions, answers, authorities, additional)

def authorities(+packet: Name.Packet, header: Header, count: U32, questions: List<&2, Question>, answers: List<&2, Record>, result: Result<&2, &2, Error, Parsed<List<&2, Record>>>) -> Result<&2, &2, Error, Message>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Parsed{values, next}}: additionals(packet, header, questions, answers, values, section(~Record, ~(p => i => record(p, i)), U32.to_nat(count), packet, Done{Parsed{Nil{}, next}}))

def answers(+packet: Name.Packet, header: Header, authorityCount: U32, additionalCount: U32, questions: List<&2, Question>, result: Result<&2, &2, Error, Parsed<List<&2, Record>>>) -> Result<&2, &2, Error, Message>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Parsed{values, next}}: authorities(packet, header, additionalCount, questions, values, section(~Record, ~(p => i => record(p, i)), U32.to_nat(authorityCount), packet, Done{Parsed{Nil{}, next}}))

def questions(+packet: Name.Packet, header: Header, answerCount: U32, authorityCount: U32, additionalCount: U32, result: Result<&2, &2, Error, Parsed<List<&2, Question>>>) -> Result<&2, &2, Error, Message>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Parsed{values, next}}: answers(packet, header, authorityCount, additionalCount, values, section(~Record, ~(p => i => record(p, i)), U32.to_nat(answerCount), packet, Done{Parsed{Nil{}, next}}))

def withHeader(+packet: Name.Packet, value: Result<&2, &2, Error, Header>) -> Result<&2, &2, Error, Message>:
  match value:
    case Fail{error}: Fail{error}
    case Done{Header{id, flags, +qd, +an, +ns, +ar}}: questions(packet, Header{id, flags, qd, an, ns, ar}, an, ns, ar, section(~Question, ~(p => i => question(p, i)), U32.to_nat(qd), packet, Done{Parsed{Nil{}, 12}}))

def fromPacket(value: Result<&2, &2, Name.Error, Name.Packet>) -> Result<&2, &2, Error, Message>:
  match value:
    case Fail{error}: Fail{NameError{error}}
    case Done{+packet}: withHeader(packet, header(packet))

def parse(bytes: List<&2, U32>) -> Result<&2, &2, Error, Message>:
  fromPacket(Name.packet(bytes))

# Uncompressed single-question query. Caller supplies transaction ID and flags
# (e.g. recursion desired); validation/matching policy remains explicit above.
def u16(+value: U32, tail: List<&2, U32>) -> List<&2, U32>:
  (value / 256 : U32) <> (value % 256 : U32) <> tail

def queryName(id: U32, flags: U32, kind: U32, class: U32, encoded: Result<&2, &2, Name.Error, List<&2, U32>>) -> Result<&2, &2, Error, List<&2, U32>>:
  match encoded:
    case Fail{error}: Fail{NameError{error}}
    case Done{bytes}: Done{u16(id, u16(flags, 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> List.append(&2, U32, bytes, u16(kind, u16(class, Nil{})))))}

def queryFields(valid: Bool, id: U32, flags: U32, question: Question) -> Result<&2, &2, Error, List<&2, U32>>:
  match valid question:
    case False{} _: Fail{InvalidField{}}
    case True{} Question{name, kind, class}: queryName(id, flags, kind, class, Name.encode(name))

def query(+id: U32, +flags: U32, question: Question) -> Result<&2, &2, Error, List<&2, U32>>:
  match question:
    case Question{name, +kind, +class}: queryFields(U32.is_le(id, 65535) && U32.is_le(flags, 65535) && U32.is_le(kind, 65535) && U32.is_le(class, 65535), id, flags, Question{name, kind, class})
