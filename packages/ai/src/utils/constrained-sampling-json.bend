import Base
import ../types.bend as T
import ./grammar-variants.bend as G
import ../../../runtime/src/record.bend as R

# Wire codec for the typed constrained-sampling domain. Object field order is
# retained because transcript declarations are compared by JSON serialization.
def grammarFields(properties: List<&2, T.GrammarVariant>, fields: R.Record<T.JsonValue>) -> R.Record<T.JsonValue>:
  match properties:
    case Nil{}: fields
    case T.GrammarVariant{_, None{}} <> rest: grammarFields(rest, fields)
    case T.GrammarVariant{format, Some{value}} <> rest:
      grammarFields(rest, R.set(T.JsonValue, fields, G.name(format), T.JsonString{value}))

def grammarVariants(value: T.GrammarVariants) -> T.JsonValue:
  match value:
    case T.GrammarVariants{properties}: T.JsonObject{grammarFields(properties, R.new(T.JsonValue))}

def strictness(value: T.SamplingStrictness) -> String:
  match value:
    case T.Prefer{}: "prefer"
    case T.Require{}: "require"

def configFields(order: T.SamplingPropertyOrder, tag: String, key: String, value: T.JsonValue) -> R.Record<T.JsonValue>:
  match order:
    case T.TypeFirst{}: R.set(T.JsonValue, R.set(T.JsonValue, R.new(T.JsonValue), "type", T.JsonString{tag}), key, value)
    case T.TypeLast{}: R.set(T.JsonValue, R.set(T.JsonValue, R.new(T.JsonValue), key, value), "type", T.JsonString{tag})

def config(value: T.ConstrainedSamplingConfig) -> T.JsonValue:
  match value:
    case T.JsonSchemaSampling{strict, order}: T.JsonObject{configFields(order, "json_schema", "strict", T.JsonString{strictness(strict)})}
    case T.GrammarSampling{variants, order}: T.JsonObject{configFields(order, "grammar", "variants", grammarVariants(variants))}

def toJson(value: T.ToolConstrainedSampling) -> T.JsonValue:
  match value:
    case T.SamplingDisabled{}: T.JsonBoolean{False{}}
    case T.SamplingConfigured{settings}: config(settings)
