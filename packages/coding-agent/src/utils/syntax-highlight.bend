import Base
import ../../../runtime/src/highlight.bend as H
import ../../../runtime/src/ecma-regex.bend as Re
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/ref.bend as Ref
import ./html.bend as Html

# Syntax highlighting (upstream utils/syntax-highlight.ts) with highlight.js
# 10.7.3, ported as runtime/src/highlight.bend over its generated grammars.
#
# Upstream registers twenty common languages when the module loads and the
# remaining ones when interactive mode, after its first render, awaits
# loadAllHighlightLanguages. A Highlighter holds that registry: `create`
# registers the eager languages and `loadAllHighlightLanguages` the rest, so
# the same languages are available at the same points. Grammar data is read
# on the first highlight that can use a language and kept.
#
# A HighlightTheme maps highlight.js scopes to formatters; formatters are
# data of any type interpreted by a `format` function (upstream: functions).

def eagerLanguages() -> List<&2, String>:
  ["python", "java", "go", "javascript", "cpp", "typescript", "php", "ruby", "c", "csharp", "nix", "bash", "rust", "scala", "kotlin", "swift", "dart", "groovy", "perl", "lua"]

type Remembered is Data: Unknown{} Remembered{tokens: Maybe<&2, List<&2, H.Token>>}
type Recalled is Data: Missing{} Recent{tokens: Maybe<&2, List<&2, H.Token>>} Older{tokens: Maybe<&2, List<&2, H.Token>>}
# `recent` and `older` remember highlight.js's tokens for recently
# highlighted code (see `memoized`).
type HighlighterState is Data: HighlighterState{registry: H.Registry, grammars: H.Grammars, allLanguages: Bool, recent: Map<&2, Remembered>, older: Map<&2, Remembered>, size: Nat}
type Highlighter is Data: Highlighter{directory: String, languages: List<&2, H.LanguageInfo>, state: Ref.Ref<HighlighterState>}

def indexed(languages: List<&2, H.LanguageInfo>, +name: String) -> Maybe<&2, H.LanguageInfo>:
  match languages:
    case Nil{}: None{}
    case H.LanguageInfo{+other, aliases, disabled, superset} <> rest:
      Bool.pick(Unit -> Maybe<&2, H.LanguageInfo>, String.eq(other, name), _ => Some{H.LanguageInfo{other, aliases, disabled, superset}}, _ => indexed(rest, name))(Unit{})
def registeredIf(registry: H.Registry, info: Maybe<&2, H.LanguageInfo>) -> H.Registry:
  match info:
    case Some{found}: H.registerLanguage(registry, found)
    case None{}: registry
def registeredNamed(+languages: List<&2, H.LanguageInfo>, names: List<&2, String>, registry: H.Registry) -> H.Registry:
  match names:
    case Nil{}: registry
    case name <> rest: registeredNamed(languages, rest, registeredIf(registry, indexed(languages, name)))
def registeredAll(languages: List<&2, H.LanguageInfo>, registry: H.Registry) -> H.Registry:
  match languages:
    case Nil{}: registry
    case info <> rest: registeredAll(rest, H.registerLanguage(registry, info))
def indexLanguages(loaded: Result<&2, &2, String, List<&2, H.LanguageInfo>>) -> List<&2, H.LanguageInfo>:
  match loaded:
    case Done{languages}: languages
    case Fail{_}: Nil{}
# A highlighter over the grammar data in `directory`, with pi's eager
# languages registered.
def create(+directory: String) -> IO(Highlighter):
  do IO<Highlighter>:
    loaded : Result<&2, &2, String, List<&2, H.LanguageInfo>> <- H.loadIndex(directory)
    +languages : List<&2, H.LanguageInfo> <- IO.pure(List<&2, H.LanguageInfo>, indexLanguages(loaded))
    state : Ref.Ref<HighlighterState> <- Ref.new(HighlighterState, HighlighterState{registeredNamed(languages, eagerLanguages(), H.emptyRegistry()), H.noGrammars(), False{}, Map.new(&2, Remembered), Map.new(&2, Remembered), 0n})
    return Highlighter{directory, languages, state}
