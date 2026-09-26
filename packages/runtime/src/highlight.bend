import Base
import ./ecma-regex.bend as Re
import ./json.bend as Json
import ./schema-value.bend as V
import ./record.bend as R
import ./u32-table.bend as Table
import ./case-map.bend as Case
import ./filesystem.bend as FS
import ./utf8.bend as Utf8
import ./posix-path.bend as Path
import ./stable-sort.bend as Sort
import ./f64.bend as F

# highlight.js 10.7.3 (the highlighter pi uses) over its compiled grammars.
#
# highlight.js grammars are JavaScript functions compiled lazily into a graph
# of modes. scripts/generate-highlight-languages.mjs lets highlight.js compile
# all 191 of them and serializes that graph to packages/runtime/data/highlight;
# this module decodes a grammar per language on demand and runs
# highlight.js's `_highlight` lexer over it: the resumable multi-regex matcher,
# mode begin/end/illegal handling, keywords, relevance, sub-languages with
# continuations, `highlightAuto`, and the TokenTree emitter.
#
# Language-driven differences, each with the same observable output:
# - highlight.js joins a mode's rules into one alternation regex; here each
#   rule is tried in order at each position, which is what the alternation
#   does. The grammars have no named groups and every backreference refers to
#   a group of its own rule, so join()'s renumbering is the identity on them.
# - Mutable compiled-mode state (the matcher's regexIndex and lastIndex, and
#   the END_SAME_AS_BEGIN `data._beginMatch`) is explicit state of a run.
# - A sub-language buffer is highlighted after the host run's main loop, in
#   the order highlight.js would have highlighted it; its tokens replace a
#   placeholder. Continuations and relevance are threaded in the same order.
# - Indices count Unicode scalars instead of UTF-16 code units.

# Grammar
# -------

# The five callbacks highlight.js grammars attach to modes.
type Keyword is Data: Keyword{kind: String, relevance: F64}
type WordEntry is Data: WordEntry{word: String, keyword: Keyword}
type Words is Data: Words{buckets: Table.Table<List<&2, WordEntry>>}
type Callback is Data:
  SkipIfHasPrecedingDot{}
  Shebang{}
  EndSameAsBegin{}
  JsxOpeningTag{}
  SystemSymbol{symbols: Words}
type SubLanguage is Data:
  Named{name: String}
  Detect{names: List<&2, String>}
type Rule is Data: Rule{regex: Re.RegExp, start: Re.Start}
type TerminatorKind is Data:
  BeginOf{mode: Nat}
  EndOf{}
  IllegalOf{}
type Terminator is Data: Terminator{rule: Rule, kind: TerminatorKind}
# A rule with its index in the matcher. A Scanner lists, for each ASCII
# scalar, the rules whose match can begin with it, plus those that can begin
# with a wider scalar and those that can match at the end of the input, each
# in rule order. Trying only these at a position gives the result of trying
# every rule there.
type Candidate is Data: Candidate{position: Nat, terminator: Terminator}
type Scanner is Data:
  Dispatch{ascii: Table.Table<List<&2, Candidate>>, wide: List<&2, Candidate>, ending: List<&2, Candidate>}
  Single{candidate: Candidate}
type Flags is Data: Flags{excludeBegin: Bool, excludeEnd: Bool, returnBegin: Bool, returnEnd: Bool, endsWithParent: Bool, endsParent: Bool, skip: Bool}
# A compiled mode; `keywordPattern` scans for keyword candidates.
type Mode is Data:
  Mode{className: String, begin: Maybe<&2, Rule>, end: Maybe<&2, Rule>, terminatorEnd: Maybe<&2, Rule>, illegal: Maybe<&2, Rule>, keywords: Maybe<&2, Words>, keywordPattern: Scanner, relevance: F64, flags: Flags, subLanguage: Maybe<&2, SubLanguage>, beforeBegin: Maybe<&2, Callback>, onBegin: Maybe<&2, Callback>, onEnd: Maybe<&2, Callback>, contains: List<&2, Nat>, starts: Maybe<&2, Nat>}
# A mode's ResumableMultiRegex rules: the begins of its contained modes, then
# its terminator end and illegal pattern. `count` is the number of begins.
type Matcher is Data: Matcher{rules: List<&2, Terminator>, count: Nat, scanner: Scanner}
type Language is Data:
  Language{name: String, caseInsensitive: Bool, classNameAliases: R.Record<String>, modes: Table.Table<Mode>, matchers: Table.Table<Matcher>, subLanguages: List<&2, SubLanguage>}

# Word tables
# -----------
# Keyword dictionaries (and Mathematica's symbol set) hash each word into a
# balanced table of buckets.

def hashFrom(text: String, +hash: U32) -> U32:
  match text:
    case SNil{}: hash
    case SCon{Chr{code}, rest}: hashFrom(rest, U32.mul(U32.xor(hash, code), 16777619))
def hashOf(text: String) -> U32: hashFrom(text, 2166136261)
type Keyed is Data: Keyed{hash: U32, entry: WordEntry}
def keyedLe(left: Keyed, right: Keyed) -> Bool:
  match left right:
    case Keyed{a, _} Keyed{b, _}: U32.is_le(a, b)
def keyedAll(entries: List<&2, WordEntry>, reversed: List<&2, Keyed>) -> List<&2, Keyed>:
  match entries:
    case Nil{}: List.reverse(&2, Keyed, reversed)
    case WordEntry{+word, keyword} <> rest: keyedAll(rest, Keyed{hashOf(word), WordEntry{word, keyword}} <> reversed)
# A later duplicate word replaces an earlier one, as assignment to a
# JavaScript object does.
def withoutWord(entries: List<&2, WordEntry>, +word: String) -> List<&2, WordEntry>:
  match entries:
    case Nil{}: Nil{}
    case WordEntry{+other, keyword} <> +rest:
      Bool.pick(Unit -> List<&2, WordEntry>, String.eq(other, word), _ => rest, _ => WordEntry{other, keyword} <> withoutWord(rest, word))(Unit{})
def bucketed(keyed: List<&2, Keyed>, +current: U32, +bucket: List<&2, WordEntry>, +reversed: List<&2, Table.Entry<List<&2, WordEntry>>>) -> List<&2, Table.Entry<List<&2, WordEntry>>>:
  match keyed bucket:
    case Nil{} Nil{}: List.reverse(&2, Table.Entry<List<&2, WordEntry>>, reversed)
    case Nil{} _: List.reverse(&2, Table.Entry<List<&2, WordEntry>>, Table.Entry{current, bucket} <> reversed)
    case Keyed{+hash, WordEntry{+word, +keyword}} <> +rest Nil{}: bucketed(rest, hash, [WordEntry{word, keyword}], reversed)
    case Keyed{+hash, WordEntry{+word, +keyword}} <> +rest _:
      Bool.pick(Unit -> List<&2, Table.Entry<List<&2, WordEntry>>>, U32.is_eq(hash, current),
        _ => bucketed(rest, hash, WordEntry{word, keyword} <> withoutWord(bucket, word), reversed),
        _ => bucketed(rest, hash, [WordEntry{word, keyword}], Table.Entry{current, bucket} <> reversed))(Unit{})
def wordsOf(entries: List<&2, WordEntry>) -> Words:
  Words{Table.fromSortedEntries(List<&2, WordEntry>, bucketed(Sort.sort(~Keyed, ~keyedLe, keyedAll(entries, Nil{})), 0, Nil{}, Nil{}))}
def found(entries: List<&2, WordEntry>, +word: String) -> Maybe<&2, Keyword>:
  match entries:
    case Nil{}: None{}
    case WordEntry{other, keyword} <> rest: Bool.pick(Unit -> Maybe<&2, Keyword>, String.eq(other, word), _ => Some{keyword}, _ => found(rest, word))(Unit{})
def lookup(words: Words, +word: String) -> Maybe<&2, Keyword>:
  match words:
    case Words{buckets}: found(Maybe.default(&2, List<&2, WordEntry>, Table.get(List<&2, WordEntry>, buckets, hashOf(word)), Nil{}), word)

# Decoding
# --------
# Grammar files hold highlight.js's compiled modes: regex sources (compiled
# here with langRe's flags), compiled keyword lists and the mode graph.

def Loaded(-A: Data) -> Data: Result<&2, &2, String, A>

def truthy(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.Boolean{True{}}}: True{}
    case _: False{}
def textOf(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{text}}: Some{text}
    case _: None{}
def numberOf(value: V.Value) -> Loaded(F64):
  match value:
    case V.Number{number}: Done{number}
    case _: Fail{"expected a number"}
def naturalOf(value: V.Value) -> Loaded(Nat):
  match value:
    case V.Number{number}: Done{U32.to_nat(F64.to_u32(number))}
    case _: Fail{"expected a number"}
def optionalNatural(value: Maybe<&2, V.Value>) -> Loaded(Maybe<&2, Nat>):
  match value:
    case None{}: Done{None{}}
    case Some{present}: Result.map(&2, &2, String, Nat, Maybe<&2, Nat>, number => Some{number}, naturalOf(present))
def arrayOf(value: Maybe<&2, V.Value>) -> Loaded(List<&2, V.Value>):
  match value:
    case Some{V.ArrayValue{values}}: Done{values}
    case None{}: Done{Nil{}}
    case _: Fail{"expected an array"}
def objectOf(value: V.Value) -> Loaded(R.Record<V.Value>):
  match value:
    case V.ObjectValue{fields}: Done{fields}
    case _: Fail{"expected an object"}
def textsFrom(values: List<&2, V.Value>, reversed: List<&2, String>) -> Loaded(List<&2, String>):
  match values:
    case Nil{}: Done{List.reverse(&2, String, reversed)}
    case V.Text{text} <> rest: textsFrom(rest, text <> reversed)
    case _: Fail{"expected a string"}
def naturalsFrom(values: List<&2, V.Value>, reversed: List<&2, Nat>) -> Loaded(List<&2, Nat>):
  match values:
    case Nil{}: Done{List.reverse(&2, Nat, reversed)}
    case V.Number{number} <> rest: naturalsFrom(rest, U32.to_nat(F64.to_u32(number)) <> reversed)
    case _: Fail{"expected a number"}

def ruleFrom(source: String, compiled: Result<&2, &2, Re.Error, Re.RegExp>) -> Loaded(Rule):
  match compiled:
    case Done{+regex}: Done{Rule{regex, Re.startOf(regex)}}
    case Fail{Re.SyntaxError{message}}: Fail{"invalid pattern /" ++ source ++ "/: " ++ message}
def ruleOf(+source: String, flags: String) -> Loaded(Rule): ruleFrom(source, Re.compile(source, flags))
def optionalRule(source: Maybe<&2, String>, flags: String) -> Loaded(Maybe<&2, Rule>):
  match source:
    case None{}: Done{None{}}
    case Some{""}: Done{None{}}
    case Some{text}: Result.map(&2, &2, String, Rule, Maybe<&2, Rule>, rule => Some{rule}, ruleOf(text, flags))

def wordEntries(values: List<&2, V.Value>, reversed: List<&2, WordEntry>) -> Loaded(List<&2, WordEntry>):
  match values:
    case Nil{}: Done{List.reverse(&2, WordEntry, reversed)}
    case V.ArrayValue{V.Text{word} <> V.Text{kind} <> V.Number{relevance} <> Nil{}} <> rest: wordEntries(rest, WordEntry{word, Keyword{kind, relevance}} <> reversed)
    case V.ArrayValue{V.Text{word} <> V.Text{kind} <> V.Text{"NaN"} <> Nil{}} <> rest: wordEntries(rest, WordEntry{word, Keyword{kind, F.nan()}} <> reversed)
    case _: Fail{"invalid keyword entry"}
def keywordTable(value: V.Value) -> Loaded(Words):
  match value:
    case V.ArrayValue{values}: Result.map(&2, &2, String, List<&2, WordEntry>, Words, wordsOf, wordEntries(values, Nil{}))
    case _: Fail{"invalid keyword table"}
