import Base
import ./image.bend as Image

# VP8 keyframes, the lossy payload of WebP. RIFF and alpha belong to webp.bend.
# Probability tables and reconstruction follow image-rs 0.24.8 / RFC 6386.
type Error is Data:
  InvalidByte{}
  Truncated{}
  Signature{}
  Interframe{}
  Dimensions{}
  PixelLimit{}
  ColorSpace{}
  Partition{}
  UnsupportedVersion{}
  HiddenFrame{}

type Row is Data: Row{a: U32,b: U32,c: U32,d: U32}
def zeroRow() -> Row: Row{0,0,0,0}

type Reader is Data:
  Reader{bytes: List<&2,U32>, range: U32, value: U32, count: U32, padding: U32}

def Read(-A: Data) -> Type: Reader -> Reader & A

def Read.pure(-A: Data, value: A) -> Read(A): reader => (reader,value)

def readBound(-A: Data, -B: Data, next: A -> Read(B), pair: Reader & A) -> Reader & B:
  match pair:
    case (reader,value): next(value)(reader)

def Read.bind(-A: Data, -B: Data, step: Read(A), next: A -> Read(B)) -> Read(B):
  reader => readBound(A,B,next,step(reader))

# RFC 6386 explicitly permits zero padding after the arithmetic partition.
# One lookahead byte may be zero-filled; reading beyond it is truncated.
# An unused coefficient partition may legally contain a single byte.
def refill(bytes: List<&2,U32>, range: U32, value: U32,padding: U32) -> Reader:
  match bytes:
    case Nil{}: Reader{Nil{},range,value,0,U32.min(2,(padding + 1 : U32))}
    case byte <> rest: Reader{rest,range,U32.or(value,byte),0,padding}

def normalize(fuel: Nat, reader: Reader) -> Reader:
  match fuel reader:
    case 0n state: state
    case 1n+n Reader{+bytes,+range,+value,+count,+padding}:
      Bool.pick(Reader -> Reader,U32.is_lt(range,128),
        state => normalize(n,state),state => state)(
          Bool.pick(Unit -> Reader,U32.is_lt(range,128),
            _ => Bool.pick(Unit -> Reader,U32.is_eq(count,7),
              _ => refill(bytes,U32.shln(range,1n),U32.shln(value,1n),padding),
              _ => Reader{bytes,U32.shln(range,1n),U32.shln(value,1n),(count + 1 : U32),padding})(Unit{}),
            _ => Reader{bytes,range,value,count,padding})(Unit{}))

def readBit(probability: U32, reader: Reader) -> Reader & U32:
  match reader:
    case Reader{bytes,+range,+value,count,padding}:
      +split = (1 + U32.shrn(((range - 1) * probability : U32),8n) : U32)
      +one = U32.is_ge(value,U32.shln(split,8n))
      (normalize(8n,Reader{bytes,Bool.pick(U32,one,(range - split : U32),split),Bool.pick(U32,one,(value - U32.shln(split,8n) : U32),value),count,padding}),Bool.pick(U32,one,1,0))

def readerValid(reader: Reader) -> Bool:
  match reader:
    case Reader{_,_,_,_,padding}: U32.is_le(padding,1)

def bit(probability: U32) -> Read(U32): reader => readBit(probability,reader)

def literalBits(fuel: Nat, value: U32) -> Read(U32):
  match fuel:
    case 0n: Read.pure(U32,value)
    case 1n+n:
      do Read<U32>:
        next : U32 <- bit(128)
        literalBits(n,(value * 2 + next : U32))

def literal(bits: Nat) -> Read(U32): literalBits(bits,0)

def signed(bits: Nat) -> Read(U32):
  do Read<U32>:
    +value : U32 <- literal(bits)
    sign : U32 <- bit(128)
    Read.pure(U32,Bool.pick(U32,U32.is_eq(sign,0),value,(0 - value : U32)))

def optionalSigned(bits: Nat) -> Read(U32):
  do Read<U32>:
    present : U32 <- bit(128)
    Bool.pick(Unit -> Read(U32),U32.is_eq(present,0),_ => Read.pure(U32,0),_ => signed(bits))(Unit{})

# Immutable balanced probability tables are shared across coefficient reads.
# Construction happens once per frame; lookup follows at most eleven branches.
type Table is Data:
  Leaf{value: U32}
  Branch{left: Table,right: Table}

def tableAt(tree: Table, +index: U32) -> U32:
  match tree:
    case Leaf{value}: value
    case Branch{left,right}: Bool.pick(Unit -> U32,U32.is_eq(U32.and(index,1),0),_ => tableAt(left,U32.shrn(index,1n)),_ => tableAt(right,U32.shrn(index,1n)))(Unit{})

def tableSet(tree: Table, +index: U32, +value: U32) -> Table:
  match tree:
    case Leaf{_}: Leaf{value}
    case Branch{+left,+right}:
      Bool.pick(Unit -> Table,U32.is_eq(U32.and(index,1),0),
        _ => Branch{tableSet(left,U32.shrn(index,1n),value),right},
        _ => Branch{left,tableSet(right,U32.shrn(index,1n),value)})(Unit{})

def emptyTable(depth: Nat, value: U32) -> Table:
  match depth:
    case 0n: Leaf{value}
    case 1n+n:
      +child = emptyTable(n,value)
      Branch{child,child}

def fillTable(values: List<&2,U32>, +index: U32, tree: Table) -> Table:
  match values:
    case Nil{}: tree
    case value <> rest: fillTable(rest,(index + 1 : U32),tableSet(tree,index,value))

def table(depth: Nat, values: List<&2,U32>) -> Table: fillTable(values,0,emptyTable(depth,0))

def small(values: List<&2,U32>, index: U32) -> U32:
  match values index:
    case value <> _ 0: value
    case _ <> rest +i: small(rest,(i - 1 : U32))
    case Nil{} _: 0

def branch(fuel: Nat, +tree: List<&2,U32>, +probs: Table, +base: U32, +index: U32) -> Read(U32):
  match fuel:
    case 0n: Read.pure(U32,0)
    case 1n+n:
      do Read<U32>:
        next : U32 <- bit(tableAt(probs,(base + index / 2 : U32)))
        +node : U32 <- Read.pure(U32,small(tree,(index + next : U32)))
        Bool.pick(Unit -> Read(U32),U32.is_ge(node,2147483648) || U32.is_eq(node,0),
          _ => Read.pure(U32,(0 - node : U32)),
          _ => branch(n,tree,probs,base,node))(Unit{})

def intraProbabilities() -> List<&2,U32>:
  231 <> 120 <> 48 <> 89 <> 115 <> 113 <> 120 <> 152 <> 112 <> 152 <> 179 <> 64 <> 126 <> 170 <> 118 <> 46 <> 70 <> 95 <> 175 <> 69 <> 143 <> 80 <> 85 <> 82 <>
  72 <> 155 <> 103 <> 56 <> 58 <> 10 <> 171 <> 218 <> 189 <> 17 <> 13 <> 152 <> 144 <> 71 <> 10 <> 38 <> 171 <> 213 <> 144 <> 34 <> 26 <> 114 <> 26 <> 17 <>
  163 <> 44 <> 195 <> 21 <> 10 <> 173 <> 121 <> 24 <> 80 <> 195 <> 26 <> 62 <> 44 <> 64 <> 85 <> 170 <> 46 <> 55 <> 19 <> 136 <> 160 <> 33 <> 206 <> 71 <>
  63 <> 20 <> 8 <> 114 <> 114 <> 208 <> 12 <> 9 <> 226 <> 81 <> 40 <> 11 <> 96 <> 182 <> 84 <> 29 <> 16 <> 36 <> 134 <> 183 <> 89 <> 137 <> 98 <> 101 <>
  106 <> 165 <> 148 <> 72 <> 187 <> 100 <> 130 <> 157 <> 111 <> 32 <> 75 <> 80 <> 66 <> 102 <> 167 <> 99 <> 74 <> 62 <> 40 <> 234 <> 128 <> 41 <> 53 <> 9 <>
  178 <> 241 <> 141 <> 26 <> 8 <> 107 <> 104 <> 79 <> 12 <> 27 <> 217 <> 255 <> 87 <> 17 <> 7 <> 74 <> 43 <> 26 <> 146 <> 73 <> 166 <> 49 <> 23 <> 157 <>
  65 <> 38 <> 105 <> 160 <> 51 <> 52 <> 31 <> 115 <> 128 <> 87 <> 68 <> 71 <> 44 <> 114 <> 51 <> 15 <> 186 <> 23 <> 47 <> 41 <> 14 <> 110 <> 182 <> 183 <>
  21 <> 17 <> 194 <> 66 <> 45 <> 25 <> 102 <> 197 <> 189 <> 23 <> 18 <> 22 <> 88 <> 88 <> 147 <> 150 <> 42 <> 46 <> 45 <> 196 <> 205 <> 43 <> 97 <> 183 <>
  117 <> 85 <> 38 <> 35 <> 179 <> 61 <> 39 <> 53 <> 200 <> 87 <> 26 <> 21 <> 43 <> 232 <> 171 <> 56 <> 34 <> 51 <> 104 <> 114 <> 102 <> 29 <> 93 <> 77 <>
  107 <> 54 <> 32 <> 26 <> 51 <> 1 <> 81 <> 43 <> 31 <> 39 <> 28 <> 85 <> 171 <> 58 <> 165 <> 90 <> 98 <> 64 <> 34 <> 22 <> 116 <> 206 <> 23 <> 34 <>
  43 <> 166 <> 73 <> 68 <> 25 <> 106 <> 22 <> 64 <> 171 <> 36 <> 225 <> 114 <> 34 <> 19 <> 21 <> 102 <> 132 <> 188 <> 16 <> 76 <> 124 <> 62 <> 18 <> 78 <>
  95 <> 85 <> 57 <> 50 <> 48 <> 51 <> 193 <> 101 <> 35 <> 159 <> 215 <> 111 <> 89 <> 46 <> 111 <> 60 <> 148 <> 31 <> 172 <> 219 <> 228 <> 21 <> 18 <> 111 <>
  112 <> 113 <> 77 <> 85 <> 179 <> 255 <> 38 <> 120 <> 114 <> 40 <> 42 <> 1 <> 196 <> 245 <> 209 <> 10 <> 25 <> 109 <> 100 <> 80 <> 8 <> 43 <> 154 <> 1 <>
  51 <> 26 <> 71 <> 88 <> 43 <> 29 <> 140 <> 166 <> 213 <> 37 <> 43 <> 154 <> 61 <> 63 <> 30 <> 155 <> 67 <> 45 <> 68 <> 1 <> 209 <> 142 <> 78 <> 78 <>
  16 <> 255 <> 128 <> 34 <> 197 <> 171 <> 41 <> 40 <> 5 <> 102 <> 211 <> 183 <> 4 <> 1 <> 221 <> 51 <> 50 <> 17 <> 168 <> 209 <> 192 <> 23 <> 25 <> 82 <>
  125 <> 98 <> 42 <> 88 <> 104 <> 85 <> 117 <> 175 <> 82 <> 95 <> 84 <> 53 <> 89 <> 128 <> 100 <> 113 <> 101 <> 45 <> 75 <> 79 <> 123 <> 47 <> 51 <> 128 <>
  81 <> 171 <> 1 <> 57 <> 17 <> 5 <> 71 <> 102 <> 57 <> 53 <> 41 <> 49 <> 115 <> 21 <> 2 <> 10 <> 102 <> 255 <> 166 <> 23 <> 6 <> 38 <> 33 <> 13 <>
  121 <> 57 <> 73 <> 26 <> 1 <> 85 <> 41 <> 10 <> 67 <> 138 <> 77 <> 110 <> 90 <> 47 <> 114 <> 101 <> 29 <> 16 <> 10 <> 85 <> 128 <> 101 <> 196 <> 26 <>
  57 <> 18 <> 10 <> 102 <> 102 <> 213 <> 34 <> 20 <> 43 <> 117 <> 20 <> 15 <> 36 <> 163 <> 128 <> 68 <> 1 <> 26 <> 138 <> 31 <> 36 <> 171 <> 27 <> 166 <>
  38 <> 44 <> 229 <> 67 <> 87 <> 58 <> 169 <> 82 <> 115 <> 26 <> 59 <> 179 <> 63 <> 59 <> 90 <> 180 <> 59 <> 166 <> 93 <> 73 <> 154 <> 40 <> 40 <> 21 <>
  116 <> 143 <> 209 <> 34 <> 39 <> 175 <> 57 <> 46 <> 22 <> 24 <> 128 <> 1 <> 54 <> 17 <> 37 <> 47 <> 15 <> 16 <> 183 <> 34 <> 223 <> 49 <> 45 <> 183 <>
  46 <> 17 <> 33 <> 183 <> 6 <> 98 <> 15 <> 32 <> 183 <> 65 <> 32 <> 73 <> 115 <> 28 <> 128 <> 23 <> 128 <> 205 <> 40 <> 3 <> 9 <> 115 <> 51 <> 192 <>
  18 <> 6 <> 223 <> 87 <> 37 <> 9 <> 115 <> 59 <> 77 <> 64 <> 21 <> 47 <> 104 <> 55 <> 44 <> 218 <> 9 <> 54 <> 53 <> 130 <> 226 <> 64 <> 90 <> 70 <>
  205 <> 40 <> 41 <> 23 <> 26 <> 57 <> 54 <> 57 <> 112 <> 184 <> 5 <> 41 <> 38 <> 166 <> 213 <> 30 <> 34 <> 26 <> 133 <> 152 <> 116 <> 10 <> 32 <> 134 <>
  75 <> 32 <> 12 <> 51 <> 192 <> 255 <> 160 <> 43 <> 51 <> 39 <> 19 <> 53 <> 221 <> 26 <> 114 <> 32 <> 73 <> 255 <> 31 <> 9 <> 65 <> 234 <> 2 <> 15 <>
  1 <> 118 <> 73 <> 88 <> 31 <> 35 <> 67 <> 102 <> 85 <> 55 <> 186 <> 85 <> 56 <> 21 <> 23 <> 111 <> 59 <> 205 <> 45 <> 37 <> 192 <> 55 <> 38 <> 70 <>
  124 <> 73 <> 102 <> 1 <> 34 <> 98 <> 102 <> 61 <> 71 <> 37 <> 34 <> 53 <> 31 <> 243 <> 192 <> 69 <> 60 <> 71 <> 38 <> 73 <> 119 <> 28 <> 222 <> 37 <>
  68 <> 45 <> 128 <> 34 <> 1 <> 47 <> 11 <> 245 <> 171 <> 62 <> 17 <> 19 <> 70 <> 146 <> 85 <> 55 <> 62 <> 70 <> 75 <> 15 <> 9 <> 9 <> 64 <> 255 <>
  184 <> 119 <> 16 <> 37 <> 43 <> 37 <> 154 <> 100 <> 163 <> 85 <> 160 <> 1 <> 63 <> 9 <> 92 <> 136 <> 28 <> 64 <> 32 <> 201 <> 85 <> 86 <> 6 <> 28 <>
  5 <> 64 <> 255 <> 25 <> 248 <> 1 <> 56 <> 8 <> 17 <> 132 <> 137 <> 255 <> 55 <> 116 <> 128 <> 58 <> 15 <> 20 <> 82 <> 135 <> 57 <> 26 <> 121 <> 40 <>
  164 <> 50 <> 31 <> 137 <> 154 <> 133 <> 25 <> 35 <> 218 <> 51 <> 103 <> 44 <> 131 <> 131 <> 123 <> 31 <> 6 <> 158 <> 86 <> 40 <> 64 <> 135 <> 148 <> 224 <>
  45 <> 183 <> 128 <> 22 <> 26 <> 17 <> 131 <> 240 <> 154 <> 14 <> 1 <> 209 <> 83 <> 12 <> 13 <> 54 <> 192 <> 255 <> 68 <> 47 <> 28 <> 45 <> 16 <> 21 <>
  91 <> 64 <> 222 <> 7 <> 1 <> 197 <> 56 <> 21 <> 39 <> 155 <> 60 <> 138 <> 23 <> 102 <> 213 <> 85 <> 26 <> 85 <> 85 <> 128 <> 128 <> 32 <> 146 <> 171 <>
  18 <> 11 <> 7 <> 63 <> 144 <> 171 <> 4 <> 4 <> 246 <> 35 <> 27 <> 10 <> 146 <> 174 <> 171 <> 12 <> 26 <> 128 <> 190 <> 80 <> 35 <> 99 <> 180 <> 80 <>
  126 <> 54 <> 45 <> 85 <> 126 <> 47 <> 87 <> 176 <> 51 <> 41 <> 20 <> 32 <> 101 <> 75 <> 128 <> 139 <> 118 <> 146 <> 116 <> 128 <> 85 <> 56 <> 41 <> 15 <>
  176 <> 236 <> 85 <> 37 <> 9 <> 62 <> 146 <> 36 <> 19 <> 30 <> 171 <> 255 <> 97 <> 27 <> 20 <> 71 <> 30 <> 17 <> 119 <> 118 <> 255 <> 17 <> 18 <> 138 <>
  101 <> 38 <> 60 <> 138 <> 55 <> 70 <> 43 <> 26 <> 142 <> 138 <> 45 <> 61 <> 62 <> 219 <> 1 <> 81 <> 188 <> 64 <> 32 <> 41 <> 20 <> 117 <> 151 <> 142 <>
  20 <> 21 <> 163 <> 112 <> 19 <> 12 <> 61 <> 195 <> 128 <> 48 <> 4 <> 24 <> Nil{}

