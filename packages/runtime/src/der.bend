import Base

# DER framing for certificate parsing. Tag numbers and content lengths are
# bounded by U32; larger encodings report LimitExceeded, not integer wrap.
# Contents are interpreted by typed accessors and the enclosing ASN.1 schema.
type Error is Data:
  Truncated{}
  InvalidByte{}
  NonCanonical{}
  LimitExceeded{}
  UnexpectedTag{}
  InvalidValue{}
  TrailingData{}

type Tag is Data:
  Tag{class: U32, constructed: Bool, number: U32}

type Node is Data:
  Node{tag: Tag, header: List<&2, U32>, content: List<&2, U32>}

type Read is Data:
  Read{node: Node, rest: List<&2, U32>}

type Identifier is Data:
  Identifier{tag: Tag, reverse: List<&2, U32>, rest: List<&2, U32>}

def choose(-A: Data, condition: Bool, yes: Unit -> Result<&2, &2, Error, A>, no: Unit -> Result<&2, &2, Error, A>) -> Result<&2, &2, Error, A>:
  match condition:
    case True{}: yes(Unit{})
    case False{}: no(Unit{})

def append(left: List<&2, U32>, right: List<&2, U32>) -> List<&2, U32>:
  List.reverse.go(&2, U32, List.reverse(&2, U32, left), right)

def encoded(node: Node) -> List<&2, U32>:
  match node:
    case Node{_, header, content}: append(header, content)

def identifier(allowed: Bool, tag: Tag, reverse: List<&2, U32>, rest: List<&2, U32>) -> Result<&2, &2, Error, Identifier>:
  match allowed:
    case False{}: Fail{NonCanonical{}}
    case True{}: Done{Identifier{tag, reverse, rest}}

def highTag(bytes: List<&2, U32>, +class: U32, +constructed: Bool, +value: U32, +reverse: List<&2, U32>) -> Result<&2, &2, Error, Identifier>:
  match bytes:
    case Nil{}: Fail{Truncated{}}
    case +byte <> +rest:
      choose(Identifier, U32.is_gt(byte, 255), unit => Fail{InvalidByte{}}, unit =>
        choose(Identifier, U32.is_gt(value, 33554431), unit => Fail{LimitExceeded{}}, unit =>
          choose(Identifier, U32.is_eq(value, 0) && U32.is_eq(byte, 128), unit => Fail{NonCanonical{}}, unit =>
            choose(Identifier, U32.is_lt(byte, 128), unit =>
              +number = (value * 128 + byte : U32)
              identifier(U32.is_ge(number, 31), Tag{class, constructed, number}, byte <> reverse, rest), unit =>
              highTag(rest, class, constructed, (value * 128 + U32.and(byte, 127) : U32), byte <> reverse)))))

def readTag(bytes: List<&2, U32>) -> Result<&2, &2, Error, Identifier>:
  match bytes:
    case Nil{}: Fail{Truncated{}}
    case +byte <> +rest:
      +class = U32.shrn(byte, 6n)
      +constructed = U32.is_eq(U32.and(byte, 32), 32)
      +number = U32.and(byte, 31)
      choose(Identifier, U32.is_gt(byte, 255), unit => Fail{InvalidByte{}}, unit =>
        choose(Identifier, U32.is_eq(number, 31), unit =>
          highTag(rest, class, constructed, 0, byte <> Nil{}), unit =>
          identifier(Bool.not(U32.is_eq(class, 0) && U32.is_eq(number, 0)), Tag{class, constructed, number}, byte <> Nil{}, rest)))

def content(count: Nat, bytes: List<&2, U32>, tag: Tag, header: List<&2, U32>, reverse: List<&2, U32>) -> Result<&2, &2, Error, Read>:
  match count bytes:
    case 0n rest: Done{Read{Node{tag, List.reverse(&2, U32, header), List.reverse(&2, U32, reverse)}, rest}}
    case 1n+_ Nil{}: Fail{Truncated{}}
    case 1n+count +byte <> rest:
      choose(Read, U32.is_gt(byte, 255), unit => Fail{InvalidByte{}}, unit =>
        content(count, rest, tag, header, byte <> reverse))

def longLength(count: Nat, bytes: List<&2, U32>, first: Bool, +size: U32, tag: Tag, reverse: List<&2, U32>) -> Result<&2, &2, Error, Read>:
  match count bytes:
    case 0n rest:
      choose(Read, U32.is_lt(size, 128), unit => Fail{NonCanonical{}}, unit =>
        content(U32.to_nat(size), rest, tag, reverse, Nil{}))
    case 1n+_ Nil{}: Fail{Truncated{}}
    case 1n+count +byte <> rest:
      choose(Read, U32.is_gt(byte, 255), unit => Fail{InvalidByte{}}, unit =>
        choose(Read, first && U32.is_eq(byte, 0), unit => Fail{NonCanonical{}}, unit =>
          longLength(count, rest, False{}, (size * 256 + byte : U32), tag, byte <> reverse)))

