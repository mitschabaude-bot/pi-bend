import Base
import ../packages/runtime/src/resolver-environment.bend as Environment
import ../packages/runtime/src/resolver-settings.bend as Settings
import ../packages/runtime/src/resolver-config.bend as Config
import ./resolver-settings.bend as Output

def report(text: String, hostname: String, captured: Result<&2, &2, Environment.Error, Environment.Values>) -> IO(Unit):
  match captured:
    case Fail{Environment.Error{variable, code, message}}: IO.print("error:" ++ variable ++ ":" ++ U32.show(code) ++ ":" ++ message)
    case Done{values}: Output.report(Settings.configure(Config.parse(text), Environment.overrides(Some{hostname}, values)))

def args(values: List<String>) -> IO(Unit):
  match values:
    case text <> hostname <> Nil{}:
      do IO<Unit>:
        captured : Result<&2, &2, Environment.Error, Environment.Values> <- Environment.capture()
        report(text, hostname, captured)
    case _: IO.die(Unit, 1, "expected configuration text and hostname")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
