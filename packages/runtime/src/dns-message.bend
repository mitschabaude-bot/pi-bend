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
  Packet{size: U32, bytes: Map<&2, U32>}

def key(+index: U32) -> String:
  SCon{Chr{(index / 256 : U32)}, SCon{Chr{(index % 256 : U32)}, SNil{}}}

def inserted(valid: Bool, +index: U32, byte: U32, bytes: Map<&2, U32>) -> Result<&2, &2, DomainNameError, Packet>:
  match valid:
    case False{}: Fail{NameInvalidByte{}}
    case True{}: Done{Packet{(index + 1 : U32), Map.set(&2, U32, bytes, key(index), byte)}}

def insert(result: Result<&2, &2, DomainNameError, Packet>, +byte: U32) -> Result<&2, &2, DomainNameError, Packet>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Packet{65535, _}}: Fail{PacketTooLong{}}
    case Done{Packet{index, bytes}}: inserted(U32.is_le(byte, 255), index, byte, bytes)

# An immutable offset index avoids scanning the packet for each pointer.
def packetLoop(input: List<&2, U32>, result: Result<&2, &2, DomainNameError, Packet>) -> Result<&2, &2, DomainNameError, Packet>:
  match input result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case value <> rest packet: packetLoop(rest, insert(packet, value))

def parsePacket(input: List<&2, U32>) -> Result<&2, &2, DomainNameError, Packet>:
  packetLoop(input, Done{Packet{0, MTip{}}})

def found(value: Map<&2, U32> & U32) -> U32:
  match value:
    case (_, byte): byte

def boundedByte(valid: Bool, bytes: Map<&2, U32>, index: U32) -> U32:
  match valid:
    case False{}: 256
    case True{}: found(Map.get(U32, 256, bytes, key(index)))

def byteAt(packet: Packet, +index: U32) -> U32:
  match packet:
    case Packet{size, bytes}: boundedByte(U32.is_lt(index, size), bytes, index)

type Decoded is Data:
  Decoded{name: Name, next: U32}

type Mode is Data:
  Head{}
  Label{left: U32, reversed: List<&2, U32>}
  Pointer{high: U32}

type State is Data:
  Reading{position: U32, ceiling: U32, next: Maybe<&2, U32>, length: U32, reversed: List<&2, List<&2, U32>>, mode: Mode}
  Finished{value: Decoded}
  Failed{error: DomainNameError}

def nextOffset(following: Maybe<&2, U32>, fallback: U32) -> U32:
  match following:
    case None{}: fallback
    case Some{value}: value

def labelHead(valid: Bool, position: U32, ceiling: U32, following: Maybe<&2, U32>, length: U32, labels: List<&2, List<&2, U32>>, count: U32) -> State:
  match valid:
    case False{}: Failed{NameTooLong{}}
    case True{}: Reading{position, ceiling, following, length, labels, Label{count, Nil{}}}

def headFlags(zero: Bool, label: Bool, pointer: Bool, +tag: U32, position: U32, ceiling: U32, following: Maybe<&2, U32>, +length: U32, labels: List<&2, List<&2, U32>>) -> State:
  match zero label pointer:
    case True{} _ _: Finished{Decoded{Name{List.reverse(&2, List<&2, U32>, labels)}, nextOffset(following, position)}}
    case False{} True{} _: labelHead(U32.is_le((length + tag + 1 : U32), 255), position, ceiling, following, (length + tag + 1 : U32), labels, tag)
    case False{} False{} True{}: Reading{position, ceiling, following, length, labels, Pointer{(tag - 192 : U32)}}
    case _ _ _: Failed{ReservedLabel{}}

def head(+tag: U32, position: U32, ceiling: U32, following: Maybe<&2, U32>, length: U32, labels: List<&2, List<&2, U32>>) -> State:
  headFlags(U32.is_eq(tag, 0), U32.is_lt(tag, 64), U32.is_ge(tag, 192), tag, position, ceiling, following, length, labels)

def pointed(valid: Bool, +target: U32, position: U32, following: Maybe<&2, U32>, length: U32, labels: List<&2, List<&2, U32>>) -> State:
  match valid:
    case False{}: Failed{InvalidPointer{}}
    case True{}: Reading{target, target, Some{nextOffset(following, position)}, length, labels, Head{}}

def consume(mode: Mode, +value: U32, +position: U32, +ceiling: U32, following: Maybe<&2, U32>, length: U32, labels: List<&2, List<&2, U32>>) -> State:
  match mode:
    case Head{}: head(value, position, ceiling, following, length, labels)
    case Label{1, reversed}: Reading{position, ceiling, following, length, List.reverse(&2, U32, value <> reversed) <> labels, Head{}}
    case Label{left, reversed}: Reading{position, ceiling, following, length, labels, Label{(left - 1 : U32), value <> reversed}}
    case Pointer{+high}: pointed(U32.is_lt((high * 256 + value : U32), ceiling), (high * 256 + value : U32), position, following, length, labels)

def present(valid: Bool, mode: Mode, value: U32, position: U32, ceiling: U32, following: Maybe<&2, U32>, length: U32, labels: List<&2, List<&2, U32>>) -> State:
  match valid:
    case False{}: Failed{NameTruncated{}}
    case True{}: consume(mode, value, position, ceiling, following, length, labels)

def step(packet: Packet, state: State) -> State:
  match state:
    case Reading{+position, ceiling, following, length, labels, mode}:
      +value = byteAt(packet, position)
      present(U32.is_le(value, 255), mode, value, (position + 1 : U32), ceiling, following, length, labels)
    case final: final

# Every pointer must refer to an earlier name segment. The ceiling strictly
# decreases on a jump, rejecting self/forward/cyclic references. Labels count
# toward the expanded 255-octet limit, including their lengths and root.
def loop(fuel: Nat, +packet: Packet, state: State) -> Result<&2, &2, DomainNameError, Decoded>:
  match fuel state:
    case _ Finished{value}: Done{value}
    case _ Failed{error}: Fail{error}
    case Zero{} _: Fail{InvalidPointer{}}
    case Succ{rest} reading: loop(rest, packet, step(packet, reading))