def keywordTables(values: List<&2, V.Value>, reversed: List<&2, Words>) -> Loaded(List<&2, Words>):
  match values:
    case Nil{}: Done{List.reverse(&2, Words, reversed)}
    case value <> rest:
      do Result<&2, &2, String, List<&2, Words>>:
        table : Words <- keywordTable(value)
        keywordTables(rest, table <> reversed)
def tableAt(table: Maybe<&2, Words>) -> Loaded(Maybe<&2, Words>):
  match table:
    case Some{words}: Done{Some{words}}
    case None{}: Fail{"missing keyword table"}
def keywordsAt(index: Maybe<&2, Nat>, tables: List<&2, Words>) -> Loaded(Maybe<&2, Words>):
  match index:
    case None{}: Done{None{}}
    case Some{at}: tableAt(List.get(&2, Words, tables, at))

def symbolEntries(words: List<&2, String>, reversed: List<&2, WordEntry>) -> List<&2, WordEntry>:
  match words:
    case Nil{}: List.reverse(&2, WordEntry, reversed)
    case word <> rest: symbolEntries(rest, WordEntry{word, Keyword{"", U32.to_f64(0)}} <> reversed)
def symbolsOf(value: Maybe<&2, V.Value>) -> Loaded(Callback):
  do Result<&2, &2, String, Callback>:
    values : List<&2, V.Value> <- arrayOf(value)
    words : List<&2, String> <- textsFrom(values, Nil{})
    return SystemSymbol{wordsOf(symbolEntries(words, Nil{}))}
def namedCallback(name: Maybe<&2, String>, +fields: R.Record<V.Value>) -> Loaded(Callback):
  match name:
    case Some{"skipIfHasPrecedingDot"}: Done{SkipIfHasPrecedingDot{}}
    case Some{"shebang"}: Done{Shebang{}}
    case Some{"endSameAsBegin"}: Done{EndSameAsBegin{}}
    case Some{"jsxOpeningTag"}: Done{JsxOpeningTag{}}
    case Some{"systemSymbol"}: symbolsOf(R.get(V.Value, fields, "symbols"))
    case _: Fail{"unknown callback"}
def callbackOf(value: Maybe<&2, V.Value>) -> Loaded(Maybe<&2, Callback>):
  match value:
    case None{}: Done{None{}}
    case Some{V.ObjectValue{+fields}}: Result.map(&2, &2, String, Callback, Maybe<&2, Callback>, callback => Some{callback}, namedCallback(textOf(R.get(V.Value, fields, "name")), fields))
    case _: Fail{"invalid callback"}
def subLanguageOf(value: Maybe<&2, V.Value>) -> Loaded(Maybe<&2, SubLanguage>):
  match value:
    case None{}: Done{None{}}
    case Some{V.Text{name}}: Done{Some{Named{name}}}
    case Some{V.ArrayValue{values}}: Result.map(&2, &2, String, List<&2, String>, Maybe<&2, SubLanguage>, names => Some{Detect{names}}, textsFrom(values, Nil{}))
    case _: Fail{"invalid subLanguage"}
def relevanceOf(value: Maybe<&2, V.Value>) -> Loaded(F64):
  match value:
    case None{}: Done{U32.to_f64(0)}
    case Some{number}: numberOf(number)
def flagsOf(+fields: R.Record<V.Value>) -> Flags:
  Flags{truthy(R.get(V.Value, fields, "excludeBegin")), truthy(R.get(V.Value, fields, "excludeEnd")), truthy(R.get(V.Value, fields, "returnBegin")), truthy(R.get(V.Value, fields, "returnEnd")), truthy(R.get(V.Value, fields, "endsWithParent")), truthy(R.get(V.Value, fields, "endsParent")), truthy(R.get(V.Value, fields, "skip"))}

def numbered(rules: List<&2, Terminator>, +position: Nat, reversed: List<&2, Candidate>) -> List<&2, Candidate>:
  match rules:
    case Nil{}: List.reverse(&2, Candidate, reversed)
    case rule <> rest: numbered(rest, position + 1n, Candidate{position, rule} <> reversed)
def startAdmits(start: Re.Start, +code: U32) -> Bool:
  match start: case Re.Start{nullable, _, ascii, _, _, _}: nullable || Re.asciiHas(ascii, code)
def candidateStart(candidate: Candidate) -> Re.Start:
  match candidate: case Candidate{_, Terminator{Rule{_, start}, _}}: start
def admittingCode(candidates: List<&2, Candidate>, +code: U32, +reversed: List<&2, Candidate>) -> List<&2, Candidate>:
  match candidates:
    case Nil{}: List.reverse(&2, Candidate, reversed)
    case +candidate <> rest: admittingCode(rest, code, Bool.pick(List<&2, Candidate>, startAdmits(candidateStart(candidate), code), candidate <> reversed, reversed))
def asciiEntries(count: Nat, +code: U32, +candidates: List<&2, Candidate>, reversed: List<&2, Table.Entry<List<&2, Candidate>>>) -> List<&2, Table.Entry<List<&2, Candidate>>>:
  match count:
    case Zero{}: List.reverse(&2, Table.Entry<List<&2, Candidate>>, reversed)
    case Succ{more}: asciiEntries(more, (code + 1 : U32), candidates, Table.Entry{code, admittingCode(candidates, code, Nil{})} <> reversed)
def startWide(start: Re.Start) -> Bool:
  match start: case Re.Start{nullable, _, _, wide, _, _}: nullable || wide
def admittingWide(candidates: List<&2, Candidate>, +reversed: List<&2, Candidate>) -> List<&2, Candidate>:
  match candidates:
    case Nil{}: List.reverse(&2, Candidate, reversed)
    case +candidate <> rest: admittingWide(rest, Bool.pick(List<&2, Candidate>, startWide(candidateStart(candidate)), candidate <> reversed, reversed))
# Whether a rule may match at the end of the input.
def startEnds(start: Re.Start) -> Bool:
  match start: case Re.Start{nullable, _, _, _, _, ends}: nullable || ends
def admittingEnd(candidates: List<&2, Candidate>, +reversed: List<&2, Candidate>) -> List<&2, Candidate>:
  match candidates:
    case Nil{}: List.reverse(&2, Candidate, reversed)
    case +candidate <> rest: admittingEnd(rest, Bool.pick(List<&2, Candidate>, startEnds(candidateStart(candidate)), candidate <> reversed, reversed))
def dispatchOf(rules: List<&2, Terminator>) -> Scanner:
  +candidates = numbered(rules, 0n, Nil{})
  Dispatch{Table.fromSortedEntries(List<&2, Candidate>, asciiEntries(128n, 0, candidates, Nil{})), admittingWide(candidates, Nil{}), admittingEnd(candidates, Nil{})}
# A lone rule (a keyword pattern) is checked against its start directly.
def scannerOf(rules: List<&2, Terminator>) -> Scanner:
  match rules:
    case rule <> Nil{}: Single{Candidate{0n, rule}}
    case rules: dispatchOf(rules)

def modeFrom(+fields: R.Record<V.Value>, +flags: String, tables: List<&2, Words>) -> Loaded(Mode):
  do Result<&2, &2, String, Mode>:
    begin : Maybe<&2, Rule> <- optionalRule(textOf(R.get(V.Value, fields, "begin")), flags)
    end : Maybe<&2, Rule> <- optionalRule(textOf(R.get(V.Value, fields, "end")), flags)
    terminatorEnd : Maybe<&2, Rule> <- optionalRule(textOf(R.get(V.Value, fields, "terminatorEnd")), flags)
    illegal : Maybe<&2, Rule> <- optionalRule(textOf(R.get(V.Value, fields, "illegal")), flags)
    index : Maybe<&2, Nat> <- optionalNatural(R.get(V.Value, fields, "keywords"))
    keywords : Maybe<&2, Words> <- keywordsAt(index, tables)
    pattern : Rule <- ruleOf(Maybe.default(&2, String, textOf(R.get(V.Value, fields, "keywordPattern")), "\\w+"), flags)
    relevance : F64 <- relevanceOf(R.get(V.Value, fields, "relevance"))
    subLanguage : Maybe<&2, SubLanguage> <- subLanguageOf(R.get(V.Value, fields, "subLanguage"))
    beforeBegin : Maybe<&2, Callback> <- callbackOf(R.get(V.Value, fields, "beforeBegin"))
    onBegin : Maybe<&2, Callback> <- callbackOf(R.get(V.Value, fields, "onBegin"))
    onEnd : Maybe<&2, Callback> <- callbackOf(R.get(V.Value, fields, "onEnd"))
    containsValues : List<&2, V.Value> <- arrayOf(R.get(V.Value, fields, "contains"))
    contains : List<&2, Nat> <- naturalsFrom(containsValues, Nil{})
    starts : Maybe<&2, Nat> <- optionalNatural(R.get(V.Value, fields, "starts"))
    return Mode{Maybe.default(&2, String, textOf(R.get(V.Value, fields, "className")), ""), begin, end, terminatorEnd, illegal, keywords, scannerOf([Terminator{pattern, EndOf{}}]), relevance, flagsOf(fields), subLanguage, beforeBegin, onBegin, onEnd, contains, starts}
def modesFrom(values: List<&2, V.Value>, +flags: String, +tables: List<&2, Words>, +id: Nat, reversed: List<&2, Table.Entry<Mode>>) -> Loaded(List<&2, Table.Entry<Mode>>):
  match values:
    case Nil{}: Done{List.reverse(&2, Table.Entry<Mode>, reversed)}
    case value <> rest:
      do Result<&2, &2, String, List<&2, Table.Entry<Mode>>>:
        fields : R.Record<V.Value> <- objectOf(value)
        mode : Mode <- modeFrom(fields, flags, tables)
        modesFrom(rest, flags, tables, id + 1n, Table.Entry{U32.from_nat(id), mode} <> reversed)

def modeBegin(mode: Maybe<&2, Mode>) -> Maybe<&2, Rule>:
  match mode:
    case Some{Mode{_, begin, _, _, _, _, _, _, _, _, _, _, _, _, _}}: begin
    case None{}: None{}
def withBegin(rule: Maybe<&2, Rule>, id: Nat, reversed: List<&2, Terminator>) -> List<&2, Terminator>:
  match rule:
    case Some{value}: Terminator{value, BeginOf{id}} <> reversed
    case None{}: reversed
def beginRules(contains: List<&2, Nat>, +modes: Table.Table<Mode>, reversed: List<&2, Terminator>) -> List<&2, Terminator>:
  match contains:
    case Nil{}: List.reverse(&2, Terminator, reversed)
    case +id <> rest: beginRules(rest, modes, withBegin(modeBegin(Table.get(Mode, modes, U32.from_nat(id))), id, reversed))
def optionalTerminator(rule: Maybe<&2, Rule>, kind: TerminatorKind) -> List<&2, Terminator>:
  match rule:
    case None{}: Nil{}
    case Some{value}: [Terminator{value, kind}]
def matcherOf(mode: Mode, +modes: Table.Table<Mode>) -> Matcher:
  match mode:
    case Mode{_, _, _, terminatorEnd, illegal, _, _, _, _, _, _, _, _, contains, _}:
      +begins = beginRules(contains, modes, Nil{})
      +rules = List.append(&2, Terminator, begins, List.append(&2, Terminator, optionalTerminator(terminatorEnd, EndOf{}), optionalTerminator(illegal, IllegalOf{})))
      Matcher{rules, List.length(&2, Terminator, begins), scannerOf(rules)}
def matchersOf(entries: List<&2, Table.Entry<Mode>>, +modes: Table.Table<Mode>, reversed: List<&2, Table.Entry<Matcher>>) -> List<&2, Table.Entry<Matcher>>:
  match entries:
    case Nil{}: List.reverse(&2, Table.Entry<Matcher>, reversed)
    case Table.Entry{id, mode} <> rest: matchersOf(rest, modes, Table.Entry{id, matcherOf(mode, modes)} <> reversed)

def aliasesFrom(entries: List<&2, R.Property<V.Value>>, record: R.Record<String>) -> Loaded(R.Record<String>):
  match entries:
    case Nil{}: Done{record}
    case R.Property{key, V.Text{value}} <> rest: aliasesFrom(rest, R.set(String, record, key, value))
    case _: Fail{"invalid classNameAliases"}
