import Base
import ../packages/runtime/src/glob.bend as Glob

# A wildcard accepts every finite string; the matcher's finite work budget
# must not turn a valid match into a rejection.
law star_matches_every_string:
  for +text: String
  {Glob.matches(Glob.Pattern{Glob.Star{} <> Nil{}}, text) == True{} : Bool}
