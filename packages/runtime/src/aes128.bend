import Base

# AES-128 encryption, FIPS 197. GCM uses the forward cipher for both directions.
# Blocks are four big-endian words. The cipher is bitsliced after BearSSL's
# aes_ct: two blocks become eight 32-bit bit planes, the S-box is a Boolean
# circuit, and ShiftRows/MixColumns are shifts and rotations of whole planes.
# No table lookup or branch depends on a key or data value.
type Block is Data:
  Block{a: U32, b: U32, c: U32, d: U32}

# Bit plane i holds bit i of every byte of two blocks.
type Slice is Data:
  Slice{q0: U32, q1: U32, q2: U32, q3: U32, q4: U32, q5: U32, q6: U32, q7: U32}

type Pair is Data:
  Pair{first: Block, second: Block}

type ExpandedKey is Data:
  ExpandedKey{initial: Slice, rounds: List<&2, Slice>}

def xtime(+x: U32) -> U32:
  U32.xor(U32.and(U32.shln(x, 1n), 255), U32.and((0 - U32.shrn(x, 7n) : U32), 27))

def pack(a: U32, b: U32, c: U32, d: U32) -> U32:
  (a * 16777216 + b * 65536 + c * 256 + d : U32)

def byte(word: U32, shift: Nat) -> U32: U32.and(U32.shrn(word, shift), 255)

# Big-endian words become the little-endian words of the bitsliced layout.
def swapBytes(+x: U32) -> U32:
  U32.or(U32.or(U32.shln(x, 24n), U32.shln(U32.and(x, 65280), 8n)), U32.or(U32.and(U32.shrn(x, 8n), 65280), U32.shrn(x, 24n)))

