import Base
import ./dns-name.bend as Name
import ./utf8.bend as UTF8

# Text-to-wire syntax only. IDNA, hostname policy and search expansion belong
# to callers. A trailing unescaped dot makes the name absolute.
type Parsed is Data:
  Parsed{name: Name.Name, absolute: Bool}

type Error is Data:
  InvalidByte{}
  RawNul{}
  EmptyLabel{}
  LabelTooLong{}
  NameTooLong{}
  InvalidEscape{}

type Mode is Data:
  Plain{}
  Escape{}
  SecondDigit{value: U32}
  ThirdDigit{value: U32}

type Cursor is Data:
  Cursor{labels: List<&2, List<&2, U32>>, label: List<&2, U32>, size: U32, total: U32}

type State is Data:
  State{cursor: Cursor, mode: Mode, absolute: Bool}

def byteAdded(fits: Bool, byte: U32, labels: List<&2, List<&2, U32>>, label: List<&2, U32>, size: U32, total: U32) -> Result<&2, &2, Error, Cursor>:
  match fits:
    case False{}: Fail{NameTooLong{}}
    case True{}: Done{Cursor{labels, byte <> label, (size + 1 : U32), total}}

def withinLabel(valid: Bool, byte: U32, labels: List<&2, List<&2, U32>>, label: List<&2, U32>, +size: U32, total: U32) -> Result<&2, &2, Error, Cursor>:
  match valid:
    case False{}: Fail{LabelTooLong{}}
    case True{}:
      +next = (total + Bool.pick(U32, U32.is_zero(size), 2, 1) : U32)
      byteAdded(U32.is_le(next, 255), byte, labels, label, size, next)

def appendByte(byte: U32, cursor: Cursor) -> Result<&2, &2, Error, Cursor>:
  match cursor:
    case Cursor{labels, label, +size, total}: withinLabel(U32.is_lt(size, 63), byte, labels, label, size, total)

def stateResult(result: Result<&2, &2, Error, Cursor>) -> Result<&2, &2, Error, State>:
  match result:
    case Fail{error}: Fail{error}
    case Done{cursor}: Done{State{cursor, Plain{}, False{}}}

def separator(last: Bool, cursor: Cursor) -> Result<&2, &2, Error, State>:
  match last cursor:
    case True{} Cursor{Nil{}, Nil{}, 0, total}: Done{State{Cursor{Nil{}, Nil{}, 0, total}, Plain{}, True{}}}
    case _ Cursor{_, _, 0, _}: Fail{EmptyLabel{}}
    case final Cursor{labels, label, _, total}: Done{State{Cursor{List.reverse(&2, U32, label) <> labels, Nil{}, 0, total}, Plain{}, final}}

def decimalByte(valid: Bool, value: U32, cursor: Cursor) -> Result<&2, &2, Error, State>:
  match valid:
    case False{}: Fail{InvalidEscape{}}
    case True{}: stateResult(appendByte(value, cursor))

def escaped(digit: Bool, byte: U32, cursor: Cursor) -> Result<&2, &2, Error, State>:
  match digit:
    case True{}: Done{State{cursor, SecondDigit{(byte - 48 : U32)}, False{}}}
    case False{}: stateResult(appendByte(byte, cursor))

def second(valid: Bool, byte: U32, value: U32, cursor: Cursor) -> Result<&2, &2, Error, State>:
  match valid:
    case False{}: Fail{InvalidEscape{}}
    case True{}: Done{State{cursor, ThirdDigit{(value * 10 + byte - 48 : U32)}, False{}}}

def isDigit(+byte: U32) -> Bool: U32.is_ge(byte, 48) && U32.is_le(byte, 57)

def plain(byte: U32, last: Bool, cursor: Cursor) -> Result<&2, &2, Error, State>:
  match byte:
    case 92: Done{State{cursor, Escape{}, False{}}}
    case 46: separator(last, cursor)
    case value: stateResult(appendByte(value, cursor))

def step(+byte: U32, last: Bool, state: State) -> Result<&2, &2, Error, State>:
  match state:
    case State{cursor, Plain{}, _}: plain(byte, last, cursor)
    case State{cursor, Escape{}, _}: escaped(isDigit(byte), byte, cursor)
    case State{cursor, SecondDigit{number}, _}: second(isDigit(byte), byte, number, cursor)
    case State{cursor, ThirdDigit{number}, _}:
      +decoded = (number * 10 + byte - 48 : U32)
      decimalByte(isDigit(byte) && U32.is_le(decoded, 255), decoded, cursor)

def checkedByte(valid: Bool, byte: U32, last: Bool, state: State) -> Result<&2, &2, Error, State>:
  match valid byte:
    case False{} _: Fail{InvalidByte{}}
    case True{} 0: Fail{RawNul{}}
    case True{} value: step(value, last, state)

def empty(bytes: List<&2, U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case _: False{}

def finished(state: State) -> Result<&2, &2, Error, Parsed>:
  match state:
    case State{Cursor{labels, Nil{}, 0, _}, Plain{}, absolute}: Done{Parsed{Name.Name{List.reverse(&2, List<&2, U32>, labels)}, absolute}}
    case State{Cursor{labels, label, _, _}, Plain{}, absolute}: Done{Parsed{Name.Name{List.reverse(&2, List<&2, U32>, List.reverse(&2, U32, label) <> labels)}, absolute}}
    case _: Fail{InvalidEscape{}}

def scan(bytes: List<&2, U32>, state: Result<&2, &2, Error, State>) -> Result<&2, &2, Error, Parsed>:
  match bytes state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{value}: finished(value)
    case +byte <> +rest Done{value}: scan(rest, checkedByte(U32.is_le(byte, 255), byte, empty(rest), value))

# Raw zero cannot occur in a C presentation string. Keep it a typed error,
# rather than silently truncating a Bend value. The escape \000 is valid data.
def parseBytes(bytes: List<&2, U32>) -> Result<&2, &2, Error, Parsed>:
  scan(bytes, Done{State{Cursor{Nil{}, Nil{}, 0, 1}, Plain{}, False{}}})

def parse(text: String) -> Result<&2, &2, Error, Parsed>:
  parseBytes(UTF8.encode(text))
