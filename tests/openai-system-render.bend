import Base
import ../packages/ai/src/api/openai-responses-system-render.bend as Render
import ../packages/ai/src/api/openai-responses-system-error.bend as E
import ../packages/ai/src/api/openai-responses-native-render.bend as Native
import ../packages/ai/src/api/openai-responses-native-session-error.bend as Inner
import ../packages/ai/src/api/openai-responses-cleartext-system-runtime.bend as System
import ../packages/ai/src/api/openai-responses-cleartext-runtime.bend as Runtime
import ../packages/ai/src/api/openai-responses-stream.bend as Stream
import ../packages/ai/src/api/openai-responses-stream-error.bend as Format
import ../packages/ai/src/api/openai-responses-reader.bend as Reader
import ../packages/ai/src/api/openai-body-responses-reader.bend as Body
import ../packages/ai/src/utils/provider-owned-acquire.bend as Owned
import ../packages/ai/src/utils/error-body.bend as Diagnostic
import ../packages/runtime/src/random-seed.bend as Seed
import ../packages/runtime/src/json-decode.bend as Decode
import ../packages/runtime/src/json-string.bend as Quote

def leaves(fail: Bool) -> Native.Leaves<Unit, System.SourceError(), String>:
  match fail:
    case False{}: Native.Leaves{message => Done{message}, _ => Done{"attempt"}, _ => Done{"reader"}, _ => Done{"disposal"}, _ => Done{"release"}}
    case True{}: Native.Leaves{_ => Fail{Diagnostic.NumberFormattingFailure{}}, _ => Fail{Diagnostic.NumberFormattingFailure{}}, _ => Fail{Diagnostic.NumberFormattingFailure{}}, _ => Fail{Diagnostic.NumberFormattingFailure{}}, _ => Fail{Diagnostic.NumberFormattingFailure{}}}

def initialize(fail: Bool, cause: System.Error) -> Format.Formatted():
  match fail cause:
    case True{} _: Fail{Diagnostic.NumberFormattingFailure{}}
    case False{} System.InitializationFailure{Runtime.RetryFailure{Seed.SourceFailure{_, message}}}: Done{message}
    case False{} _: Done{"unexpected initialization cause"}

def wrap(depth: Nat, cause: E.Error<Unit, String>) -> E.Error<Unit, String>:
  match depth:
    case Zero{}: cause
    case Succ{n}: wrap(n, E.ProcessingFailure{Stream.ReadFailure{E.ProcessingFailure{Stream.EmitFailure{E.ProcessingFailure{Stream.ResolveServiceTierFailure{E.ProcessingFailure{Stream.ApplyServiceTierPricingFailure{cause}}}}}}}})

def output(value: Format.Formatted()) -> IO(Unit):
  match value:
    case Done{text}: IO.print(Quote.quote(text))
    case Fail{_}: IO.print(Quote.quote("formatting-failure"))

def show(+fail: Bool, cause: E.Error<Unit, String>) -> IO(Unit):
  output(Render.render(Unit, String, leaves(fail), initialize(fail), cause))

def initial() -> E.Error<Unit, String>:
  E.AcquisitionFailure{Owned.InitializationFailure{System.InitializationFailure{Runtime.RetryFailure{Seed.SourceFailure{5, "entropy source failed"}}}}}

def main() -> IO(Unit):
  do IO<Unit>:
    show(False{}, wrap(24n, initial()))
    show(True{}, wrap(24n, initial()))
    show(False{}, wrap(24n, E.AcquisitionFailure{Owned.AcquisitionFailure{Inner.HookFailure{"primary"}}}))
    show(True{}, wrap(24n, E.AcquisitionFailure{Owned.AcquisitionFailure{Inner.HookFailure{"primary"}}}))
    show(False{}, E.ReleaseFailure{Inner.HookFailure{"release cause"}})
    show(True{}, E.ReleaseFailure{Inner.HookFailure{"release cause"}})
    show(False{}, E.ReaderFailure{Reader.ProtocolFailure{Decode.MissingField{Nil{}}}})
    show(False{}, E.DisposalFailure{Body.ReaderFailure{Reader.ProtocolFailure{Decode.MissingField{Nil{}}}}})
    show(True{}, E.ReaderFailure{Reader.ProtocolFailure{Decode.MissingField{Nil{}}}})
    show(True{}, E.DisposalFailure{Body.ReaderFailure{Reader.ProtocolFailure{Decode.MissingField{Nil{}}}}})
    output(Render.format(Unit, String, leaves(False{}), initial()))
    output(Render.format(Unit, String, leaves(False{}), wrap(24n, initial())))
