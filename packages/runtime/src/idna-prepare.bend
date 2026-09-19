import Base
import ./u32-table.bend as Table
import ./idna-mapping-data.bend as MappingData
import ./idna-mapping.bend as Mapping
import ./unicode-normalization-data.bend as NormalizationData
import ./unicode-normalization.bend as Normalization

type Context is Data:
  Context{mapping: Table.Table<MappingData.Entry>, normalization: NormalizationData.Tables}

def normalized(result: Result<&2, &2, Mapping.MappingError, String>, tables: NormalizationData.Tables) -> Result<&2, &2, Mapping.MappingError, String>:
  match result:
    case Fail{error}: Fail{error}
    case Done{text}: Done{Normalization.nfc(tables, text)}

# UTS #46 mapping followed by NFC. This is input preparation, not a validated
# domain: label splitting, ACE handling, contextual/Bidi rules and host checks
# still have to run before a result can be used as a hostname.
def prepare(context: Context, mode: Mapping.Mode, input: String) -> Result<&2, &2, Mapping.MappingError, String>:
  match context:
    case Context{mapping, normalization}: normalized(Mapping.map(mapping, mode, input), normalization)
