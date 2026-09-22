import Base
import ./unicode.bend as Data
import ./u32-table.bend as Table
import ./punycode.bend as Punycode
import ./string.bend as Split


# RFC 5893 section 2. The caller applies validity to every label if any label
# contains R, AL or AN. This rule does not replace IDNA mapping/label validity.
type DirectionState is Data:
  Initial{}
  Left{terminal: Bool}
  Right{terminal: Bool, european: Bool, arabic: Bool}
  Invalid{}

type State is Data:
  State{direction: DirectionState, hasRTL: Bool}

type Analysis is Data:
  Analysis{hasRTL: Bool, valid: Bool}

def start() -> State:
  State{Initial{}, False{}}

def rtlClass(value: Data.Class) -> Bool:
  match value:
    case Data.R{}: True{}
    case Data.AL{}: True{}
    case Data.AN{}: True{}
    case _: False{}

def initial(value: Data.Class) -> DirectionState:
  match value:
    case Data.L{}: Left{True{}}
    case Data.R{}: Right{True{}, False{}, False{}}
    case Data.AL{}: Right{True{}, False{}, False{}}
    case _: Invalid{}

def left(value: Data.Class, terminal: Bool) -> DirectionState:
  match value:
    case Data.L{}: Left{True{}}
    case Data.EN{}: Left{True{}}
    case Data.NSM{}: Left{terminal}
    case Data.ES{}: Left{False{}}
    case Data.CS{}: Left{False{}}
    case Data.ET{}: Left{False{}}
    case Data.ON{}: Left{False{}}
    case Data.BN{}: Left{False{}}
    case _: Invalid{}

def right(value: Data.Class, terminal: Bool, european: Bool, arabic: Bool) -> DirectionState:
  match value:
    case Data.R{}: Right{True{}, european, arabic}
    case Data.AL{}: Right{True{}, european, arabic}
    case Data.EN{}: Right{True{}, True{}, arabic}
    case Data.AN{}: Right{True{}, european, True{}}
    case Data.NSM{}: Right{terminal, european, arabic}
    case Data.ES{}: Right{False{}, european, arabic}
    case Data.CS{}: Right{False{}, european, arabic}
    case Data.ET{}: Right{False{}, european, arabic}
    case Data.ON{}: Right{False{}, european, arabic}
    case Data.BN{}: Right{False{}, european, arabic}
    case _: Invalid{}

def advance(state: DirectionState, value: Data.Class) -> DirectionState:
  match state:
    case Initial{}: initial(value)
    case Left{terminal}: left(value, terminal)
    case Right{terminal, european, arabic}: right(value, terminal, european, arabic)
    case Invalid{}: Invalid{}

# Continue collecting hasRTL even after rule failure: a late RTL character
# still makes other labels in the domain subject to the Bidi rule.
def push(state: State, +value: Data.Class) -> State:
  match state:
    case State{direction, hasRTL}: State{advance(direction, value), hasRTL || rtlClass(value)}

def accepted(state: DirectionState) -> Bool:
  match state:
    case Left{terminal}: terminal
    case Right{terminal, european, arabic}: terminal && Bool.not(european && arabic)
    case _: False{}

def finish(state: State) -> Analysis:
  match state:
    case State{direction, hasRTL}: Analysis{hasRTL, accepted(direction)}

def scan(values: List<&2, Data.Class>, state: State) -> Analysis:
  match values:
    case Nil{}: finish(state)
    case value <> rest: scan(rest, push(state, value))

def analyze(values: List<&2, Data.Class>) -> Analysis:
  scan(values, start())


# RFC 5892 Appendix A.1/A.2. Only an immediate CCC=9 predecessor permits ZWJ.
# ZWNJ additionally permits L/D T* ZWNJ T* R/D joining context.
type ContextjState is Data:
  Active{beforeVirama: Bool, leftJoining: Bool, awaitingRight: Bool}
  ContextjInvalid{}

def startContextj() -> ContextjState:
  Active{False{}, False{}, False{}}

def leftContext(value: Data.JoiningType, previous: Bool) -> Bool:
  match value:
    case Data.Transparent{}: previous
    case Data.LeftJoining{}: True{}
    case Data.DualJoining{}: True{}
    case _: False{}

def rightContext(value: Data.JoiningType) -> Bool:
  match value:
    case Data.RightJoining{}: True{}
    case Data.DualJoining{}: True{}
    case _: False{}

