import Base

def status(result: Result<&1,&1,U32 & String,ProcessStatus>,closed: Result<&1,&1,U32 & String,Unit>) -> String:
  match result closed:
    case Done{ProcessExited{code}} Done{_}: "exit:" ++ U32.show(code)
    case Done{ProcessSignalled{signal}} Done{_}: "signal:" ++ U32.show(signal)
    case Fail{(code,_)} _: "wait-error:" ++ U32.show(code)
    case _ Fail{(code,_)}: "close-error:" ++ U32.show(code)

def ended(pair: Process & Result<&1,&1,U32 & String,ProcessStatus>) -> IO(Unit):
  match pair:
    case (owner,result):
      do IO<Unit>:
        closed : Result<&1,&1,U32 & String,Unit> <- Process.close_checked(owner)
        IO.print(status(result,closed))

def spawned(result: Result<&1,&1,U32 & String,Process>) -> IO(Unit):
  match result:
    case Fail{(code,_)}: IO.print("spawn-error:" ++ U32.show(code))
    case Done{owner}:
      do IO<Unit>:
        result : Process & Result<&1,&1,U32 & String,ProcessStatus> <- Process.wait(owner)
        ended(result)

def temporary(result: Result<&1,&1,U32 & String,String>) -> IO(Unit):
  match result:
    case Done{path}: IO.print(path)
    case Fail{(code,_)}: IO.print("temp-error:" ++ U32.show(code))

def run(args: List<String>) -> IO(Unit):
  match args:
    case "temp" <> template <> Nil{}:
      do IO<Unit>:
        result : Result<&1,&1,U32 & String,String> <- Directory.mkdtemp(template)
        temporary(result)
    case path <> cwd <> args:
      do IO<Unit>:
        env : List<String> <- IO.environment()
        result : Result<&1,&1,U32 & String,Process> <- Process.spawn_inherit(path,args,cwd,env)
        spawned(result)
    case _: IO.die(Unit,1,"usage: PATH CWD [ARGS] | temp TEMPLATE")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
