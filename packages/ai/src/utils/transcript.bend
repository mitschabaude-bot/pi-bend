import Base
import ../types.bend as T
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/f64.bend as Number

# Initial normalization from transcript.ts. Replay and declaration comparison
# remain separate pending operations, not implicit changes to this constructor.
def promptValue(prompt: Maybe<&2, String>) -> String:
  match prompt:
    case None{}: ""
    case Some{value}: value

def nonEmptyTools(-P: Data, tools: Maybe<&2, List<&2, Ref.Ref<T.Tool<P>>>>) -> Maybe<&2, List<&2, Ref.Ref<T.Tool<P>>>>:
  match tools:
    case None{}: None{}
    case Some{Nil{}}: None{}
    case Some{head <> tail}: Some{head <> tail}

def hasTools(-P: Data, tools: Maybe<&2, List<&2, Ref.Ref<T.Tool<P>>>>) -> Bool:
  match tools:
    case None{}: False{}
    case Some{_}: True{}

def createInitial(-P: Data, needed: Bool, prompt: String, tools: Maybe<&2, List<&2, Ref.Ref<T.Tool<P>>>>) -> IO(Maybe<&2, Ref.Ref<T.SystemMessage<P>>>):
  match needed:
    case False{}: IO.pure(Maybe<&2, Ref.Ref<T.SystemMessage<P>>>, None{})
    case True{}:
      do IO<Maybe<&2, Ref.Ref<T.SystemMessage<P>>>>:
        value : Ref.Ref<T.SystemMessage<P>> <- Ref.new(T.SystemMessage<P>, T.SystemMessage{T.SystemText{prompt}, None{}, tools, None{}, Number.fromU32(0)})
        return Some{value}

def createInitialSystemMessage(-P: Data, systemPrompt: Maybe<&2, String>, tools: Maybe<&2, List<&2, Ref.Ref<T.Tool<P>>>>) -> IO(Maybe<&2, Ref.Ref<T.SystemMessage<P>>>):
  +prompt = promptValue(systemPrompt)
  +available = nonEmptyTools(P, tools)
  createInitial(P, Bool.not(String.is_empty(prompt)) || hasTools(P, available), prompt, available)

def prependInitial(-P: Data, -A: Data, -G: Data, -H: Data, initial: Maybe<&2, Ref.Ref<T.SystemMessage<P>>>, messages: List<&2, T.Message<P, A, G, H>>) -> T.TranscriptContext<P, A, G, H>:
  match initial:
    case None{}: T.TranscriptContext{messages}
    case Some{value}: T.TranscriptContext{T.System{value} <> messages}

def normalizeContext(-P: Data, -A: Data, -G: Data, -H: Data, context: T.Context<P, A, G, H>) -> IO(T.TranscriptContext<P, A, G, H>):
  match context:
    case T.Context{systemPrompt, messages, tools}:
      do IO<T.TranscriptContext<P, A, G, H>>:
        initial : Maybe<&2, Ref.Ref<T.SystemMessage<P>>> <- createInitialSystemMessage(P, systemPrompt, tools)
        return prependInitial(P, A, G, H, initial, messages)

def getInitialSystemMessage(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>) -> Maybe<&2, Ref.Ref<T.SystemMessage<P>>>:
  match messages:
    case T.System{value} <> _: Some{value}
    case _: None{}

def withoutInitialSystemMessage(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>) -> List<&2, T.Message<P, A, G, H>>:
  match messages:
    case T.System{_} <> tail: tail
    case messages: messages
