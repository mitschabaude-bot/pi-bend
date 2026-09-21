import Base
import ./url-percent.bend as Percent
import ./utf8.bend as Utf8
import ./string-split.bend as Split

# Ordered tuples retain duplicates and empty names/values. Delimiters are
# recognized before percent decoding, so encoded '&' and '=' remain data.
type Entry is Data:
  Entry{name: String, value: String}

def plus(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{'+', rest}: SCon{' ', plus(rest)}
    case SCon{char, rest}: SCon{char, plus(rest)}

# Form parsing uses replacement-mode UTF-8 without stripping a leading BOM.
def decoded(text: String) -> String:
  Utf8.complete(Utf8.decode(Utf8.Decoder{Utf8.Ready{}, True{}}, Percent.decode(Utf8.encode(plus(text)))))

def split(text: String, reversed: String) -> Entry:
  match text:
    case SNil{}: Entry{decoded(String.reverse(reversed)), ""}
    case SCon{'=', value}: Entry{decoded(String.reverse(reversed)), decoded(value)}
    case SCon{char, rest}: split(rest, SCon{char, reversed})

def parseParts(parts: List<&2, String>, reversed: List<&2, Entry>) -> List<&2, Entry>:
  match parts:
    case Nil{}: List.reverse(&2, Entry, reversed)
    case SNil{} <> rest: parseParts(rest, reversed)
    case part <> rest: parseParts(rest, split(part, "") <> reversed)

# Unlike the URLSearchParams string constructor, a form body does not strip '?'.
def parse(text: String) -> List<&2, Entry>:
  parseParts(Split.split(text, '&'), Nil{})

def encoded(entry: Entry) -> String:
  match entry:
    case Entry{name, value}: Percent.encode(Percent.Form{}, name) ++ "=" ++ Percent.encode(Percent.Form{}, value)

def encodeEntries(entries: List<&2, Entry>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: encoded(entry) <> encodeEntries(rest)

def serialize(entries: List<&2, Entry>) -> String:
  String.join(encodeEntries(entries), "&")

# Web URL inputs are scalar-value strings, preserving BOM and replacing only
# invalid scalar representations. This is not Unicode NFC/case normalization.
def scalar(text: String) -> String:
  Utf8.complete(Utf8.decode(Utf8.Decoder{Utf8.Ready{}, True{}}, Utf8.encode(text)))

def normalize(entry: Entry) -> Entry:
  match entry:
    case Entry{name, value}: Entry{scalar(name), scalar(value)}
