import Base
import ./dns-name.bend as Name
import ./dns-message.bend as Message
import ./url-ipv4.bend as IPv4
import ./url-ipv6.bend as IPv6

# Typed IN records needed by address resolution. Unknown kinds/classes retain
# their original record/span, rather than interpreting class-specific bytes.
type Value is Data:
  A{address: IPv4.Address}
  AAAA{address: IPv6.Address}
  CNAME{target: Name.Name}
  NS{target: Name.Name}
  PTR{target: Name.Name}
  SOA{primary: Name.Name, mailbox: Name.Name, serial: U32, refresh: U32, retry: U32, expire: U32, minimum: U32}
  Opaque{record: Message.Record}

type Error is Data:
  InvalidSpan{}
  InvalidLength{}
  InvalidName{error: Name.Error}

def integer(+packet: Name.Packet, +start: U32) -> U32:
  (Message.word(packet, start) * 65536 + Message.word(packet, (start + 2 : U32)) : U32)

def address4(valid: Bool, packet: Name.Packet, start: U32) -> Result<&2, &2, Error, Value>:
  match valid:
    case False{}: Fail{InvalidLength{}}
    case True{}: Done{A{IPv4.Address{integer(packet, start)}}}

def address6(valid: Bool, +packet: Name.Packet, +start: U32) -> Result<&2, &2, Error, Value>:
  match valid:
    case False{}: Fail{InvalidLength{}}
    case True{}: Done{AAAA{IPv6.Address{integer(packet, start), integer(packet, (start + 4 : U32)), integer(packet, (start + 8 : U32)), integer(packet, (start + 12 : U32))}}}

def named(kind: U32, target: Name.Name) -> Value:
  match kind:
    case 5: CNAME{target}
    case 2: NS{target}
    case _: PTR{target}

def exactName(valid: Bool, kind: U32, target: Name.Name) -> Result<&2, &2, Error, Value>:
  match valid:
    case False{}: Fail{InvalidLength{}}
    case True{}: Done{named(kind, target)}

def nameResult(kind: U32, end: U32, result: Result<&2, &2, Name.Error, Name.Decoded>) -> Result<&2, &2, Error, Value>:
  match result:
    case Fail{error}: Fail{InvalidName{error}}
    case Done{Name.Decoded{target, next}}: exactName(U32.is_eq(next, end), kind, target)

def soaFields(valid: Bool, +packet: Name.Packet, primary: Name.Name, mailbox: Name.Name, +start: U32) -> Result<&2, &2, Error, Value>:
  match valid:
    case False{}: Fail{InvalidLength{}}
    case True{}: Done{SOA{primary, mailbox, integer(packet, start), integer(packet, (start + 4 : U32)), integer(packet, (start + 8 : U32)), integer(packet, (start + 12 : U32)), integer(packet, (start + 16 : U32))}}

def soaMailbox(packet: Name.Packet, primary: Name.Name, end: U32, result: Result<&2, &2, Name.Error, Name.Decoded>) -> Result<&2, &2, Error, Value>:
  match result:
    case Fail{error}: Fail{InvalidName{error}}
    case Done{Name.Decoded{mailbox, +next}}: soaFields(U32.is_eq((next + 20 : U32), end), packet, primary, mailbox, next)

def soaMore(valid: Bool, +packet: Name.Packet, primary: Name.Name, end: U32, next: U32) -> Result<&2, &2, Error, Value>:
  match valid:
    case False{}: Fail{InvalidLength{}}
    case True{}: soaMailbox(packet, primary, end, Name.decode(packet, next))

def soaPrimary(packet: Name.Packet, +end: U32, result: Result<&2, &2, Name.Error, Name.Decoded>) -> Result<&2, &2, Error, Value>:
  match result:
    case Fail{error}: Fail{InvalidName{error}}
    case Done{Name.Decoded{primary, +next}}: soaMore(U32.is_lt(next, end), packet, primary, end, next)

def kindFields(+packet: Name.Packet, kind: U32, +start: U32, +length: U32, original: Message.Record) -> Result<&2, &2, Error, Value>:
  match kind:
    case 1: address4(U32.is_eq(length, 4), packet, start)
    case 28: address6(U32.is_eq(length, 16), packet, start)
    case 5: nameResult(5, (start + length : U32), Name.decode(packet, start))
    case 2: nameResult(2, (start + length : U32), Name.decode(packet, start))
    case 12: nameResult(12, (start + length : U32), Name.decode(packet, start))
    case 6: soaPrimary(packet, (start + length : U32), Name.decode(packet, start))
    case _: Done{Opaque{original}}

def classFields(class: U32, packet: Name.Packet, kind: U32, start: U32, length: U32, original: Message.Record) -> Result<&2, &2, Error, Value>:
  match class:
    case 1: kindFields(packet, kind, start, length, original)
    case _: Done{Opaque{original}}

def fields(packet: Name.Packet, record: Message.Record) -> Result<&2, &2, Error, Value>:
  match record:
    case Message.Record{name, +kind, +class, ttl, +start, +length}: classFields(class, packet, kind, start, length, Message.Record{name, kind, class, ttl, start, length})

def checked(valid: Bool, packet: Name.Packet, record: Message.Record) -> Result<&2, &2, Error, Value>:
  match valid:
    case False{}: Fail{InvalidSpan{}}
    case True{}: fields(packet, record)

# Validate even manually constructed spans. Message.parse already checks them,
# but callers may supply a record independently. Unknown data stays opaque.
def decode(+packet: Name.Packet, record: Message.Record) -> Result<&2, &2, Error, Value>:
  match record:
    case Message.Record{name, kind, class, ttl, +start, +length}: checked(Message.available(packet, start, length), packet, Message.Record{name, kind, class, ttl, start, length})
