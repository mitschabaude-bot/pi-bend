import Base
import ./url.bend as IPv4
import ./url.bend as IPv6
import ./utf8.bend as UTF8
import ./io-pair.bend as Pair

# DNS labels are octet strings, not Unicode text. Names include an implicit
# terminal root; an empty list denotes that root. Preserve spelling and case.
type Name is Data:
  Name{labels: List<&2, List<&2, U32>>}

type DomainNameError is Data:
  NameInvalidByte{}
  InvalidLabel{}
  NameTooLong{}
  PacketTooLong{}
  NameTruncated{}
  ReservedLabel{}
  InvalidPointer{}

type Packet is Data:
  Packet{sizeLocal: U32, bytes: Map<&2, U32>}

def key(+index: U32) -> String:
  SCon{Chr{(index / 256 : U32)}, SCon{Chr{(index % 256 : U32)}, SNil{}}}

def inserted(valid: Bool, +index: U32, byteLocal: U32, bytes: Map<&2, U32>) -> Result<&2, &2, DomainNameError, Packet>:
  match valid:
    case False{}: Fail{NameInvalidByte{}}
    case True{}: Done{Packet{(index + 1 : U32), Map.set(&2, U32, bytes, key(index), byteLocal)}}

def insert(result: Result<&2, &2, DomainNameError, Packet>, +byteLocal: U32) -> Result<&2, &2, DomainNameError, Packet>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Packet{65535, _}}: Fail{PacketTooLong{}}
    case Done{Packet{index, bytes}}: inserted(U32.is_le(byteLocal, 255), index, byteLocal, bytes)

# An immutable offset index avoids scanning the packetLocal for each pointer.
def packetLoop(input: List<&2, U32>, result: Result<&2, &2, DomainNameError, Packet>) -> Result<&2, &2, DomainNameError, Packet>:
  match input result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case value <> rest packetLocal: packetLoop(rest, insert(packetLocal, value))

def packet(input: List<&2, U32>) -> Result<&2, &2, DomainNameError, Packet>:
  packetLoop(input, Done{Packet{0, MTip{}}})

def found(value: Map<&2, U32> & U32) -> U32:
  match value:
    case (_, byteLocal): byteLocal

def boundedByte(valid: Bool, bytes: Map<&2, U32>, index: U32) -> U32:
  match valid:
    case False{}: 256
    case True{}: found(Map.get(U32, 256, bytes, key(index)))

def byte(packetLocal: Packet, +index: U32) -> U32:
  match packetLocal:
    case Packet{sizeLocal, bytes}: boundedByte(U32.is_lt(index, sizeLocal), bytes, index)

type Decoded is Data:
  Decoded{name: Name, nextLocal: U32}

type Mode is Data:
  Head{}
  Label{left: U32, reversed: List<&2, U32>}
  Pointer{high: U32}

type State is Data:
  Reading{position: U32, ceiling: U32, nextLocal: Maybe<&2, U32>, length: U32, reversed: List<&2, List<&2, U32>>, mode: Mode}
  Finished{value: Decoded}
  Failed{error: DomainNameError}

def nextOffset(nextLocal: Maybe<&2, U32>, fallback: U32) -> U32:
  match nextLocal:
    case None{}: fallback
    case Some{value}: value

def labelHead(valid: Bool, position: U32, ceiling: U32, nextLocal: Maybe<&2, U32>, length: U32, labels: List<&2, List<&2, U32>>, count: U32) -> State:
  match valid:
    case False{}: Failed{NameTooLong{}}
    case True{}: Reading{position, ceiling, nextLocal, length, labels, Label{count, Nil{}}}

def headFlags(zero: Bool, label: Bool, pointer: Bool, +tag: U32, position: U32, ceiling: U32, nextLocal: Maybe<&2, U32>, +length: U32, labels: List<&2, List<&2, U32>>) -> State:
  match zero label pointer:
    case True{} _ _: Finished{Decoded{Name{List.reverse(&2, List<&2, U32>, labels)}, nextOffset(nextLocal, position)}}
    case False{} True{} _: labelHead(U32.is_le((length + tag + 1 : U32), 255), position, ceiling, nextLocal, (length + tag + 1 : U32), labels, tag)
    case False{} False{} True{}: Reading{position, ceiling, nextLocal, length, labels, Pointer{(tag - 192 : U32)}}
    case _ _ _: Failed{ReservedLabel{}}

def head(+tag: U32, position: U32, ceiling: U32, nextLocal: Maybe<&2, U32>, length: U32, labels: List<&2, List<&2, U32>>) -> State:
  headFlags(U32.is_eq(tag, 0), U32.is_lt(tag, 64), U32.is_ge(tag, 192), tag, position, ceiling, nextLocal, length, labels)

def pointed(valid: Bool, +target: U32, position: U32, nextLocal: Maybe<&2, U32>, length: U32, labels: List<&2, List<&2, U32>>) -> State:
  match valid:
    case False{}: Failed{InvalidPointer{}}
    case True{}: Reading{target, target, Some{nextOffset(nextLocal, position)}, length, labels, Head{}}

def consume(mode: Mode, +value: U32, +position: U32, +ceiling: U32, nextLocal: Maybe<&2, U32>, length: U32, labels: List<&2, List<&2, U32>>) -> State:
  match mode:
    case Head{}: head(value, position, ceiling, nextLocal, length, labels)
    case Label{1, reversed}: Reading{position, ceiling, nextLocal, length, List.reverse(&2, U32, value <> reversed) <> labels, Head{}}
    case Label{left, reversed}: Reading{position, ceiling, nextLocal, length, labels, Label{(left - 1 : U32), value <> reversed}}
    case Pointer{+high}: pointed(U32.is_lt((high * 256 + value : U32), ceiling), (high * 256 + value : U32), position, nextLocal, length, labels)

def present(valid: Bool, mode: Mode, value: U32, position: U32, ceiling: U32, nextLocal: Maybe<&2, U32>, length: U32, labels: List<&2, List<&2, U32>>) -> State:
  match valid:
    case False{}: Failed{NameTruncated{}}
    case True{}: consume(mode, value, position, ceiling, nextLocal, length, labels)

def step(packetLocal: Packet, state: State) -> State:
  match state:
    case Reading{+position, ceiling, nextLocal, length, labels, mode}:
      +value = byte(packetLocal, position)
      present(U32.is_le(value, 255), mode, value, (position + 1 : U32), ceiling, nextLocal, length, labels)
    case final: final

# Every pointer must refer to an earlier name segment. The ceiling strictly
# decreases on a jump, rejecting self/forward/cyclic references. Labels count
# toward the expanded 255-octet limit, including their lengths and root.
def loop(fuel: Nat, +packetLocal: Packet, state: State) -> Result<&2, &2, DomainNameError, Decoded>:
  match fuel state:
    case _ Finished{value}: Done{value}
    case _ Failed{error}: Fail{error}
    case Zero{} _: Fail{InvalidPointer{}}
    case Succ{rest} reading: loop(rest, packetLocal, step(packetLocal, reading))

def decodeName(packetLocal: Packet, +position: U32) -> Result<&2, &2, DomainNameError, Decoded>:
  loop(65536n, packetLocal, Reading{position, position, None{}, 1, Nil{}, Head{}})

type EncodedLabel is Data:
  EncodedLabel{length: U32, reversed: List<&2, U32>}

def labelByte(valid: Bool, value: U32, length: U32, reversed: List<&2, U32>) -> Result<&2, &2, DomainNameError, EncodedLabel>:
  match valid:
    case False{}: Fail{NameInvalidByte{}}
    case True{}: Done{EncodedLabel{(length + 1 : U32), value <> reversed}}

def labelStep(result: Result<&2, &2, DomainNameError, EncodedLabel>, +value: U32) -> Result<&2, &2, DomainNameError, EncodedLabel>:
  match result:
    case Fail{error}: Fail{error}
    case Done{EncodedLabel{63, _}}: Fail{InvalidLabel{}}
    case Done{EncodedLabel{length, reversed}}: labelByte(U32.is_le(value, 255), value, length, reversed)

def labelLoop(input: List<&2, U32>, result: Result<&2, &2, DomainNameError, EncodedLabel>) -> Result<&2, &2, DomainNameError, EncodedLabel>:
  match input result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{EncodedLabel{0, _}}: Fail{InvalidLabel{}}
    case Nil{} value: value
    case value <> rest state: labelLoop(rest, labelStep(state, value))

def appended(valid: Bool, length: U32, reversed: List<&2, U32>) -> Result<&2, &2, DomainNameError, EncodedLabel>:
  match valid:
    case False{}: Fail{NameTooLong{}}
    case True{}: Done{EncodedLabel{length, reversed}}

def encodedLabel(state: Result<&2, &2, DomainNameError, EncodedLabel>, value: Result<&2, &2, DomainNameError, EncodedLabel>) -> Result<&2, &2, DomainNameError, EncodedLabel>:
  match state value:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{EncodedLabel{+length, reversed}} Done{EncodedLabel{+sizeLocal, bytes}}: appended(U32.is_le((length + sizeLocal + 1 : U32), 255), (length + sizeLocal + 1 : U32), List.append(&2, U32, bytes, sizeLocal <> reversed))

def encodeLoop(labels: List<&2, List<&2, U32>>, state: Result<&2, &2, DomainNameError, EncodedLabel>) -> Result<&2, &2, DomainNameError, List<&2, U32>>:
  match labels state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{EncodedLabel{_, reversed}}: Done{List.reverse(&2, U32, 0 <> reversed)}
    case label <> rest value: encodeLoop(rest, encodedLabel(value, labelLoop(label, Done{EncodedLabel{0, Nil{}}})))

