import Base
import ../packages/runtime/test/utf8-runner.bend as Wire

def status(value: Result<&1,&1,U32 & String,Unit>) -> String:
  match value:
    case Done{_}: "ok"
    case Fail{(code,_)}: "error:" ++ U32.show(code)

def size(value: Result<&1,&1,U32 & String,U32 & U32>) -> String:
  match value:
    case Done{(high,low)}: U32.show(high) ++ ":" ++ U32.show(low)
    case Fail{(code,_)}: "error:" ++ U32.show(code)

def bytes(count: Nat,+index: U32,reversed: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: List.reverse(&2,U32,reversed)
    case 1n+n: bytes(n,(index + 1 : U32),(index % 256 : U32) <> reversed)

def closed(pair: File & Result<&1,&1,U32 & String,Unit>) -> IO(Unit):
  match pair:
    case (file,result):
      do IO<Unit>:
        IO.print(status(result))
        outcome : Result<&1,&1,U32 & String,Unit> <- File.close_checked(file)
        IO.print(status(outcome))

def retained(pair: File & Result<&1,&1,U32 & String,Unit>) -> IO(Unit):
  match pair:
    case (file,result):
      do IO<Unit>:
        IO.print(status(result))
        written : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,0 <> 255 <> 195 <> Nil{})
        closed(written)

def opened(mode: String,data: List<&2,U32>,value: Result<&1,&1,U32 & String,File>) -> IO(Unit):
  match value:
    case Fail{(code,_)}: IO.print("open:" ++ U32.show(code))
    case Done{file}:
      do IO<Unit>:
        written : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,data)
        Bool.pick((File & Result<&1,&1,U32 & String,Unit>) -> IO(Unit),String.eq(mode,"retain"),retained,closed)(written)

def run(args: List<String>) -> IO(Unit):
  match args:
    case "size" <> path <> Nil{}:
      do IO<Unit>:
        result : Result<&1,&1,U32 & String,U32 & U32> <- File.size_bytes(path)
        IO.print(size(result))
    case "nul" <> path <> Nil{}:
      do IO<Unit>:
        result : Result<&1,&1,U32 & String,U32 & U32> <- File.size_bytes(path ++ SCon{Chr{0},"suffix"})
        IO.print(size(result))
    case "retain" <> path <> Nil{}:
      do IO<Unit>:
        result : Result<&1,&1,U32 & String,File> <- File.open_mode(path,"w",384)
        opened("retain",1 <> 256 <> 2 <> Nil{},result)
    case "write" <> path <> mode <> count <> Nil{}:
      do IO<Unit>:
        result : Result<&1,&1,U32 & String,File> <- File.open_mode(path,mode,384)
        opened("write",bytes(Maybe.default(&2,Nat,Nat.read(count),0n),0,Nil{}),result)
    case _: IO.die(Unit,1,"invalid filesystem byte fixture arguments")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
