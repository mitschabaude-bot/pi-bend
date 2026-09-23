import Base
import ./string.bend as Strings
import ./utf8.bend as Utf8
import ./file-fold.bend as Fold
import ./u64.bend as Word
import ./f64.bend as F
import ./date.bend as Date

type Error is Data:
  System{code: U32, message: String}
  InvalidPathEncoding{cause: Utf8.Error}
  WriteAndClose{writeCode: U32, writeMessage: String, closeCode: U32, closeMessage: String}
  ReadAndClose{readCode: U32, readMessage: String, closeCode: U32, closeMessage: String}

def system(-A: Data, result: Result<&1,&1,U32 & String,A>) -> Result<&2,&2,Error,A>:
  match result:
    case Fail{(code,message)}: Fail{System{code,message}}
    case Done{value}: Done{value}

def decoded(result: Result<&2,&2,Utf8.Error,String>) -> Result<&2,&2,Error,String>:
  match result:
    case Fail{cause}: Fail{InvalidPathEncoding{cause}}
    case Done{value}: Done{value}

def pathBytes(result: Result<&1,&1,U32 & String,List<&2,U32>>) -> Result<&2,&2,Error,String>:
  Result.bind(&2,&2,Error,List<&2,U32>,String,system(List<&2,U32>,result),bytes => decoded(Utf8.decodeWith(Utf8.Preserve{},bytes)))

def realpath(path: String) -> IO(Result<&2,&2,Error,String>):
  do IO<Result<&2,&2,Error,String>>:
    result : Result<&1,&1,U32 & String,List<&2,U32>> <- File.realpath_bytes(path)
    return pathBytes(result)

def cwd() -> IO(Result<&2,&2,Error,String>):
  do IO<Result<&2,&2,Error,String>>:
    result : Result<&1,&1,U32 & String,List<&2,U32>> <- Directory.current_bytes()
    return pathBytes(result)

def homedir() -> IO(Result<&2,&2,Error,String>):
  do IO<Result<&2,&2,Error,String>>:
    result : Result<&1,&1,U32 & String,List<&2,U32>> <- Directory.home_bytes()
    return pathBytes(result)

def child(parent: String, name: String) -> String:
  match parent:
    case "": name
    case "/": "/" ++ name
    case value: value ++ "/" ++ name

# Resolve each prefix through the OS. Lexically cancelling `link/..` here would
# change filesystem meaning; path-input normalization belongs to the caller.
def directories(parts: List<&2,String>, parent: String, previous: Result<&2,&2,Error,Unit>) -> IO(Result<&2,&2,Error,Unit>):
  match parts previous:
    case _ Fail{error}: IO.pure(Result<&2,&2,Error,Unit>,Fail{error})
    case Nil{} Done{Unit{}}: IO.pure(Result<&2,&2,Error,Unit>,Done{Unit{}})
    case "" <> rest Done{Unit{}}: directories(rest,parent,Done{Unit{}})
    case name <> rest Done{Unit{}}:
      +next = child(parent,name)
      do IO<Result<&2,&2,Error,Unit>>:
        result : Result<&1,&1,U32 & String,Unit> <- Directory.ensure(next)
        directories(rest,next,system(Unit,result))

def missingParents(path: String, result: Result<&2,&2,Error,Unit>) -> IO(Result<&2,&2,Error,Unit>):
  match path result:
    case _ Done{Unit{}}: IO.pure(Result<&2,&2,Error,Unit>,Done{Unit{}})
    case "" Fail{error}: IO.pure(Result<&2,&2,Error,Unit>,Fail{error})
    case SCon{'/',rest} Fail{System{2,_}}: directories(Strings.split(rest,'/'),"/",Done{Unit{}})
    case value Fail{System{2,_}}: directories(Strings.split(value,'/'),"",Done{Unit{}})
    case _ Fail{error}: IO.pure(Result<&2,&2,Error,Unit>,Fail{error})

# Try the complete path first, preserving ENOTDIR and permission errors. Only
# ENOENT needs parent creation. Existing paths take one OS operation.
def mkdir(+path: String) -> IO(Result<&2,&2,Error,Unit>):
  do IO<Result<&2,&2,Error,Unit>>:
    result : Result<&1,&1,U32 & String,Unit> <- Directory.ensure(path)
    missingParents(path,system(Unit,result))

# Node's writeFile retains both failures when writing and closing both fail.
def closed(write: Result<&1,&1,U32 & String,Unit>, close: Result<&1,&1,U32 & String,Unit>) -> Result<&2,&2,Error,Unit>:
  match write close:
    case Done{Unit{}} Done{Unit{}}: Done{Unit{}}
    case Fail{(code,message)} Done{Unit{}}: Fail{System{code,message}}
    case Done{Unit{}} Fail{(code,message)}: Fail{System{code,message}}
    case Fail{(wc,wm)} Fail{(cc,cm)}: Fail{WriteAndClose{wc,wm,cc,cm}}

