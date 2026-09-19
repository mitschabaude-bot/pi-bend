import Base

# DNS labels are octet strings, not Unicode text. Names include an implicit
# terminal root; an empty list denotes that root. Preserve spelling and case.
type Name is Data:
  Name{labels: List<&2, List<&2, U32>>}

type Error is Data:
  InvalidByte{}
  InvalidLabel{}
  NameTooLong{}
  PacketTooLong{}
  Truncated{}
  ReservedLabel{}
  InvalidPointer{}

type Packet is Data:
  Packet{size: U32, bytes: Map<&2, U32>}

def key(+index: U32) -> String:
  SCon{Chr{(index / 256 : U32)}, SCon{Chr{(index % 256 : U32)}, SNil{}}}

def inserted(valid: Bool, +index: U32, byte: U32, bytes: Map<&2, U32>) -> Result<&2, &2, Error, Packet>:
  match valid:
    case False{}: Fail{InvalidByte{}}
    case True{}: Done{Packet{(index + 1 : U32), Map.set(&2, U32, bytes, key(index), byte)}}

def insert(result: Result<&2, &2, Error, Packet>, +byte: U32) -> Result<&2, &2, Error, Packet>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Packet{65535, _}}: Fail{PacketTooLong{}}
    case Done{Packet{index, bytes}}: inserted(U32.is_le(byte, 255), index, byte, bytes)

# An immutable offset index avoids scanning the packet for each pointer.
def packetLoop(input: List<&2, U32>, result: Result<&2, &2, Error, Packet>) -> Result<&2, &2, Error, Packet>:
  match input result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case value <> rest packet: packetLoop(rest, insert(packet, value))

def packet(input: List<&2, U32>) -> Result<&2, &2, Error, Packet>:
  packetLoop(input, Done{Packet{0, MTip{}}})

def found(value: Map<&2, U32> & U32) -> U32:
  match value:
    case (_, byte): byte

def boundedByte(valid: Bool, bytes: Map<&2, U32>, index: U32) -> U32:
  match valid:
    case False{}: 256
    case True{}: found(Map.get(U32, 256, bytes, key(index)))

def byte(packet: Packet, +index: U32) -> U32:
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
  Failed{error: Error}

def nextOffset(next: Maybe<&2, U32>, fallback: U32) -> U32:
  match next:
    case None{}: fallback
    case Some{value}: value

def labelHead(valid: Bool, position: U32, ceiling: U32, next: Maybe<&2, U32>, length: U32, labels: List<&2, List<&2, U32>>, count: U32) -> State:
  match valid:
    case False{}: Failed{NameTooLong{}}
    case True{}: Reading{position, ceiling, next, length, labels, Label{count, Nil{}}}

def headFlags(zero: Bool, label: Bool, pointer: Bool, +tag: U32, position: U32, ceiling: U32, next: Maybe<&2, U32>, +length: U32, labels: List<&2, List<&2, U32>>) -> State:
  match zero label pointer:
    case True{} _ _: Finished{Decoded{Name{List.reverse(&2, List<&2, U32>, labels)}, nextOffset(next, position)}}
    case False{} True{} _: labelHead(U32.is_le((length + tag + 1 : U32), 255), position, ceiling, next, (length + tag + 1 : U32), labels, tag)
    case False{} False{} True{}: Reading{position, ceiling, next, length, labels, Pointer{(tag - 192 : U32)}}
    case _ _ _: Failed{ReservedLabel{}}

def head(+tag: U32, position: U32, ceiling: U32, next: Maybe<&2, U32>, length: U32, labels: List<&2, List<&2, U32>>) -> State:
  headFlags(U32.is_eq(tag, 0), U32.is_lt(tag, 64), U32.is_ge(tag, 192), tag, position, ceiling, next, length, labels)

def pointed(valid: Bool, +target: U32, position: U32, next: Maybe<&2, U32>, length: U32, labels: List<&2, List<&2, U32>>) -> State:
  match valid:
    case False{}: Failed{InvalidPointer{}}
    case True{}: Reading{target, target, Some{nextOffset(next, position)}, length, labels, Head{}}

