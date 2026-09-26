import Base
import ../../src/types.bend as T
import ../../../ai/src/types.bend as Ai
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/number-string.bend as Number
import ../../../runtime/src/record.bend as Record
import ../../../runtime/src/schema-value.bend as Schema

# pi-mono f07218c4d packages/agent/test/utils/calculate.ts: the calculator
# tool of the agent tests. Upstream evaluates the expression as JavaScript
# (`new Function("return " + expression)`); the port evaluates the arithmetic
# subset the tests use (decimal literals, prefix + and -, binary + - * / %,
# parentheses) with JavaScript's number semantics and spelling. Other input
# (identifiers, `**`, ...) fails as a syntax error with the port's own
# messages, since engines word theirs differently; `--` and `++` read as two
# prefix operators, not JavaScript's update operators. Bend has no mutual
# recursion, so the grammar is evaluated by operator precedence over explicit
# stacks.

# Evaluation
# ----------
type Operator is Data:
  Add{}
  Subtract{}
  Multiply{}
  Divide{}
  Remainder{}
  Negate{}
  Plus{}
  Open{}

def precedence(operator: Operator) -> U32:
  match operator:
    case Add{}: 1
    case Subtract{}: 1
    case Multiply{}: 2
    case Divide{}: 2
    case Remainder{}: 2
    case Negate{}: 3
    case Plus{}: 3
    case Open{}: 0

def binary(operator: Operator, left: F64, right: F64) -> F64:
  match operator:
    case Add{}: F.add(left, right)
    case Subtract{}: F.subtract(left, right)
    case Multiply{}: F.multiply(left, right)
    case Divide{}: F.divide(left, right)
    case _: F.remainder(left, right)

type Stacks is Data:
  Stacks{operators: List<&2, Operator>, values: List<&2, F64>}

def Reduced() -> Data: Result<&2, &2, String, Stacks>
def Evaluated() -> Data: Result<&2, &2, String, F64>

# Pops the operators binding at least as tightly as `limit`: binary operators
# are left-associative, and prefix operators bind tighter than any binary
# operator. An open parenthesis stops the reduction.
def reduce(+limit: U32, operators: List<&2, Operator>, values: List<&2, F64>) -> Reduced():
  match operators values:
    case Nil{} values: Done{Stacks{Nil{}, values}}
    case Open{} <> rest values: Done{Stacks{Open{} <> rest, values}}
    case Negate{} <> rest value <> values: reduce(limit, rest, F.negate(value) <> values)
    case Plus{} <> rest value <> values: reduce(limit, rest, value <> values)
    case +operator <> +rest +right <> +left <> +values:
      Bool.pick(Unit -> Reduced(), U32.is_ge(precedence(operator), limit), _ => reduce(limit, rest, binary(operator, left, right) <> values), _ => Done{Stacks{operator <> rest, right <> left <> values}})(Unit{})
    case _ _: Fail{"Unexpected end of input"}

def reduced(+limit: U32, stacks: Stacks) -> Reduced():
  match stacks:
    case Stacks{operators, values}: reduce(limit, operators, values)

def andThen(result: Reduced(), next: Stacks -> Evaluated()) -> Evaluated():
  match result:
    case Fail{message}: Fail{message}
    case Done{stacks}: next(stacks)

def pushed(operator: Operator, stacks: Stacks) -> Stacks:
  match stacks:
    case Stacks{operators, values}: Stacks{operator <> operators, values}

def closeParenthesis(stacks: Stacks, next: Stacks -> Evaluated()) -> Evaluated():
  match stacks:
    case Stacks{Open{} <> rest, values}: next(Stacks{rest, values})
    case _: Fail{"Unexpected token ')'"}

def finished(result: Reduced()) -> Evaluated():
  match result:
    case Fail{message}: Fail{message}
    case Done{Stacks{Nil{}, value <> Nil{}}}: Done{value}
    case Done{_}: Fail{"Unexpected end of input"}

# Tokens
# ------
def numberChar(+code: U32) -> Bool:
  (U32.is_ge(code, 48) && U32.is_le(code, 57)) || U32.is_eq(code, 46)

