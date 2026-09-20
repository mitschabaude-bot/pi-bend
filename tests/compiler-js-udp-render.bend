import Base

def csv(bytes: List<&2, U32>) -> String:
  match bytes:
    case Nil{}: ""
    case byte <> rest: U32.show(byte) ++ "," ++ csv(rest)

def bytes(size: Nat, result: List<&2, U32>) -> List<&2, U32>:
  match size:
    case Zero{}: result
    case Succ{rest}: bytes(rest, 255 <> result)

def main() -> IO(Unit):
  IO.print(csv(bytes(65283n, Nil{})))
