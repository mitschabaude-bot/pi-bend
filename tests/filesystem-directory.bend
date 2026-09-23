import Base
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as UTF8
import ../packages/runtime/src/base64.bend as Base64

def kind(value: FS.FileKind) -> String:
  match value:
    case FS.RegularFile{}: "file"
    case FS.Directory{}: "directory"
    case FS.SymbolicLink{}: "symlink"
    case FS.Other{}: "other"

def error(value: FS.Error) -> String:
  match value:
    case FS.System{code,_}: "error:" ++ U32.show(code)
    case FS.InvalidPathEncoding{_}: "invalid-utf8"
    case _: "unexpected-error"

def rawEntries(values: List<(List<&2,U32> & U32)>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case (name,code) <> rest:
      do IO<Unit>:
        IO.print(Base64.encoded(name,"") ++ "|" ++ kind(FS.fileKindValue(code)))
        rawEntries(rest)

def rawResult(value: Result<&1,&1,U32 & String,List<(List<&2,U32> & U32)>>) -> IO(Unit):
  match value:
    case Fail{(code,_)}: IO.print("error:" ++ U32.show(code))
    case Done{values}: rawEntries(values)

def entries(values: List<&2,FS.DirectoryEntry>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case FS.DirectoryEntry{name,value} <> rest:
      do IO<Unit>:
        IO.print(Base64.encoded(UTF8.encode(name),"") ++ "|" ++ kind(value))
        entries(rest)

def listed(value: Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>>) -> IO(Unit):
  match value:
    case Fail{cause}: IO.print(error(cause))
    case Done{values}: entries(values)

def typed(value: Result<&2,&2,FS.Error,FS.FileKind>) -> IO(Unit):
  match value:
    case Fail{cause}: IO.print(error(cause))
    case Done{value}: IO.print(kind(value))

def count(values: List<&2,FS.DirectoryEntry>, total: Nat) -> Nat:
  match values:
    case Nil{}: total
    case _ <> rest: count(rest,total+1n)

def counted(value: Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>>) -> Nat:
  match value:
    case Done{values}: count(values,0n)
    case Fail{_}: 999999n

def repeat(+path: String, n: Nat) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      do IO<Unit>:
        listing : Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>> <- FS.readDirectory(path)
        Bool.pick(IO(Unit),Result.is_done(&2,&2,FS.Error,List<&2,FS.DirectoryEntry>,listing),IO.pure(Unit,Unit{}),IO.die(Unit,1,"repeat listing failed"))
        value : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(path)
        Bool.pick(IO(Unit),Result.is_done(&2,&2,FS.Error,FS.FileKind,value),IO.pure(Unit,Unit{}),IO.die(Unit,1,"repeat stat failed"))
        repeat(path,rest)

def run(mode: String, +path: String) -> IO(Unit):
  match mode:
    case "raw":
      do IO<Unit>:
        value : Result<&1,&1,U32 & String,List<(List<&2,U32> & U32)>> <- Directory.read_bytes(path)
        rawResult(value)
    case "kind":
      do IO<Unit>:
        value : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(path)
        typed(value)
    case "kind-nul": run("kind",path ++ "\u{0}")
    case "list-nul": run("list",path ++ "\u{0}")
    case "repeat":
      do IO<Unit>:
        before : Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>> <- FS.readDirectory("/proc/self/fd")
        repeat(path,256n)
        after : Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>> <- FS.readDirectory("/proc/self/fd")
        IO.print(Nat.show(counted(before)) ++ "|" ++ Nat.show(counted(after)))
    case _:
      do IO<Unit>:
        value : Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>> <- FS.readDirectory(path)
        listed(value)

def args(values: List<String>) -> IO(Unit):
  match values:
    case mode <> path <> Nil{}: run(mode,path)
    case _: IO.die(Unit,1,"expected mode path")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
