import Base
import ./aes128.bend as AES
import ./aes128-gcm.bend as GCM
import ./u64.bend as Word

# TLS 1.3 protected records, RFC 8446 section 5. One affine Traffic belongs
# to one direction and key epoch. Success returns its successor; failure
# consumes it, so callers cannot retry a failed record under the same nonce.
type ContentType is Data:
  Application{}
  Handshake{}
  Alert{}

type Content is Data:
  Content{kind: ContentType, bytes: List<&2, U32>}

type Error is Data:
  InvalidByte{}
  RecordOverflow{}
  UnexpectedMessage{}
  BadRecordMac{}
  Truncated{}
  SequenceExhausted{}

type Traffic is Type:
  Traffic{key: GCM.GcmKey, iv: GCM.Nonce, sequence: Maybe<&2, Word.U64>}

type Sent is Type:
  Sent{traffic: Traffic, record: List<&2, U32>}

type Received is Type:
  Received{traffic: Traffic, content: Content, rest: List<&2, U32>}

def create(key: AES.Block, iv: GCM.Nonce) -> Traffic:
  Traffic{GCM.key(key), iv, Some{Word.zero()}}

def nonce(iv: GCM.Nonce, sequence: Word.U64) -> GCM.Nonce:
  match iv sequence:
    case GCM.Nonce{a, b, c} Word.U64{high, low}: GCM.Nonce{a, U32.xor(b, high), U32.xor(c, low)}

def next(+sequence: Word.U64) -> Maybe<&2, Word.U64>:
  Bool.pick(Maybe<&2, Word.U64>, Word.equal(sequence, Word.U64{4294967295, 4294967295}), None{}, Some{Word.add(sequence, Word.one())})

def code(kind: ContentType) -> U32:
  match kind:
    case Application{}: 23
    case Handshake{}: 22
    case Alert{}: 21

def contentValid(kind: ContentType, bytes: List<&2, U32>) -> Bool:
  match kind bytes:
    case Application{} _: True{}
    case Handshake{} Nil{}: False{}
    case Handshake{} _: True{}
    case Alert{} _ <> _ <> Nil{}: True{}
    case Alert{} _: False{}

def zeros(count: Nat, bytes: List<&2, U32>) -> List<&2, U32>:
  match count:
    case 0n: bytes
    case 1n+rest: zeros(rest, 0 <> bytes)

def length(bytes: List<&2, U32>, count: Nat) -> Nat:
  match bytes:
    case Nil{}: count
    case _ <> rest: length(rest, 1n+count)

def header(+length: U32) -> List<&2, U32>:
  23 <> 3 <> 3 <> U32.shrn(length, 8n) <> U32.and(length, 255) <> Nil{}

# Avoid recursive append of an entire record on backends without tail-call
# elimination for constructor recursion.
def append(left: List<&2, U32>, right: List<&2, U32>) -> List<&2, U32>:
  List.reverse.go(&2, U32, List.reverse(&2, U32, left), right)

def cryptoError(error: GCM.Error) -> Error:
  match error:
    case GCM.InvalidByte{}: InvalidByte{}
    case GCM.MessageTooLong{}: RecordOverflow{}
    case GCM.AuthenticationFailed{}: BadRecordMac{}

def sealed(traffic: Traffic, head: List<&2, U32>, result: Result<&2, &2, GCM.Error, GCM.Sealed>) -> Result<&2, &1, Error, Sent>:
  match result:
    case Fail{cause}: Fail{cryptoError(cause)}
    case Done{GCM.Sealed{ciphertext, tag}}: Done{Sent{traffic, append(head, append(ciphertext, AES.toBytes(tag)))}}

def sendValid(valid: Bool, bounded: Bool, traffic: Traffic, content: Content, padding: Nat) -> Result<&2, &1, Error, Sent>:
  match valid bounded traffic content:
    case False{} _ _ _: Fail{UnexpectedMessage{}}
    case True{} False{} _ _: Fail{RecordOverflow{}}
    case True{} True{} Traffic{_, _, None{}} _: Fail{SequenceExhausted{}}
    case True{} True{} Traffic{+key, +iv, Some{+sequence}} Content{kind, bytes}:
      +inner = append(bytes, code(kind) <> zeros(padding, Nil{}))
      +head = header((U32.from_nat(length(inner, 0n)) + 16 : U32))
      sealed(Traffic{key, iv, next(sequence)}, head, GCM.seal(key, nonce(iv, sequence), head, inner))

def send(traffic: Traffic, content: Content, +padding: Nat) -> Result<&2, &1, Error, Sent>:
  match content:
    case Content{+kind, +bytes}:
      sendValid(contentValid(kind, bytes), Nat.is_le(length(bytes, 0n), 16384n) && Nat.is_le(padding, Nat.sub(16384n, length(bytes, 0n))), traffic, Content{kind, bytes}, padding)

# Parse one complete record, preserving bytes belonging to subsequent records.
# Socket buffering must supply a complete frame before calling receive.
type Fragment is Data:
  Fragment{bytes: List<&2, U32>, rest: List<&2, U32>}

