import Base
import ../packages/runtime/src/resolver-config.bend as Resolver
import ../packages/runtime/src/resolver-config.bend as Options
import ../packages/runtime/src/resolver-config.bend as Config
import ../packages/runtime/src/resolver-config.bend as Settings
import ../packages/runtime/src/dns-message.bend as Search
import ../packages/runtime/src/dns-message.bend as Run
import ../packages/runtime/src/dns-message.bend as Presentation
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./resolver-options.bend as OptionsTest
import ./resolver-domains.bend as DomainsTest
import ./dns-search.bend as SearchTest
import ./dns-search-run.bend as RunTest

def run(text: String, dots: U32, absolute: Bool, result: Result<&2, &2, List<&2, Options.Diagnostic>, Resolver.Configuration>) -> IO(Unit):
  match result:
    case Fail{errors}:
      do IO<Unit>:
        IO.print("rejected")
        OptionsTest.diagnostics(errors)
    case Done{Resolver.Configuration{+options, +domains}}:
      +cursor = Resolver.startSearch(Resolver.Configuration{options, domains}, SearchTest.parsed(Presentation.parsePresentation(text)), dots, absolute)
      do IO<Unit>:
        OptionsTest.report(Options.OptionsReport{options, Nil{}})
        SearchTest.drain(10000n, 4294967295, 0, Search.next(cursor))
        result : Result<&2, &2, Run.SearchRunError<String>, String> <- Run.runSearch(~Unit, ~String, ~String, ~DomainsTest.request, Unit{}, cursor)
        RunTest.report(result)

def args(values: List<String>) -> IO(Unit):
  match values:
    case text <> dots <> absolute <> file <> options <> Nil{}:
      run(text, Scalar.decimal(dots, 0), String.eq(absolute, "1"), Resolver.fromSettingsStrict(Settings.configure(Config.parse(file), Settings.Overrides{Some{"host.example"}, None{}, Config.words(options, Config.Words{"", Nil{}})})))
    case _: IO.die(Unit, 1, "expected base dots absolute configuration environment-options")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