def encodeName(name: Name) -> Result<&2, &2, DomainNameError, List<&2, U32>>:
  match name:
    case Name{labels}: encodeLoop(labels, Done{EncodedLabel{1, Nil{}}})

# Wire structure only. Transaction matching and record-specific interpretation
# belong to the resolver; retain unknown flags, classes and record types.
type Header is Data:
  Header{id: U32, flags: U32, questions: U32, answersMessage: U32, authoritiesMessage: U32, additional: U32}

type Question is Data:
  Question{name: Name, kind: U32, class: U32}

# RDATA stays a span in the original immutable packetLocal. Compression offsets
# inside CNAME/SOA/etc. remain meaningful; opaque record types stay lossless.
type Record is Data:
  Record{name: Name, kind: U32, class: U32, ttl: U32, startLocal: U32, length: U32}

type Message is Data:
  Message{packetLocal: Packet, header: Header, questions: List<&2, Question>, answersMessage: List<&2, Record>, authoritiesMessage: List<&2, Record>, additional: List<&2, Record>}

type Parsed<-Item: Data> is Data:
  Parsed{value: Item, nextLocal: U32}

type Error is Data:
  NameError{error: DomainNameError}
  Truncated{}
  TrailingData{}
  InvalidField{}

def size(packetLocal: Packet) -> U32:
  match packetLocal:
    case Packet{packetSize, _}: packetSize

def available(+packetLocal: Packet, +position: U32, count: U32) -> Bool:
  U32.is_le(position, size(packetLocal)) && U32.is_le(count, (size(packetLocal) - position : U32))

# Call only after validating the containing fixed-sizeLocal field.
def word(+packetLocal: Packet, +position: U32) -> U32:
  (byte(packetLocal, position) * 256 + byte(packetLocal, (position + 1 : U32)) : U32)

def headerFields(valid: Bool, +packetLocal: Packet) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{Truncated{}}
    case True{}: Done{Header{word(packetLocal, 0), word(packetLocal, 2), word(packetLocal, 4), word(packetLocal, 6), word(packetLocal, 8), word(packetLocal, 10)}}

def header(+packetLocal: Packet) -> Result<&2, &2, Error, Header>:
  headerFields(available(packetLocal, 0, 12), packetLocal)

def questionFields(valid: Bool, +packetLocal: Packet, name: Name, +position: U32) -> Result<&2, &2, Error, Parsed<Question>>:
  match valid:
    case False{}: Fail{Truncated{}}
    case True{}: Done{Parsed{Question{name, word(packetLocal, position), word(packetLocal, (position + 2 : U32))}, (position + 4 : U32)}}

def questionName(+packetLocal: Packet, value: Result<&2, &2, DomainNameError, Decoded>) -> Result<&2, &2, Error, Parsed<Question>>:
  match value:
    case Fail{error}: Fail{NameError{error}}
    case Done{Decoded{name, +nextLocal}}: questionFields(available(packetLocal, nextLocal, 4), packetLocal, name, nextLocal)

def questionMessage(+packetLocal: Packet, position: U32) -> Result<&2, &2, Error, Parsed<Question>>:
  questionName(packetLocal, decodeName(packetLocal, position))

def recordData(valid: Bool, name: Name, kind: U32, class: U32, ttl: U32, +startLocal: U32, +length: U32) -> Result<&2, &2, Error, Parsed<Record>>:
  match valid:
    case False{}: Fail{Truncated{}}
    case True{}: Done{Parsed{Record{name, kind, class, ttl, startLocal, length}, (startLocal + length : U32)}}

def recordFields(valid: Bool, +packetLocal: Packet, name: Name, +position: U32) -> Result<&2, &2, Error, Parsed<Record>>:
  match valid:
    case False{}: Fail{Truncated{}}
    case True{}:
      +length = word(packetLocal, (position + 8 : U32))
      +startLocal = (position + 10 : U32)
      recordData(available(packetLocal, startLocal, length), name, word(packetLocal, position), word(packetLocal, (position + 2 : U32)), (word(packetLocal, (position + 4 : U32)) * 65536 + word(packetLocal, (position + 6 : U32)) : U32), startLocal, length)

def recordName(+packetLocal: Packet, value: Result<&2, &2, DomainNameError, Decoded>) -> Result<&2, &2, Error, Parsed<Record>>:
  match value:
    case Fail{error}: Fail{NameError{error}}
    case Done{Decoded{name, +nextLocal}}: recordFields(available(packetLocal, nextLocal, 10), packetLocal, name, nextLocal)

def record(+packetLocal: Packet, position: U32) -> Result<&2, &2, Error, Parsed<Record>>:
  recordName(packetLocal, decodeName(packetLocal, position))

def added(-Item: Data, reversed: List<&2, Item>, value: Result<&2, &2, Error, Parsed<Item>>) -> Result<&2, &2, Error, Parsed<List<&2, Item>>>:
  match value:
    case Fail{error}: Fail{error}
    case Done{Parsed{item, nextLocal}}: Done{Parsed{item <> reversed, nextLocal}}

# Parser callbacks are pure values. Section counts guide traversal but never
# authorize reading beyond the packetLocal; malformed counts stop at the first error.
def section(~Item: Data, ~parse: (Packet -> U32 -> Result<&2, &2, Error, Parsed<Item>>), count: Nat, +packetLocal: Packet, state: Result<&2, &2, Error, Parsed<List<&2, Item>>>) -> Result<&2, &2, Error, Parsed<List<&2, Item>>>:
  match count state:
    case _ Fail{error}: Fail{error}
    case Zero{} Done{Parsed{reversed, nextLocal}}: Done{Parsed{List.reverse(&2, Item, reversed), nextLocal}}
    case Succ{rest} Done{Parsed{reversed, nextLocal}}: section(~Item, ~parse, rest, packetLocal, added(Item, reversed, parse(packetLocal, nextLocal)))

def complete(valid: Bool, packetLocal: Packet, header: Header, questions: List<&2, Question>, answersMessage: List<&2, Record>, authoritiesMessage: List<&2, Record>, additional: List<&2, Record>) -> Result<&2, &2, Error, Message>:
  match valid:
    case False{}: Fail{TrailingData{}}
    case True{}: Done{Message{packetLocal, header, questions, answersMessage, authoritiesMessage, additional}}

def additionals(+packetLocal: Packet, header: Header, questions: List<&2, Question>, answersMessage: List<&2, Record>, authoritiesMessage: List<&2, Record>, result: Result<&2, &2, Error, Parsed<List<&2, Record>>>) -> Result<&2, &2, Error, Message>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Parsed{additional, nextLocal}}: complete(U32.is_eq(size(packetLocal), nextLocal), packetLocal, header, questions, answersMessage, authoritiesMessage, additional)

def authoritiesMessage(+packetLocal: Packet, header: Header, count: U32, questions: List<&2, Question>, answersMessage: List<&2, Record>, result: Result<&2, &2, Error, Parsed<List<&2, Record>>>) -> Result<&2, &2, Error, Message>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Parsed{values, nextLocal}}: additionals(packetLocal, header, questions, answersMessage, values, section(~Record, ~(p => i => record(p, i)), U32.to_nat(count), packetLocal, Done{Parsed{Nil{}, nextLocal}}))

def answersMessage(+packetLocal: Packet, header: Header, authorityCount: U32, additionalCount: U32, questions: List<&2, Question>, result: Result<&2, &2, Error, Parsed<List<&2, Record>>>) -> Result<&2, &2, Error, Message>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Parsed{values, nextLocal}}: authoritiesMessage(packetLocal, header, additionalCount, questions, values, section(~Record, ~(p => i => record(p, i)), U32.to_nat(authorityCount), packetLocal, Done{Parsed{Nil{}, nextLocal}}))

def questions(+packetLocal: Packet, header: Header, answerCount: U32, authorityCount: U32, additionalCount: U32, result: Result<&2, &2, Error, Parsed<List<&2, Question>>>) -> Result<&2, &2, Error, Message>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Parsed{values, nextLocal}}: answersMessage(packetLocal, header, authorityCount, additionalCount, values, section(~Record, ~(p => i => record(p, i)), U32.to_nat(answerCount), packetLocal, Done{Parsed{Nil{}, nextLocal}}))

def withHeader(+packetLocal: Packet, value: Result<&2, &2, Error, Header>) -> Result<&2, &2, Error, Message>:
  match value:
    case Fail{error}: Fail{error}
    case Done{Header{id, flags, +qd, +an, +ns, +ar}}: questions(packetLocal, Header{id, flags, qd, an, ns, ar}, an, ns, ar, section(~Question, ~(p => i => questionMessage(p, i)), U32.to_nat(qd), packetLocal, Done{Parsed{Nil{}, 12}}))

def fromPacket(value: Result<&2, &2, DomainNameError, Packet>) -> Result<&2, &2, Error, Message>:
  match value:
    case Fail{error}: Fail{NameError{error}}
    case Done{+packetLocal}: withHeader(packetLocal, header(packetLocal))

def parse(bytes: List<&2, U32>) -> Result<&2, &2, Error, Message>:
  fromPacket(packet(bytes))

# Uncompressed single-questionMessage query. Caller supplies transaction ID and flags
# (e.g. recursion desired); validation/matching policy remains explicit above.
def u16(+value: U32, tail: List<&2, U32>) -> List<&2, U32>:
  (value / 256 : U32) <> (value % 256 : U32) <> tail

