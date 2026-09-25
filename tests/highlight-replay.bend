import Base
import ../packages/runtime/src/highlight.bend as H
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8

# Replays build/highlight/cases.jsonl ({"language", "code"} per line) through
# runtime/src/highlight.bend with every language registered, printing each
# result's HTML value as a JSON string (tests/highlight_check.py compares them
# with highlight.js).
def dataDir() -> String: "packages/runtime/data/highlight"
def registered(languages: List<&2, H.LanguageInfo>, registry: H.Registry) -> H.Registry:
  match languages:
    case Nil{}: registry
    case info <> rest: registered(rest, H.registerLanguage(registry, info))
def fromIndex(index: Result<&2, &2, String, List<&2, H.LanguageInfo>>) -> H.Registry:
  match index:
    case Done{languages}: registered(languages, H.emptyRegistry())
    case Fail{_}: H.emptyRegistry()
def shown(result: Maybe<&2, H.HighlightResult>) -> String:
  match result:
    case Some{H.HighlightResult{_, _, tokens, _}}: Json.quote(H.toHtml(tokens))
    case None{}: "null"
type Case is Data: Case{language: String, code: String}
def caseOf(value: Result<&2, &2, Json.ParseError, V.Value>) -> Maybe<&2, Case>:
  match value:
    case Done{V.ObjectValue{+fields}}: Maybe.bind(&2, String, Case, H.textOf(R.get(V.Value, fields, "language")), language => Maybe.map(&2, String, Case, code => Case{language, code}, H.textOf(R.get(V.Value, fields, "code"))))
    case _: None{}
def splitLines(text: String, +current: String, +parts: List<&2, String>) -> List<&2, String>:
  match text:
    case SNil{}: List.reverse(&2, String, String.reverse(current) <> parts)
    case SCon{Chr{+code}, +rest}: Bool.pick(Unit -> List<&2, String>, U32.is_eq(code, 10), _ => splitLines(rest, "", String.reverse(current) <> parts), _ => splitLines(rest, SCon{Chr{code}, current}, parts))(Unit{})
@unsafe def replay(+registry: H.Registry, grammars: H.Grammars, current: Maybe<&2, Case>, lines: List<&2, String>) -> IO(Unit):
  match current lines:
    case Some{Case{+language, code}} rest:
      do IO<Unit>:
        +loaded : H.Grammars <- H.prepare(dataDir(), registry, grammars, language)
        IO.print(shown(H.highlight(registry, loaded, code, language, True{})))
        replay(registry, loaded, None{}, rest)
    case None{} Nil{}: IO.pure(Unit, Unit{})
    case None{} line <> rest: replay(registry, grammars, caseOf(Json.parse(line)), rest)
def main() -> IO(Unit):
  do IO<Unit>:
    index : Result<&2, &2, String, List<&2, H.LanguageInfo>> <- H.loadIndex(dataDir())
    bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile("build/highlight/cases.jsonl")
    replay(fromIndex(index), H.noGrammars(), None{}, splitLines(Utf8.decodeBytes(Result.default(&2, &2, FS.Error, List<&2, U32>, bytes, Nil{})), "", Nil{}))
