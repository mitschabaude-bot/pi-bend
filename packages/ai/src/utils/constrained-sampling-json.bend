import Base
import ../types.bend as T
import ../../../runtime/src/record.bend as R

def optionalField(fields: R.Record<T.JsonValue>, key: String, value: Maybe<&2, String>) -> R.Record<T.JsonValue>:
  match value:
    case None{}: fields
    case Some{text}: R.set(T.JsonValue, fields, key, T.JsonString{text})

def grammarVariants(value: T.GrammarVariants) -> T.JsonValue:
  match value:
    case T.GrammarVariants{lark, regex}: T.JsonObject{optionalField(optionalField(R.new(T.JsonValue), "openai_lark", lark), "openai_regex", regex)}

def strictness(value: T.SamplingStrictness) -> String:
  match value:
    case T.Prefer{}: "prefer"
    case T.Require{}: "require"

def configFields(tag: String, key: String, value: T.JsonValue) -> R.Record<T.JsonValue>:
  R.set(T.JsonValue, R.set(T.JsonValue, R.new(T.JsonValue), "type", T.JsonString{tag}), key, value)

def config(value: T.ConstrainedSamplingConfig) -> T.JsonValue:
  match value:
    case T.JsonSchemaSampling{strict}: T.JsonObject{configFields("json_schema", "strict", T.JsonString{strictness(strict)})}
    case T.GrammarSampling{variants}: T.JsonObject{configFields("grammar", "variants", grammarVariants(variants))}

def toJson(value: T.ToolConstrainedSampling) -> T.JsonValue:
  match value:
    case T.SamplingDisabled{}: T.JsonBoolean{False{}}
    case T.SamplingConfigured{value}: config(value)
