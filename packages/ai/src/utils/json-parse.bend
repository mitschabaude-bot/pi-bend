import Base
import ../../../runtime/src/partial-json.bend as Partial
import ../../../runtime/src/text.bend as Space
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/json.bend as Json
import ../../../runtime/src/json.bend as StringJson
import ../../../runtime/src/schema-value.bend as V

# Repair string-literal spelling only. Object/array structure, missing values
# and incomplete numbers are left to parsing rather than guessed here.
type RepairMode is Data:
  OutsideString{}
  InsideString{}
  AfterBackslash{}

def validEscape(char: Char) -> Bool:
  match char:
    case '"': True{}
    case '\\': True{}
    case '/': True{}
    case 'b': True{}
    case 'f': True{}
    case 'n': True{}
    case 'r': True{}
    case 't': True{}
    case 'u': True{}
    case _: False{}

def controlCharacter(+char: Char) -> String:
  match char:
    case Chr{+code}: Bool.pick(String, U32.is_le(code, 31), StringJson.escapeCode(code), SCon{char, SNil{}})

def finishRepair(mode: RepairMode) -> String:
  match mode:
    case AfterBackslash{}: "\\\\"
    case _: ""

type RepairStep is Data:
  RepairStep{mode: RepairMode, fragment: String}

def outside(char: Char) -> RepairStep:
  match char:
    case '"': RepairStep{InsideString{}, "\""}
    case value: RepairStep{OutsideString{}, SCon{value, SNil{}}}

def inside(char: Char) -> RepairStep:
  match char:
    case '"': RepairStep{OutsideString{}, "\""}
    case '\\': RepairStep{AfterBackslash{}, ""}
    case value: RepairStep{InsideString{}, controlCharacter(value)}

def transition(mode: RepairMode, +char: Char) -> RepairStep:
  match mode:
    case OutsideString{}: outside(char)
    case InsideString{}: inside(char)
    case AfterBackslash{}: RepairStep{InsideString{}, Bool.pick(String, validEscape(char), "\\" ++ SCon{char, SNil{}}, "\\\\" ++ controlCharacter(char))}

# A deferred backslash lets every transition consume exactly one character.
# The valid-\u case needs no special lookahead: its four hexadecimal digits
# contain neither quotes nor escapes, so normal inside-string steps preserve it.
def repair(chars: String, state: RepairStep, fragments: List<&2, String>) -> String:
  match chars state:
    case SNil{} RepairStep{mode, fragment}: String.join(List.reverse(&2, String, finishRepair(mode) <> fragment <> fragments), "")
    case SCon{char, rest} RepairStep{mode, fragment}: repair(rest, transition(mode, char), fragment <> fragments)

def repairJson(json: String) -> String:
  repair(json, RepairStep{OutsideString{}, ""}, Nil{})

def reparse(changed: Bool, error: Json.ParseError, repaired: String) -> Result<&2, &2, Json.ParseError, V.Value>:
  match changed:
    case False{}: Fail{error}
    case True{}: Json.parse(repaired)

def tryRepaired(result: Result<&2, &2, Json.ParseError, V.Value>, +json: String) -> Result<&2, &2, Json.ParseError, V.Value>:
  match result:
    case Done{value}: Done{value}
    case Fail{error}:
      +repaired = repairJson(json)
      reparse(Bool.not(String.eq(repaired, json)), error, repaired)

def parseJsonWithRepair(+json: String) -> Result<&2, &2, Json.ParseError, V.Value>:
  tryRepaired(Json.parse(json), json)


# The upstream helper may return any successfully decoded JSON value. Its
# empty-object fallback applies to absent/blank input and failed recovery.
def emptyObject() -> V.Value: V.ObjectValue{R.new(V.Value)}

def recovered(result: Result<&2, &2, Partial.Error, V.Value>) -> V.Value:
  match result:
    case Done{V.Null{}}: emptyObject()
    case Done{value}: value
    case Fail{_}: emptyObject()

def recoverRepaired(result: Result<&2, &2, Partial.Error, V.Value>, json: String) -> V.Value:
  match result:
    case Done{V.Null{}}: emptyObject()
    case Done{value}: value
    case Fail{_}: recovered(Partial.parse(repairJson(json)))

def recoverPartial(result: Result<&2, &2, Json.ParseError, V.Value>, +json: String) -> V.Value:
  match result:
    case Done{value}: value
    case Fail{_}: recoverRepaired(Partial.parse(json), json)

def nonblankStreaming(blank: Bool, +json: String) -> V.Value:
  match blank:
    case True{}: emptyObject()
    case False{}: recoverPartial(parseJsonWithRepair(json), json)

def parseStreamingJson(partialJson: Maybe<&2, String>) -> V.Value:
  match partialJson:
    case None{}: emptyObject()
    case Some{+json}: nonblankStreaming(Space.blank(json), json)
