import Base
import ../core/extensions/types.bend as T
import ../../../runtime/src/callback.bend as C
import ../../examples/extensions/subagent/index.bend as Subagent

# upstream src/extensions/index.ts: the extensions built into pi, loaded as
# named inline factories before any user extension. The only upstream
# built-in, llama.cpp, is excluded by docs/scope-decisions.md.
def builtInExtensions() -> IO(List<&2, T.InlineExtension>):
  IO.pure(List<&2, T.InlineExtension>, Nil{})

# Native extensions are linked when pi-bend is built. CLI names select from
# this registry; an unknown name is reported instead of silently ignored.
def selected(names: List<&2, String>) -> IO(List<&2, T.InlineExtension>):
  match names:
    case Nil{}: IO.pure(List<&2, T.InlineExtension>, Nil{})
    case name <> rest:
      match name:
        case "subagent":
          do IO<List<&2, T.InlineExtension>>:
            factory : T.ExtensionFactory() <- C.create(~Unit, ~T.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(_ => api => Subagent.subagentExtension(api)), Unit{})
            others : List<&2, T.InlineExtension> <- selected(rest)
            return T.InlineExtension{"subagent", factory, False{}} <> others
        case _: selected(rest)

def unlinked(names: List<&2, String>) -> List<&2, T.LoadError>:
  match names:
    case Nil{}: Nil{}
    case name <> rest:
      match name:
        case "subagent": unlinked(rest)
        case _: T.LoadError{name, "Native extension is not linked into this pi-bend build"} <> unlinked(rest)