def queryName(id: U32, flags: U32, kind: U32, class: U32, encoded: Result<&2, &2, DomainNameError, List<&2, U32>>) -> Result<&2, &2, Error, List<&2, U32>>:
  match encoded:
    case Fail{error}: Fail{NameError{error}}
    case Done{bytes}: Done{u16(id, u16(flags, 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> List.append(&2, U32, bytes, u16(kind, u16(class, Nil{})))))}

def queryFields(valid: Bool, id: U32, flags: U32, questionMessage: Question) -> Result<&2, &2, Error, List<&2, U32>>:
  match valid questionMessage:
    case False{} _: Fail{InvalidField{}}
    case True{} Question{name, kind, class}: queryName(id, flags, kind, class, encodeName(name))

def query(+id: U32, +flags: U32, questionMessage: Question) -> Result<&2, &2, Error, List<&2, U32>>:
  match questionMessage:
    case Question{name, +kind, +class}: queryFields(U32.is_le(id, 65535) && U32.is_le(flags, 65535) && U32.is_le(kind, 65535) && U32.is_le(class, 65535), id, flags, Question{name, kind, class})

# Text-to-wire syntax only. IDNA, hostname policy and search expansion belong
# to callers. A trailing unescaped dot makes the name absolute.
type PresentationParsed is Data:
  PresentationParsed{name: Name, absolute: Bool}

type PresentationError is Data:
  PresentationInvalidByte{}
  RawNul{}
  EmptyLabel{}
  LabelTooLong{}
  PresentationNameTooLong{}
  InvalidEscape{}

type PresentationMode is Data:
  Plain{}
  Escape{}
  SecondDigit{value: U32}
  ThirdDigit{value: U32}

type Cursor is Data:
  Cursor{labels: List<&2, List<&2, U32>>, label: List<&2, U32>, sizeLocal: U32, total: U32}

type PresentationState is Data:
  PresentationState{cursor: Cursor, mode: PresentationMode, absolute: Bool}

def byteAdded(fits: Bool, byteLocal: U32, labels: List<&2, List<&2, U32>>, label: List<&2, U32>, sizeLocal: U32, total: U32) -> Result<&2, &2, PresentationError, Cursor>:
  match fits:
    case False{}: Fail{PresentationNameTooLong{}}
    case True{}: Done{Cursor{labels, byteLocal <> label, (sizeLocal + 1 : U32), total}}

def withinLabel(valid: Bool, byteLocal: U32, labels: List<&2, List<&2, U32>>, label: List<&2, U32>, +sizeLocal: U32, total: U32) -> Result<&2, &2, PresentationError, Cursor>:
  match valid:
    case False{}: Fail{LabelTooLong{}}
    case True{}:
      +nextLocal = (total + Bool.pick(U32, U32.is_zero(sizeLocal), 2, 1) : U32)
      byteAdded(U32.is_le(nextLocal, 255), byteLocal, labels, label, sizeLocal, nextLocal)

def appendByte(byteLocal: U32, cursor: Cursor) -> Result<&2, &2, PresentationError, Cursor>:
  match cursor:
    case Cursor{labels, label, +sizeLocal, total}: withinLabel(U32.is_lt(sizeLocal, 63), byteLocal, labels, label, sizeLocal, total)

def stateResult(result: Result<&2, &2, PresentationError, Cursor>) -> Result<&2, &2, PresentationError, PresentationState>:
  match result:
    case Fail{error}: Fail{error}
    case Done{cursor}: Done{PresentationState{cursor, Plain{}, False{}}}

def separator(last: Bool, cursor: Cursor) -> Result<&2, &2, PresentationError, PresentationState>:
  match last cursor:
    case True{} Cursor{Nil{}, Nil{}, 0, total}: Done{PresentationState{Cursor{Nil{}, Nil{}, 0, total}, Plain{}, True{}}}
    case _ Cursor{_, _, 0, _}: Fail{EmptyLabel{}}
    case final Cursor{labels, label, _, total}: Done{PresentationState{Cursor{List.reverse(&2, U32, label) <> labels, Nil{}, 0, total}, Plain{}, final}}

def decimalByte(valid: Bool, value: U32, cursor: Cursor) -> Result<&2, &2, PresentationError, PresentationState>:
  match valid:
    case False{}: Fail{InvalidEscape{}}
    case True{}: stateResult(appendByte(value, cursor))

def escaped(digit: Bool, byteLocal: U32, cursor: Cursor) -> Result<&2, &2, PresentationError, PresentationState>:
  match digit:
    case True{}: Done{PresentationState{cursor, SecondDigit{(byteLocal - 48 : U32)}, False{}}}
    case False{}: stateResult(appendByte(byteLocal, cursor))

def second(valid: Bool, byteLocal: U32, value: U32, cursor: Cursor) -> Result<&2, &2, PresentationError, PresentationState>:
  match valid:
    case False{}: Fail{InvalidEscape{}}
    case True{}: Done{PresentationState{cursor, ThirdDigit{(value * 10 + byteLocal - 48 : U32)}, False{}}}

def isDigit(+byteLocal: U32) -> Bool: U32.is_ge(byteLocal, 48) && U32.is_le(byteLocal, 57)

def plain(byteLocal: U32, last: Bool, cursor: Cursor) -> Result<&2, &2, PresentationError, PresentationState>:
  match byteLocal:
    case 92: Done{PresentationState{cursor, Escape{}, False{}}}
    case 46: separator(last, cursor)
    case value: stateResult(appendByte(value, cursor))

def stepPresentation(+byteLocal: U32, last: Bool, state: PresentationState) -> Result<&2, &2, PresentationError, PresentationState>:
  match state:
    case PresentationState{cursor, Plain{}, _}: plain(byteLocal, last, cursor)
    case PresentationState{cursor, Escape{}, _}: escaped(isDigit(byteLocal), byteLocal, cursor)
    case PresentationState{cursor, SecondDigit{number}, _}: second(isDigit(byteLocal), byteLocal, number, cursor)
    case PresentationState{cursor, ThirdDigit{number}, _}:
      +decodedLocal = (number * 10 + byteLocal - 48 : U32)
      decimalByte(isDigit(byteLocal) && U32.is_le(decodedLocal, 255), decodedLocal, cursor)

def checkedByte(valid: Bool, byteLocal: U32, last: Bool, state: PresentationState) -> Result<&2, &2, PresentationError, PresentationState>:
  match valid byteLocal:
    case False{} _: Fail{PresentationInvalidByte{}}
    case True{} 0: Fail{RawNul{}}
    case True{} value: stepPresentation(value, last, state)

