import Base

def split(value: U32) -> U32:
  match value:
    case 0: 0
    case +word: (word / 16 + word % 16 : U32)

def main() -> IO(Unit): IO.print(U32.show(split(31)))
