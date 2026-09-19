import Base
import ./u32-table.bend as Table
import ./idna-mapping-data.bend as Data

type Mode is Data:
  Nontransitional{}
  Transitional{}

type MappingError is Data:
  Disallowed{code: U32}

def bounded(inside: Bool, status: Data.Status) -> Maybe<&2, Data.Status>:
  match inside:
    case True{}: Some{status}
    case False{}: None{}

def entry(code: U32, value: Maybe<&2, Data.Entry>) -> Maybe<&2, Data.Status>:
  match value:
    case None{}: None{}
    case Some{Data.Entry{last, status}}: bounded(U32.is_le(code, last), status)

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

def prepend(text: String, reversed: String) -> String:
  match text:
    case SNil{}: reversed
    case SCon{char, rest}: prepend(rest, SCon{char, reversed})

def appended(result: Result<&2, &2, MappingError, String>, reversed: String) -> Result<&2, &2, MappingError, String>:
  match result:
    case Fail{error}: Fail{error}
    case Done{text}: Done{prepend(text, reversed)}

def scan(text: String, +table: Table.Table<Data.Entry>, +mode: Mode, state: Result<&2, &2, MappingError, String>) -> Result<&2, &2, MappingError, String>:
  match text state:
    case _ Fail{error}: Fail{error}
    case SNil{} Done{reversed}: Done{String.reverse(reversed)}
    case SCon{Chr{code}, rest} Done{reversed}: scan(rest, table, mode, appended(codePoint(table, mode, code), reversed))

# Mapping only: controls/punctuation that are valid here can still be invalid
# URL hosts. Normalization and label/host validity are separate stages.
def map(table: Table.Table<Data.Entry>, mode: Mode, text: String) -> Result<&2, &2, MappingError, String>:
  scan(text, table, mode, Done{""})
