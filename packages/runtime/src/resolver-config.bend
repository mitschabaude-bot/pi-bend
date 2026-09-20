import Base
import ./resolver-address.bend as Address
import ./string-split.bend as Split

# An immutable syntax tree, before resolver policy and OS scope resolution.
# Keep unknown directives and invalid server tokens available to diagnostics;
# parsing never invents default servers or silently applies only some options.
type Entry is Data:
  Nameserver{token: String, address: Result<&2, &2, Address.Error, Address.Address>}
  Domain{name: String}
  Search{names: List<&2, String>}
  Options{values: List<&2, String>}
  Sortlist{values: List<&2, String>}
  Unknown{line: String}

type Keyword is Data:
  ServerKey{}
  DomainKey{}
  SearchKey{}
  OptionsKey{}
  SortKey{}
  OtherKey{}

def keywordFlags(server: Bool, domain: Bool, search: Bool, options: Bool, sort: Bool) -> Keyword:
  match server domain search options sort:
    case True{} _ _ _ _: ServerKey{}
    case _ True{} _ _ _: DomainKey{}
    case _ _ True{} _ _: SearchKey{}
    case _ _ _ True{} _: OptionsKey{}
    case _ _ _ _ True{}: SortKey{}
    case _ _ _ _ _: OtherKey{}

def keyword(+text: String) -> Keyword:
  keywordFlags(String.eq(text, "nameserver"), String.eq(text, "domain"), String.eq(text, "search"), String.eq(text, "options"), String.eq(text, "sortlist"))

def pushed(part: String, fields: List<&2, String>) -> List<&2, String>:
  match part:
    case SNil{}: fields
    case text: String.reverse(text) <> fields

type Words is Data:
  Words{part: String, fields: List<&2, String>}

def stepped(space: Bool, char: Char, state: Words) -> Words:
  match space state:
    case True{} Words{part, fields}: Words{"", pushed(part, fields)}
    case False{} Words{part, fields}: Words{SCon{char, part}, fields}

def words(text: String, state: Words) -> List<&2, String>:
  match text state:
    case SNil{} Words{part, fields}: List.reverse(&2, String, pushed(part, fields))
    case SCon{+char, rest} previous: words(rest, stepped(Char.is_eq(char, ' ') || Char.is_eq(char, '\t'), char, previous))

def entry(kind: Keyword, fields: List<&2, String>, original: String) -> Maybe<&2, Entry>:
  match kind fields:
    case ServerKey{} Nil{}: Some{Nameserver{"", Fail{Address.InvalidAddress{}}}}
    case ServerKey{} +token <> _: Some{Nameserver{token, Address.parse(token)}}
    case DomainKey{} Nil{}: None{}
    case DomainKey{} first <> _: Some{Domain{first}}
    case SearchKey{} Nil{}: None{}
    case SearchKey{} names: Some{Search{names}}
    case OptionsKey{} values: Some{Options{values}}
    case SortKey{} values: Some{Sortlist{values}}
    case OtherKey{} _: Some{Unknown{original}}

# A directive keyword starts in column zero and requires a space/tab delimiter.
# Nameserver/domain consume one token; other known directives retain all tokens.
def header(text: String, original: String, reversed: String) -> Maybe<&2, Entry>:
  match text:
    case SNil{}: Some{Unknown{original}}
    case SCon{' ', rest}: entry(keyword(String.reverse(reversed)), words(rest, Words{"", Nil{}}), original)
    case SCon{'\t', rest}: entry(keyword(String.reverse(reversed)), words(rest, Words{"", Nil{}}), original)
    case SCon{char, rest}: header(rest, original, SCon{char, reversed})

def line(+text: String) -> Maybe<&2, Entry>:
  match text:
    case SNil{}: None{}
    case SCon{'#', _}: None{}
    case SCon{';', _}: None{}
    case other: header(other, other, "")

def appended(value: Maybe<&2, Entry>, reversed: List<&2, Entry>) -> List<&2, Entry>:
  match value:
    case None{}: reversed
    case Some{item}: item <> reversed

def lines(input: List<&2, String>, reversed: List<&2, Entry>) -> List<&2, Entry>:
  match input:
    case Nil{}: List.reverse(&2, Entry, reversed)
    case text <> rest: lines(rest, appended(line(text), reversed))

# Input is decoded configuration text. File loading, byte-decoding policy,
# environment overrides, defaults and applying the entries are separate layers.
def parse(text: String) -> List<&2, Entry>:
  lines(Split.split(text, '\n'), Nil{})
