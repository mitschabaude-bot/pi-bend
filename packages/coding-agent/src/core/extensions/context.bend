import Base
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/ref.bend as R

# The part of upstream's ExtensionContext the built-in tools read: the
# session's cwd, model, identity and thinking level at the time of the call.
type ExtensionContext is Data:
  ExtensionContext{cwd: String, model: Maybe<&2, Ai.Model<Ai.JsonValue>>, sessionId: String, sessionFile: Maybe<&2, String>, thinkingLevel: Ai.ModelThinkingLevel}

def ContextFactory() -> Data: C.Callback<Unit, ExtensionContext>

# upstream wrapToolDefinition(definition, ctxFactory): tools are created before
# the session, so they share a source the session binds its factory to. An
# unbound source is upstream's missing ctx: tools use their own cwd.
def ContextSource() -> Data: R.Ref<Maybe<&2, ContextFactory()>>

def create() -> IO(ContextSource()): R.new(Maybe<&2, ContextFactory()>, None{})

def bind(source: ContextSource(), factory: Maybe<&2, ContextFactory()>) -> IO(Unit):
  R.write(Maybe<&2, ContextFactory()>, source, factory)

def contextFrom(factory: Maybe<&2, ContextFactory()>) -> IO(Maybe<&2, ExtensionContext>):
  match factory:
    case None{}: IO.pure(Maybe<&2, ExtensionContext>, None{})
    case Some{make}:
      do IO<Maybe<&2, ExtensionContext>>:
        context : ExtensionContext <- C.call(Unit, ExtensionContext, make, Unit{})
        return Some{context}

def current(source: ContextSource()) -> IO(Maybe<&2, ExtensionContext>):
  do IO<Maybe<&2, ExtensionContext>>:
    factory : Maybe<&2, ContextFactory()> <- R.read(Maybe<&2, ContextFactory()>, source)
    contextFrom(factory)

def dispose(source: ContextSource()) -> IO(Unit):
  do IO<Unit>:
    released : Maybe<&2, ContextFactory()> <- R.dispose(Maybe<&2, ContextFactory()>, source)
    return Unit{}

def cwdOf(context: Maybe<&2, ExtensionContext>) -> Maybe<&2, String>:
  match context:
    case None{}: None{}
    case Some{ExtensionContext{cwd, _, _, _, _}}: Some{cwd}

# upstream `ctx?.cwd || cwd`
def cwdOr(context: Maybe<&2, ExtensionContext>, +fallback: String) -> String:
  match context:
    case Some{ExtensionContext{SCon{first, rest}, _, _, _, _}}: SCon{first, rest}
    case _: fallback