def resolved(valid: Bool, beforeVirama: Bool, leftJoining: Bool) -> ContextjState:
  match valid:
    case True{}: Active{beforeVirama, leftJoining, False{}}
    case False{}: ContextjInvalid{}

def ordinary(value: Data.JoiningType, virama: Bool, leftJoining: Bool, awaitingRight: Bool) -> ContextjState:
  match value awaitingRight:
    case Data.Transparent{} waiting: Active{virama, leftJoining, waiting}
    case +other False{}: Active{virama, leftContext(other, False{}), False{}}
    case +other True{}: resolved(rightContext(other), virama, leftContext(other, False{}))

def nonJoiner(beforeVirama: Bool, leftJoining: Bool, awaitingRight: Bool) -> ContextjState:
  match beforeVirama leftJoining awaitingRight:
    case _ _ True{}: ContextjInvalid{}
    case True{} _ False{}: Active{False{}, False{}, False{}}
    case False{} True{} False{}: Active{False{}, False{}, True{}}
    case _ _ _: ContextjInvalid{}

def joiner(beforeVirama: Bool, awaitingRight: Bool) -> ContextjState:
  resolved(beforeVirama && Bool.not(awaitingRight), False{}, False{})

def character(code: U32, joining: Data.JoiningType, virama: Bool, beforeVirama: Bool, leftJoining: Bool, awaitingRight: Bool) -> ContextjState:
  match code:
    case 8204: nonJoiner(beforeVirama, leftJoining, awaitingRight)
    case 8205: joiner(beforeVirama, awaitingRight)
    case _: ordinary(joining, virama, leftJoining, awaitingRight)

# Feed properties of one scalar in logical label order. Join-control properties
# are fixed by Unicode; their identity takes precedence over supplied properties.
def pushContextJ(state: ContextjState, code: U32, joining: Data.JoiningType, combiningClass: U32) -> ContextjState:
  match state:
    case ContextjInvalid{}: ContextjInvalid{}
    case Active{beforeVirama, leftJoining, awaitingRight}:
      character(code, joining, U32.is_eq(combiningClass, 9), beforeVirama, leftJoining, awaitingRight)

def finishContextj(state: ContextjState) -> Bool:
  match state:
    case ContextjInvalid{}: False{}
    case Active{_, _, awaitingRight}: Bool.not(awaitingRight)


type Mode is Data:
  Nontransitional{}
  Transitional{}

type MappingError is Data:
  Disallowed{code: U32}

def boundedMapping(inside: Bool, status: Data.Status) -> Maybe<&2, Data.Status>:
  match inside:
    case True{}: Some{status}
    case False{}: None{}

def entry(code: U32, value: Maybe<&2, Data.Entry>) -> Maybe<&2, Data.Status>:
  match value:
    case None{}: None{}
    case Some{Data.Entry{last, status}}: boundedMapping(U32.is_le(code, last), status)

def lookup(table: Table.Table<Data.Entry>, +code: U32) -> Maybe<&2, Data.Status>:
  entry(code, Table.floor(Data.Entry, table, code))

def deviation(mode: Mode, code: U32, replacement: String) -> String:
  match mode:
    case Nontransitional{}: SCon{Chr{code}, SNil{}}
    case Transitional{}: replacement

# Unicode 16+ maps capital sharp S to small sharp S in the data table.
# UTS #46 section 4 separately requires "ss" for transitional processing.
def mappedReplacement(mode: Mode, code: U32, value: String) -> String:
  match mode code:
    case Transitional{} 7838: "ss"
    case _ _: value

def mapped(mode: Mode, code: U32, status: Maybe<&2, Data.Status>) -> Result<&2, &2, MappingError, String>:
  match status:
    case None{}: Fail{Disallowed{code}}
    case Some{Data.Disallowed{}}: Fail{Disallowed{code}}
    case Some{Data.Valid{}}: Done{SCon{Chr{code}, SNil{}}}
    case Some{Data.Ignored{}}: Done{""}
    case Some{Data.Mapped{value}}: Done{mappedReplacement(mode, code, value)}
    case Some{Data.Deviation{replacement}}: Done{deviation(mode, code, replacement)}

def codePoint(table: Table.Table<Data.Entry>, mode: Mode, +code: U32) -> Result<&2, &2, MappingError, String>:
  mapped(mode, code, lookup(table, code))