def digitsFrom(text: String, +token: String) -> String & String:
  match text:
    case SCon{Chr{+code}, +rest}: Bool.pick(Unit -> String & String, numberChar(code), _ => digitsFrom(rest, SCon{Chr{code}, token}), _ => (String.reverse(token), SCon{Chr{code}, rest}))(Unit{})
    case SNil{}: (String.reverse(token), "")

def signedExponent(text: String, token: String) -> String & String:
  match text:
    case SCon{'+', rest}: digitsFrom(rest, SCon{'+', token})
    case SCon{'-', rest}: digitsFrom(rest, SCon{'-', token})
    case other: digitsFrom(other, token)

# A numeric literal: digits and dots, then an optional exponent.
def numberToken(text: String, +token: String) -> String & String:
  match text:
    case SCon{'e', rest}: signedExponent(rest, SCon{'e', token})
    case SCon{'E', rest}: signedExponent(rest, SCon{'E', token})
    case SCon{Chr{+code}, +rest}: Bool.pick(Unit -> String & String, numberChar(code), _ => numberToken(rest, SCon{Chr{code}, token}), _ => (String.reverse(token), SCon{Chr{code}, rest}))(Unit{})
    case SNil{}: (String.reverse(token), "")

def unexpected(text: String) -> String:
  match text:
    case SNil{}: "Unexpected end of input"
    case SCon{char, _}: "Unexpected token '" ++ SCon{char, ""} ++ "'"

def literal(+token: String, +rest: String, next: F64 -> String -> Evaluated()) -> Evaluated():
  +value = Number.toNumber(token)
  Bool.pick(Unit -> Evaluated(), String.is_empty(token), _ => Fail{unexpected(rest)}, _ => Bool.pick(Unit -> Evaluated(), F.isNaN(value), _ => Fail{"Invalid or unexpected token"}, _ => next(value, rest))(Unit{}))(Unit{})

def operand(pair: String & String, next: F64 -> String -> Evaluated()) -> Evaluated():
  match pair:
    case (token, rest): literal(token, rest, next)

def binaryOperator(char: Char) -> Maybe<&2, Operator>:
  match char:
    case '+': Some{Add{}}
    case '-': Some{Subtract{}}
    case '*': Some{Multiply{}}
    case '/': Some{Divide{}}
    case '%': Some{Remainder{}}
    case _: None{}

def infix(operator: Maybe<&2, Operator>, text: String, stacks: Stacks, next: Stacks -> Evaluated()) -> Evaluated():
  match operator:
    case None{}: Fail{unexpected(text)}
    case Some{+chosen}: andThen(reduced(precedence(chosen), stacks), reduced => next(pushed(chosen, reduced)))

def infixAt(+char: Char, +rest: String, stacks: Stacks, next: String -> Stacks -> Evaluated()) -> Evaluated():
  infix(binaryOperator(char), SCon{char, rest}, stacks, next(rest))

def withValue(value: F64, stacks: Stacks) -> Stacks:
  match stacks:
    case Stacks{operators, values}: Stacks{operators, value <> values}

# `expecting` is true where an operand must follow.
@unsafe def scan(text: String, +expecting: Bool, stacks: Stacks) -> Evaluated():
  match text expecting:
    case SNil{} True{}: Fail{"Unexpected end of input"}
    case SNil{} False{}: finished(reduced(0, stacks))
    case SCon{' ', rest} _: scan(rest, expecting, stacks)
    case SCon{'\t', rest} _: scan(rest, expecting, stacks)
    case SCon{'\n', rest} _: scan(rest, expecting, stacks)
    case SCon{'\r', rest} _: scan(rest, expecting, stacks)
    case SCon{'(', rest} True{}: scan(rest, True{}, pushed(Open{}, stacks))
    case SCon{'-', rest} True{}: scan(rest, True{}, pushed(Negate{}, stacks))
    case SCon{'+', rest} True{}: scan(rest, True{}, pushed(Plus{}, stacks))
    case SCon{')', rest} False{}: andThen(reduced(0, stacks), popped => closeParenthesis(popped, closed => scan(rest, False{}, closed)))
    case SCon{char, rest} True{}: operand(numberToken(SCon{char, rest}, ""), value => remaining => scan(remaining, False{}, withValue(value, stacks)))
    case SCon{char, rest} False{}: infixAt(char, rest, stacks, remaining => next => scan(remaining, True{}, next))

