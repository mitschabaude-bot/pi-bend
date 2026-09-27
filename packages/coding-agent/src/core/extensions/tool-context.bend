import Base
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/callback.bend as C

# The built-in tools' view of their extension context (upstream
# wrapToolDefinition passes the ExtensionContext to execute; the built-in
# tools read its cwd, model, session identity and thinking level). The view
# is separate from context.bend, whose ExtensionContext exposes the session
# (ctx.sessionManager) and so depends on the tools' result types.

type ContextView is Data:
  ContextView{cwd: String, model: Maybe<&2, Ai.Model<Ai.JsonValue>>, sessionId: String, sessionFile: Maybe<&2, String>, thinkingLevel: Ai.ModelThinkingLevel}

# Tools are created with their runner's context reader, or without one
# (upstream's missing ctxFactory); `create` is the latter. The runner owns
# the reader. It answers None before a session binds the runner.
def ContextSource() -> Data: Maybe<&2, C.Callback<Unit, Maybe<&2, ContextView>>>

def create() -> IO(ContextSource()): IO.pure(ContextSource(), None{})

def current(source: ContextSource()) -> IO(Maybe<&2, ContextView>):
  match source:
    case None{}: IO.pure(Maybe<&2, ContextView>, None{})
    case Some{reader}: C.call(Unit, Maybe<&2, ContextView>, reader, Unit{})

def cwdOf(context: Maybe<&2, ContextView>) -> Maybe<&2, String>:
  match context:
    case None{}: None{}
    case Some{ContextView{directory, _, _, _, _}}: Some{directory}

# upstream `ctx?.cwd || cwd`
def cwdOr(context: Maybe<&2, ContextView>, +fallback: String) -> String:
  match context:
    case Some{ContextView{SCon{first, rest}, _, _, _, _}}: SCon{first, rest}
    case _: fallback
