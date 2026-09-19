import Base

# Syntax recognition only. Calendar validity, timezone policy and resolution
# of two-digit years remain explicit responsibilities of the date interpreter.
type Format is Data:
  ImfFixdate{}
  Rfc850{}
  Asctime{}

type ClockFields is Data:
  ClockFields{hour: U32, minute: U32, second: U32}

type DateFields is Data:
  DateFields{format: Format, weekday: U32, year: U32, month: U32, day: U32, clock: ClockFields}

def digits(count: Nat, text: String, value: U32) -> Maybe<&2, U32>:
  match count text:
    case Zero{} SNil{}: Some{value}
    case Succ{rest} SCon{Chr{+code}, tail}:
      Bool.pick(Maybe<&2, U32>, U32.is_ge(code, 48) && U32.is_le(code, 57), digits(rest, tail, (value * 10 + code - 48 : U32)), None{})
    case _ _: None{}

def find(+text: String, names: List<&2, String>, +index: U32) -> Maybe<&2, U32>:
  match names:
    case Nil{}: None{}
    case name <> rest: Bool.pick(Maybe<&2, U32>, String.eq(text, name), Some{index}, find(text, rest, (index + 1 : U32)))

def month(text: String) -> Maybe<&2, U32>:
  find(text, "Jan" <> "Feb" <> "Mar" <> "Apr" <> "May" <> "Jun" <> "Jul" <> "Aug" <> "Sep" <> "Oct" <> "Nov" <> "Dec" <> Nil{}, 1)

def weekday(text: String) -> Maybe<&2, U32>:
  find(text, "Mon" <> "Tue" <> "Wed" <> "Thu" <> "Fri" <> "Sat" <> "Sun" <> Nil{}, 1)

def longWeekday(text: String) -> Maybe<&2, U32>:
  find(text, "Monday" <> "Tuesday" <> "Wednesday" <> "Thursday" <> "Friday" <> "Saturday" <> "Sunday" <> Nil{}, 1)

def commaReversed(text: String) -> String:
  match text:
    case SCon{Chr{44}, rest}: String.reverse(rest)
    case _: ""

def withoutComma(text: String) -> String: commaReversed(String.reverse(text))

def clockFields(hour: Maybe<&2, U32>, minute: Maybe<&2, U32>, second: Maybe<&2, U32>) -> Maybe<&2, ClockFields>:
  match hour minute second:
    case Some{h} Some{m} Some{s}: Some{ClockFields{h, m, s}}
    case _ _ _: None{}

def clockParts(parts: List<&2, String>) -> Maybe<&2, ClockFields>:
  match parts:
    case hour <> minute <> second <> Nil{}: clockFields(digits(2n, hour, 0), digits(2n, minute, 0), digits(2n, second, 0))
    case _: None{}

def clock(text: String) -> Maybe<&2, ClockFields>: clockParts(String.split(text, ':'))

def fields(format: Format, weekday: Maybe<&2, U32>, year: Maybe<&2, U32>, month: Maybe<&2, U32>, day: Maybe<&2, U32>, clock: Maybe<&2, ClockFields>) -> Maybe<&2, DateFields>:
  match weekday year month day clock:
    case Some{w} Some{y} Some{m} Some{d} Some{t}: Some{DateFields{format, w, y, m, d, t}}
    case _ _ _ _ _: None{}

def rfc850(weekday: String, date: List<&2, String>, time: String) -> Maybe<&2, DateFields>:
  match date:
    case day <> mon <> year <> Nil{}: fields(Rfc850{}, longWeekday(withoutComma(weekday)), digits(2n, year, 0), month(mon), digits(2n, day, 0), clock(time))
    case _: None{}

def shortDay(+text: String) -> Maybe<&2, U32>:
  match text:
    case SCon{_, SNil{}}: digits(1n, text, 0)
    case _: digits(2n, text, 0)

def gmt(zone: String, value: Maybe<&2, DateFields>) -> Maybe<&2, DateFields>:
  Bool.pick(Maybe<&2, DateFields>, String.eq(zone, "GMT"), value, None{})

def words(parts: List<&2, String>) -> Maybe<&2, DateFields>:
  match parts:
    case week <> day <> mon <> year <> time <> zone <> Nil{}:
      gmt(zone, fields(ImfFixdate{}, weekday(withoutComma(week)), digits(4n, year, 0), month(mon), digits(2n, day, 0), clock(time)))
    case week <> date <> time <> zone <> Nil{}: gmt(zone, rfc850(week, String.split(date, '-'), time))
    case week <> mon <> day <> time <> year <> Nil{}:
      fields(Asctime{}, weekday(week), digits(4n, year, 0), month(mon), shortDay(day), clock(time))
    case _: None{}

# Accept surrounding/repeated spaces without changing recognized field tokens.
def nonempty(parts: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}: Nil{}
    case SNil{} <> rest: nonempty(rest)
    case head <> rest: head <> nonempty(rest)

def parse(text: String) -> Maybe<&2, DateFields>: words(nonempty(String.split(text, ' ')))
