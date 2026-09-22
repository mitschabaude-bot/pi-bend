import Base

def number(text: String, value: U32) -> U32:
  match text:
    case SNil{}: value
    case SCon{Chr{char},rest}: number(rest,(value * 10 + char - 48 : U32))

def report(result: Result<&1,&1,U32 & String,Unit>) -> String:
  match result:
    case Done{Unit{}}: "ok"
    case Fail{(code,message)}: U32.show(code) ++ ":" ++ message

def name(value: Maybe<&2,String>) -> String:
  match value:
    case None{}: "none"
    case Some{text}: text

def run(args: List<String>) -> IO(Unit):
  match args:
    case "access" <> path <> mode <> Nil{}:
      do IO<Unit>:
        result : Result<&1,&1,U32 & String,Unit> <- File.access(path,number(mode,0))
        IO.print(report(result))
    case "nul" <> path <> Nil{}:
      do IO<Unit>:
        result : Result<&1,&1,U32 & String,Unit> <- File.access(path ++ SCon{Chr{0},"suffix"},6)
        IO.print(report(result))
    case "name" <> code <> Nil{}:
      do IO<Unit>:
        result : Maybe<&2,String> <- System.error_name(number(code,0))
        IO.print(name(result))
    case _: IO.die(Unit,1,"invalid access fixture input")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
