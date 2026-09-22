import Base
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/file-fold.bend as Fold
import ../packages/coding-agent/src/utils/mime.bend as Mime

def digit(+value: U32) -> Char:
  Chr{Bool.pick(U32,U32.is_lt(value,10),(value + 48 : U32),(value + 87 : U32))}

def hex(bytes: List<&2,U32>, reversed: String) -> String:
  match bytes:
    case Nil{}: String.reverse(reversed)
    case +byte <> rest: hex(rest,SCon{digit(U32.and(byte,15)),SCon{digit(U32.div(byte,16)),reversed}})

def report(value: Result<&2,&2,FS.Error,List<&2,U32>>) -> String:
  match value:
    case Done{bytes}: "ok:" ++ hex(bytes,"")
    case Fail{FS.System{code,_}}: "error:" ++ U32.show(code)
    case Fail{FS.ReadAndClose{read,_,close,_}}: "read-close:" ++ U32.show(read) ++ ":" ++ U32.show(close)
    case Fail{_}: "unexpected-error"

type State is Type:
  State{chunks: Nat, stop: Bool, reversed: List<&2,U32>}

def control(stop: Bool, state: State) -> Fold.Control<State>:
  match stop:
    case True{}: Fold.Stop{state}
    case False{}: Fold.Continue{state}

def consume(state: State, bytes: List<&2,U32>) -> Fold.Control<State>:
  match state:
    case State{chunks,+stop,reversed}:
      control(stop,State{1n+chunks,stop,FS.collectBytes(bytes,reversed)})

def status(outcome: Result<&2,&2,Fold.Error,Fold.Completion>) -> String:
  match outcome:
    case Done{Fold.EndOfFile{}}: "eof"
    case Done{Fold.Stopped{}}: "stopped"
    case Fail{Fold.Open{code,_}}: "open:" ++ U32.show(code)
    case Fail{Fold.Read{code,_}}: "read:" ++ U32.show(code)
    case Fail{Fold.Close{code,_}}: "close:" ++ U32.show(code)
    case Fail{Fold.ReadAndClose{read,_,close,_}}: "read-close:" ++ U32.show(read) ++ ":" ++ U32.show(close)
    case Fail{Fold.InvalidReadSize{}}: "size"

def folded(value: Fold.Outcome<State>) -> String:
  match value:
    case Fold.Outcome{State{chunks,_,bytes},outcome}: status(outcome) ++ ":" ++ Nat.show(chunks) ++ ":" ++ hex(List.reverse(&2,U32,bytes),"")

def fold(path: String, stop: Bool) -> IO(Unit):
  do IO<Unit>:
    value : Fold.Outcome<State> <- Fold.read(~State,~consume,path,7,State{0n,stop,250 <> Nil{}})
    IO.print(folded(value))

def prefix(path: String, maximum: U32) -> IO(Unit):
  do IO<Unit>:
    value : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readPrefix(path,maximum)
    IO.print(report(value))

def mime(value: Result<&2,&2,FS.Error,Maybe<&2,String>>) -> String:
  match value:
    case Done{None{}}: "null"
    case Done{Some{mime}}: mime
    case Fail{FS.System{code,_}}: "error:" ++ U32.show(code)
    case Fail{FS.ReadAndClose{read,_,close,_}}: "read-close:" ++ U32.show(read) ++ ":" ++ U32.show(close)
    case Fail{_}: "unexpected-error"

def operation(mode: String, path: String) -> IO(Unit):
  match mode:
    case "read":
      do IO<Unit>:
        value : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
        IO.print(report(value))
    case "prefix": prefix(path,7)
    case "zero": prefix(path,0)
    case "mime":
      do IO<Unit>:
        value : Result<&2,&2,FS.Error,Maybe<&2,String>> <- Mime.detectSupportedImageMimeTypeFromFile(path)
        IO.print(mime(value))
    case "fold": fold(path,False{})
    case "stop": fold(path,True{})
    case _: IO.die(Unit,1,"expected read/prefix/zero/mime/fold/stop")

def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case mode <> path <> rest:
      do IO<Unit>:
        operation(mode,path)
        run(rest)
    case _: IO.die(Unit,1,"expected mode and path pairs")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
