import Base
import ./u32-table.bend as Table
import ./idna-mapping.bend as Mapping
import ./idna-mapping-data.bend as MappingData
import ./unicode-normalization-data.bend as NormalizationData
import ./unicode-normalization.bend as Normalization
import ./idna-properties.bend as Properties
import ./idna-label-rules.bend as Rules
import ./idna-label-context.bend as Contextual
import ./idna-bidi.bend as Bidi
import ./idna-ace.bend as ACE

type Context is Data:
  Context{mapping: Table.Table<MappingData.Entry>, normalization: NormalizationData.Tables, properties: Table.Table<Properties.Entry>}

type Options is Data:
  Options{checkHyphens: Bool, useSTD3: Bool, checkJoiners: Bool, mode: Mapping.Mode}

type Error is Data:
  ACEError{reason: ACE.Error}
  NotNFC{}
  LabelRule{reason: Rules.Error}
  LeadingMark{}
  JoinerContext{}
  MissingProperties{code: U32}

type Label is Data:
  Label{text: String, empty: Bool, bidi: Bidi.Analysis}

def isEmpty(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case _: False{}

def effectiveMode(encoded: Bool, mode: Mapping.Mode) -> Mapping.Mode:
  match encoded:
    case True{}: Mapping.Nontransitional{}
    case False{}: mode

def contextualResult(analysis: Result<&2, &2, U32, Contextual.Analysis>, checkJoiners: Bool, +text: String) -> Result<&2, &2, Error, Label>:
  match analysis checkJoiners:
    case Fail{code} _: Fail{MissingProperties{code}}
    case Done{Contextual.Analysis{True{}, _, _}} _: Fail{LeadingMark{}}
    case Done{Contextual.Analysis{False{}, _, False{}}} True{}: Fail{JoinerContext{}}
    case Done{Contextual.Analysis{False{}, bidi, _}} _: Done{Label{text, isEmpty(text), bidi}}

def afterRules(failure: Maybe<&2, Rules.Error>, properties: Table.Table<Properties.Entry>, checkJoiners: Bool, +text: String) -> Result<&2, &2, Error, Label>:
  match failure:
    case Some{error}: Fail{LabelRule{error}}
    case None{}: contextualResult(Contextual.analyze(properties, text), checkJoiners, text)

def afterNFC(normalized: Bool, mapping: Table.Table<MappingData.Entry>, properties: Table.Table<Properties.Entry>, rules: Rules.Options, checkJoiners: Bool, +text: String) -> Result<&2, &2, Error, Label>:
  match normalized:
    case False{}: Fail{NotNFC{}}
    case True{}: afterRules(Rules.check(mapping, rules, text), properties, checkJoiners, text)

def validate(context: Context, options: Options, label: ACE.Label) -> Result<&2, &2, Error, Label>:
  match context options label:
    case Context{mapping, normalization, properties} Options{hyphens, std3, joiners, mode} ACE.Label{+text, encoded}:
      afterNFC(String.eq(text, Normalization.nfc(normalization, text)), mapping, properties,
        Rules.Options{hyphens, std3, effectiveMode(encoded, mode)}, joiners, text)

def afterDecode(result: Result<&2, &2, ACE.Error, ACE.Label>, context: Context, options: Options) -> Result<&2, &2, Error, Label>:
  match result:
    case Fail{error}: Fail{ACEError{error}}
    case Done{label}: validate(context, options, label)

# Strict conversion/validation of one label AFTER domain-wide mapping/NFC and
# splitting. ACE output is checked without repair. Empty-label/DNS-length and
# domain-wide Bidi decisions remain with the domain processor; skip Bidi validity
# for empty labels and apply it to every nonempty label in a Bidi domain.
def process(context: Context, options: Options, input: String) -> Result<&2, &2, Error, Label>:
  afterDecode(ACE.decode(input), context, options)
