import Base
import ../types.bend as T
import ../utils/model-api.bend as Api
import ../../../runtime/src/f64.bend as F

# Outer provider failures stay distinct from caller-selected typed causes.
type Failure<-E: Data> is Data:
  RequestFailure{cause: E}
  StartFailure{cause: E}
  ProcessingFailure{cause: E}
  CleanupFailure{cause: E}
  DeliveryFailure{cause: E}
  RequestAborted{}
  MissingStopReason{}
  OutputFailure{message: String}

type Terminal<-A: Data, -G: Data, -E: Data> is Data:
  Successful{reason: T.DoneReason, message: T.AssistantMessage<A, G>}
  Failed{reason: T.ErrorReason, message: T.AssistantMessage<A, G>, cause: Failure<E>}

# A processing adapter owns resource retirement and returns both causes.
type Processed<-A: Data, -G: Data, -E: Data> is Data:
  Processed{message: T.AssistantMessage<A, G>, failure: Maybe<&2, E>, cleanup: Maybe<&2, E>}

type RunResult<-A: Data, -G: Data, -E: Data> is Data:
  RunResult{terminal: Terminal<A, G, E>, cleanup: Maybe<&2, E>, delivery: Maybe<&2, E>}

def initial(-A: Data, -G: Data, -J: Data, model: T.Model<J>, timestamp: F.F64) -> T.AssistantMessage<A, G>:
  match model:
    case T.Model{id, _, api, provider, _, _, _, _, _, _, _, _, _, _}:
      +zero = F.fromU32(0)
      T.AssistantMessage{Nil{}, Api.name(api), provider, id, None{}, None{}, None{}, None{}, T.Usage{zero, zero, zero, zero, None{}, None{}, zero, T.UsageCost{zero, zero, zero, zero, zero}}, T.Pending{}, None{}, None{}, None{}, None{}, timestamp}

def message(-A: Data, -G: Data, -E: Data, terminal: Terminal<A, G, E>) -> T.AssistantMessage<A, G>:
  match terminal:
    case Successful{_, output}: output
    case Failed{_, output, _}: output

def event(-A: Data, -G: Data, -E: Data, terminal: Terminal<A, G, E>) -> T.AssistantMessageEvent<A, G>:
  match terminal:
    case Successful{reason, output}: T.StreamDone{reason, output}
    case Failed{reason, output, _}: T.StreamError{reason, output}

def errorReason(aborted: Bool) -> T.ErrorReason:
  match aborted:
    case True{}: T.ErrorAborted{}
    case False{}: T.ErrorError{}

def stopReason(aborted: Bool) -> T.StopReason:
  match aborted:
    case True{}: T.Aborted{}
    case False{}: T.Error{}

# All fields other than stopReason and errorMessage are preserved, including
# partial content, usage, provider metadata and the original timestamp.
def withFailure(-A: Data, -G: Data, output: T.AssistantMessage<A, G>, aborted: Bool, detail: String) -> T.AssistantMessage<A, G>:
  match output:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, _, deferred, _, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, stopReason(aborted), deferred, Some{detail}, raw, endTurn, timestamp}

def outputError(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "An unknown error occurred"
    case Some{""}: "An unknown error occurred"
    case Some{text}: text

def check(-E: Data, aborted: Bool, reason: T.StopReason, detail: Maybe<&2, String>) -> Result<&2, &2, Failure<E>, T.DoneReason>:
  match aborted reason:
    case True{} _: Fail{RequestAborted{}}
    case False{} T.Pending{}: Fail{MissingStopReason{}}
    case False{} T.Error{}: Fail{OutputFailure{outputError(detail)}}
    case False{} T.Aborted{}: Fail{OutputFailure{outputError(detail)}}
    case False{} T.Stop{}: Done{T.DoneStop{}}
    case False{} T.Length{}: Done{T.DoneLength{}}
    case False{} T.ToolUse{}: Done{T.DoneToolUse{}}
    case False{} T.Deferred{}: Done{T.DoneDeferred{}}

def validate(-A: Data, -G: Data, -E: Data, output: T.AssistantMessage<A, G>, aborted: Bool) -> Result<&2, &2, Failure<E>, T.DoneReason>:
  match output:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, reason, _, detail, _, _, _}: check(E, aborted, reason, detail)

def describe(-E: Data, render: E -> String, cause: Failure<E>) -> String:
  match cause:
    case RequestFailure{value}: render(value)
    case StartFailure{value}: render(value)
    case ProcessingFailure{value}: render(value)
    case CleanupFailure{value}: render(value)
    case DeliveryFailure{value}: render(value)
    case RequestAborted{}: "Request was aborted"
    case MissingStopReason{}: "OpenAI Responses stream ended without a stop reason"
    case OutputFailure{detail}: detail

def failed(-A: Data, -G: Data, -E: Data, output: T.AssistantMessage<A, G>, +aborted: Bool, render: E -> String, +cause: Failure<E>) -> Terminal<A, G, E>:
  Failed{errorReason(aborted), withFailure(A, G, output, aborted, describe(E, render, cause)), cause}

# Existing failures retain their cause even if the signal was also aborted.
# Cancellation creates its own cause only after otherwise successful work.
def select(-A: Data, -G: Data, -E: Data, +output: T.AssistantMessage<A, G>, +aborted: Bool, render: E -> String, result: Result<&2, &2, Failure<E>, T.DoneReason>) -> Terminal<A, G, E>:
  match result:
    case Done{reason}: Successful{reason, output}
    case Fail{cause}: failed(A, G, E, output, aborted, render, cause)

def complete(-A: Data, -G: Data, -E: Data, +output: T.AssistantMessage<A, G>, +aborted: Bool, render: E -> String, failure: Maybe<&2, Failure<E>>) -> Terminal<A, G, E>:
  match failure:
    case Some{cause}: failed(A, G, E, output, aborted, render, cause)
    case None{}: select(A, G, E, output, aborted, render, validate(A, G, E, output, aborted))

def processingFailure(-E: Data, failure: Maybe<&2, E>, cleanup: Maybe<&2, E>) -> Maybe<&2, Failure<E>>:
  match failure cleanup:
    case Some{cause} _: Some{ProcessingFailure{cause}}
    case None{} Some{cause}: Some{CleanupFailure{cause}}
    case None{} None{}: None{}

# A failed terminal emission cannot leave a successful final result. Preserve
# an existing failure as primary and retain delivery separately in RunResult.
def deliveryFailed(-A: Data, -G: Data, -E: Data, terminal: Terminal<A, G, E>, aborted: Bool, render: E -> String, cause: E) -> Terminal<A, G, E>:
  match terminal:
    case Successful{_, output}: failed(A, G, E, output, aborted, render, DeliveryFailure{cause})
    case Failed{reason, output, primary}: Failed{reason, output, primary}
