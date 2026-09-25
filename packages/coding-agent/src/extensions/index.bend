import Base
import ../core/extensions/types.bend as T

# upstream src/extensions/index.ts: the extensions built into pi, loaded as
# named inline factories before any user extension. The llama.cpp extension
# (`{ name: "llama.cpp", factory: llamaExtension, hidden: true }`) is not
# ported yet, so the list is empty.
def builtInExtensions() -> List<&1, T.InlineExtension>: Nil{}
