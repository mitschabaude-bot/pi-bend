import Base

type Error is Data:
  Error{code: U32, message: String}

def normalized(result: Result<&1, &1, U32 & String, U32>) -> Result<&2, &2, Error, U32>:
  match result:
    case Fail{(code, message)}: Fail{Error{code, message}}
    case Done{index}: Done{index}

def index(name: String) -> IO(Result<&2, &2, Error, U32>):
  do IO<Result<&2, &2, Error, U32>>:
    result : Result<&1, &1, U32 & String, U32> <- IO.interface_index(name)
    return normalized(result)

def lookup(unused: Unit, name: String) -> IO(Result<&2, &2, Error, U32>):
  index(name)