def decodeName(packet: Packet, +position: U32) -> Result<&2, &2, DomainNameError, Decoded>:
  loop(65536n, packet, Reading{position, position, None{}, 1, Nil{}, Head{}})

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
    case Done{EncodedLabel{+length, reversed}} Done{EncodedLabel{+size, bytes}}: appended(U32.is_le((length + size + 1 : U32), 255), (length + size + 1 : U32), List.append(&2, U32, bytes, size <> reversed))

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
  Header{id: U32, flags: U32, questions: U32, answers: U32, authorities: U32, additional: U32}

type Question is Data:
  Question{name: Name, kind: U32, class: U32}

# RDATA stays a span in the original immutable packet. Compression offsets
# inside CNAME/SOA/etc. remain meaningful; opaque record types stay lossless.
type Record is Data:
  Record{name: Name, kind: U32, class: U32, ttl: U32, start: U32, length: U32}

type Message is Data:
  Message{packet: Packet, header: Header, questions: List<&2, Question>, answers: List<&2, Record>, authorities: List<&2, Record>, additional: List<&2, Record>}

type Parsed<-Item: Data> is Data:
  Parsed{value: Item, next: U32}

type Error is Data:
  NameError{error: DomainNameError}
  Truncated{}
  TrailingData{}
  InvalidField{}

def packetSize(packet: Packet) -> U32:
  match packet:
    case Packet{value, _}: value

def available(+packet: Packet, +position: U32, count: U32) -> Bool:
  U32.is_le(position, packetSize(packet)) && U32.is_le(count, (packetSize(packet) - position : U32))

# Call only after validating the containing fixed-size field.
def word(+packet: Packet, +position: U32) -> U32:
  (byteAt(packet, position) * 256 + byteAt(packet, (position + 1 : U32)) : U32)

def headerFields(valid: Bool, +packet: Packet) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{Truncated{}}
    case True{}: Done{Header{word(packet, 0), word(packet, 2), word(packet, 4), word(packet, 6), word(packet, 8), word(packet, 10)}}

def header(+packet: Packet) -> Result<&2, &2, Error, Header>:
  headerFields(available(packet, 0, 12), packet)

def questionFields(valid: Bool, +packet: Packet, name: Name, +position: U32) -> Result<&2, &2, Error, Parsed<Question>>:
  match valid:
    case False{}: Fail{Truncated{}}
    case True{}: Done{Parsed{Question{name, word(packet, position), word(packet, (position + 2 : U32))}, (position + 4 : U32)}}

def questionName(+packet: Packet, value: Result<&2, &2, DomainNameError, Decoded>) -> Result<&2, &2, Error, Parsed<Question>>:
  match value:
    case Fail{error}: Fail{NameError{error}}
    case Done{Decoded{name, +following}}: questionFields(available(packet, following, 4), packet, name, following)

def parsedQuestion(+packet: Packet, position: U32) -> Result<&2, &2, Error, Parsed<Question>>:
  questionName(packet, decodeName(packet, position))

def recordData(valid: Bool, name: Name, kind: U32, class: U32, ttl: U32, +offset: U32, +length: U32) -> Result<&2, &2, Error, Parsed<Record>>:
  match valid:
    case False{}: Fail{Truncated{}}
    case True{}: Done{Parsed{Record{name, kind, class, ttl, offset, length}, (offset + length : U32)}}

def recordFields(valid: Bool, +packet: Packet, name: Name, +position: U32) -> Result<&2, &2, Error, Parsed<Record>>:
  match valid:
    case False{}: Fail{Truncated{}}
    case True{}:
      +length = word(packet, (position + 8 : U32))
      +offset = (position + 10 : U32)
      recordData(available(packet, offset, length), name, word(packet, position), word(packet, (position + 2 : U32)), (word(packet, (position + 4 : U32)) * 65536 + word(packet, (position + 6 : U32)) : U32), offset, length)

def recordName(+packet: Packet, value: Result<&2, &2, DomainNameError, Decoded>) -> Result<&2, &2, Error, Parsed<Record>>:
  match value:
    case Fail{error}: Fail{NameError{error}}
    case Done{Decoded{name, +following}}: recordFields(available(packet, following, 10), packet, name, following)

def record(+packet: Packet, position: U32) -> Result<&2, &2, Error, Parsed<Record>>:
  recordName(packet, decodeName(packet, position))

def added(-Item: Data, reversed: List<&2, Item>, value: Result<&2, &2, Error, Parsed<Item>>) -> Result<&2, &2, Error, Parsed<List<&2, Item>>>:
  match value:
    case Fail{error}: Fail{error}
    case Done{Parsed{item, following}}: Done{Parsed{item <> reversed, following}}

# Parser callbacks are pure values. Section counts guide traversal but never
# authorize reading beyond the packet; malformed counts stop at the first error.
def section(~Item: Data, ~parse: (Packet -> U32 -> Result<&2, &2, Error, Parsed<Item>>), count: Nat, +packet: Packet, state: Result<&2, &2, Error, Parsed<List<&2, Item>>>) -> Result<&2, &2, Error, Parsed<List<&2, Item>>>:
  match count state:
    case _ Fail{error}: Fail{error}
    case Zero{} Done{Parsed{reversed, following}}: Done{Parsed{List.reverse(&2, Item, reversed), following}}
    case Succ{rest} Done{Parsed{reversed, following}}: section(~Item, ~parse, rest, packet, added(Item, reversed, parse(packet, following)))

def complete(valid: Bool, packet: Packet, header: Header, questions: List<&2, Question>, answers: List<&2, Record>, authorities: List<&2, Record>, additional: List<&2, Record>) -> Result<&2, &2, Error, Message>:
  match valid:
    case False{}: Fail{TrailingData{}}
    case True{}: Done{Message{packet, header, questions, answers, authorities, additional}}

def additionals(+packet: Packet, header: Header, questions: List<&2, Question>, answers: List<&2, Record>, authorities: List<&2, Record>, result: Result<&2, &2, Error, Parsed<List<&2, Record>>>) -> Result<&2, &2, Error, Message>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Parsed{additional, following}}: complete(U32.is_eq(packetSize(packet), following), packet, header, questions, answers, authorities, additional)

