import Base
import ./dns-name.bend as Name
import ./dns-message.bend as Message
import ./dns-edns.bend as Edns

# RFC 6891 metadata. Preserve unknown flags, versions and opaque options;
# negotiation and option interpretation belong to the resolver policy.
type Response is Data:
  Response{payloadSize: U32, extendedCode: U32, version: U32, flags: U32, options: List<&2, Edns.Option>}

type Error is Data:
  Misplaced{}
  Duplicate{}
  InvalidOwner{}
  InvalidField{}
  TruncatedOption{}

type Options is Data:
  Complete{values: List<&2, Edns.Option>}
  Options{position: U32, remaining: U32, reversed: List<&2, Edns.Option>}

def copyBytes(count: Nat, +packet: Name.Packet, +position: U32, reversed: List<&2, U32>) -> List<&2, U32>:
  match count:
    case Zero{}: List.reverse(&2, U32, reversed)
    case Succ{rest}: copyBytes(rest, packet, (position + 1 : U32), Name.byte(packet, position) <> reversed)

def progress(empty: Bool, position: U32, remaining: U32, reversed: List<&2, Edns.Option>) -> Options:
  match empty:
    case True{}: Complete{List.reverse(&2, Edns.Option, reversed)}
    case False{}: Options{position, remaining, reversed}

def optionData(valid: Bool, packet: Name.Packet, +position: U32, +remaining: U32, code: U32, +length: U32, reversed: List<&2, Edns.Option>) -> Result<&2, &2, Error, Options>:
  match valid:
    case False{}: Fail{TruncatedOption{}}
    case True{}: Done{progress(U32.is_eq(remaining, length), (position + length : U32), (remaining - length : U32), Edns.Option{code, copyBytes(U32.to_nat(length), packet, position, Nil{})} <> reversed)}

def optionHeader(valid: Bool, +packet: Name.Packet, +position: U32, +remaining: U32, reversed: List<&2, Edns.Option>) -> Result<&2, &2, Error, Options>:
  match valid:
    case False{}: Fail{TruncatedOption{}}
    case True{}:
      +length = Message.word(packet, (position + 2 : U32))
      optionData(U32.is_le(length, (remaining - 4 : U32)), packet, (position + 4 : U32), (remaining - 4 : U32), Message.word(packet, position), length, reversed)

def optionLoop(fuel: Nat, +packet: Name.Packet, state: Result<&2, &2, Error, Options>) -> Result<&2, &2, Error, List<&2, Edns.Option>>:
  match fuel state:
    case _ Fail{error}: Fail{error}
    case _ Done{Complete{values}}: Done{values}
    case Zero{} _: Fail{TruncatedOption{}}
    case Succ{rest} Done{Options{position, +remaining, reversed}}: optionLoop(rest, packet, optionHeader(U32.is_le(4, remaining), packet, position, remaining, reversed))

def metadata(payloadSize: U32, +ttl: U32, result: Result<&2, &2, Error, List<&2, Edns.Option>>) -> Result<&2, &2, Error, Response>:
  match result:
    case Fail{error}: Fail{error}
    case Done{values}: Done{Response{payloadSize, (ttl / 16777216 : U32), (ttl / 65536 % 256 : U32), (ttl % 65536 : U32), values}}

def bounded(valid: Bool, packet: Name.Packet, payloadSize: U32, ttl: U32, start: U32, +length: U32) -> Result<&2, &2, Error, Response>:
  match valid:
    case False{}: Fail{InvalidField{}}
    case True{}: metadata(payloadSize, ttl, optionLoop(U32.to_nat((length / 4 : U32)), packet, Done{progress(U32.is_eq(length, 0), start, length, Nil{})}))

# Packet must come from Name.packet/Message.parse. Check the public record's
# span before computing its end, so even U32-sized invalid spans cannot wrap.
def decode(+packet: Name.Packet, value: Message.Record) -> Result<&2, &2, Error, Response>:
  match value:
    case Message.Record{Name.Name{Nil{}}, +recordType, +class, ttl, +start, +length}:
      bounded(U32.is_eq(recordType, 41) && U32.is_le(class, 65535) && U32.is_le(length, 65535) && Message.available(packet, start, length), packet, class, ttl, start, length)
    case _: Fail{InvalidOwner{}}

def hasOpt(values: List<&2, Message.Record>) -> Bool:
  match values:
    case Nil{}: False{}
    case Message.Record{_, code, _, _, _, _} <> rest: U32.is_eq(code, 41) || hasOpt(rest)

def optional(result: Result<&2, &2, Error, Response>) -> Result<&2, &2, Error, Maybe<&2, Response>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{response}: Done{Some{response}}

def selected(isOpt: Bool, packet: Name.Packet, value: Message.Record, prior: Result<&2, &2, Error, Maybe<&2, Response>>) -> Result<&2, &2, Error, Maybe<&2, Response>>:
  match isOpt prior:
    case _ Fail{error}: Fail{error}
    case False{} prior: prior
    case True{} Done{Some{_}}: Fail{Duplicate{}}
    case True{} Done{None{}}: optional(decode(packet, value))

def kind(value: Message.Record) -> U32:
  match value:
    case Message.Record{_, code, _, _, _, _}: code

def scan(+packet: Name.Packet, values: List<&2, Message.Record>, state: Result<&2, &2, Error, Maybe<&2, Response>>) -> Result<&2, &2, Error, Maybe<&2, Response>>:
  match values state:
    case _ Fail{error}: Fail{error}
    case Nil{} state: state
    case +value <> rest state: scan(packet, rest, selected(U32.is_eq(kind(value), 41), packet, value, state))

def placement(invalid: Bool, packet: Name.Packet, values: List<&2, Message.Record>) -> Result<&2, &2, Error, Maybe<&2, Response>>:
  match invalid:
    case True{}: Fail{Misplaced{}}
    case False{}: scan(packet, values, Done{None{}})

# OPT may appear anywhere in additional, but nowhere else and at most once.
def inspect(message: Message.Message) -> Result<&2, &2, Error, Maybe<&2, Response>>:
  match message:
    case Message.Message{packet, _, _, answers, authorities, additional}: placement(hasOpt(answers) || hasOpt(authorities), packet, additional)

def responseCode(header: Message.Header, extension: Maybe<&2, Response>) -> U32:
  match header extension:
    case Message.Header{_, flags, _, _, _, _} None{}: (flags % 16 : U32)
    case Message.Header{_, flags, _, _, _, _} Some{Response{_, upper, _, _, _}}: (upper * 16 + flags % 16 : U32)

def dnssecOk(value: Response) -> Bool:
  match value:
    case Response{_, _, _, flags, _}: U32.is_le(32768, flags)