def allRegistered(languages: List<&2, H.LanguageInfo>, state: HighlighterState) -> HighlighterState & Unit:
  match state:
    case HighlighterState{registry, grammars, False{}, _, _, _}: (HighlighterState{registeredAll(languages, registry), grammars, True{}, Map.new(&2, Remembered), Map.new(&2, Remembered), 0n}, Unit{})
    case loaded: (loaded, Unit{})
# Registers every highlight.js language (once), as importing
# highlight.js/lib/index.js does upstream.
def loadAllHighlightLanguages(highlighter: Highlighter) -> IO(Unit):
  match highlighter:
    case Highlighter{_, languages, state}: Ref.modify(HighlighterState, Unit, state, current => allRegistered(languages, current))
def stateRegistry(state: HighlighterState) -> H.Registry:
  match state: case HighlighterState{registry, _, _, _, _, _}: registry
def supportsLanguage(highlighter: Highlighter, name: String) -> IO(Bool):
  match highlighter:
    case Highlighter{_, _, state}:
      do IO<Bool>:
        current : HighlighterState <- Ref.read(HighlighterState, state)
        return Bool.not(Maybe.is_none(&2, H.LanguageInfo, H.getLanguage(stateRegistry(current), name)))

# Rendering
# ---------

type HighlightOptions is Data: HighlightOptions{language: Maybe<&2, String>, ignoreIllegals: Bool, languageSubset: Maybe<&2, List<&2, String>>}

def classTokens(text: String, +current: String, +tokens: List<&2, String>) -> List<&2, String>:
  match text:
    case SNil{}: List.reverse(&2, String, String.reverse(current) <> tokens)
    case SCon{Chr{+code}, +rest}: Bool.pick(Unit -> List<&2, String>, Re.isSpaceCode(code), _ => classTokens(rest, "", String.reverse(current) <> tokens), _ => classTokens(rest, SCon{Chr{code}, current}, tokens))(Unit{})
def hljsScope(tokens: List<&2, String>) -> Maybe<&2, String>:
  match tokens:
    case Nil{}: None{}
    case +token <> rest: Bool.pick(Unit -> Maybe<&2, String>, String.starts_with(token, "hljs-"), _ => Some{String.drop(token, 5n)}, _ => hljsScope(rest))(Unit{})
# The scope of a span's class attribute: its first "hljs-" class.
def scopeOfClass(classValue: String) -> Maybe<&2, String>:
  match classValue:
    case "": None{}
    case value: hljsScope(classTokens(value, "", Nil{}))
def dotIndex(text: String, +separator: U32, +index: Nat) -> Maybe<&2, Nat>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{+code}, rest}: Bool.pick(Unit -> Maybe<&2, Nat>, U32.is_eq(code, separator), _ => Some{index}, _ => dotIndex(rest, separator, index + 1n))(Unit{})
def prefixFormatter(-F: Data, theme: R.Record<F>, +scope: String, index: Maybe<&2, Nat>) -> Maybe<&2, F>:
  match index:
    case Some{at}: R.get(F, theme, String.take(scope, at))
    case None{}: None{}
def orElse(-F: Data, first: Maybe<&2, F>, second: Maybe<&2, F>) -> Maybe<&2, F>:
  match first:
    case Some{value}: Some{value}
    case None{}: second
# The formatter of a scope: exact, else its prefix before the first ".", else
# before the first "-".
def getScopeFormatter(-F: Data, +theme: R.Record<F>, +scope: String) -> Maybe<&2, F>:
  orElse(F, R.get(F, theme, scope), orElse(F, prefixFormatter(F, theme, scope, dotIndex(scope, 46, 0n)), prefixFormatter(F, theme, scope, dotIndex(scope, 45, 0n))))
def formatterIn(-F: Data, +theme: R.Record<F>, scope: Maybe<&2, String>) -> Maybe<&2, F>:
  match scope:
    case Some{""}: None{}
    case Some{value}: getScopeFormatter(F, theme, value)
    case None{}: None{}
