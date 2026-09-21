import Base
import ../packages/ai/src/api/openai-responses-initialization-error.bend as D
import ../packages/ai/src/api/openai-responses-cleartext-system-runtime.bend as System
import ../packages/ai/src/api/openai-responses-cleartext-runtime.bend as Runtime
import ../packages/runtime/src/resolver-system-config.bend as Config
import ../packages/runtime/src/resolver-load.bend as Load
import ../packages/runtime/src/resolver-file.bend as File
import ../packages/runtime/src/file-fold.bend as Fold
import ../packages/runtime/src/random-index.bend as Index
import ../packages/runtime/src/random-seed.bend as Seed
import ../packages/runtime/src/json-string.bend as Quote

def show(error: System.Error) -> IO(Unit): IO.print(Quote.quote(D.format(error)))

def main() -> IO(Unit):
  do IO<Unit>:
    show(System.InitializationFailure{Runtime.ResolverFailure{Index.InvalidBound{}}})
    show(System.InitializationFailure{Runtime.ResolverFailure{Index.InvalidBytes{}}})
    show(System.InitializationFailure{Runtime.ResolverFailure{Index.SourceFailure{5, "unavailable"}}})
    show(System.InitializationFailure{Runtime.RetryFailure{Seed.SourceFailure{2, "missing"}}})
    show(System.InitializationFailure{Runtime.RetryFailure{Seed.ShortSeed{7n}}})
    show(System.ConfigurationFailure{Config.Loading{Load.File{File.File{Fold.Open{2, "missing resolver file"}}}}})
    show(System.ConfigurationFailure{Config.Loading{Load.File{File.TooLarge{}}}})
    IO.print(Quote.quote(D.display(Nil{})))
    IO.print(Quote.quote(D.display("first" <> "second" <> "third" <> Nil{})))
    IO.print(Quote.quote(D.display("" <> Nil{})))
