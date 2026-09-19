import Base

# BEND-012: this checks directly but importing it resolves the field binder as
# the module's global number function. Retained reproducer, not a passing test.
type Sample is Data:
  Sample{value: U32}

def number(value: Sample) -> U32:
  match value:
    case Sample{number}: number
