import Base

# Literal representation must survive generic storage and captured functions.
type Box<-A: Data> is Data:
  Box{value: A}

def unbox(-A: Data, value: Box<A>) -> A:
  match value:
    case Box{item}: item

def apply(f: Unit -> String) -> String:
  f(Unit{})

def codes(text: String) -> String:
  match text:
    case SNil{}: "end"
    case SCon{Chr{code}, rest}: U32.show(code) ++ ":" ++ codes(rest)

def show(text: String) -> IO(Unit):
  IO.print(codes(apply(_ => unbox(String, Box{text}))))

def main() -> IO(Unit):
  do IO<Unit>:
    show("")
    show("plain")
    show("\0\n\t\r\\\"")
    show("éλ中😀")
    show("\u{1F600}\u{0}\u{10FFFF}")
    show("a" ++ "😀" ++ "b")