def parsedAuthorities(+packet: Packet, header: Header, count: U32, questions: List<&2, Question>, answers: List<&2, Record>, result: Result<&2, &2, Error, Parsed<List<&2, Record>>>) -> Result<&2, &2, Error, Message>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Parsed{values, following}}: additionals(packet, header, questions, answers, values, section(~Record, ~(p => i => record(p, i)), U32.to_nat(count), packet, Done{Parsed{Nil{}, following}}))

def parsedAnswers(+packet: Packet, header: Header, authorityCount: U32, additionalCount: U32, questions: List<&2, Question>, result: Result<&2, &2, Error, Parsed<List<&2, Record>>>) -> Result<&2, &2, Error, Message>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Parsed{values, following}}: parsedAuthorities(packet, header, additionalCount, questions, values, section(~Record, ~(p => i => record(p, i)), U32.to_nat(authorityCount), packet, Done{Parsed{Nil{}, following}}))

def questions(+packet: Packet, header: Header, answerCount: U32, authorityCount: U32, additionalCount: U32, result: Result<&2, &2, Error, Parsed<List<&2, Question>>>) -> Result<&2, &2, Error, Message>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Parsed{values, following}}: parsedAnswers(packet, header, authorityCount, additionalCount, values, section(~Record, ~(p => i => record(p, i)), U32.to_nat(answerCount), packet, Done{Parsed{Nil{}, following}}))

def withHeader(+packet: Packet, value: Result<&2, &2, Error, Header>) -> Result<&2, &2, Error, Message>:
  match value:
    case Fail{error}: Fail{error}
    case Done{Header{id, flags, +qd, +an, +ns, +ar}}: questions(packet, Header{id, flags, qd, an, ns, ar}, an, ns, ar, section(~Question, ~(p => i => parsedQuestion(p, i)), U32.to_nat(qd), packet, Done{Parsed{Nil{}, 12}}))

def fromPacket(value: Result<&2, &2, DomainNameError, Packet>) -> Result<&2, &2, Error, Message>:
  match value:
    case Fail{error}: Fail{NameError{error}}
    case Done{+packet}: withHeader(packet, header(packet))

def parse(bytes: List<&2, U32>) -> Result<&2, &2, Error, Message>:
  fromPacket(parsePacket(bytes))

# Uncompressed single-question query. Caller supplies transaction ID and flags
# (e.g. recursion desired); validation/matching policy remains explicit above.
def u16(+value: U32, tail: List<&2, U32>) -> List<&2, U32>:
  (value / 256 : U32) <> (value % 256 : U32) <> tail

def queryName(id: U32, flags: U32, kind: U32, class: U32, encoded: Result<&2, &2, DomainNameError, List<&2, U32>>) -> Result<&2, &2, Error, List<&2, U32>>:
  match encoded:
    case Fail{error}: Fail{NameError{error}}
    case Done{bytes}: Done{u16(id, u16(flags, 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> List.append(&2, U32, bytes, u16(kind, u16(class, Nil{})))))}

def queryFields(valid: Bool, id: U32, flags: U32, question: Question) -> Result<&2, &2, Error, List<&2, U32>>:
  match valid question:
    case False{} _: Fail{InvalidField{}}
    case True{} Question{name, kind, class}: queryName(id, flags, kind, class, encodeName(name))

def query(+id: U32, +flags: U32, question: Question) -> Result<&2, &2, Error, List<&2, U32>>:
  match question:
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
  Cursor{labels: List<&2, List<&2, U32>>, label: List<&2, U32>, size: U32, total: U32}

type PresentationState is Data:
  PresentationState{cursor: Cursor, mode: PresentationMode, absolute: Bool}

def byteAdded(fits: Bool, byte: U32, labels: List<&2, List<&2, U32>>, label: List<&2, U32>, size: U32, total: U32) -> Result<&2, &2, PresentationError, Cursor>:
  match fits:
    case False{}: Fail{PresentationNameTooLong{}}
    case True{}: Done{Cursor{labels, byte <> label, (size + 1 : U32), total}}

def withinLabel(valid: Bool, byte: U32, labels: List<&2, List<&2, U32>>, label: List<&2, U32>, +size: U32, total: U32) -> Result<&2, &2, PresentationError, Cursor>:
  match valid:
    case False{}: Fail{LabelTooLong{}}
    case True{}:
      +following = (total + Bool.pick(U32, U32.is_zero(size), 2, 1) : U32)
      byteAdded(U32.is_le(following, 255), byte, labels, label, size, following)

def appendByte(byte: U32, cursor: Cursor) -> Result<&2, &2, PresentationError, Cursor>:
  match cursor:
    case Cursor{labels, label, +size, total}: withinLabel(U32.is_lt(size, 63), byte, labels, label, size, total)

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

def escaped(digit: Bool, byte: U32, cursor: Cursor) -> Result<&2, &2, PresentationError, PresentationState>:
  match digit:
    case True{}: Done{PresentationState{cursor, SecondDigit{(byte - 48 : U32)}, False{}}}
    case False{}: stateResult(appendByte(byte, cursor))

def second(valid: Bool, byte: U32, value: U32, cursor: Cursor) -> Result<&2, &2, PresentationError, PresentationState>:
  match valid:
    case False{}: Fail{InvalidEscape{}}
    case True{}: Done{PresentationState{cursor, ThirdDigit{(value * 10 + byte - 48 : U32)}, False{}}}

def isDigit(+byte: U32) -> Bool: U32.is_ge(byte, 48) && U32.is_le(byte, 57)

def plain(byte: U32, last: Bool, cursor: Cursor) -> Result<&2, &2, PresentationError, PresentationState>:
  match byte:
    case 92: Done{PresentationState{cursor, Escape{}, False{}}}
    case 46: separator(last, cursor)
    case value: stateResult(appendByte(value, cursor))

