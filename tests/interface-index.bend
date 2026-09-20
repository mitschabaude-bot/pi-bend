import Base
import ../packages/runtime/src/network-interface.bend as Interface

def report(result: Result<&2, &2, Interface.Error, U32>) -> IO(Unit):
  match result:
    case Done{index}: IO.print("index:" ++ U32.show(index))
    case Fail{Interface.Error{code, message}}: IO.print("error:" ++ U32.show(code) ++ ":" ++ Bool.pick(String, String.eq(message, ""), "empty", "message"))

def check(name: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, Interface.Error, U32> <- Interface.index(name)
    report(result)

def run(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: check("lo\0invalid")
    case name <> rest:
      do IO<Unit>:
        check(name)
        run(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    run(values)