# The innermost scope with a formatter, else the theme's "default".
def getActiveFormatter(-F: Data, scopes: List<&2, Maybe<&2, String>>, +theme: R.Record<F>) -> Maybe<&2, F>:
  match scopes:
    case Nil{}: R.get(F, theme, "default")
    case scope <> rest: orElse(F, formatterIn(F, theme, scope), getActiveFormatter(F, rest, theme))
def applied(~F: Data, ~format: F -> String -> String, formatter: Maybe<&2, F>, text: String) -> String:
  match formatter:
    case Some{value}: format(value, text)
    case None{}: text
# Pending text (reversed) under the current scopes (innermost first).
def flushed(~F: Data, ~format: F -> String -> String, buffer: String, +scopes: List<&2, Maybe<&2, String>>, +theme: R.Record<F>, output: List<&2, String>) -> List<&2, String>:
  match buffer:
    case "": output
    case text: applied(~F, ~format, getActiveFormatter(F, scopes, theme), String.reverse(text)) <> output
def popped(scopes: List<&2, Maybe<&2, String>>) -> List<&2, Maybe<&2, String>>:
  match scopes:
    case _ <> rest: rest
    case Nil{}: Nil{}
def reversedOnto(text: String, onto: String) -> String:
  match text:
    case SNil{}: onto
    case SCon{char, rest}: reversedOnto(rest, SCon{char, onto})
def finished(output: List<&2, String>) -> String: String.join(List.reverse(&2, String, output), "")

# highlight.js's tokens (the spans of its HTML) under the theme; the same
# result as renderHighlightedHtml on the HTML value.
def tokenScope(kind: String, sublanguage: Bool) -> Maybe<&2, String>:
  match sublanguage:
    case True{}: scopeOfClass(kind)
    case False{}: scopeOfClass("hljs-" ++ kind)
def renderTokens(~F: Data, ~format: F -> String -> String, tokens: List<&2, H.Token>, +theme: R.Record<F>, buffer: String, +scopes: List<&2, Maybe<&2, String>>, output: List<&2, String>) -> String:
  match tokens:
    case Nil{}: finished(flushed(~F, ~format, buffer, scopes, theme, output))
    case H.Text{text} <> rest: renderTokens(~F, ~format, rest, theme, reversedOnto(text, buffer), scopes, output)
    case H.OpenNode{kind, sublanguage} <> rest: renderTokens(~F, ~format, rest, theme, "", tokenScope(kind, sublanguage) <> scopes, flushed(~F, ~format, buffer, scopes, theme, output))
    case H.CloseNode{} <> rest: renderTokens(~F, ~format, rest, theme, "", popped(scopes), flushed(~F, ~format, buffer, scopes, theme, output))
    case H.Embed{} <> rest: renderTokens(~F, ~format, rest, theme, buffer, scopes, output)

# renderHighlightedHtml: highlight.js HTML (spans and entities) under the
# theme; unknown markup is text.
def classPattern() -> Result<&2, &2, Re.Error, Re.RegExp>: Re.compile("\\sclass\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')", "")
def classCapture(+tag: String, captures: List<&2, Maybe<&2, Re.Span>>) -> String:
  match captures:
    case Some{span} <> _: Re.matchText(tag, span)
    case None{} <> Some{span} <> _: Re.matchText(tag, span)
    case _: ""
def classMatch(+tag: String, found: Maybe<&2, Re.Match>) -> String:
  match found:
    case Some{Re.Match{_, _, captures}}: classCapture(tag, captures)
    case None{}: ""
def classOf(pattern: Result<&2, &2, Re.Error, Re.RegExp>, +tag: String) -> String:
  match pattern:
    case Done{regex}: classMatch(tag, Re.exec(regex, tag, 0n))
    case Fail{_}: ""
def getScopeFromSpanTag(tag: String) -> Maybe<&2, String>: scopeOfClass(classOf(classPattern(), tag))
def isTagBreak(code: Maybe<&2, U32>) -> Bool:
  match code:
    case Some{62}: True{}
    case Some{32}: True{}
    case Some{9}: True{}
    case Some{10}: True{}
    case Some{13}: True{}
    case _: False{}
def headCode(text: String) -> Maybe<&2, U32>:
  match text:
    case SCon{Chr{code}, _}: Some{code}
    case SNil{}: None{}
