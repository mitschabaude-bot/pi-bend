import Base
import ./u32-table.bend as Table
import ./stable-sort.bend as Sort


# Unicode Bidi_Class values. Property lookup and algorithms share this type.
type Class is Data:
  L{}
  R{}
  AL{}
  EN{}
  AN{}
  ES{}
  CS{}
  ET{}
  ON{}
  BN{}
  NSM{}
  B{}
  S{}
  WS{}
  LRE{}
  LRO{}
  RLE{}
  RLO{}
  PDF{}
  LRI{}
  RLI{}
  FSI{}
  PDI{}


# Unicode Joining_Type, independent of bidirectional class.
type JoiningType is Data:
  NonJoining{}
  LeftJoining{}
  RightJoining{}
  DualJoining{}
  JoinCausing{}
  Transparent{}


type Point is Data:
  Point{code: U32, combiningClass: U32}

type Property is Data:
  Property{combiningClass: U32, decomposition: List<&2, Point>}

type Tables is Data:
  Tables{properties: Table.Table<Property>, compositions: Table.Table<Table.Table<U32>>}


# Tables are reusable immutable values, supplied once by the Unicode-version
# module. Normalization itself performs no IO or host-library calls.
def prepend(points: List<&2, Point>, reversed: List<&2, Point>) -> List<&2, Point>:
  match points:
    case Nil{}: reversed
    case point <> rest: prepend(rest, point <> reversed)

def property(code: U32, result: Maybe<&2, Property>) -> List<&2, Point>:
  match result:
    case None{}: Point{code, 0} <> Nil{}
    case Some{Property{ccc, Nil{}}}: Point{code, ccc} <> Nil{}
    case Some{Property{_, points}}: points

def hangulTail(code: U32) -> List<&2, Point>:
  match code:
    case 0: Nil{}
    case other: Point{(4519 + other : U32), 0} <> Nil{}

def hangul(+index: U32) -> List<&2, Point>:
  Point{(4352 + index / 588 : U32), 0} <> Point{(4449 + index % 588 / 28 : U32), 0} <> hangulTail((index % 28 : U32))

def decomposition(ascii: Bool, syllable: Bool, +code: U32, table: Table.Table<Property>) -> List<&2, Point>:
  match ascii syllable:
    case True{} _: Point{code, 0} <> Nil{}
    case False{} True{}: hangul((code - 44032 : U32))
    case False{} False{}: property(code, Table.get(Property, table, code))

def decompose(text: String, +table: Table.Table<Property>, reversed: List<&2, Point>) -> List<&2, Point>:
  match text:
    case SNil{}: List.reverse(&2, Point, reversed)
    case SCon{Chr{+code}, rest}:
      decompose(rest, table, prepend(decomposition(U32.is_lt(code, 128), U32.is_ge(code, 44032) && U32.is_lt(code, 55204), code, table), reversed))

def before(left: Point, right: Point) -> Bool:
  match left right:
    case Point{_, a} Point{_, b}: U32.is_le(a, b)

def flush(segment: List<&2, Point>, reversed: List<&2, Point>) -> List<&2, Point>:
  prepend(Sort.sort(~Point, ~before, List.reverse(&2, Point, segment)), reversed)

type Order is Data:
  Order{segment: List<&2, Point>, reversed: List<&2, Point>}

def orderStep(starter: Bool, point: Point, state: Order) -> Order:
  match starter state:
    case True{} Order{segment, reversed}: Order{point <> Nil{}, flush(segment, reversed)}
    case False{} Order{segment, reversed}: Order{point <> segment, reversed}

def order(points: List<&2, Point>, state: Order) -> List<&2, Point>:
  match points state:
    case Nil{} Order{segment, reversed}: List.reverse(&2, Point, flush(segment, reversed))
    case Point{code, +ccc} <> rest state: order(rest, orderStep(U32.is_eq(ccc, 0), Point{code, ccc}, state))

def hangulPair(lv: Bool, lvt: Bool, +first: U32, +second: U32) -> Maybe<&2, U32>:
  match lv lvt:
    case True{} _: Some{(44032 + (first - 4352) * 588 + (second - 4449) * 28 : U32)}
    case False{} True{}: Some{(first + second - 4519 : U32)}
    case False{} False{}: None{}

def secondPair(table: Maybe<&2, Table.Table<U32>>, second: U32) -> Maybe<&2, U32>:
  match table:
    case None{}: None{}
    case Some{table}: Table.get(U32, table, second)

def selectedPair(result: Maybe<&2, U32>, table: Table.Table<Table.Table<U32>>, first: U32, second: U32) -> Maybe<&2, U32>:
  match result:
    case Some{value}: Some{value}
    case None{}: secondPair(Table.get(Table.Table<U32>, table, first), second)

