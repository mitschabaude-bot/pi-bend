import Base
import ./schema.bend as S
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
  Declaration{V.ObjectValue{R.Record{R.Property{"anyOf", V.ArrayValue{schemas(items)}} <> Nil{}}}, S.Any{constraints(items)}, C.Union{branches(items)}}

def check(declaration: Declaration, value: V.Value) -> Bool:
  S.check(constraint(declaration), value)

def convert(declaration: Declaration, value: V.Value) -> C.Converted():
  C.apply(conversion(declaration), value)