def prependMapping(text: String, reversed: String) -> String:
  match text:
    case SNil{}: reversed
    case SCon{char, rest}: prependMapping(rest, SCon{char, reversed})

def appended(result: Result<&2, &2, MappingError, String>, reversed: String) -> Result<&2, &2, MappingError, String>:
  match result:
    case Fail{error}: Fail{error}
    case Done{text}: Done{prependMapping(text, reversed)}

def scanMapping(text: String, +table: Table.Table<Data.Entry>, +mode: Mode, state: Result<&2, &2, MappingError, String>) -> Result<&2, &2, MappingError, String>:
  match text state:
    case _ Fail{error}: Fail{error}
    case SNil{} Done{reversed}: Done{String.reverse(reversed)}
    case SCon{Chr{code}, rest} Done{reversed}: scanMapping(rest, table, mode, appended(codePoint(table, mode, code), reversed))

# Mapping only: controls/punctuation that are valid here can still be invalid
# URL hosts. Normalization and label/host validity are separate stages.
def map(table: Table.Table<Data.Entry>, mode: Mode, text: String) -> Result<&2, &2, MappingError, String>:
  scanMapping(text, table, mode, Done{""})


type LabelContextState is Data:
  LabelContextState{first: Bool, leadingMark: Bool, bidi: State, joiners: ContextjState}

type LabelContextAnalysis is Data:
  LabelContextAnalysis{leadingMark: Bool, bidi: Analysis, joinersValid: Bool}

def mark(first: Bool, previous: Bool, current: Bool) -> Bool:
  match first:
    case True{}: current
    case False{}: previous

def advanceLabelContext(properties: Maybe<&2, Data.Properties>, code: U32, state: LabelContextState) -> Result<&2, &2, U32, LabelContextState>:
  match properties state:
    case None{} _: Fail{code}
    case Some{Data.Properties{direction, joining, combiningClass, isMark}} LabelContextState{first, leadingMark, bidi, joiners}:
      Done{LabelContextState{False{}, mark(first, leadingMark, isMark), push(bidi, direction), pushContextJ(joiners, code, joining, combiningClass)}}

def finishLabelContext(state: LabelContextState) -> LabelContextAnalysis:
  match state:
    case LabelContextState{_, leadingMark, bidi, joiners}: LabelContextAnalysis{leadingMark, finish(bidi), finishContextj(joiners)}

def scanLabelContext(text: String, +table: Table.Table<Data.PropertiesEntry>, state: Result<&2, &2, U32, LabelContextState>) -> Result<&2, &2, U32, LabelContextAnalysis>:
  match text state:
    case _ Fail{code}: Fail{code}
    case SNil{} Done{value}: Done{finishLabelContext(value)}
    case SCon{Chr{+code}, rest} Done{value}: scanLabelContext(rest, table, advanceLabelContext(Data.lookup(table, code), code, value))

# Analyze a prepared, decoded label. The caller still checks mapping status,
# NFC, hyphens, ACE handling and domain-level applicability of the Bidi rule.
def analyzeLabelContext(table: Table.Table<Data.PropertiesEntry>, text: String) -> Result<&2, &2, U32, LabelContextAnalysis>:
  scanLabelContext(text, table, Done{LabelContextState{True{}, False{}, start(), startContextj()}})


type LabelRulesOptions is Data:
  LabelRulesOptions{checkHyphens: Bool, useSTD3: Bool, mode: Mode}

type LabelRulesError is Data:
  HyphenPositions{}
  HyphenEdge{}
  ReservedPrefix{}
  Dot{}
  InvalidASCII{code: U32}
  InvalidStatus{code: U32}

def hyphenPositions(text: String) -> Bool:
  match text:
    case SCon{_, SCon{_, SCon{'-', SCon{'-', _}}}}: True{}
    case _: False{}

def reservedPrefix(text: String) -> Bool:
  match text:
    case SCon{'x', SCon{'n', SCon{'-', SCon{'-', _}}}}: True{}
    case _: False{}

def trailingHyphen(text: String, previous: Bool) -> Bool:
  match text:
    case SNil{}: previous
    case SCon{Chr{code}, rest}: trailingHyphen(rest, U32.is_eq(code, 45))