def pair(table: Table.Table<Table.Table<U32>>, +first: U32, +second: U32) -> Maybe<&2, U32>:
  selectedPair(hangulPair(U32.is_ge(first, 4352) && U32.is_lt(first, 4371) && U32.is_ge(second, 4449) && U32.is_lt(second, 4470),
    U32.is_ge(first, 44032) && U32.is_lt(first, 55204) && U32.is_eq(((first - 44032) % 28 : U32), 0) && U32.is_gt(second, 4519) && U32.is_lt(second, 4547), first, second), table, first, second)

type Compose is Data:
  Compose{starter: Maybe<&2, U32>, marks: List<&2, Point>, lastClass: U32, reversed: List<&2, Point>}

def withStarter(starter: Maybe<&2, U32>, reversed: List<&2, Point>) -> List<&2, Point>:
  match starter:
    case None{}: reversed
    case Some{code}: Point{code, 0} <> reversed

def complete(starter: Maybe<&2, U32>, marks: List<&2, Point>, reversed: List<&2, Point>) -> List<&2, Point>:
  prepend(List.reverse(&2, Point, marks), withStarter(starter, reversed))

def uncombined(zero: Bool, code: U32, +ccc: U32, starter: Maybe<&2, U32>, marks: List<&2, Point>, reversed: List<&2, Point>) -> Compose:
  match zero:
    case True{}: Compose{Some{code}, Nil{}, 0, complete(starter, marks, reversed)}
    case False{}: Compose{starter, Point{code, ccc} <> marks, ccc, reversed}

def combined(result: Maybe<&2, U32>, code: U32, +ccc: U32, state: Compose) -> Compose:
  match result state:
    case Some{value} Compose{_, marks, last, reversed}: Compose{Some{value}, marks, last, reversed}
    case None{} Compose{starter, marks, _, reversed}: uncombined(U32.is_eq(ccc, 0), code, ccc, starter, marks, reversed)

def candidate(allowed: Bool, table: Table.Table<Table.Table<U32>>, starter: Maybe<&2, U32>, code: U32) -> Maybe<&2, U32>:
  match allowed starter:
    case True{} Some{previous}: pair(table, previous, code)
    case _ _: None{}

def composeStep(table: Table.Table<Table.Table<U32>>, +code: U32, +ccc: U32, state: Compose) -> Compose:
  match state:
    case Compose{+starter, marks, +last, reversed}:
      combined(candidate(U32.is_eq(last, 0) || U32.is_lt(last, ccc), table, starter, code), code, ccc, Compose{starter, marks, last, reversed})

def compose(points: List<&2, Point>, +table: Table.Table<Table.Table<U32>>, state: Compose) -> List<&2, Point>:
  match points state:
    case Nil{} Compose{starter, marks, _, reversed}: List.reverse(&2, Point, complete(starter, marks, reversed))
    case Point{code, ccc} <> rest state: compose(rest, table, composeStep(table, code, ccc, state))

def text(points: List<&2, Point>, reversed: String) -> String:
  match points:
    case Nil{}: String.reverse(reversed)
    case Point{code, _} <> rest: text(rest, SCon{Chr{code}, reversed})

def nfd(tables: Tables, input: String) -> String:
  match tables:
    case Tables{properties, _}: text(order(decompose(input, properties, Nil{}), Order{Nil{}, Nil{}}), "")

def nfc(tables: Tables, input: String) -> String:
  match tables:
    case Tables{properties, compositions}: text(compose(order(decompose(input, properties, Nil{}), Order{Nil{}, Nil{}}), compositions, Compose{None{}, Nil{}, 0, Nil{}}), "")


type Status is Data:
  Valid{}
  Ignored{}
  Mapped{replacement: String}
  Deviation{replacement: String}
  Disallowed{}

type Entry is Data:
  Entry{last: U32, status: Status}


type Properties is Data:
  Properties{bidi: Class, joining: JoiningType, combiningClass: U32, mark: Bool}

type PropertiesEntry is Data:
  PropertiesEntry{last: U32, properties: Properties}

def bounded(inside: Bool, properties: Properties) -> Maybe<&2, Properties>:
  match inside:
    case True{}: Some{properties}
    case False{}: None{}

def found(code: U32, value: Maybe<&2, PropertiesEntry>) -> Maybe<&2, Properties>:
  match value:
    case None{}: None{}
    case Some{PropertiesEntry{last, properties}}: bounded(U32.is_le(code, last), properties)

# Numeric property lookup also covers surrogates/unassigned code points. It
# constructs no Char and does not imply that a code point is valid in IDNA.
def lookup(table: Table.Table<PropertiesEntry>, +code: U32) -> Maybe<&2, Properties>:
  found(code, Table.floor(PropertiesEntry, table, code))
