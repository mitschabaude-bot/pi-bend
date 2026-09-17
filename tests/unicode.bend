import Base
import ../src/native.bend as N

def main() -> IO(Unit):
  do IO<Unit>:
    text : String <- N.arg(1n)
    result : String <- N.segments(text)
    IO.print(result)
    result : String <- N.words("hello, 世界!")
    IO.print(result)