# Boyar and Peralta's 113-gate circuit (https://eprint.iacr.org/2009/191),
# as ordered in BearSSL's aes_ct. Input x0 is the most significant bit plane.
def sbox(state: Slice) -> Slice:
  match state:
    case Slice{+x7, +x6, +x5, x4, +x3, x2, +x1, +x0}:
      +y14 = U32.xor(x3, x5)
      +y13 = U32.xor(x0, x6)
      +y9 = U32.xor(x0, x3)
      +y8 = U32.xor(x0, x5)
      +t0 = U32.xor(x1, x2)
      +y1 = U32.xor(t0, x7)
      +y4 = U32.xor(y1, x3)
      +y12 = U32.xor(y13, y14)
      +y2 = U32.xor(y1, x0)
      +y5 = U32.xor(y1, x6)
      +y3 = U32.xor(y5, y8)
      +t1 = U32.xor(x4, y12)
      +y15 = U32.xor(t1, x5)
      +y20 = U32.xor(t1, x1)
      +y6 = U32.xor(y15, x7)
      +y10 = U32.xor(y15, t0)
      +y11 = U32.xor(y20, y9)
      +y7 = U32.xor(x7, y11)
      +y17 = U32.xor(y10, y11)
      y19 = U32.xor(y10, y8)
      +y16 = U32.xor(t0, y11)
      y21 = U32.xor(y13, y16)
      y18 = U32.xor(x0, y16)
      +t2 = U32.and(y12, y15)
      t3 = U32.and(y3, y6)
      t4 = U32.xor(t3, t2)
      t5 = U32.and(y4, x7)
      t6 = U32.xor(t5, t2)
      +t7 = U32.and(y13, y16)
      t8 = U32.and(y5, y1)
      t9 = U32.xor(t8, t7)
      t10 = U32.and(y2, y7)
      t11 = U32.xor(t10, t7)
      +t12 = U32.and(y9, y11)
      t13 = U32.and(y14, y17)
      +t14 = U32.xor(t13, t12)
      t15 = U32.and(y8, y10)
      +t16 = U32.xor(t15, t12)
      t17 = U32.xor(t4, t14)
      t18 = U32.xor(t6, t16)
      t19 = U32.xor(t9, t14)
      t20 = U32.xor(t11, t16)
      +t21 = U32.xor(t17, y20)
      +t22 = U32.xor(t18, y19)
      +t23 = U32.xor(t19, y21)
      +t24 = U32.xor(t20, y18)
      +t25 = U32.xor(t21, t22)
      +t26 = U32.and(t21, t23)
      +t27 = U32.xor(t24, t26)
      t28 = U32.and(t25, t27)
      +t29 = U32.xor(t28, t22)
      t30 = U32.xor(t23, t24)
      t31 = U32.xor(t22, t26)
      t32 = U32.and(t31, t30)
      +t33 = U32.xor(t32, t24)
      t34 = U32.xor(t23, t33)
      t35 = U32.xor(t27, t33)
      +t36 = U32.and(t24, t35)
      +t37 = U32.xor(t36, t34)
      t38 = U32.xor(t27, t36)
      t39 = U32.and(t29, t38)
      +t40 = U32.xor(t25, t39)
      +t41 = U32.xor(t40, t37)
      +t42 = U32.xor(t29, t33)
      +t43 = U32.xor(t29, t40)
      +t44 = U32.xor(t33, t37)
      +t45 = U32.xor(t42, t41)
      z0 = U32.and(t44, y15)
      z1 = U32.and(t37, y6)
      +z2 = U32.and(t33, x7)
      +z3 = U32.and(t43, y16)
      +z4 = U32.and(t40, y1)
      +z5 = U32.and(t29, y7)
      z6 = U32.and(t42, y11)
      +z7 = U32.and(t45, y17)
      z8 = U32.and(t41, y10)
      z9 = U32.and(t44, y12)
      +z10 = U32.and(t37, y3)
      z11 = U32.and(t33, y4)
      +z12 = U32.and(t43, y13)
      z13 = U32.and(t40, y5)
      z14 = U32.and(t29, y2)
      z15 = U32.and(t42, y9)
      +z16 = U32.and(t45, y14)
      z17 = U32.and(t41, y8)
      +t46 = U32.xor(z15, z16)
      t47 = U32.xor(z10, z11)
      +t48 = U32.xor(z5, z13)
      t49 = U32.xor(z9, z10)
      t50 = U32.xor(z2, z12)
      t51 = U32.xor(z2, z5)
      t52 = U32.xor(z7, z8)
      +t53 = U32.xor(z0, z3)
      t54 = U32.xor(z6, z7)
      t55 = U32.xor(z16, z17)
      t56 = U32.xor(z12, t48)
      +t57 = U32.xor(t50, t53)
      +t58 = U32.xor(z4, t46)
      +t59 = U32.xor(z3, t54)
      t60 = U32.xor(t46, t57)
      t61 = U32.xor(z14, t57)
      +t62 = U32.xor(t52, t58)
      +t63 = U32.xor(t49, t58)
      +t64 = U32.xor(z4, t59)
      +t65 = U32.xor(t61, t62)
      +t66 = U32.xor(z1, t63)
      s0 = U32.xor(t59, t63)
      s6 = U32.xor(t56, U32.not(t62))
      s7 = U32.xor(t48, U32.not(t60))
      t67 = U32.xor(t64, t65)
      +s3 = U32.xor(t53, t66)
      s4 = U32.xor(t51, t66)
      s5 = U32.xor(t47, t65)
      s1 = U32.xor(t64, U32.not(s3))
      s2 = U32.xor(t55, U32.not(t67))
      Slice{s7, s6, s5, s4, s3, s2, s1, s0}