def stepPresentation(+byte: U32, last: Bool, state: PresentationState) -> Result<&2, &2, PresentationError, PresentationState>:
  match state:
    case PresentationState{cursor, Plain{}, _}: plain(byte, last, cursor)
    case PresentationState{cursor, Escape{}, _}: escaped(isDigit(byte), byte, cursor)
    case PresentationState{cursor, SecondDigit{number}, _}: second(isDigit(byte), byte, number, cursor)
    case PresentationState{cursor, ThirdDigit{number}, _}:
      +accumulated = (number * 10 + byte - 48 : U32)
      decimalByte(isDigit(byte) && U32.is_le(accumulated, 255), accumulated, cursor)

def checkedByte(valid: Bool, byte: U32, last: Bool, state: PresentationState) -> Result<&2, &2, PresentationError, PresentationState>:
  match valid byte:
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
    case +byte <> +rest Done{value}: scanPresentation(rest, checkedByte(U32.is_le(byte, 255), byte, empty(rest), value))

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

def integer(+packet: Packet, +offset: U32) -> U32:
  (word(packet, offset) * 65536 + word(packet, (offset + 2 : U32)) : U32)

def address4(valid: Bool, packet: Packet, offset: U32) -> Result<&2, &2, RecordError, Value>:
  match valid:
    case False{}: Fail{InvalidLength{}}
    case True{}: Done{A{IPv4.Address{integer(packet, offset)}}}

def address6(valid: Bool, +packet: Packet, +offset: U32) -> Result<&2, &2, RecordError, Value>:
  match valid:
    case False{}: Fail{InvalidLength{}}
    case True{}: Done{AAAA{IPv6.Ipv6Address{integer(packet, offset), integer(packet, (offset + 4 : U32)), integer(packet, (offset + 8 : U32)), integer(packet, (offset + 12 : U32))}}}

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
    case Done{Decoded{target, following}}: exactName(U32.is_eq(following, end), kind, target)

def soaFields(valid: Bool, +packet: Packet, primary: Name, mailbox: Name, +offset: U32) -> Result<&2, &2, RecordError, Value>:
  match valid:
    case False{}: Fail{InvalidLength{}}
    case True{}: Done{SOA{primary, mailbox, integer(packet, offset), integer(packet, (offset + 4 : U32)), integer(packet, (offset + 8 : U32)), integer(packet, (offset + 12 : U32)), integer(packet, (offset + 16 : U32))}}

def soaMailbox(packet: Packet, primary: Name, end: U32, result: Result<&2, &2, DomainNameError, Decoded>) -> Result<&2, &2, RecordError, Value>:
  match result:
    case Fail{error}: Fail{InvalidName{error}}
    case Done{Decoded{mailbox, +following}}: soaFields(U32.is_eq((following + 20 : U32), end), packet, primary, mailbox, following)

def soaMore(valid: Bool, +packet: Packet, primary: Name, end: U32, following: U32) -> Result<&2, &2, RecordError, Value>:
  match valid:
    case False{}: Fail{InvalidLength{}}
    case True{}: soaMailbox(packet, primary, end, decodeName(packet, following))

def soaPrimary(packet: Packet, +end: U32, result: Result<&2, &2, DomainNameError, Decoded>) -> Result<&2, &2, RecordError, Value>:
  match result:
    case Fail{error}: Fail{InvalidName{error}}
    case Done{Decoded{primary, +following}}: soaMore(U32.is_lt(following, end), packet, primary, end, following)

def kindFields(+packet: Packet, kind: U32, +offset: U32, +length: U32, original: Record) -> Result<&2, &2, RecordError, Value>:
  match kind:
    case 1: address4(U32.is_eq(length, 4), packet, offset)
    case 28: address6(U32.is_eq(length, 16), packet, offset)
    case 5: nameResult(5, (offset + length : U32), decodeName(packet, offset))
    case 2: nameResult(2, (offset + length : U32), decodeName(packet, offset))
    case 12: nameResult(12, (offset + length : U32), decodeName(packet, offset))
    case 6: soaPrimary(packet, (offset + length : U32), decodeName(packet, offset))
    case _: Done{Opaque{original}}

def classFields(class: U32, packet: Packet, kind: U32, offset: U32, length: U32, original: Record) -> Result<&2, &2, RecordError, Value>:
  match class:
    case 1: kindFields(packet, kind, offset, length, original)
    case _: Done{Opaque{original}}

def fields(packet: Packet, record: Record) -> Result<&2, &2, RecordError, Value>:
  match record:
    case Record{name, +kind, +class, ttl, +offset, +length}: classFields(class, packet, kind, offset, length, Record{name, kind, class, ttl, offset, length})

def checkedRecord(valid: Bool, packet: Packet, record: Record) -> Result<&2, &2, RecordError, Value>:
  match valid:
    case False{}: Fail{InvalidSpan{}}
    case True{}: fields(packet, record)

# Validate even manually constructed spans. parse already checks them,
# but callers may supply a record independently. Unknown data stays opaque.
def decodeRecord(+packet: Packet, record: Record) -> Result<&2, &2, RecordError, Value>:
  match record:
    case Record{name, kind, class, ttl, +offset, +length}: checkedRecord(available(packet, offset, length), packet, Record{name, kind, class, ttl, offset, length})

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
  ResponseTruncated{parsedHeader: Header}
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

def matched(truncated: Bool, packet: Packet, parsedHeader: Header) -> Decision:
  match truncated:
    case True{}: ResponseTruncated{parsedHeader}
    case False{}: parsed(withHeader(packet, Done{parsedHeader}))

def questionMatches(equal: Bool, packet: Packet, parsedHeader: Header, flags: U32) -> Decision:
  match equal:
    case False{}: Ignore{QuestionMismatch{}}
    case True{}: matched(U32.is_ne(U32.and(flags, 512), 0), packet, parsedHeader)

def checkedQuestion(packet: Packet, parsedHeader: Header, flags: U32, expected: Question, value: Result<&2, &2, Error, Parsed<Question>>) -> Decision:
  match value:
    case Fail{error}: Ignore{Malformed{error}}
    case Done{Parsed{actual, _}}: questionMatches(sameQuestion(expected, actual), packet, parsedHeader, flags)

