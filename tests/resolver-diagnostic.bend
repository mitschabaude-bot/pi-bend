import Base
import ../packages/runtime/src/dns-resolver.bend as D
import ../packages/runtime/src/resolver-config.bend as Options
import ../packages/runtime/src/resolver-config.bend as Environment
import ../packages/runtime/src/resolver-config.bend as Load
import ../packages/runtime/src/resolver-config.bend as File
import ../packages/runtime/src/file-fold.bend as Fold
import ../packages/runtime/src/resolver-config.bend as Plan
import ../packages/runtime/src/utf8-strict.bend as UTF8
import ../packages/runtime/src/json-string.bend as Quote

def show(text: String) -> IO(Unit): IO.print(Quote.quote(text))

def main() -> IO(Unit):
  do IO<Unit>:
    show(D.file(Fold.InvalidReadSize{}))
    show(D.file(Fold.Open{2, "missing"}))
    show(D.file(Fold.Read{5, "failed"}))
    show(D.decoding(UTF8.InvalidByte{42n, 256}))
    show(D.decoding(UTF8.InvalidSequence{2n, 192}))
    show(D.decoding(UTF8.IncompleteSequence{3n}))
    show(D.transport(Plan.NoServers{}))
    show(D.transport(Plan.TooManyServers{}))
    show(D.transport(Plan.InvalidTimeout{0}))
    show(D.option(Options.Malformed{"attempts:\"bad\nvalue"}))
    show(D.option(Options.OptionsUnknown{"未知"}))
    show(D.loading(Load.Environment{Environment.EnvironmentError{"RES_OPTIONS", 5, "denied"}}))
    show(D.loading(Load.LoadFile{File.TooLarge{}}))
    show(D.loading(Load.LoadFile{File.File{Fold.Read{9, "closed"}}}))
    show(D.loading(Load.LoadFile{File.Decode{UTF8.IncompleteSequence{7n}}}))