# Transposes two blocks' eight words into eight bit planes, and back.
def ortho(state: Slice) -> Slice:
  match state:
    case Slice{+q0, +q1, +q2, +q3, +q4, +q5, +q6, +q7}:
      +a0 = U32.or(U32.and(q0, 1431655765), U32.shln(U32.and(q1, 1431655765), 1n))
      +a1 = U32.or(U32.shrn(U32.and(q0, 2863311530), 1n), U32.and(q1, 2863311530))
      +a2 = U32.or(U32.and(q2, 1431655765), U32.shln(U32.and(q3, 1431655765), 1n))
      +a3 = U32.or(U32.shrn(U32.and(q2, 2863311530), 1n), U32.and(q3, 2863311530))
      +a4 = U32.or(U32.and(q4, 1431655765), U32.shln(U32.and(q5, 1431655765), 1n))
      +a5 = U32.or(U32.shrn(U32.and(q4, 2863311530), 1n), U32.and(q5, 2863311530))
      +a6 = U32.or(U32.and(q6, 1431655765), U32.shln(U32.and(q7, 1431655765), 1n))
      +a7 = U32.or(U32.shrn(U32.and(q6, 2863311530), 1n), U32.and(q7, 2863311530))
      +b0 = U32.or(U32.and(a0, 858993459), U32.shln(U32.and(a2, 858993459), 2n))
      +b2 = U32.or(U32.shrn(U32.and(a0, 3435973836), 2n), U32.and(a2, 3435973836))
      +b1 = U32.or(U32.and(a1, 858993459), U32.shln(U32.and(a3, 858993459), 2n))
      +b3 = U32.or(U32.shrn(U32.and(a1, 3435973836), 2n), U32.and(a3, 3435973836))
      +b4 = U32.or(U32.and(a4, 858993459), U32.shln(U32.and(a6, 858993459), 2n))
      +b6 = U32.or(U32.shrn(U32.and(a4, 3435973836), 2n), U32.and(a6, 3435973836))
      +b5 = U32.or(U32.and(a5, 858993459), U32.shln(U32.and(a7, 858993459), 2n))
      +b7 = U32.or(U32.shrn(U32.and(a5, 3435973836), 2n), U32.and(a7, 3435973836))
      c0 = U32.or(U32.and(b0, 252645135), U32.shln(U32.and(b4, 252645135), 4n))
      c4 = U32.or(U32.shrn(U32.and(b0, 4042322160), 4n), U32.and(b4, 4042322160))
      c1 = U32.or(U32.and(b1, 252645135), U32.shln(U32.and(b5, 252645135), 4n))
      c5 = U32.or(U32.shrn(U32.and(b1, 4042322160), 4n), U32.and(b5, 4042322160))
      c2 = U32.or(U32.and(b2, 252645135), U32.shln(U32.and(b6, 252645135), 4n))
      c6 = U32.or(U32.shrn(U32.and(b2, 4042322160), 4n), U32.and(b6, 4042322160))
      c3 = U32.or(U32.and(b3, 252645135), U32.shln(U32.and(b7, 252645135), 4n))
      c7 = U32.or(U32.shrn(U32.and(b3, 4042322160), 4n), U32.and(b7, 4042322160))
      Slice{c0, c1, c2, c3, c4, c5, c6, c7}

def shiftWord(+x: U32) -> U32:
  U32.or(U32.or(U32.or(U32.and(x, 255), U32.shrn(U32.and(x, 64512), 2n)), U32.or(U32.shln(U32.and(x, 768), 6n), U32.shrn(U32.and(x, 15728640), 4n))), U32.or(U32.or(U32.shln(U32.and(x, 983040), 4n), U32.shrn(U32.and(x, 3221225472), 6n)), U32.shln(U32.and(x, 1056964608), 2n)))

def shiftRows(state: Slice) -> Slice:
  match state:
    case Slice{q0, q1, q2, q3, q4, q5, q6, q7}: Slice{shiftWord(q0), shiftWord(q1), shiftWord(q2), shiftWord(q3), shiftWord(q4), shiftWord(q5), shiftWord(q6), shiftWord(q7)}

def rotate8(+x: U32) -> U32: U32.or(U32.shrn(x, 8n), U32.shln(x, 24n))
def rotate16(+x: U32) -> U32: U32.or(U32.shln(x, 16n), U32.shrn(x, 16n))

def mixColumns(state: Slice) -> Slice:
  match state:
    case Slice{+q0, +q1, +q2, +q3, +q4, +q5, +q6, +q7}:
      +r0 = rotate8(q0)
      +r1 = rotate8(q1)
      +r2 = rotate8(q2)
      +r3 = rotate8(q3)
      +r4 = rotate8(q4)
      +r5 = rotate8(q5)
      +r6 = rotate8(q6)
      +r7 = rotate8(q7)
      +m7 = U32.xor(q7, r7)
      Slice{U32.xor(U32.xor(m7, r0), rotate16(U32.xor(q0, r0))), U32.xor(U32.xor(U32.xor(q0, r0), U32.xor(m7, r1)), rotate16(U32.xor(q1, r1))), U32.xor(U32.xor(U32.xor(q1, r1), r2), rotate16(U32.xor(q2, r2))), U32.xor(U32.xor(U32.xor(q2, r2), U32.xor(m7, r3)), rotate16(U32.xor(q3, r3))), U32.xor(U32.xor(U32.xor(q3, r3), U32.xor(m7, r4)), rotate16(U32.xor(q4, r4))), U32.xor(U32.xor(U32.xor(q4, r4), r5), rotate16(U32.xor(q5, r5))), U32.xor(U32.xor(U32.xor(q5, r5), r6), rotate16(U32.xor(q6, r6))), U32.xor(U32.xor(U32.xor(q6, r6), r7), rotate16(m7))}

def addKey(state: Slice, key: Slice) -> Slice:
  match state key:
    case Slice{q0, q1, q2, q3, q4, q5, q6, q7} Slice{k0, k1, k2, k3, k4, k5, k6, k7}: Slice{U32.xor(q0, k0), U32.xor(q1, k1), U32.xor(q2, k2), U32.xor(q3, k3), U32.xor(q4, k4), U32.xor(q5, k5), U32.xor(q6, k6), U32.xor(q7, k7)}

