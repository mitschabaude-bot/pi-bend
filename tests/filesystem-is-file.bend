import Base

def report(value: Result<&1,&1,U32 & String,Bool>) -> String:
  match value:
    case Fail{(code,_)}: "error:" ++ U32.show(code)
    case Done{value}: Bool.pick(String,value,"true","false")

def paths(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case path <> rest:
      do IO<Unit>:
        value : Result<&1,&1,U32 & String,Bool> <- File.is_file(path)
        IO.print(report(value))
        paths(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    paths(args)