def written(pair: File & Result<&1,&1,U32 & String,Unit>) -> IO(Result<&2,&2,Error,Unit>):
  match pair:
    case (file,result):
      do IO<Result<&2,&2,Error,Unit>>:
        close : Result<&1,&1,U32 & String,Unit> <- File.close_checked(file)
        return closed(result,close)

def opened(content: String, result: Result<&1,&1,U32 & String,File>) -> IO(Result<&2,&2,Error,Unit>):
  match result:
    case Fail{(code,message)}: IO.pure(Result<&2,&2,Error,Unit>,Fail{System{code,message}})
    case Done{file}:
      do IO<Result<&2,&2,Error,Unit>>:
        result : File & Result<&1,&1,U32 & String,Unit> <- File.write(file,content)
        written(result)

# File.write drains partial writes. The affine handle is closed on success and
# typed write failure; callers retain mutation ownership until this returns.
# Creation permissions apply only to a new file, as Node's writeFile `mode`.
def writeFileMode(path: String, content: String, permissions: U32) -> IO(Result<&2,&2,Error,Unit>):
  do IO<Result<&2,&2,Error,Unit>>:
    result : Result<&1,&1,U32 & String,File> <- File.open_mode(path,"w",permissions)
    opened(content,result)

def writeFile(path: String, content: String) -> IO(Result<&2,&2,Error,Unit>):
  writeFileMode(path,content,438)

# Node's appendFile: create with the default mode or append to the end.
def appendFile(path: String, content: String) -> IO(Result<&2,&2,Error,Unit>):
  do IO<Result<&2,&2,Error,Unit>>:
    result : Result<&1,&1,U32 & String,File> <- File.open_mode(path,"a",438)
    opened(content,result)

# Node's writeFile with flag "wx": creation fails with EEXIST for an existing path.
def writeFileExclusive(path: String, content: String) -> IO(Result<&2,&2,Error,Unit>):
  do IO<Result<&2,&2,Error,Unit>>:
    result : Result<&1,&1,U32 & String,File> <- File.open_mode(path,"wx",438)
    opened(content,result)

