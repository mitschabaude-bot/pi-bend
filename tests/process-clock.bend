import Base

def showLocal(value: LocalTime) -> String:
  match value:
    case LocalTime{year,month,day,hour,minute,second}:
      U32.show(year) ++ ":" ++ U32.show(month) ++ ":" ++ U32.show(day) ++ ":" ++ U32.show(hour) ++ ":" ++ U32.show(minute) ++ ":" ++ U32.show(second)
def result(value: Result<&1,&1,U32 & String,LocalTime>) -> String:
  match value:
    case Fail{(code,_)}: "error:" ++ U32.show(code)
    case Done{+value}: showLocal(value) ++ "|" ++ showLocal(value)
def repeat(left: Nat) -> IO(Unit):
  match left:
    case Zero{}: IO.pure(Unit,Unit{})
    case Succ{rest}:
      do IO<Unit>:
        pid : U32 <- Process.id()
        local : Result<&1,&1,U32 & String,LocalTime> <- Clock.localTime()
        IO.print(U32.show(pid) ++ "|" ++ result(local))
        repeat(rest)
def main() -> IO(Unit): repeat(4n)
