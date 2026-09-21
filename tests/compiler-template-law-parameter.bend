import Base

def identityTemplate(~A: Data, value: A) -> A: value

law generic_template_identity:
  for -A: Data
  for value: A
  {identityTemplate(~A, value) == value : A}

def generic_template_identity(A, value): {==}