# The length of `<span...>` at the start of `html`: "<span" then a tag break,
# with a ">" at or after the break.
def closingIndex(text: String, +index: Nat) -> Maybe<&2, Nat>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{+code}, rest}: Bool.pick(Unit -> Maybe<&2, Nat>, U32.is_eq(code, 62), _ => Some{index}, _ => closingIndex(rest, index + 1n))(Unit{})
def spanOpenLength(+html: String) -> Maybe<&2, Nat>:
  Bool.pick(Unit -> Maybe<&2, Nat>, String.starts_with(html, "<span") && isTagBreak(headCode(String.drop(html, 5n))), _ => Maybe.map(&2, Nat, Nat, at => at + 1n, closingIndex(String.drop(html, 5n), 5n)), _ => None{})(Unit{})
type HtmlStep is Data:
  SpanOpen{tag: String, rest: String}
  SpanClose{rest: String}
  Decoded{text: String, rest: String}
  Scalar{char: Char, rest: String}
  Ended{}
def entityStep(+html: String, decoded: Maybe<&2, Html.DecodedHtmlEntity>) -> HtmlStep:
  match html decoded:
    case _ Some{Html.DecodedHtmlEntity{text, length}}: Decoded{text, String.drop(html, length)}
    case SCon{char, rest} None{}: Scalar{char, rest}
    case SNil{} None{}: Ended{}
def textStep(+html: String) -> HtmlStep:
  match html:
    case SCon{Chr{38}, _}: entityStep(html, Html.decodeHtmlEntityAt(html))
    case SCon{char, rest}: Scalar{char, rest}
    case SNil{}: Ended{}
def closeStep(+html: String) -> HtmlStep:
  Bool.pick(Unit -> HtmlStep, String.starts_with(html, "</span>"), _ => SpanClose{String.drop(html, 7n)}, _ => textStep(html))(Unit{})
def openStep(+html: String, length: Maybe<&2, Nat>) -> HtmlStep:
  match length:
    case Some{+count}: SpanOpen{String.take(html, count), String.drop(html, count)}
    case None{}: closeStep(html)
def htmlStep(+html: String) -> HtmlStep: openStep(html, spanOpenLength(html))
@unsafe def renderHtml(~F: Data, ~format: F -> String -> String, step: HtmlStep, +theme: R.Record<F>, buffer: String, +scopes: List<&2, Maybe<&2, String>>, output: List<&2, String>) -> String:
  match step:
    case Ended{}: finished(flushed(~F, ~format, buffer, scopes, theme, output))
    case SpanOpen{tag, rest}: renderHtml(~F, ~format, htmlStep(rest), theme, "", getScopeFromSpanTag(tag) <> scopes, flushed(~F, ~format, buffer, scopes, theme, output))
    case SpanClose{rest}: renderHtml(~F, ~format, htmlStep(rest), theme, "", popped(scopes), flushed(~F, ~format, buffer, scopes, theme, output))
    case Decoded{text, rest}: renderHtml(~F, ~format, htmlStep(rest), theme, reversedOnto(text, buffer), scopes, output)
    case Scalar{char, rest}: renderHtml(~F, ~format, htmlStep(rest), theme, SCon{char, buffer}, scopes, output)
def renderHighlightedHtml(~F: Data, ~format: F -> String -> String, html: String, theme: R.Record<F>) -> String:
  renderHtml(~F, ~format, htmlStep(html), theme, "", Nil{}, Nil{})

# Highlighting
# ------------

def withGrammars(state: HighlighterState, grammars: H.Grammars) -> HighlighterState & Unit:
  match state: case HighlighterState{registry, _, all, recent, older, size}: (HighlighterState{registry, grammars, all, recent, older, size}, Unit{})
def stateGrammars(state: HighlighterState) -> H.Grammars:
  match state: case HighlighterState{_, grammars, _, _, _, _}: grammars
