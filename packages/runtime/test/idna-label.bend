import Base
import ../src/idna.bend as Label
import ../src/idna.bend as Rules
import ../src/idna.bend as ACE
import ../src/idna.bend as Bidi
import ../src/punycode.bend as Core
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

def mode(value: String) -> Mapping.Mode:
  match value:
    case "t": Mapping.Transitional{}
    case _: Mapping.Nontransitional{}

def bit(value: Bool) -> String:
  match value:
    case True{}: "1"
    case False{}: "0"

def show(value: Result<&2, &2, Label.LabelError, Label.LabelLabel>) -> String:
  match value:
    case Fail{Label.ACEError{ACE.NonASCIIEncoding{}}}: "non-ascii"
    case Fail{Label.ACEError{ACE.ASCIIOnlyDecodedLabel{}}}: "ascii-only"
    case Fail{Label.ACEError{ACE.InvalidPunycode{Core.InvalidInput{}}}}: "invalid"
    case Fail{Label.ACEError{ACE.InvalidPunycode{Core.Overflow{}}}}: "overflow"
    case Fail{Label.NotNFC{}}: "nfc"
    case Fail{Label.LeadingMark{}}: "mark"
    case Fail{Label.JoinerContext{}}: "joiners"
    case Fail{Label.MissingProperties{code}}: "missing;" ++ U32.show(code)
    case Fail{Label.LabelRule{Rules.HyphenPositions{}}}: "hyphen-positions"
    case Fail{Label.LabelRule{Rules.HyphenEdge{}}}: "hyphen-edge"
    case Fail{Label.LabelRule{Rules.ReservedPrefix{}}}: "reserved"
    case Fail{Label.LabelRule{Rules.Dot{}}}: "dot"
    case Fail{Label.LabelRule{Rules.InvalidASCII{code}}}: "ascii;" ++ U32.show(code)
    case Fail{Label.LabelRule{Rules.InvalidStatus{code}}}: "status;" ++ U32.show(code)
    case Done{Label.LabelLabel{input, empty, Bidi.Analysis{rtl, valid}}}:
      "ok;" ++ bit(empty) ++ bit(rtl) ++ bit(valid) ++ ";" ++ Text.showText(input)

def run(parts: List<&2, String>, context: Label.Context) -> String:
  match parts:
    case processing <> hyphens <> std3 <> joiners <> input <> Nil{}:
      show(Label.process(context, Label.LabelOptions{String.eq(hyphens, "1"), String.eq(std3, "1"), String.eq(joiners, "1"), mode(processing)}, text(Split.split(input, ','), "")))
    case _: "invalid-case"

def cases(args: List<String>, +context: Label.Context) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(Split.split(head, ';'), context))
        cases(rest, context)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args, Label.Context{MappingData.table(), NormalizationData.tables(), PropertiesData.table()})