def evaluate(expression: String) -> Evaluated(): scan(expression, True{}, Stacks{Nil{}, Nil{}})

# Tool
# ----
def resultText(+expression: String, value: F64) -> String:
  expression ++ " = " ++ Maybe.default(&2, String, F.toDecimal(value), "NaN")

def calculateResult(usage: Maybe<&2, Ai.Usage>, +expression: String, result: Evaluated()) -> Result<&2, &2, String, T.AgentToolResult<Unit>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{value}: Done{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{resultText(expression, value), None{}}} <> Nil{}, None{}, usage, None{}}}

# upstream calculate(expression): the text result, or the thrown message.
def calculate(+expression: String) -> Result<&2, &2, String, T.AgentToolResult<Unit>>:
  calculateResult(None{}, expression, evaluate(expression))

def textValue(value: Maybe<&2, Schema.Value>) -> Maybe<&2, String>:
  match value:
    case Some{Schema.Text{text}}: Some{text}
    case _: None{}

def expressionOf(params: Schema.Value) -> Maybe<&2, String>:
  match params:
    case Schema.ObjectValue{+fields}: textValue(Record.get(Schema.Value, fields, "expression"))
    case _: None{}

def executeExpression(usage: Maybe<&2, Ai.Usage>, expression: Maybe<&2, String>) -> Result<&2, &2, String, T.AgentToolResult<Unit>>:
  match expression:
    case None{}: Fail{"expression is not a string"}
    case Some{+text}: calculateResult(usage, text, evaluate(text))

def executeWith(usage: Maybe<&2, Ai.Usage>, input: T.ToolExecutionInput<Unit>) -> IO(Result<&2, &2, String, T.AgentToolResult<Unit>>):
  match input:
    case T.ToolExecutionInput{_, params, _, _}: IO.pure(Result<&2, &2, String, T.AgentToolResult<Unit>>, executeExpression(usage, expressionOf(params)))

def calculateSchema() -> Schema.Value:
  Schema.ObjectValue{Record.Record{
    Record.Property{"type", Schema.Text{"object"}} <>
    Record.Property{"properties", Schema.ObjectValue{Record.Record{
      Record.Property{"expression", Schema.ObjectValue{Record.Record{Record.Property{"type", Schema.Text{"string"}} <> Record.Property{"description", Schema.Text{"The mathematical expression to evaluate"}} <> Nil{}}}} <> Nil{}}}} <>
    Record.Property{"required", Schema.ArrayValue{Schema.Text{"expression"} <> Nil{}}} <> Nil{}}}

def Tool() -> Data: T.AgentTool<Unit, String>
def Execute() -> Data: C.Callback<T.ToolExecutionInput<Unit>, Result<&2, &2, String, T.AgentToolResult<Unit>>>

def toolWith(execute: Execute()) -> Tool():
  T.AgentTool{"calculate", "Evaluate mathematical expressions", calculateSchema(), None{}, "Calculator", None{}, execute, None{}, None{}}

# upstream createCalculateToolWithUsage: results also report `usage`. The
# tool owns its execute callback; release it with disposeTool.
def createCalculateToolWithUsage(usage: Maybe<&2, Ai.Usage>) -> IO(Tool()):
  do IO<Tool()>:
    execute : Execute() <- C.create(~Maybe<&2, Ai.Usage>, ~T.ToolExecutionInput<Unit>, ~Result<&2, &2, String, T.AgentToolResult<Unit>>, ~executeWith, usage)
    return toolWith(execute)

# upstream calculateTool.
def calculateTool() -> IO(Tool()): createCalculateToolWithUsage(None{})

def disposeTool(tool: Tool()) -> IO(Unit):
  match tool:
    case T.AgentTool{_, _, _, _, _, _, execute, _, _}: C.dispose(T.ToolExecutionInput<Unit>, Result<&2, &2, String, T.AgentToolResult<Unit>>, execute)
