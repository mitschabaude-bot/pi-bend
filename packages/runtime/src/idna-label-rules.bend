import Base
import ./u32-table.bend as Table
import ./idna-mapping.bend as Mapping
import ./idna-mapping-data.bend as Data

type Options is Data:
  Options{checkHyphens: Bool, useSTD3: Bool, mode: Mapping.Mode}

type Error is Data:
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

def hyphenFailure(positions: Bool, edge: Bool) -> Maybe<&2, Error>:
  match positions edge:
    case True{} _: Some{HyphenPositions{}}
    case False{} True{}: Some{HyphenEdge{}}
    case _ _: None{}

def prefixFailure(reserved: Bool) -> Maybe<&2, Error>:
  match reserved:
    case True{}: Some{ReservedPrefix{}}
    case False{}: None{}

def hyphens(enabled: Bool, +text: String) -> Maybe<&2, Error>:
  match enabled:
    case True{}: hyphenFailure(hyphenPositions(text), hyphenEdge(text))
    case False{}: prefixFailure(reservedPrefix(text))

def asciiAllowed(+code: U32) -> Bool:
  U32.is_gt(code, 127) || U32.is_eq(code, 45) ||
    (U32.is_ge(code, 48) && U32.is_le(code, 57)) ||
    (U32.is_ge(code, 97) && U32.is_le(code, 122))

def asciiFailure(valid: Bool, code: U32) -> Maybe<&2, Error>:
  match valid:
    case True{}: None{}
    case False{}: Some{InvalidASCII{code}}

def punctuation(+code: U32, std3: Bool) -> Maybe<&2, Error>:
  match code:
    case 46: Some{Dot{}}
    case _: asciiFailure(Bool.not(std3) || asciiAllowed(code), code)

def syntaxScan(text: String, +std3: Bool, failure: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match text failure:
    case _ Some{error}: Some{error}
    case SNil{} None{}: None{}
    case SCon{Chr{code}, rest} None{}: syntaxScan(rest, std3, punctuation(code, std3))

# Input is an already mapped or ACE-decoded label. Empty labels are left to
# domain/DNS length policy. This function neither maps nor normalizes text.
def syntax(+text: String, checkHyphens: Bool, std3: Bool) -> Maybe<&2, Error>:
  syntaxScan(text, std3, hyphens(checkHyphens, text))

def statusAllowed(mode: Mapping.Mode, value: Maybe<&2, Data.Status>) -> Bool:
  match mode value:
    case _ Some{Data.Valid{}}: True{}
    case Mapping.Nontransitional{} Some{Data.Deviation{_}}: True{}
    case _ _: False{}

def statusFailure(valid: Bool, code: U32) -> Maybe<&2, Error>:
  match valid:
    case True{}: None{}
    case False{}: Some{InvalidStatus{code}}

def statusScan(text: String, +table: Table.Table<Data.Entry>, +mode: Mapping.Mode, failure: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match text failure:
    case _ Some{error}: Some{error}
    case SNil{} None{}: None{}
    case SCon{Chr{+code}, rest} None{}:
      statusScan(rest, table, mode, statusFailure(statusAllowed(mode, Mapping.lookup(table, code)), code))

def check(table: Table.Table<Data.Entry>, options: Options, +text: String) -> Maybe<&2, Error>:
  match options:
    case Options{checkHyphens, std3, mode}: statusScan(text, table, mode, syntax(text, checkHyphens, std3))
