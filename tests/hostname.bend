import Base

def report(value: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match value:
    case Fail{(code, _)}: IO.print("error:" ++ U32.show(code))
    case Done{name}: IO.print("name:" ++ name)

def repeat(count: Nat) -> IO(Unit):
  match count:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+rest:
      do IO<Unit>:
        value : Result<&1, &1, U32 & String, String> <- IO.get_hostname()
        report(value)
        repeat(rest)

def main() -> IO(Unit):
  repeat(3n)
