import Base
import ./u32-table.bend as Table
import ./unicode-bidi-class.bend as Bidi
import ./unicode-joining-type.bend as Joining

type Properties is Data:
  Properties{bidi: Bidi.Class, joining: Joining.JoiningType, combiningClass: U32, mark: Bool}

type Entry is Data:
  Entry{last: U32, properties: Properties}

def bounded(inside: Bool, properties: Properties) -> Maybe<&2, Properties>:
  match inside:
    case True{}: Some{properties}
    case False{}: None{}

def found(code: U32, value: Maybe<&2, Entry>) -> Maybe<&2, Properties>:
  match value:
    case None{}: None{}
    case Some{Entry{last, properties}}: bounded(U32.is_le(code, last), properties)

# Numeric property lookup also covers surrogates/unassigned code points. It
# constructs no Char and does not imply that a code point is valid in IDNA.
def lookup(table: Table.Table<Entry>, +code: U32) -> Maybe<&2, Properties>:
  found(code, Table.floor(Entry, table, code))
