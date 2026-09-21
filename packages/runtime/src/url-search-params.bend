import Base
import ./url-form.bend as Form

# Persistent ordered name/value tuples. Operations return new values; retaining
# a prior value or its entries never observes later changes.
type URLSearchParams is Data:
  URLSearchParams{tuples: List<&2, Form.Entry>}

def new() -> URLSearchParams: URLSearchParams{Nil{}}

def parse(text: String) -> URLSearchParams:
  match text:
    case SCon{'?', rest}: URLSearchParams{Form.parse(rest)}
    case other: URLSearchParams{Form.parse(other)}

def normalized(entries: List<&2, Form.Entry>) -> List<&2, Form.Entry>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: Form.normalize(entry) <> normalized(rest)

def fromEntries(entries: List<&2, Form.Entry>) -> URLSearchParams:
  URLSearchParams{normalized(entries)}

def entries(params: URLSearchParams) -> List<&2, Form.Entry>:
  match params:
    case URLSearchParams{tuples}: tuples

def names(tuples: List<&2, Form.Entry>) -> List<&2, String>:
  match tuples:
    case Nil{}: Nil{}
    case Form.Entry{name, _} <> rest: name <> names(rest)

def contents(tuples: List<&2, Form.Entry>) -> List<&2, String>:
  match tuples:
    case Nil{}: Nil{}
    case Form.Entry{_, value} <> rest: value <> contents(rest)

def keys(params: URLSearchParams) -> List<&2, String>: names(entries(params))
def values(params: URLSearchParams) -> List<&2, String>: contents(entries(params))

def size(params: URLSearchParams) -> Nat:
  List.length(&2, Form.Entry, entries(params))

def toString(params: URLSearchParams) -> String: Form.serialize(entries(params))

def append(params: URLSearchParams, name: String, value: String) -> URLSearchParams:
  URLSearchParams{List.append(&2, Form.Entry, entries(params), Form.normalize(Form.Entry{name, value}) <> Nil{})}

def matches(entry: Form.Entry, name: String, value: Maybe<&2, String>) -> Bool:
  match entry value:
    case Form.Entry{key, _} None{}: String.eq(key, name)
    case Form.Entry{key, stored} Some{value}: String.eq(key, name) && String.eq(stored, value)

def optional(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case None{}: None{}
    case Some{text}: Some{Form.scalar(text)}

def find(tuples: List<&2, Form.Entry>, +name: String) -> Maybe<&2, String>:
  match tuples:
    case Nil{}: None{}
    case Form.Entry{key, value} <> rest: Bool.pick(Maybe<&2, String>, String.eq(key, name), Some{value}, find(rest, name))

def get(params: URLSearchParams, name: String) -> Maybe<&2, String>:
  find(entries(params), Form.scalar(name))

def findAll(tuples: List<&2, Form.Entry>, +name: String) -> List<&2, String>:
  match tuples:
    case Nil{}: Nil{}
    case Form.Entry{key, value} <> rest:
      +found = findAll(rest, name)
      Bool.pick(List<&2, String>, String.eq(key, name), value <> found, found)

def getAll(params: URLSearchParams, name: String) -> List<&2, String>:
  findAll(entries(params), Form.scalar(name))

def contains(tuples: List<&2, Form.Entry>, +name: String, +value: Maybe<&2, String>) -> Bool:
  match tuples:
    case Nil{}: False{}
    case entry <> rest: matches(entry, name, value) || contains(rest, name, value)

def has(params: URLSearchParams, name: String, value: Maybe<&2, String>) -> Bool:
  contains(entries(params), Form.scalar(name), optional(value))

def remove(tuples: List<&2, Form.Entry>, +name: String, +value: Maybe<&2, String>) -> List<&2, Form.Entry>:
  match tuples:
    case Nil{}: Nil{}
    case +entry <> rest:
      +remaining = remove(rest, name, value)
      Bool.pick(List<&2, Form.Entry>, matches(entry, name, value), remaining, entry <> remaining)

# An optional value restricts removal to matching name/value pairs.
def delete(params: URLSearchParams, name: String, value: Maybe<&2, String>) -> URLSearchParams:
  URLSearchParams{remove(entries(params), Form.scalar(name), optional(value))}

type SetState is Data:
  SetState{found: Bool, reversed: List<&2, Form.Entry>}

def setStep(equal: Bool, entry: Form.Entry, name: String, value: String, state: SetState) -> SetState:
  match equal state:
    case False{} SetState{found, reversed}: SetState{found, entry <> reversed}
    case True{} SetState{False{}, reversed}: SetState{True{}, Form.Entry{name, value} <> reversed}
    case True{} previous: previous

def finishSet(name: String, value: String, state: SetState) -> List<&2, Form.Entry>:
  match state:
    case SetState{True{}, reversed}: List.reverse(&2, Form.Entry, reversed)
    case SetState{False{}, reversed}: List.reverse(&2, Form.Entry, Form.Entry{name, value} <> reversed)

def replace(tuples: List<&2, Form.Entry>, +name: String, +value: String, state: SetState) -> List<&2, Form.Entry>:
  match tuples:
    case Nil{}: finishSet(name, value, state)
    case +entry <> rest: replace(rest, name, value, setStep(matches(entry, name, None{}), entry, name, value, state))

# Retain the first matching position, remove its later duplicates; append a
# missing name. One pass over the immutable tuple list performs the update.
def set(params: URLSearchParams, name: String, value: String) -> URLSearchParams:
  URLSearchParams{replace(entries(params), Form.scalar(name), Form.scalar(value), SetState{False{}, Nil{}})}

type SortEntry is Data:
  SortEntry{units: List<&2, U32>, entry: Form.Entry}

def scalarUnits(+scalar: U32, +rest: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_ge(scalar, 65536), (55296 + (scalar - 65536) / 1024 : U32) <> (56320 + (scalar - 65536) % 1024 : U32) <> rest, scalar <> rest)

def utf16Units(text: String) -> List<&2, U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{Chr{scalar}, rest}: scalarUnits(scalar, utf16Units(rest))

def sortKey(entry: Form.Entry) -> SortEntry:
  match entry:
    case Form.Entry{+name, value}: SortEntry{utf16Units(name), Form.Entry{name, value}}

def keyed(tuples: List<&2, Form.Entry>) -> List<&2, SortEntry>:
  match tuples:
    case Nil{}: Nil{}
    case entry <> rest: sortKey(entry) <> keyed(rest)

def lessEqual(left: List<&2, U32>, right: List<&2, U32>) -> Bool:
  match left right:
    case Nil{} _: True{}
    case _ Nil{}: False{}
    case +a <> left +b <> right: U32.is_lt(a, b) || (U32.is_eq(a, b) && lessEqual(left, right))

def before(left: SortEntry, right: SortEntry) -> Bool:
  match left right:
    case SortEntry{a, _} SortEntry{b, _}: lessEqual(a, b)

def unkeyed(tuples: List<&2, SortEntry>) -> List<&2, Form.Entry>:
  match tuples:
    case Nil{}: Nil{}
    case SortEntry{_, entry} <> rest: entry <> unkeyed(rest)

# The URL wire standard specifies stable UTF-16 name ordering. Cache each key
# once and use Base's stable merge sort; values never decide tie order.
def sort(params: URLSearchParams) -> URLSearchParams:
  URLSearchParams{unkeyed(List.sort(~SortEntry, ~before, keyed(entries(params))))}
