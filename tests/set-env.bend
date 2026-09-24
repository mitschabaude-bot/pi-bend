import Base
# IO.set_env (patches/bend-set-env.patch). Expected output: ok / value one / error 22 / environ has it.

def shown(result: Result<&1, &1, U32 & String, String>) -> String:
  match result:
    case Done{value}: value
    case Fail{_}: "<unset>"

def outcome(result: Result<&1, &1, U32 & String, Unit>) -> String:
  match result:
    case Done{_}: "ok"
    case Fail{(code, _)}: "error " ++ U32.show(code)

def listed(entries: List<String>) -> Bool:
  match entries:
    case Nil{}: False{}
    case entry <> rest: String.eq(entry, "PI_BEND_SET_ENV_TEST=value one") || listed(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    set : Result<&1, &1, U32 & String, Unit> <- IO.set_env("PI_BEND_SET_ENV_TEST", "value one")
    IO.print(outcome(set))
    got : Result<&1, &1, U32 & String, String> <- IO.get_env("PI_BEND_SET_ENV_TEST")
    IO.print(shown(got))
    bad : Result<&1, &1, U32 & String, Unit> <- IO.set_env("A=B", "x")
    IO.print(outcome(bad))
    entries : List<String> <- IO.environment()
    IO.print(Bool.pick(String, listed(entries), "environ has it", "environ lacks it"))
