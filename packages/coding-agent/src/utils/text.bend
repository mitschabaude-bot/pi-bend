import Base

# A leading BOM is file metadata; interior marks remain text.
type SplitBom is Data:
  SplitBom{bom: String, text: String}

def splitBom(+content: String) -> SplitBom:
  match content:
    case SNil{}: SplitBom{"", ""}
    case SCon{+char, +rest}:
      Bool.pick(Unit -> SplitBom, Char.is_eq(char, '\u{feff}'), _ => SplitBom{SCon{char, SNil{}}, rest}, _ => SplitBom{"", content})(Unit{})

def stripBom(content: String) -> String:
  match content:
    case SCon{'\u{feff}', rest}: rest
    case other: other