def empty(bytes: List<&2, U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case _: False{}

def finished(state: PresentationState) -> Result<&2, &2, PresentationError, PresentationParsed>:
  match state:
    case PresentationState{Cursor{labels, Nil{}, 0, _}, Plain{}, absolute}: Done{PresentationParsed{Name{List.reverse(&2, List<&2, U32>, labels)}, absolute}}
    case PresentationState{Cursor{labels, label, _, _}, Plain{}, absolute}: Done{PresentationParsed{Name{List.reverse(&2, List<&2, U32>, List.reverse(&2, U32, label) <> labels)}, absolute}}
    case _: Fail{InvalidEscape{}}

def scanPresentation(bytes: List<&2, U32>, state: Result<&2, &2, PresentationError, PresentationState>) -> Result<&2, &2, PresentationError, PresentationParsed>:
  match bytes state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{value}: finished(value)
    case +byteLocal <> +rest Done{value}: scanPresentation(rest, checkedByte(U32.is_le(byteLocal, 255), byteLocal, empty(rest), value))

# Raw zero cannot occur in a C presentation string. Keep it a typed error,
# rather than silently truncating a Bend value. The escape \000 is valid data.
def parseBytes(bytes: List<&2, U32>) -> Result<&2, &2, PresentationError, PresentationParsed>:
  scanPresentation(bytes, Done{PresentationState{Cursor{Nil{}, Nil{}, 0, 1}, Plain{}, False{}}})

def parsePresentation(text: String) -> Result<&2, &2, PresentationError, PresentationParsed>:
  parseBytes(UTF8.encode(text))

# Typed IN records needed by address resolution. Unknown kinds/classes retain
# their original record/span, rather than interpreting class-specific bytes.
type Value is Data:
  A{address: IPv4.Address}
  AAAA{address: IPv6.Ipv6Address}
  CNAME{target: Name}
  NS{target: Name}
  PTR{target: Name}
  SOA{primary: Name, mailbox: Name, serial: U32, refresh: U32, retry: U32, expire: U32, minimum: U32}
  Opaque{record: Record}

type RecordError is Data:
  InvalidSpan{}
  InvalidLength{}
  InvalidName{error: DomainNameError}

def integer(+packetLocal: Packet, +startLocal: U32) -> U32:
  (word(packetLocal, startLocal) * 65536 + word(packetLocal, (startLocal + 2 : U32)) : U32)

def address4(valid: Bool, packetLocal: Packet, startLocal: U32) -> Result<&2, &2, RecordError, Value>:
  match valid:
    case False{}: Fail{InvalidLength{}}
    case True{}: Done{A{IPv4.Address{integer(packetLocal, startLocal)}}}

def address6(valid: Bool, +packetLocal: Packet, +startLocal: U32) -> Result<&2, &2, RecordError, Value>:
  match valid:
    case False{}: Fail{InvalidLength{}}
    case True{}: Done{AAAA{IPv6.Ipv6Address{integer(packetLocal, startLocal), integer(packetLocal, (startLocal + 4 : U32)), integer(packetLocal, (startLocal + 8 : U32)), integer(packetLocal, (startLocal + 12 : U32))}}}

def named(kind: U32, target: Name) -> Value:
  match kind:
    case 5: CNAME{target}
    case 2: NS{target}
    case _: PTR{target}

def exactName(valid: Bool, kind: U32, target: Name) -> Result<&2, &2, RecordError, Value>:
  match valid:
    case False{}: Fail{InvalidLength{}}
    case True{}: Done{named(kind, target)}

def nameResult(kind: U32, end: U32, result: Result<&2, &2, DomainNameError, Decoded>) -> Result<&2, &2, RecordError, Value>:
  match result:
    case Fail{error}: Fail{InvalidName{error}}
    case Done{Decoded{target, nextLocal}}: exactName(U32.is_eq(nextLocal, end), kind, target)

def soaFields(valid: Bool, +packetLocal: Packet, primary: Name, mailbox: Name, +startLocal: U32) -> Result<&2, &2, RecordError, Value>:
  match valid:
    case False{}: Fail{InvalidLength{}}
    case True{}: Done{SOA{primary, mailbox, integer(packetLocal, startLocal), integer(packetLocal, (startLocal + 4 : U32)), integer(packetLocal, (startLocal + 8 : U32)), integer(packetLocal, (startLocal + 12 : U32)), integer(packetLocal, (startLocal + 16 : U32))}}

def soaMailbox(packetLocal: Packet, primary: Name, end: U32, result: Result<&2, &2, DomainNameError, Decoded>) -> Result<&2, &2, RecordError, Value>:
  match result:
    case Fail{error}: Fail{InvalidName{error}}
    case Done{Decoded{mailbox, +nextLocal}}: soaFields(U32.is_eq((nextLocal + 20 : U32), end), packetLocal, primary, mailbox, nextLocal)

def soaMore(valid: Bool, +packetLocal: Packet, primary: Name, end: U32, nextLocal: U32) -> Result<&2, &2, RecordError, Value>:
  match valid:
    case False{}: Fail{InvalidLength{}}
    case True{}: soaMailbox(packetLocal, primary, end, decodeName(packetLocal, nextLocal))

def soaPrimary(packetLocal: Packet, +end: U32, result: Result<&2, &2, DomainNameError, Decoded>) -> Result<&2, &2, RecordError, Value>:
  match result:
    case Fail{error}: Fail{InvalidName{error}}
    case Done{Decoded{primary, +nextLocal}}: soaMore(U32.is_lt(nextLocal, end), packetLocal, primary, end, nextLocal)

def kindFields(+packetLocal: Packet, kind: U32, +startLocal: U32, +length: U32, original: Record) -> Result<&2, &2, RecordError, Value>:
  match kind:
    case 1: address4(U32.is_eq(length, 4), packetLocal, startLocal)
    case 28: address6(U32.is_eq(length, 16), packetLocal, startLocal)
    case 5: nameResult(5, (startLocal + length : U32), decodeName(packetLocal, startLocal))
    case 2: nameResult(2, (startLocal + length : U32), decodeName(packetLocal, startLocal))
    case 12: nameResult(12, (startLocal + length : U32), decodeName(packetLocal, startLocal))
    case 6: soaPrimary(packetLocal, (startLocal + length : U32), decodeName(packetLocal, startLocal))
    case _: Done{Opaque{original}}

def classFields(class: U32, packetLocal: Packet, kind: U32, startLocal: U32, length: U32, original: Record) -> Result<&2, &2, RecordError, Value>:
  match class:
    case 1: kindFields(packetLocal, kind, startLocal, length, original)
    case _: Done{Opaque{original}}

def fields(packetLocal: Packet, record: Record) -> Result<&2, &2, RecordError, Value>:
  match record:
    case Record{name, +kind, +class, ttl, +startLocal, +length}: classFields(class, packetLocal, kind, startLocal, length, Record{name, kind, class, ttl, startLocal, length})

def checkedRecord(valid: Bool, packetLocal: Packet, record: Record) -> Result<&2, &2, RecordError, Value>:
  match valid:
    case False{}: Fail{InvalidSpan{}}
    case True{}: fields(packetLocal, record)

# Validate even manually constructed spans. parse already checks them,
# but callers may supply a record independently. Unknown data stays opaque.
def decodeRecord(+packetLocal: Packet, record: Record) -> Result<&2, &2, RecordError, Value>:
  match record:
    case Record{name, kind, class, ttl, +startLocal, +length}: checkedRecord(available(packetLocal, startLocal, length), packetLocal, Record{name, kind, class, ttl, startLocal, length})

type Address is Data:
  V4{value: IPv4.Address}
  V6{value: IPv6.Ipv6Address, scope: U32}

type Endpoint is Data:
  Endpoint{address: Address, port: U32}

# Source/destination are the actual selected endpoints, not wildcard bind
# addresses. Transport must report observed endpoints from its socket metadata.
type Transaction is Data:
  Transaction{source: Endpoint, destination: Endpoint, id: U32, opcode: U32, question: Question}

type Rejection is Data:
  EndpointMismatch{}
  IdMismatch{}
  NotResponse{}
  OpcodeMismatch{}
  QuestionCountMismatch{}
  QuestionMismatch{}
  Malformed{error: Error}

type Decision is Data:
  Ignore{reason: Rejection}
  ResponseTruncated{headerResponse: Header}
  Matched{message: Message}

def sameAddress(left: Address, right: Address) -> Bool:
  match left right:
    case V4{IPv4.Address{a}} V4{IPv4.Address{b}}: U32.is_eq(a, b)
    case V6{IPv6.Ipv6Address{a, b, c, d}, scope} V6{IPv6.Ipv6Address{e, f, g, h}, otherScope}: U32.is_eq(a, e) && U32.is_eq(b, f) && U32.is_eq(c, g) && U32.is_eq(d, h) && U32.is_eq(scope, otherScope)
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

def sameName(left: Name, right: Name) -> Bool:
  match left right:
    case Name{a} Name{b}: sameLabels(a, b)

def sameQuestion(left: Question, right: Question) -> Bool:
  match left right:
    case Question{a, at, ac} Question{b, bt, bc}: U32.is_eq(at, bt) && U32.is_eq(ac, bc) && sameName(a, b)

def parsed(value: Result<&2, &2, Error, Message>) -> Decision:
  match value:
    case Fail{error}: Ignore{Malformed{error}}
    case Done{message}: Matched{message}

def matched(truncated: Bool, packetResponse: Packet, headerResponse: Header) -> Decision:
  match truncated:
    case True{}: ResponseTruncated{headerResponse}
    case False{}: parsed(withHeader(packetResponse, Done{headerResponse}))

def questionMatches(equal: Bool, packetResponse: Packet, headerResponse: Header, flags: U32) -> Decision:
  match equal:
    case False{}: Ignore{QuestionMismatch{}}
    case True{}: matched(U32.is_ne(U32.and(flags, 512), 0), packetResponse, headerResponse)

def checkedQuestion(packetResponse: Packet, headerResponse: Header, flags: U32, expected: Question, value: Result<&2, &2, Error, Parsed<Question>>) -> Decision:
  match value:
    case Fail{error}: Ignore{Malformed{error}}
    case Done{Parsed{actual, _}}: questionMatches(sameQuestion(expected, actual), packetResponse, headerResponse, flags)

def absentQuestion(allowed: Bool, packetResponse: Packet, headerResponse: Header, flags: U32) -> Decision:
  match allowed:
    case False{}: Ignore{QuestionCountMismatch{}}
    case True{}: matched(U32.is_ne(U32.and(flags, 512), 0), packetResponse, headerResponse)

def questionCount(optional: Bool, count: U32, +packetResponse: Packet, headerResponse: Header, flags: U32, expected: Question) -> Decision:
  match count:
    case 0: absentQuestion(optional, packetResponse, headerResponse, flags)
    case 1: checkedQuestion(packetResponse, headerResponse, flags, expected, questionMessage(packetResponse, 12))
    case _: Ignore{QuestionCountMismatch{}}

def checkedHeader(equalId: Bool, response: Bool, equalOpcode: Bool, optional: Bool, count: U32, packetResponse: Packet, headerResponse: Header, flags: U32, expected: Question) -> Decision:
  match equalId response equalOpcode:
    case False{} _ _: Ignore{IdMismatch{}}
    case True{} False{} _: Ignore{NotResponse{}}
    case True{} True{} False{}: Ignore{OpcodeMismatch{}}
    case True{} True{} True{}: questionCount(optional, count, packetResponse, headerResponse, flags, expected)

def headerResponse(optional: Bool, packetResponse: Packet, id: U32, opcode: U32, expected: Question, result: Result<&2, &2, Error, Header>) -> Decision:
  match result:
    case Fail{error}: Ignore{Malformed{error}}
    case Done{Header{+actualId, +flags, +qd, an, ns, ar}}: checkedHeader(U32.is_eq(id, actualId), U32.is_ne(U32.and(flags, 32768), 0), U32.is_eq(opcode, (flags / 2048 % 16 : U32)), optional, qd, packetResponse, Header{actualId, flags, qd, an, ns, ar}, flags, expected)

def packetResponse(optional: Bool, id: U32, opcode: U32, expected: Question, value: Result<&2, &2, DomainNameError, Packet>) -> Decision:
  match value:
    case Fail{error}: Ignore{Malformed{NameError{error}}}
    case Done{+messagePacket}: headerResponse(optional, messagePacket, id, opcode, expected, header(messagePacket))

def endpoints(equal: Bool, optional: Bool, id: U32, opcode: U32, expected: Question, wire: List<&2, U32>) -> Decision:
  match equal:
    case False{}: Ignore{EndpointMismatch{}}
    case True{}: packetResponse(optional, id, opcode, expected, packet(wire))

def inspectPolicy(optional: Bool, transaction: Transaction, source: Endpoint, destination: Endpoint, wire: List<&2, U32>) -> Decision:
  match transaction:
    case Transaction{sentFrom, sentTo, id, opcode, expected}: endpoints(sameEndpoint(sentTo, source) && sameEndpoint(sentFrom, destination), optional, id, opcode, expected, wire)

# Datagram matching requires the complete question, including before accepting
# a truncation indication. Matching never grants trust to unrelated answers.
def inspectResponse(transaction: Transaction, source: Endpoint, destination: Endpoint, wire: List<&2, U32>) -> Decision:
  inspectPolicy(False{}, transaction, source, destination, wire)

# RFC 7766 section 7 allows an absent question on the established TCP stream.
# If present it must match. ID/opcode/endpoints and complete-message validation
# still apply; a zero-question response is not rewritten to invent a question.
def inspectStream(transaction: Transaction, source: Endpoint, destination: Endpoint, wire: List<&2, U32>) -> Decision:
  inspectPolicy(True{}, transaction, source, destination, wire)

# TCP segmentation is independent of DNS messages. This layer frames arbitrary
# octets; the DNS message parser validates the payload (including empty frames).
type Reader is Data:
  Prefix{}
  LengthLow{high: U32}
  Payload{remaining: U32, reversed: List<&2, U32>}

type TcpFrameError is Data:
  TcpFrameInvalidByte{value: U32}
  TcpFrameTooLong{}
  IncompleteFrame{}

type ReadResult is Data:
  More{reader: Reader}
  Frame{bytes: List<&2, U32>, rest: List<&2, U32>}
  TcpFrameFailed{error: TcpFrameError}

def newTcpFrame() -> Reader: Prefix{}

def lengthTcpFrame(value: U32) -> ReadResult:
  match value:
    case 0: Frame{Nil{}, Nil{}}
    case countTcpFrame: More{Payload{countTcpFrame, Nil{}}}

def consumeTcpFrame(reader: Reader, byteLocal: U32) -> ReadResult:
  match reader:
    case Prefix{}: More{LengthLow{byteLocal}}
    case LengthLow{high}: lengthTcpFrame((high * 256 + byteLocal : U32))
    case Payload{1, reversed}: Frame{List.reverse(&2, U32, byteLocal <> reversed), Nil{}}
    case Payload{remaining, reversed}: More{Payload{(remaining - 1 : U32), byteLocal <> reversed}}

def checkedTcpFrame(valid: Bool, reader: Reader, byteLocal: U32) -> ReadResult:
  match valid:
    case False{}: TcpFrameFailed{TcpFrameInvalidByte{byteLocal}}
    case True{}: consumeTcpFrame(reader, byteLocal)

def feed(input: List<&2, U32>, state: ReadResult) -> ReadResult:
  match input state:
    case rest Frame{bytes, _}: Frame{bytes, rest}
    case _ TcpFrameFailed{error}: TcpFrameFailed{error}
    case Nil{} More{reader}: More{reader}
    case +byteLocal <> rest More{reader}: feed(rest, checkedTcpFrame(U32.is_le(byteLocal, 255), reader, byteLocal))

# Return at most one frame and the unread suffix, so the caller can process
# messages with backpressure rather than accumulating an unbounded event list.
def read(reader: Reader, input: List<&2, U32>) -> ReadResult:
  feed(input, More{reader})

def finish(reader: Reader) -> Result<&2, &2, TcpFrameError, Unit>:
  match reader:
    case Prefix{}: Done{Unit{}}
    case _: Fail{IncompleteFrame{}}

def countByte(valid: Bool, value: U32, countTcpFrame: U32) -> Result<&2, &2, TcpFrameError, U32>:
  match valid:
    case False{}: Fail{TcpFrameInvalidByte{value}}
    case True{}: Done{(countTcpFrame + 1 : U32)}

def increment(countTcpFrame: U32, +value: U32) -> Result<&2, &2, TcpFrameError, U32>:
  match countTcpFrame:
    case 65535: Fail{TcpFrameTooLong{}}
    case sizeLocal: countByte(U32.is_le(value, 255), value, sizeLocal)

def countTcpFrame(bytes: List<&2, U32>, result: Result<&2, &2, TcpFrameError, U32>) -> Result<&2, &2, TcpFrameError, U32>:
  match bytes result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case byteLocal <> rest Done{sizeLocal}: countTcpFrame(rest, increment(sizeLocal, byteLocal))

def encodedTcpFrame(bytes: List<&2, U32>, sizeLocal: Result<&2, &2, TcpFrameError, U32>) -> Result<&2, &2, TcpFrameError, List<&2, U32>>:
  match sizeLocal:
    case Fail{error}: Fail{error}
    case Done{+byteCount}: Done{(byteCount / 256 : U32) <> (byteCount % 256 : U32) <> bytes}

# Prefix and payload form one buffer for the socket writer. The caller owns
# DNS message validity and chooses when to pipeline another framed message.
def encodeTcpFrame(+bytes: List<&2, U32>) -> Result<&2, &2, TcpFrameError, List<&2, U32>>:
  encodedTcpFrame(bytes, countTcpFrame(bytes, Done{0}))

# EDNS(0) request fields. Unknown option codes and duplicate options are
# preserved in order; interpreting individual option payloads is separate.
type Option is Data:
  Option{code: U32, data: List<&2, U32>}

type Query is Data:
  Query{payloadSize: U32, dnssecOkLocal: Bool, options: List<&2, Option>}

type EdnsError is Data:
  EdnsInvalidField{}
  InvalidByte{value: U32}
  TooLong{}
  EdnsMessage{error: Error}

type Buffer is Data:
  Buffer{sizeLocal: U32, reversed: List<&2, U32>}

def measured(result: Result<&2, &2, TcpFrameError, U32>) -> Result<&2, &2, EdnsError, U32>:
  match result:
    case Done{sizeLocal}: Done{sizeLocal}
    case Fail{TcpFrameInvalidByte{value}}: Fail{InvalidByte{value}}
    case Fail{_}: Fail{TooLong{}}

def prepend(reversed: List<&2, U32>, tail: List<&2, U32>) -> List<&2, U32>:
  match reversed:
    case Nil{}: tail
    case byteLocal <> rest: prepend(rest, byteLocal <> tail)

# Inputs to append have already been measured and checked as octets.
def append(bytes: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case Nil{}: reversed
    case byteLocal <> rest: append(rest, byteLocal <> reversed)

def optionFits(fits: Bool, code: U32, +length: U32, data: List<&2, U32>, sizeLocal: U32, reversed: List<&2, U32>) -> Result<&2, &2, EdnsError, Buffer>:
  match fits:
    case False{}: Fail{TooLong{}}
    case True{}: Done{Buffer{(sizeLocal + length + 4 : U32), append(data, append(u16(code, u16(length, Nil{})), reversed))}}

def optionSize(code: U32, data: List<&2, U32>, buffer: Buffer, result: Result<&2, &2, EdnsError, U32>) -> Result<&2, &2, EdnsError, Buffer>:
  match buffer result:
    case _ Fail{error}: Fail{error}
    case Buffer{+sizeLocal, reversed} Done{+length}: optionFits(U32.is_le((sizeLocal + length + 4 : U32), 65535), code, length, data, sizeLocal, reversed)

def optionCode(valid: Bool, code: U32, +data: List<&2, U32>, buffer: Buffer) -> Result<&2, &2, EdnsError, Buffer>:
  match valid:
    case False{}: Fail{EdnsInvalidField{}}
    case True{}: optionSize(code, data, buffer, measured(countTcpFrame(data, Done{0})))

def add(option: Option, buffer: Buffer) -> Result<&2, &2, EdnsError, Buffer>:
  match option:
    case Option{+code, data}: optionCode(U32.is_le(code, 65535), code, data, buffer)

def options(values: List<&2, Option>, result: Result<&2, &2, EdnsError, Buffer>) -> Result<&2, &2, EdnsError, Buffer>:
  match values result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case value <> rest Done{buffer}: options(rest, add(value, buffer))

def recordEdns(payloadSize: U32, dnssecOkLocal: Bool, result: Result<&2, &2, EdnsError, Buffer>) -> Result<&2, &2, EdnsError, List<&2, U32>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Buffer{sizeLocal, reversed}}:
      Done{0 <> 0 <> 41 <> u16(payloadSize, 0 <> 0 <> Bool.pick(U32, dnssecOkLocal, 128, 0) <> 0 <> u16(sizeLocal, List.reverse(&2, U32, reversed)))}

def recordFieldsEdns(valid: Bool, payloadSize: U32, dnssecOkLocal: Bool, values: List<&2, Option>) -> Result<&2, &2, EdnsError, List<&2, U32>>:
  match valid:
    case False{}: Fail{EdnsInvalidField{}}
    case True{}: recordEdns(payloadSize, dnssecOkLocal, options(values, Done{Buffer{0, Nil{}}}))

# OPT uses the root owner, type 41, advertised payload in CLASS, version zero,
# zero extended RCODE and no reserved flag bits. Only the DO bit is settable.
def encode(value: Query) -> Result<&2, &2, EdnsError, List<&2, U32>>:
  match value:
    case Query{+payloadSize, dnssecOkLocal, values}: recordFieldsEdns(U32.is_le(payloadSize, 65535), payloadSize, dnssecOkLocal, values)

def bounded(bytes: List<&2, U32>, sizeLocal: Result<&2, &2, EdnsError, U32>) -> Result<&2, &2, EdnsError, List<&2, U32>>:
  match sizeLocal:
    case Fail{error}: Fail{error}
    case Done{_}: Done{bytes}

def counted(+bytes: List<&2, U32>) -> Result<&2, &2, EdnsError, List<&2, U32>>:
  bounded(bytes, measured(countTcpFrame(bytes, Done{0})))

# Input is the validated single-question message emitted by query.
# Replace ARCOUNT, append one OPT recordEdns and enforce the full message bound.
def attach(remaining: Nat, bytes: List<&2, U32>, reversed: List<&2, U32>, opt: List<&2, U32>) -> Result<&2, &2, EdnsError, List<&2, U32>>:
  match remaining bytes:
    case Zero{} _ <> _ <> body: counted(prepend(reversed, 0 <> 1 <> prepend(List.reverse(&2, U32, body), opt)))
    case Succ{rest} byteLocal <> tail: attach(rest, tail, byteLocal <> reversed, opt)
    case _ _: Fail{EdnsInvalidField{}}

def encoded(message: Result<&2, &2, Error, List<&2, U32>>, opt: Result<&2, &2, EdnsError, List<&2, U32>>) -> Result<&2, &2, EdnsError, List<&2, U32>>:
  match message opt:
    case Fail{error} _: Fail{EdnsMessage{error}}
    case Done{_} Fail{error}: Fail{error}
    case Done{bytes} Done{optBytes}: attach(10n, bytes, Nil{}, optBytes)

def queryEdns(id: U32, flags: U32, question: Question, extension: Query) -> Result<&2, &2, EdnsError, List<&2, U32>>:
  encoded(query(id, flags, question), encode(extension))

# RFC 6891 metadata. Preserve unknown flags, versions and opaque options;
# negotiation and option interpretation belong to the resolver policy.
type Response is Data:
  Response{payloadSize: U32, extendedCode: U32, version: U32, flags: U32, options: List<&2, Option>}

type EdnsResponseError is Data:
  Misplaced{}
  Duplicate{}
  InvalidOwner{}
  EdnsResponseInvalidField{}
  TruncatedOption{}

type Options is Data:
  Complete{values: List<&2, Option>}
  Options{position: U32, remaining: U32, reversed: List<&2, Option>}

def copyBytes(count: Nat, +packetLocal: Packet, +position: U32, reversed: List<&2, U32>) -> List<&2, U32>:
  match count:
    case Zero{}: List.reverse(&2, U32, reversed)
    case Succ{rest}: copyBytes(rest, packetLocal, (position + 1 : U32), byte(packetLocal, position) <> reversed)

def progress(empty: Bool, position: U32, remaining: U32, reversed: List<&2, Option>) -> Options:
  match empty:
    case True{}: Complete{List.reverse(&2, Option, reversed)}
    case False{}: Options{position, remaining, reversed}

def optionData(valid: Bool, packetLocal: Packet, +position: U32, +remaining: U32, code: U32, +length: U32, reversed: List<&2, Option>) -> Result<&2, &2, EdnsResponseError, Options>:
  match valid:
    case False{}: Fail{TruncatedOption{}}
    case True{}: Done{progress(U32.is_eq(remaining, length), (position + length : U32), (remaining - length : U32), Option{code, copyBytes(U32.to_nat(length), packetLocal, position, Nil{})} <> reversed)}

def optionHeader(valid: Bool, +packetLocal: Packet, +position: U32, +remaining: U32, reversed: List<&2, Option>) -> Result<&2, &2, EdnsResponseError, Options>:
  match valid:
    case False{}: Fail{TruncatedOption{}}
    case True{}:
      +length = word(packetLocal, (position + 2 : U32))
      optionData(U32.is_le(length, (remaining - 4 : U32)), packetLocal, (position + 4 : U32), (remaining - 4 : U32), word(packetLocal, position), length, reversed)

def optionLoop(fuel: Nat, +packetLocal: Packet, state: Result<&2, &2, EdnsResponseError, Options>) -> Result<&2, &2, EdnsResponseError, List<&2, Option>>:
  match fuel state:
    case _ Fail{error}: Fail{error}
    case _ Done{Complete{values}}: Done{values}
    case Zero{} _: Fail{TruncatedOption{}}
    case Succ{rest} Done{Options{position, +remaining, reversed}}: optionLoop(rest, packetLocal, optionHeader(U32.is_le(4, remaining), packetLocal, position, remaining, reversed))

def metadata(payloadSize: U32, +ttl: U32, result: Result<&2, &2, EdnsResponseError, List<&2, Option>>) -> Result<&2, &2, EdnsResponseError, Response>:
  match result:
    case Fail{error}: Fail{error}
    case Done{values}: Done{Response{payloadSize, (ttl / 16777216 : U32), (ttl / 65536 % 256 : U32), (ttl % 65536 : U32), values}}

def boundedEdnsResponse(valid: Bool, packetLocal: Packet, payloadSize: U32, ttl: U32, startLocal: U32, +length: U32) -> Result<&2, &2, EdnsResponseError, Response>:
  match valid:
    case False{}: Fail{EdnsResponseInvalidField{}}
    case True{}: metadata(payloadSize, ttl, optionLoop(U32.to_nat((length / 4 : U32)), packetLocal, Done{progress(U32.is_eq(length, 0), startLocal, length, Nil{})}))

# Packet must come from packetLocal/parse. Check the public record's
# span before computing its end, so even U32-sized invalid spans cannot wrap.
def decode(+packetLocal: Packet, value: Record) -> Result<&2, &2, EdnsResponseError, Response>:
  match value:
    case Record{Name{Nil{}}, +recordType, +class, ttl, +startLocal, +length}:
      boundedEdnsResponse(U32.is_eq(recordType, 41) && U32.is_le(class, 65535) && U32.is_le(length, 65535) && available(packetLocal, startLocal, length), packetLocal, class, ttl, startLocal, length)
    case _: Fail{InvalidOwner{}}

def hasOpt(values: List<&2, Record>) -> Bool:
  match values:
    case Nil{}: False{}
    case Record{_, code, _, _, _, _} <> rest: U32.is_eq(code, 41) || hasOpt(rest)

def optional(result: Result<&2, &2, EdnsResponseError, Response>) -> Result<&2, &2, EdnsResponseError, Maybe<&2, Response>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{response}: Done{Some{response}}

def selected(isOpt: Bool, packetLocal: Packet, value: Record, prior: Result<&2, &2, EdnsResponseError, Maybe<&2, Response>>) -> Result<&2, &2, EdnsResponseError, Maybe<&2, Response>>:
  match isOpt prior:
    case _ Fail{error}: Fail{error}
    case False{} prior: prior
    case True{} Done{Some{_}}: Fail{Duplicate{}}
    case True{} Done{None{}}: optional(decode(packetLocal, value))

def kindEdnsResponse(value: Record) -> U32:
  match value:
    case Record{_, code, _, _, _, _}: code

def scan(+packetLocal: Packet, values: List<&2, Record>, state: Result<&2, &2, EdnsResponseError, Maybe<&2, Response>>) -> Result<&2, &2, EdnsResponseError, Maybe<&2, Response>>:
  match values state:
    case _ Fail{error}: Fail{error}
    case Nil{} state: state
    case +value <> rest state: scan(packetLocal, rest, selected(U32.is_eq(kindEdnsResponse(value), 41), packetLocal, value, state))

def placement(invalid: Bool, packetLocal: Packet, values: List<&2, Record>) -> Result<&2, &2, EdnsResponseError, Maybe<&2, Response>>:
  match invalid:
    case True{}: Fail{Misplaced{}}
    case False{}: scan(packetLocal, values, Done{None{}})

# OPT may appear anywhere in additional, but nowhere else and at most once.
def inspect(message: Message) -> Result<&2, &2, EdnsResponseError, Maybe<&2, Response>>:
  match message:
    case Message{packetLocal, _, _, answers, authorities, additional}: placement(hasOpt(answers) || hasOpt(authorities), packetLocal, additional)

def responseCode(header: Header, extension: Maybe<&2, Response>) -> U32:
  match header extension:
    case Header{_, flags, _, _, _, _} None{}: (flags % 16 : U32)
    case Header{_, flags, _, _, _, _} Some{Response{_, upper, _, _, _}}: (upper * 16 + flags % 16 : U32)

def dnssecOk(value: Response) -> Bool:
  match value:
    case Response{_, _, _, flags, _}: U32.is_le(32768, flags)

# One immutable query intent, retained unchanged across transport retries.
# Absence of EDNS is explicit; transport never invents negotiation policy.
type Request is Data:
  Request{id: U32, flags: U32, question: Question, extension: Maybe<&2, Query>}

def plainQuery(id: U32, flags: U32, question: Question) -> Request:
  Request{id, flags, question, None{}}

# Settings shared by distinct questions in one lookup/search. IDs and question
# names are supplied separately, so alias follow-ups do not reuse either.
type QueryOptions is Data:
  QueryOptions{flags: U32, extension: Maybe<&2, Query>}

def defaults() -> QueryOptions: QueryOptions{256, None{}}

def createQuery(options: QueryOptions, id: U32, question: Question) -> Request:
  match options:
    case QueryOptions{flags, extension}: Request{id, flags, question, extension}

# Shared checked wire encoding for transport selection and transmission.
def encodedQuery(value: Result<&2, &2, Error, List<&2, U32>>) -> Result<&2, &2, EdnsError, List<&2, U32>>:
  match value:
    case Fail{error}: Fail{EdnsMessage{error}}
    case Done{bytes}: Done{bytes}

def encodeQuery(request: Request) -> Result<&2, &2, EdnsError, List<&2, U32>>:
  match request:
    case Request{id, flags, question, None{}}: encodedQuery(query(id, flags, question))
    case Request{id, flags, question, Some{extension}}: queryEdns(id, flags, question, extension)

# ID generation is separate from matching and pending-request ownership.
# Two uniformly random octets cover the full DNS ID range without modulo bias.
type IdError is Data:
  SourceFailure{code: U32, message: String}
  InvalidBytes{}

def octets(high: U32, low: U32, valid: Bool) -> Result<&2, &2, IdError, U32>:
  match valid:
    case True{}: Done{U32.or(U32.shln(high, 8n), low)}
    case False{}: Fail{InvalidBytes{}}

def decoded(result: Result<&1, &1, U32 & String, List<&2, U32>>) -> Result<&2, &2, IdError, U32>:
  match result:
    case Fail{Tuple{code, message}}: Fail{SourceFailure{code, message}}
    case Done{+high <> +low <> Nil{}}: octets(high, low, U32.is_le(high, 255) && U32.is_le(low, 255))
    case Done{_}: Fail{InvalidBytes{}}

def random(unused: Unit) -> IO(Result<&2, &2, IdError, U32>):
  do IO<Result<&2, &2, IdError, U32>>:
    bytes : Result<&1, &1, U32 & String, List<&2, U32>> <- Entropy.bytes(2)
    return decoded(bytes)

def fixed(value: U32) -> IO(Result<&2, &2, IdError, U32>):
  IO.pure(Result<&2, &2, IdError, U32>, Done{value})

# Flags correspond to the resolver's default-name, search-list and no-TLD
# policies. Input dot count/absolute status are supplied by the caller so text
# policy is not guessed from binary labels (which can themselves contain dotsLocal).
type Policy is Data:
  Policy{ndots: U32, defaultNames: Bool, searchNames: Bool, noTld: Bool}

type Origin is Data:
  Initial{}
  Suffix{index: Nat}
  Final{}

# Invalid configured domains occupy their original search position. Their
# candidate is a typed failure; response policy decides whether to continue.
type Domain is Data:
  Valid{name: Name}
  Invalid{error: DomainNameError}

type SearchCursor is Data:
  SearchCursor{base: Name, dotsLocal: U32, noTld: Bool, first: Bool, domains: List<&2, Domain>, index: Nat, triedDirect: Bool, triedRoot: Bool, searched: Bool}

type Step is Data:
  Exhausted{}
  Candidate{origin: Origin, name: Result<&2, &2, DomainNameError, Name>, nextLocal: SearchCursor}

def checkedSearch(+name: Name, encoded: Result<&2, &2, DomainNameError, List<&2, U32>>) -> Result<&2, &2, DomainNameError, Name>:
  match encoded:
    case Fail{error}: Fail{error}
    case Done{_}: Done{name}

def valid(+name: Name) -> Result<&2, &2, DomainNameError, Name>:
  checkedSearch(name, encodeName(name))

def prependSearch(reversed: List<&2, List<&2, U32>>, suffix: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match reversed:
    case Nil{}: suffix
    case label <> rest: prependSearch(rest, label <> suffix)

def joined(base: Name, domain: Name) -> Name:
  match base domain:
    case Name{labels} Name{suffix}: Name{prependSearch(List.reverse(&2, List<&2, U32>, labels), suffix)}

def root(name: Name) -> Bool:
  match name:
    case Name{Nil{}}: True{}
    case _: False{}

def domainList(allowed: Bool, all: Bool, domains: List<&2, Domain>) -> List<&2, Domain>:
  match allowed all domains:
    case False{} _ _: Nil{}
    case True{} True{} names: names
    case True{} False{} Nil{}: Nil{}
    case True{} False{} first <> _: first <> Nil{}

def preparedDomains(absolute: Bool, base: Name, +dotsLocal: U32, domains: List<&2, Domain>, policy: Policy) -> SearchCursor:
  match absolute policy:
    case True{} _: SearchCursor{base, dotsLocal, False{}, True{}, Nil{}, Zero{}, False{}, False{}, False{}}
    case False{} Policy{ndots, defaultNames, +searchNames, noTld}:
      SearchCursor{base, dotsLocal, noTld, U32.is_ge(dotsLocal, ndots), domainList(Bool.pick(Bool, U32.is_zero(dotsLocal), defaultNames, searchNames), searchNames, domains), Zero{}, False{}, False{}, False{}}

# Names are validated individually when requested, including the composed wire
# length. No candidate is silently removed merely because it cannot be encoded.
def startDomains(base: Name, dotsLocal: U32, absolute: Bool, domains: List<&2, Domain>, policy: Policy) -> SearchCursor:
  preparedDomains(absolute, base, dotsLocal, domains, policy)

def wrapDomains(names: List<&2, Name>, reversed: List<&2, Domain>) -> List<&2, Domain>:
  match names:
    case Nil{}: List.reverse(&2, Domain, reversed)
    case name <> rest: wrapDomains(rest, Valid{name} <> reversed)

# Existing callers supplying wire names retain the same entry point.
def prepared(absolute: Bool, base: Name, dotsLocal: U32, domains: List<&2, Name>, policy: Policy) -> SearchCursor:
  preparedDomains(absolute, base, dotsLocal, wrapDomains(domains, Nil{}), policy)

def start(base: Name, dotsLocal: U32, absolute: Bool, domains: List<&2, Name>, policy: Policy) -> SearchCursor:
  prepared(absolute, base, dotsLocal, domains, policy)

def domainRoot(domain: Domain) -> Bool:
  match domain:
    case Valid{name}: root(name)
    case Invalid{_}: False{}

def domainCandidate(base: Name, domain: Domain) -> Result<&2, &2, DomainNameError, Name>:
  match domain:
    case Valid{name}: valid(joined(base, name))
    case Invalid{error}: Fail{error}

def finalCandidate(allowed: Bool, +base: Name, dotsLocal: U32, noTld: Bool, index: Nat, triedRoot: Bool, searched: Bool) -> Step:
  match allowed:
    case False{}: Exhausted{}
    case True{}: Candidate{Final{}, valid(base), SearchCursor{base, dotsLocal, noTld, False{}, Nil{}, index, True{}, triedRoot, searched}}

def next(cursor: SearchCursor) -> Step:
  match cursor:
    case SearchCursor{+base, dotsLocal, noTld, True{}, domains, index, _, triedRoot, searched}:
      Candidate{Initial{}, valid(base), SearchCursor{base, dotsLocal, noTld, False{}, domains, index, True{}, triedRoot, searched}}
    case SearchCursor{+base, dotsLocal, noTld, False{}, +domain <> rest, +index, triedDirect, triedRoot, _}:
      Candidate{Suffix{index}, domainCandidate(base, domain), SearchCursor{base, dotsLocal, noTld, False{}, rest, Succ{index}, triedDirect, triedRoot || domainRoot(domain), True{}}}
    case SearchCursor{base, +dotsLocal, +noTld, False{}, Nil{}, index, triedDirect, +triedRoot, +searched}:
      finalCandidate(Bool.not(triedDirect || triedRoot) && (Bool.not(U32.is_zero(dotsLocal)) || Bool.not(searched) || Bool.not(noTld)), base, dotsLocal, noTld, index, triedRoot, searched)

# A response policy can stop suffix searching but still attempt the final bare
# name where allowed. Only actually yielded root suffixes suppress that attempt.
def stopSearch(cursor: SearchCursor) -> SearchCursor:
  match cursor:
    case SearchCursor{base, dotsLocal, noTld, first, _, index, triedDirect, triedRoot, searched}: SearchCursor{base, dotsLocal, noTld, first, Nil{}, index, triedDirect, triedRoot, searched}

# Resolver errorSearchResponse classes, independent of OS errno and libc integer constants.
type SearchResponseError is Data:
  NotFound{}
  NoData{}
  TryAgain{}
  NoRecovery{}

# Transport/answer adapters must classify a completed candidate explicitly.
# Refused means connection refusal, not the DNS REFUSED response code.
type Cause is Data:
  Missing{}
  EmptyAnswer{}
  ServerFailure{}
  TemporaryFailure{}
  Unrecoverable{}
  ConnectionRefused{}

type History is Data:
  History{initial: Maybe<&2, SearchResponseError>, noData: Bool, serverFailure: Bool, last: SearchResponseError}

type SearchResponseDecision is Data:
  Continue{cursor: SearchCursor, history: History}
  Stop{errorSearchResponse: SearchResponseError}

def new() -> History: History{None{}, False{}, False{}, NotFound{}}

def errorSearchResponse(cause: Cause) -> SearchResponseError:
  match cause:
    case Missing{}: NotFound{}
    case EmptyAnswer{}: NoData{}
    case Unrecoverable{}: NoRecovery{}
    case _: TryAgain{}

def exhausted(history: History) -> SearchResponseError:
  match history:
    case History{Some{value}, _, _, _}: value
    case History{None{}, True{}, _, _}: NoData{}
    case History{None{}, False{}, True{}, _}: TryAgain{}
    case History{None{}, False{}, False{}, value}: value

def suffixSearchResponse(cause: Cause, cursor: SearchCursor, history: History) -> SearchResponseDecision:
  match cause history:
    case ConnectionRefused{} _: Stop{TryAgain{}}
    case Missing{} History{initial, noData, serverFailure, _}: Continue{cursor, History{initial, noData, serverFailure, NotFound{}}}
    case EmptyAnswer{} History{initial, _, serverFailure, _}: Continue{cursor, History{initial, True{}, serverFailure, NoData{}}}
    case ServerFailure{} History{initial, noData, _, _}: Continue{cursor, History{initial, noData, True{}, TryAgain{}}}
    case TemporaryFailure{} History{initial, noData, serverFailure, _}: Continue{stopSearch(cursor), History{initial, noData, serverFailure, TryAgain{}}}
    case Unrecoverable{} History{initial, noData, serverFailure, _}: Continue{stopSearch(cursor), History{initial, noData, serverFailure, NoRecovery{}}}

# Called only after failure. Success finishes immediately in the enclosing
# driver. An absolute initial name has an already exhausted continuation.
def failed(origin: Origin, cause: Cause, cursor: SearchCursor, history: History) -> SearchResponseDecision:
  match origin history:
    case Initial{} History{_, noData, serverFailure, _}:
      +value = errorSearchResponse(cause)
      Continue{cursor, History{Some{value}, noData, serverFailure, value}}
    case Final{} History{initial, noData, serverFailure, _}: Continue{cursor, History{initial, noData, serverFailure, errorSearchResponse(cause)}}
    case Suffix{_} previous: suffixSearchResponse(cause, cursor, previous)

type SearchRunRequest is Data:
  SearchRunRequest{origin: Origin, name: Name}

type Outcome<-Failure: Data, -Value: Data> is Data:
  Answer{value: Value}
  SearchRunFailed{cause: Cause}
  SearchHalt{failure: Failure}

type SearchRunError<-Failure: Data> is Data:
  NoAnswer{error: SearchResponseError}
  Halted{failure: Failure}

type Progress<-Failure: Data, -Value: Data> is Data:
  Active{cursor: SearchCursor, history: History}
  SearchRunFinished{result: Result<&2, &2, SearchRunError<Failure>, Value>}

def decided(-Failure: Data, -Value: Data, decision: SearchResponseDecision) -> Progress<Failure, Value>:
  match decision:
    case Continue{cursor, history}: Active{cursor, history}
    case Stop{error}: SearchRunFinished{Fail{NoAnswer{error}}}

def received(-Failure: Data, -Value: Data, origin: Origin, cursor: SearchCursor, history: History, outcome: Outcome<Failure, Value>) -> Progress<Failure, Value>:
  match outcome:
    case Answer{value}: SearchRunFinished{Done{value}}
    case SearchHalt{failure}: SearchRunFinished{Fail{Halted{failure}}}
    case SearchRunFailed{cause}: decided(Failure, Value, failed(origin, cause, cursor, history))

def candidateSearchRun(~Environment: Data, ~Failure: Data, ~Value: Data, ~request: Environment -> SearchRunRequest -> IO(Outcome<Failure, Value>), environment: Environment, +origin: Origin, cursor: SearchCursor, history: History, name: Result<&2, &2, DomainNameError, Name>) -> IO(Progress<Failure, Value>):
  match name:
    case Fail{_}: IO.pure(Progress<Failure, Value>, decided(Failure, Value, failed(origin, Unrecoverable{}, cursor, history)))
    case Done{value}:
      do IO<Progress<Failure, Value>>:
        outcome : Outcome<Failure, Value> <- request(environment, SearchRunRequest{origin, value})
        return received(Failure, Value, origin, cursor, history, outcome)

def advance(~Environment: Data, ~Failure: Data, ~Value: Data, ~request: Environment -> SearchRunRequest -> IO(Outcome<Failure, Value>), environment: Environment, history: History, step: Step) -> IO(Progress<Failure, Value>):
  match step:
    case Exhausted{}: IO.pure(Progress<Failure, Value>, SearchRunFinished{Fail{NoAnswer{exhausted(history)}}})
    case Candidate{origin, name, nextLocal}: candidateSearchRun(~Environment, ~Failure, ~Value, ~request, environment, origin, nextLocal, history, name)

# Each advance consumes a suffix or a direct-name phase; response policy can
# only discard additional suffixes. That finite progress crosses record fields
# and IO binds, hence the local annotation instead of an arbitrary retry limit.
@unsafe def drive(~Environment: Data, ~Failure: Data, ~Value: Data, ~request: Environment -> SearchRunRequest -> IO(Outcome<Failure, Value>), +environment: Environment, progress: Progress<Failure, Value>) -> IO(Result<&2, &2, SearchRunError<Failure>, Value>):
  match progress:
    case SearchRunFinished{result}: IO.pure(Result<&2, &2, SearchRunError<Failure>, Value>, result)
    case Active{cursor, history}:
      do IO<Result<&2, &2, SearchRunError<Failure>, Value>>:
        nextLocal : Progress<Failure, Value> <- advance(~Environment, ~Failure, ~Value, ~request, environment, history, next(cursor))
        drive(~Environment, ~Failure, ~Value, ~request, environment, nextLocal)

# The request function owns each exchange until it returns. The environment is
# borrowed and remains caller-owned. SearchHalt preserves non-DNS errors immediately;
# no earlier search failure can override cancellation/entropy/cleanup failures.
def runSearchRun(~Environment: Data, ~Failure: Data, ~Value: Data, ~request: Environment -> SearchRunRequest -> IO(Outcome<Failure, Value>), environment: Environment, cursor: SearchCursor) -> IO(Result<&2, &2, SearchRunError<Failure>, Value>):
  drive(~Environment, ~Failure, ~Value, ~request, environment, Active{cursor, new()})

# The search threshold counts presentation dotsLocal, including the terminal dot.
# Parsing first bounds the accepted input before conversion to the U32 API.
type Input is Data:
  Input{name: Name, dotsLocal: U32, absolute: Bool}

def countedSearchText(dot: Bool, rest: Nat) -> Nat:
  match dot:
    case True{}: Succ{rest}
    case False{}: rest

def dots(text: String) -> Nat:
  match text:
    case SNil{}: 0n
    case SCon{Chr{code}, rest}: countedSearchText(U32.is_eq(code, 46), dots(rest))

def parsedSearchText(text: String, result: Result<&2, &2, PresentationError, PresentationParsed>) -> Result<&2, &2, PresentationError, Input>:
  match result:
    case Fail{error}: Fail{error}
    case Done{PresentationParsed{name, absolute}}: Done{Input{name, U32.from_nat(dots(text)), absolute}}

def prepare(+text: String) -> Result<&2, &2, PresentationError, Input>:
  parsedSearchText(text, parsePresentation(text))

# One search candidate is shared by both callbacks. The caller supplies the
# protocol-aware merge over full reports; no partial result is interpreted as
# permission to advance to another suffix. The borrowed environment carries
# the shared deadline and any per-candidate transport policy.
def merged(~Left: Data, ~Right: Data, ~Failure: Data, ~Value: Data, ~merge: Left -> Right -> Outcome<Failure, Value>, reports: Left & Right) -> Outcome<Failure, Value>:
  match reports:
    case (left, right): merge(left, right)

def candidate(~Environment: Data, ~Left: Data, ~Right: Data, ~Failure: Data, ~Value: Data, ~left: Environment -> SearchRunRequest -> IO(Left), ~right: Environment -> SearchRunRequest -> IO(Right), ~merge: Left -> Right -> Outcome<Failure, Value>, environment: Environment, request: SearchRunRequest) -> IO(Outcome<Failure, Value>):
  +sharedEnvironment = environment
  +sharedRequest = request
  do IO<Outcome<Failure, Value>>:
    reports : Left & Right <- Pair.both(Left, Right, left(sharedEnvironment, sharedRequest), right(sharedEnvironment, sharedRequest))
    return merged(~Left, ~Right, ~Failure, ~Value, ~merge, reports)

# Search advances only after both children have returned and been joined.
# Callbacks own cleanup; a shared abort/deadline must make each one finish.
def run(~Environment: Data, ~Left: Data, ~Right: Data, ~Failure: Data, ~Value: Data, ~left: Environment -> SearchRunRequest -> IO(Left), ~right: Environment -> SearchRunRequest -> IO(Right), ~merge: Left -> Right -> Outcome<Failure, Value>, environment: Environment, cursor: SearchCursor) -> IO(Result<&2, &2, SearchRunError<Failure>, Value>):
  runSearchRun(~Environment, ~Failure, ~Value, ~candidate(~Environment, ~Left, ~Right, ~Failure, ~Value, ~left, ~right, ~merge), environment, cursor)

type Family is Data:
  IPv4{}
  IPv6{}

type Queries is Data:
  Queries{ipv4: Request, ipv6: Request}

type PairQueriesError is Data:
  Encoding{family: Family, error: EdnsError}

def create(+options: QueryOptions, id4: U32, id6: U32, +name: Name) -> Queries:
  Queries{createQuery(options, id4, Question{name, 1, 1}), createQuery(options, id6, Question{name, 28, 1})}

def checked(queries: Queries, first: Result<&2, &2, EdnsError, List<&2, U32>>, second: Result<&2, &2, EdnsError, List<&2, U32>>) -> Result<&2, &2, PairQueriesError, Queries>:
  match first second:
    case Fail{error} _: Fail{Encoding{IPv4{}, error}}
    case Done{_} Fail{error}: Fail{Encoding{IPv6{}, error}}
    case Done{_} Done{_}: Done{queries}

# Validate both exact requests before a caller commits shared server rotation.
# Encoded bytes are temporary validation evidence, not a second query intent.
def validate(queries: Queries) -> Result<&2, &2, PairQueriesError, Queries>:
  match queries:
    case Queries{+ipv4, +ipv6}: checked(Queries{ipv4, ipv6}, encodeQuery(ipv4), encodeQuery(ipv6))
