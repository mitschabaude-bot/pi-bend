import Base
import ../packages/runtime/src/resolver-options.bend as Options
import ../packages/runtime/src/resolver-config.bend as Config

def bit(value: Bool) -> String:
  match value:
    case True{}: ",1"
    case False{}: ",0"

def features() -> List<&2, Options.Feature>:
  Options.Rotate{} <> Options.Edns{} <> Options.SingleRequestReopen{} <> Options.SingleRequest{} <> Options.NoTldQuery{} <> Options.NoReload{} <> Options.UseTcp{} <> Options.TrustAd{} <> Options.NoAAAA{} <> Nil{}

def flags(items: List<&2, Options.Feature>, +options: Options.Options, result: String) -> String:
  match items:
    case Nil{}: result
    case item <> rest: flags(rest, options, result ++ bit(Options.enabled(item, options)))

def numbers(values: Options.Options) -> String:
  match values:
    case Options.Options{ndots, timeout, attempts, _}: U32.show(ndots) ++ "," ++ U32.show(timeout) ++ "," ++ U32.show(attempts)

def diagnostics(values: List<&2, Options.Diagnostic>) -> IO(Unit):
  match values:
    case Nil{}: IO.print("END")
    case Options.Malformed{token} <> rest:
      do IO<Unit>:
        IO.print("malformed:" ++ token)
        diagnostics(rest)
    case Options.Unknown{token} <> rest:
      do IO<Unit>:
        IO.print("unknown:" ++ token)
        diagnostics(rest)

def report(value: Options.Report) -> IO(Unit):
  match value:
    case Options.Report{+values, issues}:
      do IO<Unit>:
        IO.print(flags(features(), values, numbers(values)))
        diagnostics(issues)

def run(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        report(Options.interpretStrict(Config.words(text, Config.Words{"", Nil{}}), Options.defaults()))
        run(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