def updateProbabilities() -> List<&2,U32>:
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 176 <> 246 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 223 <> 241 <> 252 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 249 <> 253 <> 253 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 244 <> 252 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 234 <> 254 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 253 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 246 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 239 <> 253 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 254 <> 255 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 248 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 251 <>
  255 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 253 <> 254 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 251 <> 254 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 254 <> 255 <> 254 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 254 <> 253 <> 255 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 250 <> 255 <> 254 <> 255 <> 254 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  217 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 225 <> 252 <> 241 <> 253 <> 255 <> 255 <> 254 <> 255 <> 255 <> 255 <> 255 <> 234 <> 250 <>
  241 <> 250 <> 253 <> 255 <> 253 <> 254 <> 255 <> 255 <> 255 <> 255 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 223 <> 254 <> 254 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 238 <> 253 <> 254 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 248 <> 254 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 249 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 253 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 247 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 253 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 252 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 254 <> 254 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 253 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 254 <> 253 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 250 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  186 <> 251 <> 250 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 234 <> 251 <> 244 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 251 <> 251 <>
  243 <> 253 <> 254 <> 255 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 253 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 236 <> 253 <> 254 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 251 <> 253 <> 253 <> 254 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 254 <> 254 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 254 <> 254 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 254 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 254 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  248 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 250 <> 254 <> 252 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 248 <> 254 <>
  249 <> 253 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 253 <> 253 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 246 <> 253 <> 253 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 252 <> 254 <> 251 <> 254 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 254 <> 252 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 248 <> 254 <> 253 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 253 <> 255 <> 254 <> 254 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 251 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 245 <> 251 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 253 <> 253 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 251 <> 253 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 252 <>
  253 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 252 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 249 <> 255 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 254 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 253 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 250 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <>
  255 <> 255 <> 254 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> Nil{}

def coefficientProbabilities() -> List<&2,U32>:
  128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <>
  128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 253 <> 136 <> 254 <> 255 <> 228 <> 219 <> 128 <> 128 <> 128 <> 128 <> 128 <> 189 <> 129 <> 242 <> 255 <>
  227 <> 213 <> 255 <> 219 <> 128 <> 128 <> 128 <> 106 <> 126 <> 227 <> 252 <> 214 <> 209 <> 255 <> 255 <> 128 <> 128 <> 128 <> 1 <> 98 <> 248 <> 255 <> 236 <> 226 <>
  255 <> 255 <> 128 <> 128 <> 128 <> 181 <> 133 <> 238 <> 254 <> 221 <> 234 <> 255 <> 154 <> 128 <> 128 <> 128 <> 78 <> 134 <> 202 <> 247 <> 198 <> 180 <> 255 <> 219 <>
  128 <> 128 <> 128 <> 1 <> 185 <> 249 <> 255 <> 243 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 184 <> 150 <> 247 <> 255 <> 236 <> 224 <> 128 <> 128 <> 128 <> 128 <>
  128 <> 77 <> 110 <> 216 <> 255 <> 236 <> 230 <> 128 <> 128 <> 128 <> 128 <> 128 <> 1 <> 101 <> 251 <> 255 <> 241 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 170 <>
  139 <> 241 <> 252 <> 236 <> 209 <> 255 <> 255 <> 128 <> 128 <> 128 <> 37 <> 116 <> 196 <> 243 <> 228 <> 255 <> 255 <> 255 <> 128 <> 128 <> 128 <> 1 <> 204 <> 254 <>
  255 <> 245 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 207 <> 160 <> 250 <> 255 <> 238 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 102 <> 103 <> 231 <> 255 <> 211 <>
  171 <> 128 <> 128 <> 128 <> 128 <> 128 <> 1 <> 152 <> 252 <> 255 <> 240 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 177 <> 135 <> 243 <> 255 <> 234 <> 225 <> 128 <>
  128 <> 128 <> 128 <> 128 <> 80 <> 129 <> 211 <> 255 <> 194 <> 224 <> 128 <> 128 <> 128 <> 128 <> 128 <> 1 <> 1 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <>
  128 <> 128 <> 246 <> 1 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <>
  198 <> 35 <> 237 <> 223 <> 193 <> 187 <> 162 <> 160 <> 145 <> 155 <> 62 <> 131 <> 45 <> 198 <> 221 <> 172 <> 176 <> 220 <> 157 <> 252 <> 221 <> 1 <> 68 <> 47 <>
  146 <> 208 <> 149 <> 167 <> 221 <> 162 <> 255 <> 223 <> 128 <> 1 <> 149 <> 241 <> 255 <> 221 <> 224 <> 255 <> 255 <> 128 <> 128 <> 128 <> 184 <> 141 <> 234 <> 253 <>
  222 <> 220 <> 255 <> 199 <> 128 <> 128 <> 128 <> 81 <> 99 <> 181 <> 242 <> 176 <> 190 <> 249 <> 202 <> 255 <> 255 <> 128 <> 1 <> 129 <> 232 <> 253 <> 214 <> 197 <>
  242 <> 196 <> 255 <> 255 <> 128 <> 99 <> 121 <> 210 <> 250 <> 201 <> 198 <> 255 <> 202 <> 128 <> 128 <> 128 <> 23 <> 91 <> 163 <> 242 <> 170 <> 187 <> 247 <> 210 <>
  255 <> 255 <> 128 <> 1 <> 200 <> 246 <> 255 <> 234 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 109 <> 178 <> 241 <> 255 <> 231 <> 245 <> 255 <> 255 <> 128 <> 128 <>
  128 <> 44 <> 130 <> 201 <> 253 <> 205 <> 192 <> 255 <> 255 <> 128 <> 128 <> 128 <> 1 <> 132 <> 239 <> 251 <> 219 <> 209 <> 255 <> 165 <> 128 <> 128 <> 128 <> 94 <>
  136 <> 225 <> 251 <> 218 <> 190 <> 255 <> 255 <> 128 <> 128 <> 128 <> 22 <> 100 <> 174 <> 245 <> 186 <> 161 <> 255 <> 199 <> 128 <> 128 <> 128 <> 1 <> 182 <> 249 <>
  255 <> 232 <> 235 <> 128 <> 128 <> 128 <> 128 <> 128 <> 124 <> 143 <> 241 <> 255 <> 227 <> 234 <> 128 <> 128 <> 128 <> 128 <> 128 <> 35 <> 77 <> 181 <> 251 <> 193 <>
  211 <> 255 <> 205 <> 128 <> 128 <> 128 <> 1 <> 157 <> 247 <> 255 <> 236 <> 231 <> 255 <> 255 <> 128 <> 128 <> 128 <> 121 <> 141 <> 235 <> 255 <> 225 <> 227 <> 255 <>
  255 <> 128 <> 128 <> 128 <> 45 <> 99 <> 188 <> 251 <> 195 <> 217 <> 255 <> 224 <> 128 <> 128 <> 128 <> 1 <> 1 <> 251 <> 255 <> 213 <> 255 <> 128 <> 128 <> 128 <>
  128 <> 128 <> 203 <> 1 <> 248 <> 255 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 137 <> 1 <> 177 <> 255 <> 224 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <>
  253 <> 9 <> 248 <> 251 <> 207 <> 208 <> 255 <> 192 <> 128 <> 128 <> 128 <> 175 <> 13 <> 224 <> 243 <> 193 <> 185 <> 249 <> 198 <> 255 <> 255 <> 128 <> 73 <> 17 <>
  171 <> 221 <> 161 <> 179 <> 236 <> 167 <> 255 <> 234 <> 128 <> 1 <> 95 <> 247 <> 253 <> 212 <> 183 <> 255 <> 255 <> 128 <> 128 <> 128 <> 239 <> 90 <> 244 <> 250 <>
  211 <> 209 <> 255 <> 255 <> 128 <> 128 <> 128 <> 155 <> 77 <> 195 <> 248 <> 188 <> 195 <> 255 <> 255 <> 128 <> 128 <> 128 <> 1 <> 24 <> 239 <> 251 <> 218 <> 219 <>
  255 <> 205 <> 128 <> 128 <> 128 <> 201 <> 51 <> 219 <> 255 <> 196 <> 186 <> 128 <> 128 <> 128 <> 128 <> 128 <> 69 <> 46 <> 190 <> 239 <> 201 <> 218 <> 255 <> 228 <>
  128 <> 128 <> 128 <> 1 <> 191 <> 251 <> 255 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 223 <> 165 <> 249 <> 255 <> 213 <> 255 <> 128 <> 128 <> 128 <> 128 <>
  128 <> 141 <> 124 <> 248 <> 255 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 1 <> 16 <> 248 <> 255 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 190 <>
  36 <> 230 <> 255 <> 236 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 149 <> 1 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 1 <> 226 <> 255 <>
  128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 247 <> 192 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 240 <> 128 <> 255 <> 128 <> 128 <>
  128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 1 <> 134 <> 252 <> 255 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 213 <> 62 <> 250 <> 255 <> 255 <> 128 <> 128 <>
  128 <> 128 <> 128 <> 128 <> 55 <> 93 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <>
  128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <>
  202 <> 24 <> 213 <> 235 <> 186 <> 191 <> 220 <> 160 <> 240 <> 175 <> 255 <> 126 <> 38 <> 182 <> 232 <> 169 <> 184 <> 228 <> 174 <> 255 <> 187 <> 128 <> 61 <> 46 <>
  138 <> 219 <> 151 <> 178 <> 240 <> 170 <> 255 <> 216 <> 128 <> 1 <> 112 <> 230 <> 250 <> 199 <> 191 <> 247 <> 159 <> 255 <> 255 <> 128 <> 166 <> 109 <> 228 <> 252 <>
  211 <> 215 <> 255 <> 174 <> 128 <> 128 <> 128 <> 39 <> 77 <> 162 <> 232 <> 172 <> 180 <> 245 <> 178 <> 255 <> 255 <> 128 <> 1 <> 52 <> 220 <> 246 <> 198 <> 199 <>
  249 <> 220 <> 255 <> 255 <> 128 <> 124 <> 74 <> 191 <> 243 <> 183 <> 193 <> 250 <> 221 <> 255 <> 255 <> 128 <> 24 <> 71 <> 130 <> 219 <> 154 <> 170 <> 243 <> 182 <>
  255 <> 255 <> 128 <> 1 <> 182 <> 225 <> 249 <> 219 <> 240 <> 255 <> 224 <> 128 <> 128 <> 128 <> 149 <> 150 <> 226 <> 252 <> 216 <> 205 <> 255 <> 171 <> 128 <> 128 <>
  128 <> 28 <> 108 <> 170 <> 242 <> 183 <> 194 <> 254 <> 223 <> 255 <> 255 <> 128 <> 1 <> 81 <> 230 <> 252 <> 204 <> 203 <> 255 <> 192 <> 128 <> 128 <> 128 <> 123 <>
  102 <> 209 <> 247 <> 188 <> 196 <> 255 <> 233 <> 128 <> 128 <> 128 <> 20 <> 95 <> 153 <> 243 <> 164 <> 173 <> 255 <> 203 <> 128 <> 128 <> 128 <> 1 <> 222 <> 248 <>
  255 <> 216 <> 213 <> 128 <> 128 <> 128 <> 128 <> 128 <> 168 <> 175 <> 246 <> 252 <> 235 <> 205 <> 255 <> 255 <> 128 <> 128 <> 128 <> 47 <> 116 <> 215 <> 255 <> 211 <>
  212 <> 255 <> 255 <> 128 <> 128 <> 128 <> 1 <> 121 <> 236 <> 253 <> 212 <> 214 <> 255 <> 255 <> 128 <> 128 <> 128 <> 141 <> 84 <> 213 <> 252 <> 201 <> 202 <> 255 <>
  219 <> 128 <> 128 <> 128 <> 42 <> 80 <> 160 <> 240 <> 162 <> 185 <> 255 <> 205 <> 128 <> 128 <> 128 <> 1 <> 1 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <>
  128 <> 128 <> 244 <> 1 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 238 <> 1 <> 255 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> 128 <> Nil{}

