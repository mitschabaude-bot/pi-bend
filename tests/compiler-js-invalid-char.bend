import Base

# An eagerly evaluated Bool.pick branch builds Chr from an underflowed U32 that
# the other branch is selected over. See docs/bend-issues.md (BEND-048).
def unitOf(+code: U32) -> String:
  Bool.pick(String, U32.is_gt(code, 65535), SCon{Chr{(55296 + (code - 65536) / 1024 : U32)}, SNil{}}, SCon{Chr{code}, SNil{}})

def main() -> IO(Unit): IO.print(unitOf(97))
