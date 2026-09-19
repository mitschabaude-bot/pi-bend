import Base
import ../src/utils/headers.bend as Headers
import ../src/types.bend as T
import ../../runtime/src/record.bend as R
import ../../runtime/test/utf8-runner.bend as H

def text(value: String) -> String: H.fromScalars(H.parseNumbers(value))

def value(encoded: String) -> T.Nullable<String>:
  match encoded:
    case "~": T.NullValue{}
    case other: T.PresentValue{text(other)}

def add(record: T.ProviderHeaders(), parts: List<&2, String>) -> T.ProviderHeaders():
  match parts:
    case name <> encoded <> Nil{}: R.set(T.Nullable<String>, record, text(name), value(encoded))
    case _: record

def build(parts: List<&2, String>, record: T.ProviderHeaders()) -> T.ProviderHeaders():
  match parts:
    case Nil{}: record
    case head <> rest: build(rest, add(record, String.split(head, ';')))

def entries(properties: List<&2, R.Property<String>>) -> List<&2, String>:
  match properties:
    case Nil{}: Nil{}
    case R.Property{name, item} <> rest: (H.showText(name) ++ ";" ++ H.showText(item)) <> entries(rest)

def shown(result: Maybe<&2, R.Record<String>>) -> String:
  match result:
    case None{}: "none"
    case Some{R.Record{properties}}: "some|" ++ String.join(entries(properties), "|")

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case "n" <> Nil{}: IO.print(shown(Headers.providerHeadersToRecord(None{})))
    case "p" <> rest: IO.print(shown(Headers.providerHeadersToRecord(Some{build(rest, R.new(T.Nullable<String>))})))
    case _: IO.die(Unit, 1, "invalid provider headers fixture")

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        run(String.split(head, '|'))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)