def take(count: Nat, bytes: List<&2, U32>, reversed: List<&2, U32>) -> Result<&2, &2, Error, Fragment>:
  match count bytes:
    case 0n rest: Done{Fragment{List.reverse(&2, U32, reversed), rest}}
    case 1n+_ Nil{}: Fail{Truncated{}}
    case 1n+remaining head <> rest: take(remaining, rest, head <> reversed)

type Packet is Data:
  Packet{header: List<&2, U32>, encrypted: GCM.Sealed, rest: List<&2, U32>}

def packet(head: List<&2, U32>, ciphertext: List<&2, U32>, rest: List<&2, U32>, tag: Maybe<&2, AES.Block>) -> Result<&2, &2, Error, Packet>:
  match tag:
    case None{}: Fail{InvalidByte{}}
    case Some{tag}: Done{Packet{head, GCM.Sealed{ciphertext, tag}, rest}}

def withTag(head: List<&2, U32>, ciphertext: List<&2, U32>, fragment: Fragment) -> Result<&2, &2, Error, Packet>:
  match fragment:
    case Fragment{bytes, rest}: packet(head, ciphertext, rest, AES.fromBytes(bytes))

def withCiphertext(head: List<&2, U32>, fragment: Fragment) -> Result<&2, &2, Error, Packet>:
  match fragment:
    case Fragment{ciphertext, rest}: Result.bind(&2, &2, Error, Fragment, Packet, take(16n, rest, Nil{}), part => withTag(head, ciphertext, part))

def parseHeader(valid: Bool, kind: U32, +length: U32, head: List<&2, U32>, rest: List<&2, U32>) -> Result<&2, &2, Error, Packet>:
  match valid kind:
    case False{} _: Fail{InvalidByte{}}
    case True{} 23:
      bounded = Bool.pick(Result<&2, &2, Error, Unit>, U32.is_le(length, 16640),
        Bool.pick(Result<&2, &2, Error, Unit>, U32.is_ge(length, 16), Done{Unit{}}, Fail{BadRecordMac{}}), Fail{RecordOverflow{}})
      Result.bind(&2, &2, Error, Unit, Packet, bounded, unused =>
        Result.bind(&2, &2, Error, Fragment, Packet, take(U32.to_nat((length - 16 : U32)), rest, Nil{}), part => withCiphertext(head, part)))
    case True{} _: Fail{UnexpectedMessage{}}

def parse(wire: List<&2, U32>) -> Result<&2, &2, Error, Packet>:
  match wire:
    case +kind <> major <> minor <> +high <> +low <> rest:
      +head = {kind <> major <> minor <> high <> low <> Nil{} : List<&2, U32>}
      parseHeader(AES.valid(head), kind, (high * 256 + low : U32), head, rest)
    case _: Fail{Truncated{}}

def decoded(valid: Bool, kind: ContentType, bytes: List<&2, U32>) -> Result<&2, &2, Error, Content>:
  match valid:
    case False{}: Fail{UnexpectedMessage{}}
    case True{}: Done{Content{kind, bytes}}

# Scan backward only within authenticated plaintext. The first nonzero byte
# is the content type; zeros preceding that byte remain application content.
def unpad(reversed: List<&2, U32>) -> Result<&2, &2, Error, Content>:
  match reversed:
    case Nil{}: Fail{UnexpectedMessage{}}
    case 0 <> rest: unpad(rest)
    case 23 <> rest: Done{Content{Application{}, List.reverse(&2, U32, rest)}}
    case 22 <> rest:
      +bytes = List.reverse(&2, U32, rest)
      decoded(contentValid(Handshake{}, bytes), Handshake{}, bytes)
    case 21 <> rest:
      +bytes = List.reverse(&2, U32, rest)
      decoded(contentValid(Alert{}, bytes), Alert{}, bytes)
    case _: Fail{UnexpectedMessage{}}

def inner(bounded: Bool, bytes: List<&2, U32>) -> Result<&2, &2, Error, Content>:
  match bounded:
    case False{}: Fail{RecordOverflow{}}
    case True{}: unpad(List.reverse(&2, U32, bytes))

def received(traffic: Traffic, rest: List<&2, U32>, result: Result<&2, &2, Error, Content>) -> Result<&2, &1, Error, Received>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{content}: Done{Received{traffic, content, rest}}

def opened(traffic: Traffic, rest: List<&2, U32>, result: Result<&2, &2, GCM.Error, List<&2, U32>>) -> Result<&2, &1, Error, Received>:
  match result:
    case Fail{cause}: Fail{cryptoError(cause)}
    case Done{+bytes}: received(traffic, rest, inner(Nat.is_le(length(bytes, 0n), 16385n), bytes))

def receivePacket(traffic: Traffic, result: Result<&2, &2, Error, Packet>) -> Result<&2, &1, Error, Received>:
  match traffic result:
    case _ Fail{cause}: Fail{cause}
    case Traffic{_, _, None{}} _: Fail{SequenceExhausted{}}
    case Traffic{+key, +iv, Some{+sequence}} Done{Packet{head, encrypted, rest}}:
      opened(Traffic{key, iv, next(sequence)}, rest, GCM.open(key, nonce(iv, sequence), head, encrypted))

def receive(traffic: Traffic, wire: List<&2, U32>) -> Result<&2, &1, Error, Received>:
  receivePacket(traffic, parse(wire))
