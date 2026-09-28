import Base
import ../core/extensions/types.bend as T
import ../../examples/extensions/subagent/index.bend as Subagent

# upstream src/extensions/index.ts: the extensions built into pi, loaded as
# named inline factories before any user extension. The llama.cpp extension
# (`{ name: "llama.cpp", factory: llamaExtension, hidden: true }`) is not
# ported yet, so the list is empty.
def builtInExtensions() -> List<&1, T.InlineExtension>: Nil{}

# Native extensions are linked when pi-bend is built. CLI names select from
# this registry; an unknown name is reported instead of silently ignored.
def selected(names: List<&2, String>) -> List<&1, T.InlineExtension>:
  match names:
    case Nil{}: Nil{}
    case name <> rest:
      match name:
        case "subagent": T.InlineExtension{"subagent", api => Subagent.subagentExtension(api), False{}} <> selected(rest)
        case _: selected(rest)

def unlinked(names: List<&2, String>) -> List<&2, T.LoadError>:
  match names:
    case Nil{}: Nil{}
    case name <> rest:
      match name:
        case "subagent": unlinked(rest)
        case _: T.LoadError{name, "Native extension is not linked into this pi-bend build"} <> unlinked(rest)
