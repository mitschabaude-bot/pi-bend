import Base

# Checker-only reproducer: no main and no execution of this IO program.
# Recursion is intentionally unsafe, as in callback server loops. This probes
# conversion checking, not a claim that the recursive program terminates.
@unsafe def repeat(unused: Unit) -> IO(Unit):
  do IO<Unit>:
    IO.print("tick")
    repeat(Unit{})

def wrapped(unused: Unit) -> IO(Unit): repeat(Unit{})

law same_program:
  {wrapped(Unit{}) == repeat(Unit{}) : IO(Unit)}

def same_program(): {==}
