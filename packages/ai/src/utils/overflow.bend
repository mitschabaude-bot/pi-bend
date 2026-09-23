import Base
import ../types.bend as T
import ../../../runtime/src/regex.bend as Regex
import ../../../runtime/src/f64.bend as F

# pi `overflow.ts`: whether a finished assistant message means the input
# exceeded the model's context window. Three cases as upstream: provider
# error text, silent overflow (usage above the window on a normal stop) and
# length stops with no output that fill the window.

def overflowPatterns() -> List<&2, String>:
  "prompt is too long" <> "request_too_large" <> "input is too long for requested model" <> "exceeds the context window" <>
  "exceeds (?:the )?(?:model'?s )?maximum context length(?: of [\\d,]+ tokens?|\\s*\\([\\d,]+\\))" <>
  "input token count.*exceeds the maximum" <> "maximum prompt length is \\d+" <> "reduce the length of the messages" <>
  "maximum context length is \\d+ tokens" <> "exceeds (?:the )?maximum allowed input length of [\\d,]+ tokens?" <>
  "input \\(\\d+ tokens\\) is longer than the model'?s context length \\(\\d+ tokens\\)" <> "exceeds the limit of \\d+" <>
  "exceeds the available context size" <> "greater than the context length" <> "context window exceeds limit" <>
  "exceeded model token limit" <> "too large for model with \\d+ maximum context length" <>
  "prompt has [\\d,]+ tokens?, but the configured context size is [\\d,]+ tokens?" <> "model_context_window_exceeded" <>
  "prompt too long; exceeded (?:max )?context length" <> "range of input length should be" <> "context[_ ]length[_ ]exceeded" <>
  "too many tokens" <> "token limit exceeded" <> "^4(?:00|13)\\s*(?:status code)?\\s*\\(no body\\)" <> Nil{}

# Throttling and server errors are excluded even when they also match above.
def nonOverflowPatterns() -> List<&2, String>:
  "^(Throttling error|Service unavailable):" <> "rate limit" <> "too many requests" <> Nil{}

def matched(compiled: Result<&2, &2, Regex.Error, Regex.Regex>, text: String) -> Bool:
  match compiled:
    case Done{regex}: Regex.isMatch(regex, text)
    case Fail{_}: False{}

def matchesAny(patterns: List<&2, String>, +text: String) -> Bool:
  match patterns:
    case Nil{}: False{}
    case pattern <> rest: Bool.pick(Unit -> Bool, matched(Regex.compile(pattern, True{}), text), _ => True{}, _ => matchesAny(rest, text))(Unit{})

def overflowText(+text: String) -> Bool:
  Bool.pick(Unit -> Bool, Bool.or(String.eq(text, ""), matchesAny(nonOverflowPatterns(), text)), _ => False{}, _ => matchesAny(overflowPatterns(), text))(Unit{})

def overflowError(stopReason: T.StopReason, errorMessage: Maybe<&2, String>) -> Bool:
  match stopReason errorMessage:
    case T.Error{} Some{text}: overflowText(text)
    case _ _: False{}

def inputTokens(usage: T.Usage) -> F64:
  match usage:
    case T.Usage{input, _, cacheRead, _, _, _, _, _}: F.add(input, cacheRead)

def outputTokens(usage: T.Usage) -> F64:
  match usage:
    case T.Usage{_, output, _, _, _, _, _, _}: output

def isZero(value: F64) -> Bool: F.isEqual(F.compare(value, F.fromU32(0)))

# A zero or unknown window disables the usage checks, as upstream's falsy test.
def usageOverflow(+contextWindow: F64, stopReason: T.StopReason, +usage: T.Usage) -> Bool:
  match stopReason:
    case T.Stop{}: Bool.and(Bool.not(isZero(contextWindow)), F.isGreater(F.compare(inputTokens(usage), contextWindow)))
    case T.Length{}: Bool.and(Bool.not(isZero(contextWindow)), Bool.and(isZero(outputTokens(usage)), F.isAtLeast(F.compare(inputTokens(usage), F.multiply(contextWindow, F.divide(F.fromU32(99), F.fromU32(100)))))))
    case _: False{}

def isContextOverflow(-Arguments: Data, -DiagnosticDetails: Data, message: T.AssistantMessage<Arguments, DiagnosticDetails>, contextWindow: F64) -> Bool:
  match message:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, usage, +stopReason, _, errorMessage, _, _, _}:
      Bool.or(overflowError(stopReason, errorMessage), usageOverflow(contextWindow, stopReason, usage))

# A length stop below the caller's intended output limit may be recoverable
# by one bounded compact-and-retry attempt.
def isRecoverableLength(-Arguments: Data, -DiagnosticDetails: Data, message: T.AssistantMessage<Arguments, DiagnosticDetails>, +desiredMaxOutput: F64) -> Bool:
  match message:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, usage, T.Length{}, _, _, _, _, _}:
      Bool.and(F.isGreater(F.compare(desiredMaxOutput, F.fromU32(0))), Bool.not(F.isAtLeast(F.compare(outputTokens(usage), desiredMaxOutput))))
    case _: False{}
