import Base
import ../packages/runtime/src/resolver-request.bend as Request
import ../packages/runtime/src/resolver-options.bend as Resolver
import ../packages/runtime/src/resolver-config.bend as Config
import ../packages/runtime/src/dns-query.bend as Query
import ../packages/runtime/src/dns-edns.bend as Edns
import ./resolver-options.bend as OptionsTest

def query(options: Query.Options) -> String:
  match options:
    case Query.Options{flags, None{}}: U32.show(flags) ++ ":none"
    case Query.Options{flags, Some{Edns.Query{size, dnssec, Nil{}}}}: U32.show(flags) ++ ":" ++ U32.show(size) ++ OptionsTest.bit(dnssec) ++ ":empty"
    case _: "unexpected-options"

def report(result: Result<&2, &2, List<&2, Resolver.Diagnostic>, Request.Prepared>) -> IO(Unit):
  match result:
    case Fail{errors}:
      do IO<Unit>:
        IO.print("FAIL")
        OptionsTest.diagnostics(errors)
    case Done{Request.Prepared{+settings, request}}:
      do IO<Unit>:
        IO.print(OptionsTest.flags(OptionsTest.features(), settings, OptionsTest.numbers(settings)))
        IO.print(query(request))

def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        report(Request.prepareStrict(Config.words(arg, Config.Words{"", Nil{}})))
        run(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
