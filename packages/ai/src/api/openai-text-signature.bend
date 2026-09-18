import Base
import ../types.bend as T
import ../../../runtime/src/json-parse.bend as Json
import ../../../runtime/src/json-string.bend as StringJson
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F

def phaseName(phase: T.TextSignaturePhase) -> String:
  match phase:
    case T.Commentary{}: "commentary"
    case T.FinalAnswer{}: "final_answer"

def phaseField(phase: Maybe<&2,T.TextSignaturePhase>) -> String:
  match phase:
    case None{}: ""
    case Some{value}: ",\"phase\":" ++ StringJson.quote(phaseName(value))

def encodeTextSignatureV1(id: String, phase: Maybe<&2,T.TextSignaturePhase>) -> String:
  "{\"v\":1,\"id\":" ++ StringJson.quote(id) ++ phaseField(phase) ++ "}"

def decodedPhase(value: Maybe<&2,V.Value>) -> Maybe<&2,T.TextSignaturePhase>:
  match value:
    case Some{V.Text{"commentary"}}: Some{T.Commentary{}}
    case Some{V.Text{"final_answer"}}: Some{T.FinalAnswer{}}
    case _: None{}

def equalVersion(order: Maybe<&2,Cmp>) -> Bool:
  match order:
    case Some{EQ{}}: True{}
    case _: False{}

def version(value: Maybe<&2,V.Value>) -> Bool:
  match value:
    case Some{V.Number{number}}: equalVersion(F.compare(number,F.fromU32(1)))
    case _: False{}

def parsedFields(validVersion: Bool, id: Maybe<&2,V.Value>, phase: Maybe<&2,V.Value>) -> Maybe<&2,T.TextSignatureV1>:
  match validVersion id:
    case True{} Some{V.Text{text}}: Some{T.TextSignatureV1{text,decodedPhase(phase)}}
    case _ _: None{}

def parsedSignature(result: Result<&2,&2,Json.Error,V.Value>) -> Maybe<&2,T.TextSignatureV1>:
  match result:
    case Done{V.ObjectValue{+fields}}: parsedFields(version(R.get(V.Value,fields,"v")),R.get(V.Value,fields,"id"),R.get(V.Value,fields,"phase"))
    case _: None{}

def legacyFallback(parsed: Maybe<&2,T.TextSignatureV1>, text: String) -> Maybe<&2,T.TextSignatureV1>:
  match parsed:
    case None{}: Some{T.TextSignatureV1{text,None{}}}
    case value: value

def parseTextSignature(signature: Maybe<&2,String>) -> Maybe<&2,T.TextSignatureV1>:
  match signature:
    case None{}: None{}
    case Some{SNil{}}: None{}
    case Some{SCon{'{',+rest}}: legacyFallback(parsedSignature(Json.parse(SCon{'{',rest})),SCon{'{',rest})
    case Some{text}: Some{T.TextSignatureV1{text,None{}}}
