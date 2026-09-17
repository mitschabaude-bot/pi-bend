import Base
import ../src/native.bend as Native

def main() -> IO(Unit):
  do IO<Unit>:
    cwd : String <- Native.cwd()
    IO.print(cwd)
    h : String <- IO.try(String, Native.spawn("printf 'native process works'", "/tmp", 1000n))
    out : String <- IO.try(String, Native.next(h))
    IO.print(out)
