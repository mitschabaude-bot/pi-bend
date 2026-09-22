import Base
import ./compiler-def-named-binder-lib.bend as Lib

# A pattern binder that shares its name with a def of the *same module* is
# rejected as a pattern. The library type-checks alone; importing it makes
# the binder `text` resolve to the namespaced def `lib.text`.
def main() -> IO(Unit):
  IO.print(Lib.render(Lib.Wrapped{"ok"}))