def dcQuantizers() -> List<&2,U32>:
  4 <> 5 <> 6 <> 7 <> 8 <> 9 <> 10 <> 10 <> 11 <> 12 <> 13 <> 14 <> 15 <> 16 <> 17 <> 17 <> 18 <> 19 <> 20 <> 20 <> 21 <> 21 <> 22 <> 22 <>
  23 <> 23 <> 24 <> 25 <> 25 <> 26 <> 27 <> 28 <> 29 <> 30 <> 31 <> 32 <> 33 <> 34 <> 35 <> 36 <> 37 <> 37 <> 38 <> 39 <> 40 <> 41 <> 42 <> 43 <>
  44 <> 45 <> 46 <> 46 <> 47 <> 48 <> 49 <> 50 <> 51 <> 52 <> 53 <> 54 <> 55 <> 56 <> 57 <> 58 <> 59 <> 60 <> 61 <> 62 <> 63 <> 64 <> 65 <> 66 <>
  67 <> 68 <> 69 <> 70 <> 71 <> 72 <> 73 <> 74 <> 75 <> 76 <> 76 <> 77 <> 78 <> 79 <> 80 <> 81 <> 82 <> 83 <> 84 <> 85 <> 86 <> 87 <> 88 <> 89 <>
  91 <> 93 <> 95 <> 96 <> 98 <> 100 <> 101 <> 102 <> 104 <> 106 <> 108 <> 110 <> 112 <> 114 <> 116 <> 118 <> 122 <> 124 <> 126 <> 128 <> 130 <> 132 <> 134 <> 136 <>
  138 <> 140 <> 143 <> 145 <> 148 <> 151 <> 154 <> 157 <> Nil{}

def acQuantizers() -> List<&2,U32>:
  4 <> 5 <> 6 <> 7 <> 8 <> 9 <> 10 <> 11 <> 12 <> 13 <> 14 <> 15 <> 16 <> 17 <> 18 <> 19 <> 20 <> 21 <> 22 <> 23 <> 24 <> 25 <> 26 <> 27 <>
  28 <> 29 <> 30 <> 31 <> 32 <> 33 <> 34 <> 35 <> 36 <> 37 <> 38 <> 39 <> 40 <> 41 <> 42 <> 43 <> 44 <> 45 <> 46 <> 47 <> 48 <> 49 <> 50 <> 51 <>
  52 <> 53 <> 54 <> 55 <> 56 <> 57 <> 58 <> 60 <> 62 <> 64 <> 66 <> 68 <> 70 <> 72 <> 74 <> 76 <> 78 <> 80 <> 82 <> 84 <> 86 <> 88 <> 90 <> 92 <>
  94 <> 96 <> 98 <> 100 <> 102 <> 104 <> 106 <> 108 <> 110 <> 112 <> 114 <> 116 <> 119 <> 122 <> 125 <> 128 <> 131 <> 134 <> 137 <> 140 <> 143 <> 146 <> 149 <> 152 <>
  155 <> 158 <> 161 <> 164 <> 167 <> 170 <> 173 <> 177 <> 181 <> 185 <> 189 <> 193 <> 197 <> 201 <> 205 <> 209 <> 213 <> 217 <> 221 <> 225 <> 229 <> 234 <> 239 <> 245 <>
  249 <> 254 <> 259 <> 264 <> 269 <> 274 <> 279 <> 284 <> Nil{}

# Signed intermediate values are represented by two's-complement U32 words.
def arithmeticShift(+value: U32, +bits: Nat) -> U32:
  U32.or(U32.shrn(value,bits),Bool.pick(U32,U32.is_ge(value,2147483648),U32.shln(4294967295,Nat.sub(32n,bits)),0))

def clampPositive(+value: U32, maximum: U32) -> U32:
  Bool.pick(U32,U32.is_ge(value,2147483648),0,U32.min(value,maximum))

type Features is Data:
  Features{enabled: Bool, updateMap: Bool, absolute: Bool, quantizers: Table, levels: Table, probabilities: Table}

def signedTable(fuel: Nat, +bits: Nat, +index: U32, tree: Table) -> Read(Table):
  match fuel:
    case 0n: Read.pure(Table,tree)
    case 1n+n:
      do Read<Table>:
        value : U32 <- optionalSigned(bits)
        signedTable(n,bits,(index + 1 : U32),tableSet(tree,index,value))

def probabilityTable(fuel: Nat, +index: U32, tree: Table) -> Read(Table):
  match fuel:
    case 0n: Read.pure(Table,tree)
    case 1n+n:
      do Read<Table>:
        present : U32 <- bit(128)
        value : U32 <- Bool.pick(Unit -> Read(U32),U32.is_eq(present,0),_ => Read.pure(U32,255),_ => literal(8n))(Unit{})
        probabilityTable(n,(index + 1 : U32),tableSet(tree,index,value))

type FeatureValues is Data: FeatureValues{absolute: Bool, quantizers: Table, levels: Table}

def featureValues() -> Read(FeatureValues):
  do Read<FeatureValues>:
    mode : U32 <- bit(128)
    quantizers : Table <- signedTable(4n,7n,0,emptyTable(2n,0))
    levels : Table <- signedTable(4n,6n,0,emptyTable(2n,0))
    Read.pure(FeatureValues,FeatureValues{U32.is_eq(mode,1),quantizers,levels})

def assembledFeatures(updateMap: Bool, probabilities: Table, values: FeatureValues) -> Features:
  match values:
    case FeatureValues{absolute,quants,levels}: Features{True{},updateMap,absolute,quants,levels,probabilities}

def readFeatures() -> Read(Features):
  do Read<Features>:
    +updateMap : U32 <- bit(128)
    updateValues : U32 <- bit(128)
    values : FeatureValues <- Bool.pick(Unit -> Read(FeatureValues),U32.is_eq(updateValues,0),
      _ => Read.pure(FeatureValues,FeatureValues{True{},emptyTable(2n,0),emptyTable(2n,0)}),_ => featureValues())(Unit{})
    probabilities : Table <- Bool.pick(Unit -> Read(Table),U32.is_eq(updateMap,0),_ => Read.pure(Table,emptyTable(2n,255)),_ => probabilityTable(3n,0,emptyTable(2n,255)))(Unit{})
    Read.pure(Features,assembledFeatures(U32.is_eq(updateMap,1),probabilities,values))

def features() -> Read(Features):
  do Read<Features>:
    enabled : U32 <- bit(128)
    Bool.pick(Unit -> Read(Features),U32.is_eq(enabled,0),
      _ => Read.pure(Features,Features{False{},False{},False{},emptyTable(2n,0),emptyTable(2n,0),emptyTable(2n,255)}),_ => readFeatures())(Unit{})

def filterAdjustments() -> Read(Row):
  do Read<Row>:
    references : Table <- signedTable(4n,6n,0,emptyTable(2n,0))
    modes : Table <- signedTable(4n,6n,0,emptyTable(2n,0))
    Read.pure(Row,Row{tableAt(references,0),tableAt(modes,0),0,0})

def filterUpdates() -> Read(Row):
  do Read<Row>:
    update : U32 <- bit(128)
    Bool.pick(Unit -> Read(Row),U32.is_eq(update,0),_ => Read.pure(Row,zeroRow()),_ => filterAdjustments())(Unit{})

type Quantization is Data:
  Quantization{base: U32, ydc: U32, y2dc: U32, y2ac: U32, uvdc: U32, uvac: U32}

def quantization() -> Read(Quantization):
  do Read<Quantization>:
    base : U32 <- literal(7n)
    ydc : U32 <- optionalSigned(4n)
    y2dc : U32 <- optionalSigned(4n)
    y2ac : U32 <- optionalSigned(4n)
    uvdc : U32 <- optionalSigned(4n)
    uvac : U32 <- optionalSigned(4n)
    Read.pure(Quantization,Quantization{base,ydc,y2dc,y2ac,uvdc,uvac})