# Loads (and keeps) the grammars `names` can use; returns the registry and
# grammars to highlight with.
def prepared(highlighter: Highlighter, names: List<&2, String>) -> IO(H.Registry & H.Grammars):
  match highlighter:
    case Highlighter{directory, _, +state}:
      do IO<H.Registry & H.Grammars>:
        +current : HighlighterState <- Ref.read(HighlighterState, state)
        +registry : H.Registry <- IO.pure(H.Registry, stateRegistry(current))
        +grammars : H.Grammars <- H.prepareAll(directory, registry, stateGrammars(current), names)
        Ref.modify(HighlighterState, Unit, state, latest => withGrammars(latest, grammars))
        return (registry, grammars)
# A language highlight.js knows but whose grammar cannot be loaded fails as
# its compilation would.
def loadedInfo(info: Maybe<&2, H.LanguageInfo>, grammars: H.Grammars) -> Bool:
  match info:
    case Some{H.LanguageInfo{known, _, _, _}}: Bool.not(Maybe.is_none(&2, H.Language, H.grammarOf(grammars, known)))
    case None{}: False{}
def loadedLanguage(registry: H.Registry, grammars: H.Grammars, name: String) -> Bool: loadedInfo(H.getLanguage(registry, name), grammars)
def resultTokens(result: Maybe<&2, H.HighlightResult>) -> Maybe<&2, List<&2, H.Token>>:
  match result:
    case Some{H.HighlightResult{_, _, tokens, _}}: Some{tokens}
    case None{}: None{}
def rendered(~F: Data, ~format: F -> String -> String, tokens: Maybe<&2, List<&2, H.Token>>, theme: R.Record<F>) -> Maybe<&2, String>:
  match tokens:
    case Some{found}: Some{renderTokens(~F, ~format, found, theme, "", Nil{}, Nil{})}
    case None{}: None{}

# Streaming re-renders a message on every frame, highlighting its code blocks
# again. Once a language's grammars are loaded, highlight.js's tokens are a
# function of the registry, language, flag and code, so they are remembered
# until more languages are registered. The memory is generational: `recent`
# holds at most MEMO_SIZE entries before it becomes `older`, and an entry
# found in `older` moves back into `recent`.
def MEMO_SIZE() -> Nat: 256n
def memoKey(language: String, ignoreIllegals: Bool, code: String) -> String:
  language ++ Bool.pick(String, ignoreIllegals, "\u{0}1\u{0}", "\u{0}0\u{0}") ++ code
def recalled(recent: Remembered, older: Remembered) -> Recalled:
  match recent older:
    case Remembered{tokens} _: Recent{tokens}
    case Unknown{} Remembered{tokens}: Older{tokens}
    case Unknown{} Unknown{}: Missing{}
def lookedUp(registry: H.Registry, grammars: H.Grammars, all: Bool, recent: Map<&2, Remembered> & Remembered, older: Map<&2, Remembered> & Remembered, size: Nat) -> HighlighterState & Recalled:
  match recent older:
    case Tuple{recentMap, first} Tuple{olderMap, second}: (HighlighterState{registry, grammars, all, recentMap, olderMap, size}, recalled(first, second))
def lookup(state: HighlighterState, +key: String) -> HighlighterState & Recalled:
  match state:
    case HighlighterState{registry, grammars, all, recent, older, size}:
      lookedUp(registry, grammars, all, Map.get(Remembered, Unknown{}, recent, key), Map.get(Remembered, Unknown{}, older, key), size)
def rotated(registry: H.Registry, grammars: H.Grammars, all: Bool, recent: Map<&2, Remembered>, older: Map<&2, Remembered>, size: Nat, full: Bool) -> HighlighterState:
  match full:
    case False{}: HighlighterState{registry, grammars, all, recent, older, size}
    case True{}: HighlighterState{registry, grammars, all, Map.new(&2, Remembered), recent, 0n}
def added(state: HighlighterState, key: String, tokens: Maybe<&2, List<&2, H.Token>>) -> HighlighterState & Unit:
  match state:
    case HighlighterState{registry, grammars, all, recent, older, size}: (HighlighterState{registry, grammars, all, Map.set(&2, Remembered, recent, key, Remembered{tokens}), older, size + 1n}, Unit{})
