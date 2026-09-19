import Base

def answer() -> U32: 40

def effectBinding() -> IO(U32):
  do IO<U32>:
    answer : U32 <- IO.pure(U32, (answer() + 2 : U32))
    return answer

def valueBinding() -> IO(U32):
  do IO<U32>:
    answer : U32 = (answer() + 3 : U32)
    return answer

def copiedBinding() -> IO(U32):
  do IO<U32>:
    +answer : U32 <- IO.pure(U32, 4)
    return (answer + answer : U32)

def nestedBinding(answer: U32) -> IO(U32):
  do IO<U32>:
    answer : U32 <- IO.pure(U32, (answer + 1 : U32))
    return answer

def tailAction() -> IO(U32):
  do IO<U32>:
    effectBinding()

def check(value: U32, expected: U32) -> IO(Unit):
  Bool.pick(IO(Unit), U32.is_eq(value, expected), IO.print("PASS typed do binding"), IO.die(Unit, 1, "typed do binding resolved to the wrong name"))

def main() -> IO(Unit):
  do IO<Unit>:
    effect : U32 <- effectBinding()
    check(effect, 42)
    value : U32 <- valueBinding()
    check(value, 43)
    copied : U32 <- copiedBinding()
    check(copied, 8)
    nested : U32 <- nestedBinding(6)
    check(nested, 7)
    tail : U32 <- tailAction()
    check(tail, 42)