def updatedProbabilities(values: List<&2,U32>, +index: U32, +tree: Table) -> Read(Table):
  match values:
    case Nil{}: Read.pure(Table,tree)
    case probability <> rest:
      do Read<Table>:
        changed : U32 <- bit(probability)
        updated : Table <- Bool.pick(Unit -> Read(Table),U32.is_eq(changed,0),_ => Read.pure(Table,tree),
          _ => do Read<Table>:
            value : U32 <- literal(8n)
            Read.pure(Table,tableSet(tree,index,value)))(Unit{})
        updatedProbabilities(rest,(index + 1 : U32),updated)

type Parameters is Data:
  Parameters{features: Features, simple: Bool, level: U32, sharpness: U32, filterDelta: Row, partitions: U32, quantization: Quantization, coefficients: Table, skip: Maybe<&2,U32>}

def parameters() -> Read(Parameters):
  do Read<Parameters>:
    featuresValue : Features <- features()
    simple : U32 <- bit(128)
    level : U32 <- literal(6n)
    sharpness : U32 <- literal(3n)
    adjusted : U32 <- bit(128)
    filterDelta : Row <- Bool.pick(Unit -> Read(Row),U32.is_eq(adjusted,0),_ => Read.pure(Row,zeroRow()),_ => filterUpdates())(Unit{})
    partitionBits : U32 <- literal(2n)
    quantizationValue : Quantization <- quantization()
    _ : U32 <- bit(128)
    coefficients : Table <- updatedProbabilities(updateProbabilities(),0,table(11n,coefficientProbabilities()))
    maySkip : U32 <- bit(128)
    skip : Maybe<&2,U32> <- Bool.pick(Unit -> Read(Maybe<&2,U32>),U32.is_eq(maySkip,0),_ => Read.pure(Maybe<&2,U32>,None{}),
      _ => do Read<Maybe<&2,U32>>:
        probability : U32 <- literal(8n)
        Read.pure(Maybe<&2,U32>,Some{probability}))(Unit{})
    Read.pure(Parameters,Parameters{featuresValue,U32.is_eq(simple,1),level,sharpness,filterDelta,U32.shln(1,U32.to_nat(partitionBits)),quantizationValue,coefficients,skip})

type Quantizer is Data:
  Quantizer{ydc: U32,yac: U32,y2dc: U32,y2ac: U32,uvdc: U32,uvac: U32}

def quantizerWithBase(+base: U32, values: Quantization, +dc: Table, +ac: Table) -> Quantizer:
  match values:
    case Quantization{_,ydc,y2dc,y2ac,uvdc,uvac}:
      Quantizer{tableAt(dc,clampPositive((base + ydc : U32),127)),tableAt(ac,clampPositive(base,127)),
        (tableAt(dc,clampPositive((base + y2dc : U32),127)) * 2 : U32),
        U32.max(8,(tableAt(ac,clampPositive((base + y2ac : U32),127)) * 155 / 100 : U32)),
        U32.min(132,tableAt(dc,clampPositive((base + uvdc : U32),127))),tableAt(ac,clampPositive((base + uvac : U32),127))}

def quantizer(segment: U32, featureValues: Features, +values: Quantization, dc: Table, ac: Table) -> Quantizer:
  match featureValues values:
    case Features{+enabled,_,absolute,quants,_,_} Quantization{base,_,_,_,_,_}:
      +adjustment = Bool.pick(U32,enabled,tableAt(quants,segment),0)
      quantizerWithBase(Bool.pick(U32,enabled && absolute,adjustment,(base + adjustment : U32)),values,dc,ac)

type Block is Data: Block{a: Row,b: Row,c: Row,d: Row}

def zeroBlock() -> Block: Block{zeroRow(),zeroRow(),zeroRow(),zeroRow()}

def rowGet(row: Row, index: U32) -> U32:
  match row index:
    case Row{a,_,_,_} 0: a
    case Row{_,b,_,_} 1: b
    case Row{_,_,c,_} 2: c
    case Row{_,_,_,d} _: d

def rowSet(row: Row, index: U32, value: U32) -> Row:
  match row index:
    case Row{_,b,c,d} 0: Row{value,b,c,d}
    case Row{a,_,c,d} 1: Row{a,value,c,d}
    case Row{a,b,_,d} 2: Row{a,b,value,d}
    case Row{a,b,c,_} _: Row{a,b,c,value}

def blockRow(block: Block, index: U32) -> Row:
  match block index:
    case Block{a,_,_,_} 0: a
    case Block{_,b,_,_} 1: b
    case Block{_,_,c,_} 2: c
    case Block{_,_,_,d} _: d

def blockGet(block: Block, +index: U32) -> U32: rowGet(blockRow(block,(index / 4 : U32)),(index % 4 : U32))

def blockSetRow(block: Block, index: U32, offset: U32, value: U32) -> Block:
  match block index:
    case Block{a,b,c,d} 0: Block{rowSet(a,offset,value),b,c,d}
    case Block{a,b,c,d} 1: Block{a,rowSet(b,offset,value),c,d}
    case Block{a,b,c,d} 2: Block{a,b,rowSet(c,offset,value),d}
    case Block{a,b,c,d} _: Block{a,b,c,rowSet(d,offset,value)}

def blockSet(block: Block, +index: U32, value: U32) -> Block: blockSetRow(block,(index / 4 : U32),(index % 4 : U32),value)

def transpose(block: Block) -> Block:
  match block:
    case Block{Row{a,b,c,d},Row{e,f,g,h},Row{i,j,k,l},Row{m,n,o,p}}: Block{Row{a,e,i,m},Row{b,f,j,n},Row{c,g,k,o},Row{d,h,l,p}}

# Exact low word of (signed(value) * factor) >> 16, without overflowing the
# product or requiring emulated 64-bit multiplication. Factors are below 2^16.
def multiplyShift(+value: U32, +factor: U32) -> U32:
  (arithmeticShift(value,16n) * factor + U32.shrn((U32.and(value,65535) * factor : U32),16n) : U32)

def idctRow(row: Row) -> Row:
  match row:
    case Row{+a,+b,+c,+d}:
      +sum = (a + c : U32)
      +difference = (a - c : U32)
      +odd1 = (multiplyShift(b,35468) - d - multiplyShift(d,20091) : U32)
      +odd2 = (b + multiplyShift(b,20091) + multiplyShift(d,35468) : U32)
      Row{(sum + odd2 : U32),(difference + odd1 : U32),(difference - odd1 : U32),(sum - odd2 : U32)}

def idctRows(block: Block) -> Block:
  match block:
    case Block{a,b,c,d}: Block{idctRow(a),idctRow(b),idctRow(c),idctRow(d)}

def scaledRow(row: Row, +rounding: U32) -> Row:
  match row:
    case Row{a,b,c,d}: Row{arithmeticShift((a + rounding : U32),3n),arithmeticShift((b + rounding : U32),3n),arithmeticShift((c + rounding : U32),3n),arithmeticShift((d + rounding : U32),3n)}

def scaledBlock(block: Block, +rounding: U32) -> Block:
  match block:
    case Block{a,b,c,d}: Block{scaledRow(a,rounding),scaledRow(b,rounding),scaledRow(c,rounding),scaledRow(d,rounding)}

def idct(block: Block) -> Block: scaledBlock(idctRows(transpose(idctRows(transpose(block)))),4)

def walshRow(row: Row) -> Row:
  match row:
    case Row{+a,+b,+c,+d}:
      +sum1 = (a + d : U32)
      +sum2 = (b + c : U32)
      +difference1 = (b - c : U32)
      +difference2 = (a - d : U32)
      Row{(sum1 + sum2 : U32),(difference1 + difference2 : U32),(sum1 - sum2 : U32),(difference2 - difference1 : U32)}

def walshRows(block: Block) -> Block:
  match block:
    case Block{a,b,c,d}: Block{walshRow(a),walshRow(b),walshRow(c),walshRow(d)}

def walsh(block: Block) -> Block: scaledBlock(walshRows(transpose(walshRows(transpose(block)))),3)

def tokenTree() -> List<&2,U32>:
  4294967285 <> 2 <> 0 <> 4 <> 4294967295 <> 6 <> 8 <> 12 <> 4294967294 <> 10 <> 4294967293 <> 4294967292 <> 14 <> 16 <> 4294967291 <> 4294967290 <> 18 <> 20 <> 4294967289 <> 4294967288 <> 4294967287 <> 4294967286 <> Nil{}

def categoryProbabilities(category: U32) -> List<&2,U32>:
  match category:
    case 5: 159 <> Nil{}
    case 6: 165 <> 145 <> Nil{}
    case 7: 173 <> 148 <> 140 <> Nil{}
    case 8: 176 <> 155 <> 140 <> 135 <> Nil{}
    case 9: 180 <> 157 <> 141 <> 134 <> 130 <> Nil{}
    case _: 254 <> 254 <> 243 <> 230 <> 196 <> 177 <> 153 <> 140 <> 133 <> 130 <> 129 <> Nil{}

def categoryBits(probabilities: List<&2,U32>, value: U32) -> Read(U32):
  match probabilities:
    case Nil{}: Read.pure(U32,value)
    case probability <> rest:
      do Read<U32>:
        next : U32 <- bit(probability)
        categoryBits(rest,(value * 2 + next : U32))

def tokenMagnitude(+token: U32) -> Read(U32):
  Bool.pick(Unit -> Read(U32),U32.is_lt(token,5),_ => Read.pure(U32,token),
    _ => do Read<U32>:
      extra : U32 <- categoryBits(categoryProbabilities(token),0)
      Read.pure(U32,(extra + small(5 <> 7 <> 11 <> 19 <> 35 <> 67 <> Nil{},(token - 5 : U32)) : U32)))(Unit{})

def coefficientBand(index: U32) -> U32: small(0 <> 1 <> 2 <> 3 <> 6 <> 4 <> 5 <> 6 <> 6 <> 6 <> 6 <> 6 <> 6 <> 6 <> 6 <> 7 <> Nil{},index)
def zigzag(index: U32) -> U32: small(0 <> 1 <> 4 <> 8 <> 5 <> 2 <> 3 <> 6 <> 9 <> 12 <> 13 <> 10 <> 7 <> 11 <> 14 <> 15 <> Nil{},index)

type Residue is Data: Residue{block: Block,nonzero: U32}

def coefficients(fuel: Nat, +index: U32, +plane: U32, +probabilities: Table, complexity: U32, skip: Bool, +dc: U32, +ac: U32, +block: Block, +nonzero: U32) -> Read(Residue):
  match fuel:
    case 0n: Read.pure(Residue,Residue{block,nonzero})
    case 1n+ +n:
      do Read<Residue>:
        +token : U32 <- branch(12n,tokenTree(),probabilities,((plane * 8 + coefficientBand(index)) * 33 + complexity * 11 : U32),Bool.pick(U32,skip,2,0))
        Bool.pick(Unit -> Read(Residue),U32.is_eq(token,11),_ => Read.pure(Residue,Residue{block,nonzero}),
          _ => Bool.pick(Unit -> Read(Residue),U32.is_eq(token,0),
            _ => coefficients(n,(index + 1 : U32),plane,probabilities,0,True{},dc,ac,block,1),
            _ => do Read<Residue>:
              +magnitude : U32 <- tokenMagnitude(token)
              sign : U32 <- bit(128)
              +position : U32 <- Read.pure(U32,zigzag(index))
              signedValue : U32 <- Read.pure(U32,Bool.pick(U32,U32.is_eq(sign,0),magnitude,(0 - magnitude : U32)))
              coefficients(n,(index + 1 : U32),plane,probabilities,U32.min(magnitude,2),False{},dc,ac,blockSet(block,position,(signedValue * Bool.pick(U32,U32.is_eq(position,0),dc,ac) : U32)),1))(Unit{}))(Unit{})

def readCoefficients(+plane: U32, probabilities: Table, complexity: U32, dc: U32, ac: U32, block: Block) -> Read(Residue):
  +first = Bool.pick(U32,U32.is_eq(plane,0),1,0)
  coefficients(U32.to_nat((16 - first : U32)),first,plane,probabilities,complexity,False{},dc,ac,block,0)

type Edges is Data:
  Edges{p: U32,a: U32,b: U32,c: U32,d: U32,e: U32,f: U32,g: U32,h: U32,l0: U32,l1: U32,l2: U32,l3: U32}