def remembered(state: HighlighterState, key: String, tokens: Maybe<&2, List<&2, H.Token>>) -> HighlighterState & Unit:
  match state:
    case HighlighterState{registry, grammars, all, recent, older, +size}: added(rotated(registry, grammars, all, recent, older, size, Nat.is_ge(size, MEMO_SIZE())), key, tokens)
def kept(+state: Ref.Ref<HighlighterState>, +key: String, +tokens: Maybe<&2, List<&2, H.Token>>) -> IO(Maybe<&2, List<&2, H.Token>>):
  do IO<Maybe<&2, List<&2, H.Token>>>:
    Ref.modify(HighlighterState, Unit, state, current => remembered(current, key, tokens))
    return tokens
def recall(+state: Ref.Ref<HighlighterState>, +key: String, value: Recalled, compute: Unit -> Maybe<&2, List<&2, H.Token>>) -> IO(Maybe<&2, List<&2, H.Token>>):
  match value:
    case Recent{tokens}: IO.pure(Maybe<&2, List<&2, H.Token>>, tokens)
    case Older{tokens}: kept(state, key, tokens)
    case Missing{}: kept(state, key, compute(Unit{}))
def memoized(+state: Ref.Ref<HighlighterState>, +key: String, compute: Unit -> Maybe<&2, List<&2, H.Token>>) -> IO(Maybe<&2, List<&2, H.Token>>):
  do IO<Maybe<&2, List<&2, H.Token>>>:
    value : Recalled <- Ref.modify(HighlighterState, Recalled, state, current => lookup(current, key))
    recall(state, key, value, compute)
def namedTokens(+state: Ref.Ref<HighlighterState>, prepared: H.Registry & H.Grammars, +code: String, +language: String, +ignoreIllegals: Bool) -> IO(Maybe<&2, List<&2, H.Token>>):
  match prepared:
    case (+registry, +grammars):
      Bool.pick(Unit -> IO(Maybe<&2, List<&2, H.Token>>), loadedLanguage(registry, grammars, language),
        _ => memoized(state, memoKey(language, ignoreIllegals, code), _ => resultTokens(H.highlight(registry, grammars, code, language, ignoreIllegals))),
        _ => IO.pure(Maybe<&2, List<&2, H.Token>>, None{}))(Unit{})
def highlightDetected(~F: Data, ~format: F -> String -> String, prepared: H.Registry & H.Grammars, +code: String, subset: Maybe<&2, List<&2, String>>, theme: R.Record<F>) -> Maybe<&2, String>:
  match prepared:
    case (+registry, +grammars): rendered(~F, ~format, resultTokens(Some{H.highlightAuto(registry, grammars, code, subset)}), theme)
def subsetNames(+registry: H.Registry, subset: Maybe<&2, List<&2, String>>) -> List<&2, String>:
  match subset:
    case None{}: H.listLanguages(registry)
    case Some{names}: names
# highlight(code, options): hljs.highlight with a language, else
# hljs.highlightAuto over the subset; none where highlight.js throws (an
# unknown language).
def highlight(~F: Data, ~format: F -> String -> String, +highlighter: Highlighter, +code: String, options: HighlightOptions, theme: R.Record<F>) -> IO(Maybe<&2, String>):
  match options:
    case HighlightOptions{Some{+language}, ignoreIllegals, _}:
      do IO<Maybe<&2, String>>:
        ready : H.Registry & H.Grammars <- prepared(highlighter, [language])
        tokens : Maybe<&2, List<&2, H.Token>> <- namedTokens(highlighterState(highlighter), ready, code, language, ignoreIllegals)
        return rendered(~F, ~format, tokens, theme)
    case HighlightOptions{None{}, _, +subset}:
      do IO<Maybe<&2, String>>:
        current : HighlighterState <- Ref.read(HighlighterState, highlighterState(highlighter))
        ready : H.Registry & H.Grammars <- prepared(highlighter, subsetNames(stateRegistry(current), subset))
        return highlightDetected(~F, ~format, ready, code, subset, theme)
def highlighterState(highlighter: Highlighter) -> Ref.Ref<HighlighterState>:
  match highlighter: case Highlighter{_, _, state}: state
