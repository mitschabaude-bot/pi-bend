import Base
import ../packages/ai/src/api/openai-responses-native-render.bend as Render
import ../packages/ai/src/api/openai-responses-native-session-error.bend as E
import ../packages/ai/src/api/openai-responses-configured-acquire.bend as Acquire
import ../packages/ai/src/api/openai-responses-stream.bend as Stream
import ../packages/ai/src/api/openai-responses-stream-error.bend as Format
import ../packages/ai/src/api/openai-responses-reader.bend as Reader
import ../packages/ai/src/api/openai-body-responses-reader.bend as Body
import ../packages/ai/src/api/openai-responses-envelope.bend as Envelope
import ../packages/ai/src/utils/provider-request.bend as Request
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/ai/src/utils/provider-retry-policy.bend as Policy
import ../packages/ai/src/utils/error-body.bend as Diagnostic
import ../packages/runtime/src/http-response-progress.bend as Progress
import ../packages/runtime/src/json-decode.bend as Decode
import ../packages/runtime/src/json-string.bend as Quote
import ../packages/runtime/src/timer-delay.bend as Delay
import ../packages/runtime/src/f64.bend as F

def leaves(fail: Bool) -> Render.Leaves<Unit, Unit, String>:
  match fail:
    case False{}: Render.Leaves{message => Done{message}, _ => Done{"attempt"}, _ => Done{"reader"}, _ => Done{"disposal"}, _ => Done{"release"}}
    case True{}: Render.Leaves{_ => Fail{Diagnostic.NumberFormattingFailure{}}, _ => Fail{Diagnostic.NumberFormattingFailure{}}, _ => Fail{Diagnostic.NumberFormattingFailure{}}, _ => Fail{Diagnostic.NumberFormattingFailure{}}, _ => Fail{Diagnostic.NumberFormattingFailure{}}}

def wrap(depth: Nat, cause: E.Error<Unit, Unit, String>) -> E.Error<Unit, Unit, String>:
  match depth:
    case Zero{}: cause
    case Succ{n}: wrap(n, E.ProcessingFailure{Stream.ReadFailure{E.AcquisitionFailure{Acquire.AcquisitionFailed{Request.ResponseFailure{E.AcquisitionFailure{Acquire.AcquisitionFailed{Request.PayloadFailure{cause}}}, Fail{E.HookFailure{"cleanup"}}}}}}})

def output(value: Format.Formatted()) -> IO(Unit):
  match value:
    case Done{text}: IO.print(Quote.quote(text))
    case Fail{_}: IO.print(Quote.quote("formatting-failure"))

def show(fail: Bool, cause: E.Error<Unit, Unit, String>) -> IO(Unit):
  output(Render.render(Unit, Unit, String, leaves(fail), cause))

def main() -> IO(Unit):
  do IO<Unit>:
    show(False{}, wrap(32n, E.HookFailure{"primary"}))
    show(True{}, wrap(32n, E.HookFailure{"primary"}))
    show(False{}, E.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestFailed{Retry.Provider{Retry.ProviderError{E.HookFailure{"original"}, "metadata", Some{F.fromU32(500)}, Some{"false"}, None{}, None{}}}}}}})
    show(False{}, E.ProcessingFailure{Stream.EmitFailure{E.ProcessingFailure{Stream.ResolveServiceTierFailure{E.ProcessingFailure{Stream.ApplyServiceTierPricingFailure{E.HookFailure{"callback"}}}}}}})
    show(False{}, E.ReaderFailure{Reader.ProtocolFailure{Decode.MissingField{Nil{}}}})
    show(False{}, E.DisposalFailure{Body.ReaderFailure{Reader.ProtocolFailure{Decode.MissingField{Nil{}}}}})
    show(False{}, E.ReleaseFailure{Progress.PrimaryFailure{Progress.MissingHead{}}})
    show(True{}, E.ReaderFailure{Reader.ProtocolFailure{Decode.MissingField{Nil{}}}})
    show(True{}, E.DisposalFailure{Body.ReaderFailure{Reader.ProtocolFailure{Decode.MissingField{Nil{}}}}})
    show(True{}, E.ReleaseFailure{Progress.PrimaryFailure{Progress.MissingHead{}}})
    show(False{}, E.EnvelopeFailure{Envelope.NonFinitePayload{}})
    show(False{}, E.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.RequestAborted{}}}})
    show(False{}, E.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.SleepRejected{Delay.InvalidDuration{F.fromU32(0)}}}}})
    show(False{}, E.AcquisitionFailure{Acquire.AcquisitionFailed{Request.RequestFailure{Retry.DelayRejected{Policy.ServerDelayTooLong{F.fromU32(1001), F.fromU32(1000)}, "provider"}}}})