def avg2(a: U32,b: U32) -> U32: ((a + b + 1) / 2 : U32)
def avg3(a: U32,b: U32,c: U32) -> U32: ((a + b * 2 + c + 2) / 4 : U32)
def repeatRow(+value: U32) -> Row: Row{value,value,value,value}
def repeatBlock(+row: Row) -> Block: Block{row,row,row,row}
def trueMotion(+left: U32,+p: U32, row: Row) -> Row:
  match row:
    case Row{a,b,c,d}: Row{clampPositive((left + a - p : U32),255),clampPositive((left + b - p : U32),255),clampPositive((left + c - p : U32),255),clampPositive((left + d - p : U32),255)}

def predict4(mode: U32, edges: Edges) -> Block:
  match mode edges:
    case 0 Edges{_,a,b,c,d,_,_,_,_,l0,l1,l2,l3}:
      repeatBlock(repeatRow(((a + b + c + d + l0 + l1 + l2 + l3 + 4) / 8 : U32)))
    case 1 Edges{+p,+a,+b,+c,+d,_,_,_,_,l0,l1,l2,l3}:
      Block{trueMotion(l0,p,Row{a,b,c,d}),trueMotion(l1,p,Row{a,b,c,d}),trueMotion(l2,p,Row{a,b,c,d}),trueMotion(l3,p,Row{a,b,c,d})}
    case 2 Edges{p,+a,+b,+c,+d,e,_,_,_,_,_,_,_}:
      repeatBlock(Row{avg3(p,a,b),avg3(a,b,c),avg3(b,c,d),avg3(c,d,e)})
    case 3 Edges{p,_,_,_,_,_,_,_,_,+l0,+l1,+l2,+l3}:
      Block{repeatRow(avg3(p,l0,l1)),repeatRow(avg3(l0,l1,l2)),repeatRow(avg3(l1,l2,l3)),repeatRow(avg3(l2,l3,l3))}
    case 4 Edges{_,a,+b,+c,+d,+e,+f,+g,+h,_,_,_,_}:
      +v0 = avg3(a,b,c)
      +v1 = avg3(b,c,d)
      +v2 = avg3(c,d,e)
      +v3 = avg3(d,e,f)
      +v4 = avg3(e,f,g)
      +v5 = avg3(f,g,h)
      v6 = avg3(g,h,h)
      Block{Row{v0,v1,v2,v3},Row{v1,v2,v3,v4},Row{v2,v3,v4,v5},Row{v3,v4,v5,v6}}
    case 5 Edges{+p,+a,+b,+c,d,_,_,_,_,+l0,+l1,+l2,l3}:
      v0 = avg3(l3,l2,l1)
      +v1 = avg3(l2,l1,l0)
      +v2 = avg3(l1,l0,p)
      +v3 = avg3(l0,p,a)
      +v4 = avg3(p,a,b)
      +v5 = avg3(a,b,c)
      v6 = avg3(b,c,d)
      Block{Row{v3,v4,v5,v6},Row{v2,v3,v4,v5},Row{v1,v2,v3,v4},Row{v0,v1,v2,v3}}
    case 6 Edges{+p,+a,+b,+c,+d,_,_,_,_,+l0,+l1,l2,_}:
      Block{Row{avg2(p,a),avg2(a,b),avg2(b,c),avg2(c,d)},Row{avg3(l0,p,a),avg3(p,a,b),avg3(a,b,c),avg3(b,c,d)},Row{avg3(l1,l0,p),avg2(p,a),avg2(a,b),avg2(b,c)},Row{avg3(l2,l1,l0),avg3(l0,p,a),avg3(p,a,b),avg3(a,b,c)}}
    case 7 Edges{_,+a,+b,+c,+d,+e,+f,+g,h,_,_,_,_}:
      Block{Row{avg2(a,b),avg2(b,c),avg2(c,d),avg2(d,e)},Row{avg3(a,b,c),avg3(b,c,d),avg3(c,d,e),avg3(d,e,f)},Row{avg2(b,c),avg2(c,d),avg2(d,e),avg3(e,f,g)},Row{avg3(b,c,d),avg3(c,d,e),avg3(d,e,f),avg3(f,g,h)}}
    case 8 Edges{+p,+a,+b,c,_,_,_,_,_,+l0,+l1,+l2,+l3}:
      Block{Row{avg2(l0,p),avg3(l0,p,a),avg3(p,a,b),avg3(a,b,c)},Row{avg2(l1,l0),avg3(l1,l0,p),avg2(l0,p),avg3(l0,p,a)},Row{avg2(l2,l1),avg3(l2,l1,l0),avg2(l1,l0),avg3(l1,l0,p)},Row{avg2(l3,l2),avg3(l3,l2,l1),avg2(l2,l1),avg3(l2,l1,l0)}}
    case 9 Edges{_,_,_,_,_,_,_,_,_,+l0,+l1,+l2,+l3}:
      Block{Row{avg2(l0,l1),avg3(l0,l1,l2),avg2(l1,l2),avg3(l1,l2,l3)},Row{avg2(l1,l2),avg3(l1,l2,l3),avg2(l2,l3),avg3(l2,l3,l3)},Row{avg2(l2,l3),avg3(l2,l3,l3),l3,l3},Row{l3,l3,l3,l3}}
    case _ _: zeroBlock()

type Macroblock is Data:
  Macroblock{segment: U32,skip: Bool,luma: U32,chroma: U32,modes: Block}

def intraModes(fuel: Nat, +index: U32, +above: Block, +left: Row, +probabilities: Table, +modes: Block) -> Read(Block):
  match fuel:
    case 0n: Read.pure(Block,modes)
    case 1n+n:
      +x = (index % 4 : U32)
      +y = (index / 4 : U32)
      topMode = Bool.pick(Unit -> U32,U32.is_eq(y,0),_ => blockGet(above,(12 + x : U32)),_ => blockGet(modes,(index - 4 : U32)))(Unit{})
      leftMode = Bool.pick(Unit -> U32,U32.is_eq(x,0),_ => rowGet(left,y),_ => blockGet(modes,(index - 1 : U32)))(Unit{})
      do Read<Block>:
        value : U32 <- branch(10n,0 <> 2 <> 4294967295 <> 4 <> 4294967294 <> 6 <> 8 <> 12 <> 4294967293 <> 10 <> 4294967291 <> 4294967290 <> 4294967292 <> 14 <> 4294967289 <> 16 <> 4294967288 <> 4294967287 <> Nil{},probabilities,((topMode * 10 + leftMode) * 9 : U32),0)
        intraModes(n,(index + 1 : U32),above,left,probabilities,blockSet(modes,index,value))

def segment(featuresValue: Features) -> Read(U32):
  match featuresValue:
    case Features{enabled,updateMap,_,_,_,probabilities}:
      Bool.pick(Unit -> Read(U32),enabled && updateMap,_ => branch(3n,2 <> 4 <> 0 <> 4294967295 <> 4294967294 <> 4294967293 <> Nil{},probabilities,0,0),_ => Read.pure(U32,0))(Unit{})

def skipCoefficient(probability: Maybe<&2,U32>) -> Read(U32):
  match probability:
    case None{}: Read.pure(U32,0)
    case Some{value}: bit(value)

def macroblock(featuresValue: Features, skipProbability: Maybe<&2,U32>, above: Block, left: Row, probabilities: Table) -> Read(Macroblock):
  do Read<Macroblock>:
    segmentId : U32 <- segment(featuresValue)
    skip : U32 <- skipCoefficient(skipProbability)
    +luma : U32 <- branch(5n,4294967292 <> 2 <> 4 <> 6 <> 0 <> 4294967295 <> 4294967294 <> 4294967293 <> Nil{},table(2n,145 <> 156 <> 163 <> 128 <> Nil{}),0,0)
    modes : Block <- Bool.pick(Unit -> Read(Block),U32.is_eq(luma,4),_ => intraModes(16n,0,above,left,probabilities,zeroBlock()),
      _ => Read.pure(Block,repeatBlock(repeatRow(small(0 <> 2 <> 3 <> 1 <> Nil{},luma)))))(Unit{})
    chroma : U32 <- branch(4n,0 <> 2 <> 4294967295 <> 4 <> 4294967294 <> 4294967293 <> Nil{},table(2n,142 <> 114 <> 183 <> Nil{}),0,0)
    Read.pure(Macroblock,Macroblock{segmentId,U32.is_eq(skip,1),luma,chroma,modes})

def rightModes(modes: Block) -> Row:
  match modes:
    case Block{Row{_,_,_,a},Row{_,_,_,b},Row{_,_,_,c},Row{_,_,_,d}}: Row{a,b,c,d}

type Residuals is Data:
  Residuals{blocks: List<&2,Block>,top: Block,left: Block}

type DcResidual is Data:
  DcResidual{block: Block,top: Block,left: Block}

def dcResidue(+top: Block,+left: Block, residue: Residue) -> DcResidual:
  match residue:
    case Residue{block,+nonzero}: DcResidual{walsh(block),blockSet(top,0,nonzero),blockSet(left,0,nonzero)}

def dcResidual(+luma: U32,+top: Block,+left: Block,probabilities: Table,quantizers: Quantizer) -> Read(DcResidual):
  match quantizers:
    case Quantizer{_,_,dc,ac,_,_}:
      Bool.pick(Unit -> Read(DcResidual),U32.is_eq(luma,4),_ => Read.pure(DcResidual,DcResidual{zeroBlock(),top,left}),
        _ => do Read<DcResidual>:
          residue : Residue <- readCoefficients(1,probabilities,(blockGet(top,0) + blockGet(left,0) : U32),dc,ac,zeroBlock())
          Read.pure(DcResidual,dcResidue(top,left,residue)))(Unit{})

def residualIndices(+index: U32) -> Row:
  Bool.pick(Row,U32.is_lt(index,16),Row{(1 + index % 4 : U32),(1 + index / 4 : U32),0,0},
    Row{(5 + (index - 16) / 4 * 2 + index % 2 : U32),(5 + (index - 16) / 4 * 2 + index % 4 / 2 : U32),0,0})

def assembledResidual(top: Block,left: Block,indices: Row,residue: Residue,blocks: List<&2,Block>) -> Residuals:
  match indices residue:
    case Row{x,y,_,_} Residue{+block,+nonzero}:
      Residuals{Bool.pick(Unit -> Block,U32.is_gt(nonzero,0) || U32.is_gt(blockGet(block,0),0),_ => idct(block),_ => block)(Unit{}) <> blocks,blockSet(top,x,nonzero),blockSet(left,y,nonzero)}

def residualBlocks(fuel: Nat,+index: U32,+luma: U32,+probabilities: Table,+quantizers: Quantizer,+dcBlock: Block,state: Residuals) -> Read(Residuals):
  match fuel quantizers state:
    case 0n _ Residuals{blocks,top,left}: Read.pure(Residuals,Residuals{List.reverse(&2,Block,blocks),top,left})
    case 1n+n Quantizer{ydc,yac,_,_,uvdc,uvac} Residuals{blocks,+top,+left}:
      +indices = residualIndices(index)
      +initial = Bool.pick(Unit -> Block,U32.is_lt(index,16),_ => blockSet(zeroBlock(),0,blockGet(dcBlock,index)),_ => zeroBlock())(Unit{})
      do Read<Residuals>:
        residue : Residue <- readCoefficients(Bool.pick(U32,U32.is_lt(index,16),Bool.pick(U32,U32.is_eq(luma,4),3,0),2),probabilities,
          (blockGet(top,rowGet(indices,0)) + blockGet(left,rowGet(indices,1)) : U32),
          Bool.pick(U32,U32.is_lt(index,16),ydc,uvdc),Bool.pick(U32,U32.is_lt(index,16),yac,uvac),initial)
        residualBlocks(n,(index + 1 : U32),luma,probabilities,quantizers,dcBlock,assembledResidual(top,left,indices,residue,blocks))

def afterDc(luma: U32,probabilities: Table,quantizers: Quantizer,value: DcResidual) -> Read(Residuals):
  match value:
    case DcResidual{dc,top,left}: residualBlocks(24n,0,luma,probabilities,quantizers,dc,Residuals{Nil{},top,left})

def emptyBlocks(count: Nat) -> List<&2,Block>:
  match count:
    case 0n: Nil{}
    case 1n+n: zeroBlock() <> emptyBlocks(n)

