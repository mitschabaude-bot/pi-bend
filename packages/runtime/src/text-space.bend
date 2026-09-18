import Base

# Whitespace accepted by Pi's text and numeric normalization. Keep the
# classification shared so replay filtering and numeric parsing agree.
def whitespace(+code: U32) -> Bool:
  (U32.is_ge(code, 9) && U32.is_le(code, 13)) || U32.is_eq(code, 32) || U32.is_eq(code, 160) || U32.is_eq(code, 5760) || (U32.is_ge(code, 8192) && U32.is_le(code, 8202)) || U32.is_eq(code, 8232) || U32.is_eq(code, 8233) || U32.is_eq(code, 8239) || U32.is_eq(code, 8287) || U32.is_eq(code, 12288) || U32.is_eq(code, 65279)

def blank(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{code}, rest}: whitespace(code) && blank(rest)
