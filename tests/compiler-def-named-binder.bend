import Base
import ./compiler-def-named-binder-lib.bend as Lib

# A pattern binder that shares its name with a def of the same module was
# rejected once the module was imported: the binder `text` resolved to the
# namespaced def `lib.text` (BEND-032, fixed by
# patches/bend-import-binders.patch). Expected: ok.
def main() -> IO(Unit):
  IO.print(Lib.render(Lib.Wrapped{"ok"}))
