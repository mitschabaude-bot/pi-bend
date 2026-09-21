import Base
import ./url-percent.bend as Percent
import ./utf8.bend as UTF8

# RFC 3986 query-component encoding. Form '+' encoding is a different format.
def unreserved(+byte: U32) -> Bool:
  (U32.is_ge(byte, 65) && U32.is_le(byte, 90)) || (U32.is_ge(byte, 97) && U32.is_le(byte, 122)) || (U32.is_ge(byte, 48) && U32.is_le(byte, 57)) || U32.is_eq(byte, 45) || U32.is_eq(byte, 46) || U32.is_eq(byte, 95) || U32.is_eq(byte, 126)

def bytes(input: List<&2, U32>, reversed: String) -> String:
  match input:
    case Nil{}: String.reverse(reversed)
    case +byte <> rest: bytes(rest, Percent.emit(False{}, Bool.not(unreserved(byte)), byte, reversed))

def encode(text: String) -> String: bytes(UTF8.encode(text), "")