def consume(mode: Mode, +value: U32, +position: U32, +ceiling: U32, next: Maybe<&2, U32>, length: U32, labels: List<&2, List<&2, U32>>) -> State:
  match mode:
    case Head{}: head(value, position, ceiling, next, length, labels)
    case Label{1, reversed}: Reading{position, ceiling, next, length, List.reverse(&2, U32, value <> reversed) <> labels, Head{}}
    case Label{left, reversed}: Reading{position, ceiling, next, length, labels, Label{(left - 1 : U32), value <> reversed}}
    case Pointer{+high}: pointed(U32.is_lt((high * 256 + value : U32), ceiling), (high * 256 + value : U32), position, next, length, labels)

def present(valid: Bool, mode: Mode, value: U32, position: U32, ceiling: U32, next: Maybe<&2, U32>, length: U32, labels: List<&2, List<&2, U32>>) -> State:
  match valid:
    case False{}: Failed{Truncated{}}
    case True{}: consume(mode, value, position, ceiling, next, length, labels)

def step(packet: Packet, state: State) -> State:
  match state:
    case Reading{+position, ceiling, next, length, labels, mode}:
      +value = byte(packet, position)
      present(U32.is_le(value, 255), mode, value, (position + 1 : U32), ceiling, next, length, labels)
    case final: final

# Every pointer must refer to an earlier name segment. The ceiling strictly
# decreases on a jump, rejecting self/forward/cyclic references. Labels count
# toward the expanded 255-octet limit, including their lengths and root.
def loop(fuel: Nat, +packet: Packet, state: State) -> Result<&2, &2, Error, Decoded>:
  match fuel state:
    case _ Finished{value}: Done{value}
    case _ Failed{error}: Fail{error}
    case Zero{} _: Fail{InvalidPointer{}}
    case Succ{rest} reading: loop(rest, packet, step(packet, reading))

def decode(packet: Packet, +position: U32) -> Result<&2, &2, Error, Decoded>:
  loop(65536n, packet, Reading{position, position, None{}, 1, Nil{}, Head{}})

type EncodedLabel is Data:
  EncodedLabel{length: U32, reversed: List<&2, U32>}

def labelByte(valid: Bool, value: U32, length: U32, reversed: List<&2, U32>) -> Result<&2, &2, Error, EncodedLabel>:
  match valid:
    case False{}: Fail{InvalidByte{}}
    case True{}: Done{EncodedLabel{(length + 1 : U32), value <> reversed}}

def labelStep(result: Result<&2, &2, Error, EncodedLabel>, +value: U32) -> Result<&2, &2, Error, EncodedLabel>:
  match result:
    case Fail{error}: Fail{error}
    case Done{EncodedLabel{63, _}}: Fail{InvalidLabel{}}
    case Done{EncodedLabel{length, reversed}}: labelByte(U32.is_le(value, 255), value, length, reversed)

def labelLoop(input: List<&2, U32>, result: Result<&2, &2, Error, EncodedLabel>) -> Result<&2, &2, Error, EncodedLabel>:
  match input result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{EncodedLabel{0, _}}: Fail{InvalidLabel{}}
    case Nil{} value: value
    case value <> rest state: labelLoop(rest, labelStep(state, value))

def appended(valid: Bool, length: U32, reversed: List<&2, U32>) -> Result<&2, &2, Error, EncodedLabel>:
  match valid:
    case False{}: Fail{NameTooLong{}}
    case True{}: Done{EncodedLabel{length, reversed}}

def encodedLabel(state: Result<&2, &2, Error, EncodedLabel>, value: Result<&2, &2, Error, EncodedLabel>) -> Result<&2, &2, Error, EncodedLabel>:
  match state value:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{EncodedLabel{+length, reversed}} Done{EncodedLabel{+size, bytes}}: appended(U32.is_le((length + size + 1 : U32), 255), (length + size + 1 : U32), List.append(&2, U32, bytes, size <> reversed))

def encodeLoop(labels: List<&2, List<&2, U32>>, state: Result<&2, &2, Error, EncodedLabel>) -> Result<&2, &2, Error, List<&2, U32>>:
  match labels state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{EncodedLabel{_, reversed}}: Done{List.reverse(&2, U32, 0 <> reversed)}
    case label <> rest value: encodeLoop(rest, encodedLabel(value, labelLoop(label, Done{EncodedLabel{0, Nil{}}})))

def encode(name: Name) -> Result<&2, &2, Error, List<&2, U32>>:
  match name:
    case Name{labels}: encodeLoop(labels, Done{EncodedLabel{1, Nil{}}})
