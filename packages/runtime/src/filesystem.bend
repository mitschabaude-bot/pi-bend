import Base
import ./string.bend as Strings
import ./utf8.bend as Utf8

type Error is Data:
  System{code: U32, message: String}
  InvalidPathEncoding{cause: Utf8.Error}
  WriteAndClose{writeCode: U32, writeMessage: String, closeCode: U32, closeMessage: String}

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
def writeFile(path: String, content: String) -> IO(Result<&2,&2,Error,Unit>):
  do IO<Result<&2,&2,Error,Unit>>:
    result : Result<&1,&1,U32 & String,File> <- File.open_mode(path,"w",438)
    opened(content,result)