def absentQuestion(allowed: Bool, packet: Packet, parsedHeader: Header, flags: U32) -> Decision:
  match allowed:
    case False{}: Ignore{QuestionCountMismatch{}}
    case True{}: matched(U32.is_ne(U32.and(flags, 512), 0), packet, parsedHeader)

def questionCount(optional: Bool, count: U32, +packet: Packet, parsedHeader: Header, flags: U32, expected: Question) -> Decision:
  match count:
    case 0: absentQuestion(optional, packet, parsedHeader, flags)
    case 1: checkedQuestion(packet, parsedHeader, flags, expected, parsedQuestion(packet, 12))
    case _: Ignore{QuestionCountMismatch{}}

def checkedHeader(equalId: Bool, response: Bool, equalOpcode: Bool, optional: Bool, count: U32, packet: Packet, parsedHeader: Header, flags: U32, expected: Question) -> Decision:
  match equalId response equalOpcode:
    case False{} _ _: Ignore{IdMismatch{}}
    case True{} False{} _: Ignore{NotResponse{}}
    case True{} True{} False{}: Ignore{OpcodeMismatch{}}
    case True{} True{} True{}: questionCount(optional, count, packet, parsedHeader, flags, expected)

def decideHeader(optional: Bool, packet: Packet, id: U32, opcode: U32, expected: Question, result: Result<&2, &2, Error, Header>) -> Decision:
  match result:
    case Fail{error}: Ignore{Malformed{error}}
    case Done{Header{+actualId, +flags, +qd, an, ns, ar}}: checkedHeader(U32.is_eq(id, actualId), U32.is_ne(U32.and(flags, 32768), 0), U32.is_eq(opcode, (flags / 2048 % 16 : U32)), optional, qd, packet, Header{actualId, flags, qd, an, ns, ar}, flags, expected)

def decidePacket(optional: Bool, id: U32, opcode: U32, expected: Question, value: Result<&2, &2, DomainNameError, Packet>) -> Decision:
  match value:
    case Fail{error}: Ignore{Malformed{NameError{error}}}
    case Done{+messagePacket}: decideHeader(optional, messagePacket, id, opcode, expected, header(messagePacket))

def endpoints(equal: Bool, optional: Bool, id: U32, opcode: U32, expected: Question, wire: List<&2, U32>) -> Decision:
  match equal:
    case False{}: Ignore{EndpointMismatch{}}
    case True{}: decidePacket(optional, id, opcode, expected, parsePacket(wire))

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

def tcpFrameLength(value: U32) -> ReadResult:
  match value:
    case 0: Frame{Nil{}, Nil{}}
    case count: More{Payload{count, Nil{}}}

def consumeTcpFrame(reader: Reader, byte: U32) -> ReadResult:
  match reader:
    case Prefix{}: More{LengthLow{byte}}
    case LengthLow{high}: tcpFrameLength((high * 256 + byte : U32))
    case Payload{1, reversed}: Frame{List.reverse(&2, U32, byte <> reversed), Nil{}}
    case Payload{remaining, reversed}: More{Payload{(remaining - 1 : U32), byte <> reversed}}

def checkedTcpFrame(valid: Bool, reader: Reader, byte: U32) -> ReadResult:
  match valid:
    case False{}: TcpFrameFailed{TcpFrameInvalidByte{byte}}
    case True{}: consumeTcpFrame(reader, byte)

def feed(input: List<&2, U32>, state: ReadResult) -> ReadResult:
  match input state:
    case rest Frame{bytes, _}: Frame{bytes, rest}
    case _ TcpFrameFailed{error}: TcpFrameFailed{error}
    case Nil{} More{reader}: More{reader}
    case +byte <> rest More{reader}: feed(rest, checkedTcpFrame(U32.is_le(byte, 255), reader, byte))

# Return at most one frame and the unread suffix, so the caller can process
# messages with backpressure rather than accumulating an unbounded event list.
def read(reader: Reader, input: List<&2, U32>) -> ReadResult:
  feed(input, More{reader})

def finish(reader: Reader) -> Result<&2, &2, TcpFrameError, Unit>:
  match reader:
    case Prefix{}: Done{Unit{}}
    case _: Fail{IncompleteFrame{}}

def countByte(valid: Bool, value: U32, count: U32) -> Result<&2, &2, TcpFrameError, U32>:
  match valid:
    case False{}: Fail{TcpFrameInvalidByte{value}}
    case True{}: Done{(count + 1 : U32)}

def increment(count: U32, +value: U32) -> Result<&2, &2, TcpFrameError, U32>:
  match count:
    case 65535: Fail{TcpFrameTooLong{}}
    case size: countByte(U32.is_le(value, 255), value, size)

def tcpFrameCount(bytes: List<&2, U32>, result: Result<&2, &2, TcpFrameError, U32>) -> Result<&2, &2, TcpFrameError, U32>:
  match bytes result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case byte <> rest Done{size}: tcpFrameCount(rest, increment(size, byte))

def encodedTcpFrame(bytes: List<&2, U32>, size: Result<&2, &2, TcpFrameError, U32>) -> Result<&2, &2, TcpFrameError, List<&2, U32>>:
  match size:
    case Fail{error}: Fail{error}
    case Done{+byteCount}: Done{(byteCount / 256 : U32) <> (byteCount % 256 : U32) <> bytes}

# Prefix and payload form one buffer for the socket writer. The caller owns
# DNS message validity and chooses when to pipeline another framed message.
def encodeTcpFrame(+bytes: List<&2, U32>) -> Result<&2, &2, TcpFrameError, List<&2, U32>>:
  encodedTcpFrame(bytes, tcpFrameCount(bytes, Done{0}))

# EDNS(0) request fields. Unknown option codes and duplicate options are
# preserved in order; interpreting individual option payloads is separate.
type Option is Data:
  Option{code: U32, data: List<&2, U32>}

type Query is Data:
  Query{payloadSize: U32, dnssecOk: Bool, options: List<&2, Option>}

type EdnsError is Data:
  EdnsInvalidField{}
  InvalidByte{value: U32}
  TooLong{}
  EdnsMessage{error: Error}

type Buffer is Data:
  Buffer{size: U32, reversed: List<&2, U32>}