def classNameAliasesOf(value: Maybe<&2, V.Value>) -> Loaded(R.Record<String>):
  match value:
    case Some{V.ObjectValue{fields}}: aliasesFrom(R.entries(V.Value, fields), R.new(String))
    case _: Done{R.new(String)}
def withSubLanguage(sub: Maybe<&2, SubLanguage>, found: List<&2, SubLanguage>) -> List<&2, SubLanguage>:
  match sub:
    case Some{value}: value <> found
    case None{}: found
def subLanguagesOf(entries: List<&2, Table.Entry<Mode>>, found: List<&2, SubLanguage>) -> List<&2, SubLanguage>:
  match entries:
    case Nil{}: found
    case Table.Entry{_, Mode{_, _, _, _, _, _, _, _, _, sub, _, _, _, _, _}} <> rest: subLanguagesOf(rest, withSubLanguage(sub, found))
def assembled(+name: String, caseInsensitive: Bool, aliases: R.Record<String>, +entries: List<&2, Table.Entry<Mode>>) -> Language:
  +modes = Table.fromSortedEntries(Mode, entries)
  Language{name, caseInsensitive, aliases, modes, Table.fromSortedEntries(Matcher, matchersOf(entries, modes, Nil{})), subLanguagesOf(entries, Nil{})}
def languageFrom(+fields: R.Record<V.Value>) -> Loaded(Language):
  +caseInsensitive = truthy(R.get(V.Value, fields, "caseInsensitive"))
  do Result<&2, &2, String, Language>:
    tableValues : List<&2, V.Value> <- arrayOf(R.get(V.Value, fields, "keywords"))
    tables : List<&2, Words> <- keywordTables(tableValues, Nil{})
    aliases : R.Record<String> <- classNameAliasesOf(R.get(V.Value, fields, "classNameAliases"))
    modeValues : List<&2, V.Value> <- arrayOf(R.get(V.Value, fields, "modes"))
    entries : List<&2, Table.Entry<Mode>> <- modesFrom(modeValues, Bool.pick(String, caseInsensitive, "mi", "m"), tables, 0n, Nil{})
    return assembled(Maybe.default(&2, String, textOf(R.get(V.Value, fields, "name")), ""), caseInsensitive, aliases, entries)
def parsedLanguage(result: Result<&2, &2, Json.ParseError, V.Value>) -> Loaded(Language):
  match result:
    case Done{V.ObjectValue{fields}}: languageFrom(fields)
    case _: Fail{"invalid grammar document"}
# A grammar file's contents.
def parseLanguage(text: String) -> Loaded(Language): parsedLanguage(Json.parse(text))

# Registry
# --------
# highlight.js's `languages` and `aliases` tables. Registering a name again
# keeps its position (JavaScript object key order), which `highlightAuto`
# without a subset follows; an alias names the language registered last.

type LanguageInfo is Data: LanguageInfo{name: String, aliases: List<&2, String>, disableAutodetect: Bool, supersetOf: Maybe<&2, String>}
type Registry is Data: Registry{languages: List<&2, LanguageInfo>, aliases: R.Record<String>}

def emptyRegistry() -> Registry: Registry{Nil{}, R.new(String)}
def infoName(info: LanguageInfo) -> String:
  match info: case LanguageInfo{name, _, _, _}: name
def named(languages: List<&2, LanguageInfo>, +name: String) -> Maybe<&2, LanguageInfo>:
  match languages:
    case Nil{}: None{}
    case LanguageInfo{+other, aliases, disabled, superset} <> rest:
      Bool.pick(Unit -> Maybe<&2, LanguageInfo>, String.eq(other, name), _ => Some{LanguageInfo{other, aliases, disabled, superset}}, _ => named(rest, name))(Unit{})
def replaced(languages: List<&2, LanguageInfo>, +info: LanguageInfo, +name: String) -> List<&2, LanguageInfo>:
  match languages:
    case Nil{}: [info]
    case LanguageInfo{+other, aliases, disabled, superset} <> +rest:
      Bool.pick(Unit -> List<&2, LanguageInfo>, String.eq(other, name), _ => info <> rest, _ => LanguageInfo{other, aliases, disabled, superset} <> replaced(rest, info, name))(Unit{})
def aliased(names: List<&2, String>, +language: String, aliases: R.Record<String>) -> R.Record<String>:
  match names:
    case Nil{}: aliases
    case alias <> rest: aliased(rest, language, R.set(String, aliases, Case.lower(alias), language))
# hljs.registerLanguage with the definition's metadata.
def registerLanguage(registry: Registry, +info: LanguageInfo) -> Registry:
  match registry info:
    case Registry{languages, aliases} LanguageInfo{+name, names, _, _}: Registry{replaced(languages, info, name), aliased(names, name, aliases)}
def registeredNamed(registry: Registry, name: String) -> Maybe<&2, LanguageInfo>:
  match registry: case Registry{languages, _}: named(languages, name)
def aliasTarget(aliases: R.Record<String>, key: String) -> String:
  Maybe.default(&2, String, R.get(String, aliases, key), "undefined")
def languageOr(found: Maybe<&2, LanguageInfo>, +languages: List<&2, LanguageInfo>, +aliases: R.Record<String>, key: String) -> Maybe<&2, LanguageInfo>:
  match found:
    case Some{info}: Some{info}
    case None{}: named(languages, aliasTarget(aliases, key))
# hljs.getLanguage: case-insensitive name or alias.
def getLanguage(registry: Registry, name: String) -> Maybe<&2, LanguageInfo>:
  match registry:
    case Registry{+languages, aliases}:
      +key = Case.lower(name)
      languageOr(named(languages, key), languages, aliases, key)
def infoNames(languages: List<&2, LanguageInfo>, reversed: List<&2, String>) -> List<&2, String>:
  match languages:
    case Nil{}: List.reverse(&2, String, reversed)
    case LanguageInfo{name, _, _, _} <> rest: infoNames(rest, name <> reversed)
def listLanguages(registry: Registry) -> List<&2, String>:
  match registry: case Registry{languages, _}: infoNames(languages, Nil{})
def detectable(info: Maybe<&2, LanguageInfo>) -> Bool:
  match info:
    case Some{LanguageInfo{_, _, disabled, _}}: Bool.not(disabled)
    case None{}: False{}
def autoDetection(registry: Registry, name: String) -> Bool: detectable(getLanguage(registry, name))

# Grammar data by registered name, loaded ahead of a highlight call (see
# `prepare`); a registered language without loaded data fails like a grammar
# that cannot be compiled.
type Grammars is Data: Grammars{loaded: R.Record<Language>}
def noGrammars() -> Grammars: Grammars{R.new(Language)}
def grammarOf(grammars: Grammars, name: String) -> Maybe<&2, Language>:
  match grammars: case Grammars{loaded}: R.get(Language, loaded, name)
def withGrammar(grammars: Grammars, name: String, language: Language) -> Grammars:
  match grammars: case Grammars{loaded}: Grammars{R.set(Language, loaded, name, language)}

# Emitter
# -------
# TokenTreeEmitter as the walk of its tree: text, and the opening and closing
# of nodes with a kind (nodes without one emit no span). `Embed` marks where a
# sub-language result goes while its host run is in progress.

type Token is Data:
  Text{text: String}
  OpenNode{kind: String, sublanguage: Bool}
  CloseNode{}
  Embed{}
# Tokens in reverse, and whether each open node wraps (has a kind).
type Emitter is Data: Emitter{tokens: List<&2, Token>, open: List<&2, Bool>}

def reversedText(reversed: List<&2, U32>, text: String) -> String:
  match reversed:
    case Nil{}: text
    case code <> rest: reversedText(rest, SCon{Chr{code}, text})
def addText(emitter: Emitter, text: String) -> Emitter:
  match emitter text:
    case emitter "": emitter
    case Emitter{tokens, open} text: Emitter{Text{text} <> tokens, open}
def openNode(emitter: Emitter, kind: String) -> Emitter:
  match emitter kind:
    case Emitter{tokens, open} "": Emitter{tokens, False{} <> open}
    case Emitter{tokens, open} kind: Emitter{OpenNode{kind, False{}} <> tokens, True{} <> open}
def closeNode(emitter: Emitter) -> Emitter:
  match emitter:
    case Emitter{tokens, Nil{}}: Emitter{tokens, Nil{}}
    case Emitter{tokens, True{} <> open}: Emitter{CloseNode{} <> tokens, open}
    case Emitter{tokens, False{} <> open}: Emitter{tokens, open}
def closedAll(open: List<&2, Bool>, tokens: List<&2, Token>) -> Emitter:
  match open:
    case Nil{}: Emitter{tokens, Nil{}}
    case True{} <> rest: closedAll(rest, CloseNode{} <> tokens)
    case False{} <> rest: closedAll(rest, tokens)
def closeAllNodes(emitter: Emitter) -> Emitter:
  match emitter: case Emitter{tokens, open}: closedAll(open, tokens)
def addKeyword(emitter: Emitter, text: String, +kind: String) -> Emitter:
  match text:
    case "": emitter
    case text: closeNode(addText(openNode(emitter, kind), text))
def embedded(emitter: Emitter) -> Emitter:
  match emitter: case Emitter{tokens, open}: Emitter{Embed{} <> tokens, open}

# Modes
# -----

def blankRule() -> Rule: Rule{Re.RegExp{"", Re.noFlags(), Re.Empty{}, 0n, Nil{}}, Re.nullableStart()}
def blankMode() -> Mode: Mode{"", None{}, None{}, None{}, None{}, None{}, scannerOf([Terminator{blankRule(), EndOf{}}]), U32.to_f64(0), Flags{False{}, False{}, False{}, False{}, False{}, False{}, False{}}, None{}, None{}, None{}, None{}, Nil{}, None{}}
def modeOr(found: Maybe<&2, Mode>) -> Mode:
  match found:
    case Some{mode}: mode
    case None{}: blankMode()
def modeAt(language: Language, id: Nat) -> Mode:
  match language: case Language{_, _, _, modes, _, _}: modeOr(Table.get(Mode, modes, U32.from_nat(id)))
def matcherOr(found: Maybe<&2, Matcher>) -> Matcher:
  match found:
    case Some{matcher}: matcher
    case None{}: Matcher{Nil{}, 0n, scannerOf(Nil{})}
def matcherAt(language: Language, id: Nat) -> Matcher:
  match language: case Language{_, _, _, _, matchers, _}: matcherOr(Table.get(Matcher, matchers, U32.from_nat(id)))
def languageName(language: Language) -> String:
  match language: case Language{name, _, _, _, _, _}: name
def caseInsensitiveOf(language: Language) -> Bool:
  match language: case Language{_, caseInsensitive, _, _, _, _}: caseInsensitive
def aliasOrKind(alias: Maybe<&2, String>, kind: String) -> String:
  match alias:
    case Some{""}: kind
    case Some{value}: value
    case None{}: kind
# language.classNameAliases[kind] || kind
def cssClass(language: Language, +kind: String) -> String:
  match language: case Language{_, _, aliases, _, _, _}: aliasOrKind(R.get(String, aliases, kind), kind)