def load(first: Block, second: Block) -> Slice:
  match first second:
    case Block{a, b, c, d} Block{e, f, g, h}:
      ortho(Slice{swapBytes(a), swapBytes(e), swapBytes(b), swapBytes(f), swapBytes(c), swapBytes(g), swapBytes(d), swapBytes(h)})

def unload(state: Slice) -> Pair:
  match state:
    case Slice{q0, q1, q2, q3, q4, q5, q6, q7}:
      Pair{Block{swapBytes(q0), swapBytes(q2), swapBytes(q4), swapBytes(q6)}, Block{swapBytes(q1), swapBytes(q3), swapBytes(q5), swapBytes(q7)}}

def store(state: Slice) -> Pair: unload(ortho(state))

# The same round key for both blocks.
def roundKey(+key: Block) -> Slice: load(key, key)

# SubWord through the bitsliced S-box: bytes stay in place under ortho.
def substituted(state: Slice) -> U32:
  match state:
    case Slice{q0, _, _, _, _, _, _, _}: swapBytes(q0)

def subWord(word: U32) -> U32:
  substituted(ortho(sbox(ortho(Slice{swapBytes(word), 0, 0, 0, 0, 0, 0, 0}))))

def add(left: Block, right: Block) -> Block:
  match left right:
    case Block{a, b, c, d} Block{e, f, g, h}: Block{U32.xor(a, e), U32.xor(b, f), U32.xor(c, g), U32.xor(d, h)}

def nextKey(key: Block, constant: U32) -> Block:
  match key:
    case Block{a, b, c, +d}:
      rotated = U32.or(U32.shln(d, 8n), U32.shrn(d, 24n))
      +e = U32.xor(a, U32.xor(subWord(rotated), U32.shln(constant, 24n)))
      +f = U32.xor(b, e)
      +g = U32.xor(c, f)
      Block{e, f, g, U32.xor(d, g)}

# FIPS 197's round keys after the first, in block form.
def expandRounds(count: Nat, key: Block, +constant: U32) -> List<&2, Block>:
  match count:
    case 0n: Nil{}
    case 1n+rest:
      +next = nextKey(key, constant)
      next <> expandRounds(rest, next, xtime(constant))

def roundKeys(keys: List<&2, Block>) -> List<&2, Slice>:
  match keys:
    case Nil{}: Nil{}
    case key <> rest: roundKey(key) <> roundKeys(rest)

def expand(+key: Block) -> ExpandedKey: ExpandedKey{roundKey(key), roundKeys(expandRounds(10n, key, 1))}

def rounds(keys: List<&2, Slice>, state: Slice) -> Slice:
  match keys:
    case Nil{}: state
    case key <> Nil{}: addKey(shiftRows(sbox(state)), key)
    case key <> rest: rounds(rest, addKey(mixColumns(shiftRows(sbox(state))), key))

# Two blocks cost the same as one.
def encryptPair(key: ExpandedKey, first: Block, second: Block) -> Pair:
  match key:
    case ExpandedKey{initial, keys}: store(rounds(keys, addKey(load(first, second), initial)))

def firstBlock(pair: Pair) -> Block:
  match pair:
    case Pair{first, _}: first

def encrypt(key: ExpandedKey, +plaintext: Block) -> Block:
  firstBlock(encryptPair(key, plaintext, plaintext))

def valid(bytes: List<&2, U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case head <> rest: U32.is_le(head, 255) && valid(rest)

def parsed(valid: Bool, block: Block) -> Maybe<&2, Block>:
  match valid:
    case True{}: Some{block}
    case False{}: None{}

def fromBytes(+bytes: List<&2, U32>) -> Maybe<&2, Block>:
  match bytes:
    case a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> k <> l <> m <> n <> o <> p <> Nil{}:
      parsed(valid(bytes), Block{pack(a, b, c, d), pack(e, f, g, h), pack(i, j, k, l), pack(m, n, o, p)})
    case _: None{}

def wordBytes(+word: U32) -> List<&2, U32>:
  byte(word, 24n) <> byte(word, 16n) <> byte(word, 8n) <> byte(word, 0n) <> Nil{}

def toBytes(block: Block) -> List<&2, U32>:
  match block:
    case Block{a, b, c, d}: List.append(&2, U32, wordBytes(a), List.append(&2, U32, wordBytes(b), List.append(&2, U32, wordBytes(c), wordBytes(d))))