def measured(result: Result<&2, &2, TcpFrameError, U32>) -> Result<&2, &2, EdnsError, U32>:
  match result:
    case Done{size}: Done{size}
    case Fail{TcpFrameInvalidByte{value}}: Fail{InvalidByte{value}}
    case Fail{_}: Fail{TooLong{}}

def prepend(reversed: List<&2, U32>, tail: List<&2, U32>) -> List<&2, U32>:
  match reversed:
    case Nil{}: tail
    case byte <> rest: prepend(rest, byte <> tail)

# Inputs to append have already been measured and checked as octets.
def append(bytes: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case Nil{}: reversed
    case byte <> rest: append(rest, byte <> reversed)

def optionFits(fits: Bool, code: U32, +length: U32, data: List<&2, U32>, size: U32, reversed: List<&2, U32>) -> Result<&2, &2, EdnsError, Buffer>:
  match fits:
    case False{}: Fail{TooLong{}}
    case True{}: Done{Buffer{(size + length + 4 : U32), append(data, append(u16(code, u16(length, Nil{})), reversed))}}

def optionSize(code: U32, data: List<&2, U32>, buffer: Buffer, result: Result<&2, &2, EdnsError, U32>) -> Result<&2, &2, EdnsError, Buffer>:
  match buffer result:
    case _ Fail{error}: Fail{error}
    case Buffer{+size, reversed} Done{+length}: optionFits(U32.is_le((size + length + 4 : U32), 65535), code, length, data, size, reversed)

def optionCode(valid: Bool, code: U32, +data: List<&2, U32>, buffer: Buffer) -> Result<&2, &2, EdnsError, Buffer>:
  match valid:
    case False{}: Fail{EdnsInvalidField{}}
    case True{}: optionSize(code, data, buffer, measured(tcpFrameCount(data, Done{0})))

def add(option: Option, buffer: Buffer) -> Result<&2, &2, EdnsError, Buffer>:
  match option:
    case Option{+code, data}: optionCode(U32.is_le(code, 65535), code, data, buffer)

def options(values: List<&2, Option>, result: Result<&2, &2, EdnsError, Buffer>) -> Result<&2, &2, EdnsError, Buffer>:
  match values result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case value <> rest Done{buffer}: options(rest, add(value, buffer))

def ednsRecord(payloadSize: U32, dnssecOkFlag: Bool, result: Result<&2, &2, EdnsError, Buffer>) -> Result<&2, &2, EdnsError, List<&2, U32>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Buffer{size, reversed}}:
      Done{0 <> 0 <> 41 <> u16(payloadSize, 0 <> 0 <> Bool.pick(U32, dnssecOkFlag, 128, 0) <> 0 <> u16(size, List.reverse(&2, U32, reversed)))}

def ednsRecordFields(valid: Bool, payloadSize: U32, dnssecOkFlag: Bool, values: List<&2, Option>) -> Result<&2, &2, EdnsError, List<&2, U32>>:
  match valid:
    case False{}: Fail{EdnsInvalidField{}}
    case True{}: ednsRecord(payloadSize, dnssecOkFlag, options(values, Done{Buffer{0, Nil{}}}))

# OPT uses the root owner, type 41, advertised payload in CLASS, version zero,
# zero extended RCODE and no reserved flag bits. Only the DO bit is settable.
def encode(value: Query) -> Result<&2, &2, EdnsError, List<&2, U32>>:
  match value:
    case Query{+payloadSize, dnssecOkFlag, values}: ednsRecordFields(U32.is_le(payloadSize, 65535), payloadSize, dnssecOkFlag, values)

def bounded(bytes: List<&2, U32>, size: Result<&2, &2, EdnsError, U32>) -> Result<&2, &2, EdnsError, List<&2, U32>>:
  match size:
    case Fail{error}: Fail{error}
    case Done{_}: Done{bytes}

def counted(+bytes: List<&2, U32>) -> Result<&2, &2, EdnsError, List<&2, U32>>:
  bounded(bytes, measured(tcpFrameCount(bytes, Done{0})))

# Input is the validated single-question message emitted by query.
# Replace ARCOUNT, append one OPT record and enforce the full message bound.
def attach(remaining: Nat, bytes: List<&2, U32>, reversed: List<&2, U32>, opt: List<&2, U32>) -> Result<&2, &2, EdnsError, List<&2, U32>>:
  match remaining bytes:
    case Zero{} _ <> _ <> body: counted(prepend(reversed, 0 <> 1 <> prepend(List.reverse(&2, U32, body), opt)))
    case Succ{rest} byte <> tail: attach(rest, tail, byte <> reversed, opt)
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

def copyBytes(count: Nat, +packet: Packet, +position: U32, reversed: List<&2, U32>) -> List<&2, U32>:
  match count:
    case Zero{}: List.reverse(&2, U32, reversed)
    case Succ{rest}: copyBytes(rest, packet, (position + 1 : U32), byteAt(packet, position) <> reversed)

def progress(empty: Bool, position: U32, remaining: U32, reversed: List<&2, Option>) -> Options:
  match empty:
    case True{}: Complete{List.reverse(&2, Option, reversed)}
    case False{}: Options{position, remaining, reversed}

def optionData(valid: Bool, packet: Packet, +position: U32, +remaining: U32, code: U32, +length: U32, reversed: List<&2, Option>) -> Result<&2, &2, EdnsResponseError, Options>:
  match valid:
    case False{}: Fail{TruncatedOption{}}
    case True{}: Done{progress(U32.is_eq(remaining, length), (position + length : U32), (remaining - length : U32), Option{code, copyBytes(U32.to_nat(length), packet, position, Nil{})} <> reversed)}

def optionHeader(valid: Bool, +packet: Packet, +position: U32, +remaining: U32, reversed: List<&2, Option>) -> Result<&2, &2, EdnsResponseError, Options>:
  match valid:
    case False{}: Fail{TruncatedOption{}}
    case True{}:
      +length = word(packet, (position + 2 : U32))
      optionData(U32.is_le(length, (remaining - 4 : U32)), packet, (position + 4 : U32), (remaining - 4 : U32), word(packet, position), length, reversed)

