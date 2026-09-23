import Base
import ./calendar.bend as Calendar
import ./string.bend as Strings
import ./u64.bend as W
import ./f64.bend as F

# Date.now's wall-clock source, separate from monotonic elapsed-time clocks.
# Negative epochs use signed two's-complement words; conversion never passes
# through F32 or a host floating-point adapter. This is not the full Date API.
def fromMilliseconds(+value: W.U64) -> F64:
  match value:
    case W.U64{+high, +low}:
      Bool.pick(F64, U32.is_ge(high, 2147483648), F.negate(F.fromU64(W.subtract(W.zero(), W.U64{high, low}))), F.fromU64(W.U64{high, low}))

def words(value: U32 & U32) -> W.U64:
  match value:
    case Tuple{high, low}: W.U64{high, low}

def now() -> IO(F64):
  do IO<F64>:
    value : U32 & U32 <- IO.unixMilliseconds()
    return fromMilliseconds(words(value))


type ParseError is Data: InvalidSyntax{} InvalidOffset{} InvalidCivilTime{cause: Calendar.CalendarError}
type Zone is Data: Zone{clock: String, offset: W.U64, subtract: Bool}

def digits(text: String, count: Nat, number: U32, valid: Bool) -> Maybe<&2,U32>:
  match text count:
    case SNil{} 0n: Bool.pick(Maybe<&2,U32>,valid,Some{number},None{})
    case SCon{Chr{+char},rest} 1n+count: digits(rest,count,(number * 10 + char - 48 : U32),valid && U32.is_ge(char,48) && U32.is_le(char,57))
    case _ _: None{}

def checkedOffset(clock: String, subtract: Bool, hours: Maybe<&2,U32>, minutes: Maybe<&2,U32>) -> Result<&2,&2,ParseError,Zone>:
  match hours minutes:
    case Some{+hour} Some{+minute}:
      Bool.pick(Result<&2,&2,ParseError,Zone>,U32.is_lt(hour,24) && U32.is_lt(minute,60),Done{Zone{clock,W.fromU32((hour * 3600000 + minute * 60000 : U32)),subtract}},Fail{InvalidOffset{}})
    case _ _: Fail{InvalidOffset{}}

def offsetParts(clock: String, subtract: Bool, parts: List<&2,String>) -> Result<&2,&2,ParseError,Zone>:
  match parts:
    case hour <> minute <> Nil{}: checkedOffset(clock,subtract,digits(hour,2n,0,True{}),digits(minute,2n,0,True{}))
    case _: Fail{InvalidOffset{}}

def zone(text: String, reversed: String) -> Result<&2,&2,ParseError,Zone>:
  match text:
    case SCon{Chr{90},SNil{}}: Done{Zone{String.reverse(reversed),W.zero(),True{}}}
    case SCon{Chr{43},rest}: offsetParts(String.reverse(reversed),True{},Strings.split(rest,':'))
    case SCon{Chr{45},rest}: offsetParts(String.reverse(reversed),False{},Strings.split(rest,':'))
    case SCon{char,rest}: zone(rest,SCon{char,reversed})
    case SNil{}: Fail{InvalidSyntax{}}

# ISO fractions may be longer than milliseconds. Validate every digit while
# retaining only the first three, without rounding or integer overflow.
def fraction(text: String, +count: Nat, +number: U32, valid: Bool) -> Maybe<&2,U32>:
  match text:
    case SNil{}:
      Bool.pick(Maybe<&2,U32>,valid && Nat.is_gt(count,0n),Some{(number * Bool.pick(U32,Nat.is_eq(count,1n),100,Bool.pick(U32,Nat.is_eq(count,2n),10,1)) : U32)},None{})
    case SCon{Chr{+char},rest}:
      fraction(rest,count + 1n,Bool.pick(U32,Nat.is_lt(count,3n),(number * 10 + char - 48 : U32),number),valid && U32.is_ge(char,48) && U32.is_le(char,57))

def numberCons(value: Maybe<&2,U32>, values: Maybe<&2,List<&2,U32>>) -> Maybe<&2,List<&2,U32>>:
  match value values:
    case Some{number} Some{rest}: Some{number <> rest}
    case _ _: None{}

def fields(parts: List<&2,String>, widths: List<&2,Nat>, reversed: Maybe<&2,List<&2,U32>>) -> Maybe<&2,List<&2,U32>>:
  match parts widths:
    case Nil{} Nil{}: Maybe.map(&2,List<&2,U32>,List<&2,U32>,values => List.reverse(&2,U32,values),reversed)
    case part <> rest width <> widths: fields(rest,widths,numberCons(digits(part,width,0,True{}),reversed))
    case _ _: None{}

