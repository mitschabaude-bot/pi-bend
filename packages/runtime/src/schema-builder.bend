import Base
import ./schema.bend as S
import ./schema-load.bend as Loader
import ./schema-value.bend as V
import ./schema-convert.bend as C
import ./record.bend as R
import ./big-nat.bend as B
import ./number-string.bend as Number

# A declaration carries its wire schema, executable constraint and conversion
# policy explicitly. Builders keep these projections together as immutable data.
type Declaration is Data:
  Declaration{schema: V.Value, constraint: S.Schema, conversion: C.Policy}

def schema(declaration: Declaration) -> V.Value:
  match declaration:
    case Declaration{raw, _, _}: raw

def constraint(declaration: Declaration) -> S.Schema:
  match declaration:
    case Declaration{_, checker, _}: checker

def conversion(declaration: Declaration) -> C.Policy:
  match declaration:
    case Declaration{_, _, policy}: policy

def primitive(name: String, kind: S.JsonType, policy: C.Primitive) -> Declaration:
  Declaration{V.ObjectValue{R.Record{R.Property{"type", V.Text{name}} <> Nil{}}}, S.JsonKind{kind}, C.Scalar{policy}}

def boolean() -> Declaration: primitive("boolean", S.BooleanType{}, C.ToBoolean{})
def number() -> Declaration: primitive("number", S.NumberType{}, C.ToNumber{})
def integer() -> Declaration: primitive("integer", S.IntegerType{}, C.ToInteger{})
def string() -> Declaration: primitive("string", S.StringType{}, C.ToString{})
def null() -> Declaration: primitive("null", S.NullType{}, C.ToNull{})
def unknown() -> Declaration: Declaration{V.ObjectValue{R.new(V.Value)}, S.Accept{}, C.Preserve{}}
def never() -> Declaration: Declaration{V.ObjectValue{R.Record{R.Property{"not", V.ObjectValue{R.new(V.Value)}} <> Nil{}}}, S.Not{S.Accept{}}, C.Preserve{}}

def literalDeclaration(name: String, kind: S.JsonType, +value: V.Value, policy: C.LiteralValue) -> Declaration:
  Declaration{V.ObjectValue{R.Record{R.Property{"type", V.Text{name}} <> R.Property{"const", value} <> Nil{}}}, S.All{S.JsonKind{kind} <> S.Constant{value} <> Nil{}}, C.Literal{policy}}

def literal(value: C.LiteralValue) -> Declaration:
  match value:
    case C.BooleanLiteral{+value}: literalDeclaration("boolean", S.BooleanType{}, V.Boolean{value}, C.BooleanLiteral{value})
    case C.NumberLiteral{+value}: literalDeclaration("number", S.NumberType{}, V.Number{value}, C.NumberLiteral{value})
    case C.StringLiteral{+value}: literalDeclaration("string", S.StringType{}, V.Text{value}, C.StringLiteral{value})

def array(item: Declaration) -> Declaration:
  match item:
    case Declaration{raw, checker, policy}:
      Declaration{V.ObjectValue{R.Record{R.Property{"type", V.Text{"array"}} <> R.Property{"items", raw} <> Nil{}}}, S.All{S.JsonKind{S.ArrayType{}} <> S.Array{Nil{}, checker} <> Nil{}}, C.ArrayItems{policy}}

def schemas(items: List<&2, Declaration>) -> List<&2, V.Value>:
  match items:
    case Nil{}: Nil{}
    case head <> tail: schema(head) <> schemas(tail)

def constraints(items: List<&2, Declaration>) -> List<&2, S.Schema>:
  match items:
    case Nil{}: Nil{}
    case head <> tail: constraint(head) <> constraints(tail)

def conversions(items: List<&2, Declaration>) -> List<&2, C.Policy>:
  match items:
    case Nil{}: Nil{}
    case head <> tail: conversion(head) <> conversions(tail)

def count(items: List<&2, Declaration>) -> B.BigNat:
  match items:
    case Nil{}: B.zero()
    case _ <> tail: B.add(count(tail), B.fromU32(1))