def residuals(meta: Macroblock,+probabilities: Table,+quantizers: Quantizer,+top: Block,+left: Block) -> Read(Residuals):
  match meta:
    case Macroblock{_,skip,+luma,_,_}:
      Bool.pick(Unit -> Read(Residuals),skip,
        _ => Read.pure(Residuals,Residuals{emptyBlocks(24n),blockSet(zeroBlock(),0,Bool.pick(U32,U32.is_eq(luma,4),blockGet(top,0),0)),blockSet(zeroBlock(),0,Bool.pick(U32,U32.is_eq(luma,4),blockGet(left,0),0))}),
        _ => do Read<Residuals>:
          dc : DcResidual <- dcResidual(luma,top,left,probabilities,quantizers)
          afterDc(luma,probabilities,quantizers,dc))(Unit{})

# The reconstruction buffer is owned and threaded through a small local state
# computation. Sequential samples/writes stay explicit without copying pixels.
def Pixels(-A: Data) -> Type: Array<U32> -> Array<U32> & A

def Pixels.pure(-A: Data,value: A) -> Pixels(A): pixels => (pixels,value)

def pixelsBound(-A: Data,-B: Data,next: A -> Pixels(B),pair: Array<U32> & A) -> Array<U32> & B:
  match pair:
    case (pixels,value): next(value)(pixels)

def Pixels.bind(-A: Data,-B: Data,step: Pixels(A),next: A -> Pixels(B)) -> Pixels(B):
  pixels => pixelsBound(A,B,next,step(pixels))

def get(index: U32) -> Pixels(U32): pixels => Array.get(U32,pixels,index)
def put(index: U32,value: U32) -> Pixels(Unit): pixels => (Array.set(U32,pixels,index,value),Unit{})

type Plane is Data: Plane{offset: U32,stride: U32,width: U32,height: U32,size: U32}

def point(plane: Plane,x: U32,y: U32) -> U32:
  match plane:
    case Plane{offset,stride,_,_,_}: (offset + y * stride + x : U32)

# Coordinates may contain -1 encoded as a word. Border sentinels are chosen
# before indexing. Padded reconstructed neighbors remain available until cropping.
def borderSample(plane: Plane,+x: U32,+y: U32,vertical: Bool) -> Pixels(U32):
  match plane:
    case Plane{offset,+stride,_,_,_}:
      Bool.pick(Unit -> Pixels(U32),U32.is_ge(y,2147483648),_ => Pixels.pure(U32,127),
        _ => Bool.pick(Unit -> Pixels(U32),U32.is_ge(x,2147483648),_ => Pixels.pure(U32,129),
          _ => get((offset + y * stride + U32.min(x,(stride - 1 : U32)) : U32)))(Unit{}))(Unit{})

def edgeValue(+plane: Plane,+mx: U32,+my: U32,+bx: U32,+by: U32,+position: U32) -> Pixels(U32):
  Bool.pick(Unit -> Pixels(U32),U32.is_eq(position,0),_ => borderSample(plane,(mx + bx - 1 : U32),(my + by - 1 : U32),False{}),
    _ => Bool.pick(Unit -> Pixels(U32),U32.is_le(position,8),
      _ => borderSample(plane,(mx + bx + position - 1 : U32),Bool.pick(U32,U32.is_ge((bx + position - 1 : U32),16),(my - 1 : U32),(my + by - 1 : U32)),False{}),
      _ => borderSample(plane,(mx + bx - 1 : U32),(my + by + position - 9 : U32),True{}))(Unit{}))(Unit{})

def edges4(+plane: Plane,+mx: U32,+my: U32,+bx: U32,+by: U32) -> Pixels(Edges):
  do Pixels<Edges>:
    p : U32 <- edgeValue(plane,mx,my,bx,by,0)
    a : U32 <- edgeValue(plane,mx,my,bx,by,1)
    b : U32 <- edgeValue(plane,mx,my,bx,by,2)
    c : U32 <- edgeValue(plane,mx,my,bx,by,3)
    d : U32 <- edgeValue(plane,mx,my,bx,by,4)
    e : U32 <- edgeValue(plane,mx,my,bx,by,5)
    f : U32 <- edgeValue(plane,mx,my,bx,by,6)
    g : U32 <- edgeValue(plane,mx,my,bx,by,7)
    h : U32 <- edgeValue(plane,mx,my,bx,by,8)
    l0 : U32 <- edgeValue(plane,mx,my,bx,by,9)
    l1 : U32 <- edgeValue(plane,mx,my,bx,by,10)
    l2 : U32 <- edgeValue(plane,mx,my,bx,by,11)
    l3 : U32 <- edgeValue(plane,mx,my,bx,by,12)
    Pixels.pure(Edges,Edges{p,a,b,c,d,e,f,g,h,l0,l1,l2,l3})

def writeBlock(fuel: Nat,+index: U32,+plane: Plane,+x: U32,+y: U32,+prediction: Block,+residue: Block) -> Pixels(Unit):
  match fuel:
    case 0n: Pixels.pure(Unit,Unit{})
    case 1n+n:
      do Pixels<Unit>:
        put(point(plane,(x + index % 4 : U32),(y + index / 4 : U32)),clampPositive((blockGet(prediction,index) + blockGet(residue,index) : U32),255))
        writeBlock(n,(index + 1 : U32),plane,x,y,prediction,residue)

def predictedBlocks(blocks: List<&2,Block>,+index: U32,+plane: Plane,+mx: U32,+my: U32,+modes: Block) -> Pixels(Unit):
  match blocks:
    case Nil{}: Pixels.pure(Unit,Unit{})
    case residue <> rest:
      +bx = (index % 4 * 4 : U32)
      +by = (index / 4 * 4 : U32)
      do Pixels<Unit>:
        edges : Edges <- edges4(plane,mx,my,bx,by)
        writeBlock(16n,0,plane,(mx + bx : U32),(my + by : U32),predict4(blockGet(modes,index),edges),residue)
        predictedBlocks(rest,(index + 1 : U32),plane,mx,my,modes)

def boundary(fuel: Nat,+index: U32,+plane: Plane,+mx: U32,+my: U32,+vertical: Bool,values: Table) -> Pixels(Table):
  match fuel:
    case 0n: Pixels.pure(Table,values)
    case 1n+n:
      do Pixels<Table>:
        value : U32 <- borderSample(plane,Bool.pick(U32,vertical,(mx - 1 : U32),(mx + index : U32)),Bool.pick(U32,vertical,(my + index : U32),(my - 1 : U32)),vertical)
        boundary(n,(index + 1 : U32),plane,mx,my,vertical,tableSet(values,index,value))

def sumBoundary(fuel: Nat,+index: U32,+values: Table,sum: U32) -> U32:
  match fuel:
    case 0n: sum
    case 1n+n: sumBoundary(n,(index + 1 : U32),values,(sum + tableAt(values,index) : U32))

def dcPrediction(+size: U32,+mx: U32,+my: U32,above: Table,left: Table) -> U32:
  +sum = (Bool.pick(U32,U32.is_eq(mx,0),0,sumBoundary(U32.to_nat(size),0,left,0)) + Bool.pick(U32,U32.is_eq(my,0),0,sumBoundary(U32.to_nat(size),0,above,0)) : U32)
  +count = (Bool.pick(U32,U32.is_eq(mx,0),0,size) + Bool.pick(U32,U32.is_eq(my,0),0,size) : U32)
  Bool.pick(Unit -> U32,U32.is_eq(count,0),_ => 128,_ => ((sum + count / 2) / count : U32))(Unit{})

def predictedPixel(mode: U32,top: U32,left: U32,corner: U32,dc: U32) -> U32:
  match mode:
    case 0: dc
    case 1: top
    case 2: left
    case _: clampPositive((top + left - corner : U32),255)

def bigPrediction(fuel: Nat,+index: U32,+plane: Plane,+mx: U32,+my: U32,+size: U32,+mode: U32,+top: Table,+left: Table,+corner: U32,+dc: U32) -> Pixels(Unit):
  match fuel:
    case 0n: Pixels.pure(Unit,Unit{})
    case 1n+n:
      +x = (index % size : U32)
      +y = (index / size : U32)
      do Pixels<Unit>:
        put(point(plane,(mx + x : U32),(my + y : U32)),predictedPixel(mode,tableAt(top,x),tableAt(left,y),corner,dc))
        bigPrediction(n,(index + 1 : U32),plane,mx,my,size,mode,top,left,corner,dc)

def predictPlane(+plane: Plane,+mx: U32,+my: U32,mode: U32) -> Pixels(Unit):
  match plane:
    case Plane{_,_,_,_,+size}:
      do Pixels<Unit>:
        +top : Table <- boundary(U32.to_nat(size),0,plane,mx,my,False{},emptyTable(4n,0))
        +left : Table <- boundary(U32.to_nat(size),0,plane,mx,my,True{},emptyTable(4n,0))
        corner : U32 <- borderSample(plane,(mx - 1 : U32),(my - 1 : U32),False{})
        bigPrediction(U32.to_nat((size * size : U32)),0,plane,mx,my,size,mode,top,left,corner,dcPrediction(size,mx,my,top,left))

def addBlock(fuel: Nat,+index: U32,+plane: Plane,+x: U32,+y: U32,+residue: Block) -> Pixels(Unit):
  match fuel:
    case 0n: Pixels.pure(Unit,Unit{})
    case 1n+n:
      +position = point(plane,(x + index % 4 : U32),(y + index / 4 : U32))
      do Pixels<Unit>:
        value : U32 <- get(position)
        put(position,clampPositive((value + blockGet(residue,index) : U32),255))
        addBlock(n,(index + 1 : U32),plane,x,y,residue)

def addBlocks(blocks: List<&2,Block>,+index: U32,+plane: Plane,+mx: U32,+my: U32,+columns: U32) -> Pixels(Unit):
  match blocks:
    case Nil{}: Pixels.pure(Unit,Unit{})
    case residue <> rest:
      do Pixels<Unit>:
        addBlock(16n,0,plane,(mx + index % columns * 4 : U32),(my + index / columns * 4 : U32),residue)
        addBlocks(rest,(index + 1 : U32),plane,mx,my,columns)

type Edge is Data: Edge{p3: U32,p2: U32,p1: U32,p0: U32,q0: U32,q1: U32,q2: U32,q3: U32}

def difference(+a: U32,+b: U32) -> U32: Bool.pick(U32,U32.is_ge(a,b),(a - b : U32),(b - a : U32))
def clampSigned(+value: U32) -> U32: Bool.pick(U32,U32.is_ge(value,2147483648),U32.max(value,4294967168),U32.min(value,127))

def eligible(edge: Edge,+interior: U32,limit: U32,simple: Bool) -> Bool:
  match edge:
    case Edge{p3,+p2,+p1,+p0,+q0,+q1,+q2,q3}:
      U32.is_le((difference(p0,q0) * 2 + difference(p1,q1) / 2 : U32),limit) &&
        (simple || (U32.is_le(difference(p3,p2),interior) && U32.is_le(difference(p2,p1),interior) && U32.is_le(difference(p1,p0),interior) && U32.is_le(difference(q3,q2),interior) && U32.is_le(difference(q2,q1),interior) && U32.is_le(difference(q1,q0),interior)))

def adjustCommon(edge: Edge,+outer: Bool,subblock: Bool) -> Edge:
  match edge:
    case Edge{p3,p2,+p1,+p0,+q0,+q1,q2,q3}:
      +w = clampSigned((Bool.pick(U32,outer,clampSigned((p1 - q1 : U32)),0) + 3 * (q0 - p0) : U32))
      +a = arithmeticShift(clampSigned((w + 4 : U32)),3n)
      b = arithmeticShift(clampSigned((w + 3 : U32)),3n)
      +spread = Bool.pick(U32,subblock && Bool.not(outer),arithmeticShift((a + 1 : U32),1n),0)
      # VP8 spreads the adjustment symmetrically across the edge.
      Edge{p3,p2,clampPositive((p1 + spread : U32),255),clampPositive((p0 + b : U32),255),clampPositive((q0 - a : U32),255),clampPositive((q1 - spread : U32),255),q2,q3}

def adjustMacroblock(edge: Edge) -> Edge:
  match edge:
    case Edge{p3,+p2,+p1,+p0,+q0,+q1,+q2,q3}:
      +w = clampSigned((clampSigned((p1 - q1 : U32)) + 3 * (q0 - p0) : U32))
      +a = clampSigned(arithmeticShift((27 * w + 63 : U32),7n))
      +b = clampSigned(arithmeticShift((18 * w + 63 : U32),7n))
      +c = clampSigned(arithmeticShift((9 * w + 63 : U32),7n))
      Edge{p3,clampPositive((p2 + c : U32),255),clampPositive((p1 + b : U32),255),clampPositive((p0 + a : U32),255),clampPositive((q0 - a : U32),255),clampPositive((q1 - b : U32),255),clampPositive((q2 - c : U32),255),q3}

