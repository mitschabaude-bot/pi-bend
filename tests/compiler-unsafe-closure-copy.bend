import Base

@unsafe def twice(+f: U32 -> U32, +x: U32) -> U32:
  (f(x) + f(x) : U32)

def captured(n: U32) -> U32:
  twice(x => (x + n : U32), 1)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    IO.print(U32.show(captured(U32.from_nat(List.length(&1, String, args)))))
