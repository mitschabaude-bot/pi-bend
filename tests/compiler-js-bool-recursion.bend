import Base

# Reduced JS stack cliff: the recursive result is an argument to Bool.and.
def grow(count: Nat, text: String) -> String:
  match count:
    case Zero{}: text
    case Succ{rest}: grow(rest, SCon{'9', text})

def allDigits(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}: U32.is_ge(code, 48) && U32.is_le(code, 57) && allDigits(rest)

def main() -> IO(Unit):
  IO.print(Bool.pick(String, allDigits(grow(65536n, "")), "digits", "not-digits"))