def highVariance(edge: Edge,+threshold: U32) -> Bool:
  match edge:
    case Edge{_,_,p1,p0,q0,q1,_,_}: U32.is_gt(difference(p1,p0),threshold) || U32.is_gt(difference(q1,q0),threshold)

def filteredEdge(+edge: Edge,+simple: Bool,macroblockEdge: Bool,interior: U32,limit: U32,hev: U32) -> Edge:
  Bool.pick(Unit -> Edge,eligible(edge,interior,limit,simple),
    _ => Bool.pick(Unit -> Edge,simple || highVariance(edge,hev),_ => adjustCommon(edge,True{},False{}),
      _ => Bool.pick(Unit -> Edge,macroblockEdge,_ => adjustMacroblock(edge),_ => adjustCommon(edge,False{},True{}))(Unit{}))(Unit{}),_ => edge)(Unit{})

def readEdge(+position: U32,+stride: U32) -> Pixels(Edge):
  do Pixels<Edge>:
    p3 : U32 <- get((position - 4 * stride : U32))
    p2 : U32 <- get((position - 3 * stride : U32))
    p1 : U32 <- get((position - 2 * stride : U32))
    p0 : U32 <- get((position - stride : U32))
    q0 : U32 <- get(position)
    q1 : U32 <- get((position + stride : U32))
    q2 : U32 <- get((position + 2 * stride : U32))
    q3 : U32 <- get((position + 3 * stride : U32))
    Pixels.pure(Edge,Edge{p3,p2,p1,p0,q0,q1,q2,q3})

def writeEdge(+position: U32,+stride: U32,edge: Edge) -> Pixels(Unit):
  match edge:
    case Edge{_,p2,p1,p0,q0,q1,q2,_}:
      do Pixels<Unit>:
        put((position - 3 * stride : U32),p2)
        put((position - 2 * stride : U32),p1)
        put((position - stride : U32),p0)
        put(position,q0)
        put((position + stride : U32),q1)
        put((position + 2 * stride : U32),q2)
        Pixels.pure(Unit,Unit{})

def filterLine(fuel: Nat,+position: U32,+step: U32,+stride: U32,+simple: Bool,+macroblockEdge: Bool,+interior: U32,+limit: U32,+hev: U32) -> Pixels(Unit):
  match fuel:
    case 0n: Pixels.pure(Unit,Unit{})
    case 1n+n:
      do Pixels<Unit>:
        edge : Edge <- readEdge(position,stride)
        writeEdge(position,stride,filteredEdge(edge,simple,macroblockEdge,interior,limit,hev))
        filterLine(n,(position + step : U32),step,stride,simple,macroblockEdge,interior,limit,hev)

type Filter is Data: Filter{level: U32,interior: U32,hev: U32,simple: Bool,inner: Bool}

def filterParameters(meta: Macroblock,parametersValue: Parameters) -> Filter:
  match meta parametersValue:
    case Macroblock{segmentId,skip,+luma,_,_} Parameters{Features{enabled,_,absolute,_,levels,_},simple,+base,+sharpness,Row{referenceDelta,modeDelta,_,_},_,_,_,_}:
      +adjustment = tableAt(levels,segmentId)
      +level = clampPositive((Bool.pick(U32,enabled,Bool.pick(U32,absolute,adjustment,(base + adjustment : U32)),base) + referenceDelta + Bool.pick(U32,U32.is_eq(luma,4),modeDelta,0) : U32),63)
      shifted = U32.shrn(level,Bool.pick(Nat,U32.is_gt(sharpness,4),2n,1n))
      interior = U32.max(1,Bool.pick(U32,U32.is_eq(sharpness,0),level,U32.min(shifted,(9 - sharpness : U32))))
      Filter{level,interior,Bool.pick(U32,U32.is_ge(level,40),2,Bool.pick(U32,U32.is_ge(level,15),1,0)),simple,U32.is_eq(luma,4) || Bool.not(skip)}

def filterInner(fuel: Nat,+offset: U32,+length: U32,+count: U32,+position: U32,+step: U32,+stride: U32,+settings: Filter) -> Pixels(Unit):
  match fuel settings:
    case 0n _: Pixels.pure(Unit,Unit{})
    case 1n+n Filter{level,+interior,hev,+simple,_}:
      Bool.pick(Unit -> Pixels(Unit),U32.is_lt((offset + Bool.pick(U32,simple,1,3) : U32),length),
        _ => do Pixels<Unit>:
          filterLine(U32.to_nat(count),(position + offset * stride : U32),step,stride,simple,False{},interior,(level * 2 + interior : U32),hev)
          filterInner(n,(offset + 4 : U32),length,count,position,step,stride,settings),_ => Pixels.pure(Unit,Unit{}))(Unit{})

def filterDirection(+length: U32,+count: U32,+position: U32,+step: U32,+stride: U32,hasOuter: Bool,+settings: Filter) -> Pixels(Unit):
  match settings:
    case Filter{level,+interior,hev,+simple,inner}:
      do Pixels<Unit>:
        Bool.pick(Unit -> Pixels(Unit),hasOuter && U32.is_ge(length,Bool.pick(U32,simple,2,4)),
          _ => filterLine(U32.to_nat(count),position,step,stride,simple,True{},interior,((level + 2) * 2 + interior : U32),hev),_ => Pixels.pure(Unit,Unit{}))(Unit{})
        Bool.pick(Unit -> Pixels(Unit),inner,_ => filterInner(3n,4,length,count,position,step,stride,settings),_ => Pixels.pure(Unit,Unit{}))(Unit{})

def filterPlane(+plane: Plane,+mx: U32,+my: U32,+settings: Filter) -> Pixels(Unit):
  match plane settings:
    case Plane{_,+stride,width,height,+size} Filter{level,_,_,simple,_}:
      +w = size
      +h = size
      +position = point(plane,mx,my)
      Bool.pick(Unit -> Pixels(Unit),U32.is_gt(level,0) && (U32.is_eq(size,16) || Bool.not(simple)),
        _ => do Pixels<Unit>:
          filterDirection(w,h,position,stride,1,U32.is_gt(mx,0),settings)
          filterDirection(h,w,position,1,stride,U32.is_gt(my,0),settings),_ => Pixels.pure(Unit,Unit{}))(Unit{})

def Parsed(-A: Data) -> Data: Result<&2,&2,Error,A>
def Parsed.pure(-A: Data,value: A) -> Parsed(A): Done{value}
def Parsed.bind(-A: Data,-B: Data,value: Parsed(A),next: A -> Parsed(B)) -> Parsed(B):
  match value:
    case Fail{cause}: Fail{cause}
    case Done{result}: next(result)

type Slice is Data: Slice{bytes: List<&2,U32>,rest: List<&2,U32>}

def take(count: Nat,bytes: List<&2,U32>,reversed: List<&2,U32>) -> Parsed(Slice):
  match count bytes:
    case 0n rest: Done{Slice{List.reverse(&2,U32,reversed),rest}}
    case 1n+n byte <> rest: take(n,rest,byte <> reversed)
    case _ Nil{}: Fail{Truncated{}}

def reader(bytes: List<&2,U32>) -> Parsed(Reader):
  match bytes:
    case a <> b <> rest: Done{Reader{rest,255,(a * 256 + b : U32),0,0}}
    case a <> Nil{}: Done{Reader{Nil{},255,(a * 256 : U32),0,1}}
    case _: Fail{Partition{}}

def remainingBytes(value: Slice) -> List<&2,U32>:
  match value:
    case Slice{_,rest}: rest

def sliceBytes(value: Slice) -> List<&2,U32>:
  match value:
    case Slice{bytes,_}: bytes

def u24(a: U32,b: U32,c: U32) -> U32: (a + b * 256 + c * 65536 : U32)

def partitionReaders(sizes: List<&2,U32>,bytes: List<&2,U32>,reversed: List<&2,Reader>) -> Parsed(List<&2,Reader>):
  match sizes:
    case Nil{}:
      do Parsed<List<&2,Reader>>:
        last : Reader <- reader(bytes)
        Done{List.reverse(&2,Reader,last <> reversed)}
    case a <> b <> c <> rest:
      do Parsed<List<&2,Reader>>:
        +part : Slice <- take(U32.to_nat(u24(a,b,c)),bytes,Nil{})
        value : Reader <- reader(sliceBytes(part))
        partitionReaders(rest,remainingBytes(part),value <> reversed)
    case _: Fail{Partition{}}

def partitions(count: U32,bytes: List<&2,U32>) -> Parsed(List<&2,Reader>):
  do Parsed<List<&2,Reader>>:
    +sizes : Slice <- take(U32.to_nat((count * 3 - 3 : U32)),bytes,Nil{})
    partitionReaders(sliceBytes(sizes),remainingBytes(sizes),Nil{})

type Header is Data:
  Header{width: U32,height: U32,parameters: Parameters,reader: Reader,partitions: List<&2,Reader>}

def partitionCount(values: Parameters) -> U32:
  match values:
    case Parameters{_,_,_,_,_,count,_,_,_}: count

def assembledHeader(width: U32,height: U32,bytes: List<&2,U32>,pair: Reader & Parameters) -> Parsed(Header):
  match pair:
    case (+headerReader,+values):
      Bool.pick(Unit -> Parsed(Header),readerValid(headerReader),
        _ => do Parsed<Header>:
          tokens : List<&2,Reader> <- partitions(partitionCount(values),bytes)
          Done{Header{width,height,values,headerReader,tokens}},_ => Fail{Truncated{}})(Unit{})

def headerBits(width: U32,height: U32,bytes: List<&2,U32>,pair: Reader & U32) -> Parsed(Header):
  match pair:
    case (headerReader,colorSpace):
      Bool.pick(Unit -> Parsed(Header),U32.is_eq(colorSpace,0),_ => assembledHeader(width,height,bytes,parameters()(headerReader)),_ => Fail{ColorSpace{}})(Unit{})

def colorSpace() -> Read(U32):
  do Read<U32>:
    color : U32 <- bit(128)
    _ : U32 <- bit(128)
    Read.pure(U32,color)

def rawFrameHeader(bytes: List<&2,U32>,pixelLimit: Nat) -> Parsed(Header):
  match bytes:
    case +a <> b <> c <> 157 <> 1 <> 42 <> w0 <> w1 <> h0 <> h1 <> rest:
      +width = U32.and((w0 + w1 * 256 : U32),16383)
      +height = U32.and((h0 + h1 * 256 : U32),16383)
      Bool.pick(Unit -> Parsed(Header),U32.is_eq(U32.and(a,1),0),
        _ => Bool.pick(Unit -> Parsed(Header),U32.is_gt(width,0) && U32.is_gt(height,0),
          _ => Bool.pick(Unit -> Parsed(Header),Nat.is_le(U32.to_nat(width) * U32.to_nat(height),pixelLimit),
            _ => do Parsed<Header>:
              +part : Slice <- take(U32.to_nat(U32.shrn(u24(a,b,c),5n)),rest,Nil{})
              arithmetic : Reader <- reader(sliceBytes(part))
              headerBits(width,height,remainingBytes(part),colorSpace()(arithmetic)),_ => Fail{PixelLimit{}})(Unit{}),_ => Fail{Dimensions{}})(Unit{}),_ => Fail{Interframe{}})(Unit{})
    case a <> _:
      Bool.pick(Parsed(Header),U32.is_eq(U32.and(a,1),1),Fail{Interframe{}},Fail{Signature{}})
    case _: Fail{Truncated{}}

def frameHeader(bytes: List<&2,U32>,pixelLimit: Nat) -> Parsed(Header):
  match bytes:
    case +first <> rest:
      Bool.pick(Unit -> Parsed(Header),U32.is_le(U32.and(U32.shrn(first,1n),7),3),
        _ => Bool.pick(Unit -> Parsed(Header),U32.is_eq(U32.and(first,16),16),_ => rawFrameHeader(first <> rest,pixelLimit),_ => Fail{HiddenFrame{}})(Unit{}),_ => Fail{UnsupportedVersion{}})(Unit{})
    case _: Fail{Truncated{}}

type Planes is Data: Planes{y: Plane,u: Plane,v: Plane}

def planes(+width: U32,+height: U32) -> Planes:
  +stride = ((width + 15) / 16 * 16 : U32)
  +rows = ((height + 15) / 16 * 16 : U32)
  +count = (stride * rows : U32)
  Planes{Plane{0,stride,width,height,16},Plane{count,(stride / 2 : U32),((width + 1) / 2 : U32),((height + 1) / 2 : U32),8},Plane{(count + count / 4 : U32),(stride / 2 : U32),((width + 1) / 2 : U32),((height + 1) / 2 : U32),8}}

