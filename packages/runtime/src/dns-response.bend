import Base
import ./dns-name.bend as Name
import ./dns-message.bend as Message
import ./url-ipv4.bend as IPv4
import ./url-ipv6.bend as IPv6

type Address is Data:
  V4{value: IPv4.Address}
  V6{value: IPv6.Address, scope: U32}

type Endpoint is Data:
  Endpoint{address: Address, port: U32}

# Source/destination are the actual selected endpoints, not wildcard bind
# addresses. Transport must report observed endpoints from its socket metadata.
type Transaction is Data:
  Transaction{source: Endpoint, destination: Endpoint, id: U32, opcode: U32, question: Message.Question}

type Rejection is Data:
  EndpointMismatch{}
  IdMismatch{}
  NotResponse{}
  OpcodeMismatch{}
  QuestionCountMismatch{}
  QuestionMismatch{}
  Malformed{error: Message.Error}

type Decision is Data:
  Ignore{reason: Rejection}
  Truncated{header: Message.Header}
  Matched{message: Message.Message}

def sameAddress(left: Address, right: Address) -> Bool:
  match left right:
    case V4{IPv4.Address{a}} V4{IPv4.Address{b}}: U32.is_eq(a, b)
    case V6{IPv6.Address{a, b, c, d}, scope} V6{IPv6.Address{e, f, g, h}, otherScope}: U32.is_eq(a, e) && U32.is_eq(b, f) && U32.is_eq(c, g) && U32.is_eq(d, h) && U32.is_eq(scope, otherScope)
    case _ _: False{}

def sameEndpoint(left: Endpoint, right: Endpoint) -> Bool:
  match left right:
    case Endpoint{a, ap} Endpoint{b, bp}: U32.is_eq(ap, bp) && sameAddress(a, b)

# DNS case insensitivity folds ASCII letters only. Label boundaries, zero
# octets and all non-ASCII bytes remain significant; no Unicode case mapping.
def folded(upper: Bool, value: U32) -> U32:
  match upper:
    case True{}: (value + 32 : U32)
    case False{}: value

def fold(+value: U32) -> U32:
  folded(U32.is_ge(value, 65) && U32.is_le(value, 90), value)

def sameLabel(left: List<&2, U32>, right: List<&2, U32>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> restA b <> restB: U32.is_eq(fold(a), fold(b)) && sameLabel(restA, restB)
    case _ _: False{}

def sameLabels(left: List<&2, List<&2, U32>>, right: List<&2, List<&2, U32>>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> restA b <> restB: sameLabel(a, b) && sameLabels(restA, restB)
    case _ _: False{}

def sameName(left: Name.Name, right: Name.Name) -> Bool:
  match left right:
    case Name.Name{a} Name.Name{b}: sameLabels(a, b)

def sameQuestion(left: Message.Question, right: Message.Question) -> Bool:
  match left right:
    case Message.Question{a, at, ac} Message.Question{b, bt, bc}: U32.is_eq(at, bt) && U32.is_eq(ac, bc) && sameName(a, b)

def parsed(value: Result<&2, &2, Message.Error, Message.Message>) -> Decision:
  match value:
    case Fail{error}: Ignore{Malformed{error}}
    case Done{message}: Matched{message}

def matched(truncated: Bool, packet: Name.Packet, header: Message.Header) -> Decision:
  match truncated:
    case True{}: Truncated{header}
    case False{}: parsed(Message.withHeader(packet, Done{header}))

def questionMatches(equal: Bool, packet: Name.Packet, header: Message.Header, flags: U32) -> Decision:
  match equal:
    case False{}: Ignore{QuestionMismatch{}}
    case True{}: matched(U32.is_ne(U32.and(flags, 512), 0), packet, header)

def checkedQuestion(packet: Name.Packet, header: Message.Header, flags: U32, expected: Message.Question, value: Result<&2, &2, Message.Error, Message.Parsed<Message.Question>>) -> Decision:
  match value:
    case Fail{error}: Ignore{Malformed{error}}
    case Done{Message.Parsed{actual, _}}: questionMatches(sameQuestion(expected, actual), packet, header, flags)

def absentQuestion(allowed: Bool, packet: Name.Packet, header: Message.Header, flags: U32) -> Decision:
  match allowed:
    case False{}: Ignore{QuestionCountMismatch{}}
    case True{}: matched(U32.is_ne(U32.and(flags, 512), 0), packet, header)

def questionCount(optional: Bool, count: U32, +packet: Name.Packet, header: Message.Header, flags: U32, expected: Message.Question) -> Decision:
  match count:
    case 0: absentQuestion(optional, packet, header, flags)
    case 1: checkedQuestion(packet, header, flags, expected, Message.question(packet, 12))
    case _: Ignore{QuestionCountMismatch{}}

def checkedHeader(equalId: Bool, response: Bool, equalOpcode: Bool, optional: Bool, count: U32, packet: Name.Packet, header: Message.Header, flags: U32, expected: Message.Question) -> Decision:
  match equalId response equalOpcode:
    case False{} _ _: Ignore{IdMismatch{}}
    case True{} False{} _: Ignore{NotResponse{}}
    case True{} True{} False{}: Ignore{OpcodeMismatch{}}
    case True{} True{} True{}: questionCount(optional, count, packet, header, flags, expected)

def header(optional: Bool, packet: Name.Packet, id: U32, opcode: U32, expected: Message.Question, result: Result<&2, &2, Message.Error, Message.Header>) -> Decision:
  match result:
    case Fail{error}: Ignore{Malformed{error}}
    case Done{Message.Header{+actualId, +flags, +qd, an, ns, ar}}: checkedHeader(U32.is_eq(id, actualId), U32.is_ne(U32.and(flags, 32768), 0), U32.is_eq(opcode, (flags / 2048 % 16 : U32)), optional, qd, packet, Message.Header{actualId, flags, qd, an, ns, ar}, flags, expected)

def packet(optional: Bool, id: U32, opcode: U32, expected: Message.Question, value: Result<&2, &2, Name.Error, Name.Packet>) -> Decision:
  match value:
    case Fail{error}: Ignore{Malformed{Message.NameError{error}}}
    case Done{+messagePacket}: header(optional, messagePacket, id, opcode, expected, Message.header(messagePacket))

def endpoints(equal: Bool, optional: Bool, id: U32, opcode: U32, expected: Message.Question, wire: List<&2, U32>) -> Decision:
  match equal:
    case False{}: Ignore{EndpointMismatch{}}
    case True{}: packet(optional, id, opcode, expected, Name.packet(wire))

def inspectPolicy(optional: Bool, transaction: Transaction, source: Endpoint, destination: Endpoint, wire: List<&2, U32>) -> Decision:
  match transaction:
    case Transaction{sentFrom, sentTo, id, opcode, expected}: endpoints(sameEndpoint(sentTo, source) && sameEndpoint(sentFrom, destination), optional, id, opcode, expected, wire)

# Datagram matching requires the complete question, including before accepting
# a truncation indication. Matching never grants trust to unrelated answers.
def inspect(transaction: Transaction, source: Endpoint, destination: Endpoint, wire: List<&2, U32>) -> Decision:
  inspectPolicy(False{}, transaction, source, destination, wire)

# RFC 7766 section 7 allows an absent question on the established TCP stream.
# If present it must match. ID/opcode/endpoints and complete-message validation
# still apply; a zero-question response is not rewritten to invent a question.
def inspectStream(transaction: Transaction, source: Endpoint, destination: Endpoint, wire: List<&2, U32>) -> Decision:
  inspectPolicy(True{}, transaction, source, destination, wire)