def hyphenEdge(text: String) -> Bool:
  match text:
    case SCon{'-', _}: True{}
    case other: trailingHyphen(other, False{})

def hyphenFailure(positions: Bool, edge: Bool) -> Maybe<&2, LabelRulesError>:
  match positions edge:
    case True{} _: Some{HyphenPositions{}}
    case False{} True{}: Some{HyphenEdge{}}
    case _ _: None{}

def prefixFailure(reserved: Bool) -> Maybe<&2, LabelRulesError>:
  match reserved:
    case True{}: Some{ReservedPrefix{}}
    case False{}: None{}

def hyphenRule(enabled: Bool, +text: String) -> Maybe<&2, LabelRulesError>:
  match enabled:
    case True{}: hyphenFailure(hyphenPositions(text), hyphenEdge(text))
    case False{}: prefixFailure(reservedPrefix(text))

def asciiAllowed(+code: U32) -> Bool:
  U32.is_gt(code, 127) || U32.is_eq(code, 45) ||
    (U32.is_ge(code, 48) && U32.is_le(code, 57)) ||
    (U32.is_ge(code, 97) && U32.is_le(code, 122))

def asciiFailure(valid: Bool, code: U32) -> Maybe<&2, LabelRulesError>:
  match valid:
    case True{}: None{}
    case False{}: Some{InvalidASCII{code}}

def punctuation(+code: U32, std3: Bool) -> Maybe<&2, LabelRulesError>:
  match code:
    case 46: Some{Dot{}}
    case _: asciiFailure(Bool.not(std3) || asciiAllowed(code), code)

def syntaxScan(text: String, +std3: Bool, failure: Maybe<&2, LabelRulesError>) -> Maybe<&2, LabelRulesError>:
  match text failure:
    case _ Some{error}: Some{error}
    case SNil{} None{}: None{}
    case SCon{Chr{code}, rest} None{}: syntaxScan(rest, std3, punctuation(code, std3))

# Input is an already mapped or ACE-decoded label. Empty labels are left to
# domain/DNS length policy. This function neither maps nor normalizes text.
def syntax(+text: String, checkHyphens: Bool, std3: Bool) -> Maybe<&2, LabelRulesError>:
  syntaxScan(text, std3, hyphenRule(checkHyphens, text))

def statusAllowed(mode: Mode, value: Maybe<&2, Data.Status>) -> Bool:
  match mode value:
    case _ Some{Data.Valid{}}: True{}
    case Nontransitional{} Some{Data.Deviation{_}}: True{}
    case _ _: False{}

def statusFailure(valid: Bool, code: U32) -> Maybe<&2, LabelRulesError>:
  match valid:
    case True{}: None{}
    case False{}: Some{InvalidStatus{code}}

def statusScan(text: String, +table: Table.Table<Data.Entry>, +mode: Mode, failure: Maybe<&2, LabelRulesError>) -> Maybe<&2, LabelRulesError>:
  match text failure:
    case _ Some{error}: Some{error}
    case SNil{} None{}: None{}
    case SCon{Chr{+code}, rest} None{}:
      statusScan(rest, table, mode, statusFailure(statusAllowed(mode, lookup(table, code)), code))

def check(table: Table.Table<Data.Entry>, options: LabelRulesOptions, +text: String) -> Maybe<&2, LabelRulesError>:
  match options:
    case LabelRulesOptions{checkHyphens, std3, mode}: statusScan(text, table, mode, syntax(text, checkHyphens, std3))


type PrepareContext is Data:
  PrepareContext{mapping: Table.Table<Data.Entry>, normalization: Data.Tables}

def normalized(result: Result<&2, &2, MappingError, String>, tables: Data.Tables) -> Result<&2, &2, MappingError, String>:
  match result:
    case Fail{error}: Fail{error}
    case Done{text}: Done{Data.nfc(tables, text)}

# UTS #46 mapping followed by NFC. This is input preparation, not a validated
# domain: label splitting, ACE handling, contextual/Bidi rules and host checks
# still have to run before a result can be used as a hostname.
def prepareInput(context: PrepareContext, mode: Mode, input: String) -> Result<&2, &2, MappingError, String>:
  match context:
    case PrepareContext{mapping, normalization}: normalized(map(mapping, mode, input), normalization)


type Error is Data:
  NonASCIIEncoding{}
  InvalidPunycode{reason: Punycode.Error}
  ASCIIOnlyDecodedLabel{}

