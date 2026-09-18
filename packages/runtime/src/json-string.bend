import Base
import ./utf16.bend as U

# Quote a JavaScript-compatible string. Bend may contain Unicode scalars or
# individual UTF-16 surrogate units. Valid adjacent pairs emit their scalar;
# unpaired units emit lowercase Unicode escapes, as JSON.stringify does.
def hex(+value: U32) -> Char:
  Char.from_u32(Bool.pick(U32, U32.is_lt(value, 10), (48 + value : U32), (87 + value : U32)))

def unicodeEscape(+code: U32) -> String:
  "\\u" ++ SCon{hex((code / 4096 : U32)), SCon{hex(((code / 256) % 16 : U32)), SCon{hex(((code / 16) % 16 : U32)), SCon{hex((code % 16 : U32)), SNil{}}}}}

def escapeOther(needed: Bool, code: U32) -> String:
  match needed:
    case True{}: unicodeEscape(code)
    case False{}: SCon{Chr{code}, SNil{}}

def escapeCode(+code: U32) -> String:
  match code:
    case 34: "\\\""
    case 92: "\\\\"
    case 8: "\\b"
    case 9: "\\t"
    case 10: "\\n"
    case 12: "\\f"
    case 13: "\\r"
    case _: escapeOther(U32.is_lt(code, 32) || U.highSurrogate(code) || U.lowSurrogate(code), code)

def escaped(chars: String) -> String:
  match chars:
    case SNil{}: ""
    case SCon{Chr{code}, rest}: escapeCode(code) ++ escaped(rest)

def quote(text: String) -> String:
  "\"" ++ escaped(U.normalize(text)) ++ "\""
