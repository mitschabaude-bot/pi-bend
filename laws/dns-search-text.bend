import Base
import ../packages/runtime/src/dns-message.bend as Text
import ../packages/runtime/src/dns-message.bend as Presentation
import ../packages/runtime/src/dns-message.bend as Name

law dots_append:
  for +left: String
  for +right: String
  {Text.dots(left ++ right) == Nat.add(Text.dots(left), Text.dots(right)) : Nat}

law leading_dot_counted:
  for +text: String
  {Text.dots("." ++ text) == Succ{Text.dots(text)} : Nat}

law dots_empty:
  {Text.dots("") == 0n : Nat}

law invalid_input_is_terminal:
  for text: String
  for +error: Presentation.PresentationError
  {Text.parsedSearchText(text, Fail{error}) == Fail{error} : Result<&2, &2, Presentation.PresentationError, Text.Input>}

law prepared_fields_retained:
  for +text: String
  for +name: Name.Name
  for +absolute: Bool
  {Text.parsedSearchText(text, Done{Presentation.PresentationParsed{name, absolute}}) == Done{Text.Input{name, U32.from_nat(Text.dots(text)), absolute}} : Result<&2, &2, Presentation.PresentationError, Text.Input>}
