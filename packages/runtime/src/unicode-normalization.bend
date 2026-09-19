import Base
import ./stable-sort.bend as Sort
import ./u32-table.bend as Table
import ./unicode-normalization-data.bend as Data

# Tables are reusable immutable values, supplied once by the Unicode-version
# module. Normalization itself performs no IO or host-library calls.
def prepend(points: List<&2, Data.Point>, reversed: List<&2, Data.Point>) -> List<&2, Data.Point>:
  match points:
    case Nil{}: reversed
    case point <> rest: prepend(rest, point <> reversed)

def property(code: U32, result: Maybe<&2, Data.Property>) -> List<&2, Data.Point>:
  match result:
    case None{}: Data.Point{code, 0} <> Nil{}
    case Some{Data.Property{ccc, Nil{}}}: Data.Point{code, ccc} <> Nil{}
    case Some{Data.Property{_, points}}: points

def hangulTail(code: U32) -> List<&2, Data.Point>:
  match code:
    case 0: Nil{}
    case other: Data.Point{(4519 + other : U32), 0} <> Nil{}

def hangul(+index: U32) -> List<&2, Data.Point>:
  Data.Point{(4352 + index / 588 : U32), 0} <> Data.Point{(4449 + index % 588 / 28 : U32), 0} <> hangulTail((index % 28 : U32))

def decomposition(ascii: Bool, syllable: Bool, +code: U32, table: Table.Table<Data.Property>) -> List<&2, Data.Point>:
  match ascii syllable:
    case True{} _: Data.Point{code, 0} <> Nil{}
    case False{} True{}: hangul((code - 44032 : U32))
    case False{} False{}: property(code, Table.get(Data.Property, table, code))

def decompose(text: String, +table: Table.Table<Data.Property>, reversed: List<&2, Data.Point>) -> List<&2, Data.Point>:
  match text:
    case SNil{}: List.reverse(&2, Data.Point, reversed)
    case SCon{Chr{+code}, rest}:
      decompose(rest, table, prepend(decomposition(U32.is_lt(code, 128), U32.is_ge(code, 44032) && U32.is_lt(code, 55204), code, table), reversed))

def before(left: Data.Point, right: Data.Point) -> Bool:
  match left right:
    case Data.Point{_, a} Data.Point{_, b}: U32.is_le(a, b)

def flush(segment: List<&2, Data.Point>, reversed: List<&2, Data.Point>) -> List<&2, Data.Point>:
  prepend(Sort.sort(~Data.Point, ~before, List.reverse(&2, Data.Point, segment)), reversed)

type Order is Data:
  Order{segment: List<&2, Data.Point>, reversed: List<&2, Data.Point>}

def orderStep(starter: Bool, point: Data.Point, state: Order) -> Order:
  match starter state:
    case True{} Order{segment, reversed}: Order{point <> Nil{}, flush(segment, reversed)}
    case False{} Order{segment, reversed}: Order{point <> segment, reversed}

def order(points: List<&2, Data.Point>, state: Order) -> List<&2, Data.Point>:
  match points state:
    case Nil{} Order{segment, reversed}: List.reverse(&2, Data.Point, flush(segment, reversed))
    case Data.Point{code, +ccc} <> rest state: order(rest, orderStep(U32.is_eq(ccc, 0), Data.Point{code, ccc}, state))

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
  Compose{starter: Maybe<&2, U32>, marks: List<&2, Data.Point>, lastClass: U32, reversed: List<&2, Data.Point>}

def withStarter(starter: Maybe<&2, U32>, reversed: List<&2, Data.Point>) -> List<&2, Data.Point>:
  match starter:
    case None{}: reversed
    case Some{code}: Data.Point{code, 0} <> reversed

def complete(starter: Maybe<&2, U32>, marks: List<&2, Data.Point>, reversed: List<&2, Data.Point>) -> List<&2, Data.Point>:
  prepend(List.reverse(&2, Data.Point, marks), withStarter(starter, reversed))

def uncombined(zero: Bool, code: U32, +ccc: U32, starter: Maybe<&2, U32>, marks: List<&2, Data.Point>, reversed: List<&2, Data.Point>) -> Compose:
  match zero:
    case True{}: Compose{Some{code}, Nil{}, 0, complete(starter, marks, reversed)}
    case False{}: Compose{starter, Data.Point{code, ccc} <> marks, ccc, reversed}

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

def compose(points: List<&2, Data.Point>, +table: Table.Table<Table.Table<U32>>, state: Compose) -> List<&2, Data.Point>:
  match points state:
    case Nil{} Compose{starter, marks, _, reversed}: List.reverse(&2, Data.Point, complete(starter, marks, reversed))
    case Data.Point{code, ccc} <> rest state: compose(rest, table, composeStep(table, code, ccc, state))

def text(points: List<&2, Data.Point>, reversed: String) -> String:
  match points:
    case Nil{}: String.reverse(reversed)
    case Data.Point{code, _} <> rest: text(rest, SCon{Chr{code}, reversed})

def nfd(tables: Data.Tables, input: String) -> String:
  match tables:
    case Data.Tables{properties, _}: text(order(decompose(input, properties, Nil{}), Order{Nil{}, Nil{}}), "")

def nfc(tables: Data.Tables, input: String) -> String:
  match tables:
    case Data.Tables{properties, compositions}: text(compose(order(decompose(input, properties, Nil{}), Order{Nil{}, Nil{}}), compositions, Compose{None{}, Nil{}, 0, Nil{}}), "")