def zonedEpoch(+offset: W.U64, subtract: Bool, value: Result<&2,&2,Calendar.CalendarError,W.U64>) -> Result<&2,&2,ParseError,F64>:
  match value:
    case Fail{cause}: Fail{InvalidCivilTime{cause}}
    case Done{+epoch}: Done{fromMilliseconds(Bool.pick(W.U64,subtract,W.subtract(epoch,offset),W.add(epoch,offset)))}

def civil(numbers: Maybe<&2,List<&2,U32>>, millis: Maybe<&2,U32>, offset: W.U64, subtract: Bool) -> Result<&2,&2,ParseError,F64>:
  match numbers millis:
    case Some{year <> month <> day <> hour <> minute <> second <> Nil{}} Some{millis}:
      zonedEpoch(offset,subtract,Calendar.toEpochMilliseconds(Calendar.CivilTime{year,month,day,hour,minute,second,millis}))
    case _ _: Fail{InvalidSyntax{}}

def secondsParts(prefix: List<&2,String>, seconds: List<&2,String>, offset: W.U64, subtract: Bool) -> Result<&2,&2,ParseError,F64>:
  match seconds:
    case second <> Nil{}: civil(fields(List.concat(&2,String,[prefix,[second]]),[4n,2n,2n,2n,2n,2n],Some{Nil{}}),Some{0},offset,subtract)
    case second <> decimals <> Nil{}: civil(fields(List.concat(&2,String,[prefix,[second]]),[4n,2n,2n,2n,2n,2n],Some{Nil{}}),fraction(decimals,0n,0,True{}),offset,subtract)
    case _: Fail{InvalidSyntax{}}

def clockParts(date: List<&2,String>, clock: List<&2,String>, offset: W.U64, subtract: Bool) -> Result<&2,&2,ParseError,F64>:
  match date clock:
    case year <> month <> day <> Nil{} hour <> minute <> second <> Nil{}:
      secondsParts([year,month,day,hour,minute],Strings.split(second,'.'),offset,subtract)
    case _ _: Fail{InvalidSyntax{}}

def parsedZone(date: String, result: Result<&2,&2,ParseError,Zone>) -> Result<&2,&2,ParseError,F64>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Zone{clock,offset,subtract}}: clockParts(Strings.split(date,'-'),Strings.split(clock,':'),offset,subtract)

def isoParts(parts: List<&2,String>) -> Result<&2,&2,ParseError,F64>:
  match parts:
    case date <> clock <> Nil{}: parsedZone(date,zone(clock,""))
    case _: Fail{InvalidSyntax{}}

# Strict zoned ISO date-time; supported civil years are 0000..9999, matching
# Calendar. Locale forms, missing offsets and normalized invalid dates reject.
def parseIso(timestamp: String) -> Result<&2,&2,ParseError,F64>:
  isoParts(Strings.split(timestamp,'T'))

# Date.prototype.toISOString for finite non-negative integral epochs within
# Calendar's civil range: YYYY-MM-DDTHH:MM:SS.mmmZ. Other values yield None.
def zeros(count: Nat) -> String:
  match count:
    case 0n: ""
    case 1n+n: "0" ++ zeros(n)

def padded(+text: String, width: Nat) -> String:
  zeros(Nat.sub(width, String.length(text))) ++ text

def pad(value: U32, width: Nat) -> String:
  padded(U32.show(value), width)

def civilIso(value: Calendar.CivilTime) -> String:
  match value:
    case Calendar.CivilTime{year, month, day, hour, minute, second, millisecond}:
      pad(year, 4n) ++ "-" ++ pad(month, 2n) ++ "-" ++ pad(day, 2n) ++ "T" ++ pad(hour, 2n) ++ ":" ++ pad(minute, 2n) ++ ":" ++ pad(second, 2n) ++ "." ++ pad(millisecond, 3n) ++ "Z"

def formattedCivil(result: Result<&2, &2, Calendar.Error, Calendar.CivilTime>) -> Maybe<&2, String>:
  match result:
    case Fail{_}: None{}
    case Done{value}: Some{civilIso(value)}

def exactWord(value: F64, word: W.U64, order: Maybe<&2, Cmp>) -> Maybe<&2, String>:
  match order:
    case Some{EQ{}}: formattedCivil(Calendar.fromEpochMilliseconds(word))
    case _: None{}

def formatIso(+value: F64) -> Maybe<&2, String>:
  +word = F.candidate(F.decode(value))
  exactWord(value, word, F.compare(value, F.fromU64(word)))