def optionLoop(fuel: Nat, +packet: Packet, state: Result<&2, &2, EdnsResponseError, Options>) -> Result<&2, &2, EdnsResponseError, List<&2, Option>>:
  match fuel state:
    case _ Fail{error}: Fail{error}
    case _ Done{Complete{values}}: Done{values}
    case Zero{} _: Fail{TruncatedOption{}}
    case Succ{rest} Done{Options{position, +remaining, reversed}}: optionLoop(rest, packet, optionHeader(U32.is_le(4, remaining), packet, position, remaining, reversed))

def metadata(payloadSize: U32, +ttl: U32, result: Result<&2, &2, EdnsResponseError, List<&2, Option>>) -> Result<&2, &2, EdnsResponseError, Response>:
  match result:
    case Fail{error}: Fail{error}
    case Done{values}: Done{Response{payloadSize, (ttl / 16777216 : U32), (ttl / 65536 % 256 : U32), (ttl % 65536 : U32), values}}

def boundedEdnsResponse(valid: Bool, packet: Packet, payloadSize: U32, ttl: U32, offset: U32, +length: U32) -> Result<&2, &2, EdnsResponseError, Response>:
  match valid:
    case False{}: Fail{EdnsResponseInvalidField{}}
    case True{}: metadata(payloadSize, ttl, optionLoop(U32.to_nat((length / 4 : U32)), packet, Done{progress(U32.is_eq(length, 0), offset, length, Nil{})}))

# Packet must come from packet/parse. Check the public record's
# span before computing its end, so even U32-sized invalid spans cannot wrap.
def decode(+packet: Packet, value: Record) -> Result<&2, &2, EdnsResponseError, Response>:
  match value:
    case Record{Name{Nil{}}, +recordType, +class, ttl, +offset, +length}:
      boundedEdnsResponse(U32.is_eq(recordType, 41) && U32.is_le(class, 65535) && U32.is_le(length, 65535) && available(packet, offset, length), packet, class, ttl, offset, length)
    case _: Fail{InvalidOwner{}}

def hasOpt(values: List<&2, Record>) -> Bool:
  match values:
    case Nil{}: False{}
    case Record{_, code, _, _, _, _} <> rest: U32.is_eq(code, 41) || hasOpt(rest)

def optional(result: Result<&2, &2, EdnsResponseError, Response>) -> Result<&2, &2, EdnsResponseError, Maybe<&2, Response>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{response}: Done{Some{response}}

def selected(isOpt: Bool, packet: Packet, value: Record, prior: Result<&2, &2, EdnsResponseError, Maybe<&2, Response>>) -> Result<&2, &2, EdnsResponseError, Maybe<&2, Response>>:
  match isOpt prior:
    case _ Fail{error}: Fail{error}
    case False{} prior: prior
    case True{} Done{Some{_}}: Fail{Duplicate{}}
    case True{} Done{None{}}: optional(decode(packet, value))

def ednsRecordKind(value: Record) -> U32:
  match value:
    case Record{_, code, _, _, _, _}: code

def scan(+packet: Packet, values: List<&2, Record>, state: Result<&2, &2, EdnsResponseError, Maybe<&2, Response>>) -> Result<&2, &2, EdnsResponseError, Maybe<&2, Response>>:
  match values state:
    case _ Fail{error}: Fail{error}
    case Nil{} state: state
    case +value <> rest state: scan(packet, rest, selected(U32.is_eq(ednsRecordKind(value), 41), packet, value, state))

def placement(invalid: Bool, packet: Packet, values: List<&2, Record>) -> Result<&2, &2, EdnsResponseError, Maybe<&2, Response>>:
  match invalid:
    case True{}: Fail{Misplaced{}}
    case False{}: scan(packet, values, Done{None{}})

# OPT may appear anywhere in additional, but nowhere else and at most once.
def inspect(message: Message) -> Result<&2, &2, EdnsResponseError, Maybe<&2, Response>>:
  match message:
    case Message{packet, _, _, answers, authorities, additional}: placement(hasOpt(answers) || hasOpt(authorities), packet, additional)

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
# policy is not guessed from binary labels (which can themselves contain dots).
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
  SearchCursor{base: Name, dots: U32, noTld: Bool, first: Bool, domains: List<&2, Domain>, index: Nat, triedDirect: Bool, triedRoot: Bool, searched: Bool}

type Step is Data:
  Exhausted{}
  Candidate{origin: Origin, name: Result<&2, &2, DomainNameError, Name>, next: SearchCursor}

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

def preparedDomains(absolute: Bool, base: Name, +dotCount: U32, domains: List<&2, Domain>, policy: Policy) -> SearchCursor:
  match absolute policy:
    case True{} _: SearchCursor{base, dotCount, False{}, True{}, Nil{}, Zero{}, False{}, False{}, False{}}
    case False{} Policy{ndots, defaultNames, +searchNames, noTld}:
      SearchCursor{base, dotCount, noTld, U32.is_ge(dotCount, ndots), domainList(Bool.pick(Bool, U32.is_zero(dotCount), defaultNames, searchNames), searchNames, domains), Zero{}, False{}, False{}, False{}}

# Names are validated individually when requested, including the composed wire
# length. No candidate is silently removed merely because it cannot be encoded.
def startDomains(base: Name, dotCount: U32, absolute: Bool, domains: List<&2, Domain>, policy: Policy) -> SearchCursor:
  preparedDomains(absolute, base, dotCount, domains, policy)

def wrapDomains(names: List<&2, Name>, reversed: List<&2, Domain>) -> List<&2, Domain>:
  match names:
    case Nil{}: List.reverse(&2, Domain, reversed)
    case name <> rest: wrapDomains(rest, Valid{name} <> reversed)

# Existing callers supplying wire names retain the same entry point.
def prepared(absolute: Bool, base: Name, dotCount: U32, domains: List<&2, Name>, policy: Policy) -> SearchCursor:
  preparedDomains(absolute, base, dotCount, wrapDomains(domains, Nil{}), policy)

def start(base: Name, dotCount: U32, absolute: Bool, domains: List<&2, Name>, policy: Policy) -> SearchCursor:
  prepared(absolute, base, dotCount, domains, policy)

