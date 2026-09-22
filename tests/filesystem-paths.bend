import Base
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/test/utf8-runner.bend as Wire

def error(value: FS.Error) -> String:
  match value:
    case FS.System{code,_}: "error:" ++ U32.show(code)
    case FS.InvalidPathEncoding{_}: "encoding"
    case FS.WriteAndClose{wc,_,cc,_}: "write-close:" ++ U32.show(wc) ++ ":" ++ U32.show(cc)
    case FS.ReadAndClose{wc,_,cc,_}: "read-close:" ++ U32.show(wc) ++ ":" ++ U32.show(cc)

def unit(result: Result<&2,&2,FS.Error,Unit>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{Unit{}}: "ok"

def text(result: Result<&2,&2,FS.Error,String>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{value}: "ok:" ++ Wire.showText(value)

def bytes(result: Result<&1,&1,U32 & String,List<&2,U32>>) -> String:
  match result:
    case Fail{(code,_)}: "error:" ++ U32.show(code)
    case Done{value}: "ok:" ++ String.join(Wire.showNumbers(value),",")

def repeatWrites(count: Nat, +path: String) -> IO(Unit):
  match count:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      do IO<Unit>:
        result : Result<&2,&2,FS.Error,Unit> <- FS.writeFile(path,"x")
        IO.print(unit(result))
        repeatWrites(rest,path)

def closed(result: Result<&1,&1,U32 & String,Unit>) -> String:
  match result:
    case Fail{(code,_)}: "error:" ++ U32.show(code)
    case Done{Unit{}}: "ok"

def opened(result: Result<&1,&1,U32 & String,File>) -> IO(Unit):
  match result:
    case Fail{(code,_)}: IO.print("error:" ++ U32.show(code))
    case Done{file}:
      do IO<Unit>:
        result : Result<&1,&1,U32 & String,Unit> <- File.close_checked(file)
        IO.print(closed(result))

def run(arguments: List<String>) -> IO(Unit):
  match arguments:
    case "open" <> path <> mode <> Nil{}:
      do IO<Unit>:
        result : Result<&1,&1,U32 & String,File> <- File.open_mode(path,mode,384)
        opened(result)
    case "mkdir" <> path <> Nil{}:
      do IO<Unit>:
        result : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(path)
        IO.print(unit(result))
    case "realpath" <> path <> Nil{}:
      do IO<Unit>:
        result : Result<&2,&2,FS.Error,String> <- FS.realpath(path)
        IO.print(text(result))
    case "bytes" <> path <> Nil{}:
      do IO<Unit>:
        result : Result<&1,&1,U32 & String,List<&2,U32>> <- File.realpath_bytes(path)
        IO.print(bytes(result))
    case "home-bytes" <> Nil{}:
      do IO<Unit>:
        result : Result<&1,&1,U32 & String,List<&2,U32>> <- Directory.home_bytes()
        IO.print(bytes(result))
    case "home" <> Nil{}:
      do IO<Unit>:
        result : Result<&2,&2,FS.Error,String> <- FS.homedir()
        IO.print(text(result))
    case "cwd" <> Nil{}:
      do IO<Unit>:
        result : Result<&2,&2,FS.Error,String> <- FS.cwd()
        IO.print(text(result))
    case "write" <> path <> content <> Nil{}:
      do IO<Unit>:
        result : Result<&2,&2,FS.Error,Unit> <- FS.writeFile(path,content)
        IO.print(unit(result))
    case "nul" <> +path <> Nil{}:
      do IO<Unit>:
        first : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(path ++ SCon{Chr{0},"suffix"})
        second : Result<&2,&2,FS.Error,String> <- FS.realpath(path ++ SCon{Chr{0},"suffix"})
        IO.print(unit(first) ++ "|" ++ text(second))
    case "repeat" <> path <> Nil{}: repeatWrites(128n,path)
    case _: IO.die(Unit,1,"invalid filesystem fixture arguments")

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    run(arguments)