type Label is Data:
  Label{text: String, encoded: Bool}

def asciiScan(text: String, ascii: Bool) -> Bool:
  match text:
    case SNil{}: ascii
    case SCon{Chr{code}, rest}: asciiScan(rest, ascii && U32.is_le(code, 127))

def isASCII(text: String) -> Bool:
  asciiScan(text, True{})

def decodedText(ascii: Bool, value: String) -> Result<&2, &2, Error, Label>:
  match ascii:
    case True{}: Fail{ASCIIOnlyDecodedLabel{}}
    case False{}: Done{Label{value, True{}}}

def decoded(value: Result<&2, &2, Punycode.Error, String>) -> Result<&2, &2, Error, Label>:
  match value:
    case Fail{error}: Fail{InvalidPunycode{error}}
    case Done{+text}: decodedText(isASCII(text), text)

def decodeBody(ascii: Bool, text: String) -> Result<&2, &2, Error, Label>:
  match ascii:
    case False{}: Fail{NonASCIIEncoding{}}
    case True{}: decoded(Punycode.decode(text))

# Input has already undergone domain-wide mapping/NFC. ACE output must later be
# validated WITHOUT mapping and always using nontransitional status rules.
# This strict decoder is the IgnoreInvalidPunycode=false path used by URL hosts.
def decode(label: String) -> Result<&2, &2, Error, Label>:
  match label:
    case SCon{'x', SCon{'n', SCon{'-', SCon{'-', +rest}}}}: decodeBody(isASCII(rest), rest)
    case text: Done{Label{text, False{}}}


type Context is Data:
  Context{mapping: Table.Table<Data.Entry>, normalization: Data.Tables, properties: Table.Table<Data.PropertiesEntry>}

type LabelOptions is Data:
  LabelOptions{checkHyphens: Bool, useSTD3: Bool, checkJoiners: Bool, mode: Mode}

type LabelError is Data:
  ACEError{reason: Error}
  NotNFC{}
  LabelRule{reason: LabelRulesError}
  LeadingMark{}
  JoinerContext{}
  MissingProperties{code: U32}

type ValidatedLabel is Data:
  ValidatedLabel{text: String, empty: Bool, bidi: Analysis}

def effectiveMode(encoded: Bool, mode: Mode) -> Mode:
  match encoded:
    case True{}: Nontransitional{}
    case False{}: mode

def contextualResult(analysis: Result<&2, &2, U32, LabelContextAnalysis>, checkJoiners: Bool, +text: String) -> Result<&2, &2, LabelError, ValidatedLabel>:
  match analysis checkJoiners:
    case Fail{code} _: Fail{MissingProperties{code}}
    case Done{LabelContextAnalysis{True{}, _, _}} _: Fail{LeadingMark{}}
    case Done{LabelContextAnalysis{False{}, _, False{}}} True{}: Fail{JoinerContext{}}
    case Done{LabelContextAnalysis{False{}, bidi, _}} _: Done{ValidatedLabel{text, String.is_empty(text), bidi}}

def afterRules(failure: Maybe<&2, LabelRulesError>, properties: Table.Table<Data.PropertiesEntry>, checkJoiners: Bool, +text: String) -> Result<&2, &2, LabelError, ValidatedLabel>:
  match failure:
    case Some{error}: Fail{LabelRule{error}}
    case None{}: contextualResult(analyzeLabelContext(properties, text), checkJoiners, text)

def afterNFC(normalized: Bool, mapping: Table.Table<Data.Entry>, properties: Table.Table<Data.PropertiesEntry>, rules: LabelRulesOptions, checkJoiners: Bool, +text: String) -> Result<&2, &2, LabelError, ValidatedLabel>:
  match normalized:
    case False{}: Fail{NotNFC{}}
    case True{}: afterRules(check(mapping, rules, text), properties, checkJoiners, text)

def validate(context: Context, options: LabelOptions, label: Label) -> Result<&2, &2, LabelError, ValidatedLabel>:
  match context options label:
    case Context{mapping, normalization, properties} LabelOptions{hyphens, std3, joiners, mode} Label{+text, encoded}:
      afterNFC(String.eq(text, Data.nfc(normalization, text)), mapping, properties,
        LabelRulesOptions{hyphens, std3, effectiveMode(encoded, mode)}, joiners, text)

