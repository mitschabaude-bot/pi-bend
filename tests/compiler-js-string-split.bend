import Base

def grow(count: Nat, text: String) -> String:
  match count:
    case Zero{}: text
    case Succ{rest}: grow(rest, SCon{'x', text})

def check(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case _ <> Nil{}: IO.print("split")
    case _: IO.die(Unit, 1, "incorrect split")

def main() -> IO(Unit): check(String.split(grow(65536n, ""), ','))
