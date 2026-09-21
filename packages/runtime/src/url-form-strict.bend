import Base
import ./url-form.bend as Form
import ./uri-component.bend as URI
import ./string-split.bend as Split

# Provider configuration rejects malformed percent escapes and malformed UTF-8.
# Error positions count '&'-separated fields, including empty fields. Never put
# a credential-bearing field's contents into an error value.
type Error is Data:
  InvalidName{field: Nat}
  InvalidValue{field: Nat}

def decoded(field: Nat, name: Maybe<&2, String>, value: Maybe<&2, String>) -> Result<&2, &2, Error, Form.Entry>:
  match name value:
    case None{} _: Fail{InvalidName{field}}
    case Some{_} None{}: Fail{InvalidValue{field}}
    case Some{name} Some{value}: Done{Form.Entry{name, value}}

def pair(+field: Nat, name: String, value: String) -> Result<&2, &2, Error, Form.Entry>:
  decoded(field, URI.decode(Form.plus(name)), URI.decode(Form.plus(value)))

def split(field: Nat, text: String, reversed: String) -> Result<&2, &2, Error, Form.Entry>:
  match text:
    case SNil{}: pair(field, String.reverse(reversed), "")
    case SCon{'=', value}: pair(field, String.reverse(reversed), value)
    case SCon{char, rest}: split(field, rest, SCon{char, reversed})

def prepend(parsed: Result<&2, &2, Error, Form.Entry>, reversed: List<&2, Form.Entry>) -> Result<&2, &2, Error, List<&2, Form.Entry>>:
  match parsed:
    case Fail{cause}: Fail{cause}
    case Done{tuple}: Done{tuple <> reversed}

def step(field: Nat, text: String, result: Result<&2, &2, Error, List<&2, Form.Entry>>) -> Result<&2, &2, Error, List<&2, Form.Entry>>:
  match text result:
    case _ Fail{cause}: Fail{cause}
    case SNil{} Done{reversed}: Done{reversed}
    case other Done{reversed}: prepend(split(field, other, ""), reversed)

def fields(parts: List<&2, String>, +field: Nat, result: Result<&2, &2, Error, List<&2, Form.Entry>>) -> Result<&2, &2, Error, List<&2, Form.Entry>>:
  match parts result:
    case _ Fail{cause}: Fail{cause}
    case Nil{} done: done
    case text <> rest Done{reversed}: fields(rest, Succ{field}, step(field, text, Done{reversed}))

def finish(result: Result<&2, &2, Error, List<&2, Form.Entry>>) -> Result<&2, &2, Error, List<&2, Form.Entry>>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{reversed}: Done{List.reverse(&2, Form.Entry, reversed)}

def parse(text: String) -> Result<&2, &2, Error, List<&2, Form.Entry>>:
  finish(fields(Split.split(text, '&'), Zero{}, Done{Nil{}}))

# Query syntax allows one leading '?'; a form body treats it as ordinary data.
def query(text: String) -> Result<&2, &2, Error, List<&2, Form.Entry>>:
  match text:
    case SCon{'?', rest}: parse(rest)
    case other: parse(other)