def tuple(+items: List<&2, Declaration>) -> Declaration:
  +size = count(items)
  Declaration{
    V.ObjectValue{R.Record{R.Property{"type", V.Text{"array"}} <> R.Property{"additionalItems", V.Boolean{False{}}} <> R.Property{"items", V.ArrayValue{schemas(items)}} <> R.Property{"minItems", V.Number{Number.toNumber(B.toDecimal(size))}} <> Nil{}}},
    S.All{S.JsonKind{S.ArrayType{}} <> S.AdditionalItems{List.length(&2, Declaration, items), S.Reject{}} <> S.Array{constraints(items), S.Accept{}} <> S.ItemCount{S.CountBounds{size, None{}}} <> Nil{}},
    C.TupleItems{conversions(items)}}

def branches(items: List<&2, Declaration>) -> List<&2, C.Branch<C.Policy>>:
  match items:
    case Nil{}: Nil{}
    case Declaration{_, checker, policy} <> tail: C.Branch{checker, policy} <> branches(tail)

def union(+items: List<&2, Declaration>) -> Declaration:
  Declaration{V.ObjectValue{R.Record{R.Property{"anyOf", V.ArrayValue{schemas(items)}} <> Nil{}}}, S.Any{constraints(items)}, C.union(branches(items))}

def check(declaration: Declaration, value: V.Value) -> Bool:
  S.check(constraint(declaration), value)

def convert(declaration: Declaration, value: V.Value) -> C.Converted():
  C.apply(conversion(declaration), value)

# Optionality belongs to a declared field, rather than hidden metadata on the
# schema value. Required and optional fields share the same value constraint.
type Field is Data:
  Required{declaration: Declaration}
  Optional{declaration: Declaration}

def required(declaration: Declaration) -> Field: Required{declaration}
def optional(declaration: Declaration) -> Field: Optional{declaration}

def fieldDeclaration(field: Field) -> Declaration:
  match field:
    case Required{declaration}: declaration
    case Optional{declaration}: declaration

def requiredKeys(fields: List<&2, R.Property<Field>>) -> List<&2, String>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, Required{_}} <> rest: key <> requiredKeys(rest)
    case R.Property{_, Optional{_}} <> rest: requiredKeys(rest)

def fieldSchemas(fields: List<&2, R.Property<Field>>) -> List<&2, R.Property<V.Value>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, field} <> rest: R.Property{key, schema(fieldDeclaration(field))} <> fieldSchemas(rest)

def fieldConstraints(fields: List<&2, R.Property<Field>>) -> List<&2, R.Property<S.Schema>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, field} <> rest: R.Property{key, constraint(fieldDeclaration(field))} <> fieldConstraints(rest)

def fieldConversions(fields: List<&2, R.Property<Field>>) -> List<&2, R.Property<C.Policy>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, field} <> rest: R.Property{key, conversion(fieldDeclaration(field))} <> fieldConversions(rest)

def textValues(keys: List<&2, String>) -> List<&2, V.Value>:
  match keys:
    case Nil{}: Nil{}
    case key <> rest: V.Text{key} <> textValues(rest)

def requiredSchema(keys: List<&2, String>) -> List<&2, R.Property<V.Value>>:
  match keys:
    case Nil{}: Nil{}
    case keys: R.Property{"required", V.ArrayValue{textValues(keys)}} <> Nil{}

# Literal-key conversion is the proposed native policy. Its known differences
# from TypeBox's regexp-key behavior await approval before public integration.
# This factory uses the default unconstrained, unconverted additional fields.
def object(fields: R.Record<Field>) -> Declaration:
  match fields:
    case R.Record{+fields}:
      +keys = requiredKeys(fields)
      Declaration{
        V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> List.append(&2, R.Property<V.Value>, requiredSchema(keys), R.Property{"properties", V.ObjectValue{R.Record{fieldSchemas(fields)}}} <> Nil{})}},
        S.All{S.JsonKind{S.ObjectType{}} <> S.Object{R.Record{fieldConstraints(fields)}, keys, S.Accept{}} <> Nil{}},
        C.ObjectFields{R.Record{fieldConversions(fields)}, C.Preserve{}}}

