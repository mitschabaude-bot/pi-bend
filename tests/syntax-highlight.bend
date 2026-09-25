import Base
import ../packages/coding-agent/src/utils/syntax-highlight.bend as SH
import ../packages/runtime/src/highlight.bend as H
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/modes/interactive/theme/markdown-theme.bend as Styles
import ../packages/tui/src/components/markdown.bend as Markdown
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8

# pi's syntax highlighting against upstream syntax-highlight.ts and theme.ts
# (tests/syntax_highlight_reference.ts): each line of
# build/syntax-highlight/cases.jsonl is one case, printed as a JSON value.
# "eager" cases run before loadAllHighlightLanguages, the others after it.

def dataDir() -> String: "packages/runtime/data/highlight"
# The marker theme: every scope formatter wraps text as [scope:text].
def marked(scope: String, text: String) -> String: "[" ++ scope ++ ":" ++ text ++ "]"
def markerKeys() -> List<&2, String>:
  ["keyword", "built_in", "type", "literal", "number", "regexp", "string", "subst", "symbol", "class", "function", "title", "params", "comment", "doctag", "meta", "section", "tag", "name", "attr", "attribute", "variable", "bullet", "code", "emphasis", "strong", "formula", "link", "quote", "selector", "template", "addition", "deletion", "operator", "punctuation"]
def markerEntries(keys: List<&2, String>, record: R.Record<String>) -> R.Record<String>:
  match keys:
    case Nil{}: record
    case +key <> rest: markerEntries(rest, R.set(String, record, key, key))
def markerTheme(withDefault: Bool) -> R.Record<String>:
  match withDefault:
    case True{}: R.set(String, markerEntries(markerKeys(), R.new(String)), "default", "default")
    case False{}: markerEntries(markerKeys(), R.new(String))
def quotedLines(lines: List<&2, String>, reversed: List<&2, String>) -> String:
  match lines:
    case Nil{}: "[" ++ String.join(List.reverse(&2, String, reversed), ",") ++ "]"
    case line <> rest: quotedLines(rest, Json.quote(line) <> reversed)
def maybeText(value: Maybe<&2, String>) -> String:
  match value:
    case Some{text}: Json.quote(text)
    case None{}: "null"
def boolText(value: Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"

type Case is Data:
  Highlight{language: Maybe<&2, String>, code: String, withDefault: Bool}
  HighlightCode{language: Maybe<&2, String>, code: String}
  MarkdownCase{text: String}
  PathCase{path: String}
  HtmlCase{html: String}
  Supports{language: String}
  LoadAll{}
  Skip{}
def text(fields: R.Record<V.Value>, key: String) -> String: Maybe.default(&2, String, H.textOf(R.get(V.Value, fields, key)), "")
def caseFrom(kind: String, +fields: R.Record<V.Value>) -> Case:
  match kind:
    case "highlight": Highlight{H.textOf(R.get(V.Value, fields, "language")), text(fields, "code"), H.truthy(R.get(V.Value, fields, "default"))}
    case "highlightCode": HighlightCode{H.textOf(R.get(V.Value, fields, "language")), text(fields, "code")}
    case "markdown": MarkdownCase{text(fields, "text")}
    case "path": PathCase{text(fields, "path")}
    case "html": HtmlCase{text(fields, "html")}
    case "supports": Supports{text(fields, "language")}
    case "loadAll": LoadAll{}
    case _: Skip{}
def caseOf(value: Result<&2, &2, Json.ParseError, V.Value>) -> Case:
  match value:
    case Done{V.ObjectValue{+fields}}: caseFrom(text(fields, "kind"), fields)
    case _: Skip{}

def markdownLines(pair: Markdown.Markdown & List<&2, String>) -> String:
  match pair:
    case (_, lines): quotedLines(lines, Nil{})
def ran(+highlighter: SH.Highlighter, +theme: Theme.Theme, +markdown: Markdown.MarkdownTheme, item: Case) -> IO(Unit):
  match item:
    case Highlight{language, code, withDefault}:
      do IO<Unit>:
        result : Maybe<&2, String> <- SH.highlight(~String, ~marked, highlighter, code, SH.HighlightOptions{language, True{}, None{}}, markerTheme(withDefault))
        IO.print(maybeText(result))
    case HighlightCode{language, code}:
      do IO<Unit>:
        lines : List<&2, String> <- Theme.highlightCode(highlighter, theme, code, language)
        IO.print(quotedLines(lines, Nil{}))
    case MarkdownCase{source}:
      do IO<Unit>:
        pair : Markdown.Markdown & List<&2, String> <- Markdown.render(Markdown.new(source, 1n, 0n, markdown, None{}, None{}), 60n)
        IO.print(markdownLines(pair))
    case PathCase{path}: IO.print(maybeText(Theme.getLanguageFromPath(path)))
    case HtmlCase{html}: IO.print(Json.quote(SH.renderHighlightedHtml(~String, ~marked, html, markerTheme(False{}))))
    case Supports{language}:
      do IO<Unit>:
        supported : Bool <- SH.supportsLanguage(highlighter, language)
        IO.print(boolText(supported))
    case LoadAll{}:
      do IO<Unit>:
        SH.loadAllHighlightLanguages(highlighter)
        IO.print("null")
    case Skip{}: IO.pure(Unit, Unit{})
def splitLines(text: String, +current: String, +parts: List<&2, String>) -> List<&2, String>:
  match text:
    case SNil{}: List.reverse(&2, String, String.reverse(current) <> parts)
    case SCon{Chr{+code}, +rest}: Bool.pick(Unit -> List<&2, String>, U32.is_eq(code, 10), _ => splitLines(rest, "", String.reverse(current) <> parts), _ => splitLines(rest, SCon{Chr{code}, current}, parts))(Unit{})
def runAll(+highlighter: SH.Highlighter, +theme: Theme.Theme, +markdown: Markdown.MarkdownTheme, lines: List<&2, String>) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit, Unit{})
    case "" <> rest: runAll(highlighter, theme, markdown, rest)
    case line <> rest:
      do IO<Unit>:
        ran(highlighter, theme, markdown, caseOf(Json.parse(line)))
        runAll(highlighter, theme, markdown, rest)
def withStyles(+highlighter: SH.Highlighter, +theme: Theme.Theme, pair: Styles.Styles & Markdown.MarkdownTheme, lines: List<&2, String>) -> IO(Unit):
  match pair:
    case (styles, markdown):
      do IO<Unit>:
        runAll(highlighter, theme, markdown, lines)
        Styles.dispose(styles)
def loaded(result: Result<&2, &2, Theme.LoadError, Theme.Theme>, lines: List<&2, String>) -> IO(Unit):
  match result:
    case Done{+theme}:
      do IO<Unit>:
        +highlighter : SH.Highlighter <- SH.create(dataDir())
        styles : Styles.Styles <- Styles.create(theme, highlighter)
        withStyles(highlighter, theme, Styles.borrow(styles), lines)
    case Fail{_}: IO.die(Unit, 1, "theme failed to load")
def main() -> IO(Unit):
  do IO<Unit>:
    bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile("build/syntax-highlight/cases.jsonl")
    result : Result<&2, &2, Theme.LoadError, Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json", Color.TrueColor{})
    loaded(result, splitLines(Utf8.decodeBytes(Result.default(&2, &2, FS.Error, List<&2, U32>, bytes, Nil{})), "", Nil{}))
