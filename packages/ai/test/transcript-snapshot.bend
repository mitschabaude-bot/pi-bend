import Base
import ../src/types.bend as T
import ../src/utils/transcript.bend as Transcript
import ../../runtime/src/ref.bend as R

# Value snapshots for the original field/order assertions. Every adapter calls
# production normalization/collapse/resolve and releases only its array cells.
# Shared-array identity and mutation are tested separately against production.
type Context<-P: Data, -A: Data, -G: Data, -H: Data> is Data:
  Context{systemPrompt: Maybe<&2, String>, messages: List<&2, T.Message<P, A, G, H>>, tools: Maybe<&2, List<&2, R.Ref<T.Tool<P>>>>}
type TranscriptContext<-P: Data, -A: Data, -G: Data, -H: Data> is Data:
  TranscriptContext{messages: List<&2, T.Message<P, A, G, H>>}

def disposeOriginal(-P: Data, -A: Data, -G: Data, -H: Data, same: Bool, original: R.Ref<List<&2, T.Message<P, A, G, H>>>) -> IO(Unit):
  match same:
    case True{}: IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        old : List<&2, T.Message<P, A, G, H>> <- R.dispose(List<&2, T.Message<P, A, G, H>>, original)
        return Unit{}

def snapshot(-P: Data, -A: Data, -G: Data, -H: Data, +original: R.Ref<List<&2, T.Message<P, A, G, H>>>, context: T.TranscriptContext<P, A, G, H>) -> IO(TranscriptContext<P, A, G, H>):
  match context:
    case T.TranscriptContext{+messages}:
      do IO<TranscriptContext<P, A, G, H>>:
        same : Bool = R.same(List<&2, T.Message<P, A, G, H>>, original, messages)
        values : List<&2, T.Message<P, A, G, H>> <- R.dispose(List<&2, T.Message<P, A, G, H>>, messages)
        disposeOriginal(P, A, G, H, same, original)
        return TranscriptContext{values}

def normalizeContext(-P: Data, -A: Data, -G: Data, -H: Data, context: Context<P, A, G, H>) -> IO(TranscriptContext<P, A, G, H>):
  match context:
    case Context{prompt, messages, tools}:
      do IO<TranscriptContext<P, A, G, H>>:
        +input : R.Ref<List<&2, T.Message<P, A, G, H>>> <- R.new(List<&2, T.Message<P, A, G, H>>, messages)
        result : T.TranscriptContext<P, A, G, H> <- Transcript.normalizeContext(P, A, G, H, T.Context{prompt, input, tools})
        snapshot(P, A, G, H, input, result)

def collapseSystemMessages(-P: Data, -A: Data, -G: Data, -H: Data, context: TranscriptContext<P, A, G, H>) -> IO(TranscriptContext<P, A, G, H>):
  match context:
    case TranscriptContext{messages}:
      do IO<TranscriptContext<P, A, G, H>>:
        +input : R.Ref<List<&2, T.Message<P, A, G, H>>> <- R.new(List<&2, T.Message<P, A, G, H>>, messages)
        result : T.TranscriptContext<P, A, G, H> <- Transcript.collapseSystemMessages(P, A, G, H, T.TranscriptContext{input})
        snapshot(P, A, G, H, input, result)

def resolveTranscript(-P: Data, -A: Data, -G: Data, -H: Data, context: TranscriptContext<P, A, G, H>, supports: Maybe<&2, Bool>) -> IO(TranscriptContext<P, A, G, H>):
  match context:
    case TranscriptContext{messages}:
      do IO<TranscriptContext<P, A, G, H>>:
        +input : R.Ref<List<&2, T.Message<P, A, G, H>>> <- R.new(List<&2, T.Message<P, A, G, H>>, messages)
        result : T.TranscriptContext<P, A, G, H> <- Transcript.resolveTranscript(P, A, G, H, T.TranscriptContext{input}, supports)
        snapshot(P, A, G, H, input, result)
