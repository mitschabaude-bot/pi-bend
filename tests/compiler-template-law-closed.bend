import Base

def identityTemplate(~A: Data, value: A) -> A: value

law closed_template_identity:
  for value: Nat
  {identityTemplate(~Nat, value) == value : Nat}

def closed_template_identity(value): {==}