def afterDecode(result: Result<&2, &2, Error, Label>, context: Context, options: LabelOptions) -> Result<&2, &2, LabelError, ValidatedLabel>:
  match result:
    case Fail{error}: Fail{ACEError{error}}
    case Done{label}: validate(context, options, label)

# Strict conversion/validation of one label AFTER domain-wide mapping/NFC and
# splitting. ACE output is checked without repair. Empty-label/DNS-length and
# domain-wide Bidi decisions remain with the domain processor; skip Bidi validity
# for empty labels and apply it to every nonempty label in a Bidi domain.
def process(context: Context, options: LabelOptions, input: String) -> Result<&2, &2, LabelError, ValidatedLabel>:
  afterDecode(decode(input), context, options)


type BidiState is Data:
  BidiState{hasRTL: Bool, labelsValid: Bool}

def bidiStart() -> BidiState:
  BidiState{False{}, True{}}

def bidiPush(state: BidiState, label: ValidatedLabel) -> BidiState:
  match state label:
    case BidiState{rtl, valid} ValidatedLabel{_, empty, Analysis{labelRTL, labelValid}}:
      BidiState{rtl || labelRTL, valid && (empty || labelValid)}

def bidiFinish(state: BidiState) -> Bool:
  match state:
    case BidiState{rtl, valid}: Bool.not(rtl) || valid

def bidiScan(labels: List<&2, ValidatedLabel>, state: BidiState) -> Bool:
  match labels:
    case Nil{}: bidiFinish(state)
    case label <> rest: bidiScan(rest, bidiPush(state, label))

# Every nonempty label participates, regardless of where RTL was encountered.
def bidiValid(labels: List<&2, ValidatedLabel>) -> Bool:
  bidiScan(labels, bidiStart())

type Length is Data:
  Length{size: U32, ascii: Bool}

type DNSState is Data:
  DNSState{used: U32, valid: Bool}

# Saturate above all relevant bounds so arbitrary input lengths cannot wrap.
def bounded(value: U32, exceeds: Bool) -> U32:
  match exceeds:
    case True{}: 255
    case False{}: value

def add(+left: U32, +right: U32) -> U32:
  bounded((left + right : U32), U32.is_gt((left + right : U32), 255))

def lengthScan(text: String, size: U32, ascii: Bool) -> Length:
  match text:
    case SNil{}: Length{size, ascii}
    case SCon{Chr{code}, rest}: lengthScan(rest, add(size, 1), ascii && U32.is_le(code, 127))

def dnsPush(state: DNSState, value: Length) -> DNSState:
  match state value:
    case DNSState{used, valid} Length{+size, ascii}:
      DNSState{add(used, add(size, 1)), valid && ascii && U32.is_gt(size, 0) && U32.is_le(size, 63)}

def dnsFinish(state: DNSState) -> Bool:
  match state:
    case DNSState{+used, valid}: valid && U32.is_gt(used, 0) && U32.is_le(used, 254)

def dnsScan(labels: List<&2, String>, state: DNSState) -> Bool:
  match labels:
    case Nil{}: dnsFinish(state)
    case label <> rest: dnsScan(rest, dnsPush(state, lengthScan(label, 0, True{})))

# Input is a list of already-ASCII labels, after Punycode conversion. A final
# empty root label also fails when UTS #46 VerifyDnsLength is enabled. used
# includes one separator per label, hence the 254 bound represents at most
# 253 ASCII characters. URL hosts can disable this entire strict length check.
def dnsLengthValid(labels: List<&2, String>) -> Bool:
  dnsScan(labels, DNSState{0, True{}})


type Options is Data:
  Options{label: LabelOptions, checkBidi: Bool, verifyDNSLength: Bool}

type DomainError is Data:
  Preparation{reason: MappingError}
  InvalidLabel{index: Nat, reason: LabelError}
  Encoding{index: Nat, reason: Punycode.Error}
  BidiDomain{}
  DNSLength{}

type DomainState is Data:
  DomainState{index: Nat, reversed: List<&2, String>, bidi: BidiState}

def prepend(text: String, reversed: String) -> String:
  match text:
    case SNil{}: reversed
    case SCon{char, rest}: prepend(rest, SCon{char, reversed})

def separator(first: Bool, reversed: String) -> String:
  match first:
    case True{}: reversed
    case False{}: SCon{'.', reversed}

