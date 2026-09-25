import Base
import ../packages/runtime/src/highlight.bend as H
import ../packages/runtime/src/clock.bend as Clock
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8

# Times highlight.bend on the JavaScript lane: loading a grammar, then
# highlighting the code in build/highlight/bench.txt (language in
# build/highlight/bench-language.txt) ten times.
def dataDir() -> String: "packages/runtime/data/highlight"
def registered(languages: List<&2, H.LanguageInfo>, registry: H.Registry) -> H.Registry:
  match languages:
    case Nil{}: registry
    case info <> rest: registered(rest, H.registerLanguage(registry, info))
def fromIndex(index: Result<&2, &2, String, List<&2, H.LanguageInfo>>) -> H.Registry:
  match index:
    case Done{languages}: registered(languages, H.emptyRegistry())
    case Fail{_}: H.emptyRegistry()
def tokenCount(result: Maybe<&2, H.HighlightResult>) -> Nat:
  match result:
    case Some{H.HighlightResult{_, _, tokens, _}}: List.length(&2, H.Token, tokens)
    case None{}: 0n
def repeat(count: Nat, +registry: H.Registry, +grammars: H.Grammars, +code: String, +language: String, total: Nat) -> Nat:
  match count:
    case Zero{}: total
    case Succ{more}: repeat(more, registry, grammars, code, language, total + tokenCount(H.highlight(registry, grammars, code, language, True{})))
def text(bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> String: Utf8.decodeBytes(Result.default(&2, &2, FS.Error, List<&2, U32>, bytes, Nil{}))
def trimmed(value: String) -> String: String.trim(value)
def main() -> IO(Unit):
  do IO<Unit>:
    +clock : Clock.Clock <- Clock.new()
    index : Result<&2, &2, String, List<&2, H.LanguageInfo>> <- H.loadIndex(dataDir())
    +registry : H.Registry <- IO.pure(H.Registry, fromIndex(index))
    codeBytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile("build/highlight/bench.txt")
    languageBytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile("build/highlight/bench-language.txt")
    +code : String <- IO.pure(String, text(codeBytes))
    +language : String <- IO.pure(String, trimmed(text(languageBytes)))
    start : F64 <- Clock.now(clock)
    +grammars : H.Grammars <- H.prepare(dataDir(), registry, H.noGrammars(), language)
    +loaded : F64 <- Clock.now(clock)
    +tokens : Nat <- IO.pure(Nat, repeat(10n, registry, grammars, code, language, 0n))
    done : F64 <- Clock.now(clock)
    IO.print("load " ++ language ++ " grammar: " ++ F64.show(F64.sub(loaded, start)) ++ " ms")
    IO.print("highlight x10: " ++ F64.show(F64.sub(done, loaded)) ++ " ms (" ++ Nat.show(tokens) ++ " tokens)")
