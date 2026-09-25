import Base
import ../packages/runtime/src/highlight.bend as H

# Every generated grammar decodes and all of its patterns compile with
# runtime/src/ecma-regex.bend.
def dataDir() -> String: "packages/runtime/data/highlight"
def reported(loaded: Result<&2, &2, String, H.Language>, name: String) -> IO(Nat):
  match loaded:
    case Done{_}: IO.pure(Nat, 0n)
    case Fail{message}:
      do IO<Nat>:
        IO.print("FAIL " ++ name ++ ": " ++ message)
        return 1n
def checkAll(languages: List<&2, H.LanguageInfo>, failures: Nat) -> IO(Nat):
  match languages:
    case Nil{}: IO.pure(Nat, failures)
    case H.LanguageInfo{+name, _, _, _} <> rest:
      do IO<Nat>:
        loaded : Result<&2, &2, String, H.Language> <- H.loadLanguage(dataDir(), name)
        +failed : Nat <- reported(loaded, name)
        checkAll(rest, failures + failed)
def summary(index: Result<&2, &2, String, H.Index>) -> IO(Unit):
  match index:
    case Fail{message}: IO.die(Unit, 1, "index: " ++ message)
    case Done{H.Index{languages, _}}:
      do IO<Unit>:
        +failures : Nat <- checkAll(languages, 0n)
        Bool.pick(Unit -> IO(Unit), Nat.is_eq(failures, 0n), _ => IO.print("all grammars load"), _ => IO.die(Unit, 1, Nat.show(failures) ++ " grammars fail to load"))(Unit{})
def main() -> IO(Unit):
  do IO<Unit>:
    index : Result<&2, &2, String, H.Index> <- H.loadIndex(dataDir())
    summary(index)