def modeClassName(mode: Mode) -> String:
  match mode: case Mode{className, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: className
def modeEnd(mode: Mode) -> Maybe<&2, Rule>:
  match mode: case Mode{_, _, end, _, _, _, _, _, _, _, _, _, _, _, _}: end
def modeKeywords(mode: Mode) -> Maybe<&2, Words>:
  match mode: case Mode{_, _, _, _, _, keywords, _, _, _, _, _, _, _, _, _}: keywords
def modeKeywordPattern(mode: Mode) -> Scanner:
  match mode: case Mode{_, _, _, _, _, _, pattern, _, _, _, _, _, _, _, _}: pattern
def modeRelevance(mode: Mode) -> F64:
  match mode: case Mode{_, _, _, _, _, _, _, relevance, _, _, _, _, _, _, _}: relevance
def modeFlags(mode: Mode) -> Flags:
  match mode: case Mode{_, _, _, _, _, _, _, _, flags, _, _, _, _, _, _}: flags
def modeSubLanguage(mode: Mode) -> Maybe<&2, SubLanguage>:
  match mode: case Mode{_, _, _, _, _, _, _, _, _, sub, _, _, _, _, _}: sub
def modeBeforeBegin(mode: Mode) -> Maybe<&2, Callback>:
  match mode: case Mode{_, _, _, _, _, _, _, _, _, _, callback, _, _, _, _}: callback
def modeOnBegin(mode: Mode) -> Maybe<&2, Callback>:
  match mode: case Mode{_, _, _, _, _, _, _, _, _, _, _, callback, _, _, _}: callback
def modeOnEnd(mode: Mode) -> Maybe<&2, Callback>:
  match mode: case Mode{_, _, _, _, _, _, _, _, _, _, _, _, callback, _, _}: callback
def modeStarts(mode: Mode) -> Maybe<&2, Nat>:
  match mode: case Mode{_, _, _, _, _, _, _, _, _, _, _, _, _, _, starts}: starts
def excludeBegin(flags: Flags) -> Bool:
  match flags: case Flags{value, _, _, _, _, _, _}: value
def excludeEnd(flags: Flags) -> Bool:
  match flags: case Flags{_, value, _, _, _, _, _}: value
def returnBegin(flags: Flags) -> Bool:
  match flags: case Flags{_, _, value, _, _, _, _}: value
def returnEnd(flags: Flags) -> Bool:
  match flags: case Flags{_, _, _, value, _, _, _}: value
def endsWithParent(flags: Flags) -> Bool:
  match flags: case Flags{_, _, _, _, value, _, _}: value
def endsParent(flags: Flags) -> Bool:
  match flags: case Flags{_, _, _, _, _, value, _}: value
def skip(flags: Flags) -> Bool:
  match flags: case Flags{_, _, _, _, _, _, value}: value
def hasSubLanguage(sub: Maybe<&2, SubLanguage>) -> Bool: Bool.not(Maybe.is_none(&2, SubLanguage, sub))

# Matching
# --------

type Hit is Data: Hit{position: Nat, kind: TerminatorKind, found: Re.Match, at: Re.Cursor}

def attempted(eligible: Bool, regex: Re.RegExp, kind: TerminatorKind, +position: Nat, input: List<&2, U32>, +cursor: Re.Cursor) -> Maybe<&2, Hit>:
  match eligible:
    case True{}: Maybe.map(&2, Re.Match, Hit, result => Hit{position, kind, result, cursor}, Re.matchAt(regex, input, cursor))
    case False{}: None{}
# Candidates for a wide scalar are checked against their start exactly.
def preciseStart(precise: Bool, regex: Re.RegExp, start: Re.Start, cursor: Re.Cursor) -> Bool:
  match precise:
    case True{}: Re.canStart(regex, start, cursor)
    case False{}: True{}
# A `\b`-led pattern starting with a word scalar cannot start after one.
def boundedOut(start: Re.Start, afterWord: Bool) -> Bool:
  match start: case Re.Start{_, _, _, _, bounded, _}: bounded && afterWord
def attemptCandidate(+from: Nat, +afterWord: Bool, precise: Bool, candidate: Candidate, input: List<&2, U32>, +cursor: Re.Cursor) -> Maybe<&2, Hit>:
  match candidate:
    case Candidate{+position, Terminator{Rule{+regex, +start}, kind}}:
      attempted(Nat.is_ge(position, from) && Bool.not(boundedOut(start, afterWord)) && preciseStart(precise, regex, start, cursor), regex, kind, position, input, cursor)
# The first candidate (from rule `from` on) matching at `cursor`, as the
# alternation of the rules tries them.
def tryCandidates(candidates: List<&2, Candidate>, +from: Nat, +afterWord: Bool, +precise: Bool, +input: List<&2, U32>, +cursor: Re.Cursor, previous: Maybe<&2, Hit>) -> Maybe<&2, Hit>:
  match candidates previous:
    case _ Some{hit}: Some{hit}
    case Nil{} None{}: None{}
    case candidate <> rest None{}: tryCandidates(rest, from, afterWord, precise, input, cursor, attemptCandidate(from, afterWord, precise, candidate, input, cursor))
def candidatesOr(found: Maybe<&2, List<&2, Candidate>>) -> List<&2, Candidate>:
  match found:
    case Some{candidates}: candidates
    case None{}: Nil{}
def asciiCandidates(table: Table.Table<List<&2, Candidate>>, code: U32) -> List<&2, Candidate>: candidatesOr(Table.get(List<&2, Candidate>, table, code))
def isWordScalar(code: Maybe<&2, U32>) -> Bool:
  match code:
    case Some{+value}: (U32.is_ge(value, 48) && U32.is_le(value, 57)) || (U32.is_ge(value, 65) && U32.is_le(value, 90)) || (U32.is_ge(value, 97) && U32.is_le(value, 122)) || U32.is_eq(value, 95)
    case None{}: False{}
def tryAt(scanner: Scanner, next: Maybe<&2, U32>, +from: Nat, +input: List<&2, U32>, +cursor: Re.Cursor) -> Maybe<&2, Hit>:
  match scanner next:
    case Single{candidate} _: tryCandidates([candidate], from, isWordScalar(Re.preceding(cursor)), True{}, input, cursor, None{})
    case Dispatch{_, _, ending} None{}: tryCandidates(ending, from, isWordScalar(Re.preceding(cursor)), False{}, input, cursor, None{})
    case Dispatch{ascii, wide, _} Some{+code}:
      Bool.pick(Unit -> Maybe<&2, Hit>, U32.is_lt(code, 128),
        _ => tryCandidates(asciiCandidates(ascii, code), from, isWordScalar(Re.preceding(cursor)), False{}, input, cursor, None{}),
        _ => tryCandidates(wide, from, isWordScalar(Re.preceding(cursor)), True{}, input, cursor, None{}))(Unit{})
def searchLoop(fuel: Nat, +scanner: Scanner, +from: Nat, +input: List<&2, U32>, previous: Maybe<&2, Hit>, next: Maybe<&2, Re.Cursor>) -> Maybe<&2, Hit>:
  match fuel previous next:
    case _ Some{hit} _: Some{hit}
    case Succ{more} None{} Some{+cursor}: searchLoop(more, scanner, from, input, tryAt(scanner, Re.nextScalar(cursor), from, input, cursor), Re.advance(cursor))
    case _ _ _: None{}
# The leftmost match at or after `cursor` of the rules from index `from` on (a
# global exec from lastIndex); `position` is the rule's index. The scan ends at
# the end of the input; its fuel only bounds it for the termination checker.
def search(scanner: Scanner, from: Nat, input: List<&2, U32>, +cursor: Re.Cursor) -> Maybe<&2, Hit>:
  searchLoop(4294967295n, scanner, from, input, None{}, Some{cursor})

type Execution is Data: Execution{hit: Maybe<&2, Hit>, regexIndex: Nat}
def hitIndex(hit: Maybe<&2, Hit>) -> Maybe<&2, Nat>:
  match hit:
    case Some{Hit{_, _, Re.Match{index, _, _}, _}}: Some{index}
    case None{}: None{}
def sameIndex(index: Maybe<&2, Nat>, +lastIndex: Nat) -> Bool:
  match index:
    case Some{value}: Nat.is_eq(value, lastIndex)
    case None{}: False{}
def afterIgnored(+scanner: Scanner, +input: List<&2, U32>, next: Maybe<&2, Re.Cursor>) -> Maybe<&2, Hit>:
  match next:
    case Some{cursor}: search(scanner, 0n, input, cursor)
    case None{}: None{}
# regexIndex advances past the matching rule's position within the matcher
# that produced the match (which starts at rule `offset`).
def executed(hit: Maybe<&2, Hit>, +regexIndex: Nat, offset: Nat, +count: Nat) -> Execution:
  match hit:
    case None{}: Execution{None{}, regexIndex}
    case Some{Hit{+position, kind, result, at}}:
      +next = regexIndex + (position - offset) + 1n
      Execution{Some{Hit{position, kind, result, at}}, Bool.pick(Nat, Nat.is_eq(next, count), 0n, next)}
# ResumableMultiRegex.exec. Resuming after an ignored begin, a match at the
# same position among the later rules wins; otherwise the full matcher is run
# from the next position.
def exec(matcher: Matcher, +regexIndex: Nat, +input: List<&2, U32>, +cursor: Re.Cursor) -> Execution:
  match matcher:
    case Matcher{_, +count, +scanner}:
      +first = search(scanner, regexIndex, input, cursor)
      Bool.pick(Unit -> Execution, Nat.is_eq(regexIndex, 0n) || sameIndex(hitIndex(first), Re.position(cursor)),
        _ => executed(first, regexIndex, regexIndex, count),
        _ => executed(afterIgnored(scanner, input, Re.advance(cursor)), regexIndex, 0n, count))(Unit{})

# The cursor `count` scalars on (stopping at the end of input).
def advanceBy(count: Nat, +cursor: Re.Cursor) -> Re.Cursor:
  match count:
    case Zero{}: cursor
    case Succ{more}: advanceBy(more, Maybe.default(&2, Re.Cursor, Re.advance(cursor), cursor))

# Runs
# ----
# One `_highlight` call: the language, its input as scalars, and the lexer
# state that highlight.js keeps in closure variables and compiled modes.

def countFrom(codes: List<&2, U32>, count: Nat) -> Nat:
  match codes:
    case Nil{}: count
    case _ <> rest: countFrom(rest, count + 1n)
# The first `count` scalars of `codes`, reversed onto `onto`.
def takeOnto(count: Nat, codes: List<&2, U32>, onto: List<&2, U32>) -> List<&2, U32>:
  match count codes:
    case Succ{more} code <> rest: takeOnto(more, rest, code <> onto)
    case _ _: onto
def reversedOnto(codes: List<&2, U32>, onto: List<&2, U32>) -> List<&2, U32>:
  match codes:
    case Nil{}: onto
    case code <> rest: reversedOnto(rest, code <> onto)
def forwardText(codes: List<&2, U32>) -> String: reversedText(reversedOnto(codes, Nil{}), "")

# END_SAME_AS_BEGIN's `data._beginMatch` of a compiled mode.
type BeginMatch is Data: BeginMatch{language: String, mode: Nat, text: Maybe<&2, String>}
def isEntry(+language: String, +mode: Nat, entry: BeginMatch) -> Bool:
  match entry: case BeginMatch{other, id, _}: String.eq(other, language) && Nat.is_eq(id, mode)
def remembered(memory: List<&2, BeginMatch>, +language: String, +mode: Nat, +text: Maybe<&2, String>) -> List<&2, BeginMatch>:
  match memory:
    case Nil{}: [BeginMatch{language, mode, text}]
    case +entry <> +rest: Bool.pick(Unit -> List<&2, BeginMatch>, isEntry(language, mode, entry), _ => BeginMatch{language, mode, text} <> rest, _ => entry <> remembered(rest, language, mode, text))(Unit{})
def recalled(memory: List<&2, BeginMatch>, +language: String, +mode: Nat) -> Maybe<&2, String>:
  match memory:
    case Nil{}: None{}
    case BeginMatch{+other, +id, +text} <> rest: Bool.pick(Unit -> Maybe<&2, String>, isEntry(language, mode, BeginMatch{other, id, text}), _ => text, _ => recalled(rest, language, mode))(Unit{})

# A sub-language buffer to highlight once the host run's loop has finished.
type Job is Data: Job{sub: SubLanguage, code: List<&2, U32>, counted: Bool}
type Context is Data: Context{language: Language, name: String, input: List<&2, U32>, ignoreIllegals: Bool, registry: Registry}
# modeBuffer (reversed), the emitter, relevance, pending sub-languages
# (reversed) and END_SAME_AS_BEGIN data.
type Output is Data: Output{buffer: List<&2, U32>, emitter: Emitter, relevance: F64, jobs: List<&2, Job>, memory: List<&2, BeginMatch>}
type Last is Data:
  NoMatchYet{}
  BeginAt{index: Nat}
  OtherAt{}
# The mode stack (top first; the language root last), the cursor at `index`,
# the iteration count, the matcher's resume flag and regexIndex, lastMatch.
type State is Data: State{stack: List<&2, Nat>, cursor: Re.Cursor, iterations: Nat, resume: Bool, regexIndex: Nat, last: Last}
type Run is Data: Run{context: Context, state: State, output: Output}
type Status is Data:
  Completed{}
  Illegal{}
  Failed{}
type Step is Data:
  Stepping{run: Run}
  Finished{run: Run, status: Status}

def contextLanguage(context: Context) -> Language:
  match context: case Context{language, _, _, _, _}: language
def contextInput(context: Context) -> List<&2, U32>:
  match context: case Context{_, _, input, _, _}: input
def contextRegistry(context: Context) -> Registry:
  match context: case Context{_, _, _, _, registry}: registry
def topOf(stack: List<&2, Nat>) -> Nat:
  match stack:
    case id <> _: id
    case Nil{}: 0n
def buffered(output: Output, codes: List<&2, U32>) -> Output:
  match output: case Output{buffer, emitter, relevance, jobs, memory}: Output{reversedOnto(codes, buffer), emitter, relevance, jobs, memory}
def rebuffered(output: Output, codes: List<&2, U32>) -> Output:
  match output: case Output{_, emitter, relevance, jobs, memory}: Output{reversedOnto(codes, Nil{}), emitter, relevance, jobs, memory}
def withMemory(output: Output, memory: List<&2, BeginMatch>) -> Output:
  match output: case Output{buffer, emitter, relevance, jobs, _}: Output{buffer, emitter, relevance, jobs, memory}
def outputMemory(output: Output) -> List<&2, BeginMatch>:
  match output: case Output{_, _, _, _, memory}: memory
def closedOutput(output: Output) -> Output:
  match output: case Output{buffer, emitter, relevance, jobs, memory}: Output{buffer, closeAllNodes(emitter), relevance, jobs, memory}

# processKeywords
type Keyworded is Data: Keyworded{pending: List<&2, U32>, emitter: Emitter, relevance: F64}
def keywordApplied(keyword: Maybe<&2, Keyword>, +word: List<&2, U32>, +language: Language, accumulated: Keyworded) -> Keyworded:
  match keyword accumulated:
    case None{} Keyworded{pending, emitter, relevance}: Keyworded{reversedOnto(word, pending), emitter, relevance}
    case Some{Keyword{+category, score}} Keyworded{pending, emitter, relevance}:
      +flushed = addText(emitter, reversedText(pending, ""))
      +total = F64.add(relevance, score)
      Bool.pick(Unit -> Keyworded, String.starts_with(category, "_"),
        _ => Keyworded{reversedOnto(word, Nil{}), flushed, total},
        _ => Keyworded{Nil{}, addKeyword(flushed, forwardText(word), cssClass(language, category)), total})(Unit{})
def wordKey(caseInsensitive: Bool, +word: String) -> String:
  match caseInsensitive:
    case True{}: Case.lower(word)
    case False{}: word
def keywordLoop(fuel: Nat, +words: Words, +pattern: Scanner, +language: Language, +input: List<&2, U32>, hit: Maybe<&2, Hit>, +cursor: Re.Cursor, accumulated: Keyworded) -> Keyworded:
  match fuel hit accumulated:
    case Succ{more} Some{Hit{_, _, Re.Match{+index, +end, _}, +at}} Keyworded{pending, emitter, relevance}:
      +word = reversedOnto(takeOnto(end - index, Re.following(at), Nil{}), Nil{})
      +next = advanceBy(end - index, at)
      keywordLoop(more, words, pattern, language, input, search(pattern, 0n, input, next), next,
        keywordApplied(lookup(words, wordKey(caseInsensitiveOf(language), forwardText(word))), word, language, Keyworded{takeOnto(index - Re.position(cursor), Re.following(cursor), pending), emitter, relevance}))
    case _ _ Keyworded{pending, emitter, relevance}: Keyworded{Nil{}, addText(emitter, reversedText(reversedOnto(Re.following(cursor), pending), "")), relevance}
def keywordOutput(result: Keyworded, output: Output) -> Output:
  match result output:
    case Keyworded{_, emitter, relevance} Output{_, _, _, jobs, memory}: Output{Nil{}, emitter, relevance, jobs, memory}
def processKeywords(+language: Language, mode: Mode, keywords: Maybe<&2, Words>, output: Output, +codes: List<&2, U32>) -> Output:
  match keywords output:
    case None{} Output{_, +emitter, +relevance, jobs, memory}: Output{Nil{}, addText(emitter, forwardText(codes)), relevance, jobs, memory}
    case Some{words} Output{buffer, +emitter, +relevance, jobs, memory}:
      +pattern = modeKeywordPattern(mode)
      +start = Re.cursorAt(codes)
      keywordOutput(keywordLoop(2n + countFrom(codes, 0n), words, pattern, language, codes, search(pattern, 0n, codes, start), start, Keyworded{Nil{}, emitter, relevance}), Output{buffer, emitter, relevance, jobs, memory})

# processSubLanguage: the buffer becomes a job; an unregistered named
# language is plain text.
def withJob(output: Output, job: Job) -> Output:
  match output: case Output{_, emitter, relevance, jobs, memory}: Output{Nil{}, embedded(emitter), relevance, job <> jobs, memory}
def plainOutput(output: Output, codes: List<&2, U32>) -> Output:
  match output: case Output{_, emitter, relevance, jobs, memory}: Output{Nil{}, addText(emitter, forwardText(codes)), relevance, jobs, memory}
def processSubLanguage(context: Context, sub: SubLanguage, +counted: Bool, +output: Output, +codes: List<&2, U32>) -> Output:
  match sub codes:
    case _ Nil{}: rebuffered(output, Nil{})
    case Named{+name} _:
      Bool.pick(Unit -> Output, Maybe.is_none(&2, LanguageInfo, registeredNamed(contextRegistry(context), name)),
        _ => plainOutput(output, codes),
        _ => withJob(output, Job{Named{name}, codes, counted}))(Unit{})
    case Detect{names} _: withJob(output, Job{Detect{names}, codes, counted})
def processedBuffer(context: Context, +mode: Mode, sub: Maybe<&2, SubLanguage>, output: Output) -> Output:
  match sub output:
    case Some{value} Output{+buffer, emitter, relevance, jobs, memory}: processSubLanguage(context, value, F64.is_gt(modeRelevance(mode), U32.to_f64(0)), Output{buffer, emitter, relevance, jobs, memory}, reversedOnto(buffer, Nil{}))
    case None{} Output{+buffer, emitter, relevance, jobs, memory}: processKeywords(contextLanguage(context), mode, modeKeywords(mode), Output{buffer, emitter, relevance, jobs, memory}, reversedOnto(buffer, Nil{}))
def processBuffer(+context: Context, top: Nat, output: Output) -> Output:
  +mode = modeAt(contextLanguage(context), top)
  processedBuffer(context, mode, modeSubLanguage(mode), output)

# startNewMode
def opened(+language: Language, className: String, output: Output) -> Output:
  match className output:
    case "" output: output
    case name Output{buffer, emitter, relevance, jobs, memory}: Output{buffer, openNode(emitter, cssClass(language, name)), relevance, jobs, memory}
# processContinuations: reopen the classes of a continuation's modes,
# outermost first (without classNameAliases, as highlight.js does).
def classOpened(+language: Language, outer: List<&2, Nat>, +emitter: Emitter) -> Emitter:
  match outer:
    case Nil{}: emitter
    case +id <> rest:
      +className = modeClassName(modeAt(language, id))
      classOpened(language, rest, Bool.pick(Emitter, String.eq(className, ""), emitter, openNode(emitter, className)))
def rootStack(stack: List<&2, Nat>) -> List<&2, Nat>:
  match stack:
    case Nil{}: [0n]
    case top <> below: top <> below
def runFrom(+context: Context, +stack: List<&2, Nat>, memory: List<&2, BeginMatch>) -> Run:
  Run{context, State{stack, Re.cursorAt(contextInput(context)), 0n, False{}, 0n, NoMatchYet{}}, Output{Nil{}, classOpened(contextLanguage(context), List.drop(&2, Nat, List.reverse(&2, Nat, stack), 1n), Emitter{Nil{}, Nil{}}), U32.to_f64(0), Nil{}, memory}}
# A run from the language root, or from a continuation's mode stack.
def newRun(context: Context, stack: List<&2, Nat>, memory: List<&2, BeginMatch>) -> Run: runFrom(context, rootStack(stack), memory)

# processLexeme
# -------------

# Step to `count` scalars past the match (at state.cursor).
def moved(context: Context, state: State, +count: Nat, output: Output) -> Step:
  match state:
    case State{stack, cursor, iterations, resume, regexIndex, last}: Stepping{Run{context, State{stack, advanceBy(count, cursor), iterations, resume, regexIndex, last}, output}}
def failed(context: Context, state: State, output: Output, status: Status) -> Step: Finished{Run{context, state, output}, status}
def stateStack(state: State) -> List<&2, Nat>:
  match state: case State{stack, _, _, _, _, _}: stack
def stateCursor(state: State) -> Re.Cursor:
  match state: case State{_, cursor, _, _, _, _}: cursor
def stateRegexIndex(state: State) -> Nat:
  match state: case State{_, _, _, _, regexIndex, _}: regexIndex
def withStack(state: State, stack: List<&2, Nat>) -> State:
  match state: case State{_, cursor, iterations, resume, regexIndex, last}: State{stack, cursor, iterations, resume, regexIndex, last}
def resumed(state: State) -> State:
  match state: case State{stack, cursor, iterations, _, regexIndex, last}: State{stack, cursor, iterations, True{}, regexIndex, last}

# m[1] of a match, as text of the input.
def captureText(capture: Maybe<&2, Re.Span>, +input: List<&2, U32>) -> Maybe<&2, String>:
  match capture:
    case Some{Re.Span{+start, end}}: Some{forwardText(reversedOnto(takeOnto(end - start, List.drop(&2, U32, input, start), Nil{}), Nil{}))}
    case None{}: None{}
def firstCapture(captures: List<&2, Maybe<&2, Re.Span>>, +input: List<&2, U32>) -> Maybe<&2, String>:
  match captures:
    case capture <> _: captureText(capture, input)
    case Nil{}: None{}
def sameText(left: Maybe<&2, String>, right: Maybe<&2, String>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: String.eq(a, b)
    case _ _: False{}

# javascript's isTrulyOpeningTag: after `<Tag`, another `<` is a nested type
# and `>` needs a later `</Tag`.
def startsWithCodes(prefix: List<&2, U32>, codes: List<&2, U32>) -> Bool:
  match prefix codes:
    case Nil{} _: True{}
    case _ Nil{}: False{}
    case +a <> more +b <> rest: U32.is_eq(a, b) && startsWithCodes(more, rest)
def containsCodes(codes: List<&2, U32>, +needle: List<&2, U32>, found: Bool) -> Bool:
  match codes found:
    case _ True{}: True{}
    case Nil{} False{}: False{}
    case +code <> +rest False{}: containsCodes(rest, needle, startsWithCodes(needle, code <> rest))
def closingTag(lexeme: List<&2, U32>) -> List<&2, U32>:
  match lexeme:
    case _ <> rest: 60 <> 47 <> rest
    case Nil{}: [60, 47]
def jsxIgnores(+lexeme: List<&2, U32>, after: List<&2, U32>) -> Bool:
  match after:
    case 60 <> _: True{}
    case 62 <> +rest: Bool.not(containsCodes(62 <> rest, closingTag(lexeme), startsWithCodes(closingTag(lexeme), 62 <> rest)))
    case _: False{}

# Callback responses: whether the match is ignored, and updated mode data.
type Decision is Data: Decision{ignored: Bool, memory: List<&2, BeginMatch>}
def isDot(code: Maybe<&2, U32>) -> Bool:
  match code:
    case Some{46}: True{}
    case _: False{}
def callbackDecision(callback: Maybe<&2, Callback>, +context: Context, +id: Nat, +index: Nat, +lexeme: List<&2, U32>, +captures: List<&2, Maybe<&2, Re.Span>>, +at: Re.Cursor, memory: List<&2, BeginMatch>) -> Decision:
  match callback:
    case None{}: Decision{False{}, memory}
    case Some{SkipIfHasPrecedingDot{}}: Decision{isDot(Re.preceding(at)), memory}
    case Some{Shebang{}}: Decision{Bool.not(Nat.is_eq(index, 0n)), memory}
    case Some{EndSameAsBegin{}}: Decision{False{}, remembered(memory, languageName(contextLanguage(context)), id, firstCapture(captures, contextInput(context)))}
    case Some{JsxOpeningTag{}}: Decision{jsxIgnores(lexeme, List.drop(&2, U32, Re.following(at), countFrom(lexeme, 0n))), memory}
    case Some{SystemSymbol{symbols}}: Decision{Maybe.is_none(&2, Keyword, lookup(symbols, forwardText(lexeme))), memory}
def beginDecision(first: Decision, second: Maybe<&2, Callback>, +context: Context, +id: Nat, +index: Nat, +lexeme: List<&2, U32>, +captures: List<&2, Maybe<&2, Re.Span>>, +at: Re.Cursor) -> Decision:
  match first:
    case Decision{True{}, memory}: Decision{True{}, memory}
    case Decision{False{}, memory}: callbackDecision(second, context, id, index, lexeme, captures, at, memory)

# startNewMode
def entered(+context: Context, +state: State, +id: Nat, output: Output) -> State & Output:
  (withStack(state, id <> stateStack(state)), opened(contextLanguage(context), modeClassName(modeAt(contextLanguage(context), id)), output))
def enteredMoved(context: Context, pair: State & Output, +count: Nat) -> Step:
  match pair:
    case (state, output): moved(context, state, count, output)

# doIgnore: lexeme[0] of an empty lexeme is `undefined` in JavaScript.
def firstOf(lexeme: List<&2, U32>) -> List<&2, U32>:
  match lexeme:
    case code <> _: [code]
    case Nil{}: [117, 110, 100, 101, 102, 105, 110, 101, 100]
def ignoredAt(regexIndex: Nat, context: Context, state: State, output: Output, lexeme: List<&2, U32>) -> Step:
  match regexIndex:
    case Zero{}: moved(context, state, 1n, buffered(output, firstOf(lexeme)))
    case _: moved(context, resumed(state), 0n, output)
def ignored(context: Context, +state: State, output: Output, lexeme: List<&2, U32>) -> Step:
  ignoredAt(stateRegexIndex(state), context, state, output, lexeme)
def beganOutput(+context: Context, top: Nat, +flags: Flags, +output: Output, +lexeme: List<&2, U32>) -> Output:
  +processed = processBuffer(context, top, Bool.pick(Output, excludeBegin(flags), buffered(output, lexeme), output))
  Bool.pick(Output, returnBegin(flags) || excludeBegin(flags), processed, rebuffered(processed, lexeme))
def began(+context: Context, +state: State, +output: Output, +id: Nat, +mode: Mode, +lexeme: List<&2, U32>, decision: Decision) -> Step:
  match decision:
    case Decision{True{}, +memory}: ignored(context, state, withMemory(output, memory), lexeme)
    case Decision{False{}, +memory}:
      +flags = modeFlags(mode)
      enteredMoved(context, entered(context, state, id, Bool.pick(Output, skip(flags), buffered(withMemory(output, memory), lexeme), beganOutput(context, topOf(stateStack(state)), flags, withMemory(output, memory), lexeme))), Bool.pick(Nat, returnBegin(flags), 0n, countFrom(lexeme, 0n)))
def doBeginMatch(+context: Context, +state: State, +output: Output, +id: Nat, +index: Nat, +lexeme: List<&2, U32>, +captures: List<&2, Maybe<&2, Re.Span>>) -> Step:
  +mode = modeAt(contextLanguage(context), id)
  +at = stateCursor(state)
  began(context, state, output, id, mode, lexeme, beginDecision(callbackDecision(modeBeforeBegin(mode), context, id, index, lexeme, captures, at, outputMemory(output)), modeOnBegin(mode), context, id, index, lexeme, captures, at))

# endOfMode: the depth of the mode the end match closes, if any.
def endMatches(end: Maybe<&2, Rule>, +remainder: List<&2, U32>) -> Bool:
  match end:
    case None{}: False{}
    case Some{Rule{+regex, start}}:
      +cursor = Re.cursorAt(remainder)
      Re.canStart(regex, start, cursor) && Bool.not(Maybe.is_none(&2, Re.Match, Re.matchAt(regex, remainder, cursor)))
def endIgnored(callback: Maybe<&2, Callback>, memory: List<&2, BeginMatch>, language: String, id: Nat, capture: Maybe<&2, String>) -> Bool:
  match callback:
    case Some{EndSameAsBegin{}}: Bool.not(sameText(recalled(memory, language, id), capture))
    case _: False{}
def climb(parents: List<&2, Nat>, +language: Language, mode: Mode, +count: Nat) -> Nat:
  match parents:
    case Nil{}: count
    case +id <> rest: Bool.pick(Unit -> Nat, endsParent(modeFlags(mode)), _ => climb(rest, language, modeAt(language, id), count + 1n), _ => count)(Unit{})
def endOfMode(stack: List<&2, Nat>, +language: Language, +depth: Nat, +remainder: List<&2, U32>, +capture: Maybe<&2, String>, +memory: List<&2, BeginMatch>) -> Maybe<&2, Nat>:
  match stack:
    case Nil{}: None{}
    case +id <> +parents:
      +mode = modeAt(language, id)
      Bool.pick(Unit -> Maybe<&2, Nat>, endMatches(modeEnd(mode), remainder) && Bool.not(endIgnored(modeOnEnd(mode), memory, languageName(language), id, capture)),
        _ => Some{depth + climb(parents, language, mode, 0n)},
        _ => Bool.pick(Unit -> Maybe<&2, Nat>, endsWithParent(modeFlags(mode)), _ => endOfMode(parents, language, depth + 1n, remainder, capture, memory), _ => None{})(Unit{}))(Unit{})

# doEndMatch: leave every mode up to the ended one, then its `starts` mode.
def leftOutput(+mode: Mode, output: Output) -> Output:
  match output:
    case Output{buffer, +emitter, +relevance, jobs, memory}:
      +flags = modeFlags(mode)
      Output{buffer, Bool.pick(Emitter, String.eq(modeClassName(mode), ""), emitter, closeNode(emitter)), Bool.pick(F64, skip(flags) || hasSubLanguage(modeSubLanguage(mode)), relevance, F64.add(relevance, modeRelevance(mode))), jobs, memory}
def leave(count: Nat, stack: List<&2, Nat>, +language: Language, output: Output) -> List<&2, Nat> & Output:
  match count stack:
    case Succ{more} +id <> rest: leave(more, rest, language, leftOutput(modeAt(language, id), output))
    case _ stack: (stack, output)
def endedOutput(+context: Context, top: Nat, +flags: Flags, +output: Output, +lexeme: List<&2, U32>) -> Output:
  +processed = processBuffer(context, top, Bool.pick(Output, returnEnd(flags) || excludeEnd(flags), output, buffered(output, lexeme)))
  Bool.pick(Output, excludeEnd(flags), rebuffered(processed, lexeme), processed)
def restarted(+context: Context, starts: Maybe<&2, Nat>, state: State, output: Output) -> State & Output:
  match starts:
    case Some{id}: entered(context, state, id, output)
    case None{}: (state, output)
def afterLeaving(+context: Context, +state: State, starts: Maybe<&2, Nat>, left: List<&2, Nat> & Output) -> State & Output:
  match left:
    case (stack, output): restarted(context, starts, withStack(state, stack), output)
def ended(+context: Context, +state: State, +output: Output, +lexeme: List<&2, U32>, +depth: Nat) -> Step:
  +language = contextLanguage(context)
  +stack = stateStack(state)
  +origin = modeAt(language, topOf(stack))
  +flags = modeFlags(origin)
  +endMode = modeAt(language, Maybe.default(&2, Nat, List.get(&2, Nat, stack, depth), 0n))
  enteredMoved(context, afterLeaving(context, state, modeStarts(endMode), leave(depth + 1n, stack, language, Bool.pick(Output, skip(flags), buffered(output, lexeme), endedOutput(context, topOf(stack), flags, output, lexeme)))), Bool.pick(Nat, returnEnd(flags), 0n, countFrom(lexeme, 0n)))

# The last-ditch paths of processLexeme: an unmatched end or ignored illegal.
# Past 100000 iterations and three per scalar, highlight.js assumes an
# infinite loop and gives up.
def fellThrough(+context: Context, state: State, +output: Output, +index: Nat, +lexeme: List<&2, U32>) -> Step:
  match state:
    case State{+stack, +cursor, +iterations, +resume, +regexIndex, +last}:
      Bool.pick(Unit -> Step, Nat.is_gt(iterations, 100000n) && Nat.is_gt(iterations, index * 3n),
        _ => failed(context, State{stack, cursor, iterations, resume, regexIndex, last}, output, Failed{}),
        _ => moved(context, State{stack, cursor, iterations, resume, regexIndex, last}, countFrom(lexeme, 0n), buffered(output, lexeme)))(Unit{})
def fallThrough(context: Context, +state: State, output: Output, kind: TerminatorKind, +index: Nat, +lexeme: List<&2, U32>) -> Step:
  match kind lexeme:
    case IllegalOf{} Nil{}: moved(context, state, 1n, output)
    case _ _: fellThrough(context, state, output, index, lexeme)
def endResult(+context: Context, +state: State, +output: Output, +index: Nat, +lexeme: List<&2, U32>, depth: Maybe<&2, Nat>) -> Step:
  match depth:
    case Some{value}: ended(context, state, output, lexeme, value)
    case None{}: fallThrough(context, state, output, EndOf{}, index, lexeme)
def doEndMatch(+context: Context, +state: State, +output: Output, +index: Nat, +lexeme: List<&2, U32>, captures: List<&2, Maybe<&2, Re.Span>>) -> Step:
  +language = contextLanguage(context)
  endResult(context, state, output, index, lexeme, endOfMode(stateStack(state), language, 0n, Re.following(stateCursor(state)), firstCapture(captures, contextInput(context)), outputMemory(output)))
def ignoreIllegalsOf(context: Context) -> Bool:
  match context: case Context{_, _, _, ignoreIllegals, _}: ignoreIllegals
def dispatched(+context: Context, +state: State, +output: Output, kind: TerminatorKind, +index: Nat, +lexeme: List<&2, U32>, +captures: List<&2, Maybe<&2, Re.Span>>) -> Step:
  match kind:
    case BeginOf{id}: doBeginMatch(context, state, output, id, index, lexeme, captures)
    case EndOf{}: doEndMatch(context, state, output, index, lexeme, captures)
    case IllegalOf{}:
      Bool.pick(Unit -> Step, ignoreIllegalsOf(context), _ => fallThrough(context, state, output, IllegalOf{}, index, lexeme), _ => failed(context, state, output, Illegal{}))(Unit{})
def isEndKind(kind: TerminatorKind) -> Bool:
  match kind:
    case EndOf{}: True{}
    case _: False{}
def isBeginKind(kind: TerminatorKind) -> Bool:
  match kind:
    case BeginOf{_}: True{}
    case _: False{}
def beganAt(last: Last, +index: Nat) -> Bool:
  match last:
    case BeginAt{other}: Nat.is_eq(other, index)
    case _: False{}
def lastOf(kind: TerminatorKind, +index: Nat) -> Last: Bool.pick(Last, isBeginKind(kind), BeginAt{index}, OtherAt{})
def withLast(state: State, last: Last) -> State:
  match state: case State{stack, cursor, iterations, resume, regexIndex, _}: State{stack, cursor, iterations, resume, regexIndex, last}
# A zero-width end right after a begin at the same index would not advance;
# highlight.js outputs the next character instead.
def lexed(+context: Context, state: State, +output: Output, +kind: TerminatorKind, +index: Nat, +lexeme: List<&2, U32>, +captures: List<&2, Maybe<&2, Re.Span>>) -> Step:
  match state:
    case State{+stack, +cursor, +iterations, +resume, +regexIndex, +last}:
      Bool.pick(Unit -> Step, beganAt(last, index) && isEndKind(kind) && List.is_empty(&2, U32, lexeme),
        _ => moved(context, State{stack, cursor, iterations, resume, regexIndex, last}, 1n, buffered(output, takeOnto(1n, Re.following(cursor), Nil{}))),
        _ => dispatched(context, State{stack, cursor, iterations, resume, regexIndex, lastOf(kind, index)}, output, kind, index, lexeme, captures))(Unit{})

# One iteration of the main loop; no further match ends the run.
def finalOutput(+context: Context, top: Nat, output: Output) -> Output: closedOutput(processBuffer(context, top, output))
def scanned(+context: Context, +stack: List<&2, Nat>, +cursor: Re.Cursor, +iterations: Nat, +last: Last, output: Output, execution: Execution) -> Step:
  match execution:
    case Execution{None{}, regexIndex}: Finished{Run{context, State{stack, cursor, iterations, False{}, regexIndex, last}, finalOutput(context, topOf(stack), buffered(output, Re.following(cursor)))}, Completed{}}
    case Execution{Some{Hit{_, kind, Re.Match{+index, +end, captures}, +at}}, regexIndex}:
      lexed(context, State{stack, at, iterations, False{}, regexIndex, last}, buffered(output, reversedOnto(takeOnto(index - Re.position(cursor), Re.following(cursor), Nil{}), Nil{})), kind, index, reversedOnto(takeOnto(end - index, Re.following(at), Nil{}), Nil{}), captures)
def scanStep(run: Run) -> Step:
  match run:
    case Run{+context, State{+stack, +cursor, iterations, resume, regexIndex, last}, output}:
      scanned(context, stack, cursor, iterations + 1n, last, output, exec(matcherAt(contextLanguage(context), topOf(stack)), Bool.pick(Nat, resume, regexIndex, 0n), contextInput(context), cursor))

# Sub-languages and highlightAuto
# -------------------------------
# A run that finished its loop resolves its sub-language jobs in order, each
# as a nested run (a named language, continuing from that language's previous
# top mode) or a detection over candidate languages. One explicit stack of
# frames drives all runs.

type Continuation is Data: Continuation{language: String, top: List<&2, Nat>}
# A finished run: result.language (none for an illegal result), tokens,
# relevance (floored; zero unless completed), the final mode stack.
type Outcome is Data: Outcome{language: Maybe<&2, String>, tokens: List<&2, Token>, relevance: F64, top: List<&2, Nat>, status: Status}
type Hosted is Data: Hosted{language: Maybe<&2, String>, tokens: List<&2, Token>, top: List<&2, Nat>, status: Status}
type Frame is Data:
  Scanning{run: Run}
  Resolving{host: Hosted, jobs: List<&2, Job>, embeds: List<&2, List<&2, Token>>, relevance: F64, continuations: List<&2, Continuation>}
  Detecting{code: List<&2, U32>, candidates: List<&2, String>, results: List<&2, Outcome>}
type Machine is Data: Machine{frames: List<&2, Frame>, memory: List<&2, BeginMatch>, result: Maybe<&2, Outcome>}

def zero() -> F64: U32.to_f64(0)
def reversedTokens(tokens: List<&2, Token>, onto: List<&2, Token>) -> List<&2, Token>:
  match tokens:
    case Nil{}: onto
    case token <> rest: reversedTokens(rest, token <> onto)
# Each Embed placeholder takes the next embedded result (tokens reversed).
def substituted(tokens: List<&2, Token>, embeds: List<&2, List<&2, Token>>, reversed: List<&2, Token>) -> List<&2, Token>:
  match tokens embeds:
    case Nil{} _: reversedTokens(reversed, Nil{})
    case Embed{} <> rest embed <> more: substituted(rest, more, reversedTokens(embed, reversed))
    case token <> rest embeds: substituted(rest, embeds, token <> reversed)
def resolved(host: Hosted, embeds: List<&2, List<&2, Token>>, relevance: F64) -> Outcome:
  match host:
    case Hosted{language, tokens, top, Completed{}}: Outcome{language, substituted(tokens, List.reverse(&2, List<&2, Token>, embeds), Nil{}), F64.floor(relevance), top, Completed{}}
    case Hosted{language, tokens, top, status}: Outcome{language, substituted(tokens, List.reverse(&2, List<&2, Token>, embeds), Nil{}), zero(), top, status}
# addSublanguage: the result's tokens under a node of the language's name.
def embedding(outcome: Outcome) -> List<&2, Token>:
  match outcome:
    case Outcome{Some{name}, tokens, _, _, _}: OpenNode{name, True{}} <> List.append(&2, Token, tokens, [CloseNode{}])
    case Outcome{None{}, tokens, _, _, _}: tokens
def jobCounted(job: Job) -> Bool:
  match job: case Job{_, _, counted}: counted
def countedRelevance(counted: Bool, outcome: Outcome) -> F64:
  match counted outcome:
    case True{} Outcome{_, _, relevance, _, _}: relevance
    case False{} _: zero()
def continuedWith(continuations: List<&2, Continuation>, +language: String, +top: List<&2, Nat>) -> List<&2, Continuation>:
  match continuations:
    case Nil{}: [Continuation{language, top}]
    case Continuation{+other, stack} <> +rest: Bool.pick(Unit -> List<&2, Continuation>, String.eq(other, language), _ => Continuation{language, top} <> rest, _ => Continuation{other, stack} <> continuedWith(rest, language, top))(Unit{})
def recordedContinuation(job: Job, outcome: Outcome, continuations: List<&2, Continuation>) -> List<&2, Continuation>:
  match job outcome:
    case Job{Named{name}, _, _} Outcome{_, _, _, top, _}: continuedWith(continuations, name, top)
    case _ _: continuations
def continuationOf(continuations: List<&2, Continuation>, +language: String) -> List<&2, Nat>:
  match continuations:
    case Nil{}: Nil{}
    case Continuation{other, top} <> rest: Bool.pick(Unit -> List<&2, Nat>, String.eq(other, language), _ => top, _ => continuationOf(rest, language))(Unit{})

# highlightAuto's ordering: relevance, then a language before its superset.
def supersetFrom(info: Maybe<&2, LanguageInfo>) -> Maybe<&2, String>:
  match info:
    case Some{LanguageInfo{_, _, _, superset}}: superset
    case None{}: None{}
def supersetOf(registry: Registry, name: String) -> Maybe<&2, String>: supersetFrom(getLanguage(registry, name))
def sameName(name: Maybe<&2, String>, +other: String) -> Bool:
  match name:
    case Some{value}: String.eq(value, other)
    case None{}: False{}
# compare(a, b) < 0: a sorts before b.
def before(+registry: Registry, a: Outcome, b: Outcome) -> Bool:
  match a b:
    case Outcome{Some{+left}, _, +x, _, _} Outcome{Some{+right}, _, +y, _, _}:
      Bool.pick(Unit -> Bool, F64.is_eq(x, y), _ => Bool.not(sameName(supersetOf(registry, left), right)) && sameName(supersetOf(registry, right), left), _ => F64.is_gt(x, y))(Unit{})
    case Outcome{_, _, x, _, _} Outcome{_, _, y, _, _}: F64.is_gt(x, y)
def inserted(+registry: Registry, +outcome: Outcome, sorted: List<&2, Outcome>) -> List<&2, Outcome>:
  match sorted:
    case Nil{}: [outcome]
    case +head <> +rest: Bool.pick(Unit -> List<&2, Outcome>, before(registry, outcome, head), _ => outcome <> head <> rest, _ => head <> inserted(registry, outcome, rest))(Unit{})
def sortedResults(+registry: Registry, results: List<&2, Outcome>, sorted: List<&2, Outcome>) -> List<&2, Outcome>:
  match results:
    case Nil{}: sorted
    case outcome <> rest: sortedResults(registry, rest, inserted(registry, outcome, sorted))
def bestOf(sorted: List<&2, Outcome>) -> Outcome:
  match sorted:
    case best <> _: best
    case Nil{}: Outcome{None{}, Nil{}, zero(), Nil{}, Completed{}}
def addTokens(text: String) -> List<&2, Token>:
  match text:
    case "": Nil{}
    case text: [Text{text}]
def plaintext(code: List<&2, U32>) -> Outcome: Outcome{None{}, addTokens(forwardText(code)), zero(), Nil{}, Completed{}}
def detectableNames(+registry: Registry, names: List<&2, String>, +reversed: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: List.reverse(&2, String, reversed)
    case +name <> rest: detectableNames(registry, rest, Bool.pick(List<&2, String>, autoDetection(registry, name), name <> reversed, reversed))
# languageSubset.filter(getLanguage).filter(autoDetection)
def candidates(+registry: Registry, names: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: detectableNames(registry, listLanguages(registry), Nil{})
    case names: detectableNames(registry, names, Nil{})

def contextFor(+registry: Registry, grammars: Grammars, +name: String, code: List<&2, U32>, ignoreIllegals: Bool) -> Maybe<&2, Context>:
  Maybe.bind(&2, LanguageInfo, Context, getLanguage(registry, name), info => Maybe.map(&2, Language, Context, language => Context{language, name, code, ignoreIllegals, registry}, grammarOf(grammars, infoName(info))))
def runFrame(context: Maybe<&2, Context>, +name: String, stack: List<&2, Nat>, memory: List<&2, BeginMatch>) -> Frame:
  match context:
    case Some{value}: Scanning{newRun(value, stack, memory)}
    case None{}: Resolving{Hosted{Some{name}, Nil{}, Nil{}, Failed{}}, Nil{}, Nil{}, zero(), Nil{}}
def jobFrame(+registry: Registry, grammars: Grammars, job: Job, continuations: List<&2, Continuation>, memory: List<&2, BeginMatch>) -> Frame:
  match job:
    case Job{Named{+name}, +code, _}: runFrame(contextFor(registry, grammars, name, code, True{}), name, continuationOf(continuations, name), memory)
    case Job{Detect{names}, code, _}: Detecting{code, candidates(registry, names), Nil{}}

def delivered(+outcome: Outcome, frames: List<&2, Frame>, memory: List<&2, BeginMatch>, result: Maybe<&2, Outcome>) -> Machine:
  match frames:
    case Nil{}: Machine{Nil{}, memory, Some{outcome}}
    case Resolving{host, +job <> jobs, embeds, relevance, continuations} <> rest:
      Machine{Resolving{host, jobs, embedding(outcome) <> embeds, F64.add(relevance, countedRelevance(jobCounted(job), outcome)), recordedContinuation(job, outcome, continuations)} <> rest, memory, result}
    case Detecting{code, _ <> names, results} <> rest: Machine{Detecting{code, names, outcome <> results} <> rest, memory, result}
    case frames: Machine{frames, memory, result}
def outputJobs(output: Output) -> List<&2, Job>:
  match output: case Output{_, _, _, jobs, _}: List.reverse(&2, Job, jobs)
def outputRelevance(output: Output) -> F64:
  match output: case Output{_, _, relevance, _, _}: relevance
def tokensOf(emitter: Emitter) -> List<&2, Token>:
  match emitter: case Emitter{tokens, _}: List.reverse(&2, Token, tokens)
def outputTokens(output: Output) -> List<&2, Token>:
  match output: case Output{_, emitter, _, _, _}: tokensOf(closeAllNodes(emitter))
def runName(run: Run) -> String:
  match run: case Run{Context{_, name, _, _, _}, _, _}: name
def stepped(step: Step, rest: List<&2, Frame>, result: Maybe<&2, Outcome>, memory: List<&2, BeginMatch>) -> Machine:
  match step:
    case Stepping{run}: Machine{Scanning{run} <> rest, memory, result}
    case Finished{Run{_, _, output}, Illegal{}}: delivered(Outcome{None{}, Nil{}, zero(), Nil{}, Illegal{}}, rest, outputMemory(output), result)
    case Finished{Run{Context{_, name, _, _, _}, State{stack, _, _, _, _, _}, +output}, status}:
      Machine{Resolving{Hosted{Some{name}, outputTokens(output), stack, status}, outputJobs(output), Nil{}, outputRelevance(output), Nil{}} <> rest, outputMemory(output), result}

def machineStep(+registry: Registry, +grammars: Grammars, machine: Machine) -> Machine:
  match machine:
    case Machine{Scanning{run} <> rest, memory, result}: stepped(scanStep(run), rest, result, memory)
    case Machine{Resolving{host, Nil{}, embeds, relevance, _} <> rest, memory, result}: delivered(resolved(host, embeds, relevance), rest, memory, result)
    case Machine{Resolving{host, +job <> jobs, embeds, relevance, +continuations} <> rest, +memory, result}:
      Machine{jobFrame(registry, grammars, job, continuations, memory) <> Resolving{host, job <> jobs, embeds, relevance, continuations} <> rest, memory, result}
    case Machine{Detecting{+code, Nil{}, results} <> rest, memory, result}: delivered(bestOf(sortedResults(registry, plaintext(code) <> List.reverse(&2, Outcome, results), Nil{})), rest, memory, result)
    case Machine{Detecting{+code, +name <> names, results} <> rest, +memory, result}:
      Machine{runFrame(contextFor(registry, grammars, name, code, False{}), name, Nil{}, memory) <> Detecting{code, name <> names, results} <> rest, memory, result}
    case other: other
def drive(fuel: Nat, +registry: Registry, +grammars: Grammars, machine: Machine) -> Machine:
  match fuel machine:
    case _ Machine{Nil{}, memory, result}: Machine{Nil{}, memory, result}
    case Succ{more} other: drive(more, registry, grammars, machineStep(registry, grammars, other))
    case Zero{} other: other

# Highlighting
# ------------

# hljs.highlight's result (`language` is none for highlightAuto's plain-text
# result); `tokens` is the TokenTree walk that `value` renders as HTML.
type HighlightResult is Data: HighlightResult{language: Maybe<&2, String>, relevance: F64, tokens: List<&2, Token>, illegal: Bool}
def machineResult(+code: String, machine: Machine) -> HighlightResult:
  match machine:
    case Machine{_, _, Some{Outcome{language, tokens, relevance, _, Completed{}}}}: HighlightResult{language, relevance, tokens, False{}}
    case Machine{_, _, Some{Outcome{_, _, _, _, Illegal{}}}}: HighlightResult{None{}, zero(), addTokens(code), True{}}
    case Machine{_, _, Some{Outcome{language, _, _, _, Failed{}}}}: HighlightResult{language, zero(), addTokens(code), False{}}
    case _: HighlightResult{None{}, zero(), addTokens(code), False{}}
def driven(+registry: Registry, +grammars: Grammars, +input: List<&2, U32>, frame: Frame) -> Machine:
  drive(1000000n + 64n * countFrom(input, 0n), registry, grammars, Machine{[frame], Nil{}, None{}})
# hljs.highlight(code, {language, ignoreIllegals}); none for an unknown
# language (highlight.js throws). A run that fails (highlight.js's safe-mode
# errors, or grammar data that is not loaded) yields the plain code.
def highlight(+registry: Registry, +grammars: Grammars, +code: String, +language: String, ignoreIllegals: Bool) -> Maybe<&2, HighlightResult>:
  +input = Re.codes(code)
  Maybe.map(&2, LanguageInfo, HighlightResult, _ => machineResult(code, driven(registry, grammars, input, runFrame(contextFor(registry, grammars, language, input, ignoreIllegals), language, Nil{}, Nil{}))), getLanguage(registry, language))
# The languages hljs.highlightAuto tries: the subset (or every registered
# language) that is registered and allows auto-detection.
def autoCandidates(+registry: Registry, subset: Maybe<&2, List<&2, String>>) -> List<&2, String>:
  match subset:
    case None{}: detectableNames(registry, listLanguages(registry), Nil{})
    case Some{names}: detectableNames(registry, names, Nil{})
# hljs.highlightAuto(code, languageSubset): the most relevant result, plain
# text unless a language scores higher.
def highlightAuto(+registry: Registry, +grammars: Grammars, +code: String, subset: Maybe<&2, List<&2, String>>) -> HighlightResult:
  +input = Re.codes(code)
  machineResult(code, driven(registry, grammars, input, Detecting{input, autoCandidates(registry, subset), Nil{}}))

# HTMLRenderer: result.value.
def escapeHtml(text: String, reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{Chr{38}, rest}: escapeHtml(rest, String.reverse("&amp;") ++ reversed)
    case SCon{Chr{60}, rest}: escapeHtml(rest, String.reverse("&lt;") ++ reversed)
    case SCon{Chr{62}, rest}: escapeHtml(rest, String.reverse("&gt;") ++ reversed)
    case SCon{Chr{34}, rest}: escapeHtml(rest, String.reverse("&quot;") ++ reversed)
    case SCon{Chr{39}, rest}: escapeHtml(rest, String.reverse("&#x27;") ++ reversed)
    case SCon{char, rest}: escapeHtml(rest, SCon{char, reversed})
def tokenHtml(token: Token) -> String:
  match token:
    case Text{text}: escapeHtml(text, "")
    case OpenNode{kind, True{}}: "<span class=\"" ++ kind ++ "\">"
    case OpenNode{kind, False{}}: "<span class=\"hljs-" ++ kind ++ "\">"
    case CloseNode{}: "</span>"
    case Embed{}: ""
def htmlFrom(tokens: List<&2, Token>, reversed: List<&2, String>) -> String:
  match tokens:
    case Nil{}: String.join(List.reverse(&2, String, reversed), "")
    case token <> rest: htmlFrom(rest, tokenHtml(token) <> reversed)
def toHtml(tokens: List<&2, Token>) -> String: htmlFrom(tokens, Nil{})

# Loading
# -------
# index.json lists the languages in highlight.js/lib/index.js registration
# order with their metadata (name, aliases, disableAutodetect, supersetOf).

def infoFrom(+fields: R.Record<V.Value>) -> Loaded(LanguageInfo):
  do Result<&2, &2, String, LanguageInfo>:
    aliasValues : List<&2, V.Value> <- arrayOf(R.get(V.Value, fields, "aliases"))
    aliases : List<&2, String> <- textsFrom(aliasValues, Nil{})
    return LanguageInfo{Maybe.default(&2, String, textOf(R.get(V.Value, fields, "name")), ""), aliases, truthy(R.get(V.Value, fields, "disableAutodetect")), textOf(R.get(V.Value, fields, "supersetOf"))}
def infosFrom(values: List<&2, V.Value>, reversed: List<&2, LanguageInfo>) -> Loaded(List<&2, LanguageInfo>):
  match values:
    case Nil{}: Done{List.reverse(&2, LanguageInfo, reversed)}
    case value <> rest:
      do Result<&2, &2, String, List<&2, LanguageInfo>>:
        fields : R.Record<V.Value> <- objectOf(value)
        info : LanguageInfo <- infoFrom(fields)
        infosFrom(rest, info <> reversed)
def indexFrom(+fields: R.Record<V.Value>) -> Loaded(List<&2, LanguageInfo>):
  do Result<&2, &2, String, List<&2, LanguageInfo>>:
    languageValues : List<&2, V.Value> <- arrayOf(R.get(V.Value, fields, "languages"))
    infosFrom(languageValues, Nil{})
def parsedIndex(result: Result<&2, &2, Json.ParseError, V.Value>) -> Loaded(List<&2, LanguageInfo>):
  match result:
    case Done{V.ObjectValue{fields}}: indexFrom(fields)
    case _: Fail{"invalid highlight index"}
def parseIndex(text: String) -> Loaded(List<&2, LanguageInfo>): parsedIndex(Json.parse(text))

def utf8Text(result: Result<&2, &2, Utf8.Error, String>, path: String) -> Loaded(String):
  match result:
    case Done{text}: Done{text}
    case Fail{_}: Fail{"invalid UTF-8 in " ++ path}
def readBytes(result: Result<&2, &2, FS.Error, List<&2, U32>>, path: String) -> Loaded(String):
  match result:
    case Done{bytes}: utf8Text(Utf8.decodeStrict(bytes), path)
    case Fail{_}: Fail{"cannot read " ++ path}
def readText(+path: String) -> IO(Loaded(String)):
  do IO<Result<&2, &2, String, String>>:
    bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
    return readBytes(bytes, path)
def loadIndex(directory: String) -> IO(Loaded(List<&2, LanguageInfo>)):
  do IO<Result<&2, &2, String, List<&2, LanguageInfo>>>:
    text : Result<&2, &2, String, String> <- readText(Path.join(directory, "index.json"))
    return Result.bind(&2, &2, String, String, List<&2, LanguageInfo>, text, parseIndex)
def loadLanguage(directory: String, name: String) -> IO(Loaded(Language)):
  do IO<Result<&2, &2, String, Language>>:
    text : Result<&2, &2, String, String> <- readText(Path.join(directory, name ++ ".json"))
    return Result.bind(&2, &2, String, String, Language, text, parseLanguage)

# The registered languages a language's sub-language modes can highlight
# with (a named language when registered, detection candidates otherwise).
def resolvedNames(+registry: Registry, names: List<&2, String>, +reversed: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: reversed
    case name <> rest: resolvedNames(registry, rest, Maybe.default(&2, List<&2, String>, Maybe.map(&2, LanguageInfo, List<&2, String>, info => infoName(info) <> reversed, getLanguage(registry, name)), reversed))
def referenced(+registry: Registry, subs: List<&2, SubLanguage>, +found: List<&2, String>) -> List<&2, String>:
  match subs:
    case Nil{}: found
    case Named{+name} <> rest: referenced(registry, rest, Bool.pick(List<&2, String>, Maybe.is_none(&2, LanguageInfo, registeredNamed(registry, name)), found, name <> found))
    case Detect{names} <> rest: referenced(registry, rest, resolvedNames(registry, candidates(registry, names), found))
def subLanguageNames(+registry: Registry, language: Language, rest: List<&2, String>) -> List<&2, String>:
  match language: case Language{_, _, _, _, _, subs}: referenced(registry, subs, rest)
def visited(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case other <> rest: String.eq(other, name) || visited(rest, name)
def cachedOr(known: Maybe<&2, Language>, directory: String, name: String) -> IO(Loaded(Language)):
  match known:
    case Some{language}: IO.pure(Result<&2, &2, String, Language>, Done{language})
    case None{}: loadLanguage(directory, name)
def withLoaded(grammars: Grammars, +name: String, loaded: Loaded(Language)) -> Grammars:
  match loaded:
    case Done{language}: withGrammar(grammars, name, language)
    case Fail{_}: grammars
def namesAfter(+registry: Registry, loaded: Loaded(Language), rest: List<&2, String>) -> List<&2, String>:
  match loaded:
    case Done{language}: subLanguageNames(registry, language, rest)
    case Fail{_}: rest
def prepareLoop(fuel: Nat, +directory: String, +registry: Registry, +grammars: Grammars, pending: List<&2, String>, +seen: List<&2, String>) -> IO(Grammars):
  match fuel pending:
    case Succ{+more} +name <> +rest:
      Bool.pick(Unit -> IO(Grammars), visited(seen, name),
        _ => prepareLoop(more, directory, registry, grammars, rest, seen),
        _ => do IO<Grammars>:
          +loaded : Result<&2, &2, String, Language> <- cachedOr(grammarOf(grammars, name), directory, name)
          prepareLoop(more, directory, registry, withLoaded(grammars, name, loaded), namesAfter(registry, loaded, rest), name <> seen))(Unit{})
    case _ _: IO.pure(Grammars, grammars)
# Loads the grammars highlighting with `names` can use from `directory`: the
# languages and, transitively, their registered sub-languages.
def prepareAll(directory: String, +registry: Registry, grammars: Grammars, names: List<&2, String>) -> IO(Grammars):
  prepareLoop(100000n, directory, registry, grammars, resolvedNames(registry, names, Nil{}), Nil{})
def prepare(directory: String, registry: Registry, grammars: Grammars, name: String) -> IO(Grammars): prepareAll(directory, registry, grammars, [name])
