import Base
import ./unicode-17-case-map.bend as Unicode

# Unicode17 default full lowercase for scalar strings, without locale tailoring.
# Property bits: Cased=1, Case_Ignorable=2. Ignorable takes precedence in the
# Final_Sigma context: some characters have both properties.
def cased(properties: U32) -> Bool: U32.is_eq((properties % 2: U32),1)
def ignorable(properties: U32) -> Bool: U32.is_ge(properties,2)
def followedByCased(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{code},+rest}:
      +properties = Unicode.properties(code)
      Bool.pick(Unit -> Bool,ignorable(properties),_ => followedByCased(rest),_ => cased(properties))(Unit{})
def mapped(+code: U32,+before: Bool,+rest: String,reversed: String) -> String:
  match code:
    case 304: SCon{Chr{775},SCon{Chr{105},reversed}}
    case 931:
      SCon{Chr{Bool.pick(U32,before && Bool.not(followedByCased(rest)),962,963)},reversed}
    case _: SCon{Chr{(code + Unicode.delta(code): U32)},reversed}

# Lookahead occurs only at Sigma and stops at the next non-ignorable scalar.
# Sigma is non-ignorable, so those runs never overlap: traversal stays linear.
def scan(text: String,+before: Bool,reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{Chr{+code},+rest}:
      +properties = Unicode.properties(code)
      scan(rest,Bool.pick(Bool,ignorable(properties),before,cased(properties)),mapped(code,before,rest,reversed))
def lower(text: String) -> String: scan(text,False{},"")