def domainRoot(domain: Domain) -> Bool:
  match domain:
    case Valid{name}: root(name)
    case Invalid{_}: False{}

def domainCandidate(base: Name, domain: Domain) -> Result<&2, &2, DomainNameError, Name>:
  match domain:
    case Valid{name}: valid(joined(base, name))
    case Invalid{error}: Fail{error}

def finalCandidate(allowed: Bool, +base: Name, dotCount: U32, noTld: Bool, index: Nat, triedRoot: Bool, searched: Bool) -> Step:
  match allowed:
    case False{}: Exhausted{}
    case True{}: Candidate{Final{}, valid(base), SearchCursor{base, dotCount, noTld, False{}, Nil{}, index, True{}, triedRoot, searched}}

def next(cursor: SearchCursor) -> Step:
  match cursor:
    case SearchCursor{+base, dotCount, noTld, True{}, domains, index, _, triedRoot, searched}:
      Candidate{Initial{}, valid(base), SearchCursor{base, dotCount, noTld, False{}, domains, index, True{}, triedRoot, searched}}
    case SearchCursor{+base, dotCount, noTld, False{}, +domain <> rest, +index, triedDirect, triedRoot, _}:
      Candidate{Suffix{index}, domainCandidate(base, domain), SearchCursor{base, dotCount, noTld, False{}, rest, Succ{index}, triedDirect, triedRoot || domainRoot(domain), True{}}}
    case SearchCursor{base, +dotCount, +noTld, False{}, Nil{}, index, triedDirect, +triedRoot, +searched}:
      finalCandidate(Bool.not(triedDirect || triedRoot) && (Bool.not(U32.is_zero(dotCount)) || Bool.not(searched) || Bool.not(noTld)), base, dotCount, noTld, index, triedRoot, searched)

# A response policy can stop suffix searching but still attempt the final bare
# name where allowed. Only actually yielded root suffixes suppress that attempt.
def stopSearch(cursor: SearchCursor) -> SearchCursor:
  match cursor:
    case SearchCursor{base, dotCount, noTld, first, _, index, triedDirect, triedRoot, searched}: SearchCursor{base, dotCount, noTld, first, Nil{}, index, triedDirect, triedRoot, searched}

# Resolver error classes, independent of OS errno and libc integer constants.
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
  Stop{error: SearchResponseError}

def new() -> History: History{None{}, False{}, False{}, NotFound{}}

def searchResponseError(cause: Cause) -> SearchResponseError:
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

def searchSuffixDecision(cause: Cause, cursor: SearchCursor, history: History) -> SearchResponseDecision:
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
      +value = searchResponseError(cause)
      Continue{cursor, History{Some{value}, noData, serverFailure, value}}
    case Final{} History{initial, noData, serverFailure, _}: Continue{cursor, History{initial, noData, serverFailure, searchResponseError(cause)}}
    case Suffix{_} previous: searchSuffixDecision(cause, cursor, previous)

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

def searchCandidate(~Environment: Data, ~Failure: Data, ~Value: Data, ~request: Environment -> SearchRunRequest -> IO(Outcome<Failure, Value>), environment: Environment, +origin: Origin, cursor: SearchCursor, history: History, name: Result<&2, &2, DomainNameError, Name>) -> IO(Progress<Failure, Value>):
  match name:
    case Fail{_}: IO.pure(Progress<Failure, Value>, decided(Failure, Value, failed(origin, Unrecoverable{}, cursor, history)))
    case Done{value}:
      do IO<Progress<Failure, Value>>:
        outcome : Outcome<Failure, Value> <- request(environment, SearchRunRequest{origin, value})
        return received(Failure, Value, origin, cursor, history, outcome)

def advance(~Environment: Data, ~Failure: Data, ~Value: Data, ~request: Environment -> SearchRunRequest -> IO(Outcome<Failure, Value>), environment: Environment, history: History, step: Step) -> IO(Progress<Failure, Value>):
  match step:
    case Exhausted{}: IO.pure(Progress<Failure, Value>, SearchRunFinished{Fail{NoAnswer{exhausted(history)}}})
    case Candidate{origin, name, following}: searchCandidate(~Environment, ~Failure, ~Value, ~request, environment, origin, following, history, name)

# Each advance consumes a suffix or a direct-name phase; response policy can
# only discard additional suffixes. That finite progress crosses record fields
# and IO binds, hence the local annotation instead of an arbitrary retry limit.
@unsafe def drive(~Environment: Data, ~Failure: Data, ~Value: Data, ~request: Environment -> SearchRunRequest -> IO(Outcome<Failure, Value>), +environment: Environment, progress: Progress<Failure, Value>) -> IO(Result<&2, &2, SearchRunError<Failure>, Value>):
  match progress:
    case SearchRunFinished{result}: IO.pure(Result<&2, &2, SearchRunError<Failure>, Value>, result)
    case Active{cursor, history}:
      do IO<Result<&2, &2, SearchRunError<Failure>, Value>>:
        following : Progress<Failure, Value> <- advance(~Environment, ~Failure, ~Value, ~request, environment, history, next(cursor))
        drive(~Environment, ~Failure, ~Value, ~request, environment, following)

# The request function owns each exchange until it returns. The environment is
# borrowed and remains caller-owned. SearchHalt preserves non-DNS errors immediately;
# no earlier search failure can override cancellation/entropy/cleanup failures.
def runSearch(~Environment: Data, ~Failure: Data, ~Value: Data, ~request: Environment -> SearchRunRequest -> IO(Outcome<Failure, Value>), environment: Environment, cursor: SearchCursor) -> IO(Result<&2, &2, SearchRunError<Failure>, Value>):
  drive(~Environment, ~Failure, ~Value, ~request, environment, Active{cursor, new()})

# The search threshold counts presentation dots, including the terminal dot.
# Parsing first bounds the accepted input before conversion to the U32 API.
type Input is Data:
  Input{name: Name, dots: U32, absolute: Bool}

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
  runSearch(~Environment, ~Failure, ~Value, ~candidate(~Environment, ~Left, ~Right, ~Failure, ~Value, ~left, ~right, ~merge), environment, cursor)

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