# Accumulate chunks in reverse byte order, then reverse once at EOF. Short
# reads and resource retirement are owned by the shared file fold.
def collectBytes(bytes: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case Nil{}: reversed
    case byte <> rest: collectBytes(rest, byte <> reversed)

def consumeBytes(reversed: List<&2, U32>, bytes: List<&2, U32>) -> Fold.Control<List<&2, U32>>:
  Fold.Continue{collectBytes(bytes, reversed)}

def readResult(outcome: Fold.Outcome<List<&2, U32>>) -> Result<&2, &2, Error, List<&2, U32>>:
  match outcome:
    case Fold.Outcome{bytes, Done{_}}: Done{bytes}
    case Fold.Outcome{_, Fail{Fold.Open{code, message}}}: Fail{System{code, message}}
    case Fold.Outcome{_, Fail{Fold.Read{code, message}}}: Fail{System{code, message}}
    case Fold.Outcome{_, Fail{Fold.Close{code, message}}}: Fail{System{code, message}}
    case Fold.Outcome{_, Fail{Fold.ReadAndClose{rc, rm, cc, cm}}}: Fail{ReadAndClose{rc, rm, cc, cm}}
    case Fold.Outcome{_, Fail{Fold.InvalidReadSize{}}}: Fail{System{22, "Invalid file read size"}}

def readFile(path: String) -> IO(Result<&2, &2, Error, List<&2, U32>>):
  do IO<Result<&2, &2, Error, List<&2, U32>>>:
    outcome : Fold.Outcome<List<&2, U32>> <- Fold.read(~List<&2, U32>, ~consumeBytes, path, 65536, Nil{})
    return Result.map(&2, &2, Error, List<&2, U32>, List<&2, U32>, bytes => List.reverse(&2, U32, bytes), readResult(outcome))

def prefixBytes(unused: List<&2, U32>, bytes: List<&2, U32>) -> Fold.Control<List<&2, U32>>:
  Fold.Stop{bytes}

# Read one prefix chunk, then close. The positive maximum bounds allocation;
# a short OS read is returned as-is, matching Pi's image header inspection.
def readPrefix(path: String, maximum: U32) -> IO(Result<&2, &2, Error, List<&2, U32>>):
  do IO<Result<&2, &2, Error, List<&2, U32>>>:
    outcome : Fold.Outcome<List<&2, U32>> <- Fold.read(~List<&2, U32>, ~prefixBytes, path, maximum, Nil{})
    return readResult(outcome)

# stat follows symbolic links and reads no content. Keep the full OS word size.
def granted(result: Result<&1,&1,U32 & String,Unit>) -> Bool:
  match result:
    case Done{Unit{}}: True{}
    case Fail{_}: False{}

# Node's fs.access as a predicate: mode 0 checks existence, 1 execution,
# 2 writing, 4 reading, and their sums combine the checks.
def accessible(path: String, mode: U32) -> IO(Bool):
  do IO<Bool>:
    result : Result<&1,&1,U32 & String,Unit> <- File.access(path, mode)
    return granted(result)

def fileSize(result: Result<&1,&1,U32 & String,U32 & U32>) -> Result<&2,&2,Error,Word.U64>:
  match result:
    case Fail{(code,message)}: Fail{System{code,message}}
    case Done{(high,low)}: Done{Word.U64{high,low}}

def size(path: String) -> IO(Result<&2,&2,Error,Word.U64>):
  do IO<Result<&2,&2,Error,Word.U64>>:
    result : Result<&1,&1,U32 & String,U32 & U32> <- File.size_bytes(path)
    return fileSize(result)

# Node's Stats.mtime.getTime(): the exact modification time (signed seconds
# high/low, nanoseconds) as milliseconds, rounded to the nearest integer.
def modifiedMilliseconds(value: U32 & U32 & U32) -> F64:
  match value:
    case (high,(low,nanos)):
      +raw = F64.add(F64.mul(Date.fromMilliseconds(Word.U64{high,low}),U32.to_f64(1000)),F64.div(U32.to_f64(nanos),U32.to_f64(1000000)))
      F64.floor(F64.add(raw,F64.div(U32.to_f64(1),U32.to_f64(2))))

def modifiedResult(result: Result<&1,&1,U32 & String,U32 & U32 & U32>) -> Result<&2,&2,Error,F64>:
  match result:
    case Fail{(code,message)}: Fail{System{code,message}}
    case Done{value}: Done{modifiedMilliseconds(value)}

def modified(path: String) -> IO(Result<&2,&2,Error,F64>):
  do IO<Result<&2,&2,Error,F64>>:
    result : Result<&1,&1,U32 & String,U32 & U32 & U32> <- File.modified_time(path)
    return modifiedResult(result)

# Metadata inspection never opens the contents of FIFOs, devices or sockets.
type FileKind is Data:
  RegularFile{}
  Directory{}
  SymbolicLink{}
  Other{}

type DirectoryEntry is Data:
  DirectoryEntry{name: String, kind: FileKind}

def fileKindValue(value: U32) -> FileKind:
  match value:
    case 1: RegularFile{}
    case 2: Directory{}
    case 3: SymbolicLink{}
    case _: Other{}

# stat follows links; a dangling link reports the underlying OS error.
def fileKind(path: String) -> IO(Result<&2,&2,Error,FileKind>):
  do IO<Result<&2,&2,Error,FileKind>>:
    result : Result<&1,&1,U32 & String,U32> <- File.kind(path)
    return Result.map(&2,&2,Error,U32,FileKind,fileKindValue,system(U32,result))

def directoryEntries(values: List<(List<&2,U32> & U32)>, reversed: List<&2,DirectoryEntry>) -> Result<&2,&2,Error,List<&2,DirectoryEntry>>:
  match values:
    case Nil{}: Done{List.reverse(&2,DirectoryEntry,reversed)}
    case (bytes,kind) <> rest:
      Result.bind(&2,&2,Error,String,List<&2,DirectoryEntry>,decoded(Utf8.decodeWith(Utf8.Preserve{},bytes)),name => directoryEntries(rest,DirectoryEntry{name,fileKindValue(kind)} <> reversed))

def directoryResult(result: Result<&1,&1,U32 & String,List<(List<&2,U32> & U32)>>) -> Result<&2,&2,Error,List<&2,DirectoryEntry>>:
  match result:
    case Fail{(code,message)}: Fail{System{code,message}}
    case Done{entries}: directoryEntries(entries,Nil{})

# Entries preserve OS enumeration order. Consumers choose their own sorting;
# symlink entries are reported as links, and invalid UTF-8 names fail explicitly.
def readDirectory(path: String) -> IO(Result<&2,&2,Error,List<&2,DirectoryEntry>>):
  do IO<Result<&2,&2,Error,List<&2,DirectoryEntry>>>:
    result : Result<&1,&1,U32 & String,List<(List<&2,U32> & U32)>> <- Directory.read_bytes(path)
    return directoryResult(result)
