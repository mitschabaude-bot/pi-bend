import Base
import ./u64.bend as W
import ./random.bend as Random

# Linux entropy boundary using existing native binary-file primitives. Source
# failures remain typed; never substitute timestamps or a fixed fallback seed.
type SeedError is Data:
  SourceFailure{code: U32, message: String}
  ShortSeed{bytes: Nat}

def sourceFailure(error: U32 & String) -> SeedError:
  match error:
    case Tuple{code, message}: SourceFailure{code, message}

def word(a: U32, b: U32, c: U32, d: U32) -> U32:
  U32.or(U32.shln(a, 24n), U32.or(U32.shln(b, 16n), U32.or(U32.shln(c, 8n), d)))

def decode(+bytes: List<&2, U32>) -> Result<&2, &2, SeedError, W.U64>:
  match bytes:
    case a <> b <> c <> d <> e <> f <> g <> h <> Nil{}: Done{W.U64{word(a, b, c, d), word(e, f, g, h)}}
    case _: Fail{ShortSeed{List.length(&2, U32, bytes)}}

def decoded(result: Result<&1, &1, U32 & String, List<&2, U32>>) -> Result<&2, &2, SeedError, W.U64>:
  match result:
    case Fail{error}: Fail{sourceFailure(error)}
    case Done{bytes}: decode(bytes)

def closeRead(pair: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Result<&2, &2, SeedError, W.U64>):
  match pair:
    case Tuple{file, result}:
      do IO<Result<&2, &2, SeedError, W.U64>>:
        File.close(file)
        return decoded(result)

def readOpened(result: Result<&1, &1, U32 & String, File>) -> IO(Result<&2, &2, SeedError, W.U64>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, SeedError, W.U64>, Fail{sourceFailure(error)})
    case Done{file}:
      do IO<Result<&2, &2, SeedError, W.U64>>:
        bytes : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 8)
        closeRead(bytes)

# The source path is injectable for deterministic success/error tests. A short
# read is an explicit initialization failure, never a partially padded seed.
def read(path: String) -> IO(Result<&2, &2, SeedError, W.U64>):
  do IO<Result<&2, &2, SeedError, W.U64>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    readOpened(opened)

def initialize(result: Result<&2, &2, SeedError, W.U64>) -> IO(Result<&2, &2, SeedError, Random.Generator>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, SeedError, Random.Generator>, Fail{error})
    case Done{seed}:
      do IO<Result<&2, &2, SeedError, Random.Generator>>:
        generator : Random.Generator <- Random.seeded(seed)
        return Done{generator}

def new() -> IO(Result<&2, &2, SeedError, Random.Generator>):
  do IO<Result<&2, &2, SeedError, Random.Generator>>:
    seed : Result<&2, &2, SeedError, W.U64> <- read("/dev/urandom")
    initialize(seed)
