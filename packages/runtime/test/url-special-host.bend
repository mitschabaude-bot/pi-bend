import Base
import ../src/url.bend as Special
import ../src/url.bend as Host
import ../src/idna.bend as Domain
import ../src/idna.bend as Label
import ../src/idna.bend as Mapping
import ../src/unicode-17-idna-mapping.bend as MappingData
import ../src/unicode-17-normalization.bend as NormalizationData
import ../src/unicode-17-idna-properties.bend as PropertiesData
import ../src/string.bend as Split
import ./utf8-runner.bend as Text

def text(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: text(rest, reversed)
    case part <> rest: text(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def kind(value: Host.Host) -> String:
  match value:
    case Host.Domain{_}: "domain"
    case Host.IPv4{_}: "ipv4"
    case Host.IPv6{_}: "ipv6"
    case _: "unexpected"

def show(value: Result<&2, &2, Special.SpecialHostError, Host.Host>) -> String:
  match value:
    case Fail{_}: "invalid"
    case Done{+host}: kind(host) ++ ";" ++ Text.showText(Host.serializeHost(host))

def cases(args: List<String>, +context: Label.Context) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(show(Special.parseSpecialHost(context, Domain.Options{Label.LabelOptions{False{}, False{}, True{}, Mapping.Nontransitional{}}, True{}, False{}}, text(Split.split(head, ','), ""))))
        cases(rest, context)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args, Label.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()})