def reconstruct(meta: Macroblock,+blocks: List<&2,Block>,layout: Planes,+mx: U32,+my: U32) -> Pixels(Unit):
  match meta layout:
    case Macroblock{_,_,+luma,+chroma,modes} Planes{+y,+u,+v}:
      +lumaBlocks = List.take(&2,Block,blocks,16n)
      do Pixels<Unit>:
        Bool.pick(Unit -> Pixels(Unit),U32.is_eq(luma,4),_ => predictedBlocks(lumaBlocks,0,y,mx,my,modes),
          _ => do Pixels<Unit>:
            predictPlane(y,mx,my,luma)
            addBlocks(lumaBlocks,0,y,mx,my,4))(Unit{})
        predictPlane(u,(mx / 2 : U32),(my / 2 : U32),chroma)
        addBlocks(List.take(&2,Block,List.drop(&2,Block,blocks,16n),4n),0,u,(mx / 2 : U32),(my / 2 : U32),2)
        predictPlane(v,(mx / 2 : U32),(my / 2 : U32),chroma)
        addBlocks(List.drop(&2,Block,blocks,20n),0,v,(mx / 2 : U32),(my / 2 : U32),2)

type Context is Data: Context{modes: Block,nonzero: Block}
type RowState is Data:
  RowState{header: Reader,tokens: Reader,above: List<&2,Context>,nextAbove: List<&2,Context>,leftModes: Row,leftNonzero: Block,metadata: List<&2,Macroblock>}
type Tile is Data: Tile{state: RowState,metadata: Macroblock,blocks: List<&2,Block>}

def assembledTile(header: Reader,above: List<&2,Context>,nextAbove: List<&2,Context>,metadata: List<&2,Macroblock>,+meta: Macroblock,pair: Reader & Residuals) -> Tile:
  match meta pair:
    case Macroblock{_,_,_,_,+modes} result:
      match result:
        case (tokens,Residuals{blocks,top,left}):
          Tile{RowState{header,tokens,above,Context{modes,top} <> nextAbove,rightModes(modes),left,meta <> metadata},meta,blocks}

def segmentId(meta: Macroblock) -> U32:
  match meta:
    case Macroblock{value,_,_,_,_}: value

def tileResidual(above: List<&2,Context>,nextAbove: List<&2,Context>,metadata: List<&2,Macroblock>,tokens: Reader,top: Block,left: Block,values: Parameters,dc: Table,ac: Table,pair: Reader & Macroblock) -> Tile:
  match values pair:
    case Parameters{featuresValue,_,_,_,_,_,quants,probabilities,_} result:
      match result:
        case (header,+meta):
          assembledTile(header,above,nextAbove,metadata,meta,residuals(meta,probabilities,quantizer(segmentId(meta),featuresValue,quants,dc,ac),top,left)(tokens))

def tile(+parametersValue: Parameters,probabilities: Table,dc: Table,ac: Table,state: RowState) -> Tile:
  match parametersValue state:
    case Parameters{featuresValue,_,_,_,_,_,_,_,skip} RowState{header,tokens,Context{aboveModes,top} <> above,nextAbove,leftModes,leftNonzero,metadata}:
      tileResidual(above,nextAbove,metadata,tokens,top,leftNonzero,parametersValue,dc,ac,macroblock(featuresValue,skip,aboveModes,leftModes,probabilities)(header))
    case _ RowState{header,tokens,Nil{},nextAbove,leftModes,leftNonzero,metadata}:
      Tile{RowState{header,tokens,Nil{},nextAbove,leftModes,leftNonzero,metadata},Macroblock{0,True{},0,0,zeroBlock()},emptyBlocks(24n)}

def rowValid(state: RowState) -> Bool:
  match state:
    case RowState{header,tokens,_,_,_,_,_}: readerValid(header) && readerValid(tokens)

def drawTile(layout: Planes,mx: U32,my: U32,value: Tile) -> Pixels(RowState):
  match value:
    case Tile{+state,metadata,blocks}:
      Bool.pick(Unit -> Pixels(RowState),rowValid(state),
        _ => do Pixels<RowState>:
          reconstruct(metadata,blocks,layout,mx,my)
          Pixels.pure(RowState,state),_ => Pixels.pure(RowState,state))(Unit{})

def row(fuel: Nat,+mx: U32,+my: U32,+layout: Planes,+parametersValue: Parameters,+probabilities: Table,+dc: Table,+ac: Table,state: RowState) -> Pixels(RowState):
  match fuel:
    case 0n: Pixels.pure(RowState,state)
    case 1n+n:
      do Pixels<RowState>:
        +next : RowState <- drawTile(layout,mx,my,tile(parametersValue,probabilities,dc,ac,state))
        Bool.pick(Unit -> Pixels(RowState),rowValid(next),_ => row(n,(mx + 16 : U32),my,layout,parametersValue,probabilities,dc,ac,next),_ => Pixels.pure(RowState,next))(Unit{})

type FrameState is Data:
  FrameState{header: Reader,partitions: List<&2,Reader>,retired: List<&2,Reader>,above: List<&2,Context>,metadata: List<&2,Macroblock>}

def finishedRow(partitions: List<&2,Reader>,retired: List<&2,Reader>,value: RowState) -> FrameState:
  match value:
    case RowState{header,tokens,_,above,_,_,metadata}: FrameState{header,partitions,tokens <> retired,List.reverse(&2,Context,above),metadata}

def rowPartition(+columns: Nat,my: U32,layout: Planes,parametersValue: Parameters,probabilities: Table,dc: Table,ac: Table,state: FrameState) -> Pixels(FrameState):
  match state:
    case FrameState{header,tokenReader <> rest,retired,above,metadata}:
      do Pixels<FrameState>:
        result : RowState <- row(columns,0,my,layout,parametersValue,probabilities,dc,ac,RowState{header,tokenReader,above,Nil{},zeroRow(),zeroBlock(),metadata})
        Pixels.pure(FrameState,finishedRow(rest,retired,result))
    case value: Pixels.pure(FrameState,value)

def cyclePartitions(state: FrameState) -> FrameState:
  match state:
    case FrameState{header,Nil{},retired,above,metadata}: FrameState{header,List.reverse(&2,Reader,retired),Nil{},above,metadata}
    case value: value

def readersValid(readers: List<&2,Reader>) -> Bool:
  match readers:
    case Nil{}: True{}
    case head <> rest: Bool.pick(Unit -> Bool,readerValid(head),_ => readersValid(rest),_ => False{})(Unit{})

def frameValid(state: FrameState) -> Bool:
  match state:
    case FrameState{header,partitionsValue,retired,_,_}: readerValid(header) && readersValid(partitionsValue) && readersValid(retired)

def rows(fuel: Nat,+columns: Nat,+my: U32,+layout: Planes,+parametersValue: Parameters,+probabilities: Table,+dc: Table,+ac: Table,state: FrameState) -> Pixels(FrameState):
  match fuel:
    case 0n: Pixels.pure(FrameState,state)
    case 1n+n:
      do Pixels<FrameState>:
        +result : FrameState <- rowPartition(columns,my,layout,parametersValue,probabilities,dc,ac,cyclePartitions(state))
        Bool.pick(Unit -> Pixels(FrameState),frameValid(result),_ => rows(n,columns,(my + 16 : U32),layout,parametersValue,probabilities,dc,ac,result),_ => Pixels.pure(FrameState,result))(Unit{})

def contexts(count: Nat) -> List<&2,Context>:
  match count:
    case 0n: Nil{}
    case 1n+n: Context{zeroBlock(),zeroBlock()} <> contexts(n)

def filterTile(layout: Planes,+mx: U32,+my: U32,+settings: Filter) -> Pixels(Unit):
  match layout:
    case Planes{y,u,v}:
      do Pixels<Unit>:
        filterPlane(y,mx,my,settings)
        filterPlane(u,(mx / 2 : U32),(my / 2 : U32),settings)
        filterPlane(v,(mx / 2 : U32),(my / 2 : U32),settings)

def filterFrame(metadata: List<&2,Macroblock>,+index: U32,+columns: U32,+layout: Planes,+parametersValue: Parameters) -> Pixels(Unit):
  match metadata:
    case Nil{}: Pixels.pure(Unit,Unit{})
    case meta <> rest:
      do Pixels<Unit>:
        filterTile(layout,(index % columns * 16 : U32),(index / columns * 16 : U32),filterParameters(meta,parametersValue))
        filterFrame(rest,(index + 1 : U32),columns,layout,parametersValue)

def metadata(state: FrameState) -> List<&2,Macroblock>:
  match state:
    case FrameState{_,_,_,_,values}: List.reverse(&2,Macroblock,values)

def rgba(y: U32,u: U32,v: U32) -> U32:
  +c = (y - 16 : U32)
  +d = (u - 128 : U32)
  +e = (v - 128 : U32)
  r = clampPositive(arithmeticShift((298 * c + 409 * e + 128 : U32),8n),255)
  g = clampPositive(arithmeticShift((298 * c - 100 * d - 208 * e + 128 : U32),8n),255)
  b = clampPositive(arithmeticShift((298 * c + 516 * d + 128 : U32),8n),255)
  (r * 16777216 + g * 65536 + b * 256 + 255 : U32)

def packPixels(fuel: Nat,+index: U32,+width: U32,+layout: Planes) -> Pixels(Unit):
  match fuel layout:
    case 0n _: Pixels.pure(Unit,Unit{})
    case 1n+n Planes{y,u,v}:
      +x = (index % width : U32)
      +rowIndex = (index / width : U32)
      do Pixels<Unit>:
        yValue : U32 <- get(point(y,x,rowIndex))
        uValue : U32 <- get(point(u,(x / 2 : U32),(rowIndex / 2 : U32)))
        vValue : U32 <- get(point(v,(x / 2 : U32),(rowIndex / 2 : U32)))
        put(index,rgba(yValue,uValue,vValue))
        packPixels(n,(index + 1 : U32),width,layout)

def reconstructFrame(+width: U32,+height: U32,+parametersValue: Parameters,headerReader: Reader,partitionsValue: List<&2,Reader>) -> Pixels(Bool):
  +layout = planes(width,height)
  +columns = ((width + 15) / 16 : U32)
  do Pixels<Bool>:
    +state : FrameState <- rows(U32.to_nat(((height + 15) / 16 : U32)),U32.to_nat(columns),0,layout,parametersValue,table(10n,intraProbabilities()),table(7n,dcQuantizers()),table(7n,acQuantizers()),FrameState{headerReader,partitionsValue,Nil{},contexts(U32.to_nat(columns)),Nil{}})
    Bool.pick(Unit -> Pixels(Bool),frameValid(state),
      _ => do Pixels<Bool>:
        filterFrame(metadata(state),0,columns,layout,parametersValue)
        packPixels(U32.to_nat(width) * U32.to_nat(height),0,width,layout)
        Pixels.pure(Bool,True{}),_ => Pixels.pure(Bool,False{}))(Unit{})

def raster(width: U32,height: U32,pair: Array<U32> & Bool) -> Result<&2,&1,Error,Image.Raster>:
  match pair:
    case (pixels,valid): Bool.pick(Array<U32> -> Result<&2,&1,Error,Image.Raster>,valid,buffer => Done{Image.Raster{width,height,buffer}},_ => Fail{Truncated{}})(pixels)

def decoded(headerValue: Parsed(Header)) -> Result<&2,&1,Error,Image.Raster>:
  match headerValue:
    case Fail{cause}: Fail{cause}
    case Done{Header{+width,+height,parametersValue,headerReader,partitionsValue}}:
      count = (((width + 15) / 16) * ((height + 15) / 16) * 384 : U32)
      raster(width,height,reconstructFrame(width,height,parametersValue,headerReader,partitionsValue)(Array.new(U32,Image.depth(31n,count,1,0n),0)))

def validBytes(bytes: List<&2,U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case byte <> rest: Bool.pick(Unit -> Bool,U32.is_le(byte,255),_ => validBytes(rest),_ => False{})(Unit{})

def decode(+payload: List<&2,U32>,pixelLimit: Nat) -> Result<&2,&1,Error,Image.Raster>:
  Bool.pick(Unit -> Result<&2,&1,Error,Image.Raster>,validBytes(payload),_ => decoded(frameHeader(payload,pixelLimit)),_ => Fail{InvalidByte{}})(Unit{})
