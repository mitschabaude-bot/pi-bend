import Base

def number(text: String, acc: U32) -> U32:
  match text:
    case SNil{}: acc
    case SCon{Chr{char},rest}: number(rest,(acc * 10 + char - 48 : U32))

def source(count: Nat, +code: U32, text: String) -> String:
  match count:
    case Zero{}: text
    case Succ{rest}: source(rest,((code + 1) % 128 : U32),SCon{Chr{code},text})

def checksum(text: String, value: U32) -> U32:
  match text:
    case SNil{}: value
    case SCon{Chr{code},rest}: checksum(rest,(value * 33 + code : U32))

def measure(count: Nat, +text: String, +size: Nat, result: U32) -> U32:
  match count:
    case Zero{}: result
    case Succ{rest}: measure(rest,text,size,(result + checksum(String.take(text,size),0) : U32))

def run(args: List<String>) -> IO(Unit):
  match args:
    case amount <> size <> count <> Nil{}:
      IO.print(U32.show(measure(U32.to_nat(number(count,0)),source(U32.to_nat(number(amount,0)),0,""),U32.to_nat(number(size,0)),0)))
    case _: IO.die(Unit,1,"expected source length, prefix length, iterations")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