# A schema-valued additional field has its own constraint and conversion
# policy. Declared fields take precedence; absent fields are never synthesized.
def objectWithAdditional(fields: R.Record<Field>, additional: Declaration) -> Declaration:
  match fields additional:
    case R.Record{+fields} Declaration{raw, checker, policy}:
      +keys = requiredKeys(fields)
      Declaration{
        V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> List.append(&2, R.Property<V.Value>, requiredSchema(keys), R.Property{"properties", V.ObjectValue{R.Record{fieldSchemas(fields)}}} <> R.Property{"additionalProperties", raw} <> Nil{})}},
        S.All{S.JsonKind{S.ObjectType{}} <> S.Object{R.Record{fieldConstraints(fields)}, keys, checker} <> Nil{}},
        C.ObjectFields{R.Record{fieldConversions(fields)}, policy}}

# Constraint/annotation options preserve conversion, except that a boolean
# additionalProperties override removes that field conversion policy. Union
# candidate selection also uses the new whole schema constraint.
type OptionError is Data:
  UnsupportedOption{name: String}
  InvalidOptionSchema{error: Loader.Error}
  ExpectedObjectSchema{}

def Configured() -> Data: Result<&2, &2, OptionError, Declaration>

def booleanOption(value: V.Value) -> Bool:
  match value:
    case V.Boolean{_}: True{}
    case _: False{}

def supportedOption(kind: Loader.KeywordKind, value: V.Value) -> Bool:
  match kind:
    case Loader.AnnotationKeyword{}: True{}
    case Loader.MultipleOfKeyword{}: True{}
    case Loader.MinimumKeyword{}: True{}
    case Loader.MaximumKeyword{}: True{}
    case Loader.ExclusiveMinimumKeyword{}: True{}
    case Loader.ExclusiveMaximumKeyword{}: True{}
    case Loader.MinLengthKeyword{}: True{}
    case Loader.MaxLengthKeyword{}: True{}
    case Loader.MinItemsKeyword{}: True{}
    case Loader.MaxItemsKeyword{}: True{}
    case Loader.MinPropertiesKeyword{}: True{}
    case Loader.MaxPropertiesKeyword{}: True{}
    case Loader.UniqueItemsKeyword{}: True{}
    case Loader.AdditionalPropertiesKeyword{}: booleanOption(value)
    case _: False{}

def mergeOptions(options: List<&2, R.Property<V.Value>>, state: Result<&2, &2, OptionError, R.Record<V.Value>>) -> Result<&2, &2, OptionError, R.Record<V.Value>>:
  match options state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{fields}: Done{fields}
    case R.Property{+key, +value} <> rest Done{fields}:
      mergeOptions(rest, Bool.pick(Unit -> Result<&2, &2, OptionError, R.Record<V.Value>>, supportedOption(Loader.keywordKind(key), value),
        _ => Done{R.set(V.Value, fields, key, value)}, _ => Fail{UnsupportedOption{key}})(Unit{}))

def additionalConversion(fields: R.Record<C.Policy>, additional: C.Policy, raw: Maybe<&2, V.Value>) -> C.Policy:
  match raw:
    case Some{V.Boolean{_}}: C.ObjectFields{fields, C.Preserve{}}
    case _: C.ObjectFields{fields, additional}

def configuredConversion(policy: C.Policy, checker: S.Schema, raw: V.Value) -> C.Policy:
  match policy:
    case C.Union{choices, _}: C.Union{choices, checker}
    case C.ObjectFields{fields, additional}:
      match raw:
        case V.ObjectValue{properties}:
          additionalConversion(fields, additional, R.get(V.Value, properties, "additionalProperties"))
        case _: C.ObjectFields{fields, additional}
    case other: other

def configuredSchema(+raw: V.Value, policy: C.Policy, loaded: Loader.Loaded()) -> Configured():
  match loaded:
    case Fail{error}: Fail{InvalidOptionSchema{error}}
    case Done{+checker}: Done{Declaration{raw, checker, configuredConversion(policy, checker, raw)}}

def configuredFields(fields: Result<&2, &2, OptionError, R.Record<V.Value>>, policy: C.Policy) -> Configured():
  match fields:
    case Fail{error}: Fail{error}
    case Done{+fields}: configuredSchema(V.ObjectValue{fields}, policy, Loader.compile(V.ObjectValue{fields}))

def withOptions(declaration: Declaration, options: R.Record<V.Value>) -> Configured():
  match declaration:
    case Declaration{V.ObjectValue{fields}, _, policy}: configuredFields(mergeOptions(R.entries(V.Value, options), Done{fields}), policy)
    case _: Fail{ExpectedObjectSchema{}}