def join(labels: List<&2, String>, first: Bool, reversed: String) -> String:
  match labels:
    case Nil{}: String.reverse(reversed)
    case label <> rest: join(rest, False{}, prepend(label, separator(first, reversed)))

def asciiResult(result: Result<&2, &2, Punycode.Error, String>) -> Result<&2, &2, Punycode.Error, String>:
  match result:
    case Fail{error}: Fail{error}
    case Done{text}: Done{"xn--" ++ text}

def encode(ascii: Bool, text: String) -> Result<&2, &2, Punycode.Error, String>:
  match ascii:
    case True{}: Done{text}
    case False{}: asciiResult(Punycode.encode(text))

def afterEncoding(result: Result<&2, &2, Punycode.Error, String>, label: ValidatedLabel, state: DomainState) -> Result<&2, &2, DomainError, DomainState>:
  match result state:
    case Fail{error} DomainState{index, _, _}: Fail{Encoding{index, error}}
    case Done{text} DomainState{index, reversed, bidi}: Done{DomainState{Succ{index}, text <> reversed, bidiPush(bidi, label)}}

def encodeLabel(label: ValidatedLabel, state: DomainState) -> Result<&2, &2, DomainError, DomainState>:
  match label:
    case ValidatedLabel{+text, empty, bidi}:
      afterEncoding(encode(isASCII(text), text), ValidatedLabel{text, empty, bidi}, state)

def afterLabel(result: Result<&2, &2, LabelError, ValidatedLabel>, state: DomainState) -> Result<&2, &2, DomainError, DomainState>:
  match result state:
    case Fail{error} DomainState{index, _, _}: Fail{InvalidLabel{index, error}}
    case Done{label} previous: encodeLabel(label, previous)

def completed(bidiValid: Bool, dnsValid: Bool, labels: List<&2, String>) -> Result<&2, &2, DomainError, String>:
  match bidiValid dnsValid:
    case False{} _: Fail{BidiDomain{}}
    case True{} False{}: Fail{DNSLength{}}
    case True{} True{}: Done{join(labels, True{}, "")}

def checkLength(enabled: Bool, labels: List<&2, String>) -> Bool:
  match enabled:
    case False{}: True{}
    case True{}: dnsLengthValid(labels)

def finishDomain(state: DomainState, checkBidi: Bool, verifyDNSLength: Bool) -> Result<&2, &2, DomainError, String>:
  match state:
    case DomainState{_, +reversed, bidi}:
      completed(Bool.not(checkBidi) || bidiFinish(bidi), checkLength(verifyDNSLength, reversed), List.reverse(&2, String, reversed))

def scanDomain(labels: List<&2, String>, +context: Context, +options: LabelOptions, checkBidi: Bool, verifyDNSLength: Bool, state: Result<&2, &2, DomainError, DomainState>) -> Result<&2, &2, DomainError, String>:
  match labels state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{value}: finishDomain(value, checkBidi, verifyDNSLength)
    case label <> rest Done{value}: scanDomain(rest, context, options, checkBidi, verifyDNSLength, afterLabel(process(context, options, label), value))

def prepared(result: Result<&2, &2, MappingError, String>, context: Context, options: Options) -> Result<&2, &2, DomainError, String>:
  match result options:
    case Fail{error} _: Fail{Preparation{error}}
    case Done{text} Options{label, checkBidi, verifyDNSLength}:
      scanDomain(Split.split(text, '.'), context, label, checkBidi, verifyDNSLength, Done{DomainState{0n, Nil{}, bidiStart()}})

def prepare(context: Context, options: LabelOptions, input: String) -> Result<&2, &2, MappingError, String>:
  match context options:
    case Context{mapping, normalization, _} LabelOptions{_, _, _, mode}:
      prepareInput(PrepareContext{mapping, normalization}, mode, input)

# Strict UTS #46 ToASCII with explicit flags and reusable immutable Unicode
# tables. No default URL compatibility policy is selected here. URL host parsing
# must additionally reject forbidden host characters and handle numeric hosts.
def toASCII(+context: Context, options: Options, input: String) -> Result<&2, &2, DomainError, String>:
  match options:
    case Options{+label, +checkBidi, +verifyDNSLength}:
      prepared(prepare(context, label, input), context, Options{label, checkBidi, verifyDNSLength})
