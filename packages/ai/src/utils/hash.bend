import Base

# Pi's deterministic ID hash. Arithmetic intentionally wraps at 32 bits;
# supplementary scalars feed the same two UTF-16 units as provider transcripts.
type State is Data:
  State{first: U32, second: U32}

def unit(state: State, +code: U32) -> State:
  match state:
    case State{first, second}: State{(U32.xor(first, code) * 2654435761 : U32), (U32.xor(second, code) * 1597334677 : U32)}

def character(supplementary: Bool, state: State, +code: U32) -> State:
  match supplementary:
    case False{}: unit(state, code)
    case True{}: unit(unit(state, (55296 + (code - 65536) / 1024 : U32)), (56320 + (code - 65536) % 1024 : U32))

def consume(text: String, state: State) -> State:
  match text:
    case SNil{}: state
    case SCon{Chr{+code}, rest}: consume(rest, character(U32.is_gt(code, 65535), state, code))

def digit(+value: U32) -> Char:
  Chr{Bool.pick(U32, U32.is_lt(value, 10), (48 + value : U32), (87 + value : U32))}

def digits(fuel: Nat, +value: U32, result: String) -> String:
  match fuel value:
    case _ 0: result
    case 0n _: result
    case 1n+n current: digits(n, (current / 36 : U32), SCon{digit((current % 36 : U32)), result})

def base36(value: U32) -> String:
  match value:
    case 0: "0"
    case other: digits(7n, other, "")

def finish(state: State) -> String:
  match state:
    case State{+first, +second}:
      +mixedFirst = U32.xor((U32.xor(first, U32.shrn(first, 16n)) * 2246822507 : U32), (U32.xor(second, U32.shrn(second, 13n)) * 3266489909 : U32))
      mixedSecond = U32.xor((U32.xor(second, U32.shrn(second, 16n)) * 2246822507 : U32), (U32.xor(mixedFirst, U32.shrn(mixedFirst, 13n)) * 3266489909 : U32))
      base36(mixedSecond) ++ base36(mixedFirst)

def shortHash(text: String) -> String:
  finish(consume(text, State{3735928559, 1103547991}))