def readLength(value: Identifier) -> Result<&2, &2, Error, Read>:
  match value:
    case Identifier{_, _, Nil{}}: Fail{Truncated{}}
    case Identifier{+tag, +reverse, +byte <> +rest}:
      choose(Read, U32.is_gt(byte, 255), unit => Fail{InvalidByte{}}, unit =>
        choose(Read, U32.is_lt(byte, 128), unit =>
          content(U32.to_nat(byte), rest, tag, byte <> reverse, Nil{}), unit =>
          choose(Read, U32.is_eq(byte, 128) || U32.is_eq(byte, 255), unit => Fail{NonCanonical{}}, unit =>
            choose(Read, U32.is_gt(byte, 132), unit => Fail{LimitExceeded{}}, unit =>
              longLength(U32.to_nat((byte - 128 : U32)), rest, True{}, 0, tag, byte <> reverse)))))

def read(bytes: List<&2, U32>) -> Result<&2, &2, Error, Read>:
  Result.bind(&2, &2, Error, Identifier, Read, readTag(bytes), readLength)

def only(value: Read) -> Result<&2, &2, Error, Node>:
  match value:
    case Read{node, Nil{}}: Done{node}
    case _: Fail{TrailingData{}}

def one(bytes: List<&2, U32>) -> Result<&2, &2, Error, Node>:
  Result.bind(&2, &2, Error, Read, Node, read(bytes), only)

# ASN.1 INTEGER is signed. Strip a required positive sign octet, but reject
# negative values, empty integers and redundant leading zeroes.
def unsignedZero(bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match bytes:
    case Nil{}: Done{0 <> Nil{}}
    case +next <> rest:
      Bool.pick(Result<&2, &2, Error, List<&2, U32>>, U32.is_ge(next, 128), Done{next <> rest}, Fail{NonCanonical{}})

def unsignedBytes(bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match bytes:
    case +first <> +rest:
      choose(List<&2, U32>, U32.is_eq(first, 0), unit => unsignedZero(rest), unit =>
        Bool.pick(Result<&2, &2, Error, List<&2, U32>>, U32.is_lt(first, 128), Done{first <> rest}, Fail{InvalidValue{}}))
    case Nil{}: Fail{InvalidValue{}}

def unsigned(node: Node) -> Result<&2, &2, Error, List<&2, U32>>:
  match node:
    case Node{Tag{0, False{}, 2}, _, bytes}: unsignedBytes(bytes)
    case _: Fail{UnexpectedTag{}}

type Bits is Data:
  Bits{unused: U32, bytes: List<&2, U32>}

def padding(bytes: List<&2, U32>, +unused: U32) -> Bool:
  match bytes:
    case Nil{}: U32.is_eq(unused, 0)
    case byte <> Nil{}: U32.is_eq(U32.and(byte, (U32.shln(1, U32.to_nat(unused)) - 1 : U32)), 0)
    case _ <> rest: padding(rest, unused)

def bits(node: Node) -> Result<&2, &2, Error, Bits>:
  match node:
    case Node{Tag{0, False{}, 3}, _, +unused <> +bytes}:
      choose(Bits, U32.is_gt(unused, 7), unit => Fail{InvalidValue{}}, unit =>
        choose(Bits, padding(bytes, unused), unit =>
          Done{Bits{unused, bytes}}, unit =>
          Fail{NonCanonical{}}))
    case Node{Tag{0, False{}, 3}, _, Nil{}}: Fail{InvalidValue{}}
    case _: Fail{UnexpectedTag{}}

def length(bytes: List<&2, U32>, count: Nat) -> Nat:
  match bytes:
    case Nil{}: count
    case _ <> rest: length(rest, 1n+count)

def siblings(fuel: Nat, result: Result<&2, &2, Error, Read>, reversed: List<&2, Node>) -> Result<&2, &2, Error, List<&2, Node>>:
  match fuel result:
    case _ Fail{cause}: Fail{cause}
    case _ Done{Read{node, Nil{}}}: Done{List.reverse(&2, Node, node <> reversed)}
    case 1n+fuel Done{Read{node, rest}}: siblings(fuel, read(rest), node <> reversed)
    case _ _: Fail{Truncated{}}

def all(bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, Node>>:
  match bytes:
    case Nil{}: Done{Nil{}}
    case +head <> +rest: siblings(length(rest, 1n), read(head <> rest), Nil{})

def sequence(node: Node) -> Result<&2, &2, Error, List<&2, Node>>:
  match node:
    case Node{Tag{0, True{}, 16}, _, bytes}: all(bytes)
    case _: Fail{UnexpectedTag{}}
