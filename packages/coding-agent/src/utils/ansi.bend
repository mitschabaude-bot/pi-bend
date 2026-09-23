import Base

# A complete control sequence is removed atomically. Pending/incomplete input
# remains literal; unlike a regex match, a digit is never a CSI final byte.
type Mode is Data: Plain{} Escape{} Designation{} Csi{intermediate: Bool} Osc{escaped: Bool}
type Scanner is Data: Scanner{mode: Mode, pending: String, output: String}

def between(+value: U32, low: U32, high: U32) -> Bool:
  U32.is_ge(value,low) && U32.is_le(value,high)

# Preserve Pi's recognized single-ESC controls, including RIS (ESC c).
def single(+value: U32) -> Bool:
  between(value,65,80) || between(value,82,84) || U32.is_eq(value,90) || U32.is_eq(value,99) || between(value,102,110) || between(value,113,117) || U32.is_eq(value,121) || between(value,60,62) || U32.is_eq(value,126)

def plain(character: Char, output: String) -> Scanner:
  match character:
    case Chr{27}: Scanner{Escape{},"\u{1b}",output}
    case Chr{155}: Scanner{Csi{False{}},"\u{9b}",output}
    case character: Scanner{Plain{},"",SCon{character,output}}

# Both buffers are reversed. Use tail-recursive reversal, avoiding a recursive
# append on a possibly very long unfinished OSC payload.
def literal(pending: String, output: String) -> String:
  String.reverse.go(String.reverse(pending),output)

def sequence(+character: Char, +pending: String, +output: String, +mode: Mode, final: Bool, continued: Bool) -> Scanner:
  Bool.pick(Unit -> Scanner,final,_ => Scanner{Plain{},"",output},
    _ => Bool.pick(Unit -> Scanner,continued,_ => Scanner{mode,SCon{character,pending},output},_ => plain(character,literal(pending,output)))(Unit{}))(Unit{})

def beginEscape(+character: Char, +pending: String, +output: String) -> Scanner:
  +code = Char.to_u32(character)
  Bool.pick(Unit -> Scanner,U32.is_eq(code,91),_ => Scanner{Csi{False{}},SCon{character,pending},output},
    _ => Bool.pick(Unit -> Scanner,U32.is_eq(code,93),_ => Scanner{Osc{False{}},SCon{character,pending},output},
      _ => sequence(character,pending,output,Designation{},single(code),between(code,32,47)))(Unit{}))(Unit{})

def advance(+character: Char, scanner: Scanner) -> Scanner:
  match scanner:
    case Scanner{Plain{},_,output}: plain(character,output)
    case Scanner{Escape{},pending,output}: beginEscape(character,pending,output)
    case Scanner{Designation{},pending,output}:
      sequence(character,pending,output,Designation{},between(Char.to_u32(character),48,126),between(Char.to_u32(character),32,47))
    case Scanner{Csi{+intermediate},pending,output}:
      +code = Char.to_u32(character)
      sequence(character,pending,output,Csi{intermediate || between(code,32,47)},between(code,64,126),between(code,32,47) || (Bool.not(intermediate) && between(code,48,63)))
    case Scanner{Osc{escaped},+pending,+output}:
      Bool.pick(Scanner,Char.is_eq(character,'\u{7}') || Char.is_eq(character,'\u{9c}') || (escaped && Char.is_eq(character,'\\')),
        Scanner{Plain{},"",output},Scanner{Osc{Char.is_eq(character,'\u{1b}')},SCon{character,pending},output})

def finish(scanner: Scanner) -> String:
  match scanner:
    case Scanner{_,pending,output}: String.reverse(literal(pending,output))

def scan(value: String, scanner: Scanner) -> String:
  match value:
    case SNil{}:
      finish(scanner)
    case SCon{character,rest}: scan(rest,advance(character,scanner))

def stripAnsi(value: String) -> String: scan(value,Scanner{Plain{},"",""})
