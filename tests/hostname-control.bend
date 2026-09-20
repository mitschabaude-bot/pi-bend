import Base

def report(value: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match value:
    case Fail{(code, _)}: IO.print(U32.show(code))
    case Done{text}: IO.print(text)

def main() -> IO(Unit):
  do IO<Unit>:
    value : Result<&1, &1, U32 & String, String> <- IO.get_env("PI_BEND_HOSTNAME_CONTROL")
    report(value)
